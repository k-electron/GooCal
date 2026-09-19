# Release Guide

This document outlines the release process, versioning conventions, changelog maintenance, and code signing configuration for **GooCal**.

---

## 1. Release Philosophy & Cadence

* **Decoupled Releases:** Features, fixes, and improvements are merged into `main` continuously. Releases are cut intentionally and less frequently, bundling multiple accumulated changes into a single milestone.
* **Continuous Integration vs. Release Pipeline:**
  * Everyday pushes and pull requests to `main` trigger `.github/workflows/ci.yml` (build and test verification). They **never** trigger a release.
  * The release workflow (`.github/workflows/release.yml`) executes **only** when a version tag (e.g. `v1.0.0`) is pushed, or when triggered manually via `workflow_dispatch`.
* **Changelog Staging:** As features and bug fixes land in `main`, document them under the `## [Unreleased]` section of [`CHANGELOG.md`](CHANGELOG.md).

---

## 2. Step-by-Step: Cutting a Release

### Step 1: Finalize `CHANGELOG.md`
1. Open [`CHANGELOG.md`](CHANGELOG.md).
2. Move items from `## [Unreleased]` into a new version heading:
   ```markdown
   ## [Unreleased]

   ## [1.1.0] - YYYY-MM-DD
   ### Added
   - Feature A
   - Feature B
   ```
3. Commit the updated changelog:
   ```bash
   git add CHANGELOG.md
   git commit -m "chore(release): prepare changelog for v1.1.0"
   ```

### Step 2: Bump `MARKETING_VERSION` (Optional / Recommended)
Ensure `MARKETING_VERSION` in `GooCal.xcodeproj` matches the upcoming version (e.g., `1.1.0`). Commit and push to `main`:
```bash
git push origin main
```

### Step 3: Create and Push the Tag
Create a semantic version tag prefixed with `v` and push it to GitHub:
```bash
git tag v1.1.0
git push origin v1.1.0
```

*(Alternatively, you can go to GitHub Actions -> **Release** workflow -> click **Run workflow**, enter `v1.1.0`, and trigger manually).*

### Step 4: Automated CI Execution
GitHub Actions will automatically:
1. Build `GooCal.app` in `Release` configuration.
2. Package `GooCal-1.1.0.dmg` and `GooCal-1.1.0.zip` with drag-and-drop installer layout.
3. Compute SHA-256 checksums (`.dmg.sha256`, `.zip.sha256`).
4. Extract release notes for `[1.1.0]` from `CHANGELOG.md`.
5. Publish a new GitHub Release with all artifacts attached.

---

## 3. Release Artifacts

Every published release includes:
- **`GooCal-<version>.dmg`**: macOS Disk image containing `GooCal.app` and an `/Applications` shortcut.
- **`GooCal-<version>.zip`**: Standalone zipped app bundle for scriptable installation and Homebrew Casks.
- **`*.sha256`**: Verification checksums.

---

## 4. Code Signing & Notarization (Optional)

The release workflow is designed to work immediately out of the box without requiring a paid Apple Developer subscription, while supporting full Developer ID signing and Apple Notarization when credentials are provided.

### Ad-Hoc Signing (Default)
If no Apple Developer credentials are configured in GitHub repository secrets, the workflow builds using ad-hoc code signing (`CODE_SIGN_IDENTITY="-"`). The build and release will succeed without errors.

### Apple Developer ID Signing & Notarization (Production)
To produce Gatekeeper-friendly releases that run without macOS security warnings, add the following GitHub Secrets to your repository (`Settings -> Secrets and variables -> Actions`):

| Secret Name | Description |
|---|---|
| `APPLE_CERTIFICATE_BASE64` | Base64-encoded `.p12` export of your Developer ID Application certificate. |
| `APPLE_CERTIFICATE_PASSWORD` | Password protecting the `.p12` certificate file. |
| `APPLE_TEAM_ID` | 10-character Apple Developer Team ID (e.g. `ABC1234567`). |
| `APPLE_ID` | Apple ID email associated with the developer account. |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password generated at appleid.apple.com for `notarytool`. |
| `APPLE_CODE_SIGN_IDENTITY` | *(Optional)* Signing identity name (defaults to `Developer ID Application`). |

When these secrets are present, the workflow imports the certificate, signs `GooCal.app`, submits the DMG to Apple Notary Service via `xcrun notarytool`, and staples the notarization ticket to the disk image.

---

## 5. End-User Guide: Opening Ad-Hoc Signed Builds on macOS

For releases built with ad-hoc signatures (unnotarized):
1. Download and open `GooCal-<version>.dmg`.
2. Drag `GooCal.app` into `Applications`.
3. If macOS displays *"GooCal can't be opened because Apple cannot check it for malicious software"*:
   - In Finder, open the `/Applications` folder.
   - **Right-click (or Control-click)** `GooCal.app` and select **Open**.
   - In the dialog box, click **Open**. macOS will remember this approval.
4. Alternatively, remove the quarantine attribute via Terminal:
   ```bash
   xattr -cr /Applications/GooCal.app
   ```

---

## 6. Testing Packaging Locally

Maintainers can test the DMG creation script on any Mac:

```bash
# Build release app locally (requires Xcode)
xcodebuild -scheme GooCal -configuration Release -derivedDataPath build build

# Run packaging script (creates dist/GooCal-1.0.0.dmg and dist/GooCal-1.0.0.zip)
./scripts/package-dmg.sh build/Build/Products/Release/GooCal.app dist 1.0.0
```
