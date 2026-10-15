import { randomUUID } from 'node:crypto';
import express, { type NextFunction, type Request, type Response } from 'express';
import {
  CreateFaceLivenessSessionCommand,
  GetFaceLivenessSessionResultsCommand,
  type RekognitionClient,
} from '@aws-sdk/client-rekognition';
import { AssumeRoleCommand, type STSClient } from '@aws-sdk/client-sts';
import { bearerAuth } from './auth.js';
import { CHALLENGE_TYPES, type ChallengeType, type Config } from './config.js';
import { CREDENTIALS_DURATION_SECONDS, livenessSessionPolicy } from './policy.js';
import { rateLimit } from './rateLimit.js';
import { SessionStore } from './sessionStore.js';

/** Structured log line. Callers must never put credentials, tokens or images here. */
export type Logger = (entry: Readonly<Record<string, string | number>>) => void;

export interface AppDeps {
  config: Config;
  rekognition: Pick<RekognitionClient, 'send'>;
  sts: Pick<STSClient, 'send'>;
  log?: Logger;
  now?: () => number;
}

const SESSION_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
  ) {
    super(code);
  }
}

function sessionIdFrom(value: unknown): string {
  if (typeof value !== 'string' || !SESSION_ID_PATTERN.test(value)) {
    throw new HttpError(400, 'invalid_session_id');
  }
  return value;
}

/** Maps AWS SDK errors to responses without exposing their messages. */
function upstreamError(error: unknown): HttpError {
  const name = error instanceof Error ? error.name : '';
  switch (name) {
    case 'SessionNotFoundException':
      return new HttpError(404, 'session_not_found');
    case 'ThrottlingException':
    case 'ProvisionedThroughputExceededException':
    case 'LimitExceededException':
      return new HttpError(503, 'throttled');
    case 'AccessDeniedException':
      return new HttpError(502, 'upstream_access_denied');
    default:
      return new HttpError(502, 'upstream_error');
  }
}

export function createApp({ config, rekognition, sts, log = () => {}, now = Date.now }: AppDeps) {
  const sessions = new SessionStore(now);
  const app = express();
  app.disable('x-powered-by');

  app.use((req: Request, res: Response, next: NextFunction) => {
    const start = now();
    res.on('finish', () => {
      // Method, path and status only: never headers or bodies.
      log({ event: 'request', method: req.method, path: req.path, status: res.statusCode, ms: now() - start });
    });
    next();
  });
  app.use(rateLimit(config.rateLimitPerMinute, now));
  app.use(bearerAuth(config.apiTokens));
  app.use(express.json({ limit: '4kb' }));

  app.post('/liveness/sessions', async (req: Request, res: Response) => {
    const requested = (req.body as { challenge?: unknown } | undefined)?.challenge;
    let challenge: ChallengeType = config.defaultChallenge;
    if (requested !== undefined) {
      if (!config.allowClientChallenge) throw new HttpError(400, 'challenge_not_allowed');
      if (!CHALLENGE_TYPES.includes(requested as ChallengeType)) throw new HttpError(400, 'invalid_challenge');
      challenge = requested as ChallengeType;
    }

    const output = config.s3Output;
    const created = await rekognition
      .send(
        new CreateFaceLivenessSessionCommand({
          ClientRequestToken: randomUUID(),
          Settings: {
            AuditImagesLimit: config.auditImagesLimit,
            ChallengePreferences: [{ Type: challenge }],
            ...(output ? { OutputConfig: { S3Bucket: output.bucket, S3KeyPrefix: output.keyPrefix } } : {}),
          },
        }),
      )
      .catch((error: unknown) => {
        throw upstreamError(error);
      });

    const sessionId = sessionIdFrom(created.SessionId);
    sessions.bind(sessionId, res.locals.callerId ?? '');
    res.status(201).json({ sessionId, region: config.region, challenge });
  });

  app.post('/liveness/credentials', async (req: Request, res: Response) => {
    const callerId = res.locals.callerId ?? '';
    const sessionId = sessionIdFrom((req.body as { sessionId?: unknown } | undefined)?.sessionId);
    if (!sessions.isOwnedBy(sessionId, callerId)) throw new HttpError(404, 'session_not_found');

    const assumed = await sts
      .send(
        new AssumeRoleCommand({
          RoleArn: config.credentialsRoleArn,
          RoleSessionName: `liveness-${callerId}-${now()}`.slice(0, 64),
          DurationSeconds: CREDENTIALS_DURATION_SECONDS,
          Policy: livenessSessionPolicy(),
        }),
      )
      .catch((error: unknown) => {
        throw upstreamError(error);
      });

    const credentials = assumed.Credentials;
    if (
      !credentials?.AccessKeyId ||
      !credentials.SecretAccessKey ||
      !credentials.SessionToken ||
      !credentials.Expiration
    ) {
      throw new HttpError(502, 'upstream_error');
    }
    res.set('Cache-Control', 'no-store').json({
      accessKeyId: credentials.AccessKeyId,
      secretAccessKey: credentials.SecretAccessKey,
      sessionToken: credentials.SessionToken,
      expiration: credentials.Expiration.toISOString(),
    });
  });

  app.get('/liveness/sessions/:sessionId/result', async (req: Request, res: Response) => {
    const sessionId = sessionIdFrom(req.params.sessionId);
    if (!sessions.isOwnedBy(sessionId, res.locals.callerId ?? '')) {
      throw new HttpError(404, 'session_not_found');
    }

    const result = await rekognition
      .send(new GetFaceLivenessSessionResultsCommand({ SessionId: sessionId }))
      .catch((error: unknown) => {
        throw upstreamError(error);
      });

    // The decision is made here, from server configuration. Reference and
    // audit images in the response are deliberately not forwarded.
    const status = result.Status ?? 'UNKNOWN';
    const confidence = typeof result.Confidence === 'number' ? result.Confidence : null;
    const isLive = status === 'SUCCEEDED' && confidence !== null && confidence >= config.confidenceThreshold;
    res.set('Cache-Control', 'no-store').json({ sessionId, status, isLive, confidence });
  });

  app.use((_req: Request, res: Response) => {
    res.status(404).json({ error: 'not_found' });
  });

  app.use((error: unknown, _req: Request, res: Response, next: NextFunction) => {
    if (res.headersSent) {
      next(error);
      return;
    }
    if (error instanceof HttpError) {
      res.status(error.status).json({ error: error.code });
      return;
    }
    const type = (error as { type?: unknown } | null)?.type;
    if (type === 'entity.parse.failed' || type === 'entity.too.large') {
      res.status(400).json({ error: 'invalid_body' });
      return;
    }
    log({ event: 'unhandled_error', name: error instanceof Error ? error.name : 'unknown' });
    res.status(500).json({ error: 'internal_error' });
  });

  return app;
}
