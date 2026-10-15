import 'error.dart';

/// Outcome of one liveness attempt.
///
/// The plugin never decides whether the user is live. After
/// [LivenessCompleted], ask your backend for `GetFaceLivenessSessionResults`.
sealed class LivenessResult {
  /// Base constructor for the result subtypes.
  const LivenessResult({required this.sessionId});

  /// The session id of the attempt.
  final String sessionId;
}

/// The check finished and the video was streamed to Rekognition.
final class LivenessCompleted extends LivenessResult {
  /// Creates a completed result.
  const LivenessCompleted({required super.sessionId});

  @override
  String toString() => 'LivenessCompleted(sessionId: $sessionId)';
}

/// The attempt was cancelled before it finished.
final class LivenessCancelled extends LivenessResult {
  /// Creates a cancelled result.
  const LivenessCancelled({required super.sessionId, required this.reason});

  /// Who cancelled the attempt.
  final LivenessCancelReason reason;

  @override
  String toString() =>
      'LivenessCancelled(sessionId: $sessionId, reason: ${reason.name})';
}

/// The attempt failed; see [error].
final class LivenessFailed extends LivenessResult {
  /// Creates a failed result.
  const LivenessFailed({required super.sessionId, required this.error});

  /// What went wrong.
  final LivenessError error;

  @override
  String toString() => 'LivenessFailed(sessionId: $sessionId, error: $error)';
}

/// Who cancelled an attempt.
enum LivenessCancelReason {
  /// The user closed the liveness screen.
  user,

  /// The app called `AwsLiveness.cancel`.
  app,
}
