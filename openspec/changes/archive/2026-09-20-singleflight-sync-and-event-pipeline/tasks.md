# Tasks

## 1. Singleflight Primitives & Unit Tests

- [x] 1.1 Implement generic `SingleflightCoordinator<Key, Value>` actor supporting deduplication and trailing pass coalescing, verified with concurrent unit tests in `SingleflightCoordinatorTests.swift`.
- [x] 1.2 Implement task cancellation and error propagation handling in `SingleflightCoordinator`, verified with test cases covering thrown errors and task cancellations.

## 2. Calendar Service Protocol & EventKit Integration

- [x] 2.1 Extend `CalendarServiceManaging` protocol with `refreshSources() async throws` and `var storeChanges: AsyncStream<Void> { get }`, updating `MockCalendarService` with simulated change streams and verified by unit tests.
- [x] 2.2 Implement `refreshSources()` (calling `eventStore.refreshSourcesIfNecessary()`) and `EKEventStoreChanged` notification observation in `EventKitCalendarService`, verified by unit tests.

## 3. AppState Singleflighted Sync Pipeline & Sleep-Safe Lifecycle

- [x] 3.1 Integrate `SingleflightCoordinator` into `AppState` to coordinate `refreshEvents()` with `isSyncingRemote` state and trailing execution, verified by concurrency unit tests in `AppStateCalendarTests.swift`.
- [x] 3.2 Implement store change observer in `AppState` with a 250ms debounce to automatically ingest external calendar updates, verified by tests yielding store changes via `MockCalendarService`.
- [x] 3.3 Implement sleep-friendly 60-second background heartbeat with kernel tolerance and `NSWorkspace.didWakeNotification` observer in `AppState` for instant wake recovery and midnight rollover, verified by unit tests.
- [x] 3.4 Move `TimelineLayoutEngine` clustering and placement computation off the main actor into precomputed `AppState.placedEvents` to eliminate layout thrashing in view body evaluation, verified by unit tests.

## 4. UI Indicators & Seamless Presentation

- [x] 4.1 Update `PopoverContentView` header with unified refresh button control supporting idle icon (`arrow.clockwise`), in-flight progress spinner (`ProgressView`), yellow failure badge (`exclamationmark.triangle.fill`), hover tooltip with error details, and ⌘R keyboard shortcut, verified by UI inspection and tests.
- [x] 4.2 Update `DailyTimelineView` to bind to precomputed `placedEvents` from `AppState`, verifying event cards render without layout jumps.

## 5. Verification & Regression Testing

- [x] 5.1 Run the full GooCal test suite via `xcodebuild test` ensuring all existing and new tests pass cleanly with zero concurrency or regression issues.
