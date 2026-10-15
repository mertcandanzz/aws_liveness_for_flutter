import { createHash, timingSafeEqual } from 'node:crypto';
import type { NextFunction, Request, Response } from 'express';

/** Stable, non-reversible id of a caller, derived from its token. */
export type CallerId = string;

declare module 'express-serve-static-core' {
  interface Locals {
    callerId?: CallerId;
  }
}

function digest(value: string): Buffer {
  return createHash('sha256').update(value, 'utf8').digest();
}

/**
 * Returns the caller id for [presented], or undefined. Every configured token
 * is compared in constant time and the loop never exits early, so timing does
 * not reveal which token, or how much of one, matched.
 */
export function matchToken(presented: string, tokens: readonly string[]): CallerId | undefined {
  const presentedDigest = digest(presented);
  let match: CallerId | undefined;
  for (const token of tokens) {
    const tokenDigest = digest(token);
    if (timingSafeEqual(presentedDigest, tokenDigest)) {
      match = tokenDigest.toString('hex').slice(0, 16);
    }
  }
  return match;
}

/** Requires `Authorization: Bearer <token>` with one of [tokens]. */
export function bearerAuth(tokens: readonly string[]) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const header = req.get('authorization') ?? '';
    const [scheme, token] = header.split(' ');
    const callerId = scheme === 'Bearer' && token ? matchToken(token, tokens) : undefined;
    if (!callerId) {
      res.status(401).set('WWW-Authenticate', 'Bearer').json({ error: 'unauthorized' });
      return;
    }
    res.locals.callerId = callerId;
    next();
  };
}
