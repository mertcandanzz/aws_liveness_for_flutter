# Applied to apps that use aws_liveness_for_flutter.
#
# ErrorMapper reads the simple class names of the liveness exceptions and of the service errors
# they wrap (design §4.3). Keep the names so typed errors survive R8; the classes themselves
# can still be shrunk.
-keepnames class com.amplifyframework.ui.liveness.model.FaceLivenessDetectionException
-keepnames class com.amplifyframework.ui.liveness.model.FaceLivenessDetectionException$*
-keepnames class com.amplifyframework.predictions.PredictionsException
-keepnames class com.amplifyframework.predictions.aws.exceptions.**
-keepnames class com.amplifyframework.predictions.aws.models.liveness.**
