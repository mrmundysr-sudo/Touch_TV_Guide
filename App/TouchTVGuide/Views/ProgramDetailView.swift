import SwiftUI
import TVGuideCore

struct ProgramDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let ref: ProgramRef
    let onRemind: (ProgramRef) -> Void

    private var p: Program { ref.program }
    private var hasReminder: Bool { model.reminderKeys.contains(p.key) }
    private var isFav: Bool { model.cu.favoritePrograms.contains(p.key) }
    private var canRemind: Bool { ReminderLogic.canRemind(p, now: model.nowMillis) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(p.title).font(.title2.weight(.bold))
                    Text("\(GuideLogic.effectiveNumber(ref.channel, model.cu)) · \(ref.channel.name)").font(.headline).foregroundStyle(Palette.primary)
                    Text("\(Fmt.dayTime(p.startMillis)) – \(Fmt.time(p.stopMillis))  (\(p.durationMinutes) min)")
                    if model.nowMillis >= p.startMillis && model.nowMillis < p.stopMillis { Text("On now").foregroundStyle(Palette.primary).bold() }
                    Text(p.description ?? "No description available for this program.").foregroundStyle(p.description == nil ? Palette.onSurfaceVariant : .primary)
                    HStack {
                        Button { model.toggleFavoriteProgram(p) } label: { Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "heart.fill" : "heart") }
                            .buttonStyle(.bordered)
                        if hasReminder {
                            Button { model.cancelReminder(p.key) } label: { Label("Cancel reminder", systemImage: "bell.slash") }.buttonStyle(.borderedProminent)
                        } else {
                            Button { onRemind(ref) } label: { Label("Remind me", systemImage: "bell") }.buttonStyle(.borderedProminent).disabled(!canRemind)
                        }
                    }.padding(.top, 6)
                    if !hasReminder && !canRemind { Text("This program has already started, so a reminder can't be set.").font(.footnote) }
                    if hasReminder { Text("You'll be notified \(model.settings.leadMinutes) minutes before it starts.").font(.footnote).foregroundStyle(Palette.onSurfaceVariant) }
                }.padding()
            }
            .navigationTitle("Details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
