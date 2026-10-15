#!/usr/bin/env bash
# Simulator smoke test for Notes Redux (used by .github/workflows/ios-build.yml).
#
# Installs the Debug simulator build on a fresh iOS Simulator, launches it in a
# few states using DEBUG-only launch arguments (see
# NotesRedux.swiftpm/SmokeTestHooks.swift), and saves a screenshot of each.
# Fails if the app is no longer running a few seconds after any launch, which
# catches crashes on startup and while opening notes.
#
# This is not a UI test: it does not tap or type. Screenshots must be reviewed
# by a person.
#
# Usage: smoke-test.sh <derived-data-dir> <screenshot-output-dir>
set -euo pipefail

DERIVED="$1"
OUT="$2"
SETTLE_SECONDS=6
mkdir -p "$OUT"

APP=$(find "$DERIVED/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name '*.app' -print -quit)
if [ -z "$APP" ]; then
  echo "::error::No .app found under $DERIVED"
  exit 1
fi
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")
echo "App: $APP ($BUNDLE_ID)"

# Newest available iOS runtime, first iPhone on it.
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
def version(runtime):
    m = re.search(r"iOS-([0-9-]+)$", runtime)
    return [int(p) for p in m.group(1).split("-")] if m else []
for runtime in sorted((r for r in devices if "iOS" in r), key=version, reverse=True):
    for device in devices[runtime]:
        if device["name"].startswith("iPhone"):
            print(device["udid"])
            sys.exit(0)
sys.exit("No available iPhone simulator")
')
echo "Simulator: $UDID"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"

# launch_and_capture <screenshot-name> [launch arguments...]
launch_and_capture() {
  local name="$1"
  shift
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  # Prints "<bundle id>: <pid>".
  local output pid
  output=$(xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@")
  pid="${output##*: }"
  sleep "$SETTLE_SECONDS"
  # Simulator apps are ordinary processes on the host Mac.
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "::error::App exited during '$name' (pid $pid). It probably crashed."
    xcrun simctl io "$UDID" screenshot "$OUT/$name-FAILED.png" || true
    exit 1
  fi
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png"
  echo "Captured $name"
}

# Order matters: the first launch seeds the sample notes, the add-entry launch
# saves an entry, and the plain relaunch after it shows that it persisted.
launch_and_capture 01-notes-list
launch_and_capture 02-birthdays-note -SmokeTestOpenNote Birthdays
launch_and_capture 03-birthdays-outline -SmokeTestOpenNote Birthdays -SmokeTestShowOutline YES
launch_and_capture 04-add-entry-friends \
  -SmokeTestAddEntry "Josh B - 5/28/2004" -SmokeTestNote Birthdays -SmokeTestSection Friends
launch_and_capture 05-relaunch-persisted -SmokeTestOpenNote Birthdays
# Shows the Add Entry sheet itself, pre-filled but NOT submitted.
launch_and_capture 06-add-entry-sheet   -SmokeTestShowAddEntrySheet "Aunt May - 2/14/1960" -SmokeTestNote Birthdays -SmokeTestSection Family
# Stage 4: grid layout (the app's own @AppStorage key, set via launch argument)
# and the Change Icon sheet.
launch_and_capture 07-notes-grid -notesLayout grid
launch_and_capture 08-change-icon -SmokeTestChangeIcon Birthdays

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
echo "Smoke test passed. Screenshots in $OUT"
