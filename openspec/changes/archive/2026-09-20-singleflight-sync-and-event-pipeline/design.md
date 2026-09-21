# Design

## Context

See `proposal.md` for motivation. GooCal currently operates as an accessory menu bar application (`LSUIElement = true`) built for macOS 14+ using Swift 6, SwiftUI, and the Observation framework. The application delegates calendar queries to `EventKitCalendarService` through the `CalendarServiceManaging` abstraction. 

Currently, `AppState.refreshEvents()` is only invoked when the popover opens or when the active date is clicked. GooCal does not observe `EKEventStoreChanged`, does not trigger remote account synchronization (`refreshSourcesIfNecessary()`), lacks a background heartbeat to update the menu bar title as time progresses, and evaluates `placedEvents` synchronously inside the SwiftUI view body. Multiple asynchronous triggers must now be coordinated through a unified, singleflighted architecture.

## Goals / Non-Goals

**Goals:**
- Provide a reusable `SingleflightCoordinator` that deduplicates concurrent tasks by key and coalesces multiple pending triggers into at most one trailing pass.
- Extend `CalendarServiceManaging` and `EventKitCalendarService` to expose an `AsyncStream<Void>` of store change events and an asynchronous `refreshSources()` method.
- Implement an event-driven sync pipeline in `AppState` that integrates:
  - System `EKEventStoreChanged` notifications with burst debouncing.
  - Non-blocking remote account refresh upon popover open.
  - Sleep-friendly 60-second background heartbeat with timer tolerance.
  - Immediate catch-up synchronization on `NSWorkspace.didWakeNotification`.
- Present cached events immediately upon popover open with a unified refresh button that transitions dynamically between standard refresh icon, active spinner, and error retry badge.
- Support manual refresh via click and `⌘R` keyboard shortcut.
- Precompute and singleflight event card layout computation off the main thread to eliminate view body evaluation overhead and UI jank.
- Expand `MockCalendarService` with simulated change streams and remote sync latency to verify all concurrent behaviors deterministically.

**Non-Goals:**
- Event creation, deletion, or modification (read-only calendar presentation).
- Direct Google Calendar REST API / OAuth authentication (EventKit remains the local cache and account engine).
- Power assertions (the app must never prevent system sleep, display idle, or battery optimization).

## Decisions

### 1. Reusable `SingleflightCoordinator`
- **Decision**: Introduce a generic `SingleflightCoordinator<Key: Hashable, Value: Sendable>` actor to manage task lifecycles:
  - If a task with key `K` is active, new callers join the active `Task` without starting a second execution.
  - If calls arrive while a task is in flight, the key is marked as `needsTrailing = true`. When the current pass concludes, exactly one trailing pass executes.
- **Rationale**: Eliminates race conditions, prevents redundant queries, and handles rapid burst events gracefully.
- **Alternatives Considered**: Ad-hoc boolean flags in `AppState` (error-prone and difficult to test across multiple concurrent subsystems); Combine-based throttling (less native to Swift 6 async/await architecture).

### 2. Stream-Based Store Observation (`eventStoreChanges`)
- **Decision**: Add `var storeChanges: AsyncStream<Void> { get }` to `CalendarServiceManaging`. `EventKitCalendarService` wraps `NotificationCenter.default.notifications(named: .EKEventStoreChanged)`.
- **Rationale**: Keeps `AppState` decoupled from system notification centers and allows `MockCalendarService` to yield simulated system notifications during automated testing.
- **Alternatives Considered**: Subscribing directly in `AppState` via `NotificationCenter.default`. Rejected because it creates tight coupling with live macOS notifications and hinders headless CI testing.

### 3. Immediate Cached Rendering with Asynchronous Remote Sync
- **Decision**: On popover open, `DailyTimelineView` immediately renders currently loaded events. Concurrently, `AppState` triggers `refreshSources()` through the singleflight coordinator and sets `isSyncingRemote = true`.
- **Rationale**: Guarantees zero-latency presentation without blank screens or skeleton views, while ensuring fresh data is pulled in the background.
- **Alternatives Considered**: Blocking view display until remote sync completes. Rejected because network latency (500ms–3s) causes unacceptable popover open lag.

### 4. Sleep-Safe Background Heartbeat & Wake Observer
- **Decision**:
  - Run a periodic background task in `AppState` every 60 seconds with 10-second tolerance (`timer.tolerance = 10.0`) to update upcoming meeting status and handle midnight date transitions.
  - Never declare `IOPMAssertion` or disable idle sleep.
  - Subscribe to `NSWorkspace.didWakeNotification`. When the system wakes, immediately trigger a singleflighted catch-up sync.
- **Rationale**: Guarantees freshness when the user is looking at their menu bar, zero battery/CPU draw while sleeping, and immediate correction the moment the laptop lid opens.
- **Alternatives Considered**: Event-boundary timers only. Rejected because midnight rollover and external unsynced clock changes are simpler and more robustly handled with a tolerant periodic tick combined with wake notifications.

### 5. Asynchronous Layout Placement
- **Decision**: Move `TimelineLayoutEngine.layoutEvents` execution out of `DailyTimelineView.placedEvents` computed getter into an asynchronous, singleflighted computation in `AppState` (`placedEvents: [PlacedEvent]`).
- **Rationale**: Clustering and precedence ranking can be CPU-intensive with dense calendar schedules. Precomputing layout off-main-actor ensures SwiftUI view body evaluation is purely constant-time layout mapping.
- **Alternatives Considered**: Leaving `placedEvents` as a computed property in the view. Rejected because any state tick (such as minute indicators or hover states) re-evaluates the layout engine.

### 6. Unified Header Refresh Button & State Machine
- **Decision**: Combine the manual refresh trigger and sync progress indicator into a single standard macOS control in the popover header:
  - **Idle State**: Displays `Image(systemName: "arrow.clockwise")`, enabled, with tooltip `"Refresh Calendar (⌘R)"` and `.keyboardShortcut("r", modifiers: .command)`.
  - **Syncing State**: Replaces the icon with a standard `ProgressView().controlSize(.small)`, disabled to prevent concurrent clicks while an in-flight sync runs.
  - **Failed State**: Replaces the icon with `Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)`, clickable to retry, with a detailed hover tooltip describing the sync error.
- **Rationale**: Follows standard Apple interface conventions by unifying trigger and status, saving valuable popover header space and providing clear, actionable feedback.
- **Alternatives Considered**: Separate static spinner and separate refresh button. Rejected to prevent visual clutter and contradictory UI states.

## Risks / Trade-offs

- **[Risk] Remote Sync Rate-Limiting**: Calling `refreshSourcesIfNecessary()` too frequently can be throttled or ignored by macOS.  
  *Mitigation*: Remote sync is only triggered by explicit user popover open or manual refresh button, and is guarded by singleflight deduplication; the 60s background tick only performs local EventKit queries.
- **[Risk] Rapid Notification Storms on Multi-Calendar Sync**: Multiple `.EKEventStoreChanged` notifications arrive in rapid succession.  
  *Mitigation*: Debounce notifications by 250ms and rely on trailing singleflight coalescing so at most two passes occur.
- **[Risk] Indicator Strobe Effect**: Fast local queries (e.g. 10ms) could cause the sync spinner to flash briefly.  
  *Mitigation*: The sync indicator tracks remote account sync (`isSyncingRemote`), with subtle SwiftUI opacity transitions.
