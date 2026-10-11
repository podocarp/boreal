#!/usr/bin/env bash
# Run semantic (no-pixel) tests for a Godot project: fast, dummy renderer.
# Usage: run_tests.sh <project-dir> [test-script...]
#   With no test-script args, runs every tests/test_*.gd in the project via --script.
# Each test script extends SceneTree (or MainLoop), prints "PASS <name>" lines and
# calls quit(0); nonzero exit or any "FAIL" line fails the suite. A script that
# prints no PASS line FAILS (a test that asserts nothing must not pass silently).
set -uo pipefail
PROJ="${1:?usage: run_tests.sh <project-dir> [test-script...]}"
shift || true
PROJ=$(cd "$PROJ" && pwd)   # absolute: godot --path + res:// mapping must not depend on caller cwd

# Fresh clones lack the imported .godot/ cache (gitignored): class_name globals
# resolve as "Identifier not declared" until an import pass runs. Cheap no-op when current.
godot --headless --path "$PROJ" --import --quit >/dev/null 2>&1 || true

if [[ $# -eq 0 ]]; then
  mapfile -t TESTS < <(find "$PROJ/tests" -maxdepth 1 -name 'test_*.gd' 2>/dev/null | sort)
else
  TESTS=("$@")
fi

if [[ ${#TESTS[@]} -eq 0 ]]; then
  echo "no test scripts found under $PROJ/tests (expected test_*.gd)"; exit 1
fi

fails=0
for t in "${TESTS[@]}"; do
  name=$(basename "$t")
  echo "== $name"
  out=$(timeout 120 godot --headless --path "$PROJ" --script "res://${t#"$PROJ"/}" 2>&1)
  code=$?
  echo "$out" | grep -E '^(PASS|FAIL)' || true
  reason=""
  [[ $code -eq 124 ]] && reason="TIMEOUT after 120s (test hung?)"
  [[ $code -ne 0 && -z "$reason" ]] && reason="exit code $code"
  echo "$out" | grep -q '^FAIL' && reason="${reason:-FAIL line printed}"
  [[ -z "$reason" ]] && ! echo "$out" | grep -q '^PASS' && reason="no PASS line (test asserted nothing?)"
  if [[ -n "$reason" ]]; then
    echo "REASON: $reason"
    echo "$out" | grep -viE 'ALSA|alsa|audio' | tail -15
    fails=$((fails+1))
  fi
done

echo "== $(( ${#TESTS[@]} - fails ))/${#TESTS[@]} test scripts passed"
exit $(( fails > 0 ? 1 : 0 ))
