//
//  Item.swift
//  WateringReminder
//
//  Created by Kellen O'Connor on 4/15/26.
//

import Foundation
import SwiftData
import UserNotifications

// MARK: - Schema versioning

enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Item.self] }

    @Model
    final class Item {
        var timestamp: Date
        init(timestamp: Date) {
            self.timestamp = timestamp
        }
    }
}

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [Plant.self] }
}

enum PlantMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self,
        willMigrate: { context in
            // Delete any leftover Item rows from the template — they aren't meaningful plant data.
            let items = try context.fetch(FetchDescriptor<SchemaV1.Item>())
            for item in items {
                context.delete(item)
            }
            try context.save()
        },
        didMigrate: nil
    )
}

// MARK: - Plant model

@Model
final class Plant {
    var name: String
    var wateringDates: [Date]
    var reminderEnabled: Bool
    var reminderDays: Int
    // Stable ID used as the local notification identifier
    var notificationID: String

    init(name: String) {
        self.name = name
        self.wateringDates = []
        self.reminderEnabled = false
        self.reminderDays = 7
        self.notificationID = UUID().uuidString
    }

    var lastWatered: Date? {
        wateringDates.max()
    }

    var nextReminderDate: Date? {
        guard reminderEnabled, reminderDays > 0 else { return nil }
        let base = lastWatered ?? Date()
        return Calendar.current.date(byAdding: .day, value: reminderDays, to: base)
    }

    var reminderIsOverdue: Bool {
        guard let next = nextReminderDate else { return false }
        return next < Date()
    }

    func logWatering(on date: Date = Date()) {
        wateringDates.append(date)
    }
}

// MARK: - Notification manager

enum NotificationManager {

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    /// Schedule (or reschedule) the reminder for a plant based on its current settings and last watering.
    static func scheduleReminder(for plant: Plant) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [plant.notificationID])

        guard plant.reminderEnabled, plant.reminderDays > 0,
              let fireDate = plant.nextReminderDate else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(plant.name) needs water!"
        content.body = "It's been \(plant.reminderDays) day\(plant.reminderDays == 1 ? "" : "s") — time to water \(plant.name)."
        content.sound = .default

        let trigger: UNNotificationTrigger
        if fireDate > Date() {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        } else {
            // Already overdue: fire in 5 seconds so the user sees it right away
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        }

        let request = UNNotificationRequest(identifier: plant.notificationID, content: content, trigger: trigger)
        center.add(request)
    }

    static func cancelReminder(for plant: Plant) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [plant.notificationID])
    }
}
