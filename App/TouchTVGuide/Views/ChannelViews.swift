import SwiftUI
import TVGuideCore

/// Edit one channel: number, category, favorite.
struct ChannelEditView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let channel: Channel
    @State private var number = ""
    @State private var category = ""

    private var clash: Channel? {
        let n = number.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return nil }
        return model.channels.first { $0.id != channel.id && GuideLogic.effectiveNumber($0, model.cu) == n }
    }
    private var fav: Bool { model.cu.favoriteChannels.contains(channel.id) }
    private var existingCategories: [String] {
        Array(Set(model.channels.compactMap { GuideLogic.category($0, model.cu) })).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Channel number") {
                    TextField("Number (empty shows ?)", text: $number).keyboardType(.decimalPad)
                    if let clash { Label("\(clash.name) already uses this number and will show “?” instead.", systemImage: "exclamationmark.triangle").foregroundStyle(Palette.warning).font(.footnote) }
                    else { Text("Edit the number to match your own lineup.").font(.footnote).foregroundStyle(Palette.onSurfaceVariant) }
                    if let feed = channel.feedNumber, number != feed { Button("Use the guide's number (\(feed))") { number = feed } }
                }
                Section("Category") {
                    TextField("Category, for example News", text: $category)
                    if !existingCategories.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack { ForEach(existingCategories, id: \.self) { c in Button(c) { category = c }.buttonStyle(.bordered).controlSize(.small) } }
                        }
                    }
                    Text("Shows up as a filter at the top of the guide.").font(.footnote).foregroundStyle(Palette.onSurfaceVariant)
                }
                Section {
                    Button { model.toggleFavoriteChannel(channel.id) } label: { Label(fav ? "Remove from favorites" : "Add to favorites", systemImage: fav ? "star.slash" : "star") }
                }
            }
            .navigationTitle(channel.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.setNumber(channel.id, number: number.trimmingCharacters(in: .whitespaces))
                        model.setCategory(channel.id, category: category)
                        dismiss()
                    }
                }
            }
            .onAppear {
                let n = GuideLogic.effectiveNumber(channel, model.cu); number = n == unknownNumber ? "" : n
                category = GuideLogic.category(channel, model.cu) ?? ""
            }
        }
    }
}

/// Manage Channels: drag to reorder, tap to edit, restore the lineup defaults.
struct ChannelManagerScreen: View {
    @EnvironmentObject var model: AppModel
    @State private var order: [Channel] = []
    @State private var editing: Channel?
    @State private var confirmRestore = false

    var body: some View {
        List {
            if !model.duplicateNumbers.isEmpty {
                Section {
                    ForEach(model.duplicateNumbers.keys.sorted(), id: \.self) { n in
                        Label("\(n) is shown by \(model.duplicateNumbers[n]!.map(\.name).joined(separator: " and ")). The guide data legitimately contains both; edit a number if you want them apart.", systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(Palette.warning)
                    }
                } header: { Text("Shared numbers") }
            }
            Section {
                ForEach(order) { c in
                    let n = GuideLogic.effectiveNumber(c, model.cu)
                    let dup = model.duplicateNumbers[n] != nil && n != unknownNumber
                    Button { editing = c } label: {
                        HStack {
                            Text(n).bold().frame(minWidth: 48, alignment: .leading)
                            VStack(alignment: .leading) {
                                Text(c.name)
                                if let cat = GuideLogic.category(c, model.cu) { Text(cat).font(.caption).foregroundStyle(Palette.onSurfaceVariant) }
                            }
                            Spacer()
                            if dup { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning) }
                            if model.cu.favoriteChannels.contains(c.id) { Image(systemName: "star.fill").foregroundStyle(Palette.primary) }
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Channel \(n), \(c.name)")
                    .accessibilityValue(dup ? "Number shared with another channel" : "")
                    .accessibilityHint("Double tap to edit. Use the actions rotor to move.")
                }
                .onMove { from, to in
                    order.move(fromOffsets: from, toOffset: to)
                    model.setOrder(order.map(\.id))
                }
            } header: { Text("Channels (drag to reorder)") } footer: {
                Text("A custom order is kept until you restore the lineup defaults. Without one, channels are sorted by number with unknown (?) numbers last.")
            }
            Section {
                Button("Restore lineup defaults", role: .destructive) { confirmRestore = true }
            } footer: { Text("Clears your channel numbers, categories and order. Favorites are kept.") }
        }
        .navigationTitle("Manage channels")
        .toolbar { EditButton() }
        .onAppear { order = GuideLogic.sorted(model.channels, model.cu) }
        .onChange(of: model.cu) { _, _ in if order.map(\.id) != GuideLogic.sorted(model.channels, model.cu).map(\.id) { order = GuideLogic.sorted(model.channels, model.cu) } }
        .sheet(item: $editing) { ChannelEditView(channel: $0) }
        .confirmationDialog("Restore lineup defaults?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore defaults", role: .destructive) { model.restoreDefaults() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This clears the channel numbers, categories and order you set. Favorites are kept.") }
    }

}
