package io.github.mertcandanzz.aws_liveness_for_flutter

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.amplifyframework.ui.liveness.ui.Camera
import com.amplifyframework.ui.liveness.ui.ChallengeOptions
import com.amplifyframework.ui.liveness.ui.FaceLivenessDetector
import com.amplifyframework.ui.liveness.ui.LivenessChallenge

/**
 * Full-screen host for the SDK's `FaceLivenessDetector` (design §6, §7).
 *
 * Every way out of this screen goes through [end] or [onDestroy], which deliver the attempt's
 * result through [SessionRegistry.finish] at most once.
 */
class LivenessActivity : ComponentActivity() {
    private var attempt: ActiveAttempt? = null
    private var attemptToken = NO_TOKEN
    private var isPermissionGranted by mutableStateOf(false)
    private var sdkCancel by mutableStateOf<(() -> Unit)?>(null)
    private val closeUi: () -> Unit = { runOnUiThread { if (!isFinishing) finish() } }

    private val permissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { isGranted ->
            onPermissionResult(isGranted)
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        attemptToken = intent.getLongExtra(EXTRA_TOKEN, NO_TOKEN)
        val found = Shared.sessions.find(attemptToken)
        if (found == null) {
            // Process death or an attempt that already ended: nobody waits for a result, but
            // an ended attempt's result may wait for this screen to go (onDestroy).
            finish()
            return
        }
        attempt = found
        if (savedInstanceState != null) {
            // Recreated with the Dart side still waiting; the SDK session state is gone.
            Shared.sessions.finish(found, interrupted("ActivityRecreated"))
            finish()
            return
        }
        found.closeUi = closeUi
        setContent { LivenessScreen(found) }
        if (CameraPermission.isGranted(this)) {
            isPermissionGranted = true
        } else {
            permissionLauncher.launch(CameraPermission.PERMISSION)
        }
    }

    override fun onStop() {
        super.onStop()
        // Rule 6.5: once the liveness UI is visible, leaving it ends the attempt.
        if (isPermissionGranted && !isChangingConfigurations && !isFinishing) {
            end(interrupted("ActivityStopped"))
        }
    }

    override fun onDestroy() {
        attempt?.let { current ->
            if (current.closeUi === closeUi) {
                current.closeUi = null
            }
            current.sdkCancel = null
            if (!isChangingConfigurations) {
                Shared.sessions.finish(current, interrupted("ActivityDestroyed"))
            }
        }
        if (!isChangingConfigurations) {
            // The host Activity is in front again: release a result waiting for this screen.
            Shared.sessions.uiClosed(attemptToken)
        }
        super.onDestroy()
    }

    private fun onPermissionResult(isGranted: Boolean) {
        val status = CameraPermission.statusAfterRequest(isGranted, CameraPermission.shouldShowRationale(this))
        val error = CameraPermission.errorFor(status)
        if (error == null) {
            isPermissionGranted = true
        } else {
            end(Outcomes.failed(error, "CameraPermission", status.name))
        }
    }

    private fun onBack() {
        val cancel = sdkCancel
        if (cancel != null) {
            // The SDK closes its session and reports UserCancelledException.
            cancel()
        } else {
            end(Outcomes.cancelled(CancelReasonMessage.USER))
        }
    }

    private fun end(outcome: OutcomeMessage) {
        attempt?.let { Shared.sessions.finish(it, outcome) }
        if (!isFinishing) {
            finish()
        }
    }

    private fun isPermissionPermanentlyDenied(): Boolean =
        !CameraPermission.isGranted(this) && !CameraPermission.shouldShowRationale(this)

    @Composable
    private fun LivenessScreen(attempt: ActiveAttempt) {
        val theme = attempt.request.theme
        val isDark = ThemeMapper.isDark(theme.mode, isSystemInDarkTheme())
        val colorScheme = remember(isDark) { ThemeMapper.colorScheme(theme, isDark) }
        MaterialTheme(colorScheme = colorScheme) {
            BackHandler { onBack() }
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(MaterialTheme.colorScheme.background)
                    .systemBarsPadding(),
            ) {
                if (isPermissionGranted) {
                    Detector(attempt)
                    if (sdkCancel == null) {
                        // Start view and connecting phase: the SDK shows no cancel control yet.
                        LivenessCancelButton { end(Outcomes.cancelled(CancelReasonMessage.USER)) }
                    }
                }
            }
        }
    }

    @Composable
    private fun Detector(attempt: ActiveAttempt) {
        val request = attempt.request
        val provider = attempt.credentialsProvider
        if (provider == null) {
            DisposableEffect(Unit) {
                end(Outcomes.failed(ErrorCodeMessage.CREDENTIALS_UNAVAILABLE, "NoCredentialsProvider"))
                onDispose {}
            }
            return
        }
        val camera = if (request.faceMovementCamera == CameraMessage.BACK) Camera.Back else Camera.Front
        val challengeOptions = remember(camera) {
            ChallengeOptions(faceMovement = LivenessChallenge.FaceMovement(camera = camera))
        }
        FaceLivenessDetector(
            sessionId = request.sessionId,
            region = request.region,
            credentialsProvider = provider,
            disableStartView = !request.showStartView,
            onComplete = { end(Outcomes.completed()) },
            onError = { error ->
                end(
                    ErrorMapper.map(
                        error = error,
                        pluginEnd = null,
                        credentialsFailed = attempt.credentialsFailed,
                        isPermissionPermanentlyDenied = ::isPermissionPermanentlyDenied,
                    ),
                )
            },
            challengeOptions = challengeOptions,
            cancelButton = { onCancel ->
                DisposableEffect(onCancel) {
                    sdkCancel = onCancel
                    attempt.sdkCancel = onCancel
                    onDispose {
                        if (sdkCancel === onCancel) {
                            sdkCancel = null
                        }
                        if (attempt.sdkCancel === onCancel) {
                            attempt.sdkCancel = null
                        }
                    }
                }
                LivenessCancelButton(onCancel)
            },
        )
    }

    private fun interrupted(nativeCode: String): OutcomeMessage =
        Outcomes.failed(ErrorCodeMessage.SESSION_INTERRUPTED, nativeCode)

    internal companion object {
        private const val EXTRA_TOKEN = "io.github.mertcandanzz.aws_liveness_for_flutter.ATTEMPT_TOKEN"
        private const val NO_TOKEN = -1L

        fun intent(context: Context, attemptToken: Long): Intent =
            Intent(context, LivenessActivity::class.java).putExtra(EXTRA_TOKEN, attemptToken)
    }
}

/** The plugin's cancel control: localized label and TalkBack description (design §9.7). */
@Composable
private fun BoxScope.LivenessCancelButton(onCancel: () -> Unit) {
    val description = stringResource(R.string.aws_liveness_cancel_content_description)
    TextButton(
        onClick = onCancel,
        modifier = Modifier
            .align(Alignment.TopEnd)
            .padding(16.dp)
            .semantics { contentDescription = description },
        colors = ButtonDefaults.textButtonColors(
            containerColor = MaterialTheme.colorScheme.background,
            contentColor = MaterialTheme.colorScheme.onBackground,
        ),
    ) {
        Text(stringResource(R.string.aws_liveness_cancel))
    }
}
