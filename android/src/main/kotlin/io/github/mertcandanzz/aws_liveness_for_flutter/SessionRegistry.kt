package io.github.mertcandanzz.aws_liveness_for_flutter

import com.amplifyframework.auth.AWSCredentials
import com.amplifyframework.auth.AWSCredentialsProvider
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * One liveness attempt owned by one Flutter engine.
 *
 * [token] is unique in this process and is the only value passed to [LivenessActivity] through
 * its Intent; the request itself never leaves memory.
 */
internal class ActiveAttempt(
    val token: Long,
    val engineToken: Any,
    val request: StartRequestMessage,
    private val deliver: (OutcomeMessage) -> Unit,
) {
    private val finished = AtomicBoolean(false)
    private val endListeners = mutableListOf<() -> Unit>()

    /** Set when our credentials provider failed for this attempt (design §4.2, rule 3). */
    @Volatile
    var credentialsFailed: Boolean = false

    /** Set by the host API before [LivenessActivity] starts. */
    @Volatile
    var credentialsProvider: AWSCredentialsProvider<AWSCredentials>? = null

    /** The SDK's cancel lambda, captured from the `cancelButton` slot once it is composed. */
    @Volatile
    var sdkCancel: (() -> Unit)? = null

    /** Closes the native UI; set by [LivenessActivity] while it is alive. */
    @Volatile
    var closeUi: (() -> Unit)? = null

    // Guarded by the owning SessionRegistry's lock.
    internal var isUiOpen = false
    internal var isDetached = false
    internal var pendingOutcome: OutcomeMessage? = null
    internal var graceTask: Runnable? = null

    val isFinished: Boolean
        get() = finished.get()

    /**
     * Runs [listener] once when the attempt finishes or its engine detaches. Returns false,
     * without registering, when the attempt has already ended.
     */
    fun addEndListener(listener: () -> Unit): Boolean = synchronized(endListeners) {
        if (finished.get()) {
            false
        } else {
            endListeners += listener
            true
        }
    }

    fun removeEndListener(listener: () -> Unit) {
        synchronized(endListeners) { endListeners.remove(listener) }
    }

    /** Returns true only for the first caller; later calls are dropped. */
    internal fun markFinished(): Boolean = finished.compareAndSet(false, true)

    internal fun runEndListeners() {
        val listeners = synchronized(endListeners) { endListeners.toList().also { endListeners.clear() } }
        listeners.forEach { it() }
    }

    internal fun deliver(outcome: OutcomeMessage) = deliver.invoke(outcome)
}

/**
 * Process-wide single slot for the active attempt (design §6.1, §6.2).
 *
 * Every result goes through [finish], which delivers at most once per attempt and always
 * through [scheduler] (the main thread). The slot is released at once, but while the
 * liveness UI is still open the result waits until [uiClosed] or [deliveryGraceMillis], so a
 * caller that starts again right away finds its own Activity back in the foreground.
 *
 * An attempt stays in one list from [begin] until it is delivered or dropped, so
 * [detachEngine] sees it at every step of a delivery, and the delivery callback runs under
 * the same lock. Once [detachEngine] has returned, no callback for that engine is running or
 * can start.
 */
internal class SessionRegistry(
    private val scheduler: Scheduler,
    private val deliveryGraceMillis: Long = DELIVERY_GRACE_MILLIS,
    private val raceHooks: RaceHooks = RaceHooks(),
) {
    private val lock = Any()
    private val nextToken = AtomicLong(1)
    private var active: ActiveAttempt? = null

    /** Begun and neither delivered nor dropped yet; guarded by [lock]. */
    private val undelivered = mutableListOf<ActiveAttempt>()

    /** Claims the slot, or returns null when another attempt (from any engine) holds it. */
    fun begin(
        engineToken: Any,
        request: StartRequestMessage,
        deliver: (OutcomeMessage) -> Unit,
    ): ActiveAttempt? = synchronized(lock) {
        if (active != null) {
            return null
        }
        ActiveAttempt(nextToken.getAndIncrement(), engineToken, request, deliver).also {
            active = it
            undelivered += it
        }
    }

    /** The active attempt with [token], or null after process death or once it finished. */
    fun find(token: Long): ActiveAttempt? = synchronized(lock) { active?.takeIf { it.token == token } }

    /** The active attempt for [attemptId] started by [engineToken], if any. */
    fun find(engineToken: Any, attemptId: Long): ActiveAttempt? = synchronized(lock) {
        active?.takeIf { it.engineToken === engineToken && it.request.attemptId == attemptId }
    }

    /** The liveness UI for [attempt] was started; its result now waits for [uiClosed]. */
    fun uiOpened(attempt: ActiveAttempt) {
        synchronized(lock) {
            if (!attempt.isFinished) {
                attempt.isUiOpen = true
            }
        }
    }

    /** The liveness UI for the attempt with [token] is gone; a waiting result is delivered. */
    fun uiClosed(token: Long) {
        val attempt = synchronized(lock) {
            undelivered.firstOrNull { it.token == token }?.also { it.isUiOpen = false }
        } ?: return
        flush(attempt)
    }

    /** Delivers [outcome] if [attempt] has not finished yet. Returns whether it was accepted. */
    fun finish(attempt: ActiveAttempt, outcome: OutcomeMessage): Boolean {
        if (!attempt.markFinished()) {
            return false
        }
        val postNow = synchronized(lock) {
            if (active === attempt) {
                active = null
            }
            when {
                attempt.isDetached -> false
                attempt.isUiOpen -> {
                    val grace = Runnable { flush(attempt) }
                    attempt.pendingOutcome = outcome
                    attempt.graceTask = grace
                    // Scheduled under the lock, so a detach always sees and cancels it.
                    scheduler.postDelayed(grace, deliveryGraceMillis)
                    false
                }
                else -> true
            }
        }
        raceHooks.afterRelease()
        attempt.runEndListeners()
        if (postNow) {
            post(attempt, outcome)
        }
        return true
    }

    /**
     * Ends every attempt of a detaching engine without a result, including one whose result
     * is waiting for its UI to close or is queued for the main thread (design §6.9). Returns
     * them so the caller can close their UI.
     */
    fun detachEngine(engineToken: Any): List<ActiveAttempt> {
        val dropped = synchronized(lock) {
            val owned = undelivered.filter { it.engineToken === engineToken }
            owned.forEach {
                it.isDetached = true
                it.pendingOutcome = null
                it.graceTask?.let { grace -> scheduler.cancel(grace) }
                it.graceTask = null
            }
            undelivered.removeAll(owned)
            if (active?.engineToken === engineToken) {
                active = null
            }
            owned
        }
        dropped.forEach {
            if (it.markFinished()) {
                it.runEndListeners()
            }
        }
        return dropped
    }

    private fun flush(attempt: ActiveAttempt) {
        val outcome = synchronized(lock) {
            val outcome = attempt.pendingOutcome ?: return
            attempt.pendingOutcome = null
            attempt.graceTask?.let { scheduler.cancel(it) }
            attempt.graceTask = null
            outcome
        }
        raceHooks.beforePost()
        post(attempt, outcome)
    }

    private fun post(attempt: ActiveAttempt, outcome: OutcomeMessage) {
        scheduler.post {
            // The single send point. Claiming and calling back happen under the lock that
            // detachEngine takes, so a delivery either completes before a detach starts or
            // never runs: once detachEngine has returned, no callback is running or can start.
            // The callback is the Pigeon reply, which only queues a message and never blocks.
            synchronized(lock) {
                if (attempt.isDetached || !undelivered.remove(attempt)) {
                    return@post
                }
                raceHooks.afterClaim()
                attempt.deliver(outcome)
            }
        }
    }

    /** Test-only interleaving points between the steps of a delivery. */
    internal class RaceHooks(
        val afterRelease: () -> Unit = {},
        val beforePost: () -> Unit = {},
        val afterClaim: () -> Unit = {},
    )

    companion object {
        /** Longest wait for the liveness UI to close before delivering anyway (iOS parity). */
        const val DELIVERY_GRACE_MILLIS: Long = 3_000
    }
}
