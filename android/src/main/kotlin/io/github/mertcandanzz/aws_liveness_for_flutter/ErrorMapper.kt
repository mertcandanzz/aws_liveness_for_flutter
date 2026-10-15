package io.github.mertcandanzz.aws_liveness_for_flutter

import com.amplifyframework.ui.liveness.model.FaceLivenessDetectionException

/**
 * Maps a `FaceLivenessDetector` error to the wire outcome (design §4.2 and §4.3).
 *
 * Pure: everything that depends on Android state is passed in, so the whole table runs as a
 * JVM unit test.
 */
internal object ErrorMapper {
    private const val FACE_FIT_TIMED_OUT = "Face did not match oval within time limit."
    private const val FACE_FIT_CLASS = "FaceInOvalMatchExceededTimeLimitException"
    private const val THROTTLED = "Failed since the user made too many requests"
    private const val SERVICE_UNAVAILABLE = "Service is currently unavailable."
    private const val INVALID_SIGNATURE = "Invalid signature"
    private const val UNRECOGNIZED_CLIENT = "Unrecognized client"
    private const val CAMERA_OPEN_TIMED_OUT = "The camera failed to open within the allowed time limit."
    private const val CAMERA_MISSING = "facing camera is required but no"
    private const val VIDEO_INIT_FAILED = "Failed to initialize video components"

    /** Service error names carried as the `cause` of a generic `PredictionsException`. */
    private val serviceCauses = mapOf(
        "ValidationException" to ErrorCodeMessage.VALIDATION,
        "InternalServerException" to ErrorCodeMessage.INTERNAL_SERVER_ERROR,
        "ThrottlingException" to ErrorCodeMessage.THROTTLED,
        "ServiceQuotaExceededException" to ErrorCodeMessage.THROTTLED,
        "ServiceUnavailableException" to ErrorCodeMessage.SERVICE_UNAVAILABLE,
        "InvalidSignatureException" to ErrorCodeMessage.INVALID_SIGNATURE,
        "UnrecognizedClientException" to ErrorCodeMessage.ACCESS_DENIED,
    )

    /**
     * @param pluginEnd the result of a plugin-initiated end that already started (rule 2).
     * @param credentialsFailed whether our credentials provider failed for this attempt (rule 3).
     * @param isPermissionPermanentlyDenied re-reads the camera permission state; only called for
     *   a camera permission error.
     */
    fun map(
        error: FaceLivenessDetectionException,
        pluginEnd: OutcomeMessage?,
        credentialsFailed: Boolean,
        isPermissionPermanentlyDenied: () -> Boolean,
    ): OutcomeMessage {
        if (pluginEnd != null) {
            return pluginEnd
        }
        if (error is FaceLivenessDetectionException.UserCancelledException) {
            return Outcomes.cancelled(CancelReasonMessage.USER)
        }
        val code = if (credentialsFailed) {
            ErrorCodeMessage.CREDENTIALS_UNAVAILABLE
        } else {
            codeFor(error, isPermissionPermanentlyDenied)
        }
        return Outcomes.failed(code, nativeCode(error), error.message)
    }

    private fun codeFor(
        error: FaceLivenessDetectionException,
        isPermissionPermanentlyDenied: () -> Boolean,
    ): ErrorCodeMessage = when (error) {
        is FaceLivenessDetectionException.SessionNotFoundException -> ErrorCodeMessage.SESSION_NOT_FOUND
        is FaceLivenessDetectionException.AccessDeniedException -> ErrorCodeMessage.ACCESS_DENIED
        is FaceLivenessDetectionException.CameraPermissionDeniedException ->
            if (isPermissionPermanentlyDenied()) {
                ErrorCodeMessage.CAMERA_PERMISSION_PERMANENTLY_DENIED
            } else {
                ErrorCodeMessage.CAMERA_PERMISSION_DENIED
            }
        is FaceLivenessDetectionException.SessionInterruptedException -> ErrorCodeMessage.SESSION_INTERRUPTED
        is FaceLivenessDetectionException.SessionTimedOutException -> ErrorCodeMessage.SESSION_TIMED_OUT
        is FaceLivenessDetectionException.UnsupportedChallengeTypeException ->
            ErrorCodeMessage.UNSUPPORTED_CHALLENGE
        is FaceLivenessDetectionException.VideoEncodingException,
        is FaceLivenessDetectionException.VideoMuxingException -> ErrorCodeMessage.VIDEO_ENCODING_FAILED
        else -> codeForGeneric(error)
    }

    private fun codeForGeneric(error: FaceLivenessDetectionException): ErrorCodeMessage {
        if (error.javaClass.simpleName == FACE_FIT_CLASS) {
            return ErrorCodeMessage.FACE_FIT_TIMED_OUT
        }
        val causeName = error.throwable?.cause?.javaClass?.simpleName
        serviceCauses[causeName]?.let { return it }
        return codeForMessage(error.message)
    }

    /** Second line of defence for R8 builds where class names may be obfuscated. */
    private fun codeForMessage(message: String): ErrorCodeMessage = when {
        message == FACE_FIT_TIMED_OUT -> ErrorCodeMessage.FACE_FIT_TIMED_OUT
        message.startsWith(THROTTLED) -> ErrorCodeMessage.THROTTLED
        message == SERVICE_UNAVAILABLE -> ErrorCodeMessage.SERVICE_UNAVAILABLE
        message == INVALID_SIGNATURE -> ErrorCodeMessage.INVALID_SIGNATURE
        message == UNRECOGNIZED_CLIENT -> ErrorCodeMessage.ACCESS_DENIED
        message == CAMERA_OPEN_TIMED_OUT -> ErrorCodeMessage.CAMERA_UNAVAILABLE
        message.contains(CAMERA_MISSING) -> ErrorCodeMessage.CAMERA_UNAVAILABLE
        message.startsWith(VIDEO_INIT_FAILED) -> ErrorCodeMessage.VIDEO_ENCODING_FAILED
        else -> ErrorCodeMessage.UNKNOWN
    }

    /** For example `FaceLivenessDetectionException/PredictionsException/ThrottlingException`. */
    fun nativeCode(error: FaceLivenessDetectionException): String {
        val throwable = error.throwable
        return listOfNotNull(
            error.javaClass.simpleName,
            throwable?.javaClass?.simpleName,
            throwable?.cause?.javaClass?.simpleName,
        ).filter { it.isNotEmpty() }.joinToString("/")
    }
}
