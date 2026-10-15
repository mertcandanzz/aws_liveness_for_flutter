import Flutter
import UIKit

/// Entry point registered with the Flutter engine. One instance per engine; the active
/// liveness attempt is shared process-wide through `SessionCoordinator`.
///
/// No AppDelegate or SceneDelegate changes are needed: the plugin finds its presenter
/// through the registrar and the connected scenes, and observes backgrounding itself.
public final class AwsLivenessForFlutterPlugin: NSObject, FlutterPlugin {
  private let engine = EngineToken()
  private var host: LivenessHost?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = AwsLivenessForFlutterPlugin()
    plugin.attach(to: registrar)
    // Publishing makes the engine call detachFromEngine(for:) before it is destroyed.
    registrar.publish(plugin)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    LivenessHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
    MainActor.assumeIsolated {
      host?.dispose()
    }
    host = nil
  }

  private func attach(to registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let flutterApi = LivenessFlutterApi(binaryMessenger: messenger)
    let host = MainActor.assumeIsolated {
      LivenessHost.system(
        engine: engine,
        viewController: { [weak registrar] in registrar?.viewController },
        fetcher: { attemptId, completion in
          flutterApi.fetchCredentials(attemptId: attemptId) { result in
            completion(result.mapError { $0 as Error })
          }
        })
    }
    self.host = host
    LivenessHostApiSetup.setUp(binaryMessenger: messenger, api: LivenessHostApiImpl(host: host))
  }
}

/// Identifies the engine that owns an attempt.
private final class EngineToken {}
