package io.github.mertcandanzz.aws_liveness_for_flutter

internal fun startRequest(
    attemptId: Long = 1,
    credentialsTimeoutMillis: Long = 15_000,
    theme: ThemeMessage = ThemeMessage(mode = ThemeModeMessage.SYSTEM),
): StartRequestMessage = StartRequestMessage(
    attemptId = attemptId,
    sessionId = "session",
    region = "eu-west-1",
    faceMovementCamera = CameraMessage.FRONT,
    showStartView = true,
    theme = theme,
    credentialsTimeoutMillis = credentialsTimeoutMillis,
)

/**
 * Main-thread stand-in. Posted tasks run at once unless [queuePosts] is set, in which case
 * they wait for [runPosted]; delayed tasks wait for [runDelayed].
 */
internal class FakeScheduler(private val queuePosts: Boolean = false) : Scheduler {
    val posted = mutableListOf<Runnable>()
    val delayed = mutableListOf<Pair<Runnable, Long>>()

    override fun post(task: Runnable) {
        if (queuePosts) {
            synchronized(posted) { posted += task }
        } else {
            task.run()
        }
    }

    override fun postDelayed(task: Runnable, delayMillis: Long) {
        synchronized(delayed) { delayed += task to delayMillis }
    }

    override fun cancel(task: Runnable) {
        synchronized(delayed) { delayed.removeAll { it.first === task } }
    }

    fun runPosted() {
        val tasks = synchronized(posted) { posted.toList().also { posted.clear() } }
        tasks.forEach { it.run() }
    }

    fun runDelayed() {
        val tasks = synchronized(delayed) { delayed.toList().also { delayed.clear() } }
        tasks.forEach { it.first.run() }
    }
}
