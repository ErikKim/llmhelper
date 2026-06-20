#!/usr/bin/env bash
# Build LLMHelper.app : compile Swift, assemble .app bundle, ad-hoc sign, register Services.
set -euo pipefail

cd "$(dirname "$0")"
APP="build/LLMHelper.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

echo "==> cleaning"
rm -rf build
mkdir -p "$MACOS" "$RES"

echo "==> compiling (arm64 + x86_64 universal)"
swiftc -O \
  -target arm64-apple-macos12.0 \
  Sources/main.swift -o build/llmhelper-arm64
# x86_64 slice (optional; comment out if it fails on your toolchain)
if swiftc -O -target x86_64-apple-macos12.0 Sources/main.swift -o build/llmhelper-x86_64 2>/dev/null; then
  lipo -create build/llmhelper-arm64 build/llmhelper-x86_64 -output "$MACOS/LLMHelper"
  rm -f build/llmhelper-arm64 build/llmhelper-x86_64
else
  echo "    (x86_64 slice skipped — arm64 only)"
  mv build/llmhelper-arm64 "$MACOS/LLMHelper"
fi
chmod +x "$MACOS/LLMHelper"

echo "==> bundling Info.plist"
cp Info.plist "$APP/Contents/Info.plist"
echo "APPL????" > "$APP/Contents/PkgInfo"

echo "==> code signing"
# Prefer a stable code-signing identity (so TCC/Accessibility permission survives rebuilds).
# Falls back to ad-hoc (-) if none is available.
SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null | awk '/[0-9A-F]{40}/{print $2; exit}')"
if [ -n "${SIGN_ID:-}" ]; then
  echo "    using identity: $SIGN_ID"
  codesign --force --deep --sign "$SIGN_ID" "$APP"
else
  echo "    no identity found — ad-hoc signing (permission will reset each build)"
  codesign --force --deep --sign - "$APP"
fi

echo "==> registering Services with Launch Services"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$(pwd)/$APP" || true
/System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true

echo ""
echo "✅ Built: $(pwd)/$APP"
echo ""
echo "Next:"
echo "  1) (recommended) move it to Applications:"
echo "       cp -R \"$(pwd)/$APP\" /Applications/ && \"$LSREGISTER\" -f /Applications/LLMHelper.app"
echo "  2) launch once so the Service registers + the agent stays resident:"
echo "       open \"$(pwd)/$APP\"   (first time: right-click → Open, since it's unsigned)"
echo "  3) select text anywhere → right-click → Services ▸ LLMHelper: 쉽게 설명"
echo "     (if it doesn't appear: System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Services ▸ Text — enable them)"
