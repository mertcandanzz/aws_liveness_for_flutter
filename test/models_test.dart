import 'package:aws_liveness_for_flutter/aws_liveness_for_flutter.dart';
import 'package:aws_liveness_for_flutter/src/messages.g.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LivenessCredentials', () {
    test('toString never reveals secrets', () {
      final credentials = LivenessCredentials(
        accessKeyId: 'ASIAEXAMPLEKEY',
        secretAccessKey: 'secret-value',
        sessionToken: 'token-value',
        expiration: DateTime.utc(2030),
      );

      final text = credentials.toString();

      expect(text, 'LivenessCredentials(<redacted>)');
      expect(text, isNot(contains('ASIA')));
      expect(text, isNot(contains('secret')));
      expect(text, isNot(contains('token')));
    });
  });

  group('LivenessErrorCode', () {
    test('matches ErrorCodeMessage names in the same order', () {
      expect(
        LivenessErrorCode.values.map((code) => code.name).toList(),
        ErrorCodeMessage.values.map((code) => code.name).toList(),
      );
    });

    test('every code has a message and a recovery suggestion', () {
      for (final code in LivenessErrorCode.values) {
        expect(code.message.trim(), isNotEmpty, reason: code.name);
        expect(code.recoverySuggestion.trim(), isNotEmpty, reason: code.name);
      }
    });

    test('category and isRetryable match the design table', () {
      const c = LivenessErrorCategory.values;
      final snapshot = {
        for (final code in LivenessErrorCode.values)
          code.name: (code.category, code.isRetryable),
      };

      expect(snapshot, {
        'cameraPermissionDenied': (c[0], true),
        'cameraPermissionPermanentlyDenied': (c[0], false),
        'credentialsUnavailable': (c[1], true),
        'accessDenied': (c[1], false),
        'invalidSignature': (c[1], true),
        'sessionNotFound': (c[2], true),
        'invalidRegion': (c[2], false),
        'validation': (c[2], false),
        'unsupportedChallenge': (c[2], false),
        'sdkUnavailable': (c[2], false),
        'missingCameraUsageDescription': (c[2], false),
        'throttled': (c[3], true),
        'serviceUnavailable': (c[3], true),
        'internalServerError': (c[3], true),
        'sessionInterrupted': (c[4], true),
        'faceTooClose': (c[4], true),
        'multipleFaces': (c[4], true),
        'noFaceDetected': (c[4], true),
        'cameraUnavailable': (c[5], true),
        'videoEncodingFailed': (c[5], true),
        'presenterUnavailable': (c[5], true),
        'alreadyActive': (c[5], true),
        'timedOut': (c[6], true),
        'sessionTimedOut': (c[6], true),
        'faceFitTimedOut': (c[6], true),
        'unknown': (c[7], true),
      });
    });

    test('categories are declared in the documented order', () {
      expect(LivenessErrorCategory.values.map((c) => c.name), [
        'permission',
        'credentials',
        'configuration',
        'service',
        'interrupted',
        'device',
        'timeout',
        'unknown',
      ]);
    });
  });

  group('LivenessError', () {
    test('takes category, retryability and text from its code', () {
      final error = LivenessError(LivenessErrorCode.throttled);

      expect(error.category, LivenessErrorCategory.service);
      expect(error.isRetryable, isTrue);
      expect(error.message, LivenessErrorCode.throttled.message);
      expect(
        error.recoverySuggestion,
        LivenessErrorCode.throttled.recoverySuggestion,
      );
      expect(error.nativeDetails, isNull);
      expect(error.cause, isNull);
    });

    test('accepts a more specific message', () {
      final error = LivenessError(
        LivenessErrorCode.credentialsUnavailable,
        message: 'The credentials provider timed out.',
      );

      expect(error.message, 'The credentials provider timed out.');
    });

    test('toString shows code and native details but not the cause', () {
      final error = LivenessError(
        LivenessErrorCode.unknown,
        nativeDetails: const LivenessNativeDetails(
          platform: LivenessPlatform.ios,
          code: 'socketClosed',
          message: 'closed',
        ),
        cause: 'provider-secret-detail',
      );

      final text = error.toString();

      expect(text, contains('unknown'));
      expect(text, contains('socketClosed'));
      expect(text, isNot(contains('provider-secret-detail')));
    });
  });

  group('LivenessResult', () {
    test('subtypes expose their session id and payload', () {
      const completed = LivenessCompleted(sessionId: 's1');
      const cancelled = LivenessCancelled(
        sessionId: 's2',
        reason: LivenessCancelReason.app,
      );
      final failed = LivenessFailed(
        sessionId: 's3',
        error: LivenessError(LivenessErrorCode.timedOut),
      );

      expect(completed.sessionId, 's1');
      expect(cancelled.reason, LivenessCancelReason.app);
      expect(failed.error.code, LivenessErrorCode.timedOut);
      expect(completed.toString(), 'LivenessCompleted(sessionId: s1)');
      expect(cancelled.toString(), contains('app'));
      expect(failed.toString(), contains('timedOut'));
    });
  });

  group('LivenessAvailability', () {
    test('toString describes the state', () {
      const available = LivenessAvailability(isAvailable: true);
      const unavailable = LivenessAvailability(
        isAvailable: false,
        reason: LivenessUnavailableReason.noCamera,
      );

      expect(available.reason, isNull);
      expect(available.toString(), contains('true'));
      expect(unavailable.toString(), contains('noCamera'));
    });
  });
}
