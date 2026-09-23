#!/usr/bin/env bash
# Physical iPhone + saved Pocket 4 Pro power/CPU/GPU soak.
#
#   DEVICE=<udid> tools/perf-soak.sh [profile ...]
#
# Profiles (PerfSoakTests): clean, lut, pro (default), heavy; append +rec to record a take.
# Env: DETACH (1: XCTest exits before tracing, default), HOLD (s, default 90), TRACE (s, default HOLD-10), CONFIG (Release),
#      TEMPLATE ("Power Profiler"), EXTRA ("Time Profiler" instrument added),
#      COOL (s between profiles, default 60), OUT (.local/perf/<stamp>).
# Traces and logs stay under ignored .local/. Never records on the camera.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${DEVICE:?DEVICE=<udid> required (xcrun xctrace list devices)}"
HOLD="${HOLD:-90}"
TRACE="${TRACE:-$((HOLD - 10))}"
CONFIG="${CONFIG:-Release}"
TEMPLATE="${TEMPLATE:-Power Profiler}"
EXTRA="${EXTRA:-Time Profiler}"
COOL="${COOL:-60}"
OUT="${OUT:-$ROOT/.local/perf/$(date +%Y%m%d-%H%M%S)}"
PROFILES=("$@")
[[ ${#PROFILES[@]} -gt 0 ]] || PROFILES=(pro)
mkdir -p "$OUT"
cd "$ROOT"

just ios-generate >/dev/null
DERIVED="${DERIVED:-$ROOT/.local/perf/derived}"
xcodebuild build-for-testing -project ios/OpenPocketCine.xcodeproj -scheme OpenPocketCineUIReview \
  -configuration "$CONFIG" -destination "platform=iOS,id=$DEVICE" -allowProvisioningUpdates \
  -derivedDataPath "$DERIVED" >"$OUT/build.log" 2>&1 || { tail -40 "$OUT/build.log"; exit 1; }
XCTESTRUN="$(ls "$DERIVED"/Build/Products/*.xctestrun | head -1)"

for i in "${!PROFILES[@]}"; do
  profile="${PROFILES[$i]}"
  rec=0
  if [[ "$profile" == *+rec ]]; then rec=1; profile="${profile%+rec}"; fi
  tag="$profile"
  # A REC take must be stopped by the test, so +rec keeps XCTest attached.
  det="${DETACH:-1}"
  [[ $rec == 1 ]] && det=0
  [[ $rec == 1 ]] && tag="$profile-rec"
  log="$OUT/$tag.log"
  echo "== $profile (hold ${HOLD}s, trace ${TRACE}s, $CONFIG)"
  # Install this build explicitly so A/B runs from different worktrees never mix.
  xcrun devicectl device install app --device "$DEVICE" \
    "$DERIVED/Build/Products/$CONFIG-iphoneos/OpenPocketCine.app" >"$OUT/$tag.install.log" 2>&1
  xcrun devicectl device process launch --device "$DEVICE" --terminate-existing \
    com.opencapture.openpocketcine >"$OUT/$tag.launch.log" 2>&1
  sleep 3
  TEST_RUNNER_OPV_PERF_DETACH="$det" TEST_RUNNER_OPV_PERF_ATTACH=1 TEST_RUNNER_OPV_PERF_RECORD="$rec" TEST_RUNNER_OPV_PERF_SOAK=1 TEST_RUNNER_OPV_PERF_PROFILE="$profile" TEST_RUNNER_OPV_PERF_SOAK_S="$HOLD" \
    xcodebuild test-without-building -xctestrun "$XCTESTRUN" -destination "platform=iOS,id=$DEVICE" \
    -only-testing:OpenPocketCineUITests/PerfSoakTests -resultBundlePath "$OUT/$tag.xcresult" \
    >"$log" 2>&1 &
  test_pid=$!
  # Wait for the hold marker (or the test ending early).
  until grep -q PERF_SOAK_HOLD_BEGIN "$log" 2>/dev/null; do
    kill -0 "$test_pid" 2>/dev/null || { echo "test ended before hold"; tail -30 "$log"; break; }
    sleep 1
  done
  # Detached (default): the test configures and exits; trace with XCTest gone.
  [[ "$det" == 1 ]] && { wait "$test_pid" || true; sleep 3; }
  if grep -q PERF_SOAK_HOLD_BEGIN "$log"; then
    grep -o 'PERF_SOAK_HOLD_BEGIN.*' "$log" | head -1
    extra_args=()
    [[ -n "$EXTRA" ]] && extra_args=(--instrument "$EXTRA")
    xcrun xctrace record --device "$DEVICE" --template "$TEMPLATE" "${extra_args[@]}" \
      --attach OpenPocketCine --time-limit "${TRACE}s" --output "$OUT/$tag.trace" \
      >"$OUT/$tag.xctrace.log" 2>&1 || tail -5 "$OUT/$tag.xctrace.log"
  fi
  if [[ "$det" == 1 ]]; then
    grep -q "Test Suite 'Selected tests' passed" "$log" && echo "test passed" || echo "test FAILED (see $log)"
    # Stop a detached REC take and the app.
    xcrun devicectl device process terminate --device "$DEVICE" \
      --pid "$(xcrun devicectl device info processes --device "$DEVICE" 2>/dev/null | awk '/OpenPocketCine.app\/OpenPocketCine$/ {print $1; exit}')" >/dev/null 2>&1 || true
  else
    wait "$test_pid" && echo "test passed" || echo "test FAILED (see $log)"
  fi
  if [[ -d "$OUT/$tag.trace" ]]; then
    xcrun xctrace symbolicate --input "$OUT/$tag.trace" \
      --dsym "$DERIVED/Build/Products/$CONFIG-iphoneos/OpenPocketCine.app.dSYM" >/dev/null 2>&1 || true
    python3 "$ROOT/tools/perf-trace-summary.py" "$OUT/$tag.trace" | tee "$OUT/$tag.summary.txt" || true
  fi
  [[ $i -lt $((${#PROFILES[@]} - 1)) ]] && sleep "$COOL"
done
echo "artifacts: $OUT"
