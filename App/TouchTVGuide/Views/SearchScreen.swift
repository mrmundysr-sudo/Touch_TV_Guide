import SwiftUI
import TVGuideCore

struct SearchScreen: View {
    @EnvironmentObject var model: AppModel
    let onProgram: (ProgramRef) -> Void
    @State private var query = ""

    var body: some View {
        let result = GuideLogic.search(model.snapshot.guide, model.cu, query: query)
        let byId = Dictionary(model.channels.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        List {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Type to search channels and programs.").foregroundStyle(Palette.onSurfaceVariant)
            } else if result.channels.isEmpty && result.programs.isEmpty {
                Text("Nothing found for “\(query.trimmingCharacters(in: .whitespaces))”.").foregroundStyle(Palette.onSurfaceVariant)
            }
            if !result.channels.isEmpty {
                Section("Channels") {
                    ForEach(result.channels) { c in
                        let next = model.snapshot.guide.programs.filter { $0.channelId == c.id && $0.stopMillis > model.nowMillis }.min { $0.startMillis < $1.startMillis }
                        Button { if let next { onProgram(ProgramRef(channel: c, program: next)) } } label: {
                            VStack(alignment: .leading) {
                                Text("\(GuideLogic.effectiveNumber(c, model.cu))  \(c.name)").bold()
                                Text(next.map { "\($0.title) · \(Fmt.time($0.startMillis))" } ?? "No listings").font(.footnote).foregroundStyle(Palette.onSurfaceVariant)
                            }
                        }.disabled(next == nil)
                    }
                }
            }
            if !result.programs.isEmpty {
                Section("Programs") {
                    ForEach(result.programs.prefix(200)) { p in
                        if let c = byId[p.channelId] {
                            Button { onProgram(ProgramRef(channel: c, program: p)) } label: {
                                VStack(alignment: .leading) {
                                    Text(p.title)
                                    Text("\(GuideLogic.effectiveNumber(c, model.cu)) \(c.name) · \(Fmt.dayTime(p.startMillis))").font(.footnote).foregroundStyle(Palette.onSurfaceVariant)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Channel, number, show or description")
        .autocorrectionDisabled()
    }
}
