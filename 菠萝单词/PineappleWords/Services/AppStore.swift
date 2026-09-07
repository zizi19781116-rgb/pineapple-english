import Foundation
import Combine
import PineappleCore

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var snapshot = AppSnapshot()
    @Published private(set) var ready = false
    @Published private(set) var epoch = UUID()
    @Published var errorMessage: String?
    @Published var recoveryMessage: String?
    @Published var backupWarning: String?
    @Published private(set) var restoring = false
    var unsavedNotes: [UUID: String] = [:]
    let speech = SpeechService()
    let ai = DeepSeekService()
    private(set) var coordinator: StoreCoordinator?
    private var repository: LocalRepository?
    private var clock = StudyClock()
    private var checkpointInProgress = false
    private var lastCheckpointDay: Date?
    private var checkpointTask: Task<Void, Never>?
    private let rootURLOverride: URL?
    private let journalWriter: (StudySlice, URL) throws -> Void

    init(rootURL: URL? = nil, journalWriter: @escaping (StudySlice, URL) throws -> Void = { try StudyTimeJournal.write($0, to: $1) }) {
        rootURLOverride = rootURL; self.journalWriter = journalWriter; openDatabase()
    }

    func openDatabase() {
        do {
            let root: URL?
            #if DEBUG
            root = rootURLOverride ?? (ProcessInfo.processInfo.arguments.contains("-ui-testing-empty")
                ? FileManager.default.temporaryDirectory.appendingPathComponent("UITests-\(UUID().uuidString)", isDirectory: true) : nil)
            #else
            root = rootURLOverride
            #endif
            let coordinator = try StoreCoordinator(root: root); self.coordinator = coordinator
            let (repository, snapshot) = try coordinator.open()
            self.repository = repository; self.snapshot = snapshot
            clock.timeout = TimeInterval(snapshot.settings.idleTimeoutSeconds)
            ready = true; recoveryMessage = nil
            _ = replayTimeJournal()
        } catch { recoveryMessage = "本地数据库暂时无法打开。原文件已保留，没有重建或清空。\n\n\(error.localizedDescription)" }
    }

    @discardableResult
    private func commit(_ change: (inout AppSnapshot) throws -> Void) -> Bool {
        guard !restoring else { errorMessage = "正在迁入数据，请等待恢复完成。"; return false }
        guard let repository, ready else { errorMessage = "数据库尚未就绪，请先恢复数据。"; return false }
        do {
            var next = snapshot; try change(&next)
            try repository.save(next, replacing: snapshot)
            snapshot = next
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func updateSettings(_ change: (inout UserSettings) -> Void) {
        let now = Date()
        guard flushTime(at: now) else { return }
        if commit({ value in
            change(&value.settings)
            guard value.settings.isValid else { throw AppError.invalidData("设置数值超出允许范围。") }
        }) { clock.timeout = TimeInterval(snapshot.settings.idleTimeoutSeconds) }
    }
    @discardableResult
    func editWord(_ id: UUID, change: (inout Vocabulary) -> Void) -> Bool {
        commit { value in
            guard let index = value.words.firstIndex(where: { $0.id == id }) else { throw AppError.invalidData("找不到这个词条。") }
            change(&value.words[index])
            guard !TextKey.normalize(value.words[index].word).isEmpty else { throw AppError.invalidData("单词不能为空。") }
        }
    }
    func saveNote(wordID: UUID, text: String) -> Bool {
        activity()
        return commit { value in
            guard value.word(wordID) != nil else { throw AppError.invalidData("该词条已不存在。") }
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let index = value.notes.firstIndex(where: { $0.wordID == wordID }) {
                if clean.isEmpty { value.notes.remove(at: index) }
                else { value.notes[index].text = clean; value.notes[index].updatedAt = Date() }
            } else if !clean.isEmpty { value.notes.append(WordNote(wordID: wordID, text: clean)) }
        }
    }
    func markMastered(_ id: UUID) {
        editWord(id) { word in
            word.isInMistakes = false
            word.progress.masteryLevel = .mastered
            word.progress.intervalSeconds = 7 * 86400
            word.progress.nextReviewDate = Date().addingTimeInterval(7 * 86400)
        }
    }

    func submit(_ question: StudyQuestion, answer: String, now: Date = Date()) -> AnswerEvent? {
        if let existing = snapshot.answers.first(where: { $0.id == question.id }) { return existing }
        guard let word = snapshot.word(question.wordID) else { errorMessage = "这个单词已不存在，请重新开始练习。"; return nil }
        let expected = question.kind == .choice ? word.details.coreMeaning : word.word
        guard TextKey.normalize(expected) == TextKey.normalize(question.correctAnswer) else {
            errorMessage = "题目答案与词条不一致，请重新生成题目。"; return nil
        }
        let event = AnswerEvent(question: question, answer: answer, date: now, isFirstLearning: word.progress.totalAnswers == 0)
        activity(at: now)
        guard commit({ value in
            guard let index = value.words.firstIndex(where: { $0.id == word.id }) else { throw AppError.invalidData("找不到词条。") }
            ReviewEngine.record(&value.words[index], correct: event.isCorrect, at: now, removalStreak: value.settings.mistakeRemovalStreak)
            value.answers.append(event); value.settings.lastWordID = word.id
        }) else { return nil }
        return event
    }
    @discardableResult
    func appendChat(_ entry: ChatEntry, expectedEpoch: UUID) -> Bool {
        guard expectedEpoch == epoch else { return false }
        return commit { value in
            guard entry.wordID.map({ value.word($0) != nil }) ?? true else { throw AppError.invalidData("问答所属单词已不存在。") }
            value.chats.append(entry)
        }
    }
    func activity(at now: Date = Date()) {
        guard ready else { return }
        let resumingAfterIdle = clock.lastInteraction.map { now.timeIntervalSince($0) >= clock.timeout } ?? false
        if clock.isPaused || (clock.pending(at: now).map { $0.duration >= 15 || resumingAfterIdle } ?? false) {
            guard flushTime(at: now) else { return }
        }
        clock.activity(at: max(now, snapshot.studySlices.last?.end ?? now))
    }
    @discardableResult
    func flushTime(at now: Date = Date()) -> Bool {
        guard ready, replayTimeJournal() else { return false }
        guard let slice = clock.pending(at: now) else { return true }
        do {
            guard let coordinator else { throw AppError.storage("无法访问计时保护目录。") }
            try journalWriter(slice, coordinator.timeJournalURL())
        } catch { errorMessage = "计时保护记录未保存：\(error.localizedDescription)"; return false }
        guard commit({ $0.studySlices.append(slice) }) else { return false }
        clock.acknowledge(slice)
        if let url = try? coordinator?.timeJournalURL() { StudyTimeJournal.clear(url) }
        return true
    }
    private func replayTimeJournal() -> Bool {
        do {
            guard let coordinator else { return false }
            let url = try coordinator.timeJournalURL()
            guard let slice = try StudyTimeJournal.read(url) else { return true }
            if !snapshot.studySlices.contains(where: { $0.id == slice.id }) {
                guard commit({ value in
                    guard value.studySlices.allSatisfy({ $0.end <= slice.start || $0.start >= slice.end }) else {
                        throw AppError.invalidData("计时保护记录与已保存时间重叠，原文件已保留。")
                    }
                    value.studySlices.append(slice)
                }) else { return false }
            }
            clock.acknowledge(slice); StudyTimeJournal.clear(url)
            return true
        } catch { errorMessage = "计时保护记录暂时无法恢复：\(error.localizedDescription)"; return false }
    }
    func leaveLearning() {
        let now = Date()
        clock.pause(at: now)
        _ = flushTime(at: now)
        speech.stop()
    }
    func foreground(_ active: Bool, at now: Date = Date()) {
        clock.setForeground(active, at: now)
        if !active { _ = flushTime(at: now); speech.stop() }
    }
    func play(_ text: String) {
        activity(); speech.speak(text, gender: snapshot.settings.voiceGender)
        if let message = speech.errorMessage { errorMessage = message; speech.errorMessage = nil }
    }

    func importBook(_ preview: ImportPreview) -> Bool {
        do {
            guard preview.canImport else { throw AppError.emptyBook }
            let draft = ImportValidator.preview(preview.draft)
            let fingerprint = try Self.fingerprint(draft.draft)
            guard !snapshot.books.contains(where: { $0.importFingerprint == fingerprint }) else {
                throw AppError.invalidData("这份词书已经导入过，不会重复写入。可修改内容后作为新词书导入。")
            }
            let (book, chapters, words) = try ImportValidator.materialize(draft, fingerprint: fingerprint)
            return commit { value in
                value.books.append(book); value.chapters += chapters; value.words += words
                if value.settings.mainBookID == nil { value.settings.mainBookID = book.id }
                try value.validate()
            }
        } catch { errorMessage = error.localizedDescription; return false }
    }
    static func fingerprint(_ source: BookDraft) throws -> String {
        var draft = source
        draft.name = TextKey.normalize(draft.name); draft.source = nil; draft.description = nil
        draft.chapters.sort { $0.lessonNumber < $1.lessonNumber }
        for index in draft.chapters.indices {
            draft.chapters[index].words.sort { TextKey.normalize($0.word) < TextKey.normalize($1.word) }
        }
        return BackupService.digest(try JSONCoding.encoder().encode(draft))
    }

    func makeExport() async throws -> Data {
        for (wordID, text) in unsavedNotes {
            guard saveNote(wordID: wordID, text: text) else { throw AppError.storage("有笔记尚未保存，请先重试保存笔记。") }
        }
        unsavedNotes.removeAll()
        guard flushTime() else { throw AppError.storage("学习计时还未保存，请先重试。") }
        let value = snapshot
        return try await Task.detached(priority: .userInitiated) {
            let data = try BackupService.encode(value); _ = try BackupService.decode(data); return data
        }.value
    }
    func restore(_ preview: BackupPreview) async throws {
        guard let coordinator else { throw AppError.storage("无法访问应用数据目录。") }
        guard !restoring else { throw AppError.storage("另一项恢复正在进行中。") }
        if ready {
            for (wordID, text) in unsavedNotes {
                guard saveNote(wordID: wordID, text: text) else { throw AppError.storage("有笔记尚未保存，暂不迁入。") }
            }
            unsavedNotes.removeAll()
            guard flushTime() else { throw AppError.storage("当前学习数据还未保存，暂不切换数据库。") }
        }
        clock.stop(); restoring = true
        defer { restoring = false }
        if ready {
            let original = snapshot
            let url = coordinator.recoveryDirectory.appendingPathComponent(BackupService.fileName(prefix: "迁入前自动保护"))
            try await Task.detached(priority: .userInitiated) { try BackupService.writeVerified(original, to: url) }.value
        }
        try Task.checkCancellation()
        let (repository, restored) = try coordinator.activate(preview.snapshot)
        self.repository = repository; snapshot = restored; epoch = UUID()
        clock = StudyClock(timeout: TimeInterval(restored.settings.idleTimeoutSeconds))
        ready = true; recoveryMessage = nil; lastCheckpointDay = nil
    }
    func checkpointIfNeeded() {
        guard ready, !checkpointInProgress, let coordinator, !snapshot.words.isEmpty || !snapshot.studySlices.isEmpty else { return }
        let today = Calendar.current.startOfDay(for: Date())
        guard lastCheckpointDay != today else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        let dayName = formatter.string(from: today)
        let url = coordinator.recoveryDirectory.appendingPathComponent("自动保护_\(dayName).zip")
        if FileManager.default.fileExists(atPath: url.path) { lastCheckpointDay = today; return }
        checkpointInProgress = true
        let value = snapshot
        checkpointTask = Task {
            defer { checkpointInProgress = false }
            do {
                try await Task.detached(priority: .utility) { try BackupService.writeVerified(value, to: url) }.value
                lastCheckpointDay = today; backupWarning = nil
            } catch { backupWarning = "自动保护副本未生成：\(error.localizedDescription) 请检查剩余空间并手动迁出备份。" }
        }
    }
}
