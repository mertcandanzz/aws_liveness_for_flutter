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
    private val mainThreadTasks = mutableListOf<Runnable>()
    private val registry = SessionRegistry { synchronized(mainThreadTasks) { mainThreadTasks += it } }
    private val engineA = Any()
    private val engineB = Any()

    private fun drainMainThread() {
        val tasks = synchronized(mainThreadTasks) { mainThreadTasks.toList().also { mainThreadTasks.clear() } }
        tasks.forEach { it.run() }
    }

    @Test
    fun `delivers a result once and only on the main thread`() {
        val delivered = mutableListOf<OutcomeMessage>()
        val attempt = assertNotNull(registry.begin(engineA, startRequest()) { delivered += it })

        assertTrue(registry.finish(attempt, Outcomes.completed()))
        assertTrue(delivered.isEmpty(), "delivery waits for the main thread")
        assertFalse(registry.finish(attempt, Outcomes.cancelled(CancelReasonMessage.USER)))

        drainMainThread()
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

        drainMainThread()
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
        drainMainThread()
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
    fun `engine detach drops its attempt without a result`() {
        var delivered = 0
        val attempt = assertNotNull(registry.begin(engineA, startRequest()) { delivered++ })

        assertNull(registry.detachEngine(engineB), "another engine's detach is ignored")
        assertSame(attempt, registry.detachEngine(engineA))
        assertNull(registry.detachEngine(engineA), "second detach is a no-op")
        assertFalse(registry.finish(attempt, Outcomes.completed()), "late SDK results are dropped")

        drainMainThread()
        assertEquals(0, delivered)
        assertNotNull(registry.begin(engineB, startRequest()) {}, "slot is free again")
    }

    @Test
    fun `detach after the result was delivered returns nothing`() {
        val attempt = assertNotNull(registry.begin(engineA, startRequest()) {})
        registry.finish(attempt, Outcomes.completed())
        assertNull(registry.detachEngine(engineA))
    }
}
