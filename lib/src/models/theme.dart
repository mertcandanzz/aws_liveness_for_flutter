import 'dart:ui' show Color;

/// Light/dark selection for the native liveness UI.
enum LivenessThemeMode {
  /// Follow the system setting.
  system,

  /// Always use the light colours.
  light,

  /// Always use the dark colours.
  dark,
}

/// Theme of the native liveness UI.
final class LivenessTheme {
  /// Creates a theme. Null colour sets keep the SDK defaults.
  const LivenessTheme({
    this.mode = LivenessThemeMode.system,
    this.light,
    this.dark,
  });

  /// Which colour set the native UI uses.
  final LivenessThemeMode mode;

  /// Overrides used in light mode.
  final LivenessColors? light;

  /// Overrides used in dark mode.
  final LivenessColors? dark;
}

/// Colour overrides for the tokens that exist in both native SDKs.
///
/// A null token keeps the SDK default. On Android, `onSurface` follows
/// [onBackground].
final class LivenessColors {
  /// Creates colour overrides.
  const LivenessColors({
    this.primary,
    this.onPrimary,
    this.background,
    this.onBackground,
    this.surface,
    this.error,
    this.onError,
    this.errorContainer,
    this.onErrorContainer,
  });

  /// Primary colour.
  final Color? primary;

  /// Content colour on [primary].
  final Color? onPrimary;

  /// Screen background.
  final Color? background;

  /// Content colour on [background].
  final Color? onBackground;

  /// Surface colour.
  final Color? surface;

  /// Error colour.
  final Color? error;

  /// Content colour on [error].
  final Color? onError;

  /// Error container colour.
  final Color? errorContainer;

  /// Content colour on [errorContainer].
  final Color? onErrorContainer;
}
