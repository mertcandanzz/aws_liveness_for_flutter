package io.github.mertcandanzz.aws_liveness_for_flutter

import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.CyclicBarrier
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Detach racing a delivery: once detachEngine has returned, nothing is sent for that engine,
 * whatever step the delivery had reached.
 */
class SessionRegistryRaceTest {
    private val engine = Any()

    @Test
    fun `detach between release and tracking - nothing is sent`() {
        val mainThread = FakeScheduler(queuePosts = true)
        lateinit var registry: SessionRegistry
        var dropped = emptyList<ActiveAttempt>()
        registry = SessionRegistry(
            mainThread,
            raceHooks = SessionRegistry.RaceHooks(afterRelease = { dropped = registry.detachEngine(engine) }),
        )
        var sends = 0
        val attempt = assertNotNull(registry.begin(engine, startRequest()) { sends++ })

        registry.finish(attempt, Outcomes.completed())
        mainThread.runDelayed()
        mainThread.runPosted()

        assertEquals(listOf(attempt), dropped, "detach must still see the finishing attempt")
        assertEquals(0, sends)
    }

    @Test
    fun `detach between release and tracking with the UI open - nothing is sent`() {
        val mainThread = FakeScheduler(queuePosts = true)
        lateinit var registry: SessionRegistry
        registry = SessionRegistry(
            mainThread,
            raceHooks = SessionRegistry.RaceHooks(afterRelease = { registry.detachEngine(engine) }),
        )
        var sends = 0
        val attempt = assertNotNull(registry.begin(engine, startRequest()) { sends++ })
        registry.uiOpened(attempt)

        registry.finish(attempt, Outcomes.completed())
        registry.uiClosed(attempt.token)
        mainThread.runDelayed()
        mainThread.runPosted()

        assertEquals(0, sends)
        assertTrue(mainThread.delayed.isEmpty(), "no grace timer outlives the detach")
    }

    @Test
    fun `detach between flush and post - nothing is sent`() {
        val mainThread = FakeScheduler(queuePosts = true)
        lateinit var registry: SessionRegistry
        var dropped = emptyList<ActiveAttempt>()
        registry = SessionRegistry(
            mainThread,
            raceHooks = SessionRegistry.RaceHooks(beforePost = { dropped = registry.detachEngine(engine) }),
        )
        var sends = 0
        val attempt = assertNotNull(registry.begin(engine, startRequest()) { sends++ })
        registry.uiOpened(attempt)
        registry.finish(attempt, Outcomes.completed())

        registry.uiClosed(attempt.token)
        mainThread.runPosted()

        assertEquals(listOf(attempt), dropped, "detach must still see the flushed attempt")
        assertEquals(0, sends)
    }

    @Test
    fun `finish racing detach on two threads never sends after detach`() {
        val pool = Executors.newFixedThreadPool(2)
        try {
            repeat(ITERATIONS) { iteration ->
                val mainThread = FakeScheduler(queuePosts = true)
                val registry = SessionRegistry(mainThread)
                val sends = AtomicInteger()
                val attempt = assertNotNull(registry.begin(engine, startRequest()) { sends.incrementAndGet() })
                if (iteration % 2 == 0) {
                    registry.uiOpened(attempt)
                }
                val barrier = CyclicBarrier(2)
                val finishing = pool.submit {
                    barrier.await()
                    registry.finish(attempt, Outcomes.completed())
                    registry.uiClosed(attempt.token)
                }
                val detaching = pool.submit<List<ActiveAttempt>> {
                    barrier.await()
                    registry.detachEngine(engine)
                }
                finishing.get(5, TimeUnit.SECONDS)
                val dropped = detaching.get(5, TimeUnit.SECONDS)
                mainThread.runDelayed()
                mainThread.runPosted()

                // Detach returned before the main thread ran, so nothing may be sent at all.
                assertEquals(listOf(attempt), dropped, "iteration $iteration: detach missed the attempt")
                assertEquals(0, sends.get(), "iteration $iteration: sent after detach")
            }
        } finally {
            pool.shutdownNow()
        }
    }

    @Test
    fun `a delivery claimed before detach finishes its callback before detach returns`() {
        val paused = CountDownLatch(1)
        val resume = CountDownLatch(1)
        val mainThread = FakeScheduler(queuePosts = true)
        val registry = SessionRegistry(
            mainThread,
            raceHooks = SessionRegistry.RaceHooks(
                afterClaim = {
                    paused.countDown()
                    resume.await(5, TimeUnit.SECONDS)
                },
            ),
        )
        val events = Collections.synchronizedList(mutableListOf<String>())
        val attempt = assertNotNull(registry.begin(engine, startRequest()) { events += "callback" })
        registry.finish(attempt, Outcomes.completed())

        val main = thread { mainThread.runPosted() }
        assertTrue(paused.await(5, TimeUnit.SECONDS), "delivery claimed")
        var dropped = emptyList<ActiveAttempt>()
        val detachReturned = CountDownLatch(1)
        val detacher = thread {
            dropped = registry.detachEngine(engine)
            events += "detach returned"
            detachReturned.countDown()
        }
        // Give a detach that is not serialized with the callback time to return first.
        val returnedWhileClaimed = detachReturned.await(500, TimeUnit.MILLISECONDS)
        resume.countDown()
        main.join(5_000)
        detacher.join(5_000)

        assertFalse(returnedWhileClaimed, "detach returned while a claimed callback had not run")
        assertEquals(listOf("callback", "detach returned"), events)
        assertTrue(dropped.isEmpty(), "the attempt was delivered before detach")
    }

    @Test
    fun `callbacks running concurrently with detach never start after detach returned`() {
        val pool = Executors.newFixedThreadPool(2)
        try {
            repeat(ITERATIONS) { iteration ->
                val mainThread = FakeScheduler(queuePosts = true)
                val registry = SessionRegistry(mainThread)
                val detachReturned = AtomicBoolean(false)
                val sends = AtomicInteger()
                val lateSends = AtomicInteger()
                val attempt = assertNotNull(
                    registry.begin(engine, startRequest()) {
                        if (detachReturned.get()) {
                            lateSends.incrementAndGet()
                        }
                        sends.incrementAndGet()
                    },
                )
                if (iteration % 2 == 0) {
                    registry.uiOpened(attempt)
                }
                val barrier = CyclicBarrier(2)
                // The "main thread" runs the delivery callbacks while the other thread detaches.
                val finishing = pool.submit {
                    barrier.await()
                    registry.finish(attempt, Outcomes.completed())
                    registry.uiClosed(attempt.token)
                    mainThread.runPosted()
                }
                val detaching = pool.submit<List<ActiveAttempt>> {
                    barrier.await()
                    registry.detachEngine(engine).also { detachReturned.set(true) }
                }
                finishing.get(5, TimeUnit.SECONDS)
                val dropped = detaching.get(5, TimeUnit.SECONDS)
                // Anything still queued runs after detach returned and must not deliver.
                mainThread.runDelayed()
                mainThread.runPosted()

                assertEquals(0, lateSends.get(), "iteration $iteration: callback started after detach returned")
                assertEquals(
                    if (dropped.contains(attempt)) 0 else 1,
                    sends.get(),
                    "iteration $iteration: delivered once before detach, or dropped",
                )
            }
        } finally {
            pool.shutdownNow()
        }
    }

    private companion object {
        const val ITERATIONS = 2_000
    }
}
