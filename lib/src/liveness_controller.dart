import 'dart:async';

import 'package:flutter/foundation.dart';

import 'messages.g.dart';
import 'models/error.dart';
import 'models/request.dart';
import 'models/result.dart';
import 'wire_converters.dart';

/// How long Dart waits for the native reply after asking it to end an
/// attempt (timeout or app cancel) before completing on its own (design §6.3).
const nativeReplyGrace = Duration(seconds: 5);

final _regionPattern = RegExp(r'^[a-z]{2}(-[a-z]+)+-\d+$');

/// Runs liveness attempts for one isolate: validation, attempt ids,
/// exactly-once completion, timeout, app cancel and credential requests.
///
/// Internal: the public entry point is `AwsLiveness`.
class LivenessController implements LivenessFlutterApi {
  /// Creates a controller. [now] is injectable for tests.
  LivenessController({
    required LivenessHostApi hostApi,
    required LivenessPlatform platform,
    DateTime Function() now = DateTime.now,
  }) : _hostApi = hostApi,
       _platform = platform,
       _now = now;

  /// Creates a controller for the current platform and registers it to
  /// answer native credential requests.
  factory LivenessController.forCurrentPlatform() {
    final controller = LivenessController(
      hostApi: LivenessHostApi(),
      platform: defaultTargetPlatform == TargetPlatform.iOS
          ? LivenessPlatform.ios
          : LivenessPlatform.android,
    );
    LivenessFlutterApi.setUp(controller);
    return controller;
  }

  final LivenessHostApi _hostApi;
  final LivenessPlatform _platform;
  final DateTime Function() _now;

  int _nextAttemptId = 1;
  _Attempt? _active;

  /// The platform this controller reports in native details.
  LivenessPlatform get platform => _platform;

  /// The native host API.
  LivenessHostApi get hostApi => _hostApi;

  /// True from a [start] call until its future completes.
  bool get isActive => _active != null;

  /// Starts an attempt. Throws [ArgumentError] for invalid input and
  /// [StateError] while another attempt is active; the returned future never
  /// completes with an error.
  Future<LivenessResult> start(LivenessRequest request) {
    _validate(request);
    if (_active != null) {
      throw StateError(
        'A liveness attempt is already active. Wait for its result or call '
        'AwsLiveness.cancel() first.',
      );
    }
    final attempt = _Attempt(_nextAttemptId++, request);
    _active = attempt;

    final timeout = request.timeout;
    if (timeout != null) {
      attempt.timeoutTimer = Timer(timeout, () => _onTimeout(attempt));
    }

    Future.sync(
      () =>
          _hostApi.start(toStartRequestMessage(request, attemptId: attempt.id)),
    ).then(
      (outcome) => _finish(attempt, _toResult(attempt, outcome)),
      onError: (Object error) => _finish(
        attempt,
        LivenessFailed(
          sessionId: request.sessionId,
          error: toChannelError(error, platform: _platform),
        ),
      ),
    );
    return attempt.completer.future;
  }

  /// Ends the active attempt with an app cancel. No-op when idle; never
  /// throws.
  Future<void> cancel() async {
    final attempt = _active;
    if (attempt == null) return;
    await _endFromDart(
      attempt,
      CancelRequestReasonMessage.app,
      LivenessCancelled(
        sessionId: attempt.request.sessionId,
        reason: LivenessCancelReason.app,
      ),
    );
  }

  @override
  Future<CredentialsResultMessage> fetchCredentials(int attemptId) async {
    final attempt = _active;
    if (attempt == null || attempt.id != attemptId) {
      return _credentialsFailure(CredentialsFailureMessage.staleAttempt);
    }

    final _CredentialsOutcome outcome = await _callProvider(attempt.request);
    if (!identical(_active, attempt)) {
      return _credentialsFailure(CredentialsFailureMessage.staleAttempt);
    }
    final credentials = outcome.credentials;
    if (credentials != null) {
      return CredentialsResultMessage(
        credentials: toCredentialsMessage(credentials),
      );
    }
    attempt.credentialsFailure = outcome;
    return _credentialsFailure(outcome.failure!);
  }

  Future<_CredentialsOutcome> _callProvider(LivenessRequest request) async {
    try {
      final credentials = await Future.sync(request.credentialsProvider)
          .timeout(
            request.credentialsTimeout,
            onTimeout: () => throw const _ProviderTimeout(),
          );
      if (!_isValid(credentials)) {
        return const _CredentialsOutcome.failed(
          CredentialsFailureMessage.invalid,
          'The credentials provider returned empty or expired credentials.',
        );
      }
      return _CredentialsOutcome.ok(credentials);
    } on _ProviderTimeout {
      return const _CredentialsOutcome.failed(
        CredentialsFailureMessage.timedOut,
        'The credentials provider did not return within credentialsTimeout.',
      );
    } catch (error) {
      return _CredentialsOutcome.failed(
        CredentialsFailureMessage.providerError,
        'The credentials provider threw an error.',
        cause: error,
      );
    }
  }

  bool _isValid(LivenessCredentials credentials) =>
      credentials.accessKeyId.trim().isNotEmpty &&
      credentials.secretAccessKey.trim().isNotEmpty &&
      credentials.sessionToken.trim().isNotEmpty &&
      credentials.expiration.isAfter(_now());

  void _onTimeout(_Attempt attempt) {
    _endFromDart(
      attempt,
      CancelRequestReasonMessage.timeout,
      LivenessFailed(
        sessionId: attempt.request.sessionId,
        error: LivenessError(LivenessErrorCode.timedOut),
      ),
    );
  }

  /// Asks native to end [attempt] and completes with [fallback] if native
  /// does not reply within [nativeReplyGrace].
  Future<void> _endFromDart(
    _Attempt attempt,
    CancelRequestReasonMessage reason,
    LivenessResult fallback,
  ) async {
    if (attempt.completer.isCompleted) return;
    attempt.graceTimer ??= Timer(
      nativeReplyGrace,
      () => _finish(attempt, fallback),
    );
    try {
      await _hostApi.cancel(attempt.id, reason);
    } catch (_) {
      // The grace timer delivers the result if native cannot.
    }
  }

  LivenessResult _toResult(_Attempt attempt, OutcomeMessage outcome) {
    final result = toLivenessResult(
      outcome,
      sessionId: attempt.request.sessionId,
      platform: _platform,
    );
    final credentialsFailure = attempt.credentialsFailure;
    // Design §4.2 rule 3: our own credentials failure explains any SDK error.
    if (result is LivenessFailed && credentialsFailure != null) {
      return LivenessFailed(
        sessionId: result.sessionId,
        error: LivenessError(
          LivenessErrorCode.credentialsUnavailable,
          message: credentialsFailure.message,
          nativeDetails: result.error.nativeDetails,
          cause: credentialsFailure.cause,
        ),
      );
    }
    return result;
  }

  void _finish(_Attempt attempt, LivenessResult result) {
    if (attempt.completer.isCompleted) return;
    attempt.timeoutTimer?.cancel();
    attempt.graceTimer?.cancel();
    if (identical(_active, attempt)) _active = null;
    attempt.completer.complete(result);
  }

  static void _validate(LivenessRequest request) {
    if (request.sessionId.trim().isEmpty) {
      throw ArgumentError.value(
        request.sessionId,
        'sessionId',
        'must not be blank',
      );
    }
    if (!_regionPattern.hasMatch(request.region)) {
      throw ArgumentError.value(
        request.region,
        'region',
        'must be an AWS region code such as eu-west-1',
      );
    }
    final timeout = request.timeout;
    if (timeout != null && timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    if (request.credentialsTimeout <= Duration.zero) {
      throw ArgumentError.value(
        request.credentialsTimeout,
        'credentialsTimeout',
        'must be positive',
      );
    }
  }

  static CredentialsResultMessage _credentialsFailure(
    CredentialsFailureMessage failure,
  ) => CredentialsResultMessage(failure: failure);
}

class _Attempt {
  _Attempt(this.id, this.request);

  final int id;
  final LivenessRequest request;
  final Completer<LivenessResult> completer = Completer<LivenessResult>();
  Timer? timeoutTimer;
  Timer? graceTimer;
  _CredentialsOutcome? credentialsFailure;
}

class _CredentialsOutcome {
  const _CredentialsOutcome.ok(LivenessCredentials this.credentials)
    : failure = null,
      message = null,
      cause = null;

  const _CredentialsOutcome.failed(
    CredentialsFailureMessage this.failure,
    String this.message, {
    this.cause,
  }) : credentials = null;

  final LivenessCredentials? credentials;
  final CredentialsFailureMessage? failure;
  final String? message;
  final Object? cause;
}

class _ProviderTimeout implements Exception {
  const _ProviderTimeout();
}
