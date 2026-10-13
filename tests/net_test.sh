#!/usr/bin/env bash
# Online co-op integration test: a real lobby server plus headless game
# instances that play together and then survive a guest refresh, a host crash,
# everyone leaving, and a server restart (see tests/net_driver.gd).
# Usage: tests/net_test.sh [path-to-godot]
set -u
cd "$(dirname "$0")/.."
GODOT="${1:-${GODOT:-godot}}"
PORT="${NET_TEST_PORT:-18471}"
LOGS="$(mktemp -d)"
LOBBY="NETTEST-$$"
SAVES="save/net-test-$$"
mkdir -p "$SAVES"

start_server() {
  PORT="$PORT" node server/server.js >>"$LOGS/server.log" 2>&1 &
  SERVER=$!
  for _ in $(seq 50); do curl -sf "http://127.0.0.1:$PORT/healthz" >/dev/null && break; sleep 0.1; done
}
cleanup() { kill $SERVER 2>/dev/null; rm -rf "$LOGS" "$SAVES"; }
trap cleanup EXIT
start_server

# run ROLE PLAYER_ID: each identity keeps its own checkpoint, like one browser.
run() {
  "$GODOT" --headless --path . -- --net-test="$1" --player-id="$2" --checkpoint-path="res://$SAVES/$2.dat" \
    --server="ws://127.0.0.1:$PORT/ws" --lobby-name="$LOBBY" >"$LOGS/$1.log" 2>&1
}

run host host-id & H=$!
sleep 1
run guest guest-id & G=$!
sleep 4
run late late-id & L=$!
wait $G; GS=$?                      # the guest "refreshes"…
run guest2 guest-id & G2=$!         # …and comes back with the same identity
wait $H; HS=$?                      # the host crashes; hosting moves to guest2
run host2 host-id & H2=$!           # the old host returns
wait $G2; G2S=$?; wait $L; LS=$?; wait $H2; H2S=$?
sleep 0.5                           # lobby is empty now, kept for returning diggers
run host3 host-id; H3S=$?           # resumes from the server's checkpoint
kill $SERVER; wait $SERVER 2>/dev/null
start_server                        # server restart: every lobby is forgotten
run host4 host-id; H4S=$?           # resumes from its own local checkpoint

ROLES="host guest late guest2 host2 host3 host4"
for role in $ROLES; do grep -hE "NET_|CHECK|FINGERPRINT|STATE|SCRIPT ERROR" "$LOGS/$role.log"; done
status=0
for role in $ROLES; do grep -q "NET_PASS $role" "$LOGS/$role.log" || { echo "FAILED: $role did not pass"; status=1; }; done
if grep -q "SCRIPT ERROR" "$LOGS"/*.log; then echo "FAILED: script errors"; status=1; fi
# Every instance must generate identical floors.
d1=$(grep -h "FINGERPRINT" "$LOGS"/*.log | grep "d=1 " | sed 's/FINGERPRINT [a-z0-9]* //' | sort -u | wc -l)
d2=$(grep -h "FINGERPRINT" "$LOGS"/*.log | grep "d=2 " | sed 's/FINGERPRINT [a-z0-9]* //' | sort -u | wc -l)
[ "$d1" = 1 ] && [ "$d2" = 1 ] || { echo "FAILED: floor fingerprints differ (d1=$d1 d2=$d2 variants)"; status=1; }
# Resumed digs must match the state that was saved.
states=$(grep -h "^STATE" "$LOGS"/*.log | sed 's/STATE [a-z0-9]* //' | sort -u | wc -l)
[ "$states" = 1 ] || { echo "FAILED: resumed dig state differs ($states variants)"; status=1; }
for s in $HS $GS $LS $G2S $H2S $H3S $H4S; do [ "$s" = 0 ] || status=1; done
[ $status = 0 ] && echo "NET_TEST_PASS: co-op play, guest refresh, Wi-Fi drop + auto-reconnect, host crash + migration, host return, empty-lobby resume, server-restart resume"
exit $status
