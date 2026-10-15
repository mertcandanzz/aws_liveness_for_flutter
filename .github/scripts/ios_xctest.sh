#!/usr/bin/env bash
# Runs example/ios/RunnerTests on the first available iPhone simulator.
# Run from example/ after `flutter build ios --simulator`, which generates the Xcode configuration.
set -euo pipefail
test "${TEST_RUNNER_AWS_LIVENESS_EXPECT_SDK:?Set the SDK-link expectation}" = 0 \
  || test "$TEST_RUNNER_AWS_LIVENESS_EXPECT_SDK" = 1

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
  -destination-timeout 120 \
  -derivedDataPath "${RUNNER_TEMP:-/tmp}/aws-liveness-derived-data" \
  -resultBundlePath "${RUNNER_TEMP:-/tmp}/RunnerTests.xcresult" \
  -only-testing:RunnerTests \
  CODE_SIGNING_ALLOWED=NO
