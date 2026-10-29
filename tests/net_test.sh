#!/usr/bin/env bash
# Multiplayer integration test: one host + N client processes on localhost.
#   GODOT=/path/to/godot tests/net_test.sh [clients=3] [scenario=full|drop]
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
N="${1:-3}"
SC="${2:-full}"
PORT=$((24690 + RANDOM % 200))
LOG="${NET_TEST_LOG:-/tmp/spectral_net_test}"
mkdir -p "$LOG"
"$GODOT" --headless --path . res://tests/net_test.tscn -- host "$N" "$PORT" "$SC" > "$LOG/host.log" 2>&1 &
pids=($!)
for i in $(seq 1 "$N"); do
  "$GODOT" --headless --path . res://tests/net_test.tscn -- client "$i" "$PORT" "$SC" > "$LOG/client$i.log" 2>&1 &
  pids+=($!)
done
fail=0
for p in "${pids[@]}"; do wait "$p" || fail=1; done
grep -h "RESULT\|CHECK FAILED\|TIMEOUT\|SCRIPT ERROR" "$LOG"/*.log
exit $fail
