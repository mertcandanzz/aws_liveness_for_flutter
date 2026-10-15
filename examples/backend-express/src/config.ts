export type ChallengeType = 'FaceMovementChallenge' | 'FaceMovementAndLightChallenge';

export const CHALLENGE_TYPES: readonly ChallengeType[] = [
  'FaceMovementChallenge',
  'FaceMovementAndLightChallenge',
];

export interface S3Output {
  bucket: string;
  keyPrefix?: string;
}

export interface Config {
  port: number;
  region: string;
  /** Bearer tokens accepted by the API. Each token is a separate caller. */
  apiTokens: readonly string[];
  /** Role the credentials endpoint assumes, scoped down by a session policy. */
  credentialsRoleArn: string;
  defaultChallenge: ChallengeType;
  /** Whether a caller may pick the challenge. Off by default: the server decides. */
  allowClientChallenge: boolean;
  auditImagesLimit: number;
  s3Output?: S3Output;
  /** Minimum confidence (0-100) for isLive. Never taken from the client. */
  confidenceThreshold: number;
  rateLimitPerMinute: number;
}

export class ConfigError extends Error {}

const REGION_PATTERN = /^[a-z]{2}(-[a-z]+)+-\d+$/;
const ROLE_ARN_PATTERN = /^arn:aws[a-z-]*:iam::\d{12}:role\/[\w+=,.@/-]{1,512}$/;
const MIN_TOKEN_LENGTH = 32;

type Env = Readonly<Record<string, string | undefined>>;

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

function bool(env: Env, name: string): boolean {
  const raw = env[name]?.trim().toLowerCase();
  if (!raw) return false;
  if (raw === 'true') return true;
  if (raw === 'false') return false;
  throw new ConfigError(`${name} must be true or false`);
}

/** Reads and validates the configuration. Error messages never echo values. */
export function loadConfig(env: Env): Config {
  const region = required(env, 'AWS_REGION');
  if (!REGION_PATTERN.test(region)) throw new ConfigError('AWS_REGION is not a region code');

  const apiTokens = required(env, 'LIVENESS_API_TOKENS')
    .split(',')
    .map((token) => token.trim())
    .filter((token) => token.length > 0);
  if (apiTokens.length === 0 || apiTokens.some((token) => token.length < MIN_TOKEN_LENGTH)) {
    throw new ConfigError(`each LIVENESS_API_TOKENS entry must be at least ${MIN_TOKEN_LENGTH} characters`);
  }

  const credentialsRoleArn = required(env, 'LIVENESS_CREDENTIALS_ROLE_ARN');
  if (!ROLE_ARN_PATTERN.test(credentialsRoleArn)) {
    throw new ConfigError('LIVENESS_CREDENTIALS_ROLE_ARN is not an IAM role ARN');
  }

  const challenge = env.LIVENESS_CHALLENGE?.trim() || 'FaceMovementChallenge';
  if (!CHALLENGE_TYPES.includes(challenge as ChallengeType)) {
    throw new ConfigError(`LIVENESS_CHALLENGE must be one of ${CHALLENGE_TYPES.join(', ')}`);
  }

  const bucket = env.LIVENESS_OUTPUT_S3_BUCKET?.trim();
  const keyPrefix = env.LIVENESS_OUTPUT_S3_KEY_PREFIX?.trim();

  return {
    port: integer(env, 'PORT', 8787, 1, 65535),
    region,
    apiTokens,
    credentialsRoleArn,
    defaultChallenge: challenge as ChallengeType,
    allowClientChallenge: bool(env, 'LIVENESS_ALLOW_CLIENT_CHALLENGE'),
    auditImagesLimit: integer(env, 'LIVENESS_AUDIT_IMAGES_LIMIT', 0, 0, 4),
    s3Output: bucket ? { bucket, ...(keyPrefix ? { keyPrefix } : {}) } : undefined,
    confidenceThreshold: integer(env, 'LIVENESS_CONFIDENCE_THRESHOLD', 80, 0, 100),
    rateLimitPerMinute: integer(env, 'LIVENESS_RATE_LIMIT_PER_MINUTE', 30, 1, 10000),
  };
}
