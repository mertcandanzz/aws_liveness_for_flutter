/// Credentials for `aws_liveness_for_flutter` from a Cognito identity pool,
/// fetched with Amplify Auth.
///
/// The plugin itself does not depend on Cognito: this file only adapts
/// `Amplify.Auth.fetchAuthSession()` to `LivenessRequest.credentialsProvider`.
/// Session creation and result reads still happen on your backend.
library;

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:aws_liveness_for_flutter/aws_liveness_for_flutter.dart';

/// Returns a provider that fetches the signed-in user's identity pool
/// credentials every time the native SDK asks for them.
///
/// Amplify refreshes expired credentials itself. Pass [fetchSession] to
/// replace `Amplify.Auth.fetchAuthSession` in tests.
LivenessCredentialsProvider cognitoCredentialsProvider({
  Future<AuthSession> Function()? fetchSession,
}) {
  final fetch = fetchSession ?? () => Amplify.Auth.fetchAuthSession();
  return () async {
    final session = await fetch();
    if (session is! CognitoAuthSession) {
      throw StateError('Amplify Auth is not configured with Cognito.');
    }
    if (!session.isSignedIn) {
      throw StateError('Sign in before starting a liveness check.');
    }
    // Throws the Amplify exception if the identity pool refused the user.
    return livenessCredentialsFrom(session.credentialsResult.value);
  };
}

/// Maps Amplify's [AWSCredentials] to the plugin's [LivenessCredentials].
///
/// Identity pool credentials are always temporary; long-lived keys without a
/// session token or expiration are rejected.
LivenessCredentials livenessCredentialsFrom(AWSCredentials credentials) {
  final sessionToken = credentials.sessionToken;
  final expiration = credentials.expiration;
  if (sessionToken == null || sessionToken.isEmpty || expiration == null) {
    throw ArgumentError('Temporary credentials with a session token expected.');
  }
  return LivenessCredentials(
    accessKeyId: credentials.accessKeyId,
    secretAccessKey: credentials.secretAccessKey,
    sessionToken: sessionToken,
    expiration: expiration,
  );
}
