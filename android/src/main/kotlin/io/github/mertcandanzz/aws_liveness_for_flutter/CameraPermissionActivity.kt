package io.github.mertcandanzz.aws_liveness_for_flutter

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts

/**
 * Translucent Activity with no UI that shows the camera permission prompt for
 * `requestCameraPermission()`, so the host Activity never has to forward permission results.
 */
class CameraPermissionActivity : ComponentActivity() {
    private val launcher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { isGranted ->
            reply(CameraPermission.statusAfterRequest(isGranted, CameraPermission.shouldShowRationale(this)))
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!Shared.permissionRequests.hasPending) {
            // Process death: the caller is gone.
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
            // Closed before a result arrived: reply with what is known now.
            Shared.permissionRequests.complete(CameraPermission.status(this, this))
        }
        super.onDestroy()
    }

    private fun reply(status: CameraPermissionStatusMessage) {
        Shared.permissionRequests.complete(status)
        finish()
    }

    internal companion object {
        fun intent(context: Context): Intent = Intent(context, CameraPermissionActivity::class.java)
    }
}
