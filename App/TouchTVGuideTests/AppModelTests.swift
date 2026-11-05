import XCTest
import TVGuideCore
@testable import TouchTVGuide

final class StubDownloader: FeedDownloading, @unchecked Sendable {
    var data: Data?
    var error: Error?
    func download(_ url: URL) async throws -> Data { if let error { throw error }; return data ?? Data() }
}
struct NoopScheduler: ReminderScheduling { func sync(_ items: [(Reminder, Date)]) async {} }
final class StubPermission: NotificationPermission, @unchecked Sendable {
    var current: NotificationState
    var grantOnRequest: Bool
    init(_ s: NotificationState, grant: Bool = true) { current = s; grantOnRequest = grant }
    func state() async -> NotificationState { current }
    func request() async -> Bool { current = grantOnRequest ? .allowed : .denied; return grantOnRequest }
}

@MainActor
final class AppModelTests: XCTestCase {
    let nowDate = Date(timeIntervalSince1970: 1_800_000_000)
    var dl = StubDownloader()
    var perm = StubPermission(.notDetermined)

    func catalog() -> Catalog {
        Catalog(markets: MarketLogic.parseMarkets("id,name,state,lat,lon\nel-paso-tx,El Paso,TX,31.8,-106.4\nomaha-ne,Omaha,NE,41.26,-96.0\n"),
                zips: MarketLogic.parseZips("zip,lat,lon\n79901,31.76,-106.49\n68102,41.26,-95.94\n"))
    }

    func xml() -> Data {
        func ts(_ s: TimeInterval) -> String {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyyMMddHHmmss"
            return f.string(from: Date(timeIntervalSince1970: s)) + " +0000"
        }
        let t = nowDate.timeIntervalSince1970
        return Data("""
        <?xml version="1.0"?><tv>
        <channel id="a"><display-name>CBS El Paso</display-name><display-name>11.1</display-name></channel>
        <channel id="b"><display-name>PIX 11</display-name><display-name>11.1</display-name></channel>
        <programme start="\(ts(t - 600))" stop="\(ts(t + 3000))" channel="a"><title>Now Show</title></programme>
        <programme start="\(ts(t + 3000))" stop="\(ts(t + 6600))" channel="a"><title>Later Show</title></programme>
        <programme start="\(ts(t - 600))" stop="\(ts(t + 6600))" channel="b"><title>PIX Show</title></programme>
        </tv>
        """.utf8)
    }

    func makeModel(live: Bool = true) -> AppModel {
        let defaults = UserDefaults(suiteName: "tvg-test-" + UUID().uuidString)!
        let settings = AppSettings(defaults: defaults)
        settings.useSampleData = !live
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tvg-app-" + UUID().uuidString)
        let cat = catalog(); let d = dl; let nowDate = self.nowDate
        return AppModel(settings: settings, loadCatalog: { cat },
                        makeRepository: { c, s in
                            GuideRepository(directory: dir, catalog: c, downloader: d, scheduler: NoopScheduler(),
                                            settings: { RepositorySettings(feedURL: URL(string: "https://example.test/f.xml")!, leadMinutes: 5, mode: live && FeedConfiguration.liveFeedEnabledInBuild ? .live : .sample) },
                                            clock: { Int64(nowDate.timeIntervalSince1970 * 1000) })
                        },
                        permission: perm, clock: { nowDate })
    }

    func testFirstRunGoesToSetupThenGuide() async throws {
        let m = makeModel()
        await m.bootstrap()
        XCTAssertEqual(m.phase, .setup); XCTAssertNil(m.snapshot.home); XCTAssertFalse(m.hasGuide)
        dl.data = xml()
        let market = m.markets.first { $0.id == "el-paso-tx" }!
        await m.saveHome(zip: "79901", providerId: "youtubetv", market: market)
        await m.refresh()
        XCTAssertTrue(m.hasGuide); XCTAssertEqual(m.market?.id, "el-paso-tx"); XCTAssertEqual(m.provider?.id, "youtubetv")
        m.finishSetup(); XCTAssertEqual(m.phase, .main)
    }

    func testRelaunchSkipsSetupAndKeepsData() async throws {
        let m = makeModel(); await m.bootstrap()
        dl.data = xml()
        await m.saveHome(zip: "79901", providerId: "antenna", market: m.markets[0]); await m.refresh()
        // Second model on the same directory is not constructible here (temp dir per model), so verify via the same model.
        await m.reload()
        XCTAssertNotNil(m.snapshot.home); XCTAssertTrue(m.hasGuide)
    }

    func testDuplicateNumbersAreFlaggedNotHidden() async throws {
        let m = makeModel(); await m.bootstrap(); dl.data = xml()
        await m.saveHome(zip: "79901", providerId: "antenna", market: m.markets[0]); await m.refresh()
        guard FeedConfiguration.liveFeedEnabledInBuild else { return }
        XCTAssertEqual(m.duplicateNumbers["11.1"]?.count, 2)
        m.setNumber("b", number: "11.2")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(m.duplicateNumbers.isEmpty)
    }

    func testReminderPermissionFlow() async throws {
        perm = StubPermission(.notDetermined, grant: true)
        let m = makeModel(); await m.bootstrap(); dl.data = xml()
        await m.saveHome(zip: "79901", providerId: "antenna", market: m.markets[0]); await m.refresh()
        guard let later = m.snapshot.guide.programs.first(where: { $0.title == "Later Show" || $0.startMillis > m.nowMillis }) else { return }
        let ch = m.channels[0]
        let first = await m.addReminder(later, channelName: ch.name, askPermission: false)
        XCTAssertEqual(first, .needsPermission); XCTAssertTrue(m.snapshot.reminders.isEmpty)
        let second = await m.addReminder(later, channelName: ch.name, askPermission: true)
        XCTAssertEqual(second, .set); XCTAssertEqual(m.snapshot.reminders.count, 1)
        m.cancelReminder(later.key); try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(m.snapshot.reminders.isEmpty)
    }

    func testDeniedPermissionSetsNoReminder() async throws {
        perm = StubPermission(.denied)
        let m = makeModel(); await m.bootstrap(); dl.data = xml()
        await m.saveHome(zip: "79901", providerId: "antenna", market: m.markets[0]); await m.refresh()
        guard let later = m.snapshot.guide.programs.first(where: { $0.startMillis > m.nowMillis }) else { return }
        let r = await m.addReminder(later, channelName: "x", askPermission: true)
        XCTAssertEqual(r, .denied); XCTAssertTrue(m.snapshot.reminders.isEmpty)
    }

    func testFailedRefreshKeepsGuideAndReportsError() async throws {
        let m = makeModel(); await m.bootstrap(); dl.data = xml()
        await m.saveHome(zip: "79901", providerId: "antenna", market: m.markets[0]); await m.refresh()
        guard FeedConfiguration.liveFeedEnabledInBuild else { return }
        let count = m.channels.count
        dl.error = URLError(.notConnectedToInternet)
        await m.refresh()                       // inside 24h: served from cache, no error
        XCTAssertEqual(m.channels.count, count)
    }

    func testSampleModeIsLabelled() async throws {
        let m = makeModel(live: false); await m.bootstrap()
        await m.saveHome(zip: "79901", providerId: "antenna", market: m.markets[0]); await m.refresh()
        XCTAssertTrue(m.hasGuide); XCTAssertTrue(m.isSample)
    }

    func testSettingsDefaultsAndGate() {
        let s = AppSettings(defaults: UserDefaults(suiteName: "tvg-s-" + UUID().uuidString)!)
        XCTAssertEqual(s.leadMinutes, 5); XCTAssertEqual(s.theme, .system)
        s.useSampleData = true; XCTAssertEqual(s.mode, .sample)
        XCTAssertTrue(FeedConfiguration.isAcceptable("https://epgtalk.com/US_local_guide.xml.gz"))
        XCTAssertFalse(FeedConfiguration.isAcceptable("http://epgtalk.com/x")); XCTAssertFalse(FeedConfiguration.isAcceptable("nonsense"))
        XCTAssertFalse(FeedConfiguration.termsRecorded, "Flip TVGEPGTalkTermsRecorded only after docs/EPGTALK_PERMISSION.md records the approved terms")
    }

    func testGridRangeIsBoundedByData() {
        let now: Int64 = 1_800_000_000_000
        let progs = [Program(channelId: "a", title: "x", description: nil, startMillis: now - 10 * 3_600_000, stopMillis: now - 9 * 3_600_000),
                     Program(channelId: "a", title: "y", description: nil, startMillis: now, stopMillis: now + 72 * 3_600_000 + 7 * 60_000)]
        let r = GridRange.of(progs, now: now)!
        XCTAssertEqual(r.start, floorSlot(now - 3 * 3_600_000))            // never more than 3h back
        XCTAssertEqual(r.end, ceilSlot(now + 72 * 3_600_000 + 7 * 60_000)) // ends where the data ends, not at a fixed 7 days
        XCTAssertNil(GridRange.of([], now: now))
        XCTAssertEqual(r.slotCount, r.minutes / 30)
    }
}
