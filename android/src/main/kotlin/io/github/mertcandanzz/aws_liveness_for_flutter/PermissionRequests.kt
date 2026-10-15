package io.github.mertcandanzz.aws_liveness_for_flutter

/**
 * Pending `requestCameraPermission()` calls. Calls that arrive while a request is on screen
 * share its result, so at most one [CameraPermissionActivity] runs at a time.
 */
internal class PermissionRequests {
    private val lock = Any()
    private val pending = mutableListOf<(CameraPermissionStatusMessage) -> Unit>()

    /** Queues [callback]; returns true when the caller must show a new permission request. */
    fun add(callback: (CameraPermissionStatusMessage) -> Unit): Boolean = synchronized(lock) {
        pending.add(callback)
        pending.size == 1
    }

    val hasPending: Boolean
        get() = synchronized(lock) { pending.isNotEmpty() }

    /** Replies to every queued caller once; later calls are no-ops. */
    fun complete(status: CameraPermissionStatusMessage) {
        val callbacks = synchronized(lock) { pending.toList().also { pending.clear() } }
        callbacks.forEach { it(status) }
    }
}

/** Process-wide state shared by every engine's plugin instance. */
internal object Shared {
    val scheduler: Scheduler by lazy { MainThreadScheduler() }
    val sessions: SessionRegistry by lazy { SessionRegistry { scheduler.post(it) } }
    val permissionRequests: PermissionRequests = PermissionRequests()
}
