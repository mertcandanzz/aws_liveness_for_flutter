package io.github.mertcandanzz.aws_liveness_for_flutter

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

class SessionRegistryTest {
    private val mainThread = FakeScheduler(queuePosts = true)
    private val registry = SessionRegistry(mainThread)
    private val engineA = Any()
    private val engineB = Any()

    @Test
    fun `delivers a result once and only on the main thread`() {
        val delivered = mutableListOf<OutcomeMessage>()
        val attempt = assertNotNull(registry.begin(engineA, startRequest()) { delivered += it })

        assertTrue(registry.finish(attempt, Outcomes.completed()))
        assertTrue(delivered.isEmpty(), "delivery waits for the main thread")
        assertFalse(registry.finish(attempt, Outcomes.cancelled(CancelReasonMessage.USER)))

        mainThread.runPosted()
        assertEquals(listOf(Outcomes.completed()), delivered)
        assertTrue(attempt.isFinished)
    }

    @Test
    fun `concurrent completions deliver exactly once`() {
        val deliveries = AtomicInteger()
        val attempt = assertNotNull(registry.begin(engineA, startRequest()) { deliveries.incrementAndGet() })
        val threads = 16
        val ready = CountDownLatch(threads)
        val go = CountDownLatch(1)
        val wins = AtomicInteger()
        val pool = Executors.newFixedThreadPool(threads)
        repeat(threads) { index ->
            pool.execute {
                ready.countDown()
                go.await()
                val outcome = if (index % 2 == 0) Outcomes.completed() else Outcomes.failed(ErrorCodeMessage.UNKNOWN)
                if (registry.finish(attempt, outcome)) {
                    wins.incrementAndGet()
                }
            }
        }
        ready.await()
        go.countDown()
        pool.shutdown()
        assertTrue(pool.awaitTermination(10, TimeUnit.SECONDS))

        mainThread.runPosted()
        assertEquals(1, wins.get())
        assertEquals(1, deliveries.get())
    }

    @Test
    fun `a second attempt from any engine is rejected while one is active`() {
        val first = assertNotNull(registry.begin(engineA, startRequest(attemptId = 1)) {})
        assertNull(registry.begin(engineA, startRequest(attemptId = 2)) {})
        assertNull(registry.begin(engineB, startRequest(attemptId = 1)) {})

        registry.finish(first, Outcomes.completed())
        val next = assertNotNull(registry.begin(engineB, startRequest(attemptId = 1)) {})
        assertNotEquals(first.token, next.token)
    }

    @Test
    fun `slot is released before delivery`() {
        var startedFromDelivery: ActiveAttempt? = null
        val first = assertNotNull(
            registry.begin(engineA, startRequest(attemptId = 1)) {
                startedFromDelivery = registry.begin(engineA, startRequest(attemptId = 2)) {}
            },
        )
        registry.finish(first, Outcomes.completed())
        mainThread.runPosted()
        assertNotNull(startedFromDelivery)
    }

    @Test
    fun `lookups only match the active attempt of the right engine`() {
        val attempt = assertNotNull(registry.begin(engineA, startRequest(attemptId = 7)) {})

        assertSame(attempt, registry.find(attempt.token))
        assertSame(attempt, registry.find(engineA, 7))
        assertNull(registry.find(engineB, 7), "attempt ids are per engine")
        assertNull(registry.find(engineA, 8))
        assertNull(registry.find(attempt.token + 1))

        registry.finish(attempt, Outcomes.completed())
        assertNull(registry.find(attempt.token), "process death or a finished attempt")
        assertNull(registry.find(engineA, 7))
    }

    @Test
    fun `fast restart - the result waits until the liveness UI is gone`() {
        val delivered = mutableListOf<OutcomeMessage>()
        val first = assertNotNull(registry.begin(engineA, startRequest(attemptId = 1)) { delivered += it })
        registry.uiOpened(first)

        registry.finish(first, Outcomes.cancelled(CancelReasonMessage.USER))
        mainThread.runPosted()
        assertTrue(delivered.isEmpty(), "the host Activity is not back in the foreground yet")
        assertNotNull(registry.begin(engineB, startRequest()) {}.also { registry.detachEngine(engineB) },
            "the slot is free at once")

        registry.uiClosed(first.token)
        mainThread.runPosted()
        assertEquals(listOf(Outcomes.cancelled(CancelReasonMessage.USER)), delivered)
        assertTrue(mainThread.delayed.isEmpty(), "grace timer is cancelled")

        val second = assertNotNull(registry.begin(engineA, startRequest(attemptId = 2)) {}, "restart from delivery")
        assertNotEquals(first.token, second.token)
    }

    @Test
    fun `grace timer delivers when the UI never reports closing`() {
        val delivered = mutableListOf<OutcomeMessage>()
        val attempt = assertNotNull(registry.begin(engineA, startRequest()) { delivered += it })
        registry.uiOpened(attempt)
        registry.finish(attempt, Outcomes.completed())

        assertEquals(listOf(SessionRegistry.DELIVERY_GRACE_MILLIS), mainThread.delayed.map { it.second })
        assertTrue(SessionRegistry.DELIVERY_GRACE_MILLIS <= 3_000)
        mainThread.runDelayed()
        mainThread.runPosted()
        registry.uiClosed(attempt.token)
        mainThread.runPosted()

        assertEquals(listOf(Outcomes.completed()), delivered)
    }

    @Test
    fun `a UI that closes before the result makes delivery immediate`() {
        val delivered = mutableListOf<OutcomeMessage>()
        val attempt = assertNotNull(registry.begin(engineA, startRequest()) { delivered += it })
        registry.uiOpened(attempt)
        registry.uiClosed(attempt.token)

        registry.finish(attempt, Outcomes.completed())
        mainThread.runPosted()
        assertEquals(listOf(Outcomes.completed()), delivered)
        assertTrue(mainThread.delayed.isEmpty())
    }

    @Test
    fun `engine detach drops its attempt without a result`() {
        var delivered = 0
        val attempt = assertNotNull(registry.begin(engineA, startRequest()) { delivered++ })

        assertTrue(registry.detachEngine(engineB).isEmpty(), "another engine's detach is ignored")
        assertEquals(listOf(attempt), registry.detachEngine(engineA))
        assertTrue(registry.detachEngine(engineA).isEmpty(), "second detach is a no-op")
        assertFalse(registry.finish(attempt, Outcomes.completed()), "late SDK results are dropped")

        mainThread.runPosted()
        assertEquals(0, delivered)
        assertNotNull(registry.begin(engineB, startRequest()) {}, "slot is free again")
    }

    @Test
    fun `finish, detach, UI destroyed, grace elapses - nothing is sent (iOS P1 parity)`() {
        var delivered = 0
        val attempt = assertNotNull(registry.begin(engineA, startRequest()) { delivered++ })
        registry.uiOpened(attempt)
        registry.finish(attempt, Outcomes.completed())

        assertEquals(listOf(attempt), registry.detachEngine(engineA), "a result waiting for the UI is dropped")
        assertTrue(mainThread.delayed.isEmpty(), "grace timer is cancelled")
        registry.uiClosed(attempt.token)
        mainThread.runDelayed()
        mainThread.runPosted()

        assertEquals(0, delivered)
    }

    @Test
    fun `detach after a delivery was posted suppresses it`() {
        var delivered = 0
        val attempt = assertNotNull(registry.begin(engineA, startRequest()) { delivered++ })
        registry.finish(attempt, Outcomes.completed())

        registry.detachEngine(engineA)
        mainThread.runPosted()

        assertEquals(0, delivered)
    }

    @Test
    fun `detach after the result was delivered returns nothing`() {
        val attempt = assertNotNull(registry.begin(engineA, startRequest()) {})
        registry.finish(attempt, Outcomes.completed())
        mainThread.runPosted()
        assertTrue(registry.detachEngine(engineA).isEmpty())
    }

    @Test
    fun `end listeners run once on finish or detach, and late listeners are refused`() {
        val first = assertNotNull(registry.begin(engineA, startRequest(attemptId = 1)) {})
        var ended = 0
        assertTrue(first.addEndListener { ended++ })
        registry.finish(first, Outcomes.completed())
        registry.finish(first, Outcomes.completed())
        assertEquals(1, ended)
        assertFalse(first.addEndListener { ended++ })

        val second = assertNotNull(registry.begin(engineA, startRequest(attemptId = 2)) {})
        var detached = 0
        second.addEndListener { detached++ }
        registry.detachEngine(engineA)
        assertEquals(1, detached)
    }
}
