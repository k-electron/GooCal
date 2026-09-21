# Contributing to GooCal

Thank you for your interest in contributing to **GooCal**! We welcome bug reports, documentation updates, feature requests, and code contributions.

---

## 1. Getting Started

### Prerequisites
- **macOS**: 14.0 (Sonoma) or newer
- **Xcode**: 16.0 or newer
- **Swift**: 6.0 toolchain
- **Git**: Configured for command-line development

### Setup Your Fork
1. Fork the repository on GitHub: `https://github.com/k-electron/GooCal`.
2. Clone your fork locally:
   ```bash
   git clone https://github.com/<your-username>/GooCal.git
   cd GooCal
   ```
3. Create a descriptive feature branch:
   ```bash
   git checkout -b feature/my-new-feature
   # or
   git checkout -b fix/timeline-alignment
   ```

---

## 2. Building & Testing Locally

### Building
Open `GooCal.xcodeproj` in Xcode 16 or build from Terminal:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -scheme GooCal -destination 'platform=macOS'
```

> [!NOTE]
> **Automatic File Synchronization**: This project uses Xcode 16 `PBXFileSystemSynchronizedRootGroup`. Any new Swift file added inside the `GooCal/` or `GooCalTests/` directories is automatically tracked and compiled without needing manual project file edits.

### Running Tests
All unit tests are written using the Apple **Swift Testing** framework (`import Testing`):
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -scheme GooCal \
  -destination 'platform=macOS' \
  -resultBundlePath TestResults.xcresult \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  DEVELOPMENT_TEAM=""
```

---

## 3. Engineering & Style Standards

### Swift 6 Concurrency
- Strict concurrency checking is enabled across the project.
- Value types transferred across concurrency domains must conform to `Sendable`.
- UI-bound state and views must be isolated to `@MainActor`.
- Services performing background coordination or streaming must be `Sendable` or actor-isolated.

### Memory Leak & Task Management
- Never launch unmanaged, floating `Task { ... }` blocks inside SwiftUI `.onAppear` handlers without lifecycle cancellation.
- Bind task lifecycles to view presentations using SwiftUI's `.task(id:)` modifier, ensuring automatic cancellation upon view dismissal or identity changes.
- Ensure notification observers and streaming loops properly handle task cancellation.

### Testing Contracts
- **Test outcomes, not implementations**: Tests should verify observable behaviors, geometric invariants, precedence hierarchies, and error handling rather than tautological sequences or change detectors.
- Use `MockCalendarService` to write fast, deterministic tests for calendar synchronization and error handling without requiring system calendar authorizations.

### SwiftUI Layout Rules
- **Scroll Anchors**: When creating scroll targets for `ScrollViewReader`, always provide concrete layout frames (e.g. `VStack` with measured spacers). Render-only `.offset(x:y:)` does not modify layout frames and will not scroll correctly.
- **Ruler & Capsule Typography**: Always enforce `.lineLimit(1)` and `.fixedSize(horizontal: true, vertical: true)` on compact badges and timeline markers to defend against localized text wrapping.

---

## 4. OpenSpec Specifications

For major architectural additions or behavior modifications, GooCal adheres to the **OpenSpec** specification-driven workflow:
- Review existing behavior contracts in `openspec/specs/`.
- Document new or modified capabilities before implementation.
- Validate specs using `openspec validate --strict`.

For more details on architecture and guidelines for automated tooling, see [**AGENTS.md**](AGENTS.md).

---

## 5. Submitting Changes

### Commit Messages
Follow [Conventional Commits](https://www.conventionalcommits.org/):
- `feat: ...` for user-facing features or new capabilities.
- `fix: ...` for bug fixes.
- `docs: ...` for documentation updates.
- `test: ...` for adding or improving test coverage.
- `chore: ...` for maintenance, build configurations, or dependencies.

### Document in Changelog
Add a concise description of your change to [`CHANGELOG.md`](CHANGELOG.md) under the `## [Unreleased]` section.

### Pull Request Checklist
Before opening your PR, please ensure:
1. `xcodebuild build` builds cleanly with zero errors.
2. The entire test suite passes cleanly via `xcodebuild test`.
3. Changes adhere to Swift 6 concurrency and zero-memory-leak guidelines.
4. `CHANGELOG.md` is updated under `[Unreleased]`.
5. GitHub Actions CI passes green on your PR branch.

Thank you for helping make GooCal even better!
