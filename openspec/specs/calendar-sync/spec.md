# calendar-sync Specification

## Purpose
Provides an energy-efficient, singleflighted calendar synchronization engine that responds to macOS EventKit database mutations, initiates remote server pulls, runs a sleep-safe periodic heartbeat, and recovers immediately upon system wake.

## Requirements

### Requirement: Singleflighted synchronization pipeline
The application SHALL coordinate all calendar synchronization triggers through a singleflight mechanism that deduplicates in-flight operations and coalesces concurrent requests into at most one trailing execution pass.

#### Scenario: Concurrent triggers coalesce into single trailing pass
- **WHEN** multiple synchronization triggers arrive while an operation is already in flight
- **THEN** the in-flight operation completes and exactly one trailing synchronization pass executes to capture pending updates

#### Scenario: In-flight request sharing
- **WHEN** a synchronization request arrives for an ongoing operation with identical scope
- **THEN** the request awaits the completion of the in-flight task without launching duplicate work

### Requirement: System event-driven synchronization
The application SHALL observe macOS calendar store change notifications to automatically refresh local calendar state when external modifications occur.

#### Scenario: External event change detected
- **WHEN** macOS emits an `EKEventStoreChanged` notification
- **THEN** the application queries the updated events for the currently active day and updates presentation state

#### Scenario: Notification burst debouncing
- **WHEN** multiple `EKEventStoreChanged` notifications arrive within a rapid time window
- **THEN** notifications are debounced so that at most one synchronization pass executes after the burst settles

### Requirement: Remote source refresh on demand
The application SHALL trigger a remote calendar synchronization pull (`refreshSourcesIfNecessary`) when requested by user interaction, operating asynchronously without blocking the user interface.

#### Scenario: Popover open triggers remote pull
- **WHEN** the user opens the popover window
- **THEN** the application instructs EventKit to refresh remote accounts asynchronously while maintaining interactive responsiveness

### Requirement: Sleep-friendly periodic heartbeat and wake recovery
The application SHALL run a periodic timer with kernel tolerance while the system is awake to advance upcoming meeting status and handle day rollovers without declaring power assertions, and SHALL immediately synchronize upon system wake.

#### Scenario: System wake triggers immediate catch-up
- **WHEN** the system wakes from sleep as notified by `NSWorkspace.didWakeNotification`
- **THEN** the application immediately refreshes calendar events, updates the active day if crossed midnight, and recalculates the menu bar title

#### Scenario: System sleep suspends background heartbeat without power assertion
- **WHEN** the system enters sleep or display idle
- **THEN** the application maintains zero power assertions, allowing the kernel to suspend background execution naturally

#### Scenario: Periodic meeting status advancement
- **WHEN** the application is running in the background and an ongoing meeting ends or a new meeting starts
- **THEN** the menu bar title and status message automatically advance to the next upcoming commitment
