//
//  ContentView.swift
//  WateringReminder
//
//  Created by Kellen O'Connor on 4/15/26.
//

import SwiftUI
import SwiftData

// MARK: - Sort options

enum PlantSortOption: String, CaseIterable, Identifiable {
    case name = "Name (A→Z)"
    case mostOverdue = "Most overdue first"
    case recentlyWatered = "Recently watered"

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .name: return "textformat"
        case .mostOverdue: return "exclamationmark.triangle"
        case .recentlyWatered: return "drop"
        }
    }
}

// MARK: - Main plant list

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var plants: [Plant]

    @State private var showingAddPlant = false
    @State private var showingSettings = false
    @State private var searchText = ""
    @State private var sortOption: PlantSortOption = .name
    @State private var pendingDeletion: IndexSet?
    @State private var showingDeleteConfirm = false

    private var filteredSortedPlants: [Plant] {
        let filtered: [Plant]
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filtered = plants
        } else {
            filtered = plants.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        switch sortOption {
        case .name:
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .mostOverdue:
            return filtered.sorted { a, b in
                // Plants with a non-nil reminder date come first, sorted ascending
                // (earliest / most overdue first). Plants without a reminder go last.
                switch (a.nextReminderDate, b.nextReminderDate) {
                case let (x?, y?): return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
            }
        case .recentlyWatered:
            return filtered.sorted { a, b in
                switch (a.lastWatered, b.lastWatered) {
                case let (x?, y?): return x > y
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if plants.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(filteredSortedPlants) { plant in
                            NavigationLink(destination: PlantDetailView(plant: plant)) {
                                PlantRow(plant: plant)
                            }
                        }
                        .onDelete(perform: requestDelete)
                    }
                    .searchable(text: $searchText, prompt: "Search plants")
                }
            }
            .navigationTitle("My Plants")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        if !plants.isEmpty {
                            sortMenu
                        }
                        Button {
                            showingAddPlant = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddPlant) {
                AddPlantSheet()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .onAppear { WateringSnapshotCache.write(plants: plants) }
            .onChange(of: plants.count) { _, _ in
                WateringSnapshotCache.write(plants: plants)
            }
            .confirmationDialog(
                deleteConfirmTitle,
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    performPendingDelete()
                }
                Button("Cancel", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: {
                Text("This will also remove any photos on this device. This can't be undone.")
            }
        }
    }

    private var deleteConfirmTitle: String {
        guard let offsets = pendingDeletion, offsets.count > 0 else {
            return "Delete plant?"
        }
        if offsets.count == 1 {
            let plant = filteredSortedPlants[offsets.first!]
            return "Delete \(plant.name)?"
        }
        return "Delete \(offsets.count) plants?"
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sortOption) {
                ForEach(PlantSortOption.allCases) { option in
                    Label(option.rawValue, systemImage: option.systemImage).tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
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

    private func requestDelete(offsets: IndexSet) {
        pendingDeletion = offsets
        showingDeleteConfirm = true
    }

    private func performPendingDelete() {
        guard let offsets = pendingDeletion else { return }
        let list = filteredSortedPlants
        withAnimation {
            for index in offsets {
                let plant = list[index]
                NotificationManager.cancelReminder(for: plant)
                if let fileName = plant.photoFileName {
                    PlantPhotoStorage.deleteImage(fileName: fileName)
                }
                for photo in plant.photos {
                    PlantPhotoStorage.deleteImage(fileName: photo.fileName)
                }
                modelContext.delete(plant)
            }
        }
        pendingDeletion = nil
        WateringSnapshotCache.write(plants: plants)
    }
}

// MARK: - Plant row

struct PlantRow: View {
    @Bindable var plant: Plant
    @State private var confirmingDuplicate = false

    private var daysSinceWatered: Int? {
        guard let last = plant.lastWatered else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: Date())).day
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
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(lastWateredText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                attemptQuickWater()
            } label: {
                Image(systemName: "drop.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            "Already watered less than 5 minutes ago.",
            isPresented: $confirmingDuplicate,
            titleVisibility: .visible
        ) {
            Button("Log Again") { performWater() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func attemptQuickWater() {
        if let last = plant.lastWatered,
           Date().timeIntervalSince(last) < 300 {
            confirmingDuplicate = true
            return
        }
        performWater()
    }

    private func performWater() {
        withAnimation {
            plant.logWatering()
            NotificationManager.scheduleReminder(for: plant)
        }
    }

    @ViewBuilder
    private var leadingThumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let name = plant.displayPhotoFileName,
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
    @State private var confirmingDuplicate = false

    private var sortedDates: [Date] {
        plant.wateringDates.sorted(by: >)
    }

    var body: some View {
        List {
            // Photo timeline
            Section("Photos") {
                PhotoTimelineView(plant: plant)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            // Quick-water actions
            Section {
                Button {
                    attemptQuickWater()
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

                    if plant.reminderIsOverdue {
                        Button {
                            snoozeUntilTomorrow()
                        } label: {
                            Label("Remind me tomorrow", systemImage: "zzz")
                        }
                    }

                    if let snooze = plant.snoozedUntil, snooze > Date() {
                        LabeledContent("Snoozed until") {
                            Text(snooze, style: .date)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Notes
            Section("Notes") {
                TextEditor(text: $plant.notes)
                    .frame(minHeight: 80)
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
        .confirmationDialog(
            "Already watered less than 5 minutes ago.",
            isPresented: $confirmingDuplicate,
            titleVisibility: .visible
        ) {
            Button("Log Again") { performWater() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func attemptQuickWater() {
        if let last = plant.lastWatered,
           Date().timeIntervalSince(last) < 300 {
            confirmingDuplicate = true
            return
        }
        performWater()
    }

    private func performWater() {
        plant.logWatering()
        NotificationManager.scheduleReminder(for: plant)
    }

    private func snoozeUntilTomorrow() {
        SnoozeHelper.snoozeUntilTomorrow(plant)
        NotificationManager.scheduleReminder(for: plant)
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
    @State private var selectedSpeciesID: String = ""
    @FocusState private var focused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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

                Section("Species (optional)") {
                    Picker("Species", selection: $selectedSpeciesID) {
                        Text("None").tag("")
                        ForEach(SpeciesCatalog.all) { species in
                            Text(species.commonName).tag(species.id)
                        }
                    }
                    .onChange(of: selectedSpeciesID) { _, newID in
                        guard let species = SpeciesCatalog.byID(newID) else { return }
                        if trimmedName.isEmpty {
                            name = species.commonName
                        }
                    }
                    if let species = SpeciesCatalog.byID(selectedSpeciesID) {
                        Text("Recommended: every \(species.recommendedDays) day\(species.recommendedDays == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                    .disabled(trimmedName.isEmpty)
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
        let finalName = trimmedName
        guard !finalName.isEmpty else { return }
        let plant = Plant(name: finalName)

        if let species = SpeciesCatalog.byID(selectedSpeciesID) {
            plant.speciesIdentifier = species.id
            plant.reminderDays = species.recommendedDays
        }

        if let image = pendingPhoto {
            let fileName = PlantPhotoStorage.generateNewFileName()
            if (try? PlantPhotoStorage.save(image: image, as: fileName)) != nil {
                let entry = PhotoEntry(fileName: fileName, takenAt: Date())
                modelContext.insert(entry)
                entry.plant = plant
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
