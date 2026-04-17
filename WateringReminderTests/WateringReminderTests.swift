//
//  WateringReminderTests.swift
//  WateringReminderTests
//
//  Created by Kellen O'Connor on 4/15/26.
//

import Testing
import Foundation
import UIKit
@testable import WateringReminder

// MARK: - Plant model tests

struct PlantModelTests {

    // MARK: logWatering

    @Test func logWateringAppendsDate() {
        let plant = Plant(name: "Monstera")
        #expect(plant.wateringDates.isEmpty)
        plant.logWatering()
        #expect(plant.wateringDates.count == 1)
    }

    @Test func logWateringAppendsSpecificDate() {
        let plant = Plant(name: "Fern")
        let date = Date(timeIntervalSinceReferenceDate: 1_000_000)
        plant.logWatering(on: date)
        #expect(plant.wateringDates.first == date)
    }

    @Test func logWateringMultipleTimes() {
        let plant = Plant(name: "Cactus")
        let d1 = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let d2 = Date(timeIntervalSinceReferenceDate: 2_000_000)
        plant.logWatering(on: d1)
        plant.logWatering(on: d2)
        #expect(plant.wateringDates.count == 2)
    }

    // MARK: lastWatered

    @Test func lastWateredIsNilWhenNoHistory() {
        let plant = Plant(name: "Orchid")
        #expect(plant.lastWatered == nil)
    }

    @Test func lastWateredReturnsMaxDate() {
        let plant = Plant(name: "Aloe")
        let earlier = Date(timeIntervalSinceReferenceDate: 500_000)
        let later   = Date(timeIntervalSinceReferenceDate: 900_000)
        plant.logWatering(on: earlier)
        plant.logWatering(on: later)
        #expect(plant.lastWatered == later)
    }

    // MARK: nextReminderDate

    @Test func nextReminderDateIsNilWhenDisabled() {
        let plant = Plant(name: "Pothos")
        plant.reminderEnabled = false
        #expect(plant.nextReminderDate == nil)
    }

    @Test func nextReminderDateIsNilWhenDaysIsZero() {
        let plant = Plant(name: "Ivy")
        plant.reminderEnabled = true
        plant.reminderDays = 0
        #expect(plant.nextReminderDate == nil)
    }

    @Test func nextReminderDateOffsetFromLastWatered() throws {
        let plant = Plant(name: "Peace Lily")
        plant.reminderEnabled = true
        plant.reminderDays = 7
        let base = Date(timeIntervalSinceReferenceDate: 1_000_000)
        plant.logWatering(on: base)
        let expected = Calendar.current.date(byAdding: .day, value: 7, to: base)
        #expect(plant.nextReminderDate == expected)
    }

    @Test func nextReminderDateUsesTodayWhenNoHistory() throws {
        let plant = Plant(name: "Snake Plant")
        plant.reminderEnabled = true
        plant.reminderDays = 3
        // When no watering history exists, nextReminderDate is based on Date().
        // We just verify it is in the future relative to now.
        let now = Date()
        let next = try #require(plant.nextReminderDate)
        #expect(next > now)
    }

    // MARK: reminderIsOverdue

    @Test func reminderIsNotOverdueWhenDisabled() {
        let plant = Plant(name: "Succulent")
        plant.reminderEnabled = false
        #expect(plant.reminderIsOverdue == false)
    }

    @Test func reminderIsOverdueWhenNextDateIsInPast() {
        let plant = Plant(name: "Begonia")
        plant.reminderEnabled = true
        plant.reminderDays = 1
        // Water 10 days ago so the reminder (1 day later) is already overdue
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        plant.logWatering(on: tenDaysAgo)
        #expect(plant.reminderIsOverdue == true)
    }

    @Test func reminderIsNotOverdueWhenNextDateIsInFuture() {
        let plant = Plant(name: "Spider Plant")
        plant.reminderEnabled = true
        plant.reminderDays = 30
        plant.logWatering()   // watered today, reminder in 30 days
        #expect(plant.reminderIsOverdue == false)
    }

    // MARK: default values

    @Test func defaultReminderDaysIsSeven() {
        let plant = Plant(name: "Basil")
        #expect(plant.reminderDays == 7)
    }

    @Test func defaultReminderEnabledIsFalse() {
        let plant = Plant(name: "Mint")
        #expect(plant.reminderEnabled == false)
    }

    @Test func notificationIDIsNonEmpty() {
        let plant = Plant(name: "Rosemary")
        #expect(!plant.notificationID.isEmpty)
    }

    @Test func eachPlantGetsUniqueNotificationID() {
        let a = Plant(name: "Plant A")
        let b = Plant(name: "Plant B")
        #expect(a.notificationID != b.notificationID)
    }

    @Test func photoFileNameDefaultsToNil() {
        let plant = Plant(name: "Philodendron")
        #expect(plant.photoFileName == nil)
    }

    // MARK: V4 additions

    @Test func notesDefaultsToEmpty() {
        let plant = Plant(name: "Fern")
        #expect(plant.notes == "")
    }

    @Test func snoozedUntilDefaultsToNil() {
        let plant = Plant(name: "Fern")
        #expect(plant.snoozedUntil == nil)
    }

    @Test func loggingWateringClearsSnooze() {
        let plant = Plant(name: "Ivy")
        plant.snoozedUntil = Date().addingTimeInterval(86400)
        plant.logWatering()
        #expect(plant.snoozedUntil == nil)
    }

    @Test func snoozeShiftsNextReminderDateForward() throws {
        let plant = Plant(name: "Cactus")
        plant.reminderEnabled = true
        plant.reminderDays = 1
        // Water 10 days ago so the natural next reminder is well in the past
        plant.logWatering(on: Calendar.current.date(byAdding: .day, value: -10, to: Date())!)

        let originalNext = try #require(plant.nextReminderDate)
        #expect(originalNext < Date())  // overdue

        let tomorrow = SnoozeHelper.tomorrowMorning()
        plant.snoozedUntil = tomorrow

        let shiftedNext = try #require(plant.nextReminderDate)
        #expect(shiftedNext == tomorrow)
        #expect(shiftedNext > Date())
    }

    @Test func snoozeInThePastDoesNotAffectReminder() throws {
        let plant = Plant(name: "Aloe")
        plant.reminderEnabled = true
        plant.reminderDays = 7
        let base = Date(timeIntervalSinceReferenceDate: 1_000_000)
        plant.logWatering(on: base)
        plant.snoozedUntil = Date().addingTimeInterval(-3600)  // past

        let expected = Calendar.current.date(byAdding: .day, value: 7, to: base)
        #expect(plant.nextReminderDate == expected)
    }

    @Test func displayPhotoFileNameFallsBackToLegacy() {
        let plant = Plant(name: "Monstera")
        plant.photoFileName = "legacy.jpg"
        #expect(plant.displayPhotoFileName == "legacy.jpg")
    }

    @Test func tomorrowMorningIs9AMNextDay() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let snooze = SnoozeHelper.tomorrowMorning(from: now)
        let comps = Calendar.current.dateComponents([.hour, .minute, .day], from: snooze)
        let today = Calendar.current.dateComponents([.day], from: now)
        #expect(comps.hour == 9)
        #expect(comps.minute == 0)
        #expect(comps.day != today.day)
        #expect(snooze > now)
    }
}

// MARK: - Species catalog tests

struct SpeciesCatalogTests {

    @Test func catalogIsNonEmpty() {
        #expect(!SpeciesCatalog.all.isEmpty)
        #expect(SpeciesCatalog.all.count >= 20)
    }

    @Test func allIDsAreUnique() {
        let ids = SpeciesCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func byIDFindsKnownSpecies() throws {
        let monstera = try #require(SpeciesCatalog.byID("monstera_deliciosa"))
        #expect(monstera.commonName == "Monstera Deliciosa")
        #expect(monstera.recommendedDays == 7)
    }

    @Test func byIDReturnsNilForUnknown() {
        #expect(SpeciesCatalog.byID("does_not_exist") == nil)
        #expect(SpeciesCatalog.byID(nil) == nil)
        #expect(SpeciesCatalog.byID("") == nil)
    }

    @Test func allRecommendedDaysArePositive() {
        for species in SpeciesCatalog.all {
            #expect(species.recommendedDays > 0)
        }
    }
}

// MARK: - Exporter tests

struct ExporterTests {

    @Test func jsonRoundtripsAllFields() throws {
        let plant = Plant(name: "Pothos")
        plant.notes = "Likes indirect light"
        plant.reminderEnabled = true
        plant.reminderDays = 5
        plant.speciesIdentifier = "pothos"
        plant.logWatering(on: Date(timeIntervalSinceReferenceDate: 1_000_000))
        plant.photoFileName = "a.jpg"

        let data = try Exporter.encodeJSON([plant])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode([PlantExport].self, from: data)

        #expect(result.count == 1)
        #expect(result[0].name == "Pothos")
        #expect(result[0].notes == "Likes indirect light")
        #expect(result[0].reminderEnabled == true)
        #expect(result[0].reminderDays == 5)
        #expect(result[0].speciesIdentifier == "pothos")
        #expect(result[0].photoFileNames == ["a.jpg"])
        #expect(result[0].wateringDates.count == 1)
    }

    @Test func csvHeaderPresent() {
        let plant = Plant(name: "Fern")
        let csv = Exporter.encodeCSV([plant])
        let firstLine = csv.components(separatedBy: "\r\n").first ?? ""
        #expect(firstLine.contains("name"))
        #expect(firstLine.contains("last_watered"))
        #expect(firstLine.contains("total_waterings"))
    }

    @Test func csvRowCountMatches() {
        let plants = [Plant(name: "A"), Plant(name: "B"), Plant(name: "C")]
        let csv = Exporter.encodeCSV(plants)
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines.count == 4)  // header + 3 rows
    }

    @Test func csvEscapesQuotesAndCommas() {
        let plant = Plant(name: "My, \"special\" plant")
        let csv = Exporter.encodeCSV([plant])
        // Expect double-quoted field with internal quotes escaped
        #expect(csv.contains("\"My, \"\"special\"\" plant\""))
    }

    @Test func csvEscapesNewlinesInNotes() {
        let plant = Plant(name: "Ficus")
        plant.notes = "line 1\nline 2"
        let csv = Exporter.encodeCSV([plant])
        // The notes field should be quoted because it contains a newline
        #expect(csv.contains("\"line 1\nline 2\""))
    }
}

// MARK: - Snapshot cache tests

struct SnapshotCacheTests {

    @Test func mostOverduePicksBiggestPastDue() {
        let now = Date()
        let snaps: [PlantSnapshot] = [
            PlantSnapshot(notificationID: "a", name: "A", lastWatered: nil,
                          nextReminderDate: now.addingTimeInterval(-86400),
                          reminderEnabled: true, photoFileName: nil),
            PlantSnapshot(notificationID: "b", name: "B", lastWatered: nil,
                          nextReminderDate: now.addingTimeInterval(-86400 * 5),
                          reminderEnabled: true, photoFileName: nil),
            PlantSnapshot(notificationID: "c", name: "C", lastWatered: nil,
                          nextReminderDate: now.addingTimeInterval(86400),
                          reminderEnabled: true, photoFileName: nil),
        ]
        let worst = WateringSnapshotCache.mostOverdue(from: snaps)
        #expect(worst?.notificationID == "b")
    }

    @Test func mostOverdueFallsBackToSoonestUpcoming() {
        let now = Date()
        let snaps: [PlantSnapshot] = [
            PlantSnapshot(notificationID: "x", name: "X", lastWatered: nil,
                          nextReminderDate: now.addingTimeInterval(86400 * 3),
                          reminderEnabled: true, photoFileName: nil),
            PlantSnapshot(notificationID: "y", name: "Y", lastWatered: nil,
                          nextReminderDate: now.addingTimeInterval(86400),
                          reminderEnabled: true, photoFileName: nil),
        ]
        let next = WateringSnapshotCache.mostOverdue(from: snaps)
        #expect(next?.notificationID == "y")
    }

    @Test func mostOverdueReturnsNilForEmpty() {
        #expect(WateringSnapshotCache.mostOverdue(from: []) == nil)
    }
}

// MARK: - PlantPhotoStorage tests

struct PlantPhotoStorageTests {

    /// Generates a simple colored UIImage at the requested size for use in tests.
    private func makeTestImage(size: CGSize = CGSize(width: 100, height: 100),
                               color: UIColor = .systemGreen) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    @Test func saveAndLoadRoundtrip() throws {
        let name = PlantPhotoStorage.generateNewFileName()
        defer { PlantPhotoStorage.deleteImage(fileName: name) }

        let image = makeTestImage()
        try PlantPhotoStorage.save(image: image, as: name)

        let loaded = PlantPhotoStorage.loadImage(fileName: name)
        #expect(loaded != nil)
    }

    @Test func deleteRemovesFile() throws {
        let name = PlantPhotoStorage.generateNewFileName()
        try PlantPhotoStorage.save(image: makeTestImage(), as: name)
        #expect(PlantPhotoStorage.fileExists(fileName: name) == true)

        PlantPhotoStorage.deleteImage(fileName: name)
        #expect(PlantPhotoStorage.fileExists(fileName: name) == false)
    }

    @Test func photosDirectoryIsCreated() {
        let url = PlantPhotoStorage.photosDirectoryURL()
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func savedFileIsExcludedFromBackup() throws {
        let name = PlantPhotoStorage.generateNewFileName()
        defer { PlantPhotoStorage.deleteImage(fileName: name) }

        try PlantPhotoStorage.save(image: makeTestImage(), as: name)

        let url = PlantPhotoStorage.photosDirectoryURL().appendingPathComponent(name)
        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func downscaleProducesExpectedMaxDimension() {
        let source = makeTestImage(size: CGSize(width: 1000, height: 800))
        let out = PlantPhotoStorage.downscale(source, maxDimension: 300)

        let longest = max(out.size.width, out.size.height)
        #expect(longest == 300)
        // Aspect ratio preserved (within rounding)
        let sourceAspect = source.size.width / source.size.height
        let outAspect = out.size.width / out.size.height
        #expect(abs(sourceAspect - outAspect) < 0.01)
    }

    @Test func downscaleSkipsWhenAlreadySmall() {
        let source = makeTestImage(size: CGSize(width: 100, height: 80))
        let out = PlantPhotoStorage.downscale(source, maxDimension: 300)
        // Smaller-than-target images are returned unchanged
        #expect(out.size == source.size)
    }

    @Test func generateNewFileNameIsUnique() {
        let names = (0..<100).map { _ in PlantPhotoStorage.generateNewFileName() }
        #expect(Set(names).count == 100)
    }

    @Test func generateNewFileNameHasJpgExtension() {
        let name = PlantPhotoStorage.generateNewFileName()
        #expect(name.hasSuffix(".jpg"))
    }
}
