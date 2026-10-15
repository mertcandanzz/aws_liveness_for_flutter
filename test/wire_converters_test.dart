import 'package:aws_liveness_for_flutter/aws_liveness_for_flutter.dart';
import 'package:aws_liveness_for_flutter/src/messages.g.dart';
import 'package:aws_liveness_for_flutter/src/wire_converters.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<LivenessCredentials> _noCredentials() =>
    throw UnimplementedError('not used');

void main() {
  group('toStartRequestMessage', () {
    test('copies every field and converts the timeout to millis', () {
      const request = LivenessRequest(
        sessionId: 'session-1',
        region: 'eu-west-1',
        credentialsProvider: _noCredentials,
        challengeOptions: LivenessChallengeOptions(
          faceMovementCamera: LivenessCamera.back,
        ),
        showStartView: false,
        theme: LivenessTheme(mode: LivenessThemeMode.dark),
        credentialsTimeout: Duration(seconds: 7),
      );

      final message = toStartRequestMessage(request, attemptId: 42);

      expect(message.attemptId, 42);
      expect(message.sessionId, 'session-1');
      expect(message.region, 'eu-west-1');
      expect(message.faceMovementCamera, CameraMessage.back);
      expect(message.showStartView, isFalse);
      expect(message.theme.mode, ThemeModeMessage.dark);
      expect(message.credentialsTimeoutMillis, 7000);
    });
  });

  group('toThemeMessage', () {
    test('serializes colours as ARGB32 and keeps nulls', () {
      const theme = LivenessTheme(
        mode: LivenessThemeMode.light,
        light: LivenessColors(
          primary: Color(0xFF112233),
          onPrimary: Color(0x80FFFFFF),
          background: Color(0xFF000001),
          onBackground: Color(0xFF000002),
          surface: Color(0xFF000003),
          error: Color(0xFF000004),
          onError: Color(0xFF000005),
          errorContainer: Color(0xFF000006),
          onErrorContainer: Color(0xFF000007),
        ),
      );

      final message = toThemeMessage(theme);
      final light = message.light!;

      expect(message.mode, ThemeModeMessage.light);
      expect(message.dark, isNull);
      expect(light.primary, 0xFF112233);
      expect(light.onPrimary, 0x80FFFFFF);
      expect(light.background, 0xFF000001);
      expect(light.onBackground, 0xFF000002);
      expect(light.surface, 0xFF000003);
      expect(light.error, 0xFF000004);
      expect(light.onError, 0xFF000005);
      expect(light.errorContainer, 0xFF000006);
      expect(light.onErrorContainer, 0xFF000007);
    });

    test('leaves unset tokens null', () {
      final message = toThemeMessage(
        const LivenessTheme(dark: LivenessColors(primary: Color(0xFF0000FF))),
      );

      expect(message.mode, ThemeModeMessage.system);
      expect(message.dark!.primary, 0xFF0000FF);
      expect(message.dark!.surface, isNull);
    });
  });

  group('toCredentialsMessage', () {
    test('converts the expiration to epoch seconds', () {
      final message = toCredentialsMessage(
        LivenessCredentials(
          accessKeyId: 'a',
          secretAccessKey: 'b',
          sessionToken: 'c',
          expiration: DateTime.fromMillisecondsSinceEpoch(1700000000999),
        ),
      );

      expect(message.accessKeyId, 'a');
      expect(message.secretAccessKey, 'b');
      expect(message.sessionToken, 'c');
      expect(message.expirationEpochSeconds, 1700000000);
    });
  });

  group('toLivenessResult', () {
    LivenessResult convert(OutcomeMessage message) => toLivenessResult(
      message,
      sessionId: 's',
      platform: LivenessPlatform.android,
    );

    test('maps completed', () {
      final result = convert(
        OutcomeMessage(kind: OutcomeKindMessage.completed),
      );

      expect(result, isA<LivenessCompleted>());
      expect(result.sessionId, 's');
    });

    test('maps cancelled with its reason', () {
      final user = convert(
        OutcomeMessage(
          kind: OutcomeKindMessage.cancelled,
          cancelReason: CancelReasonMessage.user,
        ),
      );
      final app = convert(
        OutcomeMessage(
          kind: OutcomeKindMessage.cancelled,
          cancelReason: CancelReasonMessage.app,
        ),
      );

      expect((user as LivenessCancelled).reason, LivenessCancelReason.user);
      expect((app as LivenessCancelled).reason, LivenessCancelReason.app);
    });

    test('treats a cancel without reason as a user cancel', () {
      final result = convert(
        OutcomeMessage(kind: OutcomeKindMessage.cancelled),
      );

      expect((result as LivenessCancelled).reason, LivenessCancelReason.user);
    });

    test('maps failed with native details', () {
      final result = convert(
        OutcomeMessage(
          kind: OutcomeKindMessage.failed,
          errorCode: ErrorCodeMessage.throttled,
          nativeCode: 'PredictionsException/ThrottlingException',
          nativeMessage: 'Failed since the user made too many requests',
        ),
      );

      final error = (result as LivenessFailed).error;
      expect(error.code, LivenessErrorCode.throttled);
      expect(error.nativeDetails!.platform, LivenessPlatform.android);
      expect(
        error.nativeDetails!.code,
        'PredictionsException/ThrottlingException',
      );
      expect(error.nativeDetails!.message, startsWith('Failed since'));
    });

    test('omits native details when the native side sent none', () {
      final result = convert(
        OutcomeMessage(
          kind: OutcomeKindMessage.failed,
          errorCode: ErrorCodeMessage.timedOut,
        ),
      );

      expect((result as LivenessFailed).error.nativeDetails, isNull);
    });

    test('maps a failure without error code to unknown', () {
      final result = convert(OutcomeMessage(kind: OutcomeKindMessage.failed));

      expect((result as LivenessFailed).error.code, LivenessErrorCode.unknown);
    });
  });

  test('every ErrorCodeMessage maps to the code with the same name', () {
    for (final wire in ErrorCodeMessage.values) {
      expect(toErrorCode(wire).name, wire.name);
    }
  });

  test('toAvailability maps every reason', () {
    expect(
      toAvailability(AvailabilityMessage(isAvailable: true)).isAvailable,
      isTrue,
    );
    for (final reason in UnavailableReasonMessage.values) {
      final availability = toAvailability(
        AvailabilityMessage(isAvailable: false, reason: reason),
      );
      expect(availability.isAvailable, isFalse);
      expect(availability.reason!.name, reason.name);
    }
  });

  test('toPermissionStatus maps every status', () {
    for (final status in CameraPermissionStatusMessage.values) {
      expect(toPermissionStatus(status).name, status.name);
    }
  });

  group('channel failures', () {
    test('a missing plugin is reported as sdkUnavailable', () {
      expect(isPluginMissing(MissingPluginException()), isTrue);
      expect(isPluginMissing(PlatformException(code: 'channel-error')), isTrue);
      expect(isPluginMissing(PlatformException(code: 'other')), isFalse);
      expect(isPluginMissing(StateError('x')), isFalse);

      final error = toChannelError(
        MissingPluginException('no impl'),
        platform: LivenessPlatform.ios,
      );
      expect(error.code, LivenessErrorCode.sdkUnavailable);
    });

    test('other platform exceptions become unknown with details', () {
      final error = toChannelError(
        PlatformException(code: 'boom', message: 'bad'),
        platform: LivenessPlatform.android,
      );

      expect(error.code, LivenessErrorCode.unknown);
      expect(error.nativeDetails!.code, 'boom');
      expect(error.nativeDetails!.message, 'bad');
      expect(error.cause, isA<PlatformException>());
    });

    test('non-platform errors become unknown with the cause kept', () {
      final cause = StateError('codec');
      final error = toChannelError(cause, platform: LivenessPlatform.android);

      expect(error.code, LivenessErrorCode.unknown);
      expect(error.nativeDetails, isNull);
      expect(error.cause, same(cause));
    });
  });
}
