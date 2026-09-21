# daily-timeline Specification

## Purpose
Provides a continuous 24-hour vertical timeline view scaled to event duration, with live current-time tracking, multi-column overlap handling, and calendar event filtering.

## Requirements

### Requirement: Application queries calendar events for current day
The application SHALL query local and synced macOS calendar events for the active 24-hour day using EventKit, requesting full access authorization from macOS.

#### Scenario: Fetch events for current day
- **WHEN** the popover window opens or the active day refreshes
- **THEN** the system queries for all events occurring between 00:00:00 and 23:59:59 of that day

#### Scenario: Calendar permission denied or restricted
- **WHEN** calendar access authorization is denied or restricted by macOS
- **THEN** the timeline displays an informational empty state indicating that calendar access is required

### Requirement: Daily timeline renders 24-hour vertical scale
The application SHALL render a scrollable vertical canvas spanning 24 hours (00:00 to 24:00) where event block heights and Y-offsets are strictly proportional to their duration and start time at 40 points per hour.

#### Scenario: Event height and position mapped to scale
- **WHEN** an event starts at 10:00 and ends at 11:30
- **THEN** the event block is positioned at Y-offset 400 points from 00:00 and rendered with a height of 60 points

#### Scenario: Short events maintain minimum readable height
- **WHEN** an event has a short duration resulting in a calculated height under 18 points
- **THEN** the event block enforces a minimum height of 18 points so title text remains visible

### Requirement: Timeline displays live current time indicator
The application SHALL render a visible indicator at the exact vertical coordinate corresponding to the current time, updating every minute, and anchor the initial scroll position to keep the current time visible.

#### Scenario: Live indicator tracks current minute
- **WHEN** the popover is presented
- **THEN** a colored horizontal marker line and time badge appear at the Y-offset of the current minute and advance each minute

#### Scenario: Viewport initial scroll position
- **WHEN** the popover appears for the current day
- **THEN** the scroll view automatically positions the current time marker approximately one-third from the top of the visible viewport

### Requirement: Timeline excludes all-day and declined events
The application SHALL filter queried events to omit all-day events and events where the current user's participant status is declined.

#### Scenario: Exclude all-day events
- **WHEN** a calendar event has `isAllDay` set to true
- **THEN** the event is not rendered on the vertical timeline canvas

#### Scenario: Exclude declined invitations
- **WHEN** the current user is an attendee with a participant status of declined
- **THEN** the event is not rendered on the vertical timeline canvas

### Requirement: Clamping multi-day events to day boundaries
The application SHALL clamp timed events spanning across midnight to the active day's `[00:00, 24:00]` boundary and render directional edge indicators.

#### Scenario: Event continues from yesterday
- **WHEN** an event starts before 00:00 of the active day and ends during the active day
- **THEN** the event start is clamped to 00:00 and visually indicates continuation from the previous day

#### Scenario: Event continues into tomorrow
- **WHEN** an event starts during the active day and ends after 23:59:59
- **THEN** the event end is clamped to 24:00 and visually indicates continuation into the next day

### Requirement: Multi-column partitioning for concurrent events
The application SHALL partition overlapping events into up to 4 parallel visual columns, ranking events by precedence and displaying a static overflow indicator when 5 or more events overlap.

#### Scenario: Up to four overlapping events
- **WHEN** up to 4 events have overlapping time intervals
- **THEN** the available timeline width is divided equally across columns with each event placed in its own column

#### Scenario: Overlap ranking precedence
- **WHEN** concurrent events compete for column assignment
- **THEN** events are sorted in descending order of precedence: Accepted response > Busy status > Organizer role > Earlier start time > Shorter duration

#### Scenario: Five or more overlapping events
- **WHEN** 5 or more events overlap in the same time interval
- **THEN** the first 3 columns display the top 3 ranked events, and the 4th column displays the 4th ranked event along with a static indicator showing the count of additional overlapping events

### Requirement: Event presentation inherits macOS calendar coloring
The application SHALL style each timeline event card with visual accents and background tints derived directly from its source macOS calendar's assigned color.

#### Scenario: Event card styled with calendar color
- **WHEN** an event associated with a specific calendar is rendered on the timeline
- **THEN** its card displays a leading vertical stripe using the exact calendar color and a complementary translucent tinted background

#### Scenario: High-contrast text legibility
- **WHEN** event title and time are displayed over the tinted background in light or dark appearance
- **THEN** text is rendered using semantic high-contrast primary and secondary foreground styles to ensure readability regardless of calendar color saturation
