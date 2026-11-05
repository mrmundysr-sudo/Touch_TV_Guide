import SwiftUI
import UserNotifications
import TVGuideCore

@main
struct TouchTVGuideApp: App {
    @StateObject private var model: AppModel
    private static let delegate = NotificationDelegate()

    init() {
        let settings = AppSettings()
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TouchTVGuide", isDirectory: true)
        let m = AppModel(settings: settings, makeRepository: { catalog, s in
            GuideRepository(directory: dir, catalog: catalog, downloader: URLSessionDownloader(), scheduler: NotificationScheduler(),
                            settings: { [weak s] in s?.repositorySettings ?? RepositorySettings(feedURL: FeedConfiguration.defaultURL, leadMinutes: 5, mode: .sample) })
        })
        _model = StateObject(wrappedValue: m)
        UNUserNotificationCenter.current().delegate = Self.delegate
        Self.delegate.onOpen = { [weak m] key, _ in m?.handleNotificationOpen(key: key) }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.settings)
                .preferredColorScheme(model.settings.theme.scheme)
                .tint(Palette.primary)
                .modifier(TextSizeModifier(choice: model.settings.textSize))
        }
    }
}
