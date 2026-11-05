import SwiftUI
import TVGuideCore

/// First-run / change-Home flow: 1 location, 2 market, 3 how you watch, 4 favorites (once the guide has loaded).
struct SetupFlow: View {
    @EnvironmentObject var model: AppModel
    @State private var step = 0
    @State private var zip = ""
    @State private var zipError: String?
    @State private var locationNote: String?
    @State private var market: Market?
    @State private var providerId = "antenna"
    @State private var showAll = false
    @State private var filter = ""
    @State private var showLocationWhy = false
    @State private var locating = false
    @State private var confirmChange = false
    @State private var working = false
    @StateObject private var location = LocationServiceBox()

    var isChange: Bool { model.snapshot.home != nil }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Step \(step + 1) of 4").font(.footnote.weight(.semibold)).foregroundStyle(Palette.primary)
                Group {
                    switch step {
                    case 0: zipStep
                    case 1: marketStep
                    case 2: providerStep
                    default: favoritesStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                footer
            }
            .padding(.horizontal)
            .navigationTitle("Set up your guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isChange && step < 3 { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.cancelChangeHome() } } }
            }
        }
        .onAppear {
            if let h = model.snapshot.home, zip.isEmpty { zip = h.zip; providerId = h.providerId; market = model.market }
        }
        .alert("Use your location?", isPresented: $showLocationWhy) {
            Button("Continue") { Task { await findLocation() } }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("iOS will ask for your approximate location. The app uses it once to suggest a zip code and does not store or send it. You can always type your zip instead.")
        }
        .alert("Replace your Home setup?", isPresented: $confirmChange) {
            Button("Replace", role: .destructive) { Task { await saveAndLoad() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("If you pick a different market, your channel numbers, categories, favorites and reminders for the old market are removed. Nothing changes if you cancel.")
        }
    }

    // MARK: steps

    private var zipStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Where are you?").font(.title2.weight(.semibold))
            Text("Enter your zip code so the guide can show your local channels. Your zip stays on this device. There is no account.")
            TextField("Zip code", text: $zip)
                .keyboardType(.numberPad).textContentType(.postalCode).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Zip code")
                .onChange(of: zip) { _, v in zip = String(v.filter { $0.isNumber || $0 == "-" }.prefix(10)); zipError = nil }
            if let zipError { Text(zipError).foregroundStyle(Palette.warning).font(.footnote) }
            Button { showLocationWhy = true } label: {
                Label(locating ? "Finding your location…" : "Use my approximate location", systemImage: "location")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).disabled(locating)
            if let locationNote { Text(locationNote).font(.footnote).foregroundStyle(Palette.onSurfaceVariant) }
            Spacer()
        }
    }

    private var suggestions: [Market] {
        guard let c = model.catalog else { return [] }
        return MarketLogic.marketsForZip(zip, zips: c.zips, markets: c.markets, limit: 5)
    }

    private var marketStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick your local market").font(.title2.weight(.semibold))
            Text("These are the nearest markets to your zip. The nearest isn't always the one your stations broadcast from, so choose the one that matches your local news.")
            let list = showAll ? model.markets.filter { filter.isEmpty || $0.label.localizedCaseInsensitiveContains(filter) } : suggestions
            if showAll { TextField("Search markets", text: $filter).textFieldStyle(.roundedBorder) }
            if !showAll && suggestions.isEmpty {
                Text("That zip isn't in the built-in table. Show all markets to pick yours.").foregroundStyle(Palette.warning)
            }
            List(list) { m in
                Button { market = m } label: {
                    HStack { Text(m.label); Spacer(); if market?.id == m.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.primary) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(market?.id == m.id ? [.isSelected] : [])
            }
            .listStyle(.plain)
            Button(showAll ? "Show nearest only" : "Show all markets") { showAll.toggle() }
        }
    }

    private var providerStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How do you watch TV?").font(.title2.weight(.semibold))
            Text("This just labels your guide. The guide lists your market's local channels and cannot know which channels your plan includes, so edit a channel's number to match your lineup.")
            List(Providers.all) { p in
                Button { providerId = p.id } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) { Text(p.label); Text(p.note).font(.footnote).foregroundStyle(Palette.onSurfaceVariant) }
                        Spacer()
                        if providerId == p.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.primary) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(providerId == p.id ? [.isSelected] : [])
            }
            .listStyle(.plain)
        }
    }

    private var favoritesStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick your favorite channels").font(.title2.weight(.semibold))
            if model.refreshing && !model.hasGuide {
                HStack(spacing: 12) { ProgressView(); Text("Downloading the guide for \(model.market?.label ?? "your market")…") }
                Spacer()
            } else if model.hasGuide {
                Text("Favorites get their own filter in the guide. You can change this any time.")
                if model.isSample { SampleBadge() }
                List(GuideLogic.sorted(model.channels, model.cu)) { c in
                    let fav = model.cu.favoriteChannels.contains(c.id)
                    Button { model.toggleFavoriteChannel(c.id) } label: {
                        HStack { Text(GuideLogic.effectiveNumber(c, model.cu)).bold().frame(minWidth: 44, alignment: .leading); Text(c.name); Spacer()
                            Image(systemName: fav ? "star.fill" : "star").foregroundStyle(fav ? Palette.primary : Palette.outline) }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Channel \(GuideLogic.effectiveNumber(c, model.cu)), \(c.name)")
                    .accessibilityValue(fav ? "Favorite" : "Not a favorite")
                    .accessibilityHint("Double tap to toggle favorite")
                }
                .listStyle(.plain)
            } else {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(Palette.warning)
                Text(model.refreshError ?? "The guide hasn't downloaded yet.")
                Text("You can try again, or continue now and download it later.").font(.footnote)
                Button("Try again") { Task { await model.refresh() } }.buttonStyle(.borderedProminent)
                Spacer()
            }
        }
    }

    // MARK: footer / actions

    private var footer: some View {
        HStack {
            if step > 0 && step < 3 { Button("Back") { step -= 1 }.buttonStyle(.bordered) }
            Spacer()
            Button(step == 2 ? "Show my guide" : step == 3 ? "Done" : "Next") { Task { await next() } }
                .buttonStyle(.borderedProminent)
                .disabled((step == 1 && market == nil) || working || (step == 3 && model.refreshing))
        }
        .padding(.vertical, 10)
    }

    private func next() async {
        switch step {
        case 0:
            guard let z = MarketLogic.cleanZip(zip) else { zipError = "Enter a 5-digit US zip code."; return }
            zip = z
            let s = suggestions
            if market == nil || !s.contains(where: { $0.id == market?.id }) { market = s.first ?? market }
            step = 1
        case 1: step = 2
        case 2:
            if isChange && model.snapshot.home?.marketId != market?.id { confirmChange = true } else { await saveAndLoad() }
        default: model.finishSetup()
        }
    }

    private func saveAndLoad() async {
        guard let market else { return }
        working = true
        await model.saveHome(zip: MarketLogic.cleanZip(zip) ?? zip, providerId: providerId, market: market)
        working = false
        step = 3
        await model.refresh()
    }

    private func findLocation() async {
        locating = true; locationNote = nil
        let outcome = await location.service.requestOnce()
        locating = false
        guard let catalog = model.catalog else { return }
        switch outcome {
        case .found(let lat, let lon):
            if let z = MarketLogic.nearestZip(LatLon(lat: lat, lon: lon), zips: catalog.zips) {
                zip = z; zipError = nil; locationNote = "Suggested zip \(z) from your approximate location. Change it if it isn't right."
            } else { locationNote = "Couldn't match your location to a zip. Please type your zip code." }
        case .denied: locationNote = "Location permission wasn't granted. No problem: type your zip code instead."
        case .unavailable: locationNote = "Your phone couldn't provide a location right now. Please type your zip code."
        }
    }
}

/// Holds the main-actor location service for a View (Views are value types).
@MainActor final class LocationServiceBox: ObservableObject {
    let service = LocationService()
}

struct SampleBadge: View {
    var body: some View {
        Label("Sample preview data – not real listings", systemImage: "info.circle")
            .font(.footnote.weight(.semibold)).padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.primaryContainer, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("Sample preview data. Not real listings.")
    }
}
