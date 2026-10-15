import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { GetFaceLivenessSessionResultsCommand, RekognitionClient } from '@aws-sdk/client-rekognition';
import { confidenceThreshold, tableName } from '../lib/config.js';
import {
  callerIdOf,
  HttpError,
  json,
  respond,
  sessionIdFrom,
  upstreamError,
  type AuthorizedEvent,
  type HttpResult,
} from '../lib/http.js';
import { SessionTable } from '../lib/sessions.js';

/** Statuses after which the result cannot change. */
const FINAL_STATUSES = new Set(['SUCCEEDED', 'FAILED', 'EXPIRED']);

export interface GetResultDeps {
  rekognition: Pick<RekognitionClient, 'send'>;
  sessions: SessionTable;
  threshold: number;
}

/**
 * `GET /liveness/sessions/{sessionId}/result`: the server's decision. `isLive`
 * comes from the configured threshold only; images are never returned. A
 * final result is handed out once: later reads get `409`.
 */
export function getResultHandler({ rekognition, sessions, threshold }: GetResultDeps) {
  return (event: AuthorizedEvent): Promise<HttpResult> =>
    respond(async () => {
      const callerId = callerIdOf(event);
      const sessionId = sessionIdFrom(event.pathParameters?.sessionId);
      const state = await sessions.state(sessionId, callerId).catch((error: unknown) => {
        throw upstreamError(error);
      });
      if (state === 'missing') throw new HttpError(404, 'session_not_found');
      if (state === 'consumed') throw new HttpError(409, 'result_already_consumed');

      const result = await rekognition
        .send(new GetFaceLivenessSessionResultsCommand({ SessionId: sessionId }))
        .catch((error: unknown) => {
          throw upstreamError(error);
        });

      const status = result.Status ?? 'UNKNOWN';
      if (FINAL_STATUSES.has(status)) {
        const won = await sessions.consume(sessionId, callerId).catch((error: unknown) => {
          throw upstreamError(error);
        });
        if (!won) throw new HttpError(409, 'result_already_consumed');
      }

      const confidence = typeof result.Confidence === 'number' ? result.Confidence : null;
      const isLive = status === 'SUCCEEDED' && confidence !== null && confidence >= threshold;
      return json(200, { sessionId, status, isLive, confidence }, true);
    });
}

let handlerInstance: ReturnType<typeof getResultHandler> | undefined;

export const handler = (event: AuthorizedEvent): Promise<HttpResult> => {
  handlerInstance ??= getResultHandler({
    rekognition: new RekognitionClient({}),
    sessions: new SessionTable(new DynamoDBClient({}), tableName(process.env)),
    threshold: confidenceThreshold(process.env),
  });
  return handlerInstance(event);
};
