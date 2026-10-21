#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# SysTFTP - macOS .app Bundle and DMG Packaging Script
# Run this script on macOS with Xcode Command Line Tools installed.
# ==============================================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
APP_NAME="SysTFTP"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PROJECT_DIR}/SysTFTP/Resources/Info.plist")"
DMG_NAME="${APP_NAME}-macOS-${APP_VERSION}.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"
BACKGROUND="${PROJECT_DIR}/Assets/DMG/background.tiff"

if [ ! -f "${BACKGROUND}" ]; then
    echo "Error: Missing installer background: ${BACKGROUND}" >&2
    exit 1
fi

# 1. Build .app bundle
case "${1:-}" in
    "")
        bash "${PROJECT_DIR}/scripts/build_app.sh"
        ;;
    --skip-build)
        if [ ! -d "${APP_BUNDLE}" ]; then
            echo "Error: Build ${APP_BUNDLE} before using --skip-build." >&2
            exit 1
        fi
        codesign --verify --deep --strict "${APP_BUNDLE}"
        ;;
    *)
        echo "Usage: $0 [--skip-build]" >&2
        exit 1
        ;;
esac

# 2. Package in a unique directory so an existing installer stays available.
echo "==> Creating DMG installer..."
DMG_TEMP="$(mktemp -d "${BUILD_DIR}/dmg.XXXXXX")"
MOUNT_DIR="${DMG_TEMP}/mount"
DMG_MOUNTED=false
cleanup() {
    if [ "${DMG_MOUNTED}" = true ]; then
        if ! hdiutil detach "${MOUNT_DIR}"; then
            echo "Could not detach installer volume; preserving ${DMG_TEMP}" >&2
            return
        fi
    fi
    rm -rf "${DMG_TEMP}"
}
trap cleanup EXIT

finalize_dmg() {
    hdiutil verify "${DMG_TEMP}/${DMG_NAME}"
    mkdir -p "${MOUNT_DIR}"
    hdiutil attach "${DMG_TEMP}/${DMG_NAME}" -mountpoint "${MOUNT_DIR}" \
        -readonly -noautoopen -nobrowse
    DMG_MOUNTED=true
    codesign --verify --deep --strict "${MOUNT_DIR}/${APP_NAME}.app"
    [ -L "${MOUNT_DIR}/应用程序" ]
    [ "$(readlink "${MOUNT_DIR}/应用程序")" = /Applications ]
    hdiutil detach "${MOUNT_DIR}"
    DMG_MOUNTED=false
    mv -f "${DMG_TEMP}/${DMG_NAME}" "${DMG_PATH}"
    echo "==> Successfully created DMG installer at: ${DMG_PATH}!"
}

# CI writes Finder metadata directly because hosted runners have no GUI session.
if [ "${CI:-false}" = true ] || [ "${DMG_LAYOUT:-finder}" = headless ]; then
    if ! command -v dmgbuild >/dev/null 2>&1; then
        echo "Error: Install CI packaging dependencies with: python3 -m pip install -r scripts/dmg-requirements.txt" >&2
        exit 1
    fi
    dmgbuild -s "${PROJECT_DIR}/scripts/dmg_settings.py" \
        -D "project_dir=${PROJECT_DIR}" \
        "${APP_NAME}" "${DMG_TEMP}/${DMG_NAME}"
    finalize_dmg
    exit 0
fi

mkdir -p "${DMG_TEMP}/contents"

ditto "${APP_BUNDLE}" "${DMG_TEMP}/contents/${APP_NAME}.app"
ln -s /Applications "${DMG_TEMP}/contents/应用程序"
mkdir -p "${DMG_TEMP}/contents/.background"
cp "${BACKGROUND}" "${DMG_TEMP}/contents/.background/background.tiff"

hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_TEMP}/contents" \
    -fs HFS+ -format UDRW "${DMG_TEMP}/writable.dmg"
mkdir -p "${MOUNT_DIR}"
hdiutil attach "${DMG_TEMP}/writable.dmg" -mountpoint "${MOUNT_DIR}" \
    -readwrite -noverify -noautoopen -nobrowse
DMG_MOUNTED=true
osascript "${PROJECT_DIR}/scripts/layout_dmg.applescript" "${MOUNT_DIR}"

# Closing the Finder window flushes its layout; never wait indefinitely.
for attempt in {1..10}; do
    [ -f "${MOUNT_DIR}/.DS_Store" ] && break
    sleep 1
done
if [ ! -f "${MOUNT_DIR}/.DS_Store" ]; then
    echo "Error: Finder did not save the installer window layout." >&2
    exit 1
fi

cp "${PROJECT_DIR}/Assets/SysTFTP.icns" "${MOUNT_DIR}/.VolumeIcon.icns"
SetFile -c icnC "${MOUNT_DIR}/.VolumeIcon.icns"
SetFile -a C "${MOUNT_DIR}"

hdiutil detach "${MOUNT_DIR}"
DMG_MOUNTED=false
hdiutil convert "${DMG_TEMP}/writable.dmg" -format UDZO \
    -o "${DMG_TEMP}/${DMG_NAME}"

finalize_dmg
