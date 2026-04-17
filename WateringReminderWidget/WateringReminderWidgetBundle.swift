//
//  WateringReminderWidgetBundle.swift
//  WateringReminderWidget
//
//  Created by Kellen O'Connor on 4/17/26.
//

import WidgetKit
import SwiftUI

@main
struct WateringReminderWidgetBundle: WidgetBundle {
    var body: some Widget {
        MostOverdueWidget()
    }
}
