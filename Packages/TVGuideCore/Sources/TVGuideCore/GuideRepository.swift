import Foundation

// MARK: - Boundaries (the feed provider and the OS notification centre are injected)

/// Fetches the raw feed bytes. The production implementation uses URLSession; tests inject fakes.
public protocol FeedDownloading: Sendable {
    func download(_ url: URL) async throws -> Data
}

/// Hands reminders to the OS. `sync` replaces the whole pending set (iOS caps it at 64).
public protocol ReminderScheduling: Sendable {
    func sync(_ items: [(Reminder, Date)]) async
}

/// Where listings come from. `.sample` is the clearly-labelled preview data; `.live` downloads a XMLTV file.
public enum FeedMode: String, Codable, Sendable { case live, sample }

public struct RepositorySettings: Sendable {
    public var feedURL: URL
    public var leadMinutes: Int
    public var mode: FeedMode
    public init(feedURL: URL, leadMinutes: Int, mode: FeedMode) { self.feedURL = feedURL; self.leadMinutes = leadMinutes; self.mode = mode }
}

public enum RefreshResult: Equatable, Sendable {
    case updated(channels: Int, programs: Int, downloaded: Bool)
    case upToDate(nextAllowedMillis: Int64)
    case failed(message: String, haveSavedGuide: Bool)
    case noHome
}

/// Everything the UI needs, in one value.
public struct Snapshot: Equatable, Sendable {
    public var home: HomeProfile?
    public var guide: GuideData
    public var customization: Customization
    public var reminders: [Reminder]
    public var lastFetchMillis: Int64
    public var source: FeedMode?
    public init(home: HomeProfile? = nil, guide: GuideData = .empty, customization: Customization = Customization(),
                reminders: [Reminder] = [], lastFetchMillis: Int64 = 0, source: FeedMode? = nil) {
        self.home = home; self.guide = guide; self.customization = customization; self.reminders = reminders
        self.lastFetchMillis = lastFetchMillis; self.source = source
    }
}

private struct Meta: Codable {
    var lastFetchMillis: Int64 = 0      // last successful LIVE download
    var feedURL: String = ""
    var applied: String = ""            // "<mode>|<market>|<stamp>" of what the guide file currently holds
    var source: FeedMode?
    var sampleMillis: Int64 = 0         // when the sample guide was last built
}

/// Cache + refresh + customization + reminders. An actor, so concurrent calls are serialized.
/// A failed download or parse never touches the saved guide, customization or reminders.
public actor GuideRepository {
    private let store: FileStore
    private let catalog: Catalog
    private let downloader: FeedDownloading
    private let scheduler: ReminderScheduling
    private let settings: @Sendable () -> RepositorySettings
    private let clock: @Sendable () -> Int64

    private static let rawFile = "feed-cache.xml.gz"

    public init(directory: URL, catalog: Catalog, downloader: FeedDownloading, scheduler: ReminderScheduling,
                settings: @escaping @Sendable () -> RepositorySettings,
                clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.store = FileStore(directory: directory)
        self.catalog = catalog; self.downloader = downloader; self.scheduler = scheduler; self.settings = settings; self.clock = clock
    }

    // MARK: reading

    public func snapshot() -> Snapshot {
        let meta = store.read(Meta.self, "meta.json") ?? Meta()
        return Snapshot(home: store.read(HomeProfile.self, "home.json"),
                        guide: store.read(GuideData.self, "guide.json") ?? .empty,
                        customization: store.read(Customization.self, "custom.json") ?? Customization(),
                        reminders: (store.read([Reminder].self, "reminders.json") ?? []).sorted { $0.startMillis < $1.startMillis },
                        lastFetchMillis: meta.source == .sample ? meta.sampleMillis : meta.lastFetchMillis, source: meta.source)
    }

    public var markets: [Market] { catalog.markets }

    // MARK: customization

    private func custom() -> Customization { store.read(Customization.self, "custom.json") ?? Customization() }
    private func saveCustom(_ c: Customization) throws { try store.write(c, "custom.json") }

    @discardableResult
    public func update(_ f: (Customization) -> Customization) throws -> Customization {
        let c = f(custom()); try saveCustom(c); return c
    }

    public func assignNumber(channelId: String, number: String) throws {
        let channels = (store.read(GuideData.self, "guide.json") ?? .empty).channels
        try update { GuideLogic.assignNumber(channels, $0, channelId: channelId, number: number) }
    }

    /// "Restore lineup defaults": clears numbers, categories and order; keeps favorites.
    public func resetCustomization() throws { try update(GuideLogic.resetCustomization) }

    // MARK: home

    /// Saves the Home profile. A different market clears customization and reminders (channel ids differ per market);
    /// the same market keeps them. Returns true if the market changed.
    @discardableResult
    public func saveHome(zip: String, providerId: String, marketId: String) async throws -> Bool {
        let old = store.read(HomeProfile.self, "home.json")
        let changed = old != nil && old!.marketId != marketId
        try store.write(HomeProfile(zip: zip, providerId: providerId, marketId: marketId), "home.json")
        if changed {
            try saveCustom(Customization())
            try store.write([Reminder](), "reminders.json")
            await scheduler.sync([])
        }
        return changed
    }

    // MARK: refresh

    public func refresh(force: Bool = false) async -> RefreshResult {
        guard let home = store.read(HomeProfile.self, "home.json") else { return .noHome }
        let haveGuide = !(store.read(GuideData.self, "guide.json") ?? .empty).channels.isEmpty
        guard let market = catalog.market(id: home.marketId) else { return .failed(message: "Unknown market.", haveSavedGuide: haveGuide) }
        let s = settings()
        let now = clock()
        var meta = store.read(Meta.self, "meta.json") ?? Meta()

        let local: GuideData
        var downloaded = false
        switch s.mode {
        case .sample:
            local = SampleFeed.generate(now: now)
        case .live:
            let urlChanged = !meta.feedURL.isEmpty && meta.feedURL != s.feedURL.absoluteString
            let need = FeedPolicy.shouldRefresh(lastFetchMillis: meta.lastFetchMillis, now: now, force: force || !store.exists(Self.rawFile) || urlChanged)
            if need {
                do {
                    let data = try await downloader.download(s.feedURL)
                    let xml = try Gzip.decompressIfNeeded(data)
                    let parsed = try XmltvParser.parse(xml)
                    guard !parsed.channels.isEmpty, !parsed.programs.isEmpty else { throw XmltvError.empty }
                    try store.writeData(data, Self.rawFile)
                    meta.lastFetchMillis = now; meta.feedURL = s.feedURL.absoluteString
                    downloaded = true
                } catch {
                    return .failed(message: Self.friendly(error), haveSavedGuide: haveGuide)
                }
            } else if meta.applied == appliedKey(s.mode, home, meta.lastFetchMillis) && haveGuide {
                return .upToDate(nextAllowedMillis: FeedPolicy.nextAllowed(lastFetchMillis: meta.lastFetchMillis))
            }
            do {
                guard let raw = store.readData(Self.rawFile) else { throw XmltvError.empty }
                let full = try XmltvParser.parse(try Gzip.decompressIfNeeded(raw))
                local = MarketLogic.filterFor(market, data: full, markets: catalog.markets)
            } catch {
                return .failed(message: Self.friendly(error), haveSavedGuide: haveGuide)
            }
            if local.channels.isEmpty {
                return .failed(message: "No channels found for \(market.label) in this guide.", haveSavedGuide: haveGuide)
            }
        }
        do {
            try store.write(local, "guide.json")
            meta.applied = appliedKey(s.mode, home, meta.lastFetchMillis, now: now)
            meta.source = s.mode
            if s.mode == .sample { meta.sampleMillis = now }   // sample never counts as a live download
            try store.write(meta, "meta.json")
        } catch {
            return .failed(message: "The guide couldn't be saved on this device.", haveSavedGuide: haveGuide)
        }
        await reconcileReminders(local.programs, now: now)
        return .updated(channels: local.channels.count, programs: local.programs.count, downloaded: downloaded)
    }

    private func appliedKey(_ mode: FeedMode, _ h: HomeProfile, _ last: Int64, now: Int64 = 0) -> String {
        mode == .sample ? "sample|\(h.marketId)|\(now / 3_600_000)" : "live|\(h.marketId)|\(last)"
    }

    private static func friendly(_ e: Error) -> String {
        if let u = e as? URLError {
            switch u.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dataNotAllowed:
                return "Couldn't reach the guide server. Check your connection."
            default: return "The guide couldn't be downloaded."
            }
        }
        if let l = e as? LocalizedError, let d = l.errorDescription { return d }
        return "The guide file couldn't be read."
    }

    // MARK: reminders

    private func reminders() -> [Reminder] { store.read([Reminder].self, "reminders.json") ?? [] }
    private func saveReminders(_ r: [Reminder]) throws { try store.write(r, "reminders.json") }

    /// Returns false if the program has already started (nothing is set).
    public func addReminder(_ p: Program, channelName: String) async throws -> Bool {
        guard ReminderLogic.canRemind(p, now: clock()) else { return false }
        var all = reminders().filter { $0.programKey != p.key }
        all.append(ReminderLogic.from(p, channelName: channelName))
        try saveReminders(all)
        await syncScheduler()
        return true
    }

    public func cancelReminder(_ programKey: String) async throws {
        try saveReminders(reminders().filter { $0.programKey != programKey })
        await syncScheduler()
    }

    /// Re-arm the OS notifications from the saved reminders (app start, lead-time change). Past ones are dropped.
    public func rescheduleAll() async {
        let now = clock()
        let live = reminders().filter { $0.startMillis > now }
        if live.count != reminders().count { try? saveReminders(live) }
        await syncScheduler()
    }

    private func syncScheduler() async {
        let now = clock()
        let items = ReminderLogic.nextToSchedule(reminders(), leadMinutes: settings().leadMinutes, now: now)
            .map { ($0.0, Date(timeIntervalSince1970: TimeInterval($0.1) / 1000)) }
        await scheduler.sync(items)
    }

    private func reconcileReminders(_ programs: [Program], now: Int64) async {
        let current = reminders()
        guard !current.isEmpty else { return }
        let out = ReminderLogic.reconcile(current, programs: programs, now: now)
        try? saveReminders(out.keep + out.updated)
        await syncScheduler()
    }
}
