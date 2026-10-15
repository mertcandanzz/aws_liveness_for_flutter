#!/usr/bin/env bash
set -euo pipefail
# Outside the checkout: pana follows parent Git roots and copies the source tree.
source_dir="$(mktemp -d "$RUNNER_TEMP/pana-source.XXXXXX")"
temp_dir="$(mktemp -d "$RUNNER_TEMP/pana-temp.XXXXXX")"
git archive HEAD | tar -x -C "$source_dir"
cp pubspec.lock "$source_dir/pubspec.lock"
dart pub global activate pana 0.23.12
TMPDIR="$temp_dir" dart pub global run pana --no-warning --json "$source_dir" \
  | tee "$RUNNER_TEMP/pana.json"
python3 .github/scripts/ci_gate.py pana "$RUNNER_TEMP/pana.json"
