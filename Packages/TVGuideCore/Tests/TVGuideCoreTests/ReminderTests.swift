import XCTest
@testable import TVGuideCore

final class ReminderTests: XCTestCase {
    let now: Int64 = 1_000_000
    func prog(_ ch: String, _ start: Int64, _ title: String = "Show") -> Program {
        Program(channelId: ch, title: title, description: nil, startMillis: start, stopMillis: start + 3_600_000)
    }

    func testFireTimeAndEligibility() {
        let p = prog("a", now + 600_000)
        let r = ReminderLogic.from(p, channelName: "ABC")
        XCTAssertEqual(ReminderLogic.fireAt(r, leadMinutes: 5), p.startMillis - 300_000)
        XCTAssertTrue(ReminderLogic.canRemind(p, now: now)); XCTAssertFalse(ReminderLogic.canRemind(prog("a", now - 1), now: now))
    }

    func testReconcile() {
        let same = prog("a", now + 1_000_000), gone = prog("a", now + 5_000_000, "Gone")
        let moved = prog("b", now + 7_000_000, "Moved"), past = prog("a", now - 10, "Past")
        let rs = [same, gone, moved, past].map { ReminderLogic.from($0, channelName: "X") }
        let feed = [same, prog("b", now + 7_900_000, "Moved"), prog("a", now + 9_000_000, "Other")]
        let out = ReminderLogic.reconcile(rs, programs: feed, now: now)
        XCTAssertEqual(out.keep.map(\.programKey), [same.key])
        XCTAssertEqual(out.updated.map(\.programKey), ["b|\(now + 7_900_000)"])
        XCTAssertEqual(Set(out.dropped.map(\.title)), ["Gone", "Past"])
    }

    func testPlatformLimitKeepsSoonest() {
        let rs = (0..<80).map { ReminderLogic.from(prog("a", now + Int64($0 + 1) * 1_000_000, "S\($0)"), channelName: "X") }
        let items = ReminderLogic.nextToSchedule(rs.reversed(), leadMinutes: 5, now: now)
        XCTAssertEqual(items.count, 64); XCTAssertEqual(items.first?.0.title, "S0"); XCTAssertEqual(items.last?.0.title, "S63")
        XCTAssertTrue(items.allSatisfy { $0.1 > now })
    }

    func testRefreshPolicyIsDailyAtMost() {
        let h: Int64 = 3_600_000
        XCTAssertTrue(FeedPolicy.shouldRefresh(lastFetchMillis: 0, now: now))
        XCTAssertFalse(FeedPolicy.shouldRefresh(lastFetchMillis: now, now: now + 23 * h))
        XCTAssertTrue(FeedPolicy.shouldRefresh(lastFetchMillis: now, now: now + 24 * h))
        XCTAssertTrue(FeedPolicy.shouldRefresh(lastFetchMillis: now, now: now + 1, force: true))
        XCTAssertTrue(FeedPolicy.shouldRefresh(lastFetchMillis: now + 5, now: now))
        XCTAssertEqual(FeedPolicy.nextAllowed(lastFetchMillis: now), now + 24 * h)
    }
}
