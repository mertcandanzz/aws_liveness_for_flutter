package io.github.mertcandanzz.aws_liveness_for_flutter

import com.amplifyframework.auth.AWSCredentials
import com.amplifyframework.auth.AWSTemporaryCredentials
import com.amplifyframework.auth.AuthException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val NOW = 1_000_000L

private fun credentials(
    accessKeyId: String = "ASIAEXAMPLE",
    secretAccessKey: String = "secret",
    sessionToken: String = "token",
    expirationEpochSeconds: Long = NOW + 900,
) = CredentialsMessage(accessKeyId, secretAccessKey, sessionToken, expirationEpochSeconds)

class CredentialsConverterTest {
    @Test
    fun `valid credentials become temporary SDK credentials`() {
        val converted = assertNotNull(
            CredentialsConverter.toTemporaryCredentials(CredentialsResultMessage(credentials()), NOW),
        )
        assertEquals("ASIAEXAMPLE", converted.accessKeyId)
        assertEquals("secret", converted.secretAccessKey)
        assertEquals("token", converted.sessionToken)
        assertEquals(NOW + 900, converted.expiresAt.epochSecond)
    }

    @Test
    fun `failures and invalid credentials are rejected`() {
        val rejected = listOf(
            CredentialsResultMessage(failure = CredentialsFailureMessage.PROVIDER_ERROR),
            CredentialsResultMessage(),
            CredentialsResultMessage(credentials(), CredentialsFailureMessage.INVALID),
            CredentialsResultMessage(credentials(accessKeyId = " ")),
            CredentialsResultMessage(credentials(secretAccessKey = "")),
            CredentialsResultMessage(credentials(sessionToken = "")),
            CredentialsResultMessage(credentials(expirationEpochSeconds = NOW)),
        )
        rejected.forEach { assertNull(CredentialsConverter.toTemporaryCredentials(it, NOW), it.failure.toString()) }
    }
}

class PluginCredentialsProviderTest {
    private val scheduler = FakeScheduler()
    private val engine = Any()
    private val registry = SessionRegistry(FakeScheduler())
    private val attempt = assertNotNull(registry.begin(engine, startRequest(attemptId = 3, credentialsTimeoutMillis = 2_000)) {})
    private var pendingReply: ((Result<CredentialsResultMessage>) -> Unit)? = null
    private val requestedAttempts = mutableListOf<Long>()
    private val successes = mutableListOf<AWSCredentials>()
    private val errors = mutableListOf<AuthException>()

    private fun provider(fetcher: CredentialsFetcher = { id, reply -> requestedAttempts += id; pendingReply = reply }) =
        PluginCredentialsProvider(attempt, fetcher, scheduler) { NOW }

    private fun fetch(provider: PluginCredentialsProvider = provider()) =
        provider.fetchAWSCredentials({ successes += it }, { errors += it })

    @Test
    fun `asks Dart for its attempt and hands over credentials`() {
        fetch()
        assertEquals(listOf(3L), requestedAttempts)
        assertEquals(listOf(2_000L + PluginCredentialsProvider.GUARD_MILLIS), scheduler.delayed.map { it.second })

        assertNotNull(pendingReply).invoke(Result.success(CredentialsResultMessage(credentials())))

        assertIs<AWSTemporaryCredentials>(successes.single())
        assertTrue(errors.isEmpty())
        assertFalse(attempt.credentialsFailed)
        assertTrue(scheduler.delayed.isEmpty(), "guard timer is cancelled")
    }

    @Test
    fun `failure values set the credentials flag`() {
        fetch()
        assertNotNull(pendingReply).invoke(
            Result.success(CredentialsResultMessage(failure = CredentialsFailureMessage.TIMED_OUT)),
        )
        assertTrue(successes.isEmpty())
        assertEquals(1, errors.size)
        assertTrue(attempt.credentialsFailed)
    }

    @Test
    fun `invalid credentials and channel errors fail`() {
        fetch()
        assertNotNull(pendingReply).invoke(Result.success(CredentialsResultMessage(credentials(sessionToken = ""))))
        fetch()
        assertNotNull(pendingReply).invoke(Result.failure(AwsLivenessFlutterError("channel-error")))
        assertEquals(2, errors.size)
        assertTrue(successes.isEmpty())
        assertTrue(attempt.credentialsFailed)
    }

    @Test
    fun `guard timeout fails once and ignores a late reply`() {
        fetch()
        scheduler.runDelayed()
        assertNotNull(pendingReply).invoke(Result.success(CredentialsResultMessage(credentials())))

        assertEquals(1, errors.size)
        assertTrue(successes.isEmpty())
        assertTrue(attempt.credentialsFailed)
    }

    @Test
    fun `a throwing channel fails instead of crashing`() {
        fetch(provider { _, _ -> throw IllegalStateException("detached") })
        assertEquals(1, errors.size)
        assertTrue(scheduler.delayed.isEmpty())
    }

    @Test
    fun `a finished attempt fails at once without asking Dart`() {
        registry.finish(attempt, Outcomes.completed())
        fetch()
        assertTrue(requestedAttempts.isEmpty())
        assertEquals(1, errors.size)
    }

    @Test
    fun `a reply after the attempt finished hands over nothing`() {
        fetch()
        val reply = assertNotNull(pendingReply)
        registry.finish(attempt, Outcomes.cancelled(CancelReasonMessage.USER))

        reply(Result.success(CredentialsResultMessage(credentials())))

        assertTrue(successes.isEmpty(), "credentials never reach a finished attempt")
        assertEquals(1, errors.size, "the SDK request is released once")
        assertTrue(scheduler.delayed.isEmpty(), "guard timer is cancelled")
    }

    @Test
    fun `engine detach fails a pending request at once and ignores the late reply`() {
        fetch()
        val reply = assertNotNull(pendingReply)

        registry.detachEngine(engine)
        assertEquals(1, errors.size, "released without waiting for the guard timeout")
        assertTrue(scheduler.delayed.isEmpty())

        reply(Result.success(CredentialsResultMessage(credentials())))
        scheduler.runDelayed()
        assertTrue(successes.isEmpty())
        assertEquals(1, errors.size)
    }

    @Test
    fun `every SDK request asks again`() {
        val provider = provider()
        repeat(2) {
            fetch(provider)
            assertNotNull(pendingReply).invoke(Result.success(CredentialsResultMessage(credentials())))
        }
        assertEquals(listOf(3L, 3L), requestedAttempts)
        assertEquals(2, successes.size)
    }
}
