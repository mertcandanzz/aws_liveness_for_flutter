export type ChallengeType = 'FaceMovementChallenge' | 'FaceMovementAndLightChallenge';

export const CHALLENGE_TYPES: readonly ChallengeType[] = [
  'FaceMovementChallenge',
  'FaceMovementAndLightChallenge',
];

type Env = Readonly<Record<string, string | undefined>>;

export class ConfigError extends Error {}

function required(env: Env, name: string): string {
  const value = env[name]?.trim();
  if (!value) throw new ConfigError(`${name} is required`);
  return value;
}

function integer(env: Env, name: string, fallback: number, min: number, max: number): number {
  const raw = env[name]?.trim();
  if (!raw) return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new ConfigError(`${name} must be an integer between ${min} and ${max}`);
  }
  return value;
}

/** DynamoDB table that binds sessions to callers. Set by the stack. */
export function tableName(env: Env): string {
  return required(env, 'SESSIONS_TABLE');
}

export interface SessionSettings {
  defaultChallenge: ChallengeType;
  allowClientChallenge: boolean;
  auditImagesLimit: number;
  s3Output?: { bucket: string; keyPrefix?: string };
}

export function sessionSettings(env: Env): SessionSettings {
  const challenge = env.LIVENESS_CHALLENGE?.trim() || 'FaceMovementChallenge';
  if (!CHALLENGE_TYPES.includes(challenge as ChallengeType)) {
    throw new ConfigError(`LIVENESS_CHALLENGE must be one of ${CHALLENGE_TYPES.join(', ')}`);
  }
  const bucket = env.LIVENESS_OUTPUT_S3_BUCKET?.trim();
  const keyPrefix = env.LIVENESS_OUTPUT_S3_KEY_PREFIX?.trim();
  return {
    defaultChallenge: challenge as ChallengeType,
    allowClientChallenge: env.LIVENESS_ALLOW_CLIENT_CHALLENGE?.trim() === 'true',
    auditImagesLimit: integer(env, 'LIVENESS_AUDIT_IMAGES_LIMIT', 0, 0, 4),
    s3Output: bucket ? { bucket, ...(keyPrefix ? { keyPrefix } : {}) } : undefined,
  };
}

/** Role the credentials function assumes for the app. */
export function credentialsRoleArn(env: Env): string {
  return required(env, 'LIVENESS_CREDENTIALS_ROLE_ARN');
}

/** Minimum confidence (0-100) for isLive. Never taken from the client. */
export function confidenceThreshold(env: Env): number {
  return integer(env, 'LIVENESS_CONFIDENCE_THRESHOLD', 80, 0, 100);
}

/** SHA-256 digests (hex) of the accepted bearer tokens. Never the tokens themselves. */
export function tokenDigests(env: Env): readonly string[] {
  const digests = required(env, 'API_TOKEN_SHA256')
    .split(',')
    .map((d) => d.trim().toLowerCase())
    .filter((d) => d.length > 0);
  if (digests.length === 0 || digests.some((d) => !/^[0-9a-f]{64}$/.test(d))) {
    throw new ConfigError('API_TOKEN_SHA256 must be comma-separated SHA-256 hex digests');
  }
  return digests;
}
