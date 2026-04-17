//
//  Exporter.swift
//  WateringReminder
//
//  Encodes a user's plant collection as JSON or CSV so it can be exported
//  via the system share sheet. Photos are referenced by filename only —
//  the binary data is not inlined.
//

import Foundation

struct PlantExport: Codable {
    var name: String
    var notes: String
    var wateringDates: [Date]
    var reminderEnabled: Bool
    var reminderDays: Int
    var snoozedUntil: Date?
    var speciesIdentifier: String?
    var photoFileNames: [String]
}

enum Exporter {

    static func snapshot(_ plants: [Plant]) -> [PlantExport] {
        plants.map { plant in
            let allPhotos: [String]
            if plant.photos.isEmpty {
                allPhotos = plant.photoFileName.map { [$0] } ?? []
            } else {
                allPhotos = plant.photos
                    .sorted { $0.takenAt < $1.takenAt }
                    .map(\.fileName)
            }
            return PlantExport(
                name: plant.name,
                notes: plant.notes,
                wateringDates: plant.wateringDates,
                reminderEnabled: plant.reminderEnabled,
                reminderDays: plant.reminderDays,
                snoozedUntil: plant.snoozedUntil,
                speciesIdentifier: plant.speciesIdentifier,
                photoFileNames: allPhotos
            )
        }
    }

    // MARK: - JSON

    static func encodeJSON(_ plants: [Plant]) throws -> Data {
        let snapshot = snapshot(plants)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    static func writeJSON(_ plants: [Plant]) throws -> URL {
        let data = try encodeJSON(plants)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("plants-\(dateStamp()).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - CSV (RFC 4180)

    static func encodeCSV(_ plants: [Plant]) -> String {
        let formatter = ISO8601DateFormatter()
        let header = ["name", "last_watered", "total_waterings", "reminder_enabled",
                      "reminder_days", "species", "notes"]
        var lines: [String] = [header.map(csvEscape).joined(separator: ",")]
        for plant in plants {
            let last = plant.lastWatered.map { formatter.string(from: $0) } ?? ""
            let row = [
                plant.name,
                last,
                String(plant.wateringDates.count),
                plant.reminderEnabled ? "true" : "false",
                String(plant.reminderDays),
                plant.speciesIdentifier ?? "",
                plant.notes
            ]
            lines.append(row.map(csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n")
    }

    static func writeCSV(_ plants: [Plant]) throws -> URL {
        let csv = encodeCSV(plants)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("plants-\(dateStamp()).csv")
        try csv.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Helpers

    private static func csvEscape(_ field: String) -> String {
        let needsQuoting = field.contains(",") || field.contains("\"") ||
                           field.contains("\n") || field.contains("\r")
        if !needsQuoting { return field }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func dateStamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        return fmt.string(from: Date())
    }
}
