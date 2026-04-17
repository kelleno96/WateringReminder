//
//  NotificationResponder.swift
//  WateringReminder
//
//  Handles user taps on notification actions (e.g. "Mark as Watered") and
//  forwards them to the SwiftData model container so the plant's watering
//  history can be updated without opening the app.
//

import Foundation
import SwiftData
import UIKit
import UserNotifications

final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationResponder()

    /// Set at launch so the responder can mutate SwiftData when an action
    /// arrives while the app is backgrounded.
    static var modelContainer: ModelContainer?

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }

        guard response.actionIdentifier == NotificationManager.markWateredActionID else {
            return
        }

        let info = response.notification.request.content.userInfo
        guard let notificationID = info["plantNotificationID"] as? String else { return }

        handleMarkWatered(notificationID: notificationID)
    }

    // MARK: - Action handlers

    private func handleMarkWatered(notificationID: String) {
        guard let container = Self.modelContainer else { return }

        Task { @MainActor in
            let context = container.mainContext
            let descriptor = FetchDescriptor<Plant>(
                predicate: #Predicate { $0.notificationID == notificationID }
            )
            guard let plant = try? context.fetch(descriptor).first else { return }

            plant.logWatering()
            try? context.save()
            NotificationManager.scheduleReminder(for: plant)

            if let allPlants = try? context.fetch(FetchDescriptor<Plant>()) {
                WateringSnapshotCache.write(plants: allPlants)
            }
        }
    }
}

// MARK: - UIApplicationDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationResponder.shared
        NotificationManager.registerCategories()
        return true
    }
}
