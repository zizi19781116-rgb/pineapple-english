import Foundation

/// The caller persists pending slices before acknowledging them. Idle/open time is never a session.
public struct StudyClock: Sendable {
    public private(set) var cursor: Date?
    public private(set) var lastInteraction: Date?
    public private(set) var pausedAt: Date?
    public private(set) var isForeground = true
    public var isPaused: Bool { pausedAt != nil }
    public var timeout: TimeInterval
    public init(timeout: TimeInterval = 180) { self.timeout = timeout }

    public func pending(at now: Date) -> StudySlice? {
        guard isForeground || isPaused, let cursor, let lastInteraction else { return nil }
        let end = min(pausedAt ?? min(now, lastInteraction.addingTimeInterval(timeout)), cursor.addingTimeInterval(600))
        guard end > cursor else { return nil }
        return StudySlice(start: cursor, end: end)
    }
    public mutating func acknowledge(_ slice: StudySlice) {
        if cursor == slice.start { cursor = slice.end }
    }
    /// Flush pending time before calling activity, including when resuming after an idle period.
    public mutating func activity(at now: Date) {
        guard isForeground else { return }
        if cursor == nil || isPaused || lastInteraction.map({ now.timeIntervalSince($0) >= timeout }) == true { cursor = now }
        pausedAt = nil
        lastInteraction = now
    }
    /// Freeze before attempting a save; failed writes retain the same cutoff for later retry.
    public mutating func pause(at now: Date = Date()) {
        if pausedAt == nil { pausedAt = min(now, lastInteraction.map { $0.addingTimeInterval(timeout) } ?? now) }
    }
    /// Use only after pending time was saved, or when intentionally replacing the entire clock.
    public mutating func stop() { cursor = nil; lastInteraction = nil; pausedAt = nil }
    public mutating func setForeground(_ active: Bool, at now: Date = Date()) {
        if !active { pause(at: now) }
        isForeground = active
    }
    public func isCounting(at now: Date) -> Bool {
        isForeground && !isPaused && (lastInteraction.map { now >= $0 && now.timeIntervalSince($0) < timeout } ?? false)
    }
}
