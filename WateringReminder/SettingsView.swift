//
//  SettingsView.swift
//  WateringReminder
//
//  Settings sheet with export actions. Reached from the gear icon in the
//  main list toolbar.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var plants: [Plant]
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let jsonURL = try? Exporter.writeJSON(plants) {
                        ShareLink(item: jsonURL) {
                            Label("Export as JSON", systemImage: "square.and.arrow.up")
                        }
                    }
                    if let csvURL = try? Exporter.writeCSV(plants) {
                        ShareLink(item: csvURL) {
                            Label("Export as CSV", systemImage: "tablecells")
                        }
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Exports include plant names, notes, watering history, and reminder settings. Photos stay on your device.")
                }

                Section("About") {
                    LabeledContent("Plants", value: "\(plants.count)")
                    LabeledContent(
                        "Total waterings",
                        value: "\(plants.reduce(0) { $0 + $1.wateringDates.count })"
                    )
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
