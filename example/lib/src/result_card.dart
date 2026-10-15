import 'package:aws_liveness_for_flutter/aws_liveness_for_flutter.dart';
import 'package:flutter/material.dart';

import 'outcome.dart';
import 'strings.dart';

/// Shows the latest [Outcome] with a "Try again" action.
class ResultCard extends StatelessWidget {
  const ResultCard({
    super.key,
    required this.outcome,
    required this.strings,
    required this.onTryAgain,
    required this.onOpenSettings,
  });

  final Outcome outcome;
  final Strings strings;

  /// Starts a new attempt; always creates a new session.
  final VoidCallback? onTryAgain;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final outcome = this.outcome;
    if (outcome is Idle) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final (
      Color color,
      IconData icon,
      String title,
      List<Widget> body,
    ) = switch (outcome) {
      Idle() => throw StateError('handled above'),
      Running(:final step) => (
        theme.colorScheme.secondaryContainer,
        Icons.hourglass_top,
        switch (step) {
          RunStep.creatingSession => strings.creatingSession,
          RunStep.checking => strings.checking,
          RunStep.readingResult => strings.readingResult,
        },
        const [LinearProgressIndicator()],
      ),
      Decided(:final decision) => (
        decision.isLive
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.errorContainer,
        decision.isLive ? Icons.verified_user : Icons.gpp_bad,
        decision.isLive ? strings.live : strings.notLive,
        [
          _Row(strings.status, decision.status),
          _Row(
            strings.confidence,
            decision.confidence?.toStringAsFixed(2) ?? '—',
          ),
          Text(strings.decidedByBackend, style: theme.textTheme.bodySmall),
        ],
      ),
      Cancelled(:final reason) => (
        theme.colorScheme.surfaceContainerHighest,
        Icons.cancel_outlined,
        '${strings.cancelled} '
            '(${reason == LivenessCancelReason.user ? strings.byUser : strings.byApp})',
        const <Widget>[],
      ),
      Failed(:final error) => (
        theme.colorScheme.errorContainer,
        Icons.error_outline,
        '${strings.failed}: ${error.code.name}',
        [
          _Row(strings.category, error.category.name),
          _Row(strings.retryable, error.isRetryable ? strings.yes : strings.no),
          _Row(strings.recovery, error.recoverySuggestion),
          if (error.nativeDetails case final details?)
            _Row(
              strings.nativeDetails,
              '${details.platform.name} · ${details.code ?? '—'}'
              '${details.message == null ? '' : '\n${details.message}'}',
            ),
          if (error.code == LivenessErrorCode.cameraPermissionPermanentlyDenied)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings),
                label: Text(strings.openSettings),
              ),
            ),
        ],
      ),
      BackendFailed(:final error) => (
        theme.colorScheme.errorContainer,
        Icons.cloud_off,
        '${strings.backendError}: ${error.code}',
        [
          if (error.statusCode case final status?)
            _Row('HTTP', status.toString()),
        ],
      ),
    };

    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Row(
              spacing: 12,
              children: [
                Icon(icon),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            ...body,
            if (outcome is! Running)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: onTryAgain,
                  icon: const Icon(Icons.refresh),
                  label: Text(strings.tryAgain),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        Expanded(child: SelectableText(value)),
      ],
    );
  }
}
