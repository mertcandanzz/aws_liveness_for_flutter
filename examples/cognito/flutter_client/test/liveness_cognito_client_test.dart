import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_cognito_client/liveness_cognito_client.dart';

final _expiration = DateTime.utc(2030);

AWSCredentials _temporary() =>
    AWSCredentials('ASIAEXAMPLE', 'secret', 'session-token', _expiration);

CognitoAuthSession _session({
  bool signedIn = true,
  AuthResult<AWSCredentials>? credentials,
}) => CognitoAuthSession(
  isSignedIn: signedIn,
  userSubResult: const AuthResult.success('sub'),
  credentialsResult: credentials ?? AuthResult.success(_temporary()),
  identityIdResult: const AuthResult.success('identity'),
  userPoolTokensResult: AuthResult.error(
    const SignedOutException('not needed in this test'),
  ),
);

void main() {
  test('maps temporary credentials', () {
    final credentials = livenessCredentialsFrom(_temporary());

    expect(credentials.accessKeyId, 'ASIAEXAMPLE');
    expect(credentials.secretAccessKey, 'secret');
    expect(credentials.sessionToken, 'session-token');
    expect(credentials.expiration, _expiration);
  });

  test('rejects long-lived credentials', () {
    expect(
      () => livenessCredentialsFrom(const AWSCredentials('AKIAEXAMPLE', 'x')),
      throwsArgumentError,
    );
  });

  test('the provider returns the signed-in user credentials', () async {
    final provider = cognitoCredentialsProvider(
      fetchSession: () async => _session(),
    );

    expect((await provider()).sessionToken, 'session-token');
  });

  test('the provider fails when the user is signed out', () {
    final provider = cognitoCredentialsProvider(
      fetchSession: () async => _session(signedIn: false),
    );

    expect(provider(), throwsStateError);
  });

  test('the provider surfaces an identity pool error', () {
    final provider = cognitoCredentialsProvider(
      fetchSession: () async => _session(
        credentials: AuthResult.error(
          const UnknownException('identity pool refused'),
        ),
      ),
    );

    expect(provider(), throwsA(isA<UnknownException>()));
  });
}
