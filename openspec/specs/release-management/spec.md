# release-management Specification

## Purpose

Automates the build, packaging, verification, and distribution of GooCal releases on GitHub as macOS DMG disk images and ZIP archives, driven by curated changelog notes and decoupled from daily feature development.

## Requirements

### Requirement: Release workflow triggers on version tag or manual dispatch
The release pipeline SHALL automatically execute only when a Git tag matching `v*` is pushed to the repository, or when maintainers trigger an execution manually via workflow_dispatch, ensuring releases remain decoupled from regular branch pushes.

#### Scenario: Version tag push triggers release build
- **WHEN** a maintainer pushes a git tag matching the pattern `v*` (e.g., `v1.0.0`)
- **THEN** the GitHub Actions release workflow starts and builds the specified tag commit

#### Scenario: Regular push to main does not trigger release
- **WHEN** code is pushed or merged to `main` without a release tag
- **THEN** standard CI runs tests but the release workflow does not execute

#### Scenario: Manual workflow dispatch triggers release build
- **WHEN** a maintainer triggers the release workflow manually via GitHub Actions workflow_dispatch
- **THEN** the release workflow runs using the selected branch and inputs

### Requirement: Repository maintains a structured changelog
The repository SHALL maintain a `CHANGELOG.md` file following the Keep a Changelog standard, providing an `[Unreleased]` section to collect changes across feature development cycles before cutting a release.

#### Scenario: Changelog tracks changes with Unreleased and version sections
- **WHEN** the repository changelog is viewed
- **THEN** it contains an `[Unreleased]` section followed by version headings documenting added, changed, and fixed features

### Requirement: Release workflow extracts release notes from changelog
The release pipeline SHALL parse release notes corresponding to the released version tag from `CHANGELOG.md` and use them as the GitHub Release description, falling back to auto-generated release notes if the version section is missing.

#### Scenario: Version entry present in changelog
- **WHEN** a release workflow runs for a tag and `CHANGELOG.md` contains a matching version heading
- **THEN** the workflow extracts the section content and publishes it as the release body

#### Scenario: Version entry absent in changelog
- **WHEN** a release workflow runs for a tag not found in `CHANGELOG.md`
- **THEN** the workflow falls back to GitHub auto-generated release notes without failing the release

### Requirement: Release workflow packages compiled application as a DMG disk image
The release pipeline SHALL compile the application in Release configuration and package it into a compressed macOS DMG disk image (`.dmg`) containing the `GooCal.app` bundle and a symlink to `/Applications`.

#### Scenario: DMG creation includes application and Applications folder link
- **WHEN** the release build completes successfully
- **THEN** a `.dmg` file named `GooCal-<version>.dmg` is generated containing `GooCal.app` and an `/Applications` shortcut

### Requirement: Release workflow packages compiled application as a ZIP archive
The release pipeline SHALL compress the compiled `GooCal.app` bundle into a `.zip` archive for distribution.

#### Scenario: ZIP archive contains application bundle
- **WHEN** the release build completes successfully
- **THEN** a `.zip` file named `GooCal-<version>.zip` is generated containing `GooCal.app` preserving file permissions and symbolic links

### Requirement: Release workflow generates SHA-256 checksums for distribution artifacts
The release pipeline SHALL generate SHA-256 checksum files for all packaged distribution artifacts (`.dmg` and `.zip`).

#### Scenario: Checksums generated for release artifacts
- **WHEN** packaging of `.dmg` and `.zip` artifacts finishes
- **THEN** `.sha256` files corresponding to each artifact are created containing the hex digest and file name

### Requirement: Release workflow supports Apple Developer ID signing and notarization with ad-hoc fallback
The release pipeline SHALL sign the application and disk image with an Apple Developer ID Application certificate and submit for Apple notarization when repository secrets are provided; if secrets are not configured, it SHALL fall back to ad-hoc code signing (`-`) without failing the build.

#### Scenario: Signing credentials provided
- **WHEN** Apple Developer certificate and notarization credentials are present in repository secrets
- **THEN** the workflow signs the application bundle and DMG with the Developer ID and notarizes via Apple `notarytool`

#### Scenario: Signing credentials absent
- **WHEN** Apple Developer certificate secrets are not configured
- **THEN** the workflow applies ad-hoc code signing (`-`) and proceeds with packaging and publishing without error

### Requirement: Release workflow publishes release to GitHub Releases with attached artifacts
The release pipeline SHALL create or update a GitHub Release for the tag, attaching the generated DMG, ZIP, and checksum files, along with release notes.

#### Scenario: Release published with assets and release notes
- **WHEN** the packaging and checksum steps complete successfully
- **THEN** a GitHub Release is published containing `GooCal-<version>.dmg`, `GooCal-<version>.zip`, their `.sha256` files, and the release notes
