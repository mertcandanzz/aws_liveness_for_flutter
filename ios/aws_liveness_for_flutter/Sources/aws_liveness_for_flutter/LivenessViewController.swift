#if canImport(UIKit)
  import UIKit

  #if canImport(FaceLiveness)
    import FaceLiveness
    import SwiftUI

    /// Presents `FaceLivenessDetectorView` full screen in a `UIHostingController` (design §8).
    @MainActor
    final class SystemLivenessPresenter: LivenessPresenting {
      private let viewController: @MainActor () -> UIViewController?

      init(viewController: @escaping @MainActor () -> UIViewController?) {
        self.viewController = viewController
      }

      func present(
        _ attempt: ActiveAttempt, credentials: CredentialsBroker, events: LivenessEvents
      ) -> Bool {
        // Look the presenter up first: creating the detector view starts the session.
        guard let presenter = Presenter.presentingController(preferred: viewController()) else {
          return false
        }
        let request = attempt.request
        let controller = LivenessViewController(
          rootView: LivenessContainer(
            detector: FaceLivenessDetectorView(
              sessionID: request.sessionId,
              credentialsProvider: PluginCredentialsProvider(broker: credentials),
              region: request.region,
              disableStartView: !request.showStartView,
              challengeOptions: ChallengeOptions(
                faceMovementChallengeOption: FaceMovementChallengeOption(
                  camera: request.faceMovementCamera == .back ? .back : .front)),
              // A constant binding: the SDK sets it to false when it finishes, and the
              // plugin closes the UI itself. Real state would re-run the view initialiser,
              // which starts a new session.
              isPresented: .constant(true),
              onCompletion: { result in
                // FaceLiveness may complete on a background queue.
                MainThread.run {
                  switch result {
                  case .success:
                    events.completed()
                  case .failure(let error):
                    events.failed(SdkError(error))
                  }
                }
              }),
            theme: ThemeMapper.theme(for: request.theme)),
          events: events,
          interfaceStyle: ThemeMapper.interfaceStyle(for: request.theme.mode))
        attempt.closeUI = { [weak controller] completion in
          guard let controller = controller else {
            completion()
            return
          }
          controller.close(completion)
        }
        presenter.present(controller, animated: true)
        // UIKit ignores a presentation it cannot perform (the presenter left the window,
        // or is already presenting); report that instead of waiting forever.
        return controller.isBeingPresented || controller.presentingViewController != nil
      }
    }

    /// The SwiftUI root. The detector view is created once and stored, so re-rendering never
    /// runs its initialiser again.
    struct LivenessContainer: View {
      let detector: FaceLivenessDetectorView
      let theme: FaceLivenessDetectorTheme

      var body: some View {
        detector.faceLivenessDetectorTheme(theme)
      }
    }

    /// Full-screen host for the liveness UI. Reports `interrupted` when the app goes to the
    /// background while it is visible, or when it disappears without the plugin closing it
    /// (design §6.5, §6.7).
    final class LivenessViewController: UIHostingController<LivenessContainer> {
      private let events: LivenessEvents
      private var isClosing = false
      private var pendingClose: (@MainActor () -> Void)?

      init(rootView: LivenessContainer, events: LivenessEvents, interfaceStyle: UIUserInterfaceStyle) {
        self.events = events
        super.init(rootView: rootView)
        modalPresentationStyle = .fullScreen
        overrideUserInterfaceStyle = interfaceStyle
      }

      @available(*, unavailable)
      required init?(coder aDecoder: NSCoder) {
        return nil
      }

      override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let center = NotificationCenter.default
        center.addObserver(
          self, selector: #selector(sceneDidEnterBackground(_:)),
          name: UIScene.didEnterBackgroundNotification, object: nil)
        center.addObserver(
          self, selector: #selector(appDidEnterBackground(_:)),
          name: UIApplication.didEnterBackgroundNotification, object: nil)
        if let pendingClose = pendingClose {
          self.pendingClose = nil
          dismissFromPresenter(pendingClose)
        }
      }

      override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        NotificationCenter.default.removeObserver(self)
        if !isClosing {
          events.interrupted("ViewDisappeared")
        }
      }

      /// Closes the UI; [completion] runs once it is gone. A close requested while the
      /// presentation is still running waits for it to finish.
      func close(_ completion: @escaping @MainActor () -> Void) {
        isClosing = true
        if isBeingPresented {
          pendingClose = completion
          return
        }
        dismissFromPresenter(completion)
      }

      private func dismissFromPresenter(_ completion: @escaping @MainActor () -> Void) {
        // Dismissing from the presenter also removes anything the SDK presented on top,
        // such as its camera permission alert.
        guard let presenting = presentingViewController else {
          completion()
          return
        }
        presenting.dismiss(animated: true) {
          MainActor.assumeIsolated(completion)
        }
      }

      @objc private func sceneDidEnterBackground(_ notification: Notification) {
        guard let scene = notification.object as? UIScene,
          let ownScene = view.window?.windowScene, scene === ownScene
        else {
          return
        }
        events.interrupted("AppBackgrounded")
      }

      @objc private func appDidEnterBackground(_ notification: Notification) {
        events.interrupted("AppBackgrounded")
      }
    }

    /// The SDK's credentials hook. Holds no credentials: each call asks Dart again.
    final class PluginCredentialsProvider: AWSCredentialsProvider {
      private let broker: CredentialsBroker

      init(broker: CredentialsBroker) {
        self.broker = broker
      }

      func fetchAWSCredentials() async throws -> AWSCredentials {
        try await broker.fetch()
      }
    }

    extension PluginTemporaryCredentials: AWSTemporaryCredentials {}

    extension SdkError {
      /// `FaceLivenessDetectionError.code` is internal to the SDK; its public static cases
      /// compare by code, so the index in this list is the SDK's code.
      init(_ error: FaceLivenessDetectionError) {
        let known: [FaceLivenessDetectionError] = [
          .unknown,
          .sessionNotFound,
          .sessionTimedOut,
          .faceInOvalMatchExceededTimeLimitError,
          .accessDenied,
          .cameraPermissionDenied,
          .userCancelled,
          .socketClosed,
          .countdownFaceTooClose,
          .countdownMultipleFaces,
          .countdownNoFace,
          .invalidRegion,
          .validation,
          .internalServer,
          .throttling,
          .serviceQuotaExceeded,
          .serviceUnavailable,
          .invalidSignature,
          .cameraNotAvailable,
          .sessionInterrupted,
        ]
        self.init(code: known.firstIndex(of: error) ?? -1, message: error.message)
      }
    }
  #else
    /// CocoaPods builds: FaceLiveness is not linked, and `LivenessHost` reports
    /// `sdkUnavailable` before it would present anything.
    @MainActor
    final class SystemLivenessPresenter: LivenessPresenting {
      init(viewController: @escaping @MainActor () -> UIViewController?) {}

      func present(
        _ attempt: ActiveAttempt, credentials: CredentialsBroker, events: LivenessEvents
      ) -> Bool {
        false
      }
    }
  #endif
#endif
