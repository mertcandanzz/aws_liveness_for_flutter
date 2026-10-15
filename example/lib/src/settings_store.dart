import 'package:shared_preferences/shared_preferences.dart';

/// Backend connection settings entered by the user.
class BackendSettings {
  const BackendSettings({required this.url, required this.token});

  /// Defaults from `--dart-define=LIVENESS_BACKEND_URL=...` and
  /// `--dart-define=LIVENESS_BACKEND_TOKEN=...`; empty when not set.
  static const fromEnvironment = BackendSettings(
    url: String.fromEnvironment('LIVENESS_BACKEND_URL'),
    token: String.fromEnvironment('LIVENESS_BACKEND_TOKEN'),
  );

  final String url;
  final String token;

  bool get isComplete => parsedUrl != null && token.isNotEmpty;

  /// The URL with a trailing slash, so relative paths resolve under it.
  Uri? get parsedUrl {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    if (uri.host.isEmpty) return null;
    return uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');
  }
}

/// Persists [BackendSettings] on the device.
///
/// shared_preferences is plain storage: fine for a demo token, not for real
/// secrets. A production app authenticates its own users instead.
class SettingsStore {
  static const _urlKey = 'backend_url';
  static const _tokenKey = 'backend_token';

  Future<BackendSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    const defaults = BackendSettings.fromEnvironment;
    return BackendSettings(
      url: prefs.getString(_urlKey) ?? defaults.url,
      token: prefs.getString(_tokenKey) ?? defaults.token,
    );
  }

  Future<void> save(BackendSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, settings.url.trim());
    await prefs.setString(_tokenKey, settings.token.trim());
  }
}
