# Proposal

## Why

GooCal currently lacks an automated release and distribution pipeline. Feature development proceeds on `main`, but maintainers need a reliable, decoupled way to package and publish periodic releases containing accumulated features as macOS binaries. Automating release management on GitHub enables maintainers to cut releases on demand, packaging `GooCal.app` into standard macOS `.dmg` disk images and `.zip` archives, pulling curated release notes from a repository `CHANGELOG.md`, and publishing them to GitHub Releases.

## What Changes

- **GitHub Actions Release Workflow**: Introduce `.github/workflows/release.yml` strictly triggered on version tags (e.g., `v*`) and manual triggers (`workflow_dispatch`), completely decoupled from everyday push-to-main CI.
- **Repository Changelog**: Add a curated `CHANGELOG.md` following the [Keep a Changelog](https://keepachangelog.com/) format with an `[Unreleased]` section to accumulate changes across feature work before batching into a release.
- **Automated Release Notes Extraction**: Extract the release notes for the target release tag from `CHANGELOG.md` to populate the GitHub Release body, falling back to auto-generated GitHub notes if absent.
- **DMG & ZIP Packaging**: Automate the creation of a standalone macOS `.dmg` (with drag-and-drop `/Applications` symlink) and `.zip` archive from the compiled `GooCal.app` bundle.
- **Verification Checksums**: Generate SHA-256 checksum files for all distributed release artifacts.
- **Signing & Notarization Support**: Structure the build pipeline to support Apple Developer ID code signing and Apple Notarization (`notarytool`) when repository secrets are provided, with seamless fallback to ad-hoc signing (`-`) when credentials are not configured.
- **GitHub Release Publishing**: Automatically create GitHub Releases with attached DMGs, ZIPs, checksums, and changelog notes.
- **Release Documentation**: Add maintainer and user release documentation (`RELEASING.md`) explaining the release cadence, accumulating changes in `[Unreleased]`, tagging workflow, secret setup for signing/notarization, and guidance for end-users installing ad-hoc signed DMGs on macOS.

## Capabilities

### New Capabilities
- `release-management`: Automated building, packaging (.dmg and .zip), changelog tracking, checksum generation, optional code signing/notarization, and publishing to GitHub Releases.

### Modified Capabilities
*(None)*

## Impact

- **Repository Root**: Adds `CHANGELOG.md` seeded with initial version notes.
- **CI/CD**: Adds `.github/workflows/release.yml`. Normal `ci.yml` continues running tests on pushes to `main` without releasing.
- **Packaging Scripts**: Adds packaging helper script `scripts/package-dmg.sh`.
- **Documentation**: Adds `RELEASING.md` describing release cadence, changelog conventions, and installation notes.
- **Application Code**: No breaking changes to existing Swift source code or Xcode target configurations.
