import 'dart:async';

import 'package:aws_liveness_for_flutter/aws_liveness_for_flutter.dart';
import 'package:aws_liveness_for_flutter/src/liveness_controller.dart';
import 'package:aws_liveness_for_flutter/src/messages.g.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_host_api.dart';

final _now = DateTime.utc(2026, 10, 15, 12);

LivenessCredentials _credentials({
  String accessKeyId = 'ASIAEXAMPLE',
  DateTime? expiration,
}) => LivenessCredentials(
  accessKeyId: accessKeyId,
  secretAccessKey: 'secret',
  sessionToken: 'token',
  expiration: expiration ?? _now.add(const Duration(hours: 1)),
);

LivenessRequest _request({
  String sessionId = 'session-1',
  String region = 'eu-west-1',
  LivenessCredentialsProvider? provider,
  Duration? timeout,
  Duration credentialsTimeout = const Duration(seconds: 15),
}) => LivenessRequest(
  sessionId: sessionId,
  region: region,
  credentialsProvider: provider ?? () async => _credentials(),
  timeout: timeout,
  credentialsTimeout: credentialsTimeout,
);

OutcomeMessage _completed() =>
    OutcomeMessage(kind: OutcomeKindMessage.completed);

OutcomeMessage _cancelled(CancelReasonMessage reason) =>
    OutcomeMessage(kind: OutcomeKindMessage.cancelled, cancelReason: reason);

void main() {
  late FakeHostApi host;
  late LivenessController controller;

  setUp(() {
    host = FakeHostApi();
    controller = LivenessController(
      hostApi: host,
      platform: LivenessPlatform.android,
      now: () => _now,
    );
  });

  group('start', () {
    test('sends the request and completes with the native outcome', () async {
      final future = controller.start(_request());
      await pumpEventQueue();

      expect(host.startCalls.single.sessionId, 'session-1');
      expect(host.startCalls.single.region, 'eu-west-1');

      host.reply(_completed());
      final result = await future;

      expect(result, isA<LivenessCompleted>());
      expect(result.sessionId, 'session-1');
    });

    test('uses an increasing attempt id per start', () async {
      final first = controller.start(_request());
      host.reply(_completed());
      await first;
      final second = controller.start(_request());
      host.reply(_completed());
      await second;

      expect(host.startCalls[1].attemptId, host.startCalls[0].attemptId + 1);
    });

    test('isActive is true until the result is delivered', () async {
      expect(controller.isActive, isFalse);

      final future = controller.start(_request());
      expect(controller.isActive, isTrue);

      host.reply(_completed());
      await future;
      expect(controller.isActive, isFalse);
    });
  });

  group('misuse', () {
    final invalid = <String, LivenessRequest>{
      'blank sessionId': _request(sessionId: '  '),
      'empty sessionId': _request(sessionId: ''),
      'upper-case region': _request(region: 'EU-WEST-1'),
      'region without dashes': _request(region: 'euwest1'),
      'empty region': _request(region: ''),
      'zero timeout': _request(timeout: Duration.zero),
      'negative timeout': _request(timeout: const Duration(seconds: -1)),
      'zero credentialsTimeout': _request(credentialsTimeout: Duration.zero),
    };

    invalid.forEach((name, request) {
      test('throws ArgumentError synchronously for $name', () {
        expect(() => controller.start(request), throwsArgumentError);
        expect(host.startCalls, isEmpty);
        expect(controller.isActive, isFalse);
      });
    });

    for (final region in ['us-east-1', 'ap-southeast-5', 'us-gov-west-1']) {
      test('accepts region $region', () {
        expect(
          () => controller.start(_request(region: region)),
          returnsNormally,
        );
      });
    }

    test('throws StateError for a concurrent start', () async {
      final first = controller.start(_request());

      expect(() => controller.start(_request()), throwsStateError);
      expect(host.startCalls, hasLength(1));

      host.reply(_completed());
      await first;
      expect(() => controller.start(_request()), returnsNormally);
    });
  });

  group('channel failures', () {
    test('a missing plugin completes with sdkUnavailable', () async {
      host.startError = PlatformException(code: 'channel-error');

      final result = await controller.start(_request());

      expect(
        (result as LivenessFailed).error.code,
        LivenessErrorCode.sdkUnavailable,
      );
      expect(controller.isActive, isFalse);
    });

    test('other platform exceptions complete with unknown', () async {
      host.startError = PlatformException(code: 'boom', message: 'bad');

      final result = await controller.start(_request());

      final error = (result as LivenessFailed).error;
      expect(error.code, LivenessErrorCode.unknown);
      expect(error.nativeDetails!.code, 'boom');
    });
  });

  group('timeout', () {
    test('asks native to cancel with the timeout reason', () {
      fakeAsync((async) {
        LivenessResult? result;
        controller
            .start(_request(timeout: const Duration(seconds: 10)))
            .then((r) => result = r);

        async.elapse(const Duration(seconds: 9));
        expect(host.cancelCalls, isEmpty);

        async.elapse(const Duration(seconds: 1));
        final attemptId = host.startCalls.single.attemptId;
        expect(host.cancelCalls, [
          (attemptId, CancelRequestReasonMessage.timeout),
        ]);

        host.replyFailed(ErrorCodeMessage.timedOut);
        async.flushMicrotasks();
        expect(
          (result! as LivenessFailed).error.code,
          LivenessErrorCode.timedOut,
        );
      });
    });

    test('completes with timedOut after a 5 second grace period', () {
      fakeAsync((async) {
        LivenessResult? result;
        controller
            .start(_request(timeout: const Duration(seconds: 10)))
            .then((r) => result = r);

        async.elapse(const Duration(seconds: 14));
        expect(result, isNull);

        async.elapse(const Duration(seconds: 1));
        expect(
          (result! as LivenessFailed).error.code,
          LivenessErrorCode.timedOut,
        );
        expect(controller.isActive, isFalse);

        // A late native reply is ignored.
        host.reply(_completed());
        async.flushMicrotasks();
        expect(result, isA<LivenessFailed>());
      });
    });

    test('a finished attempt cancels its timer', () {
      fakeAsync((async) {
        controller.start(_request(timeout: const Duration(seconds: 10)));
        host.reply(_completed());
        async.flushMicrotasks();

        async.elapse(const Duration(minutes: 1));
        expect(host.cancelCalls, isEmpty);
      });
    });

    test('no timeout means no plugin-side timer', () {
      fakeAsync((async) {
        controller.start(_request());

        async.elapse(const Duration(hours: 1));
        expect(host.cancelCalls, isEmpty);
        expect(controller.isActive, isTrue);
      });
    });
  });

  group('cancel', () {
    test('asks native to cancel the active attempt', () async {
      final future = controller.start(_request());

      await controller.cancel();
      host.reply(_cancelled(CancelReasonMessage.app));
      final result = await future;

      expect(host.cancelCalls, [
        (host.startCalls.single.attemptId, CancelRequestReasonMessage.app),
      ]);
      expect((result as LivenessCancelled).reason, LivenessCancelReason.app);
    });

    test('completes as app cancel when native stays silent', () {
      fakeAsync((async) {
        LivenessResult? result;
        controller.start(_request()).then((r) => result = r);

        controller.cancel();
        async.elapse(const Duration(seconds: 5));

        expect((result! as LivenessCancelled).reason, LivenessCancelReason.app);
      });
    });

    test('is a no-op when idle', () async {
      await controller.cancel();

      expect(host.cancelCalls, isEmpty);
    });

    test('never throws when the native cancel fails', () async {
      host.cancelError = PlatformException(code: 'boom');
      controller.start(_request());

      await expectLater(controller.cancel(), completes);
    });
  });

  group('fetchCredentials', () {
    test('returns the provider credentials for the active attempt', () async {
      controller.start(_request());

      final reply = await controller.fetchCredentials(
        host.startCalls.single.attemptId,
      );

      expect(reply.failure, isNull);
      expect(reply.credentials!.accessKeyId, 'ASIAEXAMPLE');
      expect(reply.credentials!.sessionToken, 'token');
    });

    test('reports staleAttempt when idle or for another attempt', () async {
      expect(
        (await controller.fetchCredentials(1)).failure,
        CredentialsFailureMessage.staleAttempt,
      );

      controller.start(_request());
      final reply = await controller.fetchCredentials(
        host.startCalls.single.attemptId + 1,
      );

      expect(reply.credentials, isNull);
      expect(reply.failure, CredentialsFailureMessage.staleAttempt);
    });

    test('reports staleAttempt when the attempt ended meanwhile', () async {
      final pending = Completer<LivenessCredentials>();
      final future = controller.start(_request(provider: () => pending.future));
      final reply = controller.fetchCredentials(
        host.startCalls.single.attemptId,
      );

      host.reply(_completed());
      await future;
      pending.complete(_credentials());

      expect((await reply).failure, CredentialsFailureMessage.staleAttempt);
    });

    test(
      'a throwing provider fails with providerError and keeps the cause',
      () async {
        final thrown = Exception('backend down');
        final future = controller.start(
          _request(provider: () async => throw thrown),
        );

        final reply = await controller.fetchCredentials(
          host.startCalls.single.attemptId,
        );
        expect(reply.credentials, isNull);
        expect(reply.failure, CredentialsFailureMessage.providerError);

        host.replyFailed(ErrorCodeMessage.credentialsUnavailable);
        final error = ((await future) as LivenessFailed).error;
        expect(error.code, LivenessErrorCode.credentialsUnavailable);
        expect(error.cause, same(thrown));
      },
    );

    test('a synchronously throwing provider is handled', () async {
      controller.start(_request(provider: () => throw StateError('sync')));

      final reply = await controller.fetchCredentials(
        host.startCalls.single.attemptId,
      );

      expect(reply.failure, CredentialsFailureMessage.providerError);
    });

    test('a slow provider fails with timedOut', () {
      fakeAsync((async) {
        controller.start(
          _request(
            provider: () => Completer<LivenessCredentials>().future,
            credentialsTimeout: const Duration(seconds: 3),
          ),
        );
        CredentialsResultMessage? reply;
        controller
            .fetchCredentials(host.startCalls.single.attemptId)
            .then((r) => reply = r);

        async.elapse(const Duration(seconds: 3));

        expect(reply!.failure, CredentialsFailureMessage.timedOut);
      });
    });

    final invalidCredentials = <String, LivenessCredentials>{
      'empty access key': _credentials(accessKeyId: ''),
      'expired': _credentials(expiration: _now),
      'expired in the past': _credentials(
        expiration: _now.subtract(const Duration(minutes: 1)),
      ),
    };

    invalidCredentials.forEach((name, credentials) {
      test('rejects $name credentials as invalid', () async {
        controller.start(_request(provider: () async => credentials));

        final reply = await controller.fetchCredentials(
          host.startCalls.single.attemptId,
        );

        expect(reply.credentials, isNull);
        expect(reply.failure, CredentialsFailureMessage.invalid);
      });
    });

    test('a credentials failure takes precedence over the SDK error', () async {
      final future = controller.start(
        _request(provider: () async => _credentials(accessKeyId: ' ')),
      );
      await controller.fetchCredentials(host.startCalls.single.attemptId);

      host.reply(
        OutcomeMessage(
          kind: OutcomeKindMessage.failed,
          errorCode: ErrorCodeMessage.sessionInterrupted,
          nativeCode: 'socketClosed',
        ),
      );
      final error = ((await future) as LivenessFailed).error;

      expect(error.code, LivenessErrorCode.credentialsUnavailable);
      expect(error.nativeDetails!.code, 'socketClosed');
    });

    test('a user cancel still wins over a credentials failure', () async {
      final future = controller.start(
        _request(provider: () async => throw Exception('x')),
      );
      await controller.fetchCredentials(host.startCalls.single.attemptId);

      host.reply(_cancelled(CancelReasonMessage.user));

      expect(await future, isA<LivenessCancelled>());
    });
  });
}
