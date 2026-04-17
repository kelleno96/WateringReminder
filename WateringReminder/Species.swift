//
//  Species.swift
//  WateringReminder
//
//  Built-in list of common houseplants with recommended watering intervals.
//  Users pick an optional species when adding a plant; the choice pre-fills
//  the name (if blank) and sets reminderDays.
//

import Foundation

struct Species: Identifiable, Hashable, Sendable {
    let id: String
    let commonName: String
    let recommendedDays: Int
}

enum SpeciesCatalog {
    static let all: [Species] = [
        .init(id: "monstera_deliciosa", commonName: "Monstera Deliciosa", recommendedDays: 7),
        .init(id: "pothos", commonName: "Pothos", recommendedDays: 7),
        .init(id: "snake_plant", commonName: "Snake Plant", recommendedDays: 14),
        .init(id: "zz_plant", commonName: "ZZ Plant", recommendedDays: 14),
        .init(id: "spider_plant", commonName: "Spider Plant", recommendedDays: 7),
        .init(id: "peace_lily", commonName: "Peace Lily", recommendedDays: 5),
        .init(id: "philodendron", commonName: "Philodendron", recommendedDays: 7),
        .init(id: "fiddle_leaf_fig", commonName: "Fiddle Leaf Fig", recommendedDays: 7),
        .init(id: "rubber_plant", commonName: "Rubber Plant", recommendedDays: 10),
        .init(id: "aloe_vera", commonName: "Aloe Vera", recommendedDays: 14),
        .init(id: "jade_plant", commonName: "Jade Plant", recommendedDays: 14),
        .init(id: "succulent", commonName: "Succulent (generic)", recommendedDays: 10),
        .init(id: "cactus", commonName: "Cactus", recommendedDays: 21),
        .init(id: "english_ivy", commonName: "English Ivy", recommendedDays: 5),
        .init(id: "boston_fern", commonName: "Boston Fern", recommendedDays: 3),
        .init(id: "african_violet", commonName: "African Violet", recommendedDays: 7),
        .init(id: "orchid", commonName: "Orchid (Phalaenopsis)", recommendedDays: 7),
        .init(id: "calathea", commonName: "Calathea", recommendedDays: 5),
        .init(id: "chinese_evergreen", commonName: "Chinese Evergreen (Aglaonema)", recommendedDays: 10),
        .init(id: "dracaena", commonName: "Dracaena", recommendedDays: 10),
        .init(id: "ficus_benjamina", commonName: "Ficus Benjamina", recommendedDays: 7),
        .init(id: "bromeliad", commonName: "Bromeliad", recommendedDays: 7),
        .init(id: "anthurium", commonName: "Anthurium", recommendedDays: 5),
        .init(id: "hoya", commonName: "Hoya", recommendedDays: 10),
        .init(id: "prayer_plant", commonName: "Prayer Plant (Maranta)", recommendedDays: 5),
        .init(id: "parlor_palm", commonName: "Parlor Palm", recommendedDays: 7),
        .init(id: "areca_palm", commonName: "Areca Palm", recommendedDays: 5),
        .init(id: "bird_of_paradise", commonName: "Bird of Paradise", recommendedDays: 7),
        .init(id: "money_tree", commonName: "Money Tree (Pachira)", recommendedDays: 10),
        .init(id: "string_of_pearls", commonName: "String of Pearls", recommendedDays: 14),
    ]

    static func byID(_ id: String?) -> Species? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}
