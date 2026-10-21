#!/usr/bin/env bash
set -e

# ==============================================================================
# SysTFTP - macOS .app Bundle Packaging Script
# Compiles a Universal Binary (arm64 + x86_64) and packages SysTFTP.app
# ==============================================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
APP_NAME="SysTFTP"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
TEMP_DIR="${BUILD_DIR}/obj"

echo "==> Preparing build directories..."
mkdir -p "${TEMP_DIR}"
rm -rf "${APP_BUNDLE}"

# 1. Determine compatible macOS SDK
SDK_PATH=""
CANDIDATE_SDKS=(
    "$(xcrun --show-sdk-path 2>/dev/null || true)"
    "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
    "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
    "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
    "/Library/Developer/CommandLineTools/SDKs/MacOSX14.sdk"
)

for sdk in "${CANDIDATE_SDKS[@]}"; do
    if [ -n "$sdk" ] && [ -d "$sdk" ]; then
        # Check if SDK Swift compiler version matches or works
        if swiftc -sdk "$sdk" -target arm64-apple-macosx13.0 -parse-as-library "${PROJECT_DIR}/SysTFTP/Models/FTPUser.swift" -typecheck &>/dev/null; then
            SDK_PATH="$sdk"
            break
        fi
    fi
done

if [ -z "$SDK_PATH" ]; then
    echo "Warning: Could not find explicitly verified SDK, falling back to default SDK"
    SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || echo '')"
fi

echo "==> Using SDK: ${SDK_PATH:-Default}"

# 2. Gather Swift source files
SWIFT_SOURCES=()
while IFS= read -r -d '' file; do
    SWIFT_SOURCES+=("$file")
done < <(find "${PROJECT_DIR}/SysTFTP" -name "*.swift" -print0)

echo "==> Compiling ${#SWIFT_SOURCES[@]} Swift source files..."

SWIFT_FLAGS=(-O -parse-as-library)
if [ -n "$SDK_PATH" ]; then
    SWIFT_FLAGS+=(-sdk "$SDK_PATH")
fi

# Compile arm64
echo "    -> Compiling for arm64 (Apple Silicon)..."
swiftc "${SWIFT_FLAGS[@]}" -target arm64-apple-macosx13.0 "${SWIFT_SOURCES[@]}" -o "${TEMP_DIR}/${APP_NAME}_arm64"

# Compile x86_64 (Intel)
HAS_X86_64=false
echo "    -> Compiling for x86_64 (Intel)..."
if swiftc "${SWIFT_FLAGS[@]}" -target x86_64-apple-macosx13.0 "${SWIFT_SOURCES[@]}" -o "${TEMP_DIR}/${APP_NAME}_x86_64" 2>/dev/null; then
    HAS_X86_64=true
fi

# 3. Create Universal Binary (or copy arm64)
FINAL_BIN="${TEMP_DIR}/${APP_NAME}"
if [ "$HAS_X86_64" = true ]; then
    echo "==> Creating Universal 2 Binary (arm64 + x86_64)..."
    lipo -create "${TEMP_DIR}/${APP_NAME}_arm64" "${TEMP_DIR}/${APP_NAME}_x86_64" -output "${FINAL_BIN}"
else
    echo "==> Using arm64 binary..."
    cp "${TEMP_DIR}/${APP_NAME}_arm64" "${FINAL_BIN}"
fi

# 4. Construct .app bundle structure
echo "==> Creating .app bundle structure at ${APP_BUNDLE}..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${FINAL_BIN}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

cp "${PROJECT_DIR}/SysTFTP/Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "${PROJECT_DIR}/SysTFTP/Resources/port_forwarding.sh" "${APP_BUNDLE}/Contents/Resources/port_forwarding.sh"

if [ -f "${PROJECT_DIR}/Assets/SysTFTP.icns" ]; then
    cp "${PROJECT_DIR}/Assets/SysTFTP.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
elif [ -f "${PROJECT_DIR}/SysTFTP/Resources/AppIcon.icns" ]; then
    cp "${PROJECT_DIR}/SysTFTP/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# 5. Code signing
echo "==> Signing application bundle (Ad-hoc)..."
ENTITLEMENTS="${PROJECT_DIR}/SysTFTP/Resources/SysTFTP.entitlements"
if [ -f "${ENTITLEMENTS}" ]; then
    codesign --force --deep --sign - --entitlements "${ENTITLEMENTS}" "${APP_BUNDLE}"
else
    codesign --force --deep --sign - "${APP_BUNDLE}"
fi

# Verify signature
codesign --verify --deep --strict "${APP_BUNDLE}"

# Clean temporary objects
rm -rf "${TEMP_DIR}"

echo "============================================================"
echo "==> Successfully packaged: ${APP_BUNDLE}"
echo "============================================================"
