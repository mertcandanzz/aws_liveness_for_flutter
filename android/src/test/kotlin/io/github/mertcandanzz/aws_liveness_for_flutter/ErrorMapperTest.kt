package io.github.mertcandanzz.aws_liveness_for_flutter

import com.amplifyframework.predictions.PredictionsException
import com.amplifyframework.ui.liveness.model.FaceLivenessDetectionException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull

/** Stand-ins for the SDK's internal service error classes; the mapper only reads simple names. */
private object ServiceErrors {
    class ValidationException : Exception("validation")
    class InternalServerException : Exception("internal")
    class ThrottlingException : Exception("throttling")
    class ServiceQuotaExceededException : Exception("quota")
    class ServiceUnavailableException : Exception("unavailable")
    class InvalidSignatureException : Exception("signature")
    class UnrecognizedClientException : Exception("client")
    class SomethingElseException : Exception("other")
}

class ErrorMapperTest {
    private fun map(
        error: FaceLivenessDetectionException,
        pluginEnd: OutcomeMessage? = null,
        credentialsFailed: Boolean = false,
        permanentlyDenied: Boolean = false,
    ): OutcomeMessage = ErrorMapper.map(error, pluginEnd, credentialsFailed) { permanentlyDenied }

    private fun codeOf(error: FaceLivenessDetectionException, permanentlyDenied: Boolean = false) =
        map(error, permanentlyDenied = permanentlyDenied).errorCode

    private fun generic(message: String, cause: Throwable? = null) = FaceLivenessDetectionException(
        message = message,
        throwable = cause?.let { PredictionsException(message, it, "See attached exception.") },
    )

    @Test
    fun `plugin-initiated end wins over every SDK error (rule 2)`() {
        val pluginEnd = Outcomes.failed(ErrorCodeMessage.TIMED_OUT)
        assertEquals(pluginEnd, map(FaceLivenessDetectionException.UserCancelledException(), pluginEnd))
        assertEquals(
            pluginEnd,
            map(generic("Failed to start the face liveness session."), pluginEnd, credentialsFailed = true),
        )
    }

    @Test
    fun `user cancel maps to cancelled user (rule 1)`() {
        val outcome = map(FaceLivenessDetectionException.UserCancelledException(), credentialsFailed = true)
        assertEquals(OutcomeKindMessage.CANCELLED, outcome.kind)
        assertEquals(CancelReasonMessage.USER, outcome.cancelReason)
        assertNull(outcome.errorCode)
    }

    @Test
    fun `credentials failure wins over the SDK error (rule 3)`() {
        val errors = listOf(
            generic("Failed to start the face liveness session."),
            FaceLivenessDetectionException.AccessDeniedException(),
            FaceLivenessDetectionException.SessionInterruptedException(),
        )
        errors.forEach {
            assertEquals(ErrorCodeMessage.CREDENTIALS_UNAVAILABLE, map(it, credentialsFailed = true).errorCode)
        }
    }

    @Test
    fun `start failure without the credentials flag is unknown`() {
        assertEquals(ErrorCodeMessage.UNKNOWN, codeOf(generic("Failed to start the face liveness session.")))
    }

    @Test
    fun `typed SDK exceptions map through the table`() {
        val table = mapOf(
            FaceLivenessDetectionException.SessionNotFoundException() to ErrorCodeMessage.SESSION_NOT_FOUND,
            FaceLivenessDetectionException.AccessDeniedException() to ErrorCodeMessage.ACCESS_DENIED,
            FaceLivenessDetectionException.SessionInterruptedException() to ErrorCodeMessage.SESSION_INTERRUPTED,
            FaceLivenessDetectionException.SessionTimedOutException() to ErrorCodeMessage.SESSION_TIMED_OUT,
            FaceLivenessDetectionException.UnsupportedChallengeTypeException() to
                ErrorCodeMessage.UNSUPPORTED_CHALLENGE,
            FaceLivenessDetectionException.VideoEncodingException() to ErrorCodeMessage.VIDEO_ENCODING_FAILED,
            FaceLivenessDetectionException.VideoMuxingException() to ErrorCodeMessage.VIDEO_ENCODING_FAILED,
        )
        table.forEach { (error, code) -> assertEquals(code, codeOf(error), error.javaClass.simpleName) }
    }

    @Test
    fun `camera permission error re-reads the permission state`() {
        val error = FaceLivenessDetectionException.CameraPermissionDeniedException()
        assertEquals(ErrorCodeMessage.CAMERA_PERMISSION_DENIED, codeOf(error, permanentlyDenied = false))
        assertEquals(ErrorCodeMessage.CAMERA_PERMISSION_PERMANENTLY_DENIED, codeOf(error, permanentlyDenied = true))
    }

    @Test
    fun `permission state is read only for camera permission errors`() {
        var reads = 0
        ErrorMapper.map(FaceLivenessDetectionException.SessionTimedOutException(), null, false) {
            reads++
            true
        }
        assertEquals(0, reads)
    }

    @Test
    fun `internal face fit timeout class maps to faceFitTimedOut`() {
        val error = Class
            .forName(
                "com.amplifyframework.ui.liveness.model." +
                    "FaceLivenessDetectionException\$FaceInOvalMatchExceededTimeLimitException",
            )
            .getDeclaredConstructor()
            .newInstance() as FaceLivenessDetectionException
        assertEquals(ErrorCodeMessage.FACE_FIT_TIMED_OUT, codeOf(error))
    }

    @Test
    fun `service causes of a generic PredictionsException map by class name`() {
        val table = mapOf(
            ServiceErrors.ValidationException() to ErrorCodeMessage.VALIDATION,
            ServiceErrors.InternalServerException() to ErrorCodeMessage.INTERNAL_SERVER_ERROR,
            ServiceErrors.ThrottlingException() to ErrorCodeMessage.THROTTLED,
            ServiceErrors.ServiceQuotaExceededException() to ErrorCodeMessage.THROTTLED,
            ServiceErrors.ServiceUnavailableException() to ErrorCodeMessage.SERVICE_UNAVAILABLE,
            ServiceErrors.InvalidSignatureException() to ErrorCodeMessage.INVALID_SIGNATURE,
            ServiceErrors.UnrecognizedClientException() to ErrorCodeMessage.ACCESS_DENIED,
        )
        table.forEach { (cause, code) ->
            val error = generic("An error occurred during the face liveness flow.", cause)
            assertEquals(code, codeOf(error), cause.javaClass.simpleName)
        }
    }

    @Test
    fun `messages map when class names are obfuscated`() {
        val table = mapOf(
            "Face did not match oval within time limit." to ErrorCodeMessage.FACE_FIT_TIMED_OUT,
            "Failed since the user made too many requests for a face liveness check." to
                ErrorCodeMessage.THROTTLED,
            "Service is currently unavailable." to ErrorCodeMessage.SERVICE_UNAVAILABLE,
            "Invalid signature" to ErrorCodeMessage.INVALID_SIGNATURE,
            "Unrecognized client" to ErrorCodeMessage.ACCESS_DENIED,
            "The camera failed to open within the allowed time limit." to ErrorCodeMessage.CAMERA_UNAVAILABLE,
            "A front facing camera is required but no front facing camera detected." to
                ErrorCodeMessage.CAMERA_UNAVAILABLE,
            "Failed to initialize video components required for Liveness check." to
                ErrorCodeMessage.VIDEO_ENCODING_FAILED,
        )
        table.forEach { (message, code) ->
            assertEquals(code, codeOf(generic(message, ServiceErrors.SomethingElseException())), message)
        }
    }

    @Test
    fun `anything else is unknown`() {
        assertEquals(ErrorCodeMessage.UNKNOWN, codeOf(generic("Something new.")))
        assertEquals(
            ErrorCodeMessage.UNKNOWN,
            codeOf(generic("An error occurred.", ServiceErrors.SomethingElseException())),
        )
    }

    @Test
    fun `native details carry the class chain and the SDK message`() {
        val outcome = map(generic("Service is currently unavailable.", ServiceErrors.ServiceUnavailableException()))
        assertEquals(OutcomeKindMessage.FAILED, outcome.kind)
        assertEquals(
            "FaceLivenessDetectionException/PredictionsException/ServiceUnavailableException",
            outcome.nativeCode,
        )
        assertEquals("Service is currently unavailable.", outcome.nativeMessage)
        assertEquals("SessionTimedOutException", ErrorMapper.nativeCode(FaceLivenessDetectionException.SessionTimedOutException()))
    }

    @Test
    fun `cancel requests map to the plugin-initiated outcomes`() {
        val app = Outcomes.forCancelRequest(CancelRequestReasonMessage.APP)
        assertEquals(OutcomeKindMessage.CANCELLED, app.kind)
        assertEquals(CancelReasonMessage.APP, app.cancelReason)
        val timeout = Outcomes.forCancelRequest(CancelRequestReasonMessage.TIMEOUT)
        assertEquals(OutcomeKindMessage.FAILED, timeout.kind)
        assertEquals(ErrorCodeMessage.TIMED_OUT, timeout.errorCode)
        assertFalse(Outcomes.completed().let { it.errorCode != null || it.cancelReason != null })
    }
}
