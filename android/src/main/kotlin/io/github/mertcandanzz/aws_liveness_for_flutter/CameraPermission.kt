package io.github.mertcandanzz.aws_liveness_for_flutter

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat

/**
 * Camera permission status rules (design §3.5). Nothing is stored on disk, so Android cannot
 * tell "never asked" from "don't ask again" until a request has been made.
 */
internal object CameraPermission {
    const val PERMISSION: String = Manifest.permission.CAMERA

    /**
     * @param shouldShowRationale null when no Activity is available to ask.
     */
    fun currentStatus(isGranted: Boolean, shouldShowRationale: Boolean?): CameraPermissionStatusMessage =
        when {
            isGranted -> CameraPermissionStatusMessage.GRANTED
            shouldShowRationale == true -> CameraPermissionStatusMessage.DENIED
            else -> CameraPermissionStatusMessage.NOT_DETERMINED
        }

    /** After a request: no rationale on a denial means the user chose "don't ask again". */
    fun statusAfterRequest(isGranted: Boolean, shouldShowRationale: Boolean): CameraPermissionStatusMessage =
        when {
            isGranted -> CameraPermissionStatusMessage.GRANTED
            shouldShowRationale -> CameraPermissionStatusMessage.DENIED
            else -> CameraPermissionStatusMessage.PERMANENTLY_DENIED
        }

    /** The error for a denied pre-check; null when the permission is granted. */
    fun errorFor(status: CameraPermissionStatusMessage): ErrorCodeMessage? = when (status) {
        CameraPermissionStatusMessage.GRANTED -> null
        CameraPermissionStatusMessage.PERMANENTLY_DENIED,
        CameraPermissionStatusMessage.RESTRICTED -> ErrorCodeMessage.CAMERA_PERMISSION_PERMANENTLY_DENIED
        CameraPermissionStatusMessage.NOT_DETERMINED,
        CameraPermissionStatusMessage.DENIED -> ErrorCodeMessage.CAMERA_PERMISSION_DENIED
    }

    fun isGranted(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, PERMISSION) == PackageManager.PERMISSION_GRANTED

    fun shouldShowRationale(activity: Activity): Boolean =
        activity.shouldShowRequestPermissionRationale(PERMISSION)

    fun status(context: Context, activity: Activity?): CameraPermissionStatusMessage =
        currentStatus(isGranted(context), activity?.let { shouldShowRationale(it) })
}
