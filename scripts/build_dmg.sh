#!/usr/bin/env bash
set -e

# ==============================================================================
# SysTFTP - macOS .app Bundle and DMG Packaging Script
# Run this script on macOS with Xcode Command Line Tools installed.
# ==============================================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
APP_NAME="SysTFTP"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-macOS-1.0.0.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"

echo "==> Building SysTFTP (Release)..."
cd "${PROJECT_DIR}"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"
echo "==> Binary compiled at: ${BIN_PATH}"

echo "==> Creating macOS App Bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

cp "${PROJECT_DIR}/SysTFTP/Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

if [ -f "${PROJECT_DIR}/Assets/SysTFTP.icns" ]; then
    cp "${PROJECT_DIR}/Assets/SysTFTP.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
elif [ -f "${PROJECT_DIR}/SysTFTP/Resources/AppIcon.icns" ]; then
    cp "${PROJECT_DIR}/SysTFTP/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

echo "==> Code signing application (Ad-hoc)..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> Creating DMG installer..."
DMG_TEMP="${BUILD_DIR}/dmg_temp"
rm -rf "${DMG_TEMP}" "${DMG_PATH}"
mkdir -p "${DMG_TEMP}"

cp -R "${APP_BUNDLE}" "${DMG_TEMP}/"
ln -s /Applications "${DMG_TEMP}/Applications"

hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_TEMP}" -ov -format UDZO "${DMG_PATH}"

rm -rf "${DMG_TEMP}"
echo "==> Successfully created ${DMG_PATH}!"
