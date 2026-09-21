# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-09-20

### Added
- 24-hour vertical timeline view in the menu bar popover (`DailyTimelineView`).
- Proportional event scaling at 40 points/hour with automatic overlap column layout (up to 4 parallel columns) and +N overflow indicator.
- macOS Calendar color integration deriving event card accents and tints directly from source calendar colors.
- Live current-time indicator line with a non-wrapping minute badge.
- Viewport autoscroll that automatically anchors the current time at one-third from the viewport top on appear, and scrolls fully down for late-day timestamps.
- App-wide singleflight synchronization pipeline (`SingleflightCoordinator`) with trailing pass coalescing to eliminate redundant calendar queries.
- Instant cached event presentation on popover open paired with asynchronous background remote refresh (`refreshSourcesIfNecessary`).
- Unified header refresh control supporting idle, in-flight progress spinner, error warning states with tooltip, and `⌘R` keyboard shortcut.
- System event-driven calendar synchronization listening to macOS `EKEventStoreChanged` notifications with debouncing.
- Sleep-friendly 60-second periodic heartbeat and instant wake recovery via `NSWorkspace.didWakeNotification`.
- Automated release management packaging DMG and ZIP distributions with checksums on GitHub.

### Fixed
- Autoscroll failure caused by render-only translation offset on the scroll target anchor.
- Multiline text wrapping in the live time indicator pill badge by expanding ruler width to 56 pt and applying non-wrapping layout constraints.
- Event filtering to exclude all-day events and declined calendar invitations from the timeline canvas.

## [1.0.0] - 2026-09-19

### Added
- Native macOS menu bar accessory application running without Dock presence (`LSUIElement`).
- Menu bar status icon with interactive popover window.
- Application Settings window accessible directly from the popover.
- Launch at Login toggle utilizing macOS `ServiceManagement`.
- GitHub Actions automated continuous integration testing suite.
