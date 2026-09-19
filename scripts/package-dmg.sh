#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# GooCal Packaging Script (.dmg and .zip)
# Usage:
#   ./scripts/package-dmg.sh [APP_PATH] [OUTPUT_DIR] [VERSION]
# ==============================================================================

APP_PATH="${1:-}"
OUTPUT_DIR="${2:-dist}"
VERSION="${3:-}"

# Locate app bundle if not provided
if [[ -z "$APP_PATH" ]]; then
    for candidate in \
        "build/Release/GooCal.app" \
        "build/Build/Products/Release/GooCal.app" \
        "build/Products/Release/GooCal.app" \
        "GooCal.app"; do
        if [[ -d "$candidate" ]]; then
            APP_PATH="$candidate"
            break
        fi
    done
fi

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
    echo "Error: GooCal.app not found at '${APP_PATH:-<empty>}'." >&2
    echo "Usage: $0 [APP_PATH] [OUTPUT_DIR] [VERSION]" >&2
    exit 1
fi

# Detect version from Info.plist if not explicitly passed
if [[ -z "$VERSION" ]]; then
    INFO_PLIST="${APP_PATH}/Contents/Info.plist"
    if [[ -f "$INFO_PLIST" ]]; then
        VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || true)"
    fi
    if [[ -z "$VERSION" ]]; then
        VERSION="1.0.0"
    fi
fi

# Strip leading 'v' if present (e.g. v1.0.0 -> 1.0.0)
VERSION="${VERSION#v}"

echo "==> Packaging GooCal v${VERSION}"
echo "    Source: ${APP_PATH}"
echo "    Output: ${OUTPUT_DIR}"

mkdir -p "$OUTPUT_DIR"

DMG_NAME="GooCal-${VERSION}.dmg"
ZIP_NAME="GooCal-${VERSION}.zip"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"
ZIP_PATH="${OUTPUT_DIR}/${ZIP_NAME}"

# Clean up existing artifacts with the same name
rm -f "$DMG_PATH" "$ZIP_PATH" "${DMG_PATH}.sha256" "${ZIP_PATH}.sha256"

# ------------------------------------------------------------------------------
# 1. Create ZIP Archive
# ------------------------------------------------------------------------------
echo "==> Creating ${ZIP_NAME}..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
echo "    Created: ${ZIP_PATH}"

# ------------------------------------------------------------------------------
# 2. Create DMG Disk Image
# ------------------------------------------------------------------------------
echo "==> Creating ${DMG_NAME}..."

USE_FALLBACK=0

if command -v create-dmg >/dev/null 2>&1; then
    echo "    Using create-dmg utility..."
    set +e
    create-dmg \
        --volname "GooCal" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "GooCal.app" 175 190 \
        --hide-extension "GooCal.app" \
        --app-drop-link 425 190 \
        --no-mac-dmg \
        "$DMG_PATH" \
        "$APP_PATH"
    EXIT_CODE=$?
    set -e

    if [[ $EXIT_CODE -ne 0 || ! -f "$DMG_PATH" ]]; then
        echo "    Warning: create-dmg exited with ${EXIT_CODE}. Falling back to native hdiutil..."
        rm -f "$DMG_PATH"
        USE_FALLBACK=1
    fi
else
    USE_FALLBACK=1
fi

if [[ $USE_FALLBACK -eq 1 ]]; then
    echo "    Using native hdiutil to build disk image..."
    STAGING_DIR="$(mktemp -d -t goocal_dmg_staging.XXXXXX)"
    trap 'rm -rf "$STAGING_DIR"' EXIT

    # Copy app bundle into staging directory
    cp -R "$APP_PATH" "$STAGING_DIR/GooCal.app"

    # Add Applications symlink for drag-and-drop installer
    ln -s /Applications "$STAGING_DIR/Applications"

    # Create compressed UDZO disk image
    hdiutil create \
        -volname "GooCal" \
        -srcfolder "$STAGING_DIR" \
        -ov \
        -format UDZO \
        "$DMG_PATH"

    rm -rf "$STAGING_DIR"
    trap - EXIT
fi

echo "    Created: ${DMG_PATH}"

# ------------------------------------------------------------------------------
# 3. Generate SHA-256 Checksums
# ------------------------------------------------------------------------------
echo "==> Generating SHA-256 checksums..."
(
    cd "$OUTPUT_DIR"
    shasum -a 256 "$DMG_NAME" > "${DMG_NAME}.sha256"
    shasum -a 256 "$ZIP_NAME" > "${ZIP_NAME}.sha256"
)

echo "==> Packaging complete!"
echo "    Artifacts generated in: ${OUTPUT_DIR}"
ls -la "$OUTPUT_DIR"
