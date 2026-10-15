import {
  CreateFaceLivenessSessionCommand,
  GetFaceLivenessSessionResultsCommand,
  RekognitionClient,
  SessionNotFoundException,
  ThrottlingException,
  AccessDeniedException,
} from '@aws-sdk/client-rekognition';
import { AssumeRoleCommand, STSClient } from '@aws-sdk/client-sts';
import { mockClient } from 'aws-sdk-client-mock';
import request from 'supertest';
import { beforeEach, describe, expect, it } from 'vitest';
import { createApp, type Logger } from '../src/app.js';
import type { Config } from '../src/config.js';
import { CREDENTIALS_DURATION_SECONDS } from '../src/policy.js';

const TOKEN_A = 'a'.repeat(40);
const TOKEN_B = 'b'.repeat(40);
const SESSION_ID = '0f1e2d3c-4b5a-4968-8776-655443322110';
const OTHER_SESSION_ID = '11111111-2222-4333-8444-555555555555';
const SECRET = 'example-secret-access-key-value';
const SESSION_TOKEN = 'example-session-token-value';

const rekognition = mockClient(RekognitionClient);
const sts = mockClient(STSClient);

function config(overrides: Partial<Config> = {}): Config {
  return {
    port: 8787,
    region: 'eu-west-1',
    apiTokens: [TOKEN_A, TOKEN_B],
    credentialsRoleArn: 'arn:aws:iam::123456789012:role/liveness-client',
    defaultChallenge: 'FaceMovementChallenge',
    allowClientChallenge: false,
    auditImagesLimit: 0,
    confidenceThreshold: 80,
    rateLimitPerMinute: 1000,
    ...overrides,
  };
}

function build(overrides: Partial<Config> = {}, log: Logger = () => {}) {
  return createApp({
    config: config(overrides),
    rekognition: new RekognitionClient({ region: 'eu-west-1' }),
    sts: new STSClient({ region: 'eu-west-1' }),
    log,
  });
}

const bodyOf = (res: request.Response): Record<string, unknown> => res.body as Record<string, unknown>;

const auth = (token = TOKEN_A) => ({ Authorization: `Bearer ${token}` });

async function createSession(app: ReturnType<typeof build>, token = TOKEN_A) {
  rekognition.on(CreateFaceLivenessSessionCommand).resolves({ SessionId: SESSION_ID });
  return request(app).post('/liveness/sessions').set(auth(token)).send({});
}

beforeEach(() => {
  rekognition.reset();
  sts.reset();
  sts.on(AssumeRoleCommand).resolves({
    Credentials: {
      AccessKeyId: 'ASIAEXAMPLEEXAMPLE',
      SecretAccessKey: SECRET,
      SessionToken: SESSION_TOKEN,
      Expiration: new Date('2030-01-01T00:15:00Z'),
    },
  });
});

describe('authentication', () => {
  it.each([
    ['no header', {}],
    ['wrong token', auth('c'.repeat(40))],
    ['wrong scheme', { Authorization: `Basic ${TOKEN_A}` }],
    ['empty bearer', { Authorization: 'Bearer ' }],
  ])('rejects %s with 401', async (_name, headers) => {
    const res = await request(build()).post('/liveness/sessions').set(headers).send({});

    expect(res.status).toBe(401);
    expect(res.headers['www-authenticate']).toBe('Bearer');
    expect(rekognition.calls()).toHaveLength(0);
  });

  it('answers unknown routes with 404 after auth', async () => {
    const res = await request(build()).get('/nope').set(auth());

    expect(res.status).toBe(404);
  });
});

describe('POST /liveness/sessions', () => {
  it('creates a session with the configured challenge and audit limit', async () => {
    const res = await createSession(build({ auditImagesLimit: 2 }));

    expect(res.status).toBe(201);
    expect(res.body).toEqual({ sessionId: SESSION_ID, region: 'eu-west-1', challenge: 'FaceMovementChallenge' });
    const input = rekognition.commandCalls(CreateFaceLivenessSessionCommand)[0]?.args[0].input;
    expect(input?.Settings?.ChallengePreferences).toEqual([{ Type: 'FaceMovementChallenge' }]);
    expect(input?.Settings?.AuditImagesLimit).toBe(2);
    expect(input?.Settings?.OutputConfig).toBeUndefined();
    expect(input?.ClientRequestToken).toMatch(/^[0-9a-f-]{36}$/);
  });

  it('adds the S3 output when configured', async () => {
    await createSession(build({ s3Output: { bucket: 'audit-bucket', keyPrefix: 'liveness/' } }));

    const input = rekognition.commandCalls(CreateFaceLivenessSessionCommand)[0]?.args[0].input;
    expect(input?.Settings?.OutputConfig).toEqual({ S3Bucket: 'audit-bucket', S3KeyPrefix: 'liveness/' });
  });

  it('rejects a client challenge unless allowed', async () => {
    rekognition.on(CreateFaceLivenessSessionCommand).resolves({ SessionId: SESSION_ID });

    const res = await request(build())
      .post('/liveness/sessions')
      .set(auth())
      .send({ challenge: 'FaceMovementAndLightChallenge' });

    expect(res.status).toBe(400);
    expect(bodyOf(res).error).toBe('challenge_not_allowed');
    expect(rekognition.calls()).toHaveLength(0);
  });

  it('accepts a known client challenge when allowed', async () => {
    rekognition.on(CreateFaceLivenessSessionCommand).resolves({ SessionId: SESSION_ID });

    const res = await request(build({ allowClientChallenge: true }))
      .post('/liveness/sessions')
      .set(auth())
      .send({ challenge: 'FaceMovementAndLightChallenge' });

    expect(res.status).toBe(201);
    const input = rekognition.commandCalls(CreateFaceLivenessSessionCommand)[0]?.args[0].input;
    expect(input?.Settings?.ChallengePreferences).toEqual([{ Type: 'FaceMovementAndLightChallenge' }]);
  });

  it('rejects an unknown client challenge', async () => {
    const res = await request(build({ allowClientChallenge: true }))
      .post('/liveness/sessions')
      .set(auth())
      .send({ challenge: 'Anything' });

    expect(res.status).toBe(400);
    expect(bodyOf(res).error).toBe('invalid_challenge');
  });

  it('rejects malformed JSON', async () => {
    const res = await request(build())
      .post('/liveness/sessions')
      .set(auth())
      .set('Content-Type', 'application/json')
      .send('{');

    expect(res.status).toBe(400);
    expect(bodyOf(res).error).toBe('invalid_body');
  });

  it.each([
    [new ThrottlingException({ message: 'slow down', $metadata: {} }), 503, 'throttled'],
    [new AccessDeniedException({ message: 'denied', $metadata: {} }), 502, 'upstream_access_denied'],
    [new Error('boom'), 502, 'upstream_error'],
  ])('maps AWS errors without leaking messages (%#)', async (error, status, code) => {
    rekognition.on(CreateFaceLivenessSessionCommand).rejects(error);

    const res = await request(build()).post('/liveness/sessions').set(auth()).send({});

    expect(res.status).toBe(status);
    expect(res.body).toEqual({ error: code });
  });
});

describe('POST /liveness/credentials', () => {
  it('assumes the role with a liveness-only policy for 900 seconds', async () => {
    const app = build();
    await createSession(app);

    const res = await request(app).post('/liveness/credentials').set(auth()).send({ sessionId: SESSION_ID });

    expect(res.status).toBe(200);
    expect(res.headers['cache-control']).toBe('no-store');
    expect(res.body).toEqual({
      accessKeyId: 'ASIAEXAMPLEEXAMPLE',
      secretAccessKey: SECRET,
      sessionToken: SESSION_TOKEN,
      expiration: '2030-01-01T00:15:00.000Z',
    });

    const input = sts.commandCalls(AssumeRoleCommand)[0]?.args[0].input;
    expect(input?.RoleArn).toBe('arn:aws:iam::123456789012:role/liveness-client');
    expect(input?.DurationSeconds).toBe(CREDENTIALS_DURATION_SECONDS);
    expect(CREDENTIALS_DURATION_SECONDS).toBeLessThanOrEqual(900);
    expect(input?.RoleSessionName).toMatch(/^[\w+=,.@-]{2,64}$/);
    expect(JSON.parse(input?.Policy ?? '{}')).toEqual({
      Version: '2012-10-17',
      Statement: [{ Effect: 'Allow', Action: 'rekognition:StartFaceLivenessSession', Resource: '*' }],
    });
  });

  it('only serves the caller that created the session', async () => {
    const app = build();
    await createSession(app, TOKEN_A);

    const res = await request(app).post('/liveness/credentials').set(auth(TOKEN_B)).send({ sessionId: SESSION_ID });

    expect(res.status).toBe(404);
    expect(sts.calls()).toHaveLength(0);
  });

  it('rejects an unknown session', async () => {
    const res = await request(build())
      .post('/liveness/credentials')
      .set(auth())
      .send({ sessionId: OTHER_SESSION_ID });

    expect(res.status).toBe(404);
  });

  it.each([undefined, 'not-a-uuid', 42, `${SESSION_ID}/../x`])('rejects session id %s', async (sessionId) => {
    const res = await request(build()).post('/liveness/credentials').set(auth()).send({ sessionId });

    expect(res.status).toBe(400);
    expect(bodyOf(res).error).toBe('invalid_session_id');
  });

  it('fails closed when STS returns incomplete credentials', async () => {
    const app = build();
    await createSession(app);
    sts.on(AssumeRoleCommand).resolves({ Credentials: undefined });

    const res = await request(app).post('/liveness/credentials').set(auth()).send({ sessionId: SESSION_ID });

    expect(res.status).toBe(502);
  });

  it('maps STS failures', async () => {
    const app = build();
    await createSession(app);
    sts.on(AssumeRoleCommand).rejects(new Error('AccessDenied'));

    const res = await request(app).post('/liveness/credentials').set(auth()).send({ sessionId: SESSION_ID });

    expect(res.status).toBe(502);
    expect(res.body).toEqual({ error: 'upstream_error' });
  });
});

describe('GET /liveness/sessions/:id/result', () => {
  async function result(output: object, threshold = 80) {
    const app = build({ confidenceThreshold: threshold });
    await createSession(app);
    rekognition.on(GetFaceLivenessSessionResultsCommand).resolves(output);
    return request(app).get(`/liveness/sessions/${SESSION_ID}/result`).set(auth());
  }

  it('decides isLive on the server from the configured threshold', async () => {
    const live = await result({ Status: 'SUCCEEDED', Confidence: 80 });
    const notLive = await result({ Status: 'SUCCEEDED', Confidence: 79.99 });

    expect(live.body).toEqual({ sessionId: SESSION_ID, status: 'SUCCEEDED', isLive: true, confidence: 80 });
    expect(bodyOf(notLive).isLive).toBe(false);
  });

  it('ignores a threshold sent by the client', async () => {
    const app = build({ confidenceThreshold: 90 });
    await createSession(app);
    rekognition.on(GetFaceLivenessSessionResultsCommand).resolves({ Status: 'SUCCEEDED', Confidence: 50 });

    const res = await request(app).get(`/liveness/sessions/${SESSION_ID}/result?threshold=10`).set(auth());

    expect(bodyOf(res).isLive).toBe(false);
  });

  it.each(['CREATED', 'IN_PROGRESS', 'FAILED', 'EXPIRED'])('is never live when status is %s', async (status) => {
    const res = await result({ Status: status, Confidence: 99 });

    expect(bodyOf(res).isLive).toBe(false);
    expect(bodyOf(res).status).toBe(status);
  });

  it('never returns images', async () => {
    const res = await result({
      Status: 'SUCCEEDED',
      Confidence: 95,
      ReferenceImage: { Bytes: new Uint8Array([1, 2, 3]) },
      AuditImages: [{ Bytes: new Uint8Array([4, 5, 6]) }],
    });

    expect(Object.keys(bodyOf(res)).sort()).toEqual(['confidence', 'isLive', 'sessionId', 'status']);
    expect(res.headers['cache-control']).toBe('no-store');
  });

  it('reports a missing confidence as null', async () => {
    const res = await result({ Status: 'FAILED' });

    expect(bodyOf(res).confidence).toBeNull();
  });

  it('rejects reads from another caller', async () => {
    const app = build();
    await createSession(app, TOKEN_A);

    const res = await request(app).get(`/liveness/sessions/${SESSION_ID}/result`).set(auth(TOKEN_B));

    expect(res.status).toBe(404);
    expect(rekognition.commandCalls(GetFaceLivenessSessionResultsCommand)).toHaveLength(0);
  });

  it('rejects an invalid session id', async () => {
    const res = await request(build()).get('/liveness/sessions/abc/result').set(auth());

    expect(res.status).toBe(400);
  });

  it('maps a session AWS no longer knows to 404', async () => {
    const app = build();
    await createSession(app);
    rekognition
      .on(GetFaceLivenessSessionResultsCommand)
      .rejects(new SessionNotFoundException({ message: 'gone', $metadata: {} }));

    const res = await request(app).get(`/liveness/sessions/${SESSION_ID}/result`).set(auth());

    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: 'session_not_found' });
  });
});

describe('rate limit', () => {
  it('answers 429 with Retry-After once the limit is exceeded', async () => {
    const app = build({ rateLimitPerMinute: 2 });

    const statuses = [];
    for (let i = 0; i < 3; i += 1) {
      statuses.push((await request(app).get('/nope').set(auth())).status);
    }
    const limited = await request(app).get('/nope').set(auth());

    expect(statuses).toEqual([404, 404, 429]);
    expect(limited.headers['retry-after']).toMatch(/^\d+$/);
  });

  it('also limits unauthenticated callers', async () => {
    const app = build({ rateLimitPerMinute: 1 });

    await request(app).get('/nope');
    const res = await request(app).get('/nope');

    expect(res.status).toBe(429);
  });
});

describe('logging', () => {
  it('never logs credentials, tokens or bodies', async () => {
    const lines: string[] = [];
    const app = build({}, (entry) => lines.push(JSON.stringify(entry)));
    await createSession(app);
    await request(app).post('/liveness/credentials').set(auth()).send({ sessionId: SESSION_ID });

    const logged = lines.join('\n');
    expect(lines.length).toBeGreaterThan(0);
    for (const secret of [TOKEN_A, SECRET, SESSION_TOKEN, 'ASIAEXAMPLEEXAMPLE']) {
      expect(logged).not.toContain(secret);
    }
  });
});
