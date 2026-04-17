//
//  MostOverdueWidget.swift
//  WateringReminderWidget
//
//  Home-screen widget that surfaces the plant most in need of water.
//  Reads an App Group-shared JSON snapshot populated by the main app.
//

import WidgetKit
import SwiftUI

struct MostOverdueEntry: TimelineEntry {
    let date: Date
    let plant: PlantSnapshot?
}

struct MostOverdueProvider: TimelineProvider {
    func placeholder(in context: Context) -> MostOverdueEntry {
        MostOverdueEntry(
            date: Date(),
            plant: PlantSnapshot(
                notificationID: "preview",
                name: "Monstera",
                lastWatered: Date().addingTimeInterval(-86400 * 9),
                nextReminderDate: Date().addingTimeInterval(-86400 * 2),
                reminderEnabled: true,
                photoFileName: nil
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (MostOverdueEntry) -> Void) {
        completion(MostOverdueEntry(date: Date(), plant: SharedSnapshotReader.mostOverdue()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MostOverdueEntry>) -> Void) {
        let entry = MostOverdueEntry(date: Date(), plant: SharedSnapshotReader.mostOverdue())
        // Refresh every hour; the main app also reloads timelines on data change.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct MostOverdueWidget: Widget {
    let kind = "MostOverdueWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MostOverdueProvider()) { entry in
            MostOverdueView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next to Water")
        .description("Shows the plant that needs water most.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MostOverdueView: View {
    let entry: MostOverdueEntry

    var body: some View {
        if let plant = entry.plant {
            plantView(plant)
        } else {
            emptyView
        }
    }

    @ViewBuilder
    private func plantView(_ plant: PlantSnapshot) -> some View {
        let statusText = status(for: plant)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .foregroundStyle(statusColor(for: plant))
                Text("Next to water")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(plant.name)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(statusColor(for: plant))
        }
        .widgetURL(URL(string: "wateringreminder://plant/\(plant.notificationID)"))
    }

    private var emptyView: some View {
        VStack(spacing: 4) {
            Image(systemName: "leaf.fill")
                .foregroundStyle(.green.opacity(0.7))
            Text("No plants yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func status(for plant: PlantSnapshot) -> String {
        guard plant.reminderEnabled, let next = plant.nextReminderDate else {
            if let last = plant.lastWatered {
                let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
                return days == 0 ? "Watered today" : "Watered \(days)d ago"
            }
            return "Never watered"
        }
        let cal = Calendar.current
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: Date()),
                                      to: cal.startOfDay(for: next)).day ?? 0
        if days < 0 {
            return "\(-days) day\(days == -1 ? "" : "s") overdue"
        } else if days == 0 {
            return "Due today"
        } else {
            return "Due in \(days)d"
        }
    }

    private func statusColor(for plant: PlantSnapshot) -> Color {
        guard plant.reminderEnabled, let next = plant.nextReminderDate else { return .secondary }
        if next < Date() { return .red }
        let diff = next.timeIntervalSince(Date())
        if diff < 24 * 3600 { return .orange }
        return .blue
    }
}
