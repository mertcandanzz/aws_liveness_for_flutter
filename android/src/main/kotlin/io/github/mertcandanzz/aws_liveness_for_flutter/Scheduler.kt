package io.github.mertcandanzz.aws_liveness_for_flutter

import android.os.Handler
import android.os.Looper

/** Main-thread task scheduling, replaceable in JVM tests. */
internal interface Scheduler {
    fun post(task: Runnable)

    fun postDelayed(task: Runnable, delayMillis: Long)

    fun cancel(task: Runnable)
}

internal class MainThreadScheduler : Scheduler {
    private val handler = Handler(Looper.getMainLooper())

    override fun post(task: Runnable) {
        handler.post(task)
    }

    override fun postDelayed(task: Runnable, delayMillis: Long) {
        handler.postDelayed(task, delayMillis)
    }

    override fun cancel(task: Runnable) {
        handler.removeCallbacks(task)
    }
}
