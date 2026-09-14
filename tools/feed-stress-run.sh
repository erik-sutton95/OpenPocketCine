#!/usr/bin/env bash
# Physical iPhone + Pocket 4 Pro feed-stress harness.
# Coordinator owns hardware and xcodebuild. Default subcommand prints the recipe.
# Never uploads footage. Artifacts are numeric only under Documents/feed-stress/.
#
#   tools/feed-stress-run.sh print
#   DEVICE=<coredevice-id-or-name> SEED=20260914 LIMIT=300 RECORD=0 \
#     tools/feed-stress-run.sh run
#   DEVICE=... tools/feed-stress-run.sh pull
#   tools/feed-stress-run.sh report
#
# Equivalent XCTest invocation:
#
# ios-feed-stress device seed="20260914" limit="300" record="0":
#     TEST_RUNNER_OPV_FEED_STRESS=1 \
#     TEST_RUNNER_OPV_FEED_STRESS_SEED={{seed}} \
#     TEST_RUNNER_OPV_FEED_STRESS_LIMIT_S={{limit}} \
#     TEST_RUNNER_OPV_FEED_STRESS_RECORD={{record}} \
#     xcodebuild -project ios/OpenPocketCine.xcodeproj -scheme OpenPocketCineUIReview \
#       -destination 'platform=iOS,id={{device}}' -allowProvisioningUpdates \
#       -only-testing:OpenPocketCineUITests/FeedStressTests \
#       test
#     tools/feed-stress-pull.sh
#     python3 tools/feed-stress-report.py /tmp/opc-feed-stress
#
# Optional inject (Debug only, after 30 s healthy baseline, scenario-armed):
#   TEST_RUNNER_OPV_FEED_STRESS_INJECT=loss:0.05,burst:8:40,outputSilenceMs:2500
# Delay injection is omitted (ACK-queue safe). Requires FeedStressAutomation.installIfRequested()
# and the note*/shouldSilenceOutput seams. Start with a live Pocket 4 Pro picture already up.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CMD="${1:-print}"
DEVICE="${DEVICE:-}"
SEED="${SEED:-20260914}"
LIMIT="${LIMIT:-300}"
RECORD="${RECORD:-0}"
INJECT="${INJECT:-}"
DEST="${DEST:-/tmp/opc-feed-stress}"

print_recipe() {
    cat <<EOF
Equivalent XCTest invocation (the repository already provides ios-feed-stress):

ios-feed-stress device seed="${SEED}" limit="${LIMIT}" record="${RECORD}":
    TEST_RUNNER_OPV_FEED_STRESS=1 \\
    TEST_RUNNER_OPV_FEED_STRESS_SEED={{seed}} \\
    TEST_RUNNER_OPV_FEED_STRESS_LIMIT_S={{limit}} \\
    TEST_RUNNER_OPV_FEED_STRESS_RECORD={{record}} \\
    xcodebuild -project ios/OpenPocketCine.xcodeproj -scheme OpenPocketCineUIReview \\
      -destination 'platform=iOS,id={{device}}' -allowProvisioningUpdates \\
      -only-testing:OpenPocketCineUITests/FeedStressTests \\
      test

Direct invocation:
  cd $ROOT
  just ios-generate
  TEST_RUNNER_OPV_FEED_STRESS=1 TEST_RUNNER_OPV_FEED_STRESS_SEED=${SEED} \\
    TEST_RUNNER_OPV_FEED_STRESS_LIMIT_S=${LIMIT} TEST_RUNNER_OPV_FEED_STRESS_RECORD=${RECORD} \\
EOF
    if [[ -n "$INJECT" ]]; then
        echo "    TEST_RUNNER_OPV_FEED_STRESS_INJECT=${INJECT} \\"
    fi
    cat <<EOF
    xcodebuild -project ios/OpenPocketCine.xcodeproj -scheme OpenPocketCineUIReview \\
      -destination 'platform=iOS,id=${DEVICE:-<coredevice-id>}' -allowProvisioningUpdates \\
      -only-testing:OpenPocketCineUITests/FeedStressTests test

Then: DEVICE=${DEVICE:-<id>} tools/feed-stress-pull.sh && python3 tools/feed-stress-report.py ${DEST}
Preconditions: Debug device build, live Pocket 4 Pro picture, installIfRequested wired.
Do not run against the simulator. Do not overlap other xcodebuild.
EOF
}

run_tests() {
    if [[ -z "$DEVICE" ]]; then
        echo "DEVICE is required (xcrun xctrace list devices / xcrun devicectl list devices)." >&2
        exit 2
    fi
    print_recipe
    cd "$ROOT"
    env_args=(
        TEST_RUNNER_OPV_FEED_STRESS=1
        TEST_RUNNER_OPV_FEED_STRESS_SEED="$SEED"
        TEST_RUNNER_OPV_FEED_STRESS_LIMIT_S="$LIMIT"
        TEST_RUNNER_OPV_FEED_STRESS_RECORD="$RECORD"
    )
    if [[ -n "$INJECT" ]]; then
        env_args+=(TEST_RUNNER_OPV_FEED_STRESS_INJECT="$INJECT")
    fi
    if [[ -n "${SCENARIOS:-}" ]]; then
        env_args+=(TEST_RUNNER_OPV_FEED_STRESS_SCENARIOS="$SCENARIOS")
    fi
    status=0
    pull_artifacts() {
        DEVICE="$DEVICE" DEST="$DEST" "$ROOT/tools/feed-stress-pull.sh" || true
        python3 "$ROOT/tools/feed-stress-report.py" "$DEST" || true
    }
    trap 'pull_artifacts; exit "$status"' EXIT
    just ios-generate || status=$?
    if [[ "$status" -ne 0 ]]; then
        exit "$status"
    fi
    env "${env_args[@]}" xcodebuild -project ios/OpenPocketCine.xcodeproj \
      -scheme OpenPocketCineUIReview \
      -destination "platform=iOS,id=${DEVICE}" -allowProvisioningUpdates \
      -only-testing:OpenPocketCineUITests/FeedStressTests \
      test || status=$?
}

case "$CMD" in
    print) print_recipe ;;
    run) run_tests ;;
    pull) DEVICE="$DEVICE" DEST="$DEST" "$ROOT/tools/feed-stress-pull.sh" ;;
    report) python3 "$ROOT/tools/feed-stress-report.py" "$DEST" ;;
    *)
        echo "usage: tools/feed-stress-run.sh [print|run|pull|report]" >&2
        exit 2
        ;;
esac
