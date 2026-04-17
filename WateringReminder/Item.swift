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

    @Model
    final class Plant {
        var name: String
        var wateringDates: [Date]
        var reminderEnabled: Bool
        var reminderDays: Int
        var notificationID: String

        init(name: String) {
            self.name = name
            self.wateringDates = []
            self.reminderEnabled = false
            self.reminderDays = 7
            self.notificationID = UUID().uuidString
        }
    }
}

enum SchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] { [Plant.self] }

    // Pinned V3 Plant shape so SwiftData can read legacy stores correctly
    // while the top-level Plant evolves in V4.
    @Model
    final class Plant {
        var name: String
        var wateringDates: [Date]
        var reminderEnabled: Bool
        var reminderDays: Int
        var notificationID: String
        var photoFileName: String?

        init(name: String) {
            self.name = name
            self.wateringDates = []
            self.reminderEnabled = false
            self.reminderDays = 7
            self.notificationID = UUID().uuidString
            self.photoFileName = nil
        }
    }
}

enum SchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] { [Plant.self, PhotoEntry.self] }
}

enum PlantMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4]
    }

    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self,
        willMigrate: { context in
            let items = try context.fetch(FetchDescriptor<SchemaV1.Item>())
            for item in items {
                context.delete(item)
            }
            try context.save()
        },
        didMigrate: nil
    )

    // SchemaV2.Plant → SchemaV3.Plant adds `photoFileName: String?`
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SchemaV2.self,
        toVersion: SchemaV3.self
    )

    // SchemaV3.Plant → Plant (V4) adds `notes`, `snoozedUntil`,
    // `speciesIdentifier`, and `photos` relationship — all with defaults.
    // Legacy `photoFileName` values are preserved and surfaced through the
    // model's computed `displayPhotoFileName` until the next capture writes a
    // PhotoEntry.
    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: SchemaV3.self,
        toVersion: SchemaV4.self
    )
}

// MARK: - Plant model (V4 — current)

@Model
final class Plant {
    var name: String
    var wateringDates: [Date]
    var reminderEnabled: Bool
    var reminderDays: Int
    // Stable ID used as the local notification identifier
    var notificationID: String
    // Legacy single-photo field. Still populated for pre-V4 records and as a
    // fallback when `photos` is empty. New captures write PhotoEntry rows.
    var photoFileName: String?

    // V4 additions
    var notes: String = ""
    var snoozedUntil: Date?
    var speciesIdentifier: String?
    @Relationship(deleteRule: .cascade, inverse: \PhotoEntry.plant)
    var photos: [PhotoEntry] = []

    init(name: String) {
        self.name = name
        self.wateringDates = []
        self.reminderEnabled = false
        self.reminderDays = 7
        self.notificationID = UUID().uuidString
        self.photoFileName = nil
        self.notes = ""
        self.snoozedUntil = nil
        self.speciesIdentifier = nil
        self.photos = []
    }

    var lastWatered: Date? {
        wateringDates.max()
    }

    var nextReminderDate: Date? {
        guard reminderEnabled, reminderDays > 0 else { return nil }
        let base = lastWatered ?? Date()
        let scheduled = Calendar.current.date(byAdding: .day, value: reminderDays, to: base)
        if let snooze = snoozedUntil, snooze > Date() {
            guard let scheduled else { return snooze }
            return max(scheduled, snooze)
        }
        return scheduled
    }

    var reminderIsOverdue: Bool {
        guard let next = nextReminderDate else { return false }
        return next < Date()
    }

    /// Photos sorted newest first. Falls back to the legacy `photoFileName` as
    /// a synthetic single-entry list when no `PhotoEntry` records exist yet.
    var photosNewestFirst: [PhotoReference] {
        if !photos.isEmpty {
            return photos
                .sorted { $0.takenAt > $1.takenAt }
                .map { PhotoReference(fileName: $0.fileName, takenAt: $0.takenAt, entry: $0) }
        }
        if let legacy = photoFileName {
            return [PhotoReference(fileName: legacy, takenAt: lastWatered ?? Date(), entry: nil)]
        }
        return []
    }

    /// Filename of the most recent photo (new relationship or legacy).
    var displayPhotoFileName: String? {
        if let latest = photos.max(by: { $0.takenAt < $1.takenAt }) {
            return latest.fileName
        }
        return photoFileName
    }

    func logWatering(on date: Date = Date()) {
        wateringDates.append(date)
        snoozedUntil = nil
    }
}

// MARK: - PhotoEntry (V4)

@Model
final class PhotoEntry {
    var fileName: String
    var takenAt: Date
    var plant: Plant?

    init(fileName: String, takenAt: Date = Date()) {
        self.fileName = fileName
        self.takenAt = takenAt
    }
}

/// Lightweight value type used by views: works for both the new `PhotoEntry`
/// relationship and the legacy single-file field.
struct PhotoReference: Identifiable, Hashable {
    let fileName: String
    let takenAt: Date
    /// Non-nil when this reference is backed by a real `PhotoEntry` that can
    /// be deleted from the model context.
    let entry: PhotoEntry?

    var id: String { fileName }

    static func == (lhs: PhotoReference, rhs: PhotoReference) -> Bool {
        lhs.fileName == rhs.fileName
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(fileName)
    }
}

// MARK: - Snooze helper

enum SnoozeHelper {
    /// Returns tomorrow at 9:00 AM local time.
    static func tomorrowMorning(from now: Date = Date()) -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    static func snoozeUntilTomorrow(_ plant: Plant) {
        plant.snoozedUntil = tomorrowMorning()
    }
}

// MARK: - Notification manager

enum NotificationManager {

    static let plantWaterCategoryID = "PLANT_WATER"
    static let markWateredActionID = "MARK_WATERED"

    /// Registers the notification category with a "Mark as Watered" action.
    /// Call once at app launch.
    static func registerCategories() {
        let markWatered = UNNotificationAction(
            identifier: markWateredActionID,
            title: "Mark as Watered",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: plantWaterCategoryID,
            actions: [markWatered],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Schedule (or reschedule) the reminder for a plant based on its current settings and last watering.
    /// Requests notification permission on first use so the system prompt appears in context.
    static func scheduleReminder(for plant: Plant) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [plant.notificationID])

        guard plant.reminderEnabled, plant.reminderDays > 0,
              let fireDate = plant.nextReminderDate else { return }

        let plantName = plant.name
        let reminderDays = plant.reminderDays
        let notificationID = plant.notificationID

        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "\(plantName) needs water!"
            content.body = "It's been \(reminderDays) day\(reminderDays == 1 ? "" : "s") — time to water \(plantName)."
            content.sound = .default
            content.categoryIdentifier = plantWaterCategoryID
            content.userInfo = ["plantNotificationID": notificationID]

            let trigger: UNNotificationTrigger
            if fireDate > Date() {
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            } else {
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            }

            let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
            center.add(request)
        }
    }

    static func cancelReminder(for plant: Plant) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [plant.notificationID])
    }
}
