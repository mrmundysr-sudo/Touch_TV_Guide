import Foundation

/// A reminder for one program. `programKey` matches `Program.key`.
public struct Reminder: Codable, Hashable, Identifiable, Sendable {
    public var programKey: String
    public var channelId: String
    public var channelName: String
    public var title: String
    public var startMillis: Int64
    public var stopMillis: Int64
    public var id: String { programKey }
    public var start: Date { Date(timeIntervalSince1970: TimeInterval(startMillis) / 1000) }
    public init(programKey: String, channelId: String, channelName: String, title: String, startMillis: Int64, stopMillis: Int64) {
        self.programKey = programKey; self.channelId = channelId; self.channelName = channelName
        self.title = title; self.startMillis = startMillis; self.stopMillis = stopMillis
    }
}

public enum ReminderLogic {
    public static let defaultLeadMinutes = 5
    public static let leadChoices = [5, 10, 15, 30]
    /// iOS keeps at most 64 pending local notifications per app.
    public static let platformPendingLimit = 64

    public static func fireAt(_ r: Reminder, leadMinutes: Int) -> Int64 { r.startMillis - Int64(leadMinutes) * 60_000 }
    public static func canRemind(_ p: Program, now: Int64) -> Bool { p.startMillis > now }

    public static func from(_ p: Program, channelName: String) -> Reminder {
        Reminder(programKey: p.key, channelId: p.channelId, channelName: channelName, title: p.title, startMillis: p.startMillis, stopMillis: p.stopMillis)
    }

    public struct Reconciled: Equatable, Sendable {
        public var keep: [Reminder]
        public var updated: [Reminder]
        public var dropped: [Reminder]
    }

    /// After a refresh: reminders whose program vanished are dropped; ones whose program moved (same channel and title,
    /// within 6 h) are updated; ended ones are dropped.
    public static func reconcile(_ reminders: [Reminder], programs: [Program], now: Int64) -> Reconciled {
        var byKey: [String: Program] = [:]
        for p in programs { byKey[p.key] = p }
        var out = Reconciled(keep: [], updated: [], dropped: [])
        for r in reminders {
            if r.startMillis <= now { out.dropped.append(r); continue }
            if let exact = byKey[r.programKey], exact.title == r.title {
                if exact.stopMillis != r.stopMillis { var u = r; u.stopMillis = exact.stopMillis; out.updated.append(u) } else { out.keep.append(r) }
                continue
            }
            let moved = programs.first { $0.channelId == r.channelId && $0.title == r.title && $0.startMillis > now && abs($0.startMillis - r.startMillis) <= 6 * 3_600_000 }
            if let m = moved {
                var u = r; u.programKey = m.key; u.startMillis = m.startMillis; u.stopMillis = m.stopMillis; out.updated.append(u)
            } else { out.dropped.append(r) }
        }
        return out
    }

    /// The reminders to actually hand to the OS: soonest first, capped at the platform limit.
    public static func nextToSchedule(_ reminders: [Reminder], leadMinutes: Int, now: Int64) -> [(Reminder, Int64)] {
        reminders.filter { $0.startMillis > now }
            .map { ($0, max(fireAt($0, leadMinutes: leadMinutes), now + 1_000)) }
            .sorted { $0.1 < $1.1 }
            .prefix(platformPendingLimit).map { $0 }
    }
}

/// Feed refresh rule: the feed is fetched at most once every 24 hours, however the refresh is triggered.
public enum FeedPolicy {
    public static let minIntervalMillis: Int64 = 24 * 3_600_000
    /// `force` is only for "nothing cached yet" or "the user changed the feed address".
    public static func shouldRefresh(lastFetchMillis: Int64, now: Int64, force: Bool = false) -> Bool {
        force || lastFetchMillis <= 0 || now < lastFetchMillis || now - lastFetchMillis >= minIntervalMillis
    }
    public static func nextAllowed(lastFetchMillis: Int64) -> Int64 { lastFetchMillis <= 0 ? 0 : lastFetchMillis + minIntervalMillis }
}
