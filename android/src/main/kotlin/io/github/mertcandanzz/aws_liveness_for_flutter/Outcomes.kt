package io.github.mertcandanzz.aws_liveness_for_flutter

/** Builders for the [OutcomeMessage] shapes described in pigeons/messages.dart. */
internal object Outcomes {
    fun completed(): OutcomeMessage = OutcomeMessage(kind = OutcomeKindMessage.COMPLETED)

    fun cancelled(reason: CancelReasonMessage): OutcomeMessage =
        OutcomeMessage(kind = OutcomeKindMessage.CANCELLED, cancelReason = reason)

    fun failed(
        code: ErrorCodeMessage,
        nativeCode: String? = null,
        nativeMessage: String? = null,
    ): OutcomeMessage = OutcomeMessage(
        kind = OutcomeKindMessage.FAILED,
        errorCode = code,
        nativeCode = nativeCode,
        nativeMessage = nativeMessage,
    )

    /** The result of a plugin-initiated end requested by Dart (design §6.3, §6.4). */
    fun forCancelRequest(reason: CancelRequestReasonMessage): OutcomeMessage = when (reason) {
        CancelRequestReasonMessage.APP -> cancelled(CancelReasonMessage.APP)
        CancelRequestReasonMessage.TIMEOUT -> failed(ErrorCodeMessage.TIMED_OUT)
    }
}
