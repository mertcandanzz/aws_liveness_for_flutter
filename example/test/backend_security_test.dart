import 'dart:convert';

import 'package:aws_liveness_for_flutter_example/src/backend_client.dart';
import 'package:aws_liveness_for_flutter_example/src/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _sessionId = '0f1e2d3c-4b5a-4968-8776-655443322110';

/// Records every request that reaches the network layer.
class _Recorder {
  final requests = <http.Request>[];

  late final client = MockClient((request) async {
    requests.add(request);
    return http.Response(
      jsonEncode({'sessionId': _sessionId, 'region': 'eu-west-1'}),
      201,
    );
  });
}

final _insecure = throwsA(
  isA<BackendException>().having((e) => e.code, 'code', 'insecure_url'),
);

void main() {
  group('release build (allowInsecureLoopback: false)', () {
    for (final url in [
      'http://backend.example/',
      'http://localhost:8787/',
      'http://127.0.0.1:8787/',
    ]) {
      test('rejects $url before sending anything', () async {
        final recorder = _Recorder();

        expect(
          () => BackendClient(
            baseUrl: Uri.parse(url),
            token: 'token',
            httpClient: recorder.client,
            allowInsecureLoopback: false,
          ),
          _insecure,
        );
        expect(recorder.requests, isEmpty);
      });
    }

    test('allows https', () async {
      final recorder = _Recorder();
      final client = BackendClient(
        baseUrl: Uri.parse('https://backend.example/'),
        token: 'token',
        httpClient: recorder.client,
        allowInsecureLoopback: false,
      );

      await client.createSession();

      expect(recorder.requests.single.url.scheme, 'https');
    });
  });

  group('debug build (allowInsecureLoopback: true)', () {
    for (final url in [
      'http://localhost:8787/',
      'http://127.0.0.1:8787/',
      'http://[::1]:8787/',
    ]) {
      test('allows loopback $url', () async {
        final recorder = _Recorder();
        final client = BackendClient(
          baseUrl: Uri.parse(url),
          token: 'token',
          httpClient: recorder.client,
          allowInsecureLoopback: true,
        );

        await client.createSession();

        expect(recorder.requests, hasLength(1));
      });
    }

    for (final url in [
      'http://192.168.1.20:8787/',
      'http://10.0.2.2:8787/',
      'http://backend.example/',
      'http://localhost.backend.example/',
    ]) {
      test('rejects non-loopback $url', () {
        final recorder = _Recorder();

        expect(
          () => BackendClient(
            baseUrl: Uri.parse(url),
            token: 'token',
            httpClient: recorder.client,
            allowInsecureLoopback: true,
          ),
          _insecure,
        );
        expect(recorder.requests, isEmpty);
      });
    }

    test('rejects other schemes', () {
      expect(
        () => BackendClient(
          baseUrl: Uri.parse('ftp://localhost/'),
          token: 'token',
          allowInsecureLoopback: true,
        ),
        _insecure,
      );
    });
  });

  group('redirects', () {
    test('are not followed and surface as an error', () async {
      final requests = <http.Request>[];
      final client = BackendClient(
        baseUrl: Uri.parse('https://backend.example/'),
        token: 'token',
        allowInsecureLoopback: false,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            '',
            302,
            headers: {'location': 'http://evil.example/'},
          );
        }),
      );

      await expectLater(
        client.fetchCredentials(_sessionId),
        throwsA(
          isA<BackendException>()
              .having((e) => e.code, 'code', 'redirect_not_allowed')
              .having((e) => e.statusCode, 'statusCode', 302),
        ),
      );
      expect(requests.single.followRedirects, isFalse);
    });

    test('every backend request disables redirects', () async {
      final requests = <http.Request>[];
      final client = BackendClient(
        baseUrl: Uri.parse('https://backend.example/'),
        token: 'token',
        allowInsecureLoopback: false,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode({'error': 'x'}), 500);
        }),
      );

      for (final call in [
        client.createSession,
        () => client.fetchCredentials(_sessionId),
        () => client.fetchResult(_sessionId),
      ]) {
        await expectLater(call(), throwsA(isA<BackendException>()));
      }

      expect(requests, hasLength(3));
      expect(requests.every((r) => !r.followRedirects), isTrue);
    });
  });

  group('BackendSettings', () {
    test('release builds accept only https', () {
      const http = BackendSettings(url: 'http://localhost:8787', token: 't');
      const https = BackendSettings(url: 'https://backend.example', token: 't');

      expect(http.isCompleteFor(allowInsecureLoopback: false), isFalse);
      expect(http.isInsecureFor(allowInsecureLoopback: false), isTrue);
      expect(https.isCompleteFor(allowInsecureLoopback: false), isTrue);
      expect(https.isInsecureFor(allowInsecureLoopback: false), isFalse);
    });

    test('debug builds also accept http on loopback only', () {
      const local = BackendSettings(url: 'http://localhost:8787', token: 't');
      const lan = BackendSettings(url: 'http://192.168.1.20:8787', token: 't');

      expect(local.isCompleteFor(allowInsecureLoopback: true), isTrue);
      expect(lan.isCompleteFor(allowInsecureLoopback: true), isFalse);
      expect(lan.isInsecureFor(allowInsecureLoopback: true), isTrue);
    });
  });
}
