# GooCal

<div align="center">

**A lightweight, battery-friendly native macOS menu bar calendar.**  
*Built with Swift 6, SwiftUI, and EventKit for macOS 14+ (Sonoma).*

[![CI](https://github.com/k-electron/GooCal/actions/workflows/ci.yml/badge.svg)](https://github.com/k-electron/GooCal/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/k-electron/GooCal?include_prereleases&color=blue)](https://github.com/k-electron/GooCal/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014.0%2B-lightgrey)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange)](https://swift.org)

</div>

---

## Highlights

* **24-Hour Vertical Timeline Canvas**: A continuous vertical timeline view scaled strictly to meeting duration ($40\text{ pt/hour}$, $960\text{ pt}$ daily canvas) providing an intuitive "to-scale" view of your day.
* **Intelligent Multi-Column Layout**: Automatically partitions overlapping meetings into up to 4 parallel visual columns, with deterministic precedence ranking and a `+N more` overflow indicator for dense slots.
* **Live Current-Time Indicator**: Horizontal marker line and non-wrapping time capsule badge updated on minute boundaries via isolated periodic timeline rendering.
* **Smart Viewport Autoscroll**: Automatically anchors your current time at $\approx 1/3\text{rd}$ from the top of the viewport when opening the popover, contextually preserving visibility for recent past events while prioritizing upcoming meetings. Late in the day, it smoothly scrolls all the way down.
* **macOS Calendar Color Sync**: Seamlessly derives card visual accents, leading indicator bars, and translucent backgrounds directly from your configured macOS Calendar colors (Google Calendar, iCloud, Exchange, CalDAV).
* **Singleflight Synchronization Pipeline**: Eliminates redundant calendar queries and battery drag by deduplicating in-flight requests and coalescing concurrent triggers into at most one trailing pass.
* **Instant Cached Presentation & Event-Driven Updates**: Renders cached events immediately upon popover open paired with asynchronous background remote refresh (`refreshSourcesIfNecessary`) and a unified refresh control. Observes macOS `EKEventStoreChanged` notifications with debouncing.
* **Sleep-Safe & Zero Battery Drag**: Employs a 60-second periodic heartbeat with kernel tolerance and zero power assertions—never preventing your Mac from sleeping—and catches up immediately upon wake (`NSWorkspace.didWakeNotification`).
* **Menu Bar Accessory Mode (`LSUIElement`)**: Runs purely in the macOS menu bar without cluttering your Dock or `⌘Tab` app switcher. Includes optional Launch at Login support via `ServiceManagement`.

---

## Installation

### Download from GitHub Releases

1. Download the latest **`GooCal-<version>.dmg`** from [**Releases**](https://github.com/k-electron/GooCal/releases).
2. Open the disk image and drag **GooCal.app** into your **Applications** folder.
3. Open GooCal from `/Applications`.

> [!NOTE]
> **macOS Gatekeeper First Launch**: Because community builds are signed ad-hoc, macOS may prompt: *"GooCal can't be opened because Apple cannot check it for malicious software"*.  
> To approve: Right-click (or Control-click) `GooCal.app` in Finder, select **Open**, and click **Open** in the prompt. Alternatively, run:
> ```bash
> xattr -cr /Applications/GooCal.app
> ```

---

## Building from Source

### Prerequisites
- macOS 14.0 (Sonoma) or newer
- Xcode 16.0 or newer
- Swift 6 toolchain

### Build & Run Locally
```bash
# Clone the repository
git clone https://github.com/k-electron/GooCal.git
cd GooCal

# Build Debug app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -scheme GooCal -destination 'platform=macOS'

# Run all unit tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -scheme GooCal -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=""
```

---

## Usage & Controls

- **Open Schedule**: Click the GooCal icon in your macOS menu bar.
- **Date Navigation**: Click **Previous Day** (`‹`), **Next Day** (`›`), or the **Today** button to jump to the active day.
- **Refresh Calendar**: Click the refresh button in the header or press **`⌘R`**.
- **Settings**: Click the **Settings...** button in the footer or press **`⌘,`** to configure preferences such as Launch at Login.
- **Quit Application**: Click **Quit** in the popover footer.

---

## Architecture & Design

GooCal is engineered around modern Swift 6 paradigms:

- **State Management**: `@MainActor @Observable AppState` coordinates selection, event caching, precomputed layout cards, and remote sync states without layout thrashing.
- **Concurrency**: Actor-isolated `SingleflightCoordinator` guarantees thread-safe, coalesced query operations.
- **Calendar Data**: `CalendarServiceManaging` protocol abstracts EventKit access, with full implementations in `EventKitCalendarService` and deterministic test mocks in `MockCalendarService`.
- **Layout Math**: Pure, testable coordinate and layout logic isolated in `TimelineCoordinateConverter` and `TimelineLayoutEngine`.

For detailed architecture diagrams, component specs, and agent instructions, see [**AGENTS.md**](AGENTS.md).

---

## Contributing

Contributions, issues, and feature suggestions are very welcome! Please review [**CONTRIBUTING.md**](CONTRIBUTING.md) for guidelines on code conventions, test standards, and the pull request process.

---

## Documentation Links

- [**Changelog**](CHANGELOG.md): Historical record of versions, features, and fixes.
- [**Agent Guidelines (AGENTS.md)**](AGENTS.md): Architecture manual and guidance for AI assistants.
- [**Contributing Guide**](CONTRIBUTING.md): Setup instructions, test contracts, and contribution flow.
- [**Release Guide (RELEASING.md)**](RELEASING.md): Build automation, packaging, and GitHub release pipeline.
- [**OpenSpec Specifications**](openspec/): Behavior contracts and formal specifications.

---

## License

GooCal is open-source software licensed under the [**MIT License**](LICENSE).  
Copyright © 2026 Karim Fatehi.
