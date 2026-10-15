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

    val isFinished: Boolean
        get() = finished.get()

    /** Returns true only for the first caller; later calls are dropped. */
    internal fun markFinished(): Boolean = finished.compareAndSet(false, true)

    internal fun deliver(outcome: OutcomeMessage) = deliver.invoke(outcome)
}

/**
 * Process-wide single slot for the active attempt (design §6.1, §6.2).
 *
 * Every result goes through [finish], which delivers at most once per attempt and always on
 * [mainThread]. The slot is released before delivery, so a new start may begin while the old
 * UI is still closing.
 */
internal class SessionRegistry(private val mainThread: (Runnable) -> Unit) {
    private val lock = Any()
    private val nextToken = AtomicLong(1)
    private var active: ActiveAttempt? = null

    /** Claims the slot, or returns null when another attempt (from any engine) holds it. */
    fun begin(
        engineToken: Any,
        request: StartRequestMessage,
        deliver: (OutcomeMessage) -> Unit,
    ): ActiveAttempt? = synchronized(lock) {
        if (active != null) {
            return null
        }
        ActiveAttempt(nextToken.getAndIncrement(), engineToken, request, deliver).also { active = it }
    }

    /** The active attempt with [token], or null after process death or once it finished. */
    fun find(token: Long): ActiveAttempt? = synchronized(lock) { active?.takeIf { it.token == token } }

    /** The active attempt for [attemptId] started by [engineToken], if any. */
    fun find(engineToken: Any, attemptId: Long): ActiveAttempt? = synchronized(lock) {
        active?.takeIf { it.engineToken === engineToken && it.request.attemptId == attemptId }
    }

    /** Delivers [outcome] if [attempt] has not finished yet. Returns whether it was delivered. */
    fun finish(attempt: ActiveAttempt, outcome: OutcomeMessage): Boolean {
        if (!release(attempt)) {
            return false
        }
        mainThread(Runnable { attempt.deliver(outcome) })
        return true
    }

    /**
     * Ends the attempt of a detaching engine without a result: its Dart side is gone
     * (design §6.9). Returns the dropped attempt so the caller can close its UI.
     */
    fun detachEngine(engineToken: Any): ActiveAttempt? {
        val attempt = synchronized(lock) { active?.takeIf { it.engineToken === engineToken } }
            ?: return null
        return attempt.takeIf { release(it) }
    }

    private fun release(attempt: ActiveAttempt): Boolean {
        if (!attempt.markFinished()) {
            return false
        }
        synchronized(lock) {
            if (active === attempt) {
                active = null
            }
        }
        return true
    }
}
