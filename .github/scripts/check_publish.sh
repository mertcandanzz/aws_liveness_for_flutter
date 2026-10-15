#!/usr/bin/env bash
set -euo pipefail
# New Flutter SDKs migrate analysis_options.yaml during Flutter commands. Validate
# the committed package rather than publishing that mutated CI working directory.
# Keep the snapshot outside any parent Git checkout (same rule as check_pana.sh).
publish_dir="$(mktemp -d "$RUNNER_TEMP/publish-source.XXXXXX")"
git archive HEAD | tar -x -C "$publish_dir"
cp pubspec.lock "$publish_dir/pubspec.lock"
cd "$publish_dir"
# Use the Dart executable supplied by Flutter, as the official OIDC publisher does.
# `dart pub` does not invoke Flutter's project migration hooks.
dart pub get
dart pub publish --dry-run
