#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
INJECT_DIR="$PROJECT_DIR/inject"
IPA_EXTRACTED="$INJECT_DIR/SubwayCity.app.tmp"
APP_DIR="$IPA_EXTRACTED/Payload/SubwayCity.app"
DYLIB_NAME="CoinHack.dylib"
OUTPUT_IPA="$PROJECT_DIR/SubwayCity-CoinHack.ipa"

echo "=== Step 1: Compile CoinHack.dylib ==="
xcrun -sdk iphoneos clang \
    -arch arm64 \
    -shared \
    -framework Foundation -framework UIKit -framework CoreGraphics \
    -miphoneos-version-min=15.0 \
    -Wno-deprecated-declarations \
    -o "$INJECT_DIR/$DYLIB_NAME" \
    "$PROJECT_DIR/CoinHack.m" \
    "$PROJECT_DIR/libs/libdobby.a" \
    -I "$PROJECT_DIR/libs" \
    -lstdc++

echo "  -> $DYLIB_NAME built"

echo ""
echo "=== Step 2: Copy dylib into app bundle ==="
mkdir -p "$APP_DIR/Frameworks"
cp "$INJECT_DIR/$DYLIB_NAME" "$APP_DIR/Frameworks/"
echo "  -> Copied to Frameworks/"

echo ""
echo "=== Step 3: Inject load command ==="
# insert_dylib adds LC_LOAD_DYLIB to the main executable
"$HOME/bin/insert_dylib" \
    --strip-codesig \
    --inplace \
    "@executable_path/Frameworks/$DYLIB_NAME" \
    "$APP_DIR/SubwayCity"
echo "  -> Load command injected into SubwayCity binary"

echo ""
echo "=== Step 4: Remove old signature ==="
# Remove _CodeSignature so we can re-sign
find "$APP_DIR" -name "_CodeSignature" -type d -exec rm -rf {} + 2>/dev/null || true
# Remove embedded provisioning profiles
rm -f "$APP_DIR/embedded.mobileprovision" 2>/dev/null || true
echo "  -> Old signatures removed"

echo ""
echo "=== Step 5: Package IPA ==="
cd "$IPA_EXTRACTED"
zip -r -9 "$OUTPUT_IPA" Payload/ -x "*.DS_Store"
echo "  -> $OUTPUT_IPA"

echo ""
echo "=== DONE ==="
echo "IPA: $OUTPUT_IPA"
echo ""
echo "Sign & install:"
echo "  - TrollStore: Copy IPA to device, open with TrollStore"
echo "  - AltStore:   altool install $OUTPUT_IPA"
echo "  - Sideloadly: Drag IPA into Sideloadly"
echo "  - zsign:      zsign -k cert.p12 -p pass -m prov.mobileprovision -o signed.ipa $OUTPUT_IPA"
