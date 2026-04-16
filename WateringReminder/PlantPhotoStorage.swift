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

    // MARK: - Public API

    /// Returns Documents/PlantPhotos/, creating the directory if needed.
    nonisolated static func photosDirectoryURL() -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("PlantPhotos", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
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
