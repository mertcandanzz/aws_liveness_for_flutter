import 'dart:async';

import 'package:aws_liveness_for_flutter/src/messages.g.dart';

/// In-memory [LivenessHostApi] that records calls and lets tests reply.
class FakeHostApi extends LivenessHostApi {
  final List<StartRequestMessage> startCalls = [];
  final List<(int, CancelRequestReasonMessage)> cancelCalls = [];
  Completer<OutcomeMessage>? _pendingStart;

  /// When set, `start` fails with this error instead of waiting for a reply.
  Object? startError;

  /// When set, `cancel` throws this error.
  Object? cancelError;

  /// When true, `cancel` returns a future that never completes.
  bool cancelHangs = false;

  AvailabilityMessage availability = AvailabilityMessage(isAvailable: true);
  Object? availabilityError;
  CameraPermissionStatusMessage permissionStatus =
      CameraPermissionStatusMessage.notDetermined;
  CameraPermissionStatusMessage requestedPermission =
      CameraPermissionStatusMessage.granted;
  bool settingsOpened = true;

  /// Completes the pending `start` call.
  void reply(OutcomeMessage outcome) => _pendingStart!.complete(outcome);

  /// Completes the pending `start` call with a failure code.
  void replyFailed(ErrorCodeMessage code) =>
      reply(OutcomeMessage(kind: OutcomeKindMessage.failed, errorCode: code));

  @override
  Future<OutcomeMessage> start(StartRequestMessage request) {
    startCalls.add(request);
    final error = startError;
    if (error != null) return Future.error(error);
    final pending = Completer<OutcomeMessage>();
    _pendingStart = pending;
    return pending.future;
  }

  @override
  Future<void> cancel(int attemptId, CancelRequestReasonMessage reason) async {
    cancelCalls.add((attemptId, reason));
    if (cancelHangs) return Completer<void>().future;
    final error = cancelError;
    if (error != null) throw error;
  }

  @override
  Future<AvailabilityMessage> checkAvailability() async {
    final error = availabilityError;
    if (error != null) throw error;
    return availability;
  }

  @override
  Future<CameraPermissionStatusMessage> getCameraPermissionStatus() async =>
      permissionStatus;

  @override
  Future<CameraPermissionStatusMessage> requestCameraPermission() async =>
      requestedPermission;

  @override
  Future<bool> openAppSettings() async => settingsOpened;
}
