import XCTest
@testable import TVGuideCore

final class FakeDownloader: FeedDownloading, @unchecked Sendable {
    enum Reply { case data(Data), fail(Error) }
    private let lock = NSLock()
    private var replies: [Reply] = []
    private(set) var requests: [URL] = []
    func enqueue(_ r: Reply) { lock.lock(); replies.append(r); lock.unlock() }
    func download(_ url: URL) async throws -> Data {
        lock.lock(); requests.append(url)
        let r = replies.isEmpty ? Reply.fail(URLError(.notConnectedToInternet)) : replies.removeFirst()
        lock.unlock()
        switch r { case .data(let d): return d; case .fail(let e): throw e }
    }
    var count: Int { lock.lock(); defer { lock.unlock() }; return requests.count }
}

final class FakeScheduler: ReminderScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var _items: [(Reminder, Date)] = []
    func sync(_ items: [(Reminder, Date)]) async { lock.lock(); _items = items; lock.unlock() }
    var items: [(Reminder, Date)] { lock.lock(); defer { lock.unlock() }; return _items }
}

final class Box<T>: @unchecked Sendable {
    private let lock = NSLock(); private var v: T
    init(_ v: T) { self.v = v }
    var value: T { get { lock.lock(); defer { lock.unlock() }; return v } set { lock.lock(); v = newValue; lock.unlock() } }
}

final class RepositoryTests: XCTestCase {
    var dl: FakeDownloader!
    var sched: FakeScheduler!
    var now: Box<Int64>!
    var settings: Box<RepositorySettings>!
    var repo: GuideRepository!
    var dir: URL!

    override func setUp() {
        dl = FakeDownloader(); sched = FakeScheduler(); now = Box(1_800_000_000_000); dir = tempDir()
        settings = Box(RepositorySettings(feedURL: URL(string: "https://example.test/feed.xml")!, leadMinutes: 5, mode: .live))
        makeRepo()
    }

    func makeRepo() {
        let s = settings!, n = now!
        repo = GuideRepository(directory: dir, catalog: testCatalog, downloader: dl, scheduler: sched,
                               settings: { s.value }, clock: { n.value })
    }

    func xml(at t: Int64, title: String = "Evening News") -> Data {
        func ts(_ ms: Int64) -> String {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyyMMddHHmmss"; return f.string(from: Date(timeIntervalSince1970: TimeInterval(ms) / 1000)) + " +0000"
        }
        return Data("""
        <?xml version="1.0"?><!DOCTYPE tv SYSTEM "xmltv.dtd"><tv>
        <channel id="ep1"><display-name>CBS El Paso</display-name><display-name>4.1</display-name></channel>
        <channel id="ep2"><display-name>ABC El Paso</display-name><display-name>7.1</display-name></channel>
        <channel id="om1"><display-name>CBS Omaha</display-name><display-name>3.1</display-name></channel>
        <channel id="nat"><display-name>COZI TV</display-name></channel>
        <programme start="\(ts(t))" stop="\(ts(t + 3_600_000))" channel="ep1"><title>\(title)</title></programme>
        <programme start="\(ts(t + 3_600_000))" stop="\(ts(t + 7_200_000))" channel="ep1"><title>Movie</title></programme>
        <programme start="\(ts(t))" stop="\(ts(t + 3_600_000))" channel="om1"><title>Omaha Show</title></programme>
        </tv>
        """.utf8)
    }

    func setupHome() async throws { try await repo.saveHome(zip: "79901", providerId: "antenna", marketId: "el-paso-tx") }

    func testFreshInstallHasNoHomeAndEmptyGuide() async {
        let s = await repo.snapshot()
        XCTAssertNil(s.home); XCTAssertTrue(s.guide.channels.isEmpty); XCTAssertEqual(s.customization, Customization())
        let r = await repo.refresh(); XCTAssertEqual(r, .noHome)
    }

    func testSetupThenFetchStoresOnlyHomeMarketChannels() async throws {
        try await setupHome(); dl.enqueue(.data(xml(at: now.value + 600_000)))
        let r = await repo.refresh()
        guard case .updated(_, _, let downloaded) = r else { return XCTFail("\(r)") }
        XCTAssertTrue(downloaded)
        let s = await repo.snapshot()
        XCTAssertEqual(Set(s.guide.channels.map(\.id)), ["ep1", "ep2", "nat"])
        XCTAssertEqual(s.guide.programs.count, 2); XCTAssertEqual(s.source, .live); XCTAssertEqual(s.lastFetchMillis, now.value)
        XCTAssertEqual(GuideLogic.sorted(s.guide.channels, s.customization).map(\.id), ["ep1", "ep2", "nat"])
    }

    #if canImport(Compression)
    func testGzippedFeedIsAccepted() async throws {
        try await setupHome(); dl.enqueue(.data(try Gzip.compress(xml(at: now.value + 600_000))))
        let r = await repo.refresh(); guard case .updated = r else { return XCTFail("\(r)") }
        let _a1 = await repo.snapshot()
        let s = _a1; XCTAssertEqual(s.guide.channels.count, 3)
    }
    #endif

    func testCustomizationSurvivesRefresh() async throws {
        try await setupHome(); dl.enqueue(.data(xml(at: now.value + 600_000))); _ = await repo.refresh()
        try await repo.assignNumber(channelId: "ep2", number: "4.1")
        try await repo.update { GuideLogic.toggleFavoriteChannel($0, "ep2") }
        try await repo.update { var c = $0; c.categories["ep1"] = "News"; return c }
        now.value += 25 * 3_600_000; dl.enqueue(.data(xml(at: now.value + 600_000, title: "Next Day News")))
        let r = await repo.refresh(); guard case .updated = r else { return XCTFail("\(r)") }
        let s = await repo.snapshot()
        XCTAssertEqual(GuideLogic.effectiveNumber(s.guide.channels.first { $0.id == "ep2" }!, s.customization), "4.1")
        XCTAssertEqual(GuideLogic.effectiveNumber(s.guide.channels.first { $0.id == "ep1" }!, s.customization), "?")
        XCTAssertEqual(s.customization.favoriteChannels, ["ep2"]); XCTAssertEqual(s.customization.categories["ep1"], "News")
        XCTAssertTrue(s.guide.programs.contains { $0.title == "Next Day News" })
    }

    func testFailedFetchKeepsSavedGuideAndCustomization() async throws {
        try await setupHome(); dl.enqueue(.data(xml(at: now.value + 600_000))); _ = await repo.refresh()
        try await repo.update { GuideLogic.toggleFavoriteChannel($0, "ep1") }
        let before = await repo.snapshot()
        now.value += 25 * 3_600_000
        dl.enqueue(.fail(URLError(.notConnectedToInternet)))
        let r = await repo.refresh()
        guard case .failed(let msg, let have) = r else { return XCTFail("\(r)") }
        XCTAssertTrue(have); XCTAssertTrue(msg.contains("connection"))
        let _a2 = await repo.snapshot()
        XCTAssertEqual(_a2.guide, before.guide)
        let _a3 = await repo.snapshot()
        XCTAssertEqual(_a3.customization.favoriteChannels, ["ep1"])
        // garbage, truncated and empty bodies are rejected without touching anything
        for bad in [Data("<html>not a guide</html>".utf8), Data("<tv><channel id=\"a\">".utf8), Data()] {
            dl.enqueue(.data(bad))
            guard case .failed = await repo.refresh(force: true) else { return XCTFail("bad body accepted") }
            let _a4 = await repo.snapshot()
            XCTAssertEqual(_a4.guide, before.guide)
        }
    }

    func testFailedFirstFetchLeavesEmptyStateAndRetryWorks() async throws {
        try await setupHome(); dl.enqueue(.fail(URLError(.timedOut)))
        guard case .failed(_, let have) = await repo.refresh() else { return XCTFail() }
        let _a5 = await repo.snapshot()
        XCTAssertFalse(have); XCTAssertTrue(_a5.guide.channels.isEmpty)
        dl.enqueue(.data(xml(at: now.value + 600_000)))
        guard case .updated = await repo.refresh() else { return XCTFail() }
        let _a6 = await repo.snapshot()
        XCTAssertFalse(_a6.guide.channels.isEmpty)
    }

    func testNeverDownloadsMoreThanOncePerDay() async throws {
        try await setupHome(); dl.enqueue(.data(xml(at: now.value + 600_000))); _ = await repo.refresh()
        XCTAssertEqual(dl.count, 1)
        now.value += 3_600_000
        guard case .upToDate = await repo.refresh() else { return XCTFail() }
        XCTAssertEqual(dl.count, 1)
        now.value += 24 * 3_600_000; dl.enqueue(.data(xml(at: now.value + 600_000))); _ = await repo.refresh()
        XCTAssertEqual(dl.count, 2)
    }

    func testChangingMarketReusesCachedFileWithoutRedownloading() async throws {
        try await setupHome(); dl.enqueue(.data(xml(at: now.value + 600_000))); _ = await repo.refresh()
        let changed = try await repo.saveHome(zip: "68102", providerId: "cable", marketId: "omaha-ne")
        XCTAssertTrue(changed)
        guard case .updated(_, _, let downloaded) = await repo.refresh() else { return XCTFail() }
        XCTAssertFalse(downloaded); XCTAssertEqual(dl.count, 1)
        let _a7 = await repo.snapshot()
        XCTAssertEqual(Set(_a7.guide.channels.map(\.id)), ["om1", "nat"])
    }

    func testMarketChangeClearsOldCustomizationSameMarketKeepsIt() async throws {
        try await setupHome(); dl.enqueue(.data(xml(at: now.value + 600_000))); _ = await repo.refresh()
        try await repo.update { GuideLogic.toggleFavoriteChannel($0, "ep1") }
        let same = try await repo.saveHome(zip: "79901", providerId: "hulu", marketId: "el-paso-tx")
        let _a8 = await repo.snapshot()
        XCTAssertFalse(same); XCTAssertEqual(_a8.customization.favoriteChannels, ["ep1"])
        try await repo.saveHome(zip: "68102", providerId: "hulu", marketId: "omaha-ne")
        let s = await repo.snapshot()
        XCTAssertEqual(s.customization, Customization()); XCTAssertEqual(s.home, HomeProfile(zip: "68102", providerId: "hulu", marketId: "omaha-ne"))
    }

    func testResetRestoresDefaultsKeepsFavorites() async throws {
        try await setupHome(); dl.enqueue(.data(xml(at: now.value + 600_000))); _ = await repo.refresh()
        try await repo.assignNumber(channelId: "ep1", number: "99")
        try await repo.update { var c = GuideLogic.toggleFavoriteChannel($0, "ep1"); c.categories["ep1"] = "News"; return GuideLogic.setOrder(c, ids: ["nat", "ep1"]) }
        try await repo.resetCustomization()
        let c = await repo.snapshot().customization
        XCTAssertTrue(c.numbers.isEmpty && c.categories.isEmpty && c.customOrder.isEmpty); XCTAssertEqual(c.favoriteChannels, ["ep1"])
    }

    func testDataSurvivesRelaunch() async throws {
        try await setupHome(); dl.enqueue(.data(xml(at: now.value + 600_000))); _ = await repo.refresh()
        try await repo.assignNumber(channelId: "ep2", number: "4.1")
        makeRepo()                                                               // "process death"
        let s = await repo.snapshot()
        XCTAssertEqual(s.customization.numbers["ep1"], "?"); XCTAssertEqual(s.customization.numbers["ep2"], "4.1")
        XCTAssertEqual(s.guide.channels.count, 3); XCTAssertEqual(s.home?.marketId, "el-paso-tx")
    }

    func testRemindersAddCancelRescheduleReconcileAndLeadTime() async throws {
        try await setupHome(); dl.enqueue(.data(xml(at: now.value + 600_000))); _ = await repo.refresh()
        let movie = await repo.snapshot().guide.programs.first { $0.title == "Movie" }!
        let added = try await repo.addReminder(movie, channelName: "CBS El Paso"); XCTAssertTrue(added)
        XCTAssertEqual(sched.items.count, 1)
        XCTAssertEqual(sched.items[0].1.timeIntervalSince1970, TimeInterval(movie.startMillis - 300_000) / 1000, accuracy: 0.5)
        settings.value.leadMinutes = 15; await repo.rescheduleAll()
        XCTAssertEqual(sched.items[0].1.timeIntervalSince1970, TimeInterval(movie.startMillis - 900_000) / 1000, accuracy: 0.5)
        try await repo.cancelReminder(movie.key)
        let _a9 = await repo.snapshot()
        XCTAssertTrue(sched.items.isEmpty); XCTAssertTrue(_a9.reminders.isEmpty)
        let started = Program(channelId: "ep1", title: "Old", description: nil, startMillis: now.value - 1000, stopMillis: now.value + 1000)
        let notAdded = try await repo.addReminder(started, channelName: "x"); XCTAssertFalse(notAdded)
        _ = try await repo.addReminder(movie, channelName: "CBS El Paso")
        now.value += 25 * 3_600_000; dl.enqueue(.data(xml(at: now.value + 600_000).replacingOccurrences("Movie", "Different")))
        _ = await repo.refresh()
        let _a10 = await repo.snapshot()
        XCTAssertTrue(_a10.reminders.isEmpty); XCTAssertTrue(sched.items.isEmpty)
    }

    func testSampleModeNeverTouchesNetworkOrLiveClock() async throws {
        settings.value.mode = .sample
        try await setupHome()
        guard case .updated(let ch, _, let downloaded) = await repo.refresh() else { return XCTFail() }
        XCTAssertFalse(downloaded); XCTAssertEqual(dl.count, 0); XCTAssertEqual(ch, SampleFeed.channelNames.count)
        let _a11 = await repo.snapshot()
        var s = _a11; XCTAssertEqual(s.source, .sample); XCTAssertEqual(s.lastFetchMillis, now.value)
        // switching to live afterwards still performs the first real download
        settings.value.mode = .live; dl.enqueue(.data(xml(at: now.value + 600_000)))
        guard case .updated(_, _, let d2) = await repo.refresh() else { return XCTFail() }
        let _a12 = await repo.snapshot()
        XCTAssertTrue(d2); s = _a12; XCTAssertEqual(s.source, .live)
    }

    func testChangingFeedAddressForcesFreshDownload() async throws {
        try await setupHome(); dl.enqueue(.data(xml(at: now.value + 600_000))); _ = await repo.refresh()
        now.value += 1000
        settings.value.feedURL = URL(string: "https://other.test/x.xml")!
        dl.enqueue(.data(xml(at: now.value + 600_000, title: "From New Feed")))
        guard case .updated(_, _, let d) = await repo.refresh() else { return XCTFail() }
        XCTAssertTrue(d); XCTAssertEqual(dl.requests.last?.host, "other.test")
        let _a13 = await repo.snapshot()
        XCTAssertTrue(_a13.guide.programs.contains { $0.title == "From New Feed" })
    }

    func testSampleFeedShape() {
        let d = SampleFeed.generate(now: 1_800_000_000_000)
        XCTAssertEqual(d.channels.count, SampleFeed.channelNames.count)
        XCTAssertGreaterThan(GuideLogic.dataEnd(d.programs), 1_800_000_000_000 + 70 * 3_600_000)
        XCTAssertTrue(d.channels.allSatisfy { c in !GuideLogic.window(d.programs, channelId: c.id, from: 1_800_000_000_000, to: 1_800_000_000_000 + 1).isEmpty })
    }
}

extension Data {
    func replacingOccurrences(_ a: String, _ b: String) -> Data {
        Data((String(data: self, encoding: .utf8) ?? "").replacingOccurrences(of: a, with: b).utf8)
    }
}
