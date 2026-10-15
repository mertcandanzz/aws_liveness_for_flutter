import 'package:aws_liveness_for_flutter/aws_liveness_for_flutter.dart';

import 'backend_client.dart';

/// What the result card shows.
sealed class Outcome {
  const Outcome();
}

/// Nothing has run yet.
class Idle extends Outcome {
  const Idle();
}

/// Steps of a running check.
enum RunStep { creatingSession, checking, readingResult }

/// A check is running.
class Running extends Outcome {
  const Running(this.step);

  final RunStep step;
}

/// The backend decided the finished check.
class Decided extends Outcome {
  const Decided(this.decision);

  final BackendDecision decision;
}

/// The check was cancelled.
class Cancelled extends Outcome {
  const Cancelled(this.reason);

  final LivenessCancelReason reason;
}

/// The plugin reported a failure.
class Failed extends Outcome {
  const Failed(this.error);

  final LivenessError error;
}

/// A backend call failed.
class BackendFailed extends Outcome {
  const BackendFailed(this.error);

  final BackendException error;
}
