import 'dart:async';
import 'dart:convert';

import 'package:aws_liveness_for_flutter/aws_liveness_for_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'url_policy.dart';

/// Challenge the backend may create the session with.
enum LivenessChallenge {
  faceMovement('FaceMovementChallenge'),
  faceMovementAndLight('FaceMovementAndLightChallenge');

  const LivenessChallenge(this.wireName);

  final String wireName;
}

/// A session created by the backend.
class BackendSession {
  const BackendSession({required this.sessionId, required this.region});

  final String sessionId;
  final String region;
}

/// The backend's decision for a finished session.
class BackendDecision {
  const BackendDecision({
    required this.status,
    required this.isLive,
    required this.confidence,
  });

  final String status;
  final bool isLive;
  final double? confidence;
}

/// A failed backend call. [code] is the backend's error code or `network`.
class BackendException implements Exception {
  const BackendException(this.code, {this.statusCode});

  final String code;
  final int? statusCode;

  @override
  String toString() => statusCode == null
      ? 'BackendException($code)'
      : 'BackendException($statusCode $code)';
}

/// Talks to `examples/backend-express`. The app never decides liveness
/// itself; it only shows the backend's decision.
///
/// Throws [BackendException] with code `insecure_url` from the constructor,
/// before any request, unless [baseUrl] passes [isAllowedBackendUrl]:
/// `https`, or `http` on loopback when [allowInsecureLoopback] is true (by
/// default only in debug builds). Redirects are never followed, so a
/// response cannot move the token or credentials to another URL.
class BackendClient {
  BackendClient({
    required Uri baseUrl,
    required String token,
    http.Client? httpClient,
    bool allowInsecureLoopback = kDebugMode,
  }) : _baseUrl = baseUrl,
       _token = token,
       _allowInsecureLoopback = allowInsecureLoopback,
       _http = httpClient ?? http.Client() {
    _checked(baseUrl);
  }

  static const _timeout = Duration(seconds: 15);

  final Uri _baseUrl;
  final String _token;
  final bool _allowInsecureLoopback;
  final http.Client _http;

  /// Creates a single-use session. [challenge] is sent only when set; the
  /// backend rejects it unless `LIVENESS_ALLOW_CLIENT_CHALLENGE=true`.
  Future<BackendSession> createSession({LivenessChallenge? challenge}) async {
    final body = await _post('liveness/sessions', {
      if (challenge != null) 'challenge': challenge.wireName,
    });
    return BackendSession(
      sessionId: _string(body, 'sessionId'),
      region: _string(body, 'region'),
    );
  }

  /// Fetches temporary credentials for [sessionId]. Used as the plugin's
  /// credentials provider; the values are never logged or stored.
  Future<LivenessCredentials> fetchCredentials(String sessionId) async {
    final body = await _post('liveness/credentials', {'sessionId': sessionId});
    final expiration = DateTime.tryParse(_string(body, 'expiration'));
    if (expiration == null) throw const BackendException('invalid_response');
    return LivenessCredentials(
      accessKeyId: _string(body, 'accessKeyId'),
      secretAccessKey: _string(body, 'secretAccessKey'),
      sessionToken: _string(body, 'sessionToken'),
      expiration: expiration,
    );
  }

  /// Reads the backend's decision for [sessionId].
  Future<BackendDecision> fetchResult(String sessionId) async {
    final body = await _send(
      'GET',
      'liveness/sessions/${Uri.encodeComponent(sessionId)}/result',
    );
    final isLive = body['isLive'];
    final confidence = body['confidence'];
    if (isLive is! bool || (confidence != null && confidence is! num)) {
      throw const BackendException('invalid_response');
    }
    return BackendDecision(
      status: _string(body, 'status'),
      isLive: isLive,
      confidence: (confidence as num?)?.toDouble(),
    );
  }

  /// Releases the HTTP connection pool.
  void close() => _http.close();

  Future<Map<String, Object?>> _post(String path, Map<String, Object?> body) =>
      _send('POST', path, body: body);

  /// Returns [uri] if the transport policy allows it; throws otherwise.
  Uri _checked(Uri uri) {
    if (!isAllowedBackendUrl(
      uri,
      allowInsecureLoopback: _allowInsecureLoopback,
    )) {
      throw const BackendException('insecure_url');
    }
    return uri;
  }

  /// The only place that sends a request. The URL is checked first and
  /// redirects are disabled, so every byte goes to an allowed URL.
  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final request = http.Request(method, _checked(_baseUrl.resolve(path)))
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer $_token';
    if (body != null) {
      request
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(_timeout);
    } on TimeoutException {
      throw const BackendException('timeout');
    } on http.ClientException {
      throw const BackendException('network');
    }
    if (response.statusCode >= 300 && response.statusCode < 400) {
      throw BackendException(
        'redirect_not_allowed',
        statusCode: response.statusCode,
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw BackendException(
        'invalid_response',
        statusCode: response.statusCode,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw BackendException(
        'invalid_response',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'];
      throw BackendException(
        error is String ? error : 'http_error',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  static String _string(Map<String, Object?> body, String key) {
    final value = body[key];
    if (value is! String || value.isEmpty) {
      throw const BackendException('invalid_response');
    }
    return value;
  }
}
