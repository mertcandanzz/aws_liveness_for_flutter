package io.github.mertcandanzz.aws_liveness_for_flutter

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts

/**
 * Translucent Activity with no UI that shows the camera permission prompt for
 * `requestCameraPermission()`, so the host Activity never has to forward permission results.
 * It only ever completes the request whose id it was started with.
 */
class CameraPermissionActivity : ComponentActivity() {
    private val requestId: Long by lazy { intent.getLongExtra(EXTRA_REQUEST_ID, NO_REQUEST) }

    private val launcher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { isGranted ->
            reply(CameraPermission.statusAfterRequest(isGranted, CameraPermission.shouldShowRationale(this)))
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!Shared.permissionRequests.isPending(requestId)) {
            // Process death or an answered request: the caller is gone.
            finish()
            return
        }
        // A recreated instance receives the pending result from the Activity Result API.
        if (savedInstanceState == null) {
            launcher.launch(CameraPermission.PERMISSION)
        }
    }

    override fun onDestroy() {
        if (isFinishing && !isChangingConfigurations) {
            // Closed before a result arrived: reply with what is known now. A no-op when the
            // request was already answered or belongs to a newer prompt.
            Shared.permissionRequests.complete(requestId, CameraPermission.status(this, this))
        }
        super.onDestroy()
    }

    private fun reply(status: CameraPermissionStatusMessage) {
        Shared.permissionRequests.complete(requestId, status)
        finish()
    }

    internal companion object {
        private const val EXTRA_REQUEST_ID = "io.github.mertcandanzz.aws_liveness_for_flutter.PERMISSION_REQUEST_ID"
        private const val NO_REQUEST = -1L

        fun intent(context: Context, requestId: Long): Intent =
            Intent(context, CameraPermissionActivity::class.java).putExtra(EXTRA_REQUEST_ID, requestId)
    }
}
