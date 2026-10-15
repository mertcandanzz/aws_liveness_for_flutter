import type { CallerId } from './auth.js';

/** How long a session stays bound to its caller. Sessions expire after ~3 minutes. */
export const SESSION_BINDING_TTL_MS = 60 * 60 * 1000;

interface Binding {
  owner: CallerId;
  createdAt: number;
}

/**
 * Remembers which caller created each session, so credentials and results
 * are only served to that caller. In memory: use a database when you run more
 * than one instance.
 */
export class SessionStore {
  private readonly bindings = new Map<string, Binding>();

  constructor(private readonly now: () => number = Date.now) {}

  bind(sessionId: string, owner: CallerId): void {
    this.prune();
    this.bindings.set(sessionId, { owner, createdAt: this.now() });
  }

  isOwnedBy(sessionId: string, caller: CallerId): boolean {
    const binding = this.bindings.get(sessionId);
    if (!binding || this.now() - binding.createdAt >= SESSION_BINDING_TTL_MS) return false;
    return binding.owner === caller;
  }

  private prune(): void {
    const time = this.now();
    for (const [id, binding] of this.bindings) {
      if (time - binding.createdAt >= SESSION_BINDING_TTL_MS) this.bindings.delete(id);
    }
  }
}
