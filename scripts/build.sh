#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
swift build -c release --disable-sandbox
app="$PWD/dist/falcon-notifier.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/falcon-notifier "$app/Contents/MacOS/falcon-notifier"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
printf '\nBuilt %s\n' "$app"
