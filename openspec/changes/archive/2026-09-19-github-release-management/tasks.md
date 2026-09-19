# Tasks

## 1. DMG Packaging Script

- [x] 1.1 Create `scripts/package-dmg.sh` to package `GooCal.app` into `.dmg` and `.zip` with checksum generation (`.sha256`), using `create-dmg` if installed and falling back to native `hdiutil`, and verify shell syntax with `bash -n scripts/package-dmg.sh`.
- [x] 1.2 Set executable permissions on `scripts/package-dmg.sh` and verify with `ls -la scripts/package-dmg.sh`.

## 2. Repository Changelog

- [x] 2.1 Create `CHANGELOG.md` following the Keep a Changelog format with an `[Unreleased]` section and initial `1.0.0` release notes, and verify file formatting.

## 3. GitHub Actions Release Workflow

- [x] 3.1 Create `.github/workflows/release.yml` triggered only on tags matching `v*` and `workflow_dispatch`, containing steps for checkout, release build with `xcodebuild`, optional signing and notarization with ad-hoc fallback, artifact packaging via `scripts/package-dmg.sh`, changelog note extraction from `CHANGELOG.md`, and release publishing via `softprops/action-gh-release@v2`, and verify YAML formatting.

## 4. Release Documentation

- [x] 4.1 Create `RELEASING.md` documenting the batched release workflow (accumulating features in `[Unreleased]` before releasing), version bumping, tagging instructions, Apple Developer secrets configuration, and end-user guidance for opening ad-hoc signed DMGs on macOS, and verify file readability.

## 5. Verification

- [x] 5.1 Run OpenSpec change validation (`openspec validate github-release-management`) and verify that all artifacts conform to specifications.
