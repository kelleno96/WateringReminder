//
//  WateringReminderApp.swift
//  WateringReminder
//
//  Created by Kellen O'Connor on 4/15/26.
//

import SwiftUI
import SwiftData

@main
struct WateringReminderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var sharedModelContainer: ModelContainer = {
        // One-time move of any photos that predate the App Group container,
        // so the widget can load them from the shared location.
        PlantPhotoStorage.migrateFromLegacyDocumentsIfNeeded()

        let schema = Schema(versionedSchema: SchemaV4.self)
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: PlantMigrationPlan.self,
                configurations: [modelConfiguration]
            )
            NotificationResponder.modelContainer = container
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
