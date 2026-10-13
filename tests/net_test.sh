#!/usr/bin/env bash
# Online co-op integration test: a real lobby server plus three headless game
# instances (host, guest, late joiner). Usage: tests/net_test.sh [path-to-godot]
set -u
cd "$(dirname "$0")/.."
GODOT="${1:-${GODOT:-godot}}"
PORT="${NET_TEST_PORT:-18471}"
LOGS="$(mktemp -d)"
LOBBY="NETTEST-$$"

PORT="$PORT" node server/server.js >"$LOGS/server.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; rm -rf "$LOGS"' EXIT
for _ in $(seq 50); do curl -sf "http://127.0.0.1:$PORT/healthz" >/dev/null && break; sleep 0.1; done

run() { "$GODOT" --headless --path . -- --net-test="$1" --server="ws://127.0.0.1:$PORT/ws" --lobby-name="$LOBBY" >"$LOGS/$1.log" 2>&1; }
run host & H=$!
sleep 1
run guest & G=$!
sleep 4
run late & L=$!
wait $H; HS=$?; wait $G; GS=$?; wait $L; LS=$?

grep -hE "NET_|CHECK|FINGERPRINT|SCRIPT ERROR|ERROR:" "$LOGS"/host.log "$LOGS"/guest.log "$LOGS"/late.log
status=0
for role in host guest late; do grep -q "NET_PASS $role" "$LOGS/$role.log" || { echo "FAILED: $role did not pass"; status=1; }; done
if grep -q "SCRIPT ERROR" "$LOGS"/*.log; then echo "FAILED: script errors"; status=1; fi
# Every instance must generate identical floors.
d1=$(grep -h "FINGERPRINT" "$LOGS"/*.log | grep "d=1 " | sed 's/FINGERPRINT [a-z]* //' | sort -u | wc -l)
d2=$(grep -h "FINGERPRINT" "$LOGS"/*.log | grep "d=2 " | sed 's/FINGERPRINT [a-z]* //' | sort -u | wc -l)
[ "$d1" = 1 ] && [ "$d2" = 1 ] || { echo "FAILED: floor fingerprints differ (d1=$d1 d2=$d2 variants)"; status=1; }
[ $HS = 0 ] && [ $GS = 0 ] && [ $LS = 0 ] || status=1
[ $status = 0 ] && echo "NET_TEST_PASS: lobby, sync, hits, drops, choices, revive, lift, late join, shared ending"
exit $status
