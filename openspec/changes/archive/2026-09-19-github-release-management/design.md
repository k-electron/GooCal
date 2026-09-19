# Design

## Context

GooCal is a native macOS menu bar application built with Swift and Xcode. Continuous integration (`.github/workflows/ci.yml`) runs tests on pushes and PRs to `main`. 

Feature development occurs continuously on `main`, but user-facing releases occur less frequently, bundling multiple completed features, fixes, and improvements. A decoupled release pipeline is needed that packages `GooCal.app` into distribution formats (`.dmg` and `.zip`) only when a release is deliberately cut, deriving release notes from an accumulated changelog.

See `proposal.md` for motivation and scope; see `specs/release-management/spec.md` for normative requirements.

## Goals / Non-Goals

**Goals:**
- Provide a dedicated GitHub Actions release workflow (`.github/workflows/release.yml`) strictly triggered by version tags (e.g., `v1.0.0`) and manual dispatch, completely separate from continuous push-to-main CI.
- Support batched releases: allow multiple features to be developed and merged over time while accumulating notes in an `[Unreleased]` changelog section.
- Maintain a structured repository `CHANGELOG.md` following the Keep a Changelog specification.
- Extract release notes for the target version tag directly from `CHANGELOG.md` for the GitHub Release body, with fallback to auto-generated GitHub notes.
- Compile `GooCal.app` with `xcodebuild` in `Release` configuration.
- Package the compiled application into both `.dmg` and `.zip` distribution formats.
- Provide a reusable local/CI packaging script (`scripts/package-dmg.sh`) with native `hdiutil` fallback so maintainers can test DMG creation locally.
- Produce SHA-256 checksums (`.sha256`) for distributed artifacts.
- Support optional Apple Developer ID signing and Apple Notarization (`notarytool`), while gracefully falling back to ad-hoc code signing (`-`) when credentials are not configured.
- Automatically publish assets and release notes to GitHub Releases.
- Document the release procedure, changelog maintenance, secrets configuration, and macOS Gatekeeper guidelines in `RELEASING.md`.

**Non-Goals:**
- Automatic release on every feature merge; releases are intentionally batched.
- Mac App Store (MAS) distribution (which requires sandboxing and App Store Connect review).
- Automated in-app update framework integration (e.g., Sparkle) in this change; this pipeline produces the release binaries that can feed into an update framework later.

## Decisions

### Decision 1: DMG Packaging Mechanism
- **Choice**: Provide a shell script (`scripts/package-dmg.sh`) that attempts to use `create-dmg` for a styled disk image with drag-and-drop `/Applications` shortcut, falling back to macOS built-in `hdiutil` if `create-dmg` is unavailable.
- **Rationale**: Built-in `hdiutil` has zero dependencies and works out of the box on every macOS system and runner. `create-dmg` adds visual appeal (custom icon positioning, window size), and can be installed via Homebrew in CI. Having a script allows maintainers to test DMG generation locally as well as in CI.
- **Alternatives Considered**:
  - *Only ZIP files*: Simpler, but lacks the standard macOS installation UX that users expect when downloading desktop software.
  - *Third-party GitHub Action only (no script)*: Limits local reproducibility and testing.

### Decision 2: Dual Artifact Distribution (.dmg and .zip)
- **Choice**: Produce both `GooCal-<version>.dmg` and `GooCal-<version>.zip`.
- **Rationale**: `.dmg` is the preferred user-facing installer format. `.zip` is useful for scripting, package managers (such as Homebrew Cask), and auto-updaters. Both are generated cheaply from the same build output.
- **Alternatives Considered**:
  - *DMG only*: Hinders Homebrew Cask formulas or headless deployment scripts.

### Decision 3: Flexible Code Signing and Notarization
- **Choice**: The workflow conditionally checks for repository secrets (`APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`).
  - If configured: Decodes the certificate into a temporary keychain, signs with Developer ID Application, notarizes the app and DMG via `xcrun notarytool`, and staples the ticket via `xcrun stapler`.
  - If not configured: Ad-hoc signs with `codesign --force --deep -s -` (and `CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO`), allowing the build and release to succeed without paid Apple Developer credentials.
- **Rationale**: Enables immediate automated releases for open-source maintainers without requiring an Apple Developer account, while providing an upgrade path to notarized releases.
- **Alternatives Considered**:
  - *Enforcing Apple Developer ID*: Fails builds immediately if the repository has no paid Apple Developer subscription.
  - *No signing/notarization support*: Would require rewriting the pipeline when developer credentials are added later.

### Decision 4: Release Cadence & Changelog Management
- **Choice**: Follow the Keep a Changelog standard in `CHANGELOG.md` with an `[Unreleased]` section.
  - Everyday development: As PRs and features land in `main`, bullet points are added under `[Unreleased]`.
  - Release time: Maintainers rename `[Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`, open a fresh `## [Unreleased]` block, and push a tag `vX.Y.Z`.
  - CI extraction: A step in `.github/workflows/release.yml` extracts the section for `X.Y.Z` and passes it as the `body` to the release action. If the tag is not documented in `CHANGELOG.md`, the workflow falls back to GitHub's auto-generated release notes.
- **Rationale**: Decouples the fast pace of feature development from user-facing releases, keeping release notes clean, curated, and human-readable.
- **Alternatives Considered**:
  - *Generating releases on every commit to main*: Clutters GitHub Releases and user downloads with unstable micro-releases.
  - *Only auto-generated GitHub commits*: Commit titles often contain internal jargon or chore commits that are noisy for end-users.

### Decision 5: GitHub Actions Release Action
- **Choice**: Use `softprops/action-gh-release@v2` triggered on `tags: ['v*']` or `workflow_dispatch`.
- **Rationale**: Mature, widely adopted action that handles file uploads, glob patterns, release note bodies, draft/prerelease flags, and fallback release note generation.

## Risks / Trade-offs

- **[Risk] macOS Gatekeeper blocks ad-hoc signed apps on other Macs**
  - *Mitigation*: Clearly document in `RELEASING.md` and release notes how users can open ad-hoc signed apps (right-click -> Open, or running `xattr -cr /Applications/GooCal.app`). Provide clear instructions for adding Apple Developer secrets to enable notarization.
- **[Risk] Maintainer forgets to update CHANGELOG.md before tagging**
  - *Mitigation*: The workflow gracefully falls back to GitHub auto-generated release notes if the version section is missing from `CHANGELOG.md`, so the release never fails.
- **[Risk] DMG creation hangs or fails on headless CI runners**
  - *Mitigation*: The packaging script uses headless-friendly `hdiutil` operations or headless flags (`--no-mac-dmg` or non-Finder modes in `create-dmg`) to prevent GUI dialog blocks.
