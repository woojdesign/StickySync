#!/usr/bin/env bash
#
# 0.11.4: nuke transient developer state after Xcode/CoreSimulator
# get into a bad state. Idempotent; safe to run whenever tests hang,
# sim cloning fails ("Device was allocated but was stuck in creation
# state"), or PTY exhaustion kicks in.
#
# What it does (in this order):
#   1. Kill every StickySync process (Debug + Release) hard.
#   2. Shut down all iOS Simulators.
#   3. Restart the CoreSimulator daemon.
#   4. Kill Xcode's SourceKit + Swift build daemons.
#   5. Nuke DerivedData for this project.
#   6. Nuke the CoreSimulator temp clones under
#      ~/Library/Developer/CoreSimulator/Devices/*/tmp
#
# Does NOT touch:
#   - Sean's local StickySync store (~/Library/Application Support/StickySync)
#   - Any of Sean's actual note data
#   - iCloud state
#   - The user's Simulator devices themselves (only temp clones)
#
# Run when tests fail with sim-clone errors or Xcode feels stuck.
#
set -euo pipefail

echo "==> Killing StickySync processes"
killall -9 StickySync 2>/dev/null || true

echo "==> Shutting down all iOS simulators"
xcrun simctl shutdown all 2>/dev/null || true

echo "==> Restarting CoreSimulator daemons"
# The simulator daemon can wedge such that new clone requests hang.
# `launchctl bootout` + `bootstrap` is the modern way; fall back to
# `killall` if we don't have permission.
launchctl bootout gui/$(id -u) com.apple.CoreSimulator.CoreSimulatorService 2>/dev/null || \
    killall -9 com.apple.CoreSimulator.CoreSimulatorService 2>/dev/null || true
sleep 1
open -jga Simulator 2>/dev/null || true
# The service respawns on demand — no need to explicitly re-bootstrap.

echo "==> Killing Xcode build daemons"
for name in sourcekit-lsp swift-frontend SwiftBuild; do
    killall -9 "$name" 2>/dev/null || true
done

echo "==> Removing DerivedData for StickySync"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData"
rm -rf "$DERIVED"/StickySync-*
rm -rf /tmp/x /tmp/xtest

echo "==> Removing CoreSimulator temp clones"
find "$HOME/Library/Developer/CoreSimulator/Devices" -type d -name tmp -maxdepth 3 2>/dev/null \
    | while read -r dir; do
        rm -rf "$dir"/*
      done

echo
echo "Done. Next build/test starts from a clean slate."
echo "If tests still fail with 'stuck in creation state', reboot."
