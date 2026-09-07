import XCTest
@testable import PineappleCore

final class ReviewEngineTests: XCTestCase {
    func testFirstCorrectSchedulesTenMinutes() {
        var data = Fixtures.snapshot(); Fixtures.answer(&data, correct: true)
        XCTAssertEqual(data.words[0].progress.nextReviewDate, Fixtures.now.addingTimeInterval(600))
        XCTAssertEqual(data.words[0].progress.masteryLevel, .recognised)
        XCTAssertEqual(data.words[0].progress.totalAnswers, 1)
    }
    func testEarlyCorrectDoesNotInflateIntervalOrPostponeDueDate() {
        var data = Fixtures.snapshot(); Fixtures.answer(&data, correct: true)
        for index in 1...12 { Fixtures.answer(&data, correct: true, at: Fixtures.now.addingTimeInterval(Double(index))) }
        XCTAssertEqual(data.words[0].progress.intervalSeconds, 600)
        XCTAssertEqual(data.words[0].progress.nextReviewDate, Fixtures.now.addingTimeInterval(600))
        XCTAssertEqual(data.words[0].progress.masteryLevel, .recognised)
    }
    func testDueStagesAndLongTermCap() throws {
        var data = Fixtures.snapshot()
        for expected in [600.0, 86400.0, 259200.0, 604800.0, 1209600.0, 2592000.0] {
            let date = data.words[0].progress.nextReviewDate ?? Fixtures.now
            Fixtures.answer(&data, correct: true, at: date)
            XCTAssertEqual(data.words[0].progress.intervalSeconds, expected)
        }
        for _ in 0..<20 {
            Fixtures.answer(&data, correct: true, at: try XCTUnwrap(data.words[0].progress.nextReviewDate))
        }
        XCTAssertEqual(data.words[0].progress.masteryLevel, .retained)
        XCTAssertLessThanOrEqual(data.words[0].progress.intervalSeconds, 180 * 86400)
        XCTAssertNoThrow(try data.validate())
    }
    func testWrongAnswerAddsMistakeAndShortensInterval() {
        var data = Fixtures.snapshot()
        data.words[0].progress.intervalSeconds = 30 * 86400
        Fixtures.answer(&data, correct: false)
        XCTAssertTrue(data.words[0].isInMistakes)
        XCTAssertEqual(data.words[0].progress.intervalSeconds, 600)
        Fixtures.answer(&data, correct: false, at: Fixtures.now.addingTimeInterval(10))
        XCTAssertEqual(data.words[0].progress.intervalSeconds, 60)
        XCTAssertEqual(data.words[0].progress.streakWrong, 2)
        XCTAssertEqual(data.words[0].progress.lastWrongDate, Fixtures.now.addingTimeInterval(10))
    }
    func testMistakeNeedsThreeCorrectAndDoesNotAffectFavorite() {
        var data = Fixtures.snapshot(); data.words[0].isFavorite = true
        Fixtures.answer(&data, correct: false)
        for index in 1...2 { Fixtures.answer(&data, correct: true, at: Fixtures.now.addingTimeInterval(Double(index))) }
        XCTAssertTrue(data.words[0].isInMistakes)
        Fixtures.answer(&data, correct: true, at: Fixtures.now.addingTimeInterval(3))
        XCTAssertFalse(data.words[0].isInMistakes)
        XCTAssertTrue(data.words[0].isFavorite)
    }
    func testDisabledAutomaticRemoval() {
        var data = Fixtures.snapshot(); data.settings.mistakeRemovalStreak = 0
        Fixtures.answer(&data, correct: false)
        for _ in 0..<10 { Fixtures.answer(&data, correct: true) }
        XCTAssertTrue(data.words[0].isInMistakes)
    }
    func testManualExclusionOverridesRepeatedErrors() {
        var data = Fixtures.snapshot(); data.words[0].confusingOverride = false; data.words[0].weakOverride = false
        for _ in 0..<5 { Fixtures.answer(&data, correct: false) }
        XCTAssertFalse(data.words[0].isConfusing(threshold: 3)); XCTAssertFalse(data.words[0].isWeak(at: Fixtures.now))
        data.words[0].confusingOverride = nil; data.words[0].weakOverride = nil
        XCTAssertTrue(data.words[0].isConfusing(threshold: 3)); XCTAssertTrue(data.words[0].isWeak(at: Fixtures.now))
    }
    func testUnseenWordsAreNotWeak() { XCTAssertFalse(ReviewEngine.isWeak(WordProgress(), at: Fixtures.now)) }
    func testLongRandomHistoryMaintainsInvariants() throws {
        var data = Fixtures.snapshot(), date = Fixtures.now
        for index in 0..<1000 {
            date = date.addingTimeInterval(Double((index % 20 + 1) * 600))
            Fixtures.answer(&data, correct: index % 7 != 0, at: date)
        }
        XCTAssertEqual(data.words[0].progress.totalAnswers, 1000)
        XCTAssertEqual(data.words[0].progress.recentOutcomes.count, 12)
        XCTAssertNoThrow(try data.validate())
    }
}
