# Tasks

## 1. Calendar Data Layer & Permissions

- [x] 1.1 Define `CalendarEvent` model with calendar color (`CGColor`), attendee participation status, and availability models, and verify with Swift Testing unit tests
- [x] 1.2 Define `CalendarServiceManaging` protocol and implement `MockCalendarService` with simulated authorization states and deterministic event fixtures
- [x] 1.3 Implement `EventKitCalendarService` using `EKEventStore` for calendar querying, macOS 14+ `requestFullAccessToEvents` permission requests, and calendar color extraction
- [x] 1.4 Add `com.apple.security.personal-information.calendars` entitlement and `NSCalendarsFullAccessUsageDescription` to Info.plist and project build settings

## 2. Timeline Layout & Collision Engine

- [x] 2.1 Implement `TimelineCoordinateConverter` mapping dates to Y-offsets and durations to heights ($40\,\text{pt}/\text{hour}$, min height $18\,\text{pt}$), and verify with unit tests
- [x] 2.2 Implement event filtering pipeline to exclude all-day events and declined invitations, and verify with unit tests
- [x] 2.3 Implement multi-day event clamping to active day boundaries (`[00:00, 24:00]`) with continuation flags, and verify with unit tests
- [x] 2.4 Implement overlap clustering, precedence ranking (Accepted > Busy > Organizer > Start Time > Shorter Duration), and column partitioning (max 4 columns + overflow count), and verify with unit tests

## 3. SwiftUI Timeline Views & Live Indicator

- [x] 3.1 Implement `TimelineGridView` rendering 24-hour rules and time labels from 00:00 to 23:00 on the canvas
- [x] 3.2 Implement `TimelineEventCard` styling with macOS calendar color (leading stripe and translucent tint), title, time, column frame, and multi-day edge indicators
- [x] 3.3 Implement `LiveTimeIndicatorView` backed by `TimelineView(.periodic(from: .now, by: 60))` to render the live marker line and current time badge
- [x] 3.4 Implement `DailyTimelineView` combining grid, event canvas, live marker, and `ScrollViewReader` with initial positioning anchor at one-third from the viewport top

## 4. AppState Integration & Popover Redesign

- [x] 4.1 Update `AppState` to inject `CalendarServiceManaging`, load current day events, and expose authorization status
- [x] 4.2 Update `PopoverContentView` to host the timeline header, scrollable `DailyTimelineView`, and footer controls (Settings and Quit)
- [x] 4.3 Implement permission-denied / empty state view in `DailyTimelineView` with guidance to open macOS System Settings

## 5. Verification & Testing

- [x] 5.1 Run test suite via `xcodebuild test` and verify all unit tests pass
- [x] 5.2 Build application target with `xcodebuild` and verify successful compilation without warnings
