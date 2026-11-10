#!/bin/bash
# Runs the compile check, then every suite in tests/suites.txt and tests/gui_suites.txt, one log each,
# and prints one summary line per suite: "<suite>: exit <code> <n> fails". Exits 1 if anything failed.
# Usage: tests/run_all.sh [TAG]      (GODOT, AI_GAME_TESTS and TAG as in run_one.sh)
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$HERE")
TAG=${1:-main}
G=${GODOT:-godot}
OUT=${AI_GAME_TESTS:-/tmp/ai-game-tests}
mkdir -p "$OUT/logs" "$OUT/xdg_$TAG"
export XDG_DATA_HOME=$OUT/xdg_$TAG
cd "$REPO" || exit 2
BAD=0
timeout 300 "$G" --headless --path . -s tests/compile_check.gd > "$OUT/logs/run_${TAG}_compile.log" 2>&1
CODE=$?
echo "compile: exit $CODE $(grep -c '^BROKEN' "$OUT/logs/run_${TAG}_compile.log") broken"
[ $CODE -ne 0 ] && BAD=1
for suite in $(cat "$HERE/suites.txt" "$HERE/gui_suites.txt" 2>/dev/null | grep -v '^#' | grep -v '^$'); do
  "$HERE/run_one.sh" "$suite" "$TAG" > /dev/null 2>&1
  CODE=$?
  LOG=$OUT/logs/run_${TAG}_$suite.log
  FAILS=$(grep -c '^  FAIL' "$LOG")
  ERRORS=$(grep -c 'SCRIPT ERROR' "$LOG")
  echo "$suite: exit $CODE $FAILS fails $ERRORS script errors"
  if [ $CODE -ne 0 ] || [ "$FAILS" != "0" ] || [ "$ERRORS" != "0" ]; then BAD=1; fi
done
exit $BAD
