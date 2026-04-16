//
//  ContentView.swift
//  WateringReminder
//
//  Created by Kellen O'Connor on 4/15/26.
//

import SwiftUI
import SwiftData

// MARK: - Main plant list

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Plant.name) private var plants: [Plant]
    @State private var showingAddPlant = false

    var body: some View {
        NavigationStack {
            Group {
                if plants.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(plants) { plant in
                            NavigationLink(destination: PlantDetailView(plant: plant)) {
                                PlantRow(plant: plant)
                            }
                        }
                        .onDelete(perform: deletePlants)
                    }
                }
            }
            .navigationTitle("My Plants")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddPlant = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                if !plants.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                    }
                }
            }
            .sheet(isPresented: $showingAddPlant) {
                AddPlantSheet()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green.opacity(0.7))
            Text("No plants yet")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Tap + to add your first plant")
                .foregroundStyle(.secondary)
        }
    }

    private func deletePlants(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                NotificationManager.cancelReminder(for: plants[index])
                modelContext.delete(plants[index])
            }
        }
    }
}

// MARK: - Plant row

struct PlantRow: View {
    let plant: Plant

    private var daysSinceWatered: Int? {
        guard let last = plant.lastWatered else { return nil }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day
    }

    private var lastWateredText: String {
        guard let days = daysSinceWatered else { return "Never watered" }
        switch days {
        case 0:  return "Watered today"
        case 1:  return "Watered yesterday"
        default: return "Watered \(days) days ago"
        }
    }

    private var statusColor: Color {
        if plant.reminderEnabled && plant.reminderIsOverdue { return .red }
        guard let days = daysSinceWatered else { return .red }
        switch days {
        case 0...2: return .green
        case 3...6: return .orange
        default:    return .red
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(plant.name)
                    .font(.headline)
                Text(lastWateredText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation {
                    plant.logWatering()
                    NotificationManager.scheduleReminder(for: plant)
                }
            } label: {
                Image(systemName: "drop.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Plant detail / history

struct PlantDetailView: View {
    @Bindable var plant: Plant
    @State private var showingDatePicker = false
    @State private var selectedDate = Date()

    private var sortedDates: [Date] {
        plant.wateringDates.sorted(by: >)
    }

    var body: some View {
        List {
            // Quick-water actions
            Section {
                Button {
                    plant.logWatering()
                    NotificationManager.scheduleReminder(for: plant)
                } label: {
                    Label("Water now", systemImage: "drop.fill")
                        .font(.headline)
                        .foregroundStyle(.blue)
                }

                Button {
                    selectedDate = Date()
                    showingDatePicker = true
                } label: {
                    Label("Log a past watering…", systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                }
            }

            // Reminder settings
            Section("Reminder") {
                Toggle("Remind me to water", isOn: $plant.reminderEnabled)
                    .onChange(of: plant.reminderEnabled) { _, enabled in
                        if enabled {
                            NotificationManager.scheduleReminder(for: plant)
                        } else {
                            NotificationManager.cancelReminder(for: plant)
                        }
                    }

                if plant.reminderEnabled {
                    Stepper(
                        "Every \(plant.reminderDays) day\(plant.reminderDays == 1 ? "" : "s")",
                        value: $plant.reminderDays,
                        in: 1...365
                    )
                    .onChange(of: plant.reminderDays) { _, _ in
                        NotificationManager.scheduleReminder(for: plant)
                    }

                    if let next = plant.nextReminderDate {
                        LabeledContent("Next reminder") {
                            if plant.reminderIsOverdue {
                                Text("Overdue")
                                    .foregroundStyle(.red)
                            } else {
                                Text(next, style: .date)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            // Watering history
            Section("History") {
                if sortedDates.isEmpty {
                    Text("No watering history yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedDates, id: \.self) { date in
                        Text(date, style: .date)
                            .badge(Text(date, style: .time).foregroundStyle(.secondary))
                    }
                    .onDelete(perform: deleteWaterings)
                }
            }
        }
        .navigationTitle(plant.name)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingDatePicker) {
            DatePickerSheet(selectedDate: $selectedDate) {
                plant.logWatering(on: selectedDate)
                NotificationManager.scheduleReminder(for: plant)
            }
        }
    }

    private func deleteWaterings(offsets: IndexSet) {
        let sorted = sortedDates
        withAnimation {
            for index in offsets {
                let dateToRemove = sorted[index]
                if let i = plant.wateringDates.firstIndex(of: dateToRemove) {
                    plant.wateringDates.remove(at: i)
                }
            }
        }
        // Reschedule based on the new lastWatered
        NotificationManager.scheduleReminder(for: plant)
    }
}

// MARK: - Add plant sheet

struct AddPlantSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Plant name") {
                    TextField("e.g. Monstera, Fiddle Leaf Fig…", text: $name)
                        .focused($focused)
                }
            }
            .navigationTitle("New Plant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let plant = Plant(name: name.trimmingCharacters(in: .whitespaces))
                        modelContext.insert(plant)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }
}

// MARK: - Date picker sheet (for logging past waterings)

struct DatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "Date & time",
                    selection: $selectedDate,
                    in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
            }
            .navigationTitle("Log Past Watering")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Plant.self, inMemory: true)
}
