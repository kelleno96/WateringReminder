//
//  WateringSnapshotCache.swift
//  WateringReminder
//
//  Lightweight JSON snapshot of plant state written to an App Group-shared
//  UserDefaults so the home-screen widget can read it without touching
//  SwiftData. The main app refreshes the snapshot on launch and whenever
//  plant state changes.
//

import Foundation
import SwiftData
import WidgetKit

struct PlantSnapshot: Codable, Hashable {
    var notificationID: String
    var name: String
    var lastWatered: Date?
    var nextReminderDate: Date?
    var reminderEnabled: Bool
    var photoFileName: String?
}

enum WateringSnapshotCache {

    /// App Group identifier — configure in Signing & Capabilities on both
    /// the main app target and the Widget extension target, then add the
    /// same ID to both entitlements files.
    static let appGroupID = "group.OConnorK.WateringReminder"

    static let snapshotKey = "plantsSnapshotV1"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func write(plants: [Plant]) {
        let snapshots = plants.map { plant in
            PlantSnapshot(
                notificationID: plant.notificationID,
                name: plant.name,
                lastWatered: plant.lastWatered,
                nextReminderDate: plant.nextReminderDate,
                reminderEnabled: plant.reminderEnabled,
                photoFileName: plant.displayPhotoFileName
            )
        }
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        defaults?.set(data, forKey: snapshotKey)

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func read() -> [PlantSnapshot] {
        guard let data = defaults?.data(forKey: snapshotKey) else { return [] }
        return (try? JSONDecoder().decode([PlantSnapshot].self, from: data)) ?? []
    }

    /// Returns the single plant most in need of attention (biggest overdue
    /// margin first; falls back to most-recently-watered if nothing is
    /// overdue).
    static func mostOverdue(from snapshots: [PlantSnapshot]) -> PlantSnapshot? {
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
