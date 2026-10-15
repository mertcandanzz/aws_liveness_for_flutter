#!/usr/bin/env bash
# Checks the iOS plugin sources on a host without Xcode, using the official Swift Linux
# image in Docker:
#   1. `swiftc -parse` on every plugin and RunnerTests source file (all #if branches);
#   2. compiles the platform-free sources (everything except the Flutter adapters; UIKit and
#      FaceLiveness code is compiled out by its #if canImport) with the Pigeon types, and
#      runs example/ios/RunnerTests/RunnerTests.swift with swift-corelibs-xctest.
#
# This does NOT replace the macOS CI jobs: UIKit, Flutter and FaceLiveness code is only
# parsed here, never type-checked.
#
# Usage: tool/ios_linux_check.sh   (SWIFT_IMAGE overrides the image, default swift:5.10-jammy)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
if command -v cygpath >/dev/null 2>&1; then
  root="$(cygpath -w "$root")"
fi
image="${SWIFT_IMAGE:-swift:5.10-jammy}"

# Forward the optional SDK expectation to XCTest (0 for this Linux fallback build).
MSYS_NO_PATHCONV=1 docker run --rm -i -e AWS_LIVENESS_EXPECT_SDK -v "$root:/repo:ro" "$image" bash -s <<'EOF'
set -euo pipefail
src=/repo/ios/aws_liveness_for_flutter/Sources/aws_liveness_for_flutter
tests=/repo/example/ios/RunnerTests
pkg=/tmp/ios-check

echo "== swiftc -parse"
swiftc -parse "$src"/*.swift "$tests"/*.swift

mkdir -p "$pkg/Sources/aws_liveness_for_flutter" "$pkg/Tests/RunnerTests"
for file in "$src"/*.swift; do
  case "$(basename "$file")" in
    Messages.g.swift | AwsLivenessForFlutterPlugin.swift | LivenessHostApiImpl.swift) ;;
    *) cp "$file" "$pkg/Sources/aws_liveness_for_flutter/" ;;
  esac
done
# The Pigeon message types without the Flutter import, wrapError and the codec/channel code.
awk '
  /^#if os\(iOS\)/ { skip = 1 }
  skip { if (/^#endif/) skip = 0; next }
  /^private func wrapError/ { wrap = 1 }
  wrap { if (/^}/) wrap = 0; next }
  /^private class MessagesPigeonCodecReader/ { exit }
  { print }
' "$src/Messages.g.swift" > "$pkg/Sources/aws_liveness_for_flutter/MessagesTypes.swift"
cp "$tests"/*.swift "$pkg/Tests/RunnerTests/"
cat > "$pkg/Package.swift" <<'MANIFEST'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "ios-check",
  targets: [
    .target(name: "aws_liveness_for_flutter"),
    .testTarget(name: "RunnerTests", dependencies: ["aws_liveness_for_flutter"]),
  ]
)
MANIFEST

cd "$pkg"
echo "== swift build"
swift build --build-tests 2>&1
echo "== swift test"
swift test --skip-build 2>&1
EOF
