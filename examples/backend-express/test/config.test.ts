import { describe, expect, it } from 'vitest';
import { ConfigError, loadConfig } from '../src/config.js';
import { matchToken } from '../src/auth.js';
import { SESSION_BINDING_TTL_MS, SessionStore } from '../src/sessionStore.js';

const base = {
  AWS_REGION: 'eu-west-1',
  LIVENESS_API_TOKENS: 'x'.repeat(32),
  LIVENESS_CREDENTIALS_ROLE_ARN: 'arn:aws:iam::123456789012:role/liveness-client',
};

describe('loadConfig', () => {
  it('applies safe defaults', () => {
    const config = loadConfig(base);

    expect(config).toMatchObject({
      port: 8787,
      region: 'eu-west-1',
      defaultChallenge: 'FaceMovementChallenge',
      allowClientChallenge: false,
      auditImagesLimit: 0,
      confidenceThreshold: 80,
      rateLimitPerMinute: 30,
    });
    expect(config.s3Output).toBeUndefined();
  });

  it('reads every optional setting', () => {
    const config = loadConfig({
      ...base,
      PORT: '9000',
      LIVENESS_API_TOKENS: `${'x'.repeat(32)}, ${'y'.repeat(32)}`,
      LIVENESS_CHALLENGE: 'FaceMovementAndLightChallenge',
      LIVENESS_ALLOW_CLIENT_CHALLENGE: 'true',
      LIVENESS_AUDIT_IMAGES_LIMIT: '4',
      LIVENESS_OUTPUT_S3_BUCKET: 'bucket',
      LIVENESS_OUTPUT_S3_KEY_PREFIX: 'prefix/',
      LIVENESS_CONFIDENCE_THRESHOLD: '95',
      LIVENESS_RATE_LIMIT_PER_MINUTE: '5',
    });

    expect(config.port).toBe(9000);
    expect(config.apiTokens).toHaveLength(2);
    expect(config.defaultChallenge).toBe('FaceMovementAndLightChallenge');
    expect(config.allowClientChallenge).toBe(true);
    expect(config.auditImagesLimit).toBe(4);
    expect(config.s3Output).toEqual({ bucket: 'bucket', keyPrefix: 'prefix/' });
    expect(config.confidenceThreshold).toBe(95);
    expect(config.rateLimitPerMinute).toBe(5);
  });

  it.each([
    ['missing region', { AWS_REGION: undefined }],
    ['bad region', { AWS_REGION: 'EU_WEST' }],
    ['missing tokens', { LIVENESS_API_TOKENS: undefined }],
    ['short token', { LIVENESS_API_TOKENS: 'short' }],
    ['bad role arn', { LIVENESS_CREDENTIALS_ROLE_ARN: 'arn:aws:iam::1:user/x' }],
    ['bad challenge', { LIVENESS_CHALLENGE: 'Other' }],
    ['audit limit too high', { LIVENESS_AUDIT_IMAGES_LIMIT: '5' }],
    ['threshold too high', { LIVENESS_CONFIDENCE_THRESHOLD: '101' }],
    ['non-integer threshold', { LIVENESS_CONFIDENCE_THRESHOLD: '80.5' }],
    ['bad boolean', { LIVENESS_ALLOW_CLIENT_CHALLENGE: 'yes' }],
  ])('rejects %s', (_name, overrides) => {
    expect(() => loadConfig({ ...base, ...overrides })).toThrow(ConfigError);
  });

  it('never echoes secret values in errors', () => {
    const secret = 'short-secret';
    try {
      loadConfig({ ...base, LIVENESS_API_TOKENS: secret });
    } catch (error) {
      expect((error as Error).message).not.toContain(secret);
    }
  });
});

describe('matchToken', () => {
  it('returns a stable id per token and undefined otherwise', () => {
    const tokens = ['a'.repeat(32), 'b'.repeat(32)];

    const a = matchToken('a'.repeat(32), tokens);
    const b = matchToken('b'.repeat(32), tokens);

    expect(a).toMatch(/^[0-9a-f]{16}$/);
    expect(b).not.toBe(a);
    expect(matchToken('a'.repeat(32), tokens)).toBe(a);
    expect(matchToken('c'.repeat(32), tokens)).toBeUndefined();
    expect(matchToken('', tokens)).toBeUndefined();
  });
});

describe('SessionStore', () => {
  it('forgets bindings after the TTL', () => {
    let time = 0;
    const store = new SessionStore(() => time);
    store.bind('s1', 'owner');

    expect(store.isOwnedBy('s1', 'owner')).toBe(true);
    expect(store.isOwnedBy('s1', 'other')).toBe(false);

    time = SESSION_BINDING_TTL_MS;
    expect(store.isOwnedBy('s1', 'owner')).toBe(false);

    store.bind('s2', 'owner');
    expect(store.isOwnedBy('s2', 'owner')).toBe(true);
  });
});
