# Releasing

## Versioning

The package follows [Semantic Versioning 2.0](https://semver.org). While the version is
`0.x`:

- a **minor** bump (`0.1.0` → `0.2.0`) may contain breaking changes;
- a **patch** bump (`0.1.0` → `0.1.1`) contains only fixes and additions that do not break
  callers.

The package stays on `0.x` until the iOS host has been verified on a real device and early
users have given feedback. `1.0.0` then freezes the public API under normal SemVer rules.

What counts as public API: everything exported from
`package:aws_liveness_for_flutter/aws_liveness_for_flutter.dart`, the names and order of
`LivenessErrorCode` values, the documented behaviour of `AwsLiveness`, and the host app
requirements (minimum SDK versions, Info.plist and Gradle settings). Raising a minimum
version is a breaking change.

## Deprecation policy

- Deprecate first with `@Deprecated('Use X instead. Will be removed in <version>.')` and a
  CHANGELOG entry; remove no earlier than the next minor release (`0.x`) or the next major
  release (`1.0` and later).
- Error codes are never renamed or reused. New codes are appended; a code that is no longer
  produced is deprecated and kept.
- Behaviour changes that callers may depend on (for example a different error code for the
  same situation) are listed under **Changed** in the CHANGELOG.

## Release checklist

1. `main` is green in CI (Dart, Android, iOS SPM and CocoaPods, backends).
2. Bump `version` in `pubspec.yaml` and `s.version` in `ios/aws_liveness_for_flutter.podspec`.
3. Move the `Unreleased` items in `CHANGELOG.md` under the new version with today's date.
4. Update [compatibility.md](compatibility.md) if SDK or toolchain versions changed, and
   say which are tested.
5. Run the [manual test checklist](manual-test-checklist.md) on devices for anything the
   release touches; record the results there.
6. Regenerate Pigeon if `pigeons/messages.dart` changed and confirm there is no diff:
   `dart run pigeon --input pigeons/messages.dart` then `dart format lib/src/messages.g.dart`.
7. Local checks:
   ```sh
   dart format --set-exit-if-changed .
   flutter analyze --fatal-infos
   flutter test --coverage
   dart doc --dry-run
   dart pub global run pana --no-warning .
   flutter pub publish --dry-run
   ```
8. Commit `chore: release vX.Y.Z`, tag `vX.Y.Z`, push the tag.
9. Check the package page on pub.dev, the score and the example tab.

## First publication (manual)

pub.dev only allows automated publishing for a package that already exists, so the first
version is published by hand:

1. `dart pub login` with the Google account that should own the package.
2. Run the release checklist above.
3. `flutter pub publish` and confirm.
4. On pub.dev, open the package's **Admin** tab and, if wanted, move it to a verified
   publisher.

## Automated publishing (after the first version)

1. On pub.dev, package **Admin** → **Automated publishing** → enable
   **Publishing from GitHub Actions**.
2. Repository: `mertcandanzz/aws_liveness_for_flutter`; tag pattern: `v{{version}}`.
3. Optionally require a GitHub environment (for example `pub.dev`) with required reviewers.
4. The `publish.yml` workflow runs on `v*` tags and publishes with GitHub's OIDC token; no
   long-lived pub credentials are stored in the repository. (The workflow is part of the CI
   setup, which is not in `main` yet.)
5. From then on, a release is: steps 1–8 of the checklist, then pushing the tag.
