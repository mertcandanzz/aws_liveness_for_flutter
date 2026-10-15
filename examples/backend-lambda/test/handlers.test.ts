import { createHash } from 'node:crypto';
import {
  ConditionalCheckFailedException,
  DynamoDBClient,
  GetItemCommand,
  PutItemCommand,
  UpdateItemCommand,
} from '@aws-sdk/client-dynamodb';
import {
  CreateFaceLivenessSessionCommand,
  GetFaceLivenessSessionResultsCommand,
  RekognitionClient,
  SessionNotFoundException,
  ThrottlingException,
} from '@aws-sdk/client-rekognition';
import { AssumeRoleCommand, STSClient } from '@aws-sdk/client-sts';
import type { APIGatewayRequestAuthorizerEventV2 } from 'aws-lambda';
import { mockClient } from 'aws-sdk-client-mock';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createAuthorizer } from '../src/handlers/authorizer.js';
import { createSessionHandler } from '../src/handlers/createSession.js';
import { credentialsHandler } from '../src/handlers/credentials.js';
import { getResultHandler } from '../src/handlers/getResult.js';
import { ConfigError, sessionSettings, tokenDigests, type SessionSettings } from '../src/lib/config.js';
import type { AuthorizedEvent, HttpResult } from '../src/lib/http.js';
import { CREDENTIALS_DURATION_SECONDS } from '../src/lib/policy.js';
import { SESSION_TTL_SECONDS, SessionTable } from '../src/lib/sessions.js';

const SESSION_ID = '0f1e2d3c-4b5a-4968-8776-655443322110';
const CALLER = 'caller-a';
const NOW = 1_800_000_000;
const SECRET = 'example-secret-access-key-value';
const SESSION_TOKEN = 'example-session-token-value';

const rekognition = mockClient(RekognitionClient);
const sts = mockClient(STSClient);
const dynamo = mockClient(DynamoDBClient);

const table = () => new SessionTable(new DynamoDBClient({}), 'sessions', () => NOW);

function event(overrides: Partial<AuthorizedEvent> = {}, callerId = CALLER): AuthorizedEvent {
  return {
    version: '2.0',
    routeKey: 'route',
    rawPath: '/',
    rawQueryString: '',
    headers: {},
    isBase64Encoded: false,
    requestContext: {
      accountId: '123456789012',
      apiId: 'api',
      domainName: 'example.com',
      domainPrefix: 'example',
      http: { method: 'POST', path: '/', protocol: 'HTTP/1.1', sourceIp: '192.0.2.1', userAgent: 'test' },
      requestId: 'request',
      routeKey: 'route',
      stage: '$default',
      time: '',
      timeEpoch: 0,
      authorizer: { lambda: { callerId } },
    },
    ...overrides,
  };
}

const bodyOf = (result: HttpResult): Record<string, unknown> =>
  JSON.parse(result.body ?? '{}') as Record<string, unknown>;

function ownedItem(owner = CALLER, extra: Record<string, { N: string }> = {}) {
  return {
    Item: {
      sessionId: { S: SESSION_ID },
      owner: { S: owner },
      createdAt: { N: String(NOW) },
      expiresAt: { N: String(NOW + SESSION_TTL_SECONDS) },
      ...extra,
    },
  };
}

const settings = (overrides: Partial<SessionSettings> = {}): SessionSettings => ({
  defaultChallenge: 'FaceMovementChallenge',
  allowClientChallenge: false,
  auditImagesLimit: 0,
  ...overrides,
});

beforeEach(() => {
  rekognition.reset();
  sts.reset();
  dynamo.reset();
  vi.restoreAllMocks();
});

describe('createSession', () => {
  const handler = (s = settings()) =>
    createSessionHandler({ rekognition: new RekognitionClient({}), sessions: table(), settings: s, region: 'eu-west-1' });

  it('creates a FaceMovement session with no audit images and binds it to the caller', async () => {
    rekognition.on(CreateFaceLivenessSessionCommand).resolves({ SessionId: SESSION_ID });
    dynamo.on(PutItemCommand).resolves({});

    const res = await handler()(event());

    expect(res.statusCode).toBe(201);
    expect(bodyOf(res)).toEqual({ sessionId: SESSION_ID, region: 'eu-west-1', challenge: 'FaceMovementChallenge' });
    const input = rekognition.commandCalls(CreateFaceLivenessSessionCommand)[0]?.args[0].input;
    expect(input?.Settings?.ChallengePreferences).toEqual([{ Type: 'FaceMovementChallenge' }]);
    expect(input?.Settings?.AuditImagesLimit).toBe(0);
    expect(input?.Settings?.OutputConfig).toBeUndefined();
    const put = dynamo.commandCalls(PutItemCommand)[0]?.args[0].input;
    expect(put?.Item?.owner).toEqual({ S: CALLER });
    expect(put?.Item?.expiresAt).toEqual({ N: String(NOW + SESSION_TTL_SECONDS) });
    expect(put?.ConditionExpression).toBe('attribute_not_exists(sessionId)');
  });

  it('adds the S3 output when configured', async () => {
    rekognition.on(CreateFaceLivenessSessionCommand).resolves({ SessionId: SESSION_ID });
    dynamo.on(PutItemCommand).resolves({});

    await handler(settings({ s3Output: { bucket: 'audit', keyPrefix: 'liveness/' } }))(event());

    const input = rekognition.commandCalls(CreateFaceLivenessSessionCommand)[0]?.args[0].input;
    expect(input?.Settings?.OutputConfig).toEqual({ S3Bucket: 'audit', S3KeyPrefix: 'liveness/' });
  });

  it('rejects a client challenge unless allowed', async () => {
    const res = await handler()(event({ body: JSON.stringify({ challenge: 'FaceMovementAndLightChallenge' }) }));

    expect(res.statusCode).toBe(400);
    expect(bodyOf(res).error).toBe('challenge_not_allowed');
    expect(rekognition.calls()).toHaveLength(0);
  });

  it('accepts a known challenge when allowed and rejects unknown ones', async () => {
    rekognition.on(CreateFaceLivenessSessionCommand).resolves({ SessionId: SESSION_ID });
    dynamo.on(PutItemCommand).resolves({});
    const allowed = handler(settings({ allowClientChallenge: true }));

    const ok = await allowed(event({ body: JSON.stringify({ challenge: 'FaceMovementAndLightChallenge' }) }));
    const bad = await allowed(event({ body: JSON.stringify({ challenge: 'Other' }) }));

    expect(ok.statusCode).toBe(201);
    expect(bodyOf(ok).challenge).toBe('FaceMovementAndLightChallenge');
    expect(bad.statusCode).toBe(400);
  });

  it.each(['{', '[1]', 'x'.repeat(5000)])('rejects an invalid body %#', async (body) => {
    const res = await handler()(event({ body }));

    expect(res.statusCode).toBe(400);
    expect(bodyOf(res).error).toBe('invalid_body');
  });

  it('decodes a base64 body', async () => {
    const res = await handler()(
      event({ body: Buffer.from(JSON.stringify({ challenge: 'X' })).toString('base64'), isBase64Encoded: true }),
    );

    expect(bodyOf(res).error).toBe('challenge_not_allowed');
  });

  it('refuses requests without a caller id', async () => {
    const res = await handler()(event({}, ''));

    expect(res.statusCode).toBe(401);
  });

  it.each([
    [new ThrottlingException({ message: 'slow down', $metadata: {} }), 503, 'throttled'],
    [new Error('boom'), 502, 'upstream_error'],
  ])('maps AWS errors without leaking messages (%#)', async (error, status, code) => {
    rekognition.on(CreateFaceLivenessSessionCommand).rejects(error);

    const res = await handler()(event());

    expect(res.statusCode).toBe(status);
    expect(bodyOf(res)).toEqual({ error: code });
  });
});

describe('credentials', () => {
  const handler = () =>
    credentialsHandler({
      sts: new STSClient({}),
      sessions: table(),
      roleArn: 'arn:aws:iam::123456789012:role/liveness-client',
      now: () => NOW * 1000,
    });
  const body = JSON.stringify({ sessionId: SESSION_ID });

  beforeEach(() => {
    sts.on(AssumeRoleCommand).resolves({
      Credentials: {
        AccessKeyId: 'ASIAEXAMPLEEXAMPLE',
        SecretAccessKey: SECRET,
        SessionToken: SESSION_TOKEN,
        Expiration: new Date('2030-01-01T00:15:00Z'),
      },
    });
  });

  it('assumes the role with a liveness-only policy for 900 seconds', async () => {
    dynamo.on(GetItemCommand).resolves(ownedItem());

    const res = await handler()(event({ body }));

    expect(res.statusCode).toBe(200);
    expect(res.headers?.['cache-control']).toBe('no-store');
    expect(bodyOf(res)).toEqual({
      accessKeyId: 'ASIAEXAMPLEEXAMPLE',
      secretAccessKey: SECRET,
      sessionToken: SESSION_TOKEN,
      expiration: '2030-01-01T00:15:00.000Z',
    });
    const input = sts.commandCalls(AssumeRoleCommand)[0]?.args[0].input;
    expect(input?.DurationSeconds).toBe(CREDENTIALS_DURATION_SECONDS);
    expect(CREDENTIALS_DURATION_SECONDS).toBe(900);
    expect(input?.RoleSessionName).toMatch(/^[\w+=,.@-]{2,64}$/);
    expect(JSON.parse(input?.Policy ?? '{}')).toEqual({
      Version: '2012-10-17',
      Statement: [{ Effect: 'Allow', Action: 'rekognition:StartFaceLivenessSession', Resource: '*' }],
    });
    expect(dynamo.commandCalls(GetItemCommand)[0]?.args[0].input.ConsistentRead).toBe(true);
  });

  it.each([
    ['another caller', ownedItem('caller-b')],
    ['an unknown session', { Item: undefined }],
    ['an expired session', ownedItem(CALLER, { expiresAt: { N: String(NOW) } })],
    ['a consumed session', ownedItem(CALLER, { consumedAt: { N: String(NOW) } })],
  ])('refuses %s', async (_name, item) => {
    dynamo.on(GetItemCommand).resolves(item);

    const res = await handler()(event({ body }));

    expect(res.statusCode).toBe(404);
    expect(sts.calls()).toHaveLength(0);
  });

  it('rejects a malformed session id', async () => {
    const res = await handler()(event({ body: JSON.stringify({ sessionId: '../x' }) }));

    expect(res.statusCode).toBe(400);
    expect(dynamo.calls()).toHaveLength(0);
  });

  it('fails closed on incomplete STS credentials and on STS errors', async () => {
    dynamo.on(GetItemCommand).resolves(ownedItem());
    sts.on(AssumeRoleCommand).resolvesOnce({ Credentials: undefined }).rejectsOnce(new Error('AccessDenied'));

    const incomplete = await handler()(event({ body }));
    const failed = await handler()(event({ body }));

    expect(incomplete.statusCode).toBe(502);
    expect(bodyOf(failed)).toEqual({ error: 'upstream_error' });
  });

  it('maps a DynamoDB failure without leaking it', async () => {
    dynamo.on(GetItemCommand).rejects(new Error('table missing'));

    const res = await handler()(event({ body }));

    expect(bodyOf(res)).toEqual({ error: 'upstream_error' });
  });

  it('never logs credentials or tokens', async () => {
    const lines: string[] = [];
    for (const method of ['log', 'info', 'warn', 'error', 'debug'] as const) {
      vi.spyOn(console, method).mockImplementation((...args: unknown[]) => lines.push(args.join(' ')));
    }
    dynamo.on(GetItemCommand).resolves(ownedItem());
    await handler()(event({ body, headers: { authorization: 'Bearer secret-token' } }));
    dynamo.on(GetItemCommand).rejects(new Error(SECRET));
    await handler()(event({ body }));

    const logged = lines.join('\n');
    for (const secret of [SECRET, SESSION_TOKEN, 'ASIAEXAMPLEEXAMPLE', 'secret-token']) {
      expect(logged).not.toContain(secret);
    }
  });
});

describe('getResult', () => {
  const handler = (threshold = 80) =>
    getResultHandler({ rekognition: new RekognitionClient({}), sessions: table(), threshold });
  const resultEvent = (sessionId = SESSION_ID) => event({ pathParameters: { sessionId } });

  it('decides isLive on the server and consumes the final result once', async () => {
    dynamo.on(GetItemCommand).resolves(ownedItem());
    dynamo.on(UpdateItemCommand).resolves({});
    rekognition.on(GetFaceLivenessSessionResultsCommand).resolves({
      Status: 'SUCCEEDED',
      Confidence: 80,
      ReferenceImage: { Bytes: new Uint8Array([1]) },
      AuditImages: [{ Bytes: new Uint8Array([2]) }],
    });

    const res = await handler()(resultEvent());

    expect(bodyOf(res)).toEqual({ sessionId: SESSION_ID, status: 'SUCCEEDED', isLive: true, confidence: 80 });
    expect(res.headers?.['cache-control']).toBe('no-store');
    const update = dynamo.commandCalls(UpdateItemCommand)[0]?.args[0].input;
    expect(update?.ConditionExpression).toBe('#owner = :caller AND attribute_not_exists(consumedAt)');
    expect(update?.ExpressionAttributeValues?.[':caller']).toEqual({ S: CALLER });
  });

  it('is not live below the threshold, and ignores a client threshold', async () => {
    dynamo.on(GetItemCommand).resolves(ownedItem());
    dynamo.on(UpdateItemCommand).resolves({});
    rekognition.on(GetFaceLivenessSessionResultsCommand).resolves({ Status: 'SUCCEEDED', Confidence: 89.9 });

    const res = await handler(90)(
      event({ pathParameters: { sessionId: SESSION_ID }, queryStringParameters: { threshold: '1' } }),
    );

    expect(bodyOf(res).isLive).toBe(false);
  });

  it.each(['FAILED', 'EXPIRED'] as const)('is never live when status is %s', async (status) => {
    dynamo.on(GetItemCommand).resolves(ownedItem());
    dynamo.on(UpdateItemCommand).resolves({});
    rekognition.on(GetFaceLivenessSessionResultsCommand).resolves({ Status: status, Confidence: 99 });

    const res = await handler()(resultEvent());

    expect(bodyOf(res).isLive).toBe(false);
  });

  it('does not consume a result that is still in progress', async () => {
    dynamo.on(GetItemCommand).resolves(ownedItem());
    rekognition.on(GetFaceLivenessSessionResultsCommand).resolves({ Status: 'IN_PROGRESS' });

    const res = await handler()(resultEvent());

    expect(bodyOf(res)).toEqual({ sessionId: SESSION_ID, status: 'IN_PROGRESS', isLive: false, confidence: null });
    expect(dynamo.commandCalls(UpdateItemCommand)).toHaveLength(0);
  });

  it('answers 409 when the result was already consumed', async () => {
    dynamo.on(GetItemCommand).resolves(ownedItem(CALLER, { consumedAt: { N: String(NOW) } }));

    const res = await handler()(resultEvent());

    expect(res.statusCode).toBe(409);
    expect(rekognition.calls()).toHaveLength(0);
  });

  it('answers 409 to the loser of a concurrent read', async () => {
    dynamo.on(GetItemCommand).resolves(ownedItem());
    dynamo.on(UpdateItemCommand).rejects(new ConditionalCheckFailedException({ message: 'x', $metadata: {} }));
    rekognition.on(GetFaceLivenessSessionResultsCommand).resolves({ Status: 'SUCCEEDED', Confidence: 99 });

    const res = await handler()(resultEvent());

    expect(res.statusCode).toBe(409);
    expect(bodyOf(res).error).toBe('result_already_consumed');
  });

  it('rejects reads from another caller', async () => {
    dynamo.on(GetItemCommand).resolves(ownedItem('caller-b'));

    const res = await handler()(resultEvent());

    expect(res.statusCode).toBe(404);
    expect(rekognition.calls()).toHaveLength(0);
  });

  it('rejects an invalid session id and maps a session AWS no longer knows', async () => {
    const invalid = await handler()(resultEvent('abc'));
    dynamo.on(GetItemCommand).resolves(ownedItem());
    rekognition
      .on(GetFaceLivenessSessionResultsCommand)
      .rejects(new SessionNotFoundException({ message: 'gone', $metadata: {} }));
    const gone = await handler()(resultEvent());

    expect(invalid.statusCode).toBe(400);
    expect(gone.statusCode).toBe(404);
  });
});

describe('authorizer', () => {
  const token = 'a'.repeat(43);
  const other = 'b'.repeat(43);
  const digest = (t: string) => createHash('sha256').update(t).digest('hex');
  const authorize = createAuthorizer([digest(token), digest(other)]);
  const request = (authorization?: string) =>
    ({ headers: authorization === undefined ? {} : { authorization } }) as unknown as APIGatewayRequestAuthorizerEventV2;

  it('authorizes a configured token with a stable caller id', async () => {
    const a = await authorize(request(`Bearer ${token}`));
    const b = await authorize(request(`Bearer ${other}`));

    expect(a.isAuthorized).toBe(true);
    expect(a.context.callerId).toMatch(/^[0-9a-f]{16}$/);
    expect(b.context.callerId).not.toBe(a.context.callerId);
    expect((await authorize(request(`Bearer ${token}`))).context.callerId).toBe(a.context.callerId);
  });

  it.each([undefined, '', `Basic ${token}`, 'Bearer ', `Bearer ${'c'.repeat(43)}`])(
    'denies %s',
    async (authorization) => {
      expect((await authorize(request(authorization))).isAuthorized).toBe(false);
    },
  );
});

describe('config', () => {
  it('reads safe defaults', () => {
    expect(sessionSettings({})).toEqual({
      defaultChallenge: 'FaceMovementChallenge',
      allowClientChallenge: false,
      auditImagesLimit: 0,
      s3Output: undefined,
    });
  });

  it.each([
    [{ LIVENESS_CHALLENGE: 'Other' }],
    [{ LIVENESS_AUDIT_IMAGES_LIMIT: '5' }],
  ])('rejects invalid session settings %#', (env) => {
    expect(() => sessionSettings(env)).toThrow(ConfigError);
  });

  it('accepts only SHA-256 hex token digests', () => {
    expect(tokenDigests({ API_TOKEN_SHA256: `${'A'.repeat(64)}, ${'b'.repeat(64)}` })).toHaveLength(2);
    expect(() => tokenDigests({ API_TOKEN_SHA256: 'plain-token' })).toThrow(ConfigError);
    expect(() => tokenDigests({})).toThrow(ConfigError);
  });
});
