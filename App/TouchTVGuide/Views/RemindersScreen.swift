import SwiftUI
import TVGuideCore
import UIKit

struct RemindersScreen: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List {
            if model.notificationState != .allowed {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(model.notificationState == .denied ? "Notifications are off, so reminders can't alert you." : "Notifications haven't been allowed yet. You'll be asked when you set your first reminder.",
                              systemImage: "bell.slash").foregroundStyle(Palette.warning)
                        if model.notificationState == .denied {
                            Button("Open Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                        }
                    }
                }
            }
            if model.snapshot.reminders.isEmpty {
                Text("No reminders. Open a program and tap Remind me.").foregroundStyle(Palette.onSurfaceVariant)
            }
            ForEach(model.snapshot.reminders) { r in
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.title).font(.headline)
                    Text("\(r.channelName) · \(Fmt.dayTime(r.startMillis))").font(.footnote).foregroundStyle(Palette.onSurfaceVariant)
                }
                .accessibilityElement(children: .combine)
                .swipeActions { Button("Cancel", role: .destructive) { model.cancelReminder(r.programKey) } }
                .accessibilityAction(named: "Cancel reminder") { model.cancelReminder(r.programKey) }
            }
        }
        .navigationTitle("Reminders")
        .task { await model.refreshNotificationState() }
    }
}
