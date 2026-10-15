import { randomUUID } from 'node:crypto';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { CreateFaceLivenessSessionCommand, RekognitionClient } from '@aws-sdk/client-rekognition';
import { CHALLENGE_TYPES, sessionSettings, tableName, type ChallengeType, type SessionSettings } from '../lib/config.js';
import {
  callerIdOf,
  HttpError,
  json,
  parseBody,
  respond,
  sessionIdFrom,
  upstreamError,
  type AuthorizedEvent,
  type HttpResult,
} from '../lib/http.js';
import { SessionTable } from '../lib/sessions.js';

export interface CreateSessionDeps {
  rekognition: Pick<RekognitionClient, 'send'>;
  sessions: SessionTable;
  settings: SessionSettings;
  region: string;
}

/** `POST /liveness/sessions`: creates a session and binds it to the caller. */
export function createSessionHandler({ rekognition, sessions, settings, region }: CreateSessionDeps) {
  return (event: AuthorizedEvent): Promise<HttpResult> =>
    respond(async () => {
      const callerId = callerIdOf(event);
      const requested = parseBody(event).challenge;
      let challenge: ChallengeType = settings.defaultChallenge;
      if (requested !== undefined) {
        if (!settings.allowClientChallenge) throw new HttpError(400, 'challenge_not_allowed');
        if (!CHALLENGE_TYPES.includes(requested as ChallengeType)) throw new HttpError(400, 'invalid_challenge');
        challenge = requested as ChallengeType;
      }

      const output = settings.s3Output;
      const created = await rekognition
        .send(
          new CreateFaceLivenessSessionCommand({
            ClientRequestToken: randomUUID(),
            Settings: {
              AuditImagesLimit: settings.auditImagesLimit,
              ChallengePreferences: [{ Type: challenge }],
              ...(output ? { OutputConfig: { S3Bucket: output.bucket, S3KeyPrefix: output.keyPrefix } } : {}),
            },
          }),
        )
        .catch((error: unknown) => {
          throw upstreamError(error);
        });

      const sessionId = sessionIdFrom(created.SessionId);
      await sessions.bind(sessionId, callerId).catch((error: unknown) => {
        throw upstreamError(error);
      });
      return json(201, { sessionId, region, challenge });
    });
}

let handlerInstance: ReturnType<typeof createSessionHandler> | undefined;

export const handler = (event: AuthorizedEvent): Promise<HttpResult> => {
  handlerInstance ??= createSessionHandler({
    rekognition: new RekognitionClient({}),
    sessions: new SessionTable(new DynamoDBClient({}), tableName(process.env)),
    settings: sessionSettings(process.env),
    region: process.env.AWS_REGION ?? '',
  });
  return handlerInstance(event);
};
