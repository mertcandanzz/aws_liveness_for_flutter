#!/usr/bin/env bash
# Keep the generator version consistent across minimum and stable Dart SDKs.
# The published dependency remains ^27.3.0; newer Dart can resolve a newer generator.
set -euo pipefail
test ! -e pubspec_overrides.yaml
lock_backup="$(mktemp)"
cp pubspec.lock "$lock_backup"
cleanup() {
  status=$?
  trap - EXIT
  rm -f pubspec_overrides.yaml
  cp "$lock_backup" pubspec.lock
  rm -f "$lock_backup"
  flutter pub get --enforce-lockfile || exit 1
  exit "$status"
}
trap cleanup EXIT
printf 'dependency_overrides:\n  pigeon: 27.3.0\n' > pubspec_overrides.yaml
flutter pub get
dart run pigeon --input pigeons/messages.dart
dart format lib/src/messages.g.dart
git diff --exit-code -- \
  lib/src/messages.g.dart \
  android/src/main/kotlin/io/github/mertcandanzz/aws_liveness_for_flutter/Messages.g.kt \
  ios/aws_liveness_for_flutter/Sources/aws_liveness_for_flutter/Messages.g.swift
