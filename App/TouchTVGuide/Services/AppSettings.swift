import SwiftUI
import TVGuideCore

enum ThemeChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { self == .system ? "System" : self == .light ? "Light" : "Dark" }
    var scheme: ColorScheme? { self == .system ? nil : self == .light ? .light : .dark }
}

enum TextSizeChoice: String, CaseIterable, Identifiable {
    case small, standard, large, largest
    var id: String { rawValue }
    var label: String {
        switch self { case .small: return "Small"; case .standard: return "Default"; case .large: return "Large"; case .largest: return "Largest" }
    }
    /// Steps added to the system Dynamic Type size (so the in-app choice stacks with the iOS setting).
    var steps: Int { switch self { case .small: return -1; case .standard: return 0; case .large: return 1; case .largest: return 2 } }
}

/// User preferences (UserDefaults). Not part of the guide cache, so they survive a market change.
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = ThemeChoice(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system
        textSize = TextSizeChoice(rawValue: defaults.string(forKey: "textSize") ?? "") ?? .standard
        let lead = defaults.integer(forKey: "lead")
        leadMinutes = ReminderLogic.leadChoices.contains(lead) ? lead : ReminderLogic.defaultLeadMinutes
        if let s = defaults.string(forKey: "feedURL"), FeedConfiguration.isAcceptable(s) { feedURLString = s } else { feedURLString = FeedConfiguration.defaultURL.absoluteString }
        useSampleData = defaults.object(forKey: "useSample") as? Bool ?? !FeedConfiguration.liveFeedEnabledInBuild
    }

    @Published var theme: ThemeChoice { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
    @Published var textSize: TextSizeChoice { didSet { defaults.set(textSize.rawValue, forKey: "textSize") } }
    @Published var leadMinutes: Int { didSet { defaults.set(leadMinutes, forKey: "lead") } }
    @Published var feedURLString: String { didSet { defaults.set(feedURLString, forKey: "feedURL") } }
    @Published var useSampleData: Bool { didSet { defaults.set(useSampleData, forKey: "useSample") } }

    /// The effective mode. A build with the live feed disabled can never go live, whatever the stored preference says.
    var mode: FeedMode { FeedConfiguration.liveFeedEnabledInBuild && !useSampleData ? .live : .sample }

    var feedURL: URL { URL(string: feedURLString) ?? FeedConfiguration.defaultURL }

    var repositorySettings: RepositorySettings { RepositorySettings(feedURL: feedURL, leadMinutes: leadMinutes, mode: mode) }
}


/// Applies the in-app text size on top of the system Dynamic Type size.
struct TextSizeModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var system
    let choice: TextSizeChoice
    func body(content: Content) -> some View {
        let all = DynamicTypeSize.allCases
        let i = all.firstIndex(of: system) ?? all.firstIndex(of: .large) ?? 0
        let j = min(max(i + choice.steps, 0), all.count - 1)
        content.dynamicTypeSize(all[j])
    }
}
