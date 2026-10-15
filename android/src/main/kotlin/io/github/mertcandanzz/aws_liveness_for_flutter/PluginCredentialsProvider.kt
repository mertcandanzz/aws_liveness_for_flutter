package io.github.mertcandanzz.aws_liveness_for_flutter

import com.amplifyframework.auth.AWSCredentials
import com.amplifyframework.auth.AWSCredentialsProvider
import com.amplifyframework.auth.AWSTemporaryCredentials
import com.amplifyframework.auth.AuthException
import com.amplifyframework.core.Consumer
import java.util.concurrent.atomic.AtomicBoolean

/** Asks Dart for credentials for one attempt; production uses [LivenessFlutterApi.fetchCredentials]. */
internal typealias CredentialsFetcher = (attemptId: Long, callback: (Result<CredentialsResultMessage>) -> Unit) -> Unit

/** Converts the Dart reply into SDK credentials, or null when it is not usable. */
internal object CredentialsConverter {
    fun toTemporaryCredentials(
        result: CredentialsResultMessage,
        nowEpochSeconds: Long,
    ): AWSTemporaryCredentials? {
        val credentials = result.credentials ?: return null
        if (result.failure != null) {
            return null
        }
        if (credentials.accessKeyId.isBlank() ||
            credentials.secretAccessKey.isBlank() ||
            credentials.sessionToken.isBlank() ||
            credentials.expirationEpochSeconds <= nowEpochSeconds
        ) {
            return null
        }
        return AWSCredentials.createAWSCredentials(
            credentials.accessKeyId,
            credentials.secretAccessKey,
            credentials.sessionToken,
            credentials.expirationEpochSeconds,
        ) as? AWSTemporaryCredentials
    }
}

/**
 * The SDK's credentials provider for one attempt (design §7).
 *
 * The SDK calls it on the main thread, at least once per attempt and again after a reconnect.
 * Every call replies exactly once: with credentials, or with an [AuthException] after setting
 * [ActiveAttempt.credentialsFailed]. A request still waiting when the attempt finishes or its
 * engine detaches fails at once, and a later Dart reply is dropped, so credentials never reach
 * an attempt that has ended. Credentials are handed over at once and never stored or logged.
 */
internal class PluginCredentialsProvider(
    private val attempt: ActiveAttempt,
    private val fetcher: CredentialsFetcher,
    private val scheduler: Scheduler,
    private val nowEpochSeconds: () -> Long = { System.currentTimeMillis() / 1000 },
) : AWSCredentialsProvider<AWSCredentials> {

    override fun fetchAWSCredentials(onSuccess: Consumer<AWSCredentials>, onError: Consumer<AuthException>) {
        PendingRequest(onSuccess, onError).start()
    }

    /** One SDK request; replies once through [succeed] or [fail]. */
    private inner class PendingRequest(
        private val onSuccess: Consumer<AWSCredentials>,
        private val onError: Consumer<AuthException>,
    ) {
        private val replied = AtomicBoolean(false)
        private val timeout = Runnable { fail("timed out") }
        private val onAttemptEnded: () -> Unit = { fail("attempt ended") }

        fun start() {
            if (!attempt.addEndListener(onAttemptEnded)) {
                fail("attempt ended")
                return
            }
            scheduler.postDelayed(timeout, attempt.request.credentialsTimeoutMillis + GUARD_MILLIS)
            scheduler.post {
                try {
                    fetcher(attempt.request.attemptId) { result -> onReply(result) }
                } catch (e: RuntimeException) {
                    fail("channel error")
                }
            }
        }

        private fun onReply(result: Result<CredentialsResultMessage>) {
            if (attempt.isFinished) {
                fail("attempt ended")
                return
            }
            val credentials = result.getOrNull()?.let {
                CredentialsConverter.toTemporaryCredentials(it, nowEpochSeconds())
            }
            if (credentials == null) {
                fail(failureName(result))
            } else if (claimReply()) {
                onSuccess.accept(credentials)
            }
        }

        private fun fail(reason: String) {
            if (!claimReply()) {
                return
            }
            attempt.credentialsFailed = true
            onError.accept(
                AuthException(
                    "Liveness credentials are unavailable ($reason).",
                    "Check the credentialsProvider passed to AwsLiveness.start.",
                ),
            )
        }

        /** True only for the first reply; also stops the guard timer and the end listener. */
        private fun claimReply(): Boolean {
            if (!replied.compareAndSet(false, true)) {
                return false
            }
            scheduler.cancel(timeout)
            attempt.removeEndListener(onAttemptEnded)
            return true
        }
    }

    private fun failureName(result: Result<CredentialsResultMessage>): String =
        result.getOrNull()?.failure?.name?.lowercase() ?: if (result.isFailure) "channel error" else "invalid"

    companion object {
        /** Native waits this long past Dart's own credentials timeout (design §6.3). */
        const val GUARD_MILLIS: Long = 5_000
    }
}
