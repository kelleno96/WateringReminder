//
//  PlantPhotoStorage.swift
//  WateringReminder
//
//  Saves plant photos to Documents/PlantPhotos/ as small JPEGs.
//  Files are excluded from iCloud backup so camera data never leaves the device.
//

import Foundation
import UIKit

enum PlantPhotoStorage {

    /// App Group used to share the photos directory with the widget.
    /// Keep in sync with `WateringSnapshotCache.appGroupID`.
    static let appGroupID = "group.OConnorK.WateringReminder"

    // MARK: - Public API

    /// Returns the shared `PlantPhotos/` directory, creating it if needed.
    /// Prefers the App Group container so the widget can read the same
    /// files; falls back to Documents/ when the App Group is unavailable
    /// (e.g. unit tests running without the entitlement).
    nonisolated static func photosDirectoryURL() -> URL {
        let fm = FileManager.default
        let base: URL
        if let shared = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            base = shared
        } else {
            base = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        }
        let dir = base.appendingPathComponent("PlantPhotos", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Copies photos that still live in the legacy Documents/PlantPhotos/
    /// directory into the current (App Group) directory. Safe to call on
    /// every launch: it only copies files that don't already exist at the
    /// destination, and removes the legacy dir once it's empty.
    nonisolated static func migrateFromLegacyDocumentsIfNeeded() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let legacy = docs.appendingPathComponent("PlantPhotos", isDirectory: true)
        let current = photosDirectoryURL()
        guard legacy.path != current.path,
              fm.fileExists(atPath: legacy.path),
              let entries = try? fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil) else {
            return
        }
        for src in entries {
            let dst = current.appendingPathComponent(src.lastPathComponent)
            if !fm.fileExists(atPath: dst.path) {
                try? fm.moveItem(at: src, to: dst)
                var copied = dst
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? copied.setResourceValues(values)
            } else {
                try? fm.removeItem(at: src)
            }
        }
        try? fm.removeItem(at: legacy)
    }

    /// Generates a new unique filename for a plant photo.
    nonisolated static func generateNewFileName() -> String {
        "\(UUID().uuidString).jpg"
    }

    /// Saves a UIImage as a downscaled JPEG at `fileName` inside Documents/PlantPhotos/.
    /// Marks the file as excluded from iCloud backup.
    nonisolated static func save(image: UIImage, as fileName: String) throws {
        let scaled = downscale(image, maxDimension: 300)
        guard let data = scaled.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "PlantPhotoStorage", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to encode JPEG"])
        }
        var url = photosDirectoryURL().appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)

        // Per-file exclusion from iCloud/iTunes backup. Directory-level flag
        // does not reliably cascade to contents, so set it on each file.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Loads the image for `fileName`. Returns nil on any failure.
    nonisolated static func loadImage(fileName: String) -> UIImage? {
        let url = photosDirectoryURL().appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Best-effort delete. Ignores errors (e.g. file already gone).
    nonisolated static func deleteImage(fileName: String) {
        let url = photosDirectoryURL().appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    /// True if the file exists at the given name inside the photos directory.
    nonisolated static func fileExists(fileName: String) -> Bool {
        let url = photosDirectoryURL().appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Image processing

    /// Proportionally scales `image` so its largest dimension is `maxDimension`.
    /// Pure function, separated so it's trivially unit-testable.
    nonisolated static func downscale(_ image: UIImage, maxDimension: CGFloat = 300) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }

        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1  // fixed 1x — we want the pixel size to match newSize
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
