import 'dart:async';

import 'package:aws_liveness_for_flutter/aws_liveness_for_flutter.dart';
import 'package:aws_liveness_for_flutter/src/aws_liveness.dart';
import 'package:aws_liveness_for_flutter/src/liveness_controller.dart';
import 'package:aws_liveness_for_flutter/src/messages.g.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_host_api.dart';

LivenessRequest _request() => LivenessRequest(
  sessionId: 'session-1',
  region: 'eu-west-1',
  credentialsProvider: () async => LivenessCredentials(
    accessKeyId: 'ASIAEXAMPLE',
    secretAccessKey: 'secret',
    sessionToken: 'token',
    expiration: DateTime.now().add(const Duration(hours: 1)),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => debugLivenessController = null);

  group('with a fake host', () {
    late FakeHostApi host;

    setUp(() {
      host = FakeHostApi();
      debugLivenessController = LivenessController(
        hostApi: host,
        platform: LivenessPlatform.ios,
      );
    });

    test('start, isActive and cancel delegate to the controller', () async {
      final future = AwsLiveness.start(_request());
      expect(AwsLiveness.isActive, isTrue);

      await AwsLiveness.cancel();
      host.reply(
        OutcomeMessage(
          kind: OutcomeKindMessage.cancelled,
          cancelReason: CancelReasonMessage.app,
        ),
      );

      expect(await future, isA<LivenessCancelled>());
      expect(AwsLiveness.isActive, isFalse);
      expect(host.cancelCalls.single.$2, CancelRequestReasonMessage.app);
    });

    test('checkAvailability converts the native report', () async {
      host.availability = AvailabilityMessage(
        isAvailable: false,
        reason: UnavailableReasonMessage.missingCameraUsageDescription,
      );

      final availability = await AwsLiveness.checkAvailability();

      expect(availability.isAvailable, isFalse);
      expect(
        availability.reason,
        LivenessUnavailableReason.missingCameraUsageDescription,
      );
    });

    test('checkAvailability rethrows unexpected channel errors', () {
      host.availabilityError = PlatformException(code: 'boom');

      expect(
        AwsLiveness.checkAvailability(),
        throwsA(isA<PlatformException>()),
      );
    });

    test('permission helpers convert native statuses', () async {
      host.permissionStatus = CameraPermissionStatusMessage.restricted;
      host.requestedPermission =
          CameraPermissionStatusMessage.permanentlyDenied;

      expect(
        await AwsLiveness.getCameraPermissionStatus(),
        CameraPermissionStatus.restricted,
      );
      expect(
        await AwsLiveness.requestCameraPermission(),
        CameraPermissionStatus.permanentlyDenied,
      );
    });

    test('openAppSettings returns whether the page opened', () async {
      host.settingsOpened = false;

      expect(await AwsLiveness.openAppSettings(), isFalse);
    });
  });

  group('without a native implementation', () {
    test('checkAvailability reports sdkUnavailable', () async {
      final availability = await AwsLiveness.checkAvailability();

      expect(availability.isAvailable, isFalse);
      expect(availability.reason, LivenessUnavailableReason.sdkUnavailable);
    });

    test('start completes with sdkUnavailable', () async {
      final result = await AwsLiveness.start(_request());

      expect(
        (result as LivenessFailed).error.code,
        LivenessErrorCode.sdkUnavailable,
      );
    });

    test('native credential requests reach the Dart controller', () async {
      // Creates the default controller, which registers the Flutter API.
      await AwsLiveness.checkAvailability();
      const channel =
          'dev.flutter.pigeon.aws_liveness_for_flutter.'
          'LivenessFlutterApi.fetchCredentials';
      final reply = Completer<ByteData?>();

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel,
            LivenessFlutterApi.pigeonChannelCodec.encodeMessage(<Object?>[7]),
            reply.complete,
          );

      final decoded =
          LivenessFlutterApi.pigeonChannelCodec.decodeMessage(
                await reply.future,
              )
              as List<Object?>;
      final result = decoded.single! as CredentialsResultMessage;
      expect(result.failure, CredentialsFailureMessage.staleAttempt);
    });
  });

  test('knownSupportedRegions lists the documented regions', () {
    expect(AwsLiveness.knownSupportedRegions, [
      'us-east-1',
      'us-west-2',
      'ap-south-1',
      'ap-northeast-1',
      'eu-west-1',
      'sa-east-1',
      'ap-southeast-5',
      'ap-southeast-7',
    ]);
    expect(AwsLiveness.knownSupportedRegions, isNot(contains('eu-central-1')));
  });
}
