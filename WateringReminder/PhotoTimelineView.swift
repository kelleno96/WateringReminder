//
//  PhotoTimelineView.swift
//  WateringReminder
//
//  Horizontal scroll strip of a plant's photos, oldest→newest, with an
//  "add photo" control at the end. Tapping a thumb opens a full-screen
//  paged viewer with per-photo delete.
//

import SwiftUI
import SwiftData

struct PhotoTimelineView: View {
    @Bindable var plant: Plant
    @Environment(\.modelContext) private var modelContext
    @State private var showingCamera = false
    @State private var viewerPhoto: PhotoReference?

    private var photos: [PhotoReference] {
        // Oldest → newest so the most recent is at the trailing edge,
        // next to the "add photo" button.
        plant.photosNewestFirst.reversed()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(photos) { photo in
                    photoThumb(photo)
                        .onTapGesture { viewerPhoto = photo }
                }
                addPhotoButton
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
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
        .fullScreenCover(item: $viewerPhoto) { photo in
            PhotoViewerSheet(
                plant: plant,
                initialFileName: photo.fileName,
                onDismiss: { viewerPhoto = nil }
            )
        }
    }

    @ViewBuilder
    private func photoThumb(_ photo: PhotoReference) -> some View {
        VStack(spacing: 4) {
            Group {
                if let img = PlantPhotoStorage.loadImage(fileName: photo.fileName) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle()
                        .fill(.secondary.opacity(0.15))
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())

            Text(photo.takenAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var addPhotoButton: some View {
        Button {
            showingCamera = true
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .background(Circle().fill(Color.accentColor.opacity(0.1)))
                    .frame(width: 72, height: 72)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .foregroundStyle(Color.accentColor)
                    )
                Text("Add")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Capture

    private func handleCapture(_ image: UIImage) {
        let newName = PlantPhotoStorage.generateNewFileName()
        do {
            try PlantPhotoStorage.save(image: image, as: newName)
        } catch {
            return
        }
        // Migrate legacy single photoFileName into a PhotoEntry on the first
        // new capture so history isn't lost.
        if plant.photos.isEmpty, let legacy = plant.photoFileName {
            let migrated = PhotoEntry(
                fileName: legacy,
                takenAt: plant.lastWatered ?? Date().addingTimeInterval(-1)
            )
            modelContext.insert(migrated)
            migrated.plant = plant
            plant.photoFileName = nil
        }
        let entry = PhotoEntry(fileName: newName, takenAt: Date())
        modelContext.insert(entry)
        entry.plant = plant
    }
}

// MARK: - Full-screen viewer

struct PhotoViewerSheet: View {
    @Bindable var plant: Plant
    let initialFileName: String
    let onDismiss: () -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var selection: String
    @State private var confirmingDelete = false

    init(plant: Plant, initialFileName: String, onDismiss: @escaping () -> Void) {
        self.plant = plant
        self.initialFileName = initialFileName
        self.onDismiss = onDismiss
        _selection = State(initialValue: initialFileName)
    }

    private var photos: [PhotoReference] {
        plant.photosNewestFirst
    }

    private var currentPhoto: PhotoReference? {
        photos.first { $0.fileName == selection }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(photos) { photo in
                    photoPage(photo)
                        .tag(photo.fileName)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            VStack {
                topBar
                Spacer()
                if let current = currentPhoto {
                    caption(for: current)
                }
            }
        }
        .confirmationDialog(
            "Delete this photo?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteCurrent()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: photos.map(\.fileName)) { _, names in
            if !names.contains(selection) {
                if let first = names.first {
                    selection = first
                } else {
                    onDismiss()
                }
            }
        }
    }

    @ViewBuilder
    private func photoPage(_ photo: PhotoReference) -> some View {
        if let img = PlantPhotoStorage.loadImage(fileName: photo.fileName) {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .padding()
        } else {
            VStack {
                Image(systemName: "photo").font(.largeTitle)
                Text("Photo unavailable").foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
            Spacer()
            Button {
                confirmingDelete = true
            } label: {
                Image(systemName: "trash")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func caption(for photo: PhotoReference) -> some View {
        VStack(spacing: 2) {
            Text(photo.takenAt, style: .date)
                .font(.headline)
            Text(photo.takenAt, style: .time)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .padding(.bottom, 32)
    }

    private func deleteCurrent() {
        guard let current = currentPhoto else { return }
        PlantPhotoStorage.deleteImage(fileName: current.fileName)
        if let entry = current.entry {
            modelContext.delete(entry)
        } else {
            // Legacy single-photo fallback
            if plant.photoFileName == current.fileName {
                plant.photoFileName = nil
            }
        }
    }
}
