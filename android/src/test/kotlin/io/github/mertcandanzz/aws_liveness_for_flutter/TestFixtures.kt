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

/** Runs posted tasks at once and keeps delayed tasks until [runDelayed]. */
internal class FakeScheduler : Scheduler {
    val delayed = mutableListOf<Pair<Runnable, Long>>()

    override fun post(task: Runnable) = task.run()

    override fun postDelayed(task: Runnable, delayMillis: Long) {
        delayed += task to delayMillis
    }

    override fun cancel(task: Runnable) {
        delayed.removeAll { it.first === task }
    }

    fun runDelayed() {
        val tasks = delayed.toList()
        delayed.clear()
        tasks.forEach { it.first.run() }
    }
}
