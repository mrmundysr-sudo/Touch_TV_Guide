import SwiftUI
import TVGuideCore

enum GridMetrics {
    static let pointsPerMinute: CGFloat = 4
    static let slotMinutes = 30
    static var slotWidth: CGFloat { pointsPerMinute * CGFloat(slotMinutes) }
    static let channelWidth: CGFloat = 108
    static let headerHeight: CGFloat = 40
}

func floorSlot(_ ms: Int64) -> Int64 { let s = Int64(GridMetrics.slotMinutes) * 60_000; return ms - ((ms % s) + s) % s }
func ceilSlot(_ ms: Int64) -> Int64 { floorSlot(ms + Int64(GridMetrics.slotMinutes) * 60_000 - 1) }

/// Visible range: from at most 3 h before now (never before the data begins) to the end of the data.
struct GridRange: Equatable {
    let start: Int64, end: Int64
    var minutes: Int { Int((end - start) / 60_000) }
    var slotCount: Int { minutes / GridMetrics.slotMinutes }
    var contentWidth: CGFloat { GridMetrics.channelWidth + CGFloat(minutes) * GridMetrics.pointsPerMinute }
    func x(_ ms: Int64) -> CGFloat { GridMetrics.channelWidth + CGFloat(ms - start) / 60_000 * GridMetrics.pointsPerMinute }
    func slotIndex(for ms: Int64) -> Int { max(0, min(slotCount - 1, Int((ms - start) / (Int64(GridMetrics.slotMinutes) * 60_000)))) }

    static func of(_ programs: [Program], now: Int64) -> GridRange? {
        guard let dataStart = programs.map(\.startMillis).min() else { return nil }
        let dataEnd = GuideLogic.dataEnd(programs)
        let s = floorSlot(min(max(dataStart, now - 3 * 3_600_000), dataEnd - 1))
        let e = ceilSlot(dataEnd)
        return e > s ? GridRange(start: s, end: e) : nil
    }
}

/// Horizontal scroll offset, shared so only the pinned cells re-render while scrolling.
final class GridScroll: ObservableObject { @Published var x: CGFloat = 0 }

private struct OffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

enum GridCommand: Equatable { case earlier, later, now }

struct GuideGrid: View {
    let channels: [Channel]
    let programs: [String: [Program]]
    let range: GridRange
    let now: Int64
    let cu: Customization
    let duplicates: Set<String>            // channel ids with a duplicate number
    let reminderKeys: Set<String>
    @Binding var command: (GridCommand, UUID)?
    @Binding var canEarlier: Bool
    @Binding var canLater: Bool
    var jumpToMillis: Int64?
    let onProgram: (Channel, Program) -> Void
    let onChannel: (Channel) -> Void
    let onRefresh: () async -> Void

    @StateObject private var scroll = GridScroll()
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 66

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 0) {
                        TimeHeader(range: range, scroll: scroll)
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(channels) { ch in
                                    ChannelRow(channel: ch, programs: programs[ch.id] ?? [], range: range, now: now, cu: cu, rowHeight: rowHeight,
                                               duplicate: duplicates.contains(ch.id), reminderKeys: reminderKeys, scroll: scroll,
                                               onProgram: onProgram, onChannel: onChannel)
                                }
                            }
                        }
                        .refreshable { await onRefresh() }
                        .frame(width: range.contentWidth, height: max(0, geo.size.height - GridMetrics.headerHeight))
                        .overlay(alignment: .topLeading) {
                            if now >= range.start && now <= range.end {
                                Rectangle().fill(Palette.primary.opacity(0.75)).frame(width: 2).offset(x: range.x(now) - 1).allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .frame(width: range.contentWidth)
                    .overlay(alignment: .topLeading) {
                        // Scroll targets: one per slot, at x = slot offset, so `.leading` puts that slot right next to the
                        // pinned channel column.
                        HStack(spacing: 0) {
                            ForEach(0..<range.slotCount, id: \.self) { i in Color.clear.frame(width: GridMetrics.slotWidth, height: 1).id(i) }
                        }.allowsHitTesting(false).accessibilityHidden(true)
                    }
                    .background(GeometryReader { g in
                        Color.clear.preference(key: OffsetKey.self, value: -g.frame(in: .named("gridH")).minX)
                    })
                }
                .coordinateSpace(name: "gridH")
                .onPreferenceChange(OffsetKey.self) { x in
                    scroll.x = x
                    canEarlier = x > 1
                    canLater = x + geo.size.width < range.contentWidth - 1
                }
                .onChange(of: command?.1) { _, _ in
                    guard let (c, _) = command else { return }
                    let left = Int(max(0, scroll.x) / GridMetrics.slotWidth)
                    let target: Int
                    switch c {
                    case .earlier: target = max(0, left - 6)
                    case .later: target = min(range.slotCount - 1, left + 6)
                    case .now: target = range.slotIndex(for: now - 20 * 60_000)
                    }
                    withAnimation { proxy.scrollTo(target, anchor: .leading) }
                }
                .onChange(of: jumpToMillis) { _, ms in
                    if let ms { withAnimation { proxy.scrollTo(range.slotIndex(for: ms - 20 * 60_000), anchor: .leading) } }
                }
                .task(id: range) {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    proxy.scrollTo(range.slotIndex(for: now - 20 * 60_000), anchor: .leading)
                }
            }
        }
    }
}

private struct TimeHeader: View {
    let range: GridRange
    @ObservedObject var scroll: GridScroll

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Palette.surfaceVariant)
            ForEach(0..<range.slotCount, id: \.self) { i in
                let t = range.start + Int64(i) * Int64(GridMetrics.slotMinutes) * 60_000
                let midnight = Calendar.current.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(t) / 1000)) == 0
                    && Calendar.current.component(.minute, from: Date(timeIntervalSince1970: TimeInterval(t) / 1000)) == 0
                Text(i == 0 || midnight ? Fmt.dayTime(t) : Fmt.time(t))
                    .font(.caption.weight(.medium)).lineLimit(1).fixedSize()
                    .frame(width: GridMetrics.slotWidth, height: GridMetrics.headerHeight, alignment: .leading)
                    .padding(.leading, 6)
                    .overlay(alignment: .leading) { Rectangle().fill(Palette.outline.opacity(0.4)).frame(width: 1) }
                    .offset(x: GridMetrics.channelWidth + CGFloat(i) * GridMetrics.slotWidth)
                    .accessibilityHidden(true)
            }
            Text("Channel").font(.caption.weight(.semibold))
                .frame(width: GridMetrics.channelWidth, height: GridMetrics.headerHeight)
                .background(Palette.surfaceVariant)
                .offset(x: scroll.x)
                .accessibilityHidden(true)
        }
        .frame(width: range.contentWidth, height: GridMetrics.headerHeight, alignment: .topLeading)
        .clipped()
    }
}

private struct ChannelRow: View {
    let channel: Channel
    let programs: [Program]
    let range: GridRange
    let now: Int64
    let cu: Customization
    let rowHeight: CGFloat
    let duplicate: Bool
    let reminderKeys: Set<String>
    @ObservedObject var scroll: GridScroll
    let onProgram: (Channel, Program) -> Void
    let onChannel: (Channel) -> Void

    var body: some View {
        let visible = GuideLogic.window(programs, channelId: channel.id, from: range.start, to: range.end)
        ZStack(alignment: .topLeading) {
            if visible.isEmpty {
                Text("No listings").font(.subheadline).foregroundStyle(Palette.onSurfaceVariant)
                    .frame(height: rowHeight).padding(.leading, GridMetrics.channelWidth + 12)
            }
            ForEach(visible) { p in
                let s = max(p.startMillis, range.start), e = min(p.stopMillis, range.end)
                ProgramCell(program: p, channel: channel, number: GuideLogic.effectiveNumber(channel, cu), airing: now >= p.startMillis && now < p.stopMillis,
                            favorite: cu.favoritePrograms.contains(p.key), reminder: reminderKeys.contains(p.key), onTap: { onProgram(channel, p) })
                    .frame(width: max(24, CGFloat(e - s) / 60_000 * GridMetrics.pointsPerMinute - 2), height: rowHeight - 2)
                    .offset(x: range.x(s) + 1, y: 1)
            }
            ChannelCell(channel: channel, number: GuideLogic.effectiveNumber(channel, cu), favorite: cu.favoriteChannels.contains(channel.id),
                        duplicate: duplicate, rowHeight: rowHeight, onTap: { onChannel(channel) })
                .offset(x: scroll.x)
        }
        .frame(width: range.contentWidth, height: rowHeight, alignment: .topLeading)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.outline.opacity(0.25)).frame(height: 0.5) }
    }
}

private struct ChannelCell: View {
    let channel: Channel, number: String, favorite: Bool, duplicate: Bool, rowHeight: CGFloat
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if let s = channel.logoURL, let url = URL(string: s) {
                    AsyncImage(url: url) { img in img.resizable().scaledToFit() } placeholder: { Color.clear }
                        .frame(width: 26, height: 26).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text(number).font(.subheadline.weight(.bold)).lineLimit(1)
                        if favorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(Palette.primary) }
                        if duplicate { Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(Palette.warning) }
                    }
                    Text(channel.name).font(.caption2).lineLimit(2).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(width: GridMetrics.channelWidth, height: rowHeight, alignment: .leading)
            .background(Palette.surface)
            .overlay(alignment: .trailing) { Rectangle().fill(Palette.outline.opacity(0.3)).frame(width: 0.5) }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Channel \(number), \(channel.name)")
        .accessibilityValue([favorite ? "Favorite" : nil, duplicate ? "Number shared with another channel" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Double tap to edit number, category or favorite")
    }
}

private struct ProgramCell: View {
    let program: Program, channel: Channel, number: String, airing: Bool, favorite: Bool, reminder: Bool
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    if favorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(Palette.primary) }
                    if reminder { Image(systemName: "bell.fill").font(.caption2) }
                    Text(program.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                Text(Fmt.range(program)).font(.caption).foregroundStyle(Palette.onSurfaceVariant).lineLimit(1)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(airing ? Palette.primaryContainer : Palette.secondaryContainer, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(program.title), \(Fmt.range(program)), channel \(number) \(channel.name)")
        .accessibilityValue([airing ? "On now" : nil, favorite ? "Favorite" : nil, reminder ? "Reminder set" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Double tap for details")
    }
}
