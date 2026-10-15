import type {
  APIGatewayProxyEventV2WithLambdaAuthorizer,
  APIGatewayProxyStructuredResultV2,
} from 'aws-lambda';

/** Context the authorizer attaches to every authorized request. */
export interface CallerContext {
  callerId: string;
}

export type AuthorizedEvent = APIGatewayProxyEventV2WithLambdaAuthorizer<CallerContext>;
export type HttpResult = APIGatewayProxyStructuredResultV2;

export const SESSION_ID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
  ) {
    super(code);
  }
}

export function json(status: number, body: unknown, noStore = false): HttpResult {
  return {
    statusCode: status,
    headers: {
      'content-type': 'application/json',
      ...(noStore ? { 'cache-control': 'no-store' } : {}),
    },
    body: JSON.stringify(body),
  };
}

/** The caller id set by the authorizer. API Gateway never invokes a route without it. */
export function callerIdOf(event: AuthorizedEvent): string {
  const callerId = event.requestContext.authorizer?.lambda?.callerId;
  if (typeof callerId !== 'string' || callerId.length === 0) {
    throw new HttpError(401, 'unauthorized');
  }
  return callerId;
}

export function parseBody(event: AuthorizedEvent): Record<string, unknown> {
  if (!event.body) return {};
  const raw = event.isBase64Encoded ? Buffer.from(event.body, 'base64').toString('utf8') : event.body;
  if (raw.length > 4096) throw new HttpError(400, 'invalid_body');
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new HttpError(400, 'invalid_body');
  }
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    throw new HttpError(400, 'invalid_body');
  }
  return parsed as Record<string, unknown>;
}

export function sessionIdFrom(value: unknown): string {
  if (typeof value !== 'string' || !SESSION_ID_PATTERN.test(value)) {
    throw new HttpError(400, 'invalid_session_id');
  }
  return value;
}

/** Maps AWS SDK errors to responses without exposing their messages. */
export function upstreamError(error: unknown): HttpError {
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

/**
 * Runs [body] and turns errors into JSON responses. Only the error class name
 * is logged: never request bodies, headers, tokens or credentials.
 */
export async function respond(body: () => Promise<HttpResult>): Promise<HttpResult> {
  try {
    return await body();
  } catch (error) {
    if (error instanceof HttpError) return json(error.status, { error: error.code });
    console.error(JSON.stringify({ event: 'unhandled_error', name: error instanceof Error ? error.name : 'unknown' }));
    return json(500, { error: 'internal_error' });
  }
}
