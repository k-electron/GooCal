# Proposal

## Why

GooCal currently displays a static status card with a placeholder in its menu bar popover. Users need an immediate, at-a-glance visualization of their day that mirrors standard calendar day views: a vertically scrollable 24-hour timeline scaled to duration, with a live current-time marker and automatic viewport positioning (~1/3rd from the top) so they can instantly orient themselves in their daily schedule directly from the menu bar.

## What Changes

- **EventKit Integration**: Integrate macOS `EventKit` (`EKEventStore`) to fetch local and synced macOS calendar events for the active day, requesting calendar full-access permissions and declaring required privacy entitlements.
- **Continuous 24-Hour Vertical Timeline**: Replace the placeholder popover content with a scrollable 24-hour time canvas (scaled at 40 pt/hour, totaling 960 pt height) showing ~12 hours in the visible viewport (~480 pt height).
- **Initial Viewport Positioning**: Automatically anchor the scroll position upon opening so that the current time appears at approximately one-third from the top of the visible viewport.
- **Live Current-Time Indicator**: Render a live-updating horizontal marker line and badge across the timeline indicating the current minute using a periodic timeline trigger.
- **Event Filtering**:
  - Exclude all-day events from the timeline canvas.
  - Exclude declined events (where the current user's participant status is declined).
- **Multi-Day Boundary Clamping**: Clamp events that cross midnight to the current day boundary (`[00:00, 24:00]`) with visual edge indicators for events continuing from yesterday or into tomorrow.
- **Overlap Conflict Partitioning**:
  - Automatically detect concurrent/overlapping events.
  - Partition overlaps into up to 4 parallel visual columns.
  - Apply deterministic precedence ordering: Accepted > Busy > Organizer > Earlier Start Time > Shorter Duration.
  - For 5 or more overlapping events, render the top 3 events in columns 1–3, and the 4th event with a static `+N more` indicator in column 4.

## Capabilities

### New Capabilities
- `daily-timeline`: Calendar event querying via EventKit, time-to-coordinate projection engine, live time indicator, cross-day clamping, event filtering, and multi-column overlap layout.

### Modified Capabilities
- `menu-bar-app`: Popover window presents the scrollable daily timeline view alongside application settings and termination controls.

## Impact

- **Permissions & Entitlements**: Requires macOS calendar access entitlement (`com.apple.security.personal-information.calendars`) and `NSCalendarsFullAccessUsageDescription` in `Info.plist`.
- **UI Architecture**: Updates `PopoverContentView.swift` to host a fixed header, a scrollable timeline canvas with `ScrollViewReader`, and the existing footer controls.
- **Data Models & State**: Adds calendar service abstractions and models (`CalendarEvent`, `TimelineLayoutEngine`, `CalendarService`) integrated into `AppState`.
