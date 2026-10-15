import 'package:aws_liveness_for_flutter/aws_liveness_for_flutter.dart';
import 'package:flutter/material.dart';

import 'src/liveness_page.dart';
import 'src/settings_store.dart';
import 'src/strings.dart';

void main() {
  runApp(const ExampleApp());
}

/// Example app for aws_liveness_for_flutter. Needs a running
/// `examples/backend-express`; enter its URL and token in the app or pass
/// `--dart-define=LIVENESS_BACKEND_URL=...` and
/// `--dart-define=LIVENESS_BACKEND_TOKEN=...`.
class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key, this.settingsStore});

  /// Overrides persistence, for tests.
  final SettingsStore? settingsStore;

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  LivenessThemeMode _themeMode = LivenessThemeMode.system;
  AppLanguage _language = AppLanguage.en;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF00897B);
    return MaterialApp(
      title: 'aws_liveness_for_flutter example',
      themeMode: switch (_themeMode) {
        LivenessThemeMode.system => ThemeMode.system,
        LivenessThemeMode.light => ThemeMode.light,
        LivenessThemeMode.dark => ThemeMode.dark,
      },
      theme: ThemeData(colorSchemeSeed: seed),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
      home: LivenessPage(
        strings: Strings(_language),
        themeMode: _themeMode,
        onThemeModeChanged: (mode) => setState(() => _themeMode = mode),
        onLanguageChanged: (language) => setState(() => _language = language),
        settingsStore: widget.settingsStore,
      ),
    );
  }
}
