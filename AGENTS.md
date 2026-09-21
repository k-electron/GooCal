# AI Agent Guidelines & Architecture Manual (AGENTS.md)

This document provides architectural context, development rules, and workflow standards for AI agents, subagents, and automated developer tooling working in the **GooCal** repository.

---

## 1. Project Overview & Technology Stack

**GooCal** is a high-performance, battery-friendly native macOS menu bar calendar application designed to provide instant visibility into daily schedules with zero Dock clutter and zero background battery drag.

- **Platform Target**: macOS 14.0+ (Sonoma)
- **Language & Toolchain**: Swift 6, Xcode 16+
- **UI Framework**: SwiftUI (modern declarative hierarchy with `@Observable`)
- **System Frameworks**: EventKit (calendar data), ServiceManagement (Launch at Login), AppKit (window & popover management)
- **Project Configuration**: Xcode 16 `PBXFileSystemSynchronizedRootGroup` (new files created under `GooCal/` and `GooCalTests/` are automatically tracked and compiled without manually modifying `project.pbxproj`)
- **Testing Framework**: Apple Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`)

---

## 2. Architecture & Core Subsystems

```
┌─────────────────────────────────────────────────────────────┐
│                    MenuBarExtra (.window)                    │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                  PopoverContentView                   │  │
│  │  - Date Navigation Header (Today, Previous, Next)     │  │
│  │  - Unified Refresh Control (Idle, Syncing, Error, ⌘R) │  │
│  │                                                       │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │               DailyTimelineView                 │  │  │
│  │  │  - 24-Hour Grid (TimelineGridView: 40 pt/hr)    │  │  │
│  │  │  - Clustered Cards (TimelineEventCard)          │  │  │
│  │  │  - Live Marker (LiveTimeIndicatorView)          │  │  │
│  │  │  - Viewport Autoscroll Anchor                   │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  │                                                       │  │
│  │  - Fixed Footer (Quit, Settings Access)               │  │
│  └───────────────────────────────────────────────────────┘  │
└──────────────────────────────┬──────────────────────────────┘
                               │ Observes
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                      AppState (@Observable)                  │
│  - selectedDate: Date                                       │
│  - events: [CalendarEvent]                                  │
│  - placedEvents: [PlacedEvent] (precomputed placement)      │
│  - isSyncingRemote: Bool                                    │
│  - syncError: (any Error)?                                  │
│                                                             │
│  Pipelines:                                                 │
│  - SingleflightCoordinator: coalescing concurrent refreshes │
│  - Store change observation: EKEventStoreChanged debouncing │
│  - Sleep/Wake lifecycle: NSWorkspace.didWakeNotification    │
│  - Background heartbeat: 60s periodic timer with tolerance   │
└──────────────────────────────┬──────────────────────────────┘
                               │ Calls
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                   CalendarServiceManaging                   │
│  ┌─────────────────────────┐     ┌───────────────────────┐  │
│  │ EventKitCalendarService │     │  MockCalendarService  │  │
│  │ (Production EventKit)   │     │  (Isolated Testing)   │  │
│  └─────────────────────────┘     └───────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Key Modules & Responsibilities

1. **`AppState` (`GooCal/AppState.swift`)**:
   - Central `@MainActor @Observable` store.
   - Handles singleflighted calendar synchronizations via `SingleflightCoordinator`.
   - Computes event card clustering and column assignments off the main view body pass into `placedEvents` to eliminate layout thrashing.
   - Observes system sleep/wake notifications (`didWakeNotification`) to refresh commitments instantly when waking up.
   - Runs a sleep-friendly 60-second background heartbeat with generous timer tolerance and zero power assertions.

2. **`SingleflightCoordinator` (`GooCal/SingleflightCoordinator.swift`)**:
   - Generic actor deduplicating in-flight work and coalescing overlapping requests into at most one trailing execution pass.
   - Guarantees that multiple concurrent triggers (e.g., popover open, store change notification, wake-from-sleep) do not overwhelm EventKit or trigger redundant database passes.

3. **`CalendarServiceManaging` (`GooCal/CalendarServiceManaging.swift`)**:
   - `Sendable` protocol abstracting calendar authorization, event fetching, remote source synchronization (`refreshSources()`), and store mutation streaming (`storeChanges: AsyncStream<Void>`).
   - Implemented by `EventKitCalendarService` for production macOS calendars, and `MockCalendarService` for fast, deterministic, offline unit testing.

4. **`TimelineCoordinateConverter` (`GooCal/TimelineCoordinateConverter.swift`)**:
   - Converts calendar timestamps to points at a fixed scale of $40\text{ pt/hour}$ ($960\text{ pt}$ total canvas height).
   - Enforces a minimum visual card height of $18\text{ pt}$ for brief meetings so titles remain legible.
   - Calculates viewport target scroll offsets anchoring the current time at $\approx 1/3\text{rd}$ from the viewport top (clamped within $[0, 480\text{ pt}]$).

5. **`TimelineLayoutEngine` (`GooCal/TimelineLayoutEngine.swift`)**:
   - Filters out all-day events (`isAllDay == true`) and declined invitations (`participantStatus == .declined`).
   - Clamps multi-day events crossing midnight to $[00:00, 24:00]$ while flagging `spansFromYesterday` and `spansIntoTomorrow`.
   - Clusters overlapping events and sorts them by deterministic precedence:
     1. Response: `.accepted` > `.tentative` > `.pending` > `.unknown`
     2. Availability: `.busy` > `.unavailable` > `.tentative` > `.free`
     3. Role: `isOrganizer` > attendee
     4. Start Time: earlier > later
     5. Duration: shorter > longer
   - Assigns up to 4 parallel visual columns (`columnIndex: 0..<4`). When 5+ events overlap, assigns top 3 to columns 0–2 and places the 4th in column 3 with `overflowCount = total - 4`.

6. **Timeline Views**:
   - `DailyTimelineView`: Root vertical scroll canvas containing the ruler grid, event cards, live marker, and concrete layout anchor for automated scrolling.
   - `TimelineGridView`: 24-hour horizontal hairline dividers with localized hour labels in a $56\text{ pt}$ ruler column.
   - `TimelineEventCard`: Card styled with source calendar color vertical stripe, translucent fill, high-contrast text, directional continuation flat-edges, and `+N more` badge.
   - `LiveTimeIndicatorView`: 60-second periodic `TimelineView` updating the horizontal red marker line and non-wrapping time capsule pill.

---

## 3. Engineering Guidelines & Constraints

### Concurrency & State Management
- **Swift 6 Standards**: Adhere strictly to Swift 6 concurrency rules. All model types passed across concurrency boundaries must be `Sendable` (prefer immutable value types).
- **Actor Isolation**: Keep UI state on `@MainActor`. Services or coordinators performing asynchronous work, debouncing, or background streaming must be actors or `Sendable` types.
- **No Retain Cycles / No Memory Leaks**:
  - Do NOT create unmanaged `Task { ... }` blocks in `.onAppear` without lifecycle cancellation.
  - Use SwiftUI's `.task(id:)` modifier which automatically cancels the task when the view unmounts or the bound identity changes.
  - When storing closures or notification observers, always consider capture semantics and ensure cancellation on teardown.

### SwiftUI Layout & Performance
- **Layout Anchors vs Visual Transforms**: `ScrollViewReader.scrollTo()` inspects the layout frame of target views. Never use `.offset(x:y:)` on scroll anchors; use concrete layout views (such as a `VStack` with a top spacer) so the anchor view's layout origin matches the desired coordinate.
- **Text Wrapping Defense**: For compact labels (like the timeline ruler pill badge), always enforce `.lineLimit(1)` and `.fixedSize(horizontal: true, vertical: true)` to avoid unexpected multiline wrapping in varied system locales and font scales.
- **Memoized Placements**: Keep expensive clustering algorithms outside view body evaluation. Let `AppState` compute and store `placedEvents` asynchronously.

### Testing Conventions
- **Swift Testing Framework**: Use `import Testing`, `@Suite`, `@Test`, and `#expect(...)`. Avoid legacy `XCTestCase` unless testing UI automation runners.
- **Non-Tautological Tests**:
  - Test **observable outcomes, invariants, and behavioral contracts**, not implementation sequences or tautological identity checks.
  - In layout tests, verify coordinate clamping, column bounds, precedence ordering, and overflow math.
  - In calendar services, use `MockCalendarService` to simulate error propagation, store changes, and singleflight deduplication deterministically.

---

## 4. Key Commands Quick Reference

| Action | Command |
|---|---|
| **Build App** | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -scheme GooCal -destination 'platform=macOS'` |
| **Build for Testing** | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing -scheme GooCal -destination 'platform=macOS'` |
| **Fast CLI Test Run** | `DYLD_FRAMEWORK_PATH=build/Build/Products/Debug/GooCal.app/Contents/MacOS DYLD_LIBRARY_PATH=build/Build/Products/Debug/GooCal.app/Contents/MacOS /Applications/Xcode.app/Contents/Developer/usr/bin/xctest build/Build/Products/Debug/GooCal.app/Contents/PlugIns/GooCalTests.xctest` |
| **Run All Tests (CI Style)** | `xcodebuild test -scheme GooCal -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=""` |
| **Validate OpenSpec** | `openspec validate --strict` |
| **Package DMG & ZIP** | `./scripts/package-dmg.sh build/Build/Products/Release/GooCal.app dist <version>` |

---

## 5. OpenSpec Specification-Driven Workflow

This repository uses [OpenSpec](openspec/) to ensure all major features and refactors are planned, specified, and verified before integration.

- **Main Specs (`openspec/specs/<capability>/spec.md`)**: The single source of truth for behavior contracts.
- **Active Changes (`openspec/changes/<change-name>/`)**: Proposals, delta specifications, designs, and tasks for in-flight work.
- **Archived Changes (`openspec/changes/archive/YYYY-MM-DD-<change-name>/`)**: Historical records of completed and verified changes.
- **Workflow**:
  1. Propose change via `proposal.md`, `specs/**/*.md`, `design.md`, and `tasks.md`.
  2. Implement tasks step-by-step with outcome-oriented unit tests.
  3. Verify the full test suite passes and zero warnings exist.
  4. Sync delta specs to main specs and archive via `openspec/changes/archive/`.
