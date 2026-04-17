# WateringReminderWidget

Home-screen widget extension for WateringReminder. Source files are ready; the
Xcode target still needs to be wired up manually because adding an extension
target edits the `.xcodeproj` in a way that can't safely be done outside Xcode.

## One-time setup in Xcode

1. **Add Widget Extension target**
   - File → New → Target → **Widget Extension** → name it `WateringReminderWidget`.
   - Uncheck "Include Live Activity" and "Include Configuration App Intent".
   - Delete the boilerplate `.swift` and Info.plist that Xcode generates, and
     instead add the files already in this directory:
     - `WateringReminderWidgetBundle.swift`
     - `MostOverdueWidget.swift`
     - `SharedSnapshot.swift`
     - `Info.plist`
     - `WateringReminderWidget.entitlements` (set as the target's Code Signing
       Entitlements file)

2. **Enable App Groups**
   - Select the main app target → **Signing & Capabilities** → **+ Capability**
     → **App Groups** → add `group.OConnorK.WateringReminder`.
   - Select the widget target → same steps, same group ID.

3. **Deep-link handling** (optional but recommended)
   - In the main app, add `.onOpenURL { url in ... }` to `ContentView` to
     route `wateringreminder://plant/<notificationID>` into a detail view.

4. **Build and add** the widget from the home-screen long-press menu.

## How the data flow works

- The main app writes a snapshot of all plants to the App Group-shared
  `UserDefaults` after every mutation (see
  `WateringReminder/WateringSnapshotCache.swift`).
- The widget reads that same snapshot via `SharedSnapshotReader` (see
  `SharedSnapshot.swift`) and picks the most-overdue plant.
- Timeline reloads are triggered by `WidgetCenter.shared.reloadAllTimelines()`
  from the main app on every snapshot write.

## Why a snapshot cache (not SwiftData directly)

SwiftData is only available in the main app process. Sharing the store with
the widget would require an App Group container URL and a matching schema in
the widget target, which complicates migrations. A tiny JSON snapshot in
shared `UserDefaults` is cheap, always fresh, and keeps the widget's code
path simple.
