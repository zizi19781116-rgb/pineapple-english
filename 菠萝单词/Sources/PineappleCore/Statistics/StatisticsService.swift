import Foundation

public enum StatisticsPeriod: String, CaseIterable, Identifiable {
    case day, week, month, year, all
    public var id: String { rawValue }
    public var title: String { switch self { case .day: return "日"; case .week: return "周"; case .month: return "月"; case .year: return "年"; case .all: return "全部" } }
    public var component: Calendar.Component? {
        switch self { case .day: return .day; case .week: return .weekOfYear; case .month: return .month; case .year: return .year; case .all: return nil }
    }
}
public struct StudyStatistics: Equatable {
    public var seconds: TimeInterval
    public var newWords: Int
    public var reviewedWords: Int
    public var answerCount: Int
    public var correctCount: Int
    public var wrongCount: Int { answerCount - correctCount }
    public var accuracy: Double? { answerCount == 0 ? nil : Double(correctCount) / Double(answerCount) }
}
public struct YearStatistics: Identifiable {
    public var year: Int
    public var seconds: TimeInterval
    public var id: Int { year }
}

public enum StatisticsService {
    public static func calculate(_ snapshot: AppSnapshot, period: StatisticsPeriod, anchor: Date = Date(),
                                 calendar: Calendar = .current) -> StudyStatistics {
        let interval = period.component.flatMap { calendar.dateInterval(of: $0, for: anchor) }
        let events = snapshot.answers.filter { event in
            guard let interval else { return true }
            return event.date >= interval.start && event.date < interval.end
        }
        let seconds = snapshot.studySlices.reduce(0.0) { total, slice in
            guard let interval else { return total + slice.duration }
            return total + max(0, min(slice.end, interval.end).timeIntervalSince(max(slice.start, interval.start)))
        }
        return StudyStatistics(seconds: seconds, newWords: Set(events.filter(\.isFirstLearning).map(\.wordID)).count,
                               reviewedWords: Set(events.filter { !$0.isFirstLearning }.map(\.wordID)).count,
                               answerCount: events.count, correctCount: events.filter(\.isCorrect).count)
    }
    public static func annual(_ snapshot: AppSnapshot, calendar: Calendar = .current) -> [YearStatistics] {
        let dates = snapshot.studySlices.flatMap { [$0.start, $0.end.addingTimeInterval(-0.001)] } + snapshot.answers.map(\.date)
        let years = Set(dates.map { calendar.component(.year, from: $0) }).sorted(by: >)
        return years.compactMap { year in
            guard let anchor = calendar.date(from: DateComponents(year: year, month: 6, day: 1)) else { return nil }
            return YearStatistics(year: year, seconds: calculate(snapshot, period: .year, anchor: anchor, calendar: calendar).seconds)
        }
    }
    public static func streak(_ snapshot: AppSnapshot, now: Date = Date(), calendar: Calendar = .current) -> Int {
        var days = Set(snapshot.answers.map { calendar.startOfDay(for: $0.date) })
        for slice in snapshot.studySlices where slice.duration > 0 {
            days.insert(calendar.startOfDay(for: slice.start))
            days.insert(calendar.startOfDay(for: slice.end.addingTimeInterval(-0.001)))
        }
        var date = calendar.startOfDay(for: now)
        if !days.contains(date) { date = calendar.date(byAdding: .day, value: -1, to: date) ?? date }
        var count = 0
        while days.contains(date) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date), previous < date else { break }
            date = previous
        }
        return count
    }
    public static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分钟" : "\(minutes) 分钟"
    }
}
