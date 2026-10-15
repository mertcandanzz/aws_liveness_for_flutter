#!/usr/bin/env bash
set -euo pipefail

flutter pub get
flutter build ios --simulator --debug --no-codesign --config-only

# Flutter's full build adds global -sdk and BUILD_DIR overrides. These can put
# SwiftPM's macOS build-tool executables in the simulator output directory.
# Let Xcode infer each target's SDK from the destination and share DerivedData
# with ios_xctest.sh. Do not patch SDK sources or copy build-tool binaries.
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$RUNNER_TEMP/aws-liveness-derived-data" \
  -quiet CODE_SIGNING_ALLOWED=NO build
