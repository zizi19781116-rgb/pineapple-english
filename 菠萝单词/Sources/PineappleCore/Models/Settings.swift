import Foundation

public enum AIMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto, fast, deep
    public var id: String { rawValue }
    public var title: String { switch self { case .auto: return "自动"; case .fast: return "快速"; case .deep: return "深度" } }
}
public enum VoiceGender: String, Codable, CaseIterable, Identifiable, Sendable {
    case female, male
    public var id: String { rawValue }
    public var title: String { self == .female ? "英式女声" : "英式男声" }
}
public enum CardModule: String, Codable, CaseIterable, Identifiable, Sendable {
    case ipa, chinese, english, partOfSpeech, examples, phrases, derivatives, roots, synonyms, antonyms, inflections, collins, ai, notes
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .ipa: return "英式音标"; case .chinese: return "中文释义"; case .english: return "英文释义"
        case .partOfSpeech: return "词性"; case .examples: return "例句"; case .phrases: return "词组"
        case .derivatives: return "派生词"; case .roots: return "词根词缀"; case .synonyms: return "近义词"
        case .antonyms: return "反义词"; case .inflections: return "词形变化"; case .collins: return "Collins"
        case .ai: return "AI 解析"; case .notes: return "笔记"
        }
    }
}

public struct UserSettings: Codable, Equatable, Sendable {
    public var aiMode: AIMode = .auto
    public var fastModel: String = "deepseek-v4-flash"
    public var deepModel: String = "deepseek-v4-pro"
    public var voiceGender: VoiceGender = .female
    public var hardMode: Bool = false
    public var cardModules: Set<CardModule> = [.ipa, .chinese, .partOfSpeech, .examples, .phrases, .notes, .ai]
    public var mistakeRemovalStreak: Int = 3
    public var confusingWrongThreshold: Int = 3
    public var idleTimeoutSeconds: Int = 180
    public var collinsEnabled: Bool = false
    public var mainBookID: UUID?
    public var lastWordID: UUID?
    public var dailyNewGoal: Int = 20
    public init() {}

    enum CodingKeys: String, CodingKey {
        case aiMode, fastModel, deepModel, voiceGender, hardMode, cardModules, mistakeRemovalStreak,
             confusingWrongThreshold, idleTimeoutSeconds, collinsEnabled, mainBookID, lastWordID, dailyNewGoal
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        aiMode = try c.decodeIfPresent(AIMode.self, forKey: .aiMode) ?? aiMode
        fastModel = try c.decodeIfPresent(String.self, forKey: .fastModel) ?? fastModel
        deepModel = try c.decodeIfPresent(String.self, forKey: .deepModel) ?? deepModel
        voiceGender = try c.decodeIfPresent(VoiceGender.self, forKey: .voiceGender) ?? voiceGender
        hardMode = try c.decodeIfPresent(Bool.self, forKey: .hardMode) ?? hardMode
        cardModules = try c.decodeIfPresent(Set<CardModule>.self, forKey: .cardModules) ?? cardModules
        mistakeRemovalStreak = try c.decodeIfPresent(Int.self, forKey: .mistakeRemovalStreak) ?? mistakeRemovalStreak
        confusingWrongThreshold = try c.decodeIfPresent(Int.self, forKey: .confusingWrongThreshold) ?? confusingWrongThreshold
        idleTimeoutSeconds = try c.decodeIfPresent(Int.self, forKey: .idleTimeoutSeconds) ?? idleTimeoutSeconds
        collinsEnabled = try c.decodeIfPresent(Bool.self, forKey: .collinsEnabled) ?? collinsEnabled
        mainBookID = try c.decodeIfPresent(UUID.self, forKey: .mainBookID)
        lastWordID = try c.decodeIfPresent(UUID.self, forKey: .lastWordID)
        dailyNewGoal = try c.decodeIfPresent(Int.self, forKey: .dailyNewGoal) ?? dailyNewGoal
    }
    public var isValid: Bool {
        (0...20).contains(mistakeRemovalStreak) && (1...100).contains(confusingWrongThreshold)
            && (30...600).contains(idleTimeoutSeconds) && (1...200).contains(dailyNewGoal)
            && !fastModel.trimmingCharacters(in: .whitespaces).isEmpty && !deepModel.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
