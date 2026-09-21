# Proposal

## Why

GooCal currently queries macOS EventKit on-demand only when the popover opens or when the user manually changes the active date. It lacks awareness of external calendar mutations (`.EKEventStoreChanged`), does not keep the menu bar item fresh when meetings start or conclude while the popover remains closed, and lacks sleep/wake lifecycle integration. Furthermore, as multiple asynchronous refresh triggers are introduced, uncoordinated concurrent queries and layout recalculations risk causing visual stutter, layout thrashing, and race conditions. Implementing an app-wide singleflight synchronization and event-driven UI pipeline solves these gaps while maintaining strict sleep friendliness and zero battery drag.

## What Changes

- **System Event-Driven Sync**: Observe macOS `EKEventStoreChanged` notifications to automatically ingest external calendar updates (e.g. invites accepted, meetings rescheduled via web or Apple Calendar) into the application.
- **Singleflight Synchronization Pipeline**: Implement an app-wide singleflight coordinator with trailing coalescing so that concurrent triggers (popover open, system notifications, background timer, sleep wake) deduplicate in-flight operations and execute at most one trailing pass.
- **Popover-Open Immediate Render with Remote Sync & Visual Indicator**: Present cached events immediately upon popover open without blank states or layout jumps, asynchronously initiate `EKEventStore.refreshSourcesIfNecessary()`, and render a calm, non-flickering sync indicator during synchronization.
- **Sleep-Friendly Coalesced Heartbeat & Wake Recovery**: Run a lightweight periodic check with generous timer tolerance while the system is awake to advance upcoming meeting titles and rollover midnight, with zero power assertions (never inhibiting sleep) and instant recovery upon `NSWorkspace.didWakeNotification`.
- **Singleflight & Off-Main-Actor Layout Computation**: Deduplicate and run `TimelineLayoutEngine` clustering and column partitioning asynchronously, publishing atomic state updates to `@MainActor AppState` to eliminate main thread starvation and UI jank.

## Capabilities

### New Capabilities
- `calendar-sync`: Manages singleflighted background and event-driven calendar synchronization, `EKEventStoreChanged` observation, remote source refresh, sleep-friendly periodic heartbeat, and `NSWorkspace.didWakeNotification` lifecycle recovery.

### Modified Capabilities
- `daily-timeline`: Updates event querying behavior on popover open to display cached events immediately, surfaces an active synchronization progress indicator, and leverages singleflighted layout computations to eliminate UI frame drops.

## Impact

- **Core Models & Services**: Extends `CalendarServiceManaging` and `EventKitCalendarService` with remote refresh (`refreshSourcesIfNecessary`) and store-change streaming (`eventStoreChanges`).
- **State Management**: Introduces a reusable `SingleflightCoordinator` and updates `AppState` to coordinate singleflighted syncs, sync progress state (`isSyncing`), and wake-from-sleep observation.
- **Views**: Modifies `PopoverContentView` to show the sync status indicator and `DailyTimelineView` to consume singleflighted/precomputed placed events without on-body layout recalculation.
- **Testing**: Expands `MockCalendarService` to simulate store-changed events, remote sync delays, and multi-trigger collision scenarios deterministically without system permissions or network access.
