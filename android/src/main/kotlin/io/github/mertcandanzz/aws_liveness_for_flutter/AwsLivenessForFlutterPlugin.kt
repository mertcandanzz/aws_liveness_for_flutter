package io.github.mertcandanzz.aws_liveness_for_flutter

import android.app.Activity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding

/**
 * Entry point registered with the Flutter engine. One instance per engine; the active
 * liveness attempt is shared process-wide through [SessionRegistry].
 */
class AwsLivenessForFlutterPlugin : FlutterPlugin, ActivityAware {
    private var hostApi: LivenessHostApiImpl? = null
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val flutterApi = LivenessFlutterApi(binding.binaryMessenger)
        val api = LivenessHostApiImpl(
            context = binding.applicationContext,
            engineToken = Any(),
            activity = { activity },
            fetcher = { attemptId, callback -> flutterApi.fetchCredentials(attemptId, callback) },
        )
        hostApi = api
        LivenessHostApi.setUp(binding.binaryMessenger, api)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        LivenessHostApi.setUp(binding.binaryMessenger, null)
        hostApi?.dispose()
        hostApi = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}
