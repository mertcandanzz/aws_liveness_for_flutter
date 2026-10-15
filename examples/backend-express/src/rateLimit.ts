import type { NextFunction, Request, Response } from 'express';

const WINDOW_MS = 60_000;

/**
 * Fixed-window, in-memory rate limit per client IP. Good enough for an
 * example; use a shared store (for example Redis) behind a load balancer.
 */
export function rateLimit(limitPerMinute: number, now: () => number = Date.now) {
  const windows = new Map<string, { start: number; count: number }>();

  return (req: Request, res: Response, next: NextFunction): void => {
    const time = now();
    const key = req.ip ?? 'unknown';
    const current = windows.get(key);
    const window = current && time - current.start < WINDOW_MS ? current : { start: time, count: 0 };
    window.count += 1;
    windows.set(key, window);

    if (windows.size > 10_000) {
      for (const [k, w] of windows) if (time - w.start >= WINDOW_MS) windows.delete(k);
    }

    if (window.count > limitPerMinute) {
      const retryAfter = Math.ceil((window.start + WINDOW_MS - time) / 1000);
      res.status(429).set('Retry-After', String(retryAfter)).json({ error: 'rate_limited' });
      return;
    }
    next();
  };
}
