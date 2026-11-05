import SwiftUI
import TVGuideCore

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            switch model.phase {
            case .splash: SplashView(error: model.startupError)
            case .setup: SetupFlow()
            case .main: GuideScreen()
            }
        }
        .task { await model.bootstrap() }
        .onChange(of: scenePhase) { _, p in
            if p == .active, model.phase == .main { Task { await model.refreshNotificationState(); await model.refresh(silent: true) } }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: model.phase)
    }
}

struct SplashView: View {
    let error: String?
    var body: some View {
        VStack(spacing: 16) {
            Image("LaunchLogo").resizable().scaledToFit().frame(width: 140, height: 140).accessibilityHidden(true)
            Text("Touch TV Guide").font(.largeTitle.weight(.bold)).foregroundStyle(Palette.primary)
            Text("Your local listings, favorites and reminders").font(.subheadline).foregroundStyle(Palette.onSurfaceVariant)
            if let error { Text(error).foregroundStyle(Palette.warning).multilineTextAlignment(.center).padding() }
            else { ProgressView().padding(.top, 8) }
        }
        .accessibilityElement(children: .combine)
    }
}
