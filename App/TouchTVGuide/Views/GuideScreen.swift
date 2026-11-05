import SwiftUI
import TVGuideCore
import UIKit

enum GuideFilter: Hashable { case all, favorites, category(String) }

struct GuideScreen: View {
    @EnvironmentObject var model: AppModel
    @State private var filter: GuideFilter = .all
    @State private var command: (GridCommand, UUID)?
    @State private var canEarlier = false
    @State private var canLater = true
    @State private var jump: Int64?
    @State private var detail: ProgramRef?
    @State private var editing: Channel?
    @State private var tick = Date()
    @State private var path: [Destination] = []
    @State private var permissionPrompt: ProgramRef?
    @State private var permissionDenied = false

    enum Destination: Hashable { case search, settings, reminders, help, channels }

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if model.hasGuide { filterBar; statusBanners; navBar }
                content
            }
            .background(Palette.background)
            .navigationTitle(model.market?.name ?? "Touch TV Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { path.append(.search) } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Search")
                    Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(model.refreshing).accessibilityLabel("Refresh guide")
                    Button { path.append(.settings) } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                }
            }
            .navigationDestination(for: Destination.self) { d in
                switch d {
                case .search: SearchScreen(onProgram: { detail = $0 })
                case .settings: SettingsScreen(path: $path)
                case .reminders: RemindersScreen()
                case .help: HelpScreen()
                case .channels: ChannelManagerScreen()
                }
            }
        }
        .sheet(item: $detail) { ref in
            ProgramDetailView(ref: ref, onRemind: { requestReminder($0) }).presentationDetents([.medium, .large])
        }
        .sheet(item: $editing) { ch in ChannelEditView(channel: ch).presentationDetents([.medium, .large]) }
        .overlay(alignment: .bottom) { ToastView() }
        .onReceive(timer) { tick = $0 }
        .onChange(of: model.openProgramKey) { _, key in openFromNotification(key) }
        .onAppear { openFromNotification(model.openProgramKey) }
        .alert("Allow notifications?", isPresented: Binding(get: { permissionPrompt != nil }, set: { if !$0 { permissionPrompt = nil } })) {
            Button("Continue") { if let r = permissionPrompt { permissionPrompt = nil; Task { await remind(r, ask: true) } } }
            Button("Not now", role: .cancel) { permissionPrompt = nil }
        } message: { Text("Reminders appear as a notification shortly before a show starts. iOS needs your permission to show it.") }
        .alert("Notifications are off", isPresented: $permissionDenied) {
            Button("Open Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
            Button("OK", role: .cancel) {}
        } message: { Text("Reminders need notification permission. You can turn it on in the iOS Settings app.") }
    }

    // MARK: pieces

    private var nowMs: Int64 { Int64(tick.timeIntervalSince1970 * 1000) }
    private var range: GridRange? { GridRange.of(model.snapshot.guide.programs, now: nowMs) }

    private var shown: [Channel] {
        switch filter {
        case .all: return GuideLogic.sorted(model.channels, model.cu)
        case .favorites: return GuideLogic.favorites(model.channels, model.cu)
        case .category(let c): return GuideLogic.byCategory(model.channels, model.cu, category: c)
        }
    }

    private var categories: [String] {
        var seen = Set<String>(); var out: [String] = []
        for c in model.channels { if let cat = GuideLogic.category(c, model.cu), seen.insert(cat.lowercased()).inserted { out.append(cat) } }
        return out.sorted()
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", .all)
                chip("★ Favorites", .favorites)
                ForEach(categories, id: \.self) { chip($0, .category($0)) }
            }.padding(.horizontal).padding(.vertical, 6)
        }
    }

    private func chip(_ title: String, _ f: GuideFilter) -> some View {
        let on = filter == f || { if case .category(let a) = filter, case .category(let b) = f { return a.lowercased() == b.lowercased() }; return false }()
        return Button { filter = f } label: {
            Text(title).font(.subheadline.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 7)
                .background(on ? Palette.primaryContainer : Palette.surfaceVariant, in: Capsule())
                .overlay(Capsule().stroke(on ? Palette.primary : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain).accessibilityAddTraits(on ? [.isSelected] : []).accessibilityLabel(title.replacingOccurrences(of: "★ ", with: ""))
    }

    @ViewBuilder private var statusBanners: some View {
        if model.isSample { SampleBadge().padding(.horizontal).padding(.bottom, 4) }
        if let err = model.refreshError {
            Text("\(err) Showing your saved guide.").font(.footnote).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.warningContainer).foregroundStyle(Palette.warning)
        }
        if model.refreshing { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 2) }
    }

    private var navBar: some View {
        HStack(spacing: 4) {
            Button { command = (.earlier, UUID()) } label: { Label("Earlier", systemImage: "chevron.left") }.disabled(!canEarlier)
            Button("Now") { command = (.now, UUID()) }
            Button { command = (.later, UUID()) } label: { HStack { Text("Later"); Image(systemName: "chevron.right") } }.disabled(!canLater)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                if let end = model.dataEnd { Text("Listings end \(Fmt.dayTime.string(from: end))") }
                if let u = model.lastUpdated { Text("Updated \(Fmt.full.string(from: u))") } else { Text("Never updated") }
            }.font(.caption2).foregroundStyle(Palette.onSurfaceVariant)
        }
        .buttonStyle(.bordered).controlSize(.small).padding(.horizontal).padding(.bottom, 4)
    }

    @ViewBuilder private var content: some View {
        if !model.hasGuide {
            emptyState
        } else if shown.isEmpty {
            VStack { Spacer(); Text(filter == .favorites ? "No favorite channels yet. Tap a channel and choose Favorite." : "No channels here yet. Tap a channel to give it this category.")
                .multilineTextAlignment(.center).padding(); Spacer() }.frame(maxWidth: .infinity)
        } else if let r = range {
            GuideGrid(channels: shown, programs: Dictionary(grouping: model.snapshot.guide.programs, by: \.channelId), range: r, now: nowMs, cu: model.cu,
                      duplicates: Set(model.duplicateNumbers.values.flatMap { $0 }.map(\.id)), reminderKeys: model.reminderKeys,
                      command: $command, canEarlier: $canEarlier, canLater: $canLater, jumpToMillis: jump,
                      onProgram: { c, p in detail = ProgramRef(channel: c, program: p) }, onChannel: { editing = $0 },
                      onRefresh: { await model.refresh() })
        } else { emptyState }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            if model.refreshing { ProgressView(); Text("Downloading the guide for \(model.market?.label ?? "your market")…") }
            else if let err = model.refreshError {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(Palette.warning)
                Text(err); Text("There is no saved guide on this device yet.").font(.footnote)
                Button("Try again") { Task { await model.refresh() } }.buttonStyle(.borderedProminent)
            } else {
                Text("No guide has been downloaded yet.")
                Button("Download guide") { Task { await model.refresh() } }.buttonStyle(.borderedProminent)
            }
            Spacer()
        }.padding().frame(maxWidth: .infinity)
    }

    // MARK: actions

    private func openFromNotification(_ key: String?) {
        guard let key else { return }
        if let p = model.snapshot.guide.programs.first(where: { $0.key == key }), let ch = model.channels.first(where: { $0.id == p.channelId }) {
            path = []
            jump = p.startMillis
            detail = ProgramRef(channel: ch, program: p)
            model.openProgramKey = nil
        } else if model.hasGuide { model.openProgramKey = nil }
    }

    private func requestReminder(_ ref: ProgramRef) {
        Task {
            let r = await model.addReminder(ref.program, channelName: ref.channel.name, askPermission: false)
            switch r {
            case .needsPermission: permissionPrompt = ref
            case .denied: permissionDenied = true
            case .alreadyStarted: model.toast = Toast(text: "That show has already started.")
            case .set: break
            }
        }
    }

    private func remind(_ ref: ProgramRef, ask: Bool) async {
        let r = await model.addReminder(ref.program, channelName: ref.channel.name, askPermission: ask)
        if r == .denied { permissionDenied = true }
    }
}

struct ProgramRef: Identifiable, Hashable { let channel: Channel; let program: Program; var id: String { program.key } }

struct ToastView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let t = model.toast {
            Text(t.text).font(.subheadline).padding(12).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding().transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: t.id) {
                    UIAccessibility.post(notification: .announcement, argument: t.text)
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if model.toast?.id == t.id { withAnimation { model.toast = nil } }
                }
        }
    }
}
