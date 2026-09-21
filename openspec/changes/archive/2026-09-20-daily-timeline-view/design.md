# Design

## Context

See `proposal.md` for motivation. GooCal currently operates as an accessory menu bar application (`LSUIElement = true`) with a simple popover window defined in `PopoverContentView.swift` and backed by `AppState.swift`. The application does not yet integrate with any calendar data source or render calendar views.

## Goals / Non-Goals

**Goals:**
- Provide a `CalendarServiceManaging` protocol and production `EventKitCalendarService` using Apple's `EventKit` framework to query macOS calendar events for the active day.
- Provide a `MockCalendarService` enabling deterministic unit testing of calendar event querying, error states, and permissions without interacting with macOS system privacy dialogs or headless CI restrictions.
- Implement a pure, deterministic `TimelineLayoutEngine` that:
  - Clamps events crossing midnight to `[00:00, 24:00]`.
  - Filters out all-day events (`isAllDay == true`) and declined events (`participantStatus == .declined`).
  - Clusters overlapping events and partitions them into parallel columns (up to 4).
  - Sorts concurrent events by precedence (Accepted > Busy > Organizer > Start Time > Shorter Duration).
  - Emits layout metadata including column index, total columns, Y-offset, height, and overflow count (`+N more`) for 5+ overlaps.
- Render a 24-hour vertical timeline in SwiftUI ($40\,\text{pt}/\text{hour}$, total canvas $960\,\text{pt}$, visible viewport $\approx 480\,\text{pt}$).
- Track current time with a live horizontal indicator updating every minute via `TimelineView`.
- Automatically position the scroll viewport on appear so that the current time marker is positioned at approximately one-third from the top of the visible view.

**Non-Goals:**
- Event creation, deletion, or editing.
- Interactive popovers, detail inspection, or action sheets on event tap (deferred to a future specification).
- All-day event banner or shelf (all-day events are completely excluded from this view).
- Direct Google Calendar OAuth REST integration (macOS EventKit natively synchronizes all Google, iCloud, and Exchange accounts configured in macOS System Settings).

## Decisions

### 1. Data Source Abstraction (`CalendarServiceManaging`)
- **Decision**: Define a protocol `CalendarServiceManaging: Sendable` that returns an asynchronous stream or array of `CalendarEvent` models for a given date range.
- **Rationale**: Direct usage of `EKEventStore` in SwiftUI views prevents unit testing and breaks in headless CI environments. Injecting `CalendarServiceManaging` into `AppState` preserves deterministic testing patterns established in `LaunchAtLoginManaging`.
- **Alternatives Considered**: Direct Google Calendar REST API with OAuth tokens. Rejected because EventKit already synchronizes Google Calendar accounts configured on macOS without managing refresh tokens, network retries, or custom auth flows.

### 2. Time-to-Coordinate Scale ($40\,\text{pt}/\text{hour}$)
- **Decision**: Set the vertical scale factor to $40\,\text{pt}/\text{hour}$ ($0.667\,\text{pt}/\text{minute}$). Total 24-hour canvas height is $960\,\text{pt}$.
- **Rationale**: An hour scale of 40pt allows approximately 12 hours of the day to fit within a standard $480\,\text{pt}$ popover viewport without feeling cramped or requiring excessive scrolling. A 30-minute event is $20\,\text{pt}$ tall, which remains readable when enforcing a minimum height of $18\,\text{pt}$ for brief meetings.
- **Alternatives Considered**:
  - $60\,\text{pt}/\text{hour}$ ($1\,\text{pt}/\text{min}$, $1440\,\text{pt}$ total): Shows only 8 hours at a time, requiring excessive scrolling.
  - $30\,\text{pt}/\text{hour}$ ($720\,\text{pt}$ total): Too compressed for 15–30 minute meeting titles.

### 3. Viewport Anchoring via `ScrollViewReader`
- **Decision**: Anchor the initial scroll position by computing the target offset:
  $$\text{targetY} = y(\text{currentTime}) - \frac{\text{viewportHeight}}{3}$$
  clamped to $[0, 960 - \text{viewportHeight}]$.
- **Rationale**: Placing current time at one-third from the top matches user mental models: they see recent past events for context, while preserving the majority of the visible area for upcoming meetings throughout the day.
- **Alternatives Considered**: Anchoring current time at the top edge ($y(\text{currentTime})$). Rejected because it cuts off recently completed or active meetings that started 10–15 minutes ago.

### 4. Live Time Indicator via Isolated `TimelineView`
- **Decision**: Implement the live red line and badge within a dedicated `LiveTimeIndicatorView` backed by `TimelineView(.periodic(from: .now, by: 60))`.
- **Rationale**: `TimelineView` selectively invalidates only the indicator layer on the minute boundary without triggering layout recalculations or re-fetching calendar events across the entire view hierarchy.
- **Alternatives Considered**: Combine-based `Timer.publish` on `AppState`. Rejected because mutating `AppState` invalidates the entire popover view body.

### 5. Overlap Layout Algorithm & Precedence
- **Decision**: Use a deterministic 3-stage layout pipeline:
  1. **Clustering**: Group events whose active time ranges intersect.
  2. **Ranking**: Sort events within each cluster by precedence:
     - Attendee Status: `.accepted` > `.tentative` > `.pending`
     - Availability: `.busy` > `.free`
     - Role: `.organizer` > `.attendee`
     - Start Time: Earlier `startDate` before later
     - Duration: Shorter before longer
  3. **Column Slotting**: Assign each event a column index (`0...min(3, count - 1)`). If cluster count $\ge 5$, columns 0–2 receive the top 3 events, and column 3 receives the 4th event with `overflowCount = cluster.count - 4`.
- **Rationale**: Guarantees predictable, non-jittery column placement and ensures the user's most critical commitments (accepted meetings, organizer responsibilities) receive visual prominence over tentative invitations.

### 6. Event Coloring Derived from macOS Calendar
- **Decision**: Extract `calendar.cgColor` directly from each `EKEvent` when constructing `CalendarEvent` models and apply it in `TimelineEventCard`:
  - A prominent 3pt leading vertical indicator bar using `Color(cgColor: event.calendarColor)`.
  - A soft, translucent event card background using `Color(cgColor: event.calendarColor).opacity(0.18)`.
  - Legible text styling using `.foregroundStyle(.primary)` for title and `.foregroundStyle(.secondary)` for time range, ensuring clarity under both light and dark macOS appearances.
- **Rationale**: Matches standard Apple Calendar visual conventions, instantly identifying which calendar/account (work, personal, on-call) an event belongs to without manual palette configuration.
- **Alternatives Considered**: Custom user-defined color overrides in Settings. Rejected to maintain parity with macOS Calendar settings and zero-configuration friction.

### 7. Modern Swift & SwiftUI Architecture Standards
- **Decision**: Strictly align with macOS 14+ / Swift 6 standards across the implementation:
  - **Observation Framework**: Use `@Observable` macro and `@MainActor` on view models/state (`AppState`), eliminating legacy `ObservableObject` and `@Published`.
  - **Swift Concurrency**: Enforce `Sendable` on all event models and background service protocols.
  - **Swift Testing**: Author unit tests exclusively using Apple's modern Swift Testing framework (`import Testing`, `@Suite`, `@Test`, `#expect(...)`) rather than legacy `XCTest`.
  - **Modern EventKit Authorization**: Call macOS 14+ `EKEventStore.requestFullAccessToEvents()` rather than deprecated access request APIs.
  - **Modern SwiftUI View Modifiers**: Use `.foregroundStyle`, `.tint`, `.background(..., in: RoundedRectangle(...))`, and `TimelineView` instead of legacy styling patterns.


## Risks / Trade-offs

- **[Risk] System Calendar Permission Denial**  
  *Mitigation*: Detect `EKAuthorizationStatus.denied` or `.restricted` in `CalendarService` and render an actionable in-popover card with instructions and a button to open macOS System Settings (`x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars`).
- **[Risk] SwiftUI `ScrollViewReader` layout timing on initial popover display**  
  *Mitigation*: Dispatch the `scrollTo` call inside a `.task` or with a slight asynchronous delay (`Task { @MainActor in proxy.scrollTo(...) }`) to allow the parent window frame and geometry to stabilize.
- **[Risk] Headless CI build & test failures without macOS entitlements**  
  *Mitigation*: Keep `MockCalendarService` as the default test harness. Ad-hoc sign the test bundle and mock all `EKEvent` wrappers as pure Swift value types (`CalendarEvent`).
