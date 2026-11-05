import SwiftUI
import TVGuideCore

struct SettingsScreen: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @Binding var path: [GuideScreen.Destination]
    @State private var confirmHome = false
    @State private var editFeed = false
    @State private var feedText = ""

    var body: some View {
        Form {
            Section("Guide") {
                if let m = model.market, let h = model.snapshot.home {
                    LabeledContent("Market", value: m.label)
                    LabeledContent("Zip", value: h.zip)
                    LabeledContent("Watching with", value: Providers.byId(h.providerId).label)
                }
                LabeledContent("Last updated", value: model.lastUpdated.map { Fmt.full.string(from: $0) } ?? "Never")
                LabeledContent("Listings end", value: model.dataEnd.map { Fmt.full.string(from: $0) } ?? "–")
                Button { Task { await model.refresh() } } label: { HStack { Text("Refresh now"); Spacer(); if model.refreshing { ProgressView() } } }.disabled(model.refreshing)
                Text("The guide is downloaded at most once a day to be kind to the free data source. Refreshing sooner just re-checks what is saved.").font(.footnote).foregroundStyle(Palette.onSurfaceVariant)
                Button("Change location or provider") { confirmHome = true }
            }
            Section("Channels") {
                NavigationLink(value: GuideScreen.Destination.channels) { Text("Manage channels") }
                Button("Restore lineup defaults", role: .destructive) { model.restoreDefaults() }
            }
            Section("Appearance") {
                Picker("Theme", selection: $settings.theme) { ForEach(ThemeChoice.allCases) { Text($0.label).tag($0) } }
                Picker("Text size", selection: $settings.textSize) { ForEach(TextSizeChoice.allCases) { Text($0.label).tag($0) } }
                Text("Text also follows your iOS text size setting (Settings › Display & Brightness).").font(.footnote).foregroundStyle(Palette.onSurfaceVariant)
            }
            Section("Reminders") {
                Picker("Remind me before", selection: $settings.leadMinutes) { ForEach(ReminderLogic.leadChoices, id: \.self) { Text("\($0) min").tag($0) } }
                    .onChange(of: settings.leadMinutes) { _, _ in Task { await model.leadTimeChanged() } }
                NavigationLink(value: GuideScreen.Destination.reminders) { LabeledContent("Manage reminders", value: "\(model.snapshot.reminders.count) set") }
            }
            Section("Data source") {
                LabeledContent("Source", value: model.isSample ? "Sample preview data" : "EPGTalk")
                if FeedConfiguration.liveFeedEnabledInBuild {
                    Toggle("Use sample data instead", isOn: $settings.useSampleData)
                        .onChange(of: settings.useSampleData) { _, _ in Task { await model.refresh() } }
                    Button("Feed address") { feedText = settings.feedURLString; editFeed = true }
                    Text(settings.feedURLString).font(.footnote).foregroundStyle(Palette.onSurfaceVariant)
                } else {
                    Text("This build shows sample preview data only. Live listings are switched on once the EPGTalk terms are confirmed.").font(.footnote).foregroundStyle(Palette.onSurfaceVariant)
                }
                Text(FeedConfiguration.attributionLine).font(.footnote)
                Link("epgtalk.com", destination: FeedConfiguration.attributionURL)
            }
            Section("About") {
                NavigationLink(value: GuideScreen.Destination.help) { Text("Help and guide") }
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            }
        }
        .navigationTitle("Settings")
        .alert("Change location or provider?", isPresented: $confirmHome) {
            Button("Continue") { model.beginChangeHome() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This replaces your Home setup. If you pick a different market, your channel numbers, categories, favorites and reminders for the old market are removed. Nothing changes if you cancel.") }
        .alert("Guide feed address", isPresented: $editFeed) {
            TextField("https://…", text: $feedText).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            Button("Save") {
                if FeedConfiguration.isAcceptable(feedText) { settings.feedURLString = feedText.trimmingCharacters(in: .whitespaces); Task { await model.feedSettingsChanged() } }
                else { model.toast = Toast(text: "Enter a full https:// address.") }
            }
            Button("Use default") { settings.feedURLString = FeedConfiguration.defaultURL.absoluteString; Task { await model.feedSettingsChanged() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Must start with https://. Changing it downloads the guide again from the new address.") }
    }
}
