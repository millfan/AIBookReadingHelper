#!/bin/bash
# Builds a Release copy of the app and packages it as dist/AIBookReadingHelper.dmg.
# The app is signed with the project's Apple Development certificate, so the DMG
# installs on Macs signed in with that Apple ID. Sharing it with other people
# needs a Developer ID certificate and notarization.
set -euo pipefail

cd "$(dirname "$0")/.."
APP=AIBookReadingHelper
BUILD_DIR=build/release
DMG=dist/$APP.dmg

xcodebuild -project "$APP.xcodeproj" -scheme "$APP" -configuration Release \
    -derivedDataPath "$BUILD_DIR" -allowProvisioningUpdates build

# The DMG shows the app next to a shortcut to Applications, so it can be dragged across to install.
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
cp -R "$BUILD_DIR/Build/Products/Release/$APP.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

mkdir -p dist
hdiutil create -volname "AI Book Reading Helper" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
echo "Created $DMG"
