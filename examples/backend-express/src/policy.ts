/** STS minimum, and the most the app ever needs: a session lasts ~3 minutes. */
export const CREDENTIALS_DURATION_SECONDS = 900;

/**
 * Inline session policy for AssumeRole. The effective permissions are the
 * intersection of the role's policy and this one, so even a broader role
 * yields credentials that can only stream a liveness check.
 */
export function livenessSessionPolicy(): string {
  return JSON.stringify({
    Version: '2012-10-17',
    Statement: [
      {
        Effect: 'Allow',
        Action: 'rekognition:StartFaceLivenessSession',
        Resource: '*',
      },
    ],
  });
}
