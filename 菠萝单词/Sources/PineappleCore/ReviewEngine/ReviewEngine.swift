import Foundation

public enum ReviewEngine {
    public static func record(_ word: inout Vocabulary, correct: Bool, at now: Date,
                              removalStreak: Int) {
        var p = word.progress
        let first = p.totalAnswers == 0
        let due = p.nextReviewDate.map { now >= $0 } ?? true
        p.firstLearnedDate = p.firstLearnedDate ?? now
        p.lastAnswerDate = now; p.lastReviewDate = now
        p.recentOutcomes.append(correct)
        p.recentOutcomes = Array(p.recentOutcomes.suffix(12))
        if correct {
            p.correctCount += 1; p.streakCorrect += 1; p.streakWrong = 0
            // Early re-practice counts as practice but cannot inflate the spacing stage.
            if first || due {
                let previous = p.intervalSeconds
                if previous < 600 { p.intervalSeconds = 600 }
                else if previous < 86400 { p.intervalSeconds = 86400 }
                else if previous < 3 * 86400 { p.intervalSeconds = 3 * 86400 }
                else if previous < 7 * 86400 { p.intervalSeconds = 7 * 86400 }
                else if previous < 14 * 86400 { p.intervalSeconds = 14 * 86400 }
                else if previous < 30 * 86400 { p.intervalSeconds = 30 * 86400 }
                else {
                    let late = min(0.35, max(0, now.timeIntervalSince(p.nextReviewDate ?? now)) / max(previous, 1) * 0.1)
                    p.intervalSeconds = min(180 * 86400, previous * (p.ease + late))
                }
                p.ease = min(2.8, p.ease + 0.04)
                p.nextReviewDate = now.addingTimeInterval(p.intervalSeconds)
            }
            if removalStreak > 0 && p.streakCorrect >= removalStreak { word.isInMistakes = false }
        } else {
            p.wrongCount += 1; p.streakWrong += 1; p.streakCorrect = 0
            p.lastWrongDate = now; p.ease = max(1.3, p.ease - 0.2)
            p.intervalSeconds = p.streakWrong > 1 ? 60 : 600
            p.nextReviewDate = now.addingTimeInterval(p.intervalSeconds)
            word.isInMistakes = true
        }
        if !correct { p.masteryLevel = .unfamiliar }
        else if p.intervalSeconds >= 30 * 86400 { p.masteryLevel = .retained }
        else if p.intervalSeconds >= 7 * 86400 { p.masteryLevel = .mastered }
        else if p.intervalSeconds >= 86400 { p.masteryLevel = .familiar }
        else { p.masteryLevel = .recognised }
        word.progress = p
    }

    public static func isWeak(_ p: WordProgress, at now: Date) -> Bool {
        guard p.totalAnswers > 0 else { return false }
        let recentErrors = p.recentOutcomes.filter { !$0 }.count
        let unstable = p.totalAnswers >= 3 && p.accuracy < 0.8
        let recentFailure = p.lastWrongDate.map { now.timeIntervalSince($0) < 7 * 86400 } ?? false
        let overdue = p.nextReviewDate.map { now.timeIntervalSince($0) > max(86400, p.intervalSeconds * 0.5) } ?? false
        return p.streakWrong > 0 || (unstable && p.streakCorrect < 3)
            || (recentErrors >= 2 && recentFailure && p.streakCorrect < 3)
            || (overdue && p.masteryLevel.rawValue < MasteryLevel.retained.rawValue)
    }
}
