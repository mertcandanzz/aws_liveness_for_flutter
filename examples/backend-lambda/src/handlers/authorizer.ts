import { createHash, timingSafeEqual } from 'node:crypto';
import type {
  APIGatewayRequestAuthorizerEventV2,
  APIGatewaySimpleAuthorizerWithContextResult,
} from 'aws-lambda';
import { tokenDigests } from '../lib/config.js';
import type { CallerContext } from '../lib/http.js';

export type AuthorizerResult = APIGatewaySimpleAuthorizerWithContextResult<CallerContext>;

const DENY: AuthorizerResult = { isAuthorized: false, context: { callerId: '' } };

/**
 * Lambda REQUEST authorizer (simple responses) for a static bearer token.
 *
 * The stack stores only SHA-256 digests of the accepted tokens. The presented
 * token is hashed and compared in constant time against every digest, without
 * an early exit. The caller id is derived from the digest, so sessions are
 * bound to a token without ever storing it. Replace this with a JWT authorizer
 * for real users (see README).
 */
export function createAuthorizer(digests: readonly string[]) {
  const expected = digests.map((d) => Buffer.from(d, 'hex'));
  return (event: APIGatewayRequestAuthorizerEventV2): Promise<AuthorizerResult> => {
    const header = event.headers?.authorization ?? event.headers?.Authorization ?? '';
    const [scheme, token] = header.split(' ');
    if (scheme !== 'Bearer' || !token) return Promise.resolve(DENY);

    const presented = createHash('sha256').update(token, 'utf8').digest();
    let callerId: string | undefined;
    for (const digest of expected) {
      if (timingSafeEqual(presented, digest)) callerId = digest.toString('hex').slice(0, 16);
    }
    return Promise.resolve(callerId ? { isAuthorized: true, context: { callerId } } : DENY);
  };
}

let authorizerInstance: ReturnType<typeof createAuthorizer> | undefined;

export const handler = (event: APIGatewayRequestAuthorizerEventV2): Promise<AuthorizerResult> => {
  authorizerInstance ??= createAuthorizer(tokenDigests(process.env));
  return authorizerInstance(event);
};
