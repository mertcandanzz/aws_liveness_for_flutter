// Device tests for aws_liveness_for_flutter (design §11.4).
//
// Run on a real Android device from example/:
//
//   adb reverse tcp:8787 tcp:8787        # when the backend runs on this machine
//   adb shell pm grant io.github.mertcandanzz.aws_liveness_for_flutter_example android.permission.CAMERA
//   flutter test integration_test/liveness_test.dart \
//     --dart-define=LIVENESS_BACKEND_URL=http://localhost:8787 \
//     --dart-define=LIVENESS_BACKEND_TOKEN=<token>
//
// Tests that need the backend skip when LIVENESS_BACKEND_URL or
// LIVENESS_BACKEND_TOKEN is unset. Tests that need the camera skip unless the
// permission is granted. The permission test runs only with
// --dart-define=EXPECT_CAMERA_PERMANENTLY_DENIED=true after:
//
//   adb shell pm revoke <package> android.permission.CAMERA
//   adb shell pm set-permission-flags <package> android.permission.CAMERA user-fixed
//
// No test here needs a real face, and none fakes a successful check.

import 'dart:async';
import 'dart:math';

import 'package:aws_liveness_for_flutter/aws_liveness_for_flutter.dart';
import 'package:aws_liveness_for_flutter_example/src/backend_client.dart';
import 'package:aws_liveness_for_flutter_example/src/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _expectCameraDenied = bool.fromEnvironment(
  'EXPECT_CAMERA_PERMANENTLY_DENIED',
);
const _settings = BackendSettings.fromEnvironment;
const _region = String.fromEnvironment(
  'LIVENESS_REGION',
  defaultValue: 'eu-west-1',
);

/// Skips the test unless the backend URL and token were passed.
bool _backendConfigured() {
  if (_settings.isComplete) return true;
  markTestSkipped(
    'Set --dart-define=LIVENESS_BACKEND_URL and LIVENESS_BACKEND_TOKEN.',
  );
  return false;
}

const _testTimeout = Timeout(Duration(minutes: 2));

/// A random, well-formed session id that no backend created.
String _unknownSessionId() {
  final random = Random.secure();
  final hex = List.generate(32, (_) => random.nextInt(16).toRadixString(16));
  hex[12] = '4';
  hex[16] = '89ab'[random.nextInt(4)];
  final s = hex.join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-'
      '${s.substring(16, 20)}-${s.substring(20)}';
}

/// Obviously fake temporary credentials that AWS rejects.
LivenessCredentials _fakeCredentials() => LivenessCredentials(
  accessKeyId: 'ASIA-INVALID-TEST-KEY',
  secretAccessKey: 'invalid-secret-for-tests',
  sessionToken: 'invalid-session-token-for-tests',
  expiration: DateTime.now().add(const Duration(minutes: 15)),
);

Future<LivenessCredentials> _neverCompletes() =>
    Completer<LivenessCredentials>().future;

BackendClient _backend() =>
    BackendClient(baseUrl: _settings.parsedUrl!, token: _settings.token);

/// Skips the test unless the camera permission is granted; the tests cannot
/// answer a system permission dialog.
Future<bool> _cameraGranted() async {
  final status = await AwsLiveness.getCameraPermissionStatus();
  if (status == CameraPermissionStatus.granted) return true;
  markTestSkipped(
    'Camera permission is ${status.name}; grant it with adb shell pm grant.',
  );
  return false;
}

LivenessErrorCode? _code(LivenessResult result) =>
    result is LivenessFailed ? result.error.code : null;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('checkAvailability reports a linked SDK and a camera', (_) async {
    final availability = await AwsLiveness.checkAvailability();

    expect(availability.isAvailable, isTrue, reason: '$availability');
    expect(availability.reason, isNull);
  });

  testWidgets(
    'a permanently denied camera gives a typed permission error',
    (_) async {
      final result = await AwsLiveness.start(
        LivenessRequest(
          sessionId: _unknownSessionId(),
          region: _region,
          credentialsProvider: () async => throw StateError('not reached'),
        ),
      );

      expect(
        _code(result),
        LivenessErrorCode.cameraPermissionPermanentlyDenied,
      );
      expect(
        (result as LivenessFailed).error.category,
        LivenessErrorCategory.permission,
      );
    },
    skip: !_expectCameraDenied,
    timeout: _testTimeout,
  );

  testWidgets('an unknown session gives sessionNotFound', (_) async {
    if (!_backendConfigured() || !await _cameraGranted()) return;
    final backend = _backend();
    addTearDown(backend.close);
    // A real session only to obtain valid credentials.
    final real = await backend.createSession();

    final result = await AwsLiveness.start(
      LivenessRequest(
        sessionId: _unknownSessionId(),
        region: real.region,
        credentialsProvider: () => backend.fetchCredentials(real.sessionId),
        showStartView: false,
        timeout: const Duration(seconds: 60),
      ),
    );

    expect(_code(result), LivenessErrorCode.sessionNotFound, reason: '$result');
  }, timeout: _testTimeout);

  testWidgets(
    'invalid credentials give accessDenied or invalidSignature',
    (_) async {
      if (!_backendConfigured() || !await _cameraGranted()) return;
      final backend = _backend();
      addTearDown(backend.close);
      final session = await backend.createSession();

      final result = await AwsLiveness.start(
        LivenessRequest(
          sessionId: session.sessionId,
          region: session.region,
          credentialsProvider: () async => _fakeCredentials(),
          showStartView: false,
          timeout: const Duration(seconds: 60),
        ),
      );

      expect(
        _code(result),
        anyOf(
          LivenessErrorCode.accessDenied,
          LivenessErrorCode.invalidSignature,
        ),
        reason: '$result',
      );
    },
    timeout: _testTimeout,
  );

  testWidgets('a throwing provider gives credentialsUnavailable', (_) async {
    if (!await _cameraGranted()) return;
    final thrown = StateError('backend unreachable');

    final result = await AwsLiveness.start(
      LivenessRequest(
        sessionId: _unknownSessionId(),
        region: _region,
        credentialsProvider: () async => throw thrown,
        showStartView: false,
        timeout: const Duration(seconds: 60),
      ),
    );

    expect(_code(result), LivenessErrorCode.credentialsUnavailable);
    expect((result as LivenessFailed).error.cause, same(thrown));
  }, timeout: _testTimeout);

  testWidgets('cancel() ends the attempt as an app cancel', (_) async {
    if (!await _cameraGranted()) return;

    final pending = AwsLiveness.start(
      LivenessRequest(
        sessionId: _unknownSessionId(),
        region: _region,
        credentialsProvider: _neverCompletes,
        timeout: const Duration(seconds: 60),
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 3));
    await AwsLiveness.cancel();
    final result = await pending;

    expect(result, isA<LivenessCancelled>());
    expect((result as LivenessCancelled).reason, LivenessCancelReason.app);
    expect(AwsLiveness.isActive, isFalse);
  }, timeout: _testTimeout);

  testWidgets('an elapsed timeout gives timedOut', (_) async {
    if (!await _cameraGranted()) return;

    final result = await AwsLiveness.start(
      LivenessRequest(
        sessionId: _unknownSessionId(),
        region: _region,
        credentialsProvider: _neverCompletes,
        timeout: const Duration(seconds: 5),
      ),
    );

    expect(_code(result), LivenessErrorCode.timedOut);
  }, timeout: _testTimeout);
}
