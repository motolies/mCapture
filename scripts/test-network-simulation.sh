#!/usr/bin/env bash
# Run actual URLSession integration checks against the local, checked-in ipify simulation.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PORT="${MCAPTURE_SIMULATION_PORT:-49187}"
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mcapture-network.XXXXXX")"
postman simulation run postman/simulations/network-ipify.sim.yaml --port "$PORT" --no-history --output ndjson > "$LOG_DIR/requests.ndjson" 2> "$LOG_DIR/server.err" &
SIM_PID=$!
trap 'kill -INT "$SIM_PID" 2>/dev/null || true; wait "$SIM_PID" 2>/dev/null || true' EXIT
for _ in {1..100}; do
    if grep -q '"event":"listening"' "$LOG_DIR/requests.ndjson"; then break; fi
    if ! kill -0 "$SIM_PID" 2>/dev/null; then cat "$LOG_DIR/server.err"; exit 1; fi
    sleep 0.1
done
if ! grep -q '"event":"listening"' "$LOG_DIR/requests.ndjson"; then cat "$LOG_DIR/server.err"; exit 1; fi
MCAPTURE_IPIFY_SIMULATION="http://127.0.0.1:$PORT/ipify" scripts/test.sh -Xswiftc -warnings-as-errors "$@"
printf 'Simulation request evidence: %s\n' "$LOG_DIR/requests.ndjson"
