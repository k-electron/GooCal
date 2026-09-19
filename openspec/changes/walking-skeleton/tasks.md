# Tasks

## 1. Project Configuration & Cleanup

- [ ] 1.1 Remove default SwiftData boilerplate (`Item.swift` and model container references) and verify the project compiles
- [ ] 1.2 Configure `LSUIElement` (Application is agent) to `YES` in target build settings / Info.plist and verify app operates without a Dock icon

## 2. Core Services & State

- [ ] 2.1 Implement `LaunchAtLoginService` leveraging `ServiceManagement.SMAppService.mainApp` with register, unregister, and status checks
- [ ] 2.2 Implement `@Observable @MainActor AppState` to hold reactive menu bar text, status, and launch-at-login binding

## 3. Menu Bar & UI Hierarchy

- [ ] 3.1 Implement `PopoverContentView` displaying status placeholder and a Settings button that triggers `openSettings()`
- [ ] 3.2 Implement `SettingsView` providing a "Launch at Login" toggle connected to `LaunchAtLoginService`
- [ ] 3.3 Update `GooCalApp` entry point with `MenuBarExtra` (`.window` style) and the `Settings` scene

## 4. Verification

- [ ] 4.1 Build and run GooCal, verifying the icon and text appear in the menu bar, clicking opens the popover, Settings opens from the popover, and toggle updates login item status
