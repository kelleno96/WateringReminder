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
                let plant = plants[index]
                NotificationManager.cancelReminder(for: plant)
                if let fileName = plant.photoFileName {
                    PlantPhotoStorage.deleteImage(fileName: fileName)
                }
                modelContext.delete(plant)
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
            leadingThumbnail

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

    @ViewBuilder
    private var leadingThumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let name = plant.photoFileName,
                   let img = PlantPhotoStorage.loadImage(fileName: name) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle()
                        .fill(.secondary.opacity(0.15))
                        .overlay(
                            Image(systemName: "leaf.fill")
                                .foregroundStyle(.green.opacity(0.7))
                        )
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle().stroke(Color(.systemBackground), lineWidth: 2)
                )
                .offset(x: 2, y: 2)
        }
    }
}

// MARK: - Plant detail / history

struct PlantDetailView: View {
    @Bindable var plant: Plant
    @State private var showingDatePicker = false
    @State private var selectedDate = Date()
    @State private var showingCamera = false

    private var sortedDates: [Date] {
        plant.wateringDates.sorted(by: >)
    }

    var body: some View {
        List {
            // Photo
            Section {
                HStack {
                    Spacer()
                    photoThumbnail(size: 120)
                    Spacer()
                }
                .listRowBackground(Color.clear)

                if plant.photoFileName == nil {
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Add Photo", systemImage: "camera.fill")
                    }
                } else {
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Change Photo", systemImage: "camera.rotate")
                    }
                    Button(role: .destructive) {
                        removePhoto()
                    } label: {
                        Label("Remove Photo", systemImage: "trash")
                    }
                }
            }

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
        .fullScreenCover(isPresented: $showingCamera) {
            PlantCameraView(
                onCapture: { image in
                    handleCapture(image)
                    showingCamera = false
                },
                onCancel: { showingCamera = false }
            )
        }
    }

    @ViewBuilder
    private func photoThumbnail(size: CGFloat) -> some View {
        Group {
            if let name = plant.photoFileName,
               let img = PlantPhotoStorage.loadImage(fileName: name) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(.secondary.opacity(0.15))
                    .overlay(
                        Image(systemName: "leaf.fill")
                            .font(.system(size: size * 0.3))
                            .foregroundStyle(.green.opacity(0.6))
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private func handleCapture(_ image: UIImage) {
        let newName = PlantPhotoStorage.generateNewFileName()
        do {
            try PlantPhotoStorage.save(image: image, as: newName)
        } catch {
            return
        }
        if let oldName = plant.photoFileName {
            PlantPhotoStorage.deleteImage(fileName: oldName)
        }
        plant.photoFileName = newName
    }

    private func removePhoto() {
        if let name = plant.photoFileName {
            PlantPhotoStorage.deleteImage(fileName: name)
        }
        plant.photoFileName = nil
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
    @State private var pendingPhoto: UIImage?
    @State private var showingCamera = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo (optional)") {
                    HStack {
                        Spacer()
                        photoPreview
                        Spacer()
                    }
                    .listRowBackground(Color.clear)

                    if pendingPhoto == nil {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera.fill")
                        }
                    } else {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Retake", systemImage: "camera.rotate")
                        }
                        Button(role: .destructive) {
                            pendingPhoto = nil
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }

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
                    Button("Add") { addPlant() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { focused = true }
            .fullScreenCover(isPresented: $showingCamera) {
                PlantCameraView(
                    onCapture: { image in
                        pendingPhoto = image
                        showingCamera = false
                    },
                    onCancel: { showingCamera = false }
                )
            }
        }
    }

    @ViewBuilder
    private var photoPreview: some View {
        Group {
            if let image = pendingPhoto {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(.secondary.opacity(0.15))
                    .overlay(
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.green.opacity(0.6))
                    )
            }
        }
        .frame(width: 120, height: 120)
        .clipShape(Circle())
    }

    private func addPlant() {
        let plant = Plant(name: name.trimmingCharacters(in: .whitespaces))
        if let image = pendingPhoto {
            let fileName = PlantPhotoStorage.generateNewFileName()
            if (try? PlantPhotoStorage.save(image: image, as: fileName)) != nil {
                plant.photoFileName = fileName
            }
        }
        modelContext.insert(plant)
        dismiss()
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
