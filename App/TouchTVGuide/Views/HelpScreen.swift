import SwiftUI

enum HelpContent {
    static let sections: [(String, String)] = [
        ("Getting started", "On first launch, enter your zip (or let the app suggest one), pick your local market, say how you watch TV, and choose favorite channels. You can redo setup any time in Settings."),
        ("Reading the guide", "Channels run down the left, time runs across. Swipe sideways for later shows or use Earlier, Now and Later. The gold line is the current time. The guide ends where the listings end, about three days out. Tap a show for details. A channel with nothing scheduled says “No listings”. Pull down to refresh."),
        ("Channel numbers, categories and order", "Tap a channel to change its number, give it a category, or mark it a favorite. If you give a channel a number another channel already uses, the other one shows “?” until you give it a number. Some numbers are shared in the guide data itself; those channels show a ⚠ so you can edit one. Open Settings › Manage channels to drag channels into your own order. “Restore lineup defaults” clears numbers, categories and order but keeps favorites."),
        ("Favorites", "Favorite a channel from its menu, or a single show from its details. Use the Favorites filter to see just your favorite channels."),
        ("Search", "Search finds channels by name or number, and programs by title or description, listed in channel-number order."),
        ("Reminders", "Open an upcoming show and tap Remind me. The first time, iOS asks to allow notifications; without it reminders can't alert you. Choose how early to be reminded in Settings. Manage or cancel reminders in Settings › Reminders. iOS lets an app have 64 pending notifications, so the soonest 64 are scheduled. Reminders are dropped if their show disappears from the guide."),
        ("Offline use and refresh", "The guide is saved on your phone and works without a connection. It refreshes about once a day. If a refresh fails, you keep the saved guide, your numbers, favorites and reminders. Settings shows when the guide was last updated and when its listings end."),
        ("Privacy", "No account, no ads, no tracking. Your zip, choices, favorites and reminders are stored only on this device. Location is optional: if you allow it, the app reads your approximate location once to suggest a zip, and does not keep or send it. The only network request is downloading the public guide file."),
        ("Where the data comes from", "Listings come from EPGTalk's free public TV guide (epgtalk.com). Zip code positions are derived from US Census Bureau data (via the MIT-licensed US-Zip-Codes-JSON list). The market list follows EPGTalk's US Local coverage. Builds that don't have live listings switched on show clearly labelled sample data."),
        ("Good to know", "This is a guide, not a player: it doesn't play TV or video. Listings are per local market, not per provider, so your provider may not carry every channel shown and its numbers may differ; edit numbers to match. Zip codes are matched to the nearest market, which can differ from your actual broadcast area; pick another in Change location if needed. Listings can contain errors and are only as good as the source."),
    ]
}

struct HelpScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(HelpContent.sections, id: \.0) { h, b in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(h).font(.headline).foregroundStyle(Palette.primary).accessibilityAddTraits(.isHeader)
                        Text(b)
                    }
                }
            }.padding()
        }
        .navigationTitle("Help and guide").navigationBarTitleDisplayMode(.inline)
    }
}
