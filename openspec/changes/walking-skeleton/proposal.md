# Proposal

## Why

GooCal needs a solid architectural foundation before integrating Google Calendar. This walking skeleton establishes the macOS menu bar lifecycle, background accessory status, popover presentation, launch-at-login service, and basic settings infrastructure using modern Swift 6 and SwiftUI.

## What Changes

- Configure the macOS application as an accessory (`LSUIElement = true`) so it runs exclusively in the menu bar without appearing in the Dock or application switcher.
- Implement a `MenuBarExtra` with `.window` style to display an icon and placeholder status text in the macOS menu bar.
- Provide an interactive popover panel on click containing a placeholder status view and a Settings button.
- Implement a dedicated Settings scene with a "Launch at Login" toggle powered by `ServiceManagement.SMAppService.mainApp`.
- Establish clean Swift 6 state management using `@Observable` and remove default Xcode SwiftData template code.

## Capabilities

### New Capabilities
- `menu-bar-app`: Menu bar presence, popover window presentation, settings interaction, and launch-at-login automation for the GooCal macOS app.

### Modified Capabilities
*(None - this is the initial capability for the project)*

## Impact

- Target: macOS (SwiftUI, Swift 6).
- Files modified/added: `GooCalApp.swift`, `ContentView.swift`, `SettingsView.swift`, `AppState.swift`, `LaunchAtLoginService.swift`, and `Info.plist` / project build settings for `LSUIElement`.
- Removed: Unused Xcode SwiftData template code (`Item.swift` and `ModelContainer` setup).
- Dependencies: Standard macOS frameworks (`SwiftUI`, `ServiceManagement`).
