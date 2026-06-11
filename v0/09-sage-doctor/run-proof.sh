#!/bin/bash
# V0.9 Sage Doctor — reproducible proof driver.
#
# Builds the package, runs the pure-logic tests, the full doctor against real
# Sage (human + JSON), every broken-config case, the config-persistence flow,
# and an orphan check after each worker-spawning run. Use a short ready-timeout
# for the broken cases so the boot-hang fails fast.
set -u
cd "$(dirname "$0")"
DOCTOR=./.build/release/sage-doctor
FIX="$(pwd)/fixtures"

hr() { printf '\n========== %s ==========\n' "$1"; }
orphans() {
  # The orphan trap from PROBLEMS.md: nothing sage-ish or fixture-ish may linger.
  local found
  found="$(pgrep -fl 'sage -python|worker.py|/usr/local/bin/sage|hang-sage|old-sage|sleep 100000' 2>/dev/null)"
  if [ -n "$found" ]; then
    echo "ORPHANS LEFT:"; echo "$found"
  else
    echo "orphan check: clean (no sage/worker/fixture processes)"
  fi
}

hr "BUILD (release)"
swift build -c release 2>&1 | grep -E 'error|Build complete'

hr "PURE-LOGIC TESTS (swift test)"
swift test 2>&1 | tail -2

export CASETTE_CONFIG_DIR="$(mktemp -d)"

hr "FULL DOCTOR — real Sage (human)"
$DOCTOR; echo "exit=$?"; orphans

hr "FULL DOCTOR — real Sage (JSON)"
$DOCTOR --json; echo "exit=$?"; orphans

# Broken-config cases use a short ready timeout so the boot-hang fails fast.
export CASETTE_READY_TIMEOUT=4

hr "BROKEN A — nonexistent --sage path (must fail loud, not fall through)"
$DOCTOR --sage /no/such/sage; echo "exit=$?"

hr "BROKEN B — non-sage executable (/bin/ls)"
$DOCTOR --sage /bin/ls; echo "exit=$?"; orphans

hr "BROKEN C — sage-like script that hangs at boot"
$DOCTOR --sage "$FIX/hang-sage.sh"; echo "exit=$?"; orphans

hr "BROKEN D — worker.py path that does not exist"
CASETTE_WORKER=/no/such/worker.py $DOCTOR --sage /usr/local/bin/sage; echo "exit=$?"; orphans

hr "BROKEN E — below-floor version (9.2) warning band"
$DOCTOR --sage "$FIX/old-sage.sh"; echo "exit=$?"; orphans

unset CASETTE_READY_TIMEOUT

hr "CONFIG — --use stores, subsequent run prefers stored, --forget clears"
CFG="$(mktemp -d)"; export CASETTE_CONFIG_DIR="$CFG"
$DOCTOR --use /usr/local/bin/sage >/dev/null
echo "stored file:"; cat "$CFG/sage-doctor.json"; echo
$DOCTOR --json | python3 -c "import json,sys; r=json.load(sys.stdin); print('selected', r['sagePath'], 'via', [c['source'] for c in r['candidates'] if c['selected']])"
$DOCTOR --forget
[ -f "$CFG/sage-doctor.json" ] && echo "config still present (unexpected)" || echo "config cleared (file gone)"

hr "FINAL ORPHAN CHECK"
orphans
