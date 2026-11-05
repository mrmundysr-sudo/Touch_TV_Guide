import Foundation
import SwiftUI
import TVGuideCore

enum AppPhase: Equatable { case splash, setup, main }

/// A short-lived message shown at the bottom of the guide.
struct Toast: Identifiable, Equatable { let id = UUID(); let text: String }

/// Where a reminder request ended up.
enum ReminderOutcome: Equatable { case set, alreadyStarted, needsPermission, denied }

/// All app state and actions. UI reads published values and calls the methods; every rule lives in TVGuideCore.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var phase: AppPhase = .splash
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var catalog: Catalog?
    @Published private(set) var refreshing = false
    @Published private(set) var refreshError: String?
    @Published private(set) var notificationState: NotificationState = .notDetermined
    @Published var toast: Toast?
    /// Set when a reminder notification is tapped; the guide opens that program.
    @Published var openProgramKey: String?

    let settings: AppSettings
    private var repository: GuideRepository?
    private let makeRepository: (Catalog, AppSettings) -> GuideRepository
    private let loadCatalog: @Sendable () throws -> Catalog
    private let permission: NotificationPermission
    private let clock: () -> Date
    @Published private(set) var startupError: String?

    init(settings: AppSettings = AppSettings(),
         loadCatalog: @escaping @Sendable () throws -> Catalog = { try Catalog.bundled() },
         makeRepository: @escaping (Catalog, AppSettings) -> GuideRepository,
         permission: NotificationPermission = SystemNotificationPermission(),
         clock: @escaping () -> Date = Date.init) {
        self.settings = settings; self.loadCatalog = loadCatalog; self.makeRepository = makeRepository
        self.permission = permission; self.clock = clock
    }

    var now: Date { clock() }
    var nowMillis: Int64 { Int64(clock().timeIntervalSince1970 * 1000) }
    var markets: [Market] { catalog?.markets ?? [] }
    var market: Market? { snapshot.home.flatMap { catalog?.market(id: $0.marketId) } }
    var provider: Provider? { snapshot.home.map { Providers.byId($0.providerId) } }
    var cu: Customization { snapshot.customization }
    var channels: [Channel] { snapshot.guide.channels }
    var hasGuide: Bool { !snapshot.guide.channels.isEmpty && !snapshot.guide.programs.isEmpty }
    var isSample: Bool { snapshot.source == .sample || (snapshot.source == nil && settings.mode == .sample) }
    var dataEnd: Date? { snapshot.guide.programs.isEmpty ? nil : Date(timeIntervalSince1970: TimeInterval(GuideLogic.dataEnd(snapshot.guide.programs)) / 1000) }
    var lastUpdated: Date? { snapshot.lastFetchMillis > 0 ? Date(timeIntervalSince1970: TimeInterval(snapshot.lastFetchMillis) / 1000) : nil }
    var duplicateNumbers: [String: [Channel]] { GuideLogic.duplicateNumbers(channels, cu) }
    var reminderKeys: Set<String> { Set(snapshot.reminders.map(\.programKey)) }

    // MARK: startup

    func bootstrap() async {
        guard repository == nil else { return }
        let started = Date()
        let loader = loadCatalog
        do {
            let cat = try await Task.detached(priority: .userInitiated) { try loader() }.value
            catalog = cat
            repository = makeRepository(cat, settings)
        } catch {
            startupError = "The built-in market list couldn't be loaded. Please reinstall the app."
            return
        }
        await reload()
        notificationState = await permission.state()
        await repository?.rescheduleAll()
        // Keep the splash up briefly so it reads as a launch screen, not a flash.
        let elapsed = Date().timeIntervalSince(started)
        if elapsed < 0.9 { try? await Task.sleep(nanoseconds: UInt64((0.9 - elapsed) * 1_000_000_000)) }
        phase = snapshot.home == nil ? .setup : .main
        if snapshot.home != nil { await refresh(silent: true) }
    }

    func reload() async {
        guard let repository else { return }
        snapshot = await repository.snapshot()
    }

    // MARK: setup

    /// Saves Home. Returns true if the market changed (old customization was cleared).
    @discardableResult
    func saveHome(zip: String, providerId: String, market: Market) async -> Bool {
        guard let repository else { return false }
        let changed = (try? await repository.saveHome(zip: zip, providerId: providerId, marketId: market.id)) ?? false
        await reload()
        return changed
    }

    func finishSetup() { phase = .main }
    func beginChangeHome() { phase = .setup }
    func cancelChangeHome() { if snapshot.home != nil { phase = .main } }

    // MARK: refresh

    func refresh(silent: Bool = false) async {
        guard let repository, !refreshing else { return }
        refreshing = true
        let result = await repository.refresh()
        refreshing = false
        await reload()
        switch result {
        case .updated(_, _, let downloaded):
            refreshError = nil
            if !silent { toast = Toast(text: downloaded ? "Guide updated." : "Guide is up to date.") }
        case .upToDate:
            refreshError = nil
            if !silent { toast = Toast(text: "Guide is up to date. It refreshes at most once a day.") }
        case .failed(let message, let have):
            refreshError = message
            if !silent || !have { toast = Toast(text: message + (have ? " Showing your saved guide." : "")) }
        case .noHome: break
        }
    }

    /// Settings changes that need the repository to react.
    func feedSettingsChanged() async { await refresh() }
    func leadTimeChanged() async { await repository?.rescheduleAll() }

    // MARK: customization

    private func mutate(_ f: @escaping (Customization) -> Customization) {
        guard let repository else { return }
        Task { _ = try? await repository.update(f); await reload() }
    }

    func toggleFavoriteChannel(_ id: String) { mutate { GuideLogic.toggleFavoriteChannel($0, id) } }
    func toggleFavoriteProgram(_ p: Program) { mutate { GuideLogic.toggleFavoriteProgram($0, p) } }

    func setNumber(_ channelId: String, number: String) {
        guard let repository else { return }
        Task { try? await repository.assignNumber(channelId: channelId, number: number.isEmpty ? unknownNumber : number); await reload() }
    }

    func setCategory(_ channelId: String, category: String?) {
        mutate { cu in
            var c = cu
            let t = category?.trimmingCharacters(in: .whitespaces) ?? ""
            if t.isEmpty { c.categories.removeValue(forKey: channelId) } else { c.categories[channelId] = t }
            return c
        }
    }

    func setOrder(_ ids: [String]) { mutate { GuideLogic.setOrder($0, ids: ids) } }

    func restoreDefaults() {
        guard let repository else { return }
        Task { try? await repository.resetCustomization(); await reload(); toast = Toast(text: "Lineup defaults restored. Favorites kept.") }
    }

    // MARK: reminders

    func refreshNotificationState() async { notificationState = await permission.state() }

    /// Requests the permission (only when asked to) and sets the reminder.
    func addReminder(_ p: Program, channelName: String, askPermission: Bool) async -> ReminderOutcome {
        guard let repository else { return .denied }
        guard ReminderLogic.canRemind(p, now: nowMillis) else { return .alreadyStarted }
        var state = await permission.state()
        if state == .notDetermined {
            if !askPermission { return .needsPermission }
            _ = await permission.request()
            state = await permission.state()
        }
        notificationState = state
        guard state == .allowed else { return .denied }
        let ok = (try? await repository.addReminder(p, channelName: channelName)) ?? false
        await reload()
        if ok { toast = Toast(text: "Reminder set for \(p.title).") }
        return ok ? .set : .alreadyStarted
    }

    func cancelReminder(_ key: String) {
        guard let repository else { return }
        Task { try? await repository.cancelReminder(key); await reload(); toast = Toast(text: "Reminder cancelled.") }
    }

    // MARK: notifications opened

    func handleNotificationOpen(key: String) {
        openProgramKey = key
        if phase == .main { return }
    }
}
