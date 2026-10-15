import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { AssumeRoleCommand, STSClient } from '@aws-sdk/client-sts';
import { credentialsRoleArn, tableName } from '../lib/config.js';
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
import { CREDENTIALS_DURATION_SECONDS, livenessSessionPolicy } from '../lib/policy.js';
import { SessionTable } from '../lib/sessions.js';

export interface CredentialsDeps {
  sts: Pick<STSClient, 'send'>;
  sessions: SessionTable;
  roleArn: string;
  now?: () => number;
}

/**
 * `POST /liveness/credentials`: temporary credentials that can only call
 * `rekognition:StartFaceLivenessSession`, for 900 seconds, and only for a
 * session this caller created and has not finished.
 */
export function credentialsHandler({ sts, sessions, roleArn, now = Date.now }: CredentialsDeps) {
  return (event: AuthorizedEvent): Promise<HttpResult> =>
    respond(async () => {
      const callerId = callerIdOf(event);
      const sessionId = sessionIdFrom(parseBody(event).sessionId);
      const state = await sessions.state(sessionId, callerId).catch((error: unknown) => {
        throw upstreamError(error);
      });
      if (state !== 'owned') throw new HttpError(404, 'session_not_found');

      const assumed = await sts
        .send(
          new AssumeRoleCommand({
            RoleArn: roleArn,
            RoleSessionName: `liveness-${callerId}-${now()}`.slice(0, 64),
            DurationSeconds: CREDENTIALS_DURATION_SECONDS,
            Policy: livenessSessionPolicy(),
          }),
        )
        .catch((error: unknown) => {
          throw upstreamError(error);
        });

      const c = assumed.Credentials;
      if (!c?.AccessKeyId || !c.SecretAccessKey || !c.SessionToken || !c.Expiration) {
        throw new HttpError(502, 'upstream_error');
      }
      return json(
        200,
        {
          accessKeyId: c.AccessKeyId,
          secretAccessKey: c.SecretAccessKey,
          sessionToken: c.SessionToken,
          expiration: c.Expiration.toISOString(),
        },
        true,
      );
    });
}

let handlerInstance: ReturnType<typeof credentialsHandler> | undefined;

export const handler = (event: AuthorizedEvent): Promise<HttpResult> => {
  handlerInstance ??= credentialsHandler({
    sts: new STSClient({}),
    sessions: new SessionTable(new DynamoDBClient({}), tableName(process.env)),
    roleArn: credentialsRoleArn(process.env),
  });
  return handlerInstance(event);
};
