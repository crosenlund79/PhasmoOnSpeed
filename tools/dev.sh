#!/usr/bin/env bash
# Developer shortcuts. GODOT may point at any Godot 4.3 binary.
#   tools/dev.sh import | test [names...] | bot | capture OUT shots... | validate
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
case "$1" in
  import)   timeout 300 "$GODOT" --headless --path . --import >/dev/null 2>&1 || true ;;
  test)     shift; timeout 900 "$GODOT" --headless --fixed-fps 60 --path . res://tests/test_runner.tscn -- "$@" ;;
  bot)      shift; timeout 2400 "$GODOT" --headless --fixed-fps 60 --path . res://tests/bot_playtest.tscn -- "$@" ;;
  capture)  shift; out="$1"; shift; timeout 600 xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" --path . --rendering-driver opengl3 --resolution 1600x900 res://tools/capture/capture.tscn -- "$out" "$@" ;;
  validate) python3 tools/houses/build_houses.py --validate && python3 server/test_leaderboard_server.py ;;
  *) echo "usage: tools/dev.sh import|test|bot|capture|validate"; exit 2 ;;
esac
