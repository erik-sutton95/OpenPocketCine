# Caps for TestFlight / Play What to Test. Sourced by the check scripts.
# Contract: docs/tester-notes.md
tester_notes_max_characters=2000
tester_notes_max_feature_bullets=4
tester_notes_max_new_bullets=3
tester_notes_max_fix_bullets=4
tester_notes_max_test_bullets=3
tester_notes_max_bullet_characters=200
tester_notes_cumulative=0

# An explicitly named open-beta baseline opts into a complete release window.
# Keep the short per-build format unchanged for routine internal testing.
tester_notes_set_window() {
  if head -n 1 "$1" | grep -Eq '^Since open beta build [1-9][0-9]*$'; then
    tester_notes_cumulative=1
    tester_notes_max_characters=4000
    tester_notes_max_new_bullets=16
    tester_notes_max_fix_bullets=20
    tester_notes_max_test_bullets=5
  fi
}
