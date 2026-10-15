package io.github.mertcandanzz.aws_liveness_for_flutter

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner

/**
 * Android side of `LivenessHostApi` for one Flutter engine.
 *
 * Runtime failures are replied as values, never as channel errors (design §4.5). `start`
 * replies exactly once through [SessionRegistry].
 */
internal class LivenessHostApiImpl(
    private val context: Context,
    private val engineToken: Any,
    private val activity: () -> Activity?,
    private val fetcher: CredentialsFetcher,
    private val sessions: SessionRegistry = Shared.sessions,
    private val scheduler: Scheduler = Shared.scheduler,
    private val permissionRequests: PermissionRequests = Shared.permissionRequests,
) : LivenessHostApi {

    override fun checkAvailability(): AvailabilityMessage = try {
        if (context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)) {
            AvailabilityMessage(isAvailable = true)
        } else {
            AvailabilityMessage(isAvailable = false, reason = UnavailableReasonMessage.NO_CAMERA)
        }
    } catch (e: RuntimeException) {
        AvailabilityMessage(isAvailable = false, reason = UnavailableReasonMessage.NO_CAMERA)
    }

    override fun start(request: StartRequestMessage, callback: (Result<OutcomeMessage>) -> Unit) {
        val reply = { outcome: OutcomeMessage -> callback(Result.success(outcome)) }
        val host = activity()
        if (host == null || !isInForeground(host)) {
            // Android may not show an Activity started from the background (design §6.10).
            reply(Outcomes.failed(ErrorCodeMessage.PRESENTER_UNAVAILABLE, "NoForegroundActivity"))
            return
        }
        val attempt = sessions.begin(engineToken, request, reply)
        if (attempt == null) {
            reply(Outcomes.failed(ErrorCodeMessage.ALREADY_ACTIVE))
            return
        }
        try {
            attempt.credentialsProvider = PluginCredentialsProvider(attempt, fetcher, scheduler)
            host.startActivity(LivenessActivity.intent(host, attempt.token))
        } catch (e: ActivityNotFoundException) {
            sessions.finish(attempt, failed(ErrorCodeMessage.PRESENTER_UNAVAILABLE, e))
        } catch (e: RuntimeException) {
            // IllegalStateException, SecurityException and friends from startActivity.
            sessions.finish(attempt, failed(ErrorCodeMessage.UNKNOWN, e))
        }
    }

    override fun cancel(attemptId: Long, reason: CancelRequestReasonMessage) {
        val attempt = sessions.find(engineToken, attemptId) ?: return
        // Rule 2: the plugin-initiated end is delivered first; later SDK callbacks are dropped.
        sessions.finish(attempt, Outcomes.forCancelRequest(reason))
        closeQuietly { attempt.sdkCancel?.invoke() }
        closeQuietly { attempt.closeUi?.invoke() }
    }

    override fun getCameraPermissionStatus(): CameraPermissionStatusMessage = try {
        CameraPermission.status(context, activity())
    } catch (e: RuntimeException) {
        CameraPermissionStatusMessage.NOT_DETERMINED
    }

    override fun requestCameraPermission(callback: (Result<CameraPermissionStatusMessage>) -> Unit) {
        val reply = { status: CameraPermissionStatusMessage -> callback(Result.success(status)) }
        val host = activity()
        if (CameraPermission.isGranted(context) || host == null) {
            reply(CameraPermission.status(context, host))
            return
        }
        if (!permissionRequests.add(reply)) {
            return
        }
        try {
            host.startActivity(CameraPermissionActivity.intent(host))
        } catch (e: RuntimeException) {
            permissionRequests.complete(CameraPermission.status(context, host))
        }
    }

    override fun openAppSettings(callback: (Result<Boolean>) -> Unit) {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.fromParts("package", context.packageName, null))
        val opened = try {
            val host = activity()
            if (host != null) {
                host.startActivity(intent)
            } else {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            true
        } catch (e: RuntimeException) {
            false
        }
        callback(Result.success(opened))
    }

    /** Called when the engine detaches: drop its attempt and close the UI (design §6.9). */
    fun dispose() {
        val dropped = sessions.detachEngine(engineToken) ?: return
        closeQuietly { dropped.sdkCancel?.invoke() }
        closeQuietly { dropped.closeUi?.invoke() }
    }

    private fun isInForeground(host: Activity): Boolean {
        if (host.isFinishing || host.isDestroyed) {
            return false
        }
        // FlutterActivity and FlutterFragmentActivity are lifecycle owners; other hosts pass.
        val state = (host as? LifecycleOwner)?.lifecycle?.currentState ?: return true
        return state.isAtLeast(Lifecycle.State.STARTED)
    }

    private fun failed(code: ErrorCodeMessage, error: Exception): OutcomeMessage =
        Outcomes.failed(code, error.javaClass.simpleName, error.message)

    private inline fun closeQuietly(block: () -> Unit) {
        try {
            block()
        } catch (e: RuntimeException) {
            // The UI may already be gone; the result was delivered before closing.
        }
    }
}
