#!/bin/bash
# Runs one test suite headless and prints its output (also kept in a log).
# Usage: tests/run_one.sh <suite> [TAG]      e.g. tests/run_one.sh trading
#   GODOT          the Godot 4.7 binary (default: godot on PATH)
#   AI_GAME_TESTS  where logs and the isolated user:// data go (default: /tmp/ai-game-tests)
#   TAG            names the logs and the user:// dir, so two runs don't share a savegame (default: main)
# Suites listed in tests/gui_suites.txt need a display: they run under xvfb with the opengl3 driver.
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$HERE")
SUITE=$1
TAG=${2:-main}
G=${GODOT:-godot}
OUT=${AI_GAME_TESTS:-/tmp/ai-game-tests}
mkdir -p "$OUT/logs" "$OUT/xdg_$TAG"
export XDG_DATA_HOME=$OUT/xdg_$TAG
LOG=$OUT/logs/run_${TAG}_$SUITE.log
cd "$REPO" || exit 2
if grep -qx "$SUITE" "$HERE/gui_suites.txt" 2>/dev/null; then
  timeout 900 xvfb-run -a -s "-screen 0 1920x1080x24" "$G" --fixed-fps 60 --rendering-driver opengl3 --path . -s "tests/${SUITE}_test.gd" > "$LOG" 2>&1
else
  timeout 900 stdbuf -o0 "$G" --headless --fixed-fps 60 --path . -s "tests/${SUITE}_test.gd" > "$LOG" 2>&1
fi
CODE=$?
cat "$LOG"
exit $CODE
