const _loopbackHosts = {'localhost', '127.0.0.1', '::1'};

/// Whether the app may send the bearer token and receive AWS credentials over
/// [uri].
///
/// `https` is always allowed. Plain `http` only when [allowInsecureLoopback]
/// is true (debug builds) and the host is the device itself, which is what
/// `adb reverse tcp:8787 tcp:8787` provides. Dart's own sockets do not follow
/// the platform's cleartext policy, so this check is the real guard.
bool isAllowedBackendUrl(Uri uri, {required bool allowInsecureLoopback}) {
  if (uri.host.isEmpty) return false;
  if (uri.isScheme('https')) return true;
  return uri.isScheme('http') &&
      allowInsecureLoopback &&
      _loopbackHosts.contains(uri.host.toLowerCase());
}
