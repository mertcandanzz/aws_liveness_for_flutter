import 'dart:convert';

import 'package:aws_liveness_for_flutter_example/src/backend_client.dart';
import 'package:aws_liveness_for_flutter_example/src/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _sessionId = '0f1e2d3c-4b5a-4968-8776-655443322110';

BackendClient _client(MockClientHandler handler) => BackendClient(
  baseUrl: Uri.parse('http://localhost:8787/'),
  token: 'test-token',
  httpClient: MockClient(handler),
);

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  test('createSession posts with the bearer token and the challenge', () async {
    late http.Request sent;
    final client = _client((request) async {
      sent = request;
      return _json({'sessionId': _sessionId, 'region': 'eu-west-1'}, 201);
    });

    final session = await client.createSession(
      challenge: LivenessChallenge.faceMovementAndLight,
    );

    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'http://localhost:8787/liveness/sessions');
    expect(sent.headers['Authorization'], 'Bearer test-token');
    expect(jsonDecode(sent.body), {
      'challenge': 'FaceMovementAndLightChallenge',
    });
    expect(session.sessionId, _sessionId);
    expect(session.region, 'eu-west-1');
  });

  test('createSession omits the challenge when unset', () async {
    late http.Request sent;
    final client = _client((request) async {
      sent = request;
      return _json({'sessionId': _sessionId, 'region': 'eu-west-1'}, 201);
    });

    await client.createSession();

    expect(jsonDecode(sent.body), isEmpty);
  });

  test('fetchCredentials maps the response', () async {
    final client = _client(
      (request) async => _json({
        'accessKeyId': 'ASIAEXAMPLE',
        'secretAccessKey': 'secret',
        'sessionToken': 'token',
        'expiration': '2030-01-01T00:15:00.000Z',
      }),
    );

    final credentials = await client.fetchCredentials(_sessionId);

    expect(credentials.accessKeyId, 'ASIAEXAMPLE');
    expect(credentials.expiration, DateTime.utc(2030, 1, 1, 0, 15));
  });

  test('fetchResult returns the backend decision', () async {
    late http.Request sent;
    final client = _client((request) async {
      sent = request;
      return _json({
        'sessionId': _sessionId,
        'status': 'SUCCEEDED',
        'isLive': true,
        'confidence': 97.5,
      });
    });

    final decision = await client.fetchResult(_sessionId);

    expect(sent.method, 'GET');
    expect(sent.url.path, '/liveness/sessions/$_sessionId/result');
    expect(decision.isLive, isTrue);
    expect(decision.confidence, 97.5);
    expect(decision.status, 'SUCCEEDED');
  });

  test('errors carry the backend code and status', () async {
    final client = _client(
      (request) async => _json({'error': 'session_not_found'}, 404),
    );

    expect(
      client.fetchResult(_sessionId),
      throwsA(
        isA<BackendException>()
            .having((e) => e.code, 'code', 'session_not_found')
            .having((e) => e.statusCode, 'statusCode', 404),
      ),
    );
  });

  test('malformed responses are rejected', () async {
    final notJson = _client((request) async => http.Response('<html>', 200));
    final missingField = _client((request) async => _json({'region': 'x'}));
    final badDecision = _client(
      (request) async => _json({'status': 'SUCCEEDED', 'isLive': 'yes'}),
    );
    final badExpiration = _client(
      (request) async => _json({
        'accessKeyId': 'a',
        'secretAccessKey': 'b',
        'sessionToken': 'c',
        'expiration': 'later',
      }),
    );

    final invalid = throwsA(
      isA<BackendException>().having((e) => e.code, 'code', 'invalid_response'),
    );
    expect(notJson.createSession(), invalid);
    expect(missingField.createSession(), invalid);
    expect(badDecision.fetchResult(_sessionId), invalid);
    expect(badExpiration.fetchCredentials(_sessionId), invalid);
  });

  test('network failures become a network error', () async {
    final client = _client(
      (request) async => throw http.ClientException('offline'),
    );

    expect(
      client.createSession(),
      throwsA(isA<BackendException>().having((e) => e.code, 'code', 'network')),
    );
  });

  group('BackendSettings', () {
    test('accepts http(s) URLs and adds a trailing slash', () {
      const settings = BackendSettings(
        url: ' http://localhost:8787 ',
        token: 't',
      );

      expect(settings.isComplete, isTrue);
      expect(settings.parsedUrl.toString(), 'http://localhost:8787/');
    });

    test('rejects other schemes, missing hosts and empty tokens', () {
      expect(
        const BackendSettings(url: 'ftp://host', token: 't').isComplete,
        isFalse,
      );
      expect(
        const BackendSettings(url: 'localhost', token: 't').isComplete,
        isFalse,
      );
      expect(
        const BackendSettings(url: 'https://host/', token: '').isComplete,
        isFalse,
      );
    });
  });
}
