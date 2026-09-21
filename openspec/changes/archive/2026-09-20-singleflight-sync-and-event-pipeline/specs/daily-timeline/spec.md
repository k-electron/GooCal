# Spec Delta

## MODIFIED Requirements

### Requirement: Application queries calendar events for current day
The application SHALL query local and synced macOS calendar events for the active 24-hour day using EventKit, requesting full access authorization from macOS. On popover presentation or manual trigger, the system SHALL render cached events immediately while initiating non-blocking background synchronization and presenting a unified refresh control that transitions between idle, in-flight progress, and retry-warning states.

#### Scenario: Fetch events for current day
- **WHEN** the popover window opens or the active day refreshes
- **THEN** existing in-memory events for the active day are rendered immediately without blank states, and the system queries for all events occurring between 00:00:00 and 23:59:59 of that day

#### Scenario: Active synchronization progress indicator
- **WHEN** remote source synchronization is in flight
- **THEN** the refresh control swaps into an active standard spinner animation, is disabled against concurrent triggers, and returns to the standard refresh icon upon completion

#### Scenario: Manual refresh button triggers sync
- **WHEN** the user clicks the refresh button or presses the ⌘R keyboard shortcut
- **THEN** a singleflighted synchronization pass is scheduled and the control transitions to the progress animation

#### Scenario: Synchronization error displays retry warning badge
- **WHEN** calendar synchronization fails due to an error or offline state
- **THEN** the refresh control icon transforms into a yellow warning indicator, displays error details on hover, and retains clickability to retry synchronization

#### Scenario: Calendar permission denied or restricted
- **WHEN** calendar access authorization is denied or restricted by macOS
- **THEN** the timeline displays an informational empty state indicating that calendar access is required

## ADDED Requirements

### Requirement: Singleflighted event card layout computation
The application SHALL compute event clustering, precedence ranking, and column slotting asynchronously off the main actor or memoized to avoid layout thrashing and UI frame drops during view invalidation.

#### Scenario: Rapid update coalescing for layout engine
- **WHEN** multiple event updates arrive in rapid succession
- **THEN** event placement calculations are deduplicated and executed at most once for trailing state before rendering the timeline
