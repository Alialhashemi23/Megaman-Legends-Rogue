#!/usr/bin/env bash
# Export the browser build and package it as build/RelicDiver-Web.zip, the
# bundle the online server (server/, Dockerfile) serves. Requires Godot 4.7.1
# with its Web export templates installed.   tools/package-web.sh [godot]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${1:-${GODOT:-godot}}"
rm -rf build/web && mkdir -p build/web
"$GODOT" --headless --path . --export-release Web build/web/index.html
# Ship notices beside the game so credits are reachable from the site.
cp build/LICENSE.md build/GODOT-LICENSE.txt build/CHARACTER-CREDITS.md build/AUDIO-NOTES.md build/web/
cp -r build/font-licenses build/audio-licenses build/web/
rm -f build/RelicDiver-Web.zip.partial
(cd build/web && zip -q -9 -r ../RelicDiver-Web.zip.partial .)
size=$(stat -c %s build/RelicDiver-Web.zip.partial)
[ "$size" -lt 100000000 ] || { echo "Web ZIP exceeds GitHub's file limit"; exit 1; }
mv build/RelicDiver-Web.zip.partial build/RelicDiver-Web.zip
ls -l build/RelicDiver-Web.zip
