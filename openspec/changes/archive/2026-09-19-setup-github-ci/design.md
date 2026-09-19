# Design

## Context

GooCal is a native macOS menu bar accessory app written in Swift and SwiftUI, built using `GooCal.xcodeproj` with three targets: `GooCal`, `GooCalTests`, and `GooCalUITests`.
The project is hosted in a public GitHub repository (`k-electron/GooCal`). GitHub Actions provides free, standard GitHub-hosted runners (including macOS runners) for public repositories.

Currently, no CI workflows exist in `.github/workflows/`. Additionally, the `GooCal` Xcode scheme is stored in user data (`xcuserdata`), meaning a fresh checkout on a CI runner cannot discover the scheme without shared scheme definitions.

See `proposal.md` for background and motivation.

## Goals / Non-Goals

**Goals:**
- Provide a zero-cost, automated CI workflow on GitHub Actions utilizing `macos-latest`.
- Trigger build and test execution on pushes to `main`, pull requests targeting `main`, and manual execution via `workflow_dispatch`.
- Ensure headless build and test execution via `xcodebuild` succeeds deterministically on clean checkouts by committing a shared Xcode scheme.
- Run both unit tests (`GooCalTests`) and UI tests (`GooCalUITests`).
- Archive and upload `.xcresult` test bundles as workflow artifacts on completion or failure for easy inspection.

**Non-Goals:**
- Code signing with Apple Developer certificates or notarization (deferred to release automation).
- Third-party or paid CI infrastructure (Bitrise, CircleCI, MacStadium).
- Automated version bumping, tagging, or GitHub Releases publishing.

## Decisions

### Decision 1: Use `macos-latest` GitHub-hosted runner
- **Choice**: Execute CI jobs on `runs-on: macos-latest`.
- **Rationale**: For public GitHub repositories, GitHub Actions provides free execution on standard runners, including macOS runners (which provide Apple Silicon hardware and recent macOS/Xcode environments).
- **Alternatives considered**:
  - *Linux runners*: Incompatible with macOS frameworks (AppKit, SwiftUI for macOS, XCTest macOS runner).
  - *Self-hosted macOS runners*: Adds maintenance, hardware, and operational costs.

### Decision 2: Commit Shared Scheme (`GooCal.xcscheme`)
- **Choice**: Create and commit `GooCal.xcodeproj/xcshareddata/xcschemes/GooCal.xcscheme`.
- **Rationale**: Xcode stores schemes in `xcuserdata` by default unless explicitly shared. CI runners clone the repository without `xcuserdata` (which is correctly gitignored), causing `xcodebuild -scheme GooCal` to fail with "The scheme 'GooCal' does not exist". Sharing the scheme makes it available immediately upon checkout.
- **Alternatives considered**:
  - *Auto-generating schemes on CI*: Fragile and dependent on undocumented Xcode CLI behaviors.

### Decision 3: Use Standard `xcodebuild` Tooling
- **Choice**: Run `xcodebuild test -scheme GooCal -destination 'platform=macOS' -resultBundlePath TestResults.xcresult`.
- **Rationale**: Uses native Apple toolchain without third-party dependencies (e.g. Fastlane), keeping CI startup time minimal and maintenance simple.
- **Alternatives considered**:
  - *Fastlane*: Adds Ruby runtime dependencies and overhead that are not needed for simple build/test workflows.

### Decision 4: Artifact Upload for Test Results
- **Choice**: Use `actions/upload-artifact@v4` with `if: always()` to upload `TestResults.xcresult`.
- **Rationale**: When tests fail, developers can inspect the `.xcresult` file locally in Xcode to see full stack traces, system logs, and UI test screenshots.
- **Alternatives considered**:
  - *Console logs only*: Difficult to debug UI test failures without screenshots and structured test attachments.

## Risks / Trade-offs

- **[Risk] UI Test Execution on macOS Runner** → *Mitigation*: GitHub-hosted macOS runners execute in an active GUI user session, allowing `GooCalUITests` to launch and interact with the application.
- **[Risk] Xcode Version Differences** → *Mitigation*: Keep build commands compatible with the standard macOS SDK. If specific Xcode pinning is required in the future, `DEVELOPER_DIR` can be pointed to specific preinstalled Xcode versions on the runner.
- **[Risk] Artifact Storage Limits** → *Mitigation*: Set `retention-days: 7` on test artifacts so storage is automatically pruned.
