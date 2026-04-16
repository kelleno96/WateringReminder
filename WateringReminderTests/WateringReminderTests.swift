//
//  WateringReminderTests.swift
//  WateringReminderTests
//
//  Created by Kellen O'Connor on 4/15/26.
//

import Testing
import Foundation
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
}
