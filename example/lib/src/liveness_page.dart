import 'package:aws_liveness_for_flutter/aws_liveness_for_flutter.dart';
import 'package:flutter/material.dart';

import 'backend_client.dart';
import 'outcome.dart';
import 'result_card.dart';
import 'settings_store.dart';
import 'strings.dart';

/// Upper bound for one attempt, including the permission prompt and the
/// start view. Sessions themselves expire after about three minutes.
const _attemptTimeout = Duration(minutes: 3);

/// Single screen: backend settings, options, start, availability and result.
class LivenessPage extends StatefulWidget {
  const LivenessPage({
    super.key,
    required this.strings,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onLanguageChanged,
    this.settingsStore,
  });

  final Strings strings;
  final LivenessThemeMode themeMode;
  final ValueChanged<LivenessThemeMode> onThemeModeChanged;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final SettingsStore? settingsStore;

  @override
  State<LivenessPage> createState() => _LivenessPageState();
}

class _LivenessPageState extends State<LivenessPage> {
  late final SettingsStore _store = widget.settingsStore ?? SettingsStore();
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();

  LivenessChallenge? _challenge;
  LivenessCamera _camera = LivenessCamera.front;
  bool _showStartView = true;
  LivenessAvailability? _availability;
  Outcome _outcome = const Idle();

  Strings get _s => widget.strings;

  bool get _isRunning => _outcome is Running;

  @override
  void initState() {
    super.initState();
    _store.load().then((settings) {
      if (!mounted) return;
      _urlController.text = settings.url;
      _tokenController.text = settings.token;
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  BackendSettings get _settings =>
      BackendSettings(url: _urlController.text, token: _tokenController.text);

  /// Shows why [settings] cannot be used and returns false, or returns true.
  bool _validate(BackendSettings settings) {
    if (settings.isComplete) return true;
    final message = settings.isInsecure ? _s.insecureUrl : _s.invalidSettings;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    return false;
  }

  Future<void> _saveSettings() async {
    final settings = _settings;
    if (!_validate(settings)) return;
    final messenger = ScaffoldMessenger.of(context);
    await _store.save(settings);
    messenger.showSnackBar(SnackBar(content: Text(_s.saved)));
  }

  Future<void> _checkAvailability() async {
    final availability = await AwsLiveness.checkAvailability();
    if (mounted) setState(() => _availability = availability);
  }

  /// Runs one attempt with a NEW session every time.
  Future<void> _start() async {
    final settings = _settings;
    if (!_validate(settings)) return;
    final baseUrl = settings.parsedUrl;
    if (baseUrl == null) return;

    final BackendClient client;
    try {
      // Re-checks the transport policy before any request is sent.
      client = BackendClient(baseUrl: baseUrl, token: settings.token);
    } on BackendException catch (error) {
      _show(BackendFailed(error));
      return;
    }
    _show(const Running(RunStep.creatingSession));
    try {
      final session = await client.createSession(challenge: _challenge);
      _show(const Running(RunStep.checking));
      final result = await AwsLiveness.start(
        LivenessRequest(
          sessionId: session.sessionId,
          region: session.region,
          credentialsProvider: () => client.fetchCredentials(session.sessionId),
          challengeOptions: LivenessChallengeOptions(
            faceMovementCamera: _camera,
          ),
          showStartView: _showStartView,
          theme: LivenessTheme(mode: widget.themeMode),
          timeout: _attemptTimeout,
        ),
      );
      switch (result) {
        case LivenessCompleted():
          _show(const Running(RunStep.readingResult));
          _show(Decided(await client.fetchResult(session.sessionId)));
        case LivenessCancelled(:final reason):
          _show(Cancelled(reason));
        case LivenessFailed(:final error):
          _show(Failed(error));
      }
    } on BackendException catch (error) {
      _show(BackendFailed(error));
    } finally {
      client.close();
    }
  }

  void _show(Outcome outcome) {
    if (mounted) setState(() => _outcome = outcome);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_s.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ResultCard(
              outcome: _outcome,
              strings: _s,
              onTryAgain: _isRunning ? null : _start,
              onOpenSettings: AwsLiveness.openAppSettings,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _isRunning ? null : _start,
              icon: const Icon(Icons.face_retouching_natural),
              label: Text(_s.start),
            ),
            const SizedBox(height: 24),
            _section(theme, _s.backend),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: _s.backendUrl,
                hintText: _s.backendUrlHint,
              ),
            ),
            TextField(
              controller: _tokenController,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: _s.token),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _saveSettings, child: Text(_s.save)),
            ),
            _section(theme, _s.options),
            _label(theme, _s.challenge),
            SegmentedButton<LivenessChallenge?>(
              segments: [
                ButtonSegment(value: null, label: Text(_s.challengeServer)),
                ButtonSegment(
                  value: LivenessChallenge.faceMovement,
                  label: Text(_s.challengeMovement),
                ),
                ButtonSegment(
                  value: LivenessChallenge.faceMovementAndLight,
                  label: Text(_s.challengeMovementLight),
                ),
              ],
              selected: {_challenge},
              onSelectionChanged: (s) => setState(() => _challenge = s.first),
            ),
            if (_challenge == LivenessChallenge.faceMovementAndLight)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _s.photosensitivity,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            _label(theme, _s.camera),
            SegmentedButton<LivenessCamera>(
              segments: [
                ButtonSegment(
                  value: LivenessCamera.front,
                  label: Text(_s.front),
                ),
                ButtonSegment(value: LivenessCamera.back, label: Text(_s.back)),
              ],
              selected: {_camera},
              onSelectionChanged: (s) => setState(() => _camera = s.first),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_s.startView),
              value: _showStartView,
              onChanged: (value) => setState(() => _showStartView = value),
            ),
            _label(theme, _s.theme),
            SegmentedButton<LivenessThemeMode>(
              segments: [
                ButtonSegment(
                  value: LivenessThemeMode.system,
                  label: Text(_s.system),
                ),
                ButtonSegment(
                  value: LivenessThemeMode.light,
                  label: Text(_s.light),
                ),
                ButtonSegment(
                  value: LivenessThemeMode.dark,
                  label: Text(_s.dark),
                ),
              ],
              selected: {widget.themeMode},
              onSelectionChanged: (s) => widget.onThemeModeChanged(s.first),
            ),
            _label(theme, _s.languageLabel),
            SegmentedButton<AppLanguage>(
              segments: [
                for (final language in AppLanguage.values)
                  ButtonSegment(value: language, label: Text(language.label)),
              ],
              selected: {_s.language},
              onSelectionChanged: (s) => widget.onLanguageChanged(s.first),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _checkAvailability,
              child: Text(_s.checkAvailability),
            ),
            if (_availability case final availability?)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  availability.isAvailable ? Icons.check_circle : Icons.block,
                ),
                title: Text(
                  availability.isAvailable ? _s.available : _s.unavailable,
                ),
                subtitle: availability.reason == null
                    ? null
                    : Text(availability.reason!.name),
              ),
          ],
        ),
      ),
    );
  }

  Widget _section(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Text(text, style: theme.textTheme.titleLarge),
  );

  Widget _label(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Text(text, style: theme.textTheme.labelLarge),
  );
}
