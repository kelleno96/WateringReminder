//
//  SharedSnapshot.swift
//  WateringReminderWidget
//
//  Duplicated declarations of the snapshot types so the widget target can
//  read the App Group-shared UserDefaults without depending on the main
//  app's SwiftData stack. Kept in sync with WateringSnapshotCache.swift in
//  the main app target.
//

import Foundation

struct PlantSnapshot: Codable, Hashable {
    var notificationID: String
    var name: String
    var lastWatered: Date?
    var nextReminderDate: Date?
    var reminderEnabled: Bool
    var photoFileName: String?
}

enum SharedSnapshotReader {

    static let appGroupID = "group.OConnorK.WateringReminder"
    static let snapshotKey = "plantsSnapshotV1"

    static func read() -> [PlantSnapshot] {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: snapshotKey) else { return [] }
        return (try? JSONDecoder().decode([PlantSnapshot].self, from: data)) ?? []
    }

    static func mostOverdue() -> PlantSnapshot? {
        let snapshots = read()
        let now = Date()
        let overdue = snapshots.filter { snap in
            guard snap.reminderEnabled, let next = snap.nextReminderDate else { return false }
            return next < now
        }
        if let worst = overdue.min(by: {
            ($0.nextReminderDate ?? .distantFuture) < ($1.nextReminderDate ?? .distantFuture)
        }) {
            return worst
        }
        return snapshots.min(by: {
            ($0.nextReminderDate ?? .distantFuture) < ($1.nextReminderDate ?? .distantFuture)
        })
    }
}
