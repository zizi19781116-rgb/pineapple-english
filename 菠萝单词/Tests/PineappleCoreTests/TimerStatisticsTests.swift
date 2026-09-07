import XCTest
@testable import PineappleCore

final class TimerStatisticsTests: XCTestCase {
    func testOpeningAloneDoesNotCount() {
        let clock = StudyClock()
        XCTAssertNil(clock.pending(at: Fixtures.now)); XCTAssertFalse(clock.isCounting(at: Fixtures.now))
    }
    func testIdleCapAndResumeDoNotCountGap() throws {
        var clock = StudyClock(timeout: 180)
        clock.activity(at: Fixtures.now)
        let first = try XCTUnwrap(clock.pending(at: Fixtures.now.addingTimeInterval(1000)))
        XCTAssertEqual(first.duration, 180)
        clock.acknowledge(first)
        XCTAssertNil(clock.pending(at: Fixtures.now.addingTimeInterval(1100)))
        clock.activity(at: Fixtures.now.addingTimeInterval(1100))
        let resumed = try XCTUnwrap(clock.pending(at: Fixtures.now.addingTimeInterval(1120)))
        XCTAssertEqual(resumed.duration, 20)
    }
    func testCheckpointAcknowledgementPreventsDoubleCounting() throws {
        var clock = StudyClock(); clock.activity(at: Fixtures.now)
        let slice = try XCTUnwrap(clock.pending(at: Fixtures.now.addingTimeInterval(15)))
        clock.acknowledge(slice); clock.acknowledge(slice)
        XCTAssertNil(clock.pending(at: Fixtures.now.addingTimeInterval(15)))
        XCTAssertEqual(clock.pending(at: Fixtures.now.addingTimeInterval(30))?.duration, 15)
    }
    func testPendingRemainsUntilSaveAcknowledged() throws {
        var clock = StudyClock(); clock.activity(at: Fixtures.now)
        XCTAssertEqual(clock.pending(at: Fixtures.now.addingTimeInterval(15))?.duration, 15)
        XCTAssertEqual(clock.pending(at: Fixtures.now.addingTimeInterval(30))?.duration, 30)
    }
    func testBackgroundFreezesPendingUntilSavedAndDoesNotCountGap() throws {
        var clock = StudyClock(); clock.activity(at: Fixtures.now)
        clock.setForeground(false, at: Fixtures.now.addingTimeInterval(10))
        let frozen = try XCTUnwrap(clock.pending(at: Fixtures.now.addingTimeInterval(1000)))
        XCTAssertEqual(frozen.duration, 10)
        XCTAssertFalse(clock.isCounting(at: Fixtures.now.addingTimeInterval(1000)))
        clock.acknowledge(frozen)
        XCTAssertNil(clock.pending(at: Fixtures.now.addingTimeInterval(1000)))
        clock.setForeground(true, at: Fixtures.now.addingTimeInterval(1200))
        XCTAssertNil(clock.pending(at: Fixtures.now.addingTimeInterval(1200)))
        clock.activity(at: Fixtures.now.addingTimeInterval(1300))
        let resumed = try XCTUnwrap(clock.pending(at: Fixtures.now.addingTimeInterval(1310)))
        XCTAssertEqual(resumed.duration, 10)
        clock.acknowledge(resumed); clock.stop()
        XCTAssertNil(clock.pending(at: Fixtures.now.addingTimeInterval(1350)))
    }
    func testRepeatedScreenPauseCannotExtendFrozenTime() {
        var clock = StudyClock(); clock.activity(at: Fixtures.now)
        clock.pause(at: Fixtures.now.addingTimeInterval(10))
        clock.pause(at: Fixtures.now.addingTimeInterval(100))
        XCTAssertEqual(clock.pending(at: Fixtures.now.addingTimeInterval(200))?.duration, 10)
        XCTAssertFalse(clock.isCounting(at: Fixtures.now.addingTimeInterval(200)))
    }
    func testFrozenTailSurvivesWallClockRollback() {
        var clock = StudyClock(); clock.activity(at: Fixtures.now)
        clock.pause(at: Fixtures.now.addingTimeInterval(10))
        XCTAssertEqual(clock.pending(at: Fixtures.now.addingTimeInterval(-100))?.duration, 10)
    }
    func testChangingIdleTimeoutCannotExtendAlreadyFrozenTime() throws {
        var clock = StudyClock(timeout: 180); clock.activity(at: Fixtures.now)
        clock.pause(at: Fixtures.now.addingTimeInterval(1000))
        clock.timeout = 600
        let slice = try XCTUnwrap(clock.pending(at: Fixtures.now.addingTimeInterval(1000)))
        XCTAssertEqual(slice.duration, 180)
        clock.acknowledge(slice)
        XCTAssertNil(clock.pending(at: Fixtures.now.addingTimeInterval(2000)))
    }
    func testBackwardClockNeverCreatesNegativeDuration() {
        var clock = StudyClock(); clock.activity(at: Fixtures.now)
        XCTAssertNil(clock.pending(at: Fixtures.now.addingTimeInterval(-100)))
    }
    func testCrossYearTimeIsSplitPrecisely() throws {
        var data = Fixtures.snapshot(), calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let boundary = try XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)))
        data.studySlices = [StudySlice(start: boundary.addingTimeInterval(-10), end: boundary.addingTimeInterval(10))]
        XCTAssertEqual(StatisticsService.calculate(data, period: .year, anchor: boundary.addingTimeInterval(-1), calendar: calendar).seconds, 10)
        XCTAssertEqual(StatisticsService.calculate(data, period: .year, anchor: boundary, calendar: calendar).seconds, 10)
        XCTAssertEqual(StatisticsService.calculate(data, period: .all, calendar: calendar).seconds, 20)
        XCTAssertEqual(StatisticsService.annual(data, calendar: calendar).map(\.year), [2027, 2026])
    }
    func testNewAndReviewCountsDeduplicateWordsButAnswersRemain() {
        var data = Fixtures.snapshot()
        Fixtures.answer(&data, correct: false)
        Fixtures.answer(&data, correct: true, at: Fixtures.now.addingTimeInterval(30))
        Fixtures.answer(&data, correct: true, at: Fixtures.now.addingTimeInterval(60))
        let result = StatisticsService.calculate(data, period: .all)
        XCTAssertEqual(result.newWords, 1); XCTAssertEqual(result.reviewedWords, 1)
        XCTAssertEqual(result.answerCount, 3); XCTAssertEqual(result.wrongCount, 1)
        XCTAssertEqual(result.accuracy ?? 0, 2.0 / 3.0, accuracy: 0.00001)
    }
    func testNoAnswersHasNoArtificialAccuracy() { XCTAssertNil(StatisticsService.calculate(AppSnapshot(), period: .all).accuracy) }
    func testStreakCanEndYesterdayAndBreaksOnMissedDay() throws {
        var data = Fixtures.snapshot(), calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let today = calendar.startOfDay(for: Fixtures.now)
        for offset in [-1, -2, -3] {
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: today))
            data.studySlices.append(StudySlice(start: date, end: date.addingTimeInterval(60)))
        }
        XCTAssertEqual(StatisticsService.streak(data, now: today, calendar: calendar), 3)
        XCTAssertEqual(StatisticsService.streak(data, now: today.addingTimeInterval(2 * 86400), calendar: calendar), 0)
    }
    func testAnnualDataNotPrunedAcrossTenYears() throws {
        var data = Fixtures.snapshot(), calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        for year in 2026...2035 {
            let date = try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: 1, day: 1)))
            data.studySlices.append(StudySlice(start: date, end: date.addingTimeInterval(60)))
        }
        XCTAssertEqual(StatisticsService.annual(data, calendar: calendar).count, 10)
        XCTAssertEqual(StatisticsService.calculate(data, period: .all).seconds, 600)
    }
}
