#if canImport(UIKit)
  import AVFoundation
  import UIKit

  /// AVFoundation camera and permission state of the running app.
  @MainActor
  final class SystemCameraAccess: CameraAccess {
    var authorization: CameraAuthorization {
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized: return .authorized
      case .denied: return .denied
      case .restricted: return .restricted
      case .notDetermined: return .notDetermined
      @unknown default: return .notDetermined
      }
    }

    var hasVideoDevice: Bool {
      !AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified
      ).devices.isEmpty
    }

    var usageDescription: String? {
      Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String
    }

    func requestAccess(_ completion: @escaping @MainActor (Bool) -> Void) {
      AVCaptureDevice.requestAccess(for: .video) { granted in
        MainThread.run {
          completion(granted)
        }
      }
    }
  }

  @MainActor
  final class SystemSettingsOpener: SettingsOpening {
    func open(_ completion: @escaping @MainActor (Bool) -> Void) {
      guard let url = URL(string: UIApplication.openSettingsURLString) else {
        completion(false)
        return
      }
      UIApplication.shared.open(url, options: [:]) { opened in
        MainThread.run {
          completion(opened)
        }
      }
    }
  }

  extension LivenessHost {
    /// The production host for one engine.
    static func system(
      engine: AnyObject,
      viewController: @escaping @MainActor () -> UIViewController?,
      fetcher: @escaping CredentialsFetcher
    ) -> LivenessHost {
      LivenessHost(
        engine: engine,
        sessions: .shared,
        sdk: SdkStatus(
          isLinked: LivenessSDK.isLinked,
          isFaceDetectorModelBundled: { LivenessSDK.isLinked && LivenessSDK.isFaceDetectorModelBundled }),
        camera: SystemCameraAccess(),
        presenter: SystemLivenessPresenter(viewController: viewController),
        settings: SystemSettingsOpener(),
        fetcher: fetcher,
        scheduler: MainQueueScheduler())
    }
  }
#endif
