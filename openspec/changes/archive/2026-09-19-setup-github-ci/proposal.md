# Proposal

## Why

The GooCal project currently lacks automated continuous integration to validate builds and tests on code contributions. Establishing an automated GitHub Actions CI workflow using GitHub-hosted free-tier runners ensures that all commits and pull requests are automatically compiled and tested, preventing regressions without incurring infrastructure costs.

## What Changes

- Add a GitHub Actions CI workflow (`.github/workflows/ci.yml`) configured to run on pushes and pull requests to `main`, plus manual triggering (`workflow_dispatch`).
- Utilize GitHub's free-tier macOS runners (`macos-latest`) to build the application and run both unit (`GooCalTests`) and UI tests (`GooCalUITests`).
- Ensure the Xcode project has a shared scheme (`GooCal.xcodeproj/xcshareddata/xcschemes/GooCal.xcscheme`) committed to the repository so headless `xcodebuild` can reliably discover and execute the scheme on clean CI checkouts.
- Include build and test steps with log reporting, failure diagnostics, and test result bundle handling.

## Capabilities

### New Capabilities
<!-- Capabilities being introduced. Pure tooling/infrastructure change with skip_specs: true. -->
None.

### Modified Capabilities
<!-- Existing capabilities whose REQUIREMENTS are changing. -->
None.

## Impact

- **Tooling & CI**: Adds `.github/workflows/ci.yml`.
- **Xcode Project**: Adds shared scheme definition under `GooCal.xcodeproj/xcshareddata/xcschemes/GooCal.xcscheme`.
- **Application Code / APIs**: No changes to application code, runtime behavior, or public APIs.
