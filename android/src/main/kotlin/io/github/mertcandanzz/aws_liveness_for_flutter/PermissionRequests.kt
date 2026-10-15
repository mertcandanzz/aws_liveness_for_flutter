package io.github.mertcandanzz.aws_liveness_for_flutter

import java.util.concurrent.atomic.AtomicLong

/**
 * Pending `requestCameraPermission()` calls. Calls that arrive while a prompt is on screen
 * share its result, so at most one [CameraPermissionActivity] runs at a time. Each prompt has
 * an id that its Activity carries; only that Activity can complete it, so a late callback
 * from an older Activity never answers a newer request.
 */
internal class PermissionRequests {
    private val lock = Any()
    private val nextId = AtomicLong(1)
    private var currentId: Long? = null
    private val pending = mutableListOf<(CameraPermissionStatusMessage) -> Unit>()

    /**
     * Queues [callback]. Returns the id of a new prompt the caller must show, or null when the
     * callback joined the prompt already on screen.
     */
    fun add(callback: (CameraPermissionStatusMessage) -> Unit): Long? = synchronized(lock) {
        pending.add(callback)
        if (currentId != null) {
            null
        } else {
            nextId.getAndIncrement().also { currentId = it }
        }
    }

    fun isPending(id: Long): Boolean = synchronized(lock) { currentId == id }

    /** Replies to every caller of prompt [id] once. Returns false for a stale or unknown id. */
    fun complete(id: Long, status: CameraPermissionStatusMessage): Boolean {
        val callbacks = synchronized(lock) {
            if (currentId != id) {
                return false
            }
            currentId = null
            pending.toList().also { pending.clear() }
        }
        callbacks.forEach { it(status) }
        return true
    }
}

/** Process-wide state shared by every engine's plugin instance. */
internal object Shared {
    val scheduler: Scheduler by lazy { MainThreadScheduler() }
    val sessions: SessionRegistry by lazy { SessionRegistry(scheduler) }
    val permissionRequests: PermissionRequests = PermissionRequests()
}
