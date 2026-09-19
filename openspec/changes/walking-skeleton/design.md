# Design

## Context

See `proposal.md` for motivation. The project is an initial Xcode macOS template targeting modern macOS with Swift 6 and SwiftUI. The starter code contains default SwiftData boilerplate that is not needed for a lightweight menu bar utility.

## Goals / Non-Goals

**Goals:**
- Implement a pure menu bar accessory app that runs in the background without a Dock icon.
- Present a live menu bar item with an SF Symbol icon and text.
- Present a SwiftUI-based popover panel upon clicking the menu bar item.
- Provide a Settings button in the popover that navigates to a dedicated Settings window.
- Implement reliable launch-at-login toggle using Apple's modern `ServiceManagement` APIs.
- Clean up unused template boilerplate.

**Non-Goals:**
- Any Google Calendar integration, EventKit access, or web view rendering (deferred to subsequent changes).
- Custom notification scheduling or calendar permissions handling.

## Decisions

### 1. `MenuBarExtra` with `.window` style vs. `NSStatusItem` / `NSPopover`
- **Decision**: Use SwiftUI's native `MenuBarExtra(isInserted:content:label:)` with `.menuBarExtraStyle(.window)`.
- **Rationale**: Declarative, fully native to SwiftUI, avoids AppKit boilerplate (`NSStatusBar`, `NSStatusItem`, `NSPopoverDelegate`), and directly supports SwiftUI views and interactive controls.
- **Alternative considered**: AppKit `NSStatusItem` wrapper. While slightly more low-level configurable, it adds unnecessary AppKit lifecycle complexity when SwiftUI 5+ `MenuBarExtra` satisfies all requirements.

### 2. Launch at Login via `SMAppService.mainApp`
- **Decision**: Use `ServiceManagement.SMAppService.mainApp.register()` / `.unregister()`.
- **Rationale**: Supported natively on modern macOS (macOS 13+), requires no bundled helper apps or deprecated `SMLoginItemSetEnabled`, and integrates directly with macOS System Settings $\rightarrow$ General $\rightarrow$ Login Items.
- **Alternative considered**: Deprecated `LSSharedFileList` or custom LaunchAgent plist files. These are legacy and discouraged by Apple.

### 3. Application as Agent (`LSUIElement = true`)
- **Decision**: Set `LSUIElement` to `YES` in target configuration/Info.plist.
- **Rationale**: Ensures the application does not clutter the macOS Dock or the Cmd+Tab app switcher, behaving as a native system status-bar utility.

### 4. State Management with Swift 6 `@Observable`
- **Decision**: Use the `@Observable` macro (Observation framework) on `@MainActor AppState`.
- **Rationale**: Modern standard in Swift 6, outperforms `ObservableObject` / `@Published` with fine-grained invalidation, and eliminates combine dependencies.

## Risks / Trade-offs

- **[Risk] Window focus / dismiss behavior with `MenuBarExtra`**: Clicking outside standard `.window` style can occasionally behave differently depending on system window management.  
  $\rightarrow$ **Mitigation**: Use standard SwiftUI popover view hierarchy and test dismiss interactions.
- **[Risk] Unregistered Login Item permission alert**: When registering with `SMAppService`, macOS may present a system notification ("GooCal added to Login Items").  
  $\rightarrow$ **Mitigation**: This is standard macOS user-facing security behavior; maintain accurate `status` tracking in `SMAppService.mainApp.status` to reflect active state.
