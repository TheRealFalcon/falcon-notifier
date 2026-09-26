#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
swift build -c release --disable-sandbox
app="$PWD/dist/Notifier.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/Notifier "$app/Contents/MacOS/Notifier"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
printf '\nBuilt %s\n' "$app"
