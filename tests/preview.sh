#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
preview_dir=$(mktemp -d /tmp/calendar-preview.XXXXXX)
trap 'rm -rf -- "$preview_dir"' EXIT
ln -s /usr/share/omarchy/shell/Commons "$preview_dir/Commons"
ln -s /usr/share/omarchy/shell/Ui "$preview_dir/Ui"
ln -s "$repo" "$preview_dir/Plugin"
cp "$repo/tests/Preview.qml" "$preview_dir/shell.qml"
mkdir "$preview_dir/runtime" "$preview_dir/state"
chmod 700 "$preview_dir/runtime"
export PREVIEW_OUTPUT="${1:-/tmp/calendar-preview.png}"
export PREVIEW_SCREEN="${2:-calendar}"
export QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=basic QT_QUICK_BACKEND=software
export XDG_RUNTIME_DIR="$preview_dir/runtime" XDG_STATE_HOME="$preview_dir/state"
quickshell -p "$preview_dir" --no-color
