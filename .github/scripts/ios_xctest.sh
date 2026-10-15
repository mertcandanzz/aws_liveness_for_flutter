#!/usr/bin/env bash
# Runs example/ios/RunnerTests on the first available iPhone simulator.
# Run from example/ after `flutter build ios`, which generates the Xcode configuration.
set -euo pipefail

udid="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
print(next(d["udid"] for runtime, ds in devices.items() if "iOS" in runtime
           for d in ds if d["name"].startswith("iPhone")))
')"

xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -destination "id=$udid" \
  -only-testing:RunnerTests \
  CODE_SIGNING_ALLOWED=NO
