//
//  WateringReminderWidgetBundle.swift
//  WateringReminderWidget
//
//  Entry point for the widget extension.
//

import WidgetKit
import SwiftUI

@main
struct WateringReminderWidgetBundle: WidgetBundle {
    var body: some Widget {
        MostOverdueWidget()
    }
}
