import Foundation

#if canImport(UIKit)
  import UIKit
#endif

/// A view controller as seen by the presenter lookup; tests use a fake tree.
@MainActor
protocol PresentationNode: AnyObject {
  var nextPresented: PresentationNode? { get }
  var isDismissing: Bool { get }
}

/// Finds the view controller to present the liveness UI from (design §8).
@MainActor
enum Presenter {
  /// The topmost controller in [root]'s presentation chain, skipping one that is being
  /// dismissed (and everything above it).
  static func topmost(from root: PresentationNode) -> PresentationNode {
    var current = root
    while let next = current.nextPresented, !next.isDismissing {
      current = next
    }
    return current
  }
}

#if canImport(UIKit)
  extension UIViewController: PresentationNode {
    var nextPresented: PresentationNode? { presentedViewController }
    var isDismissing: Bool { isBeingDismissed }
  }

  extension Presenter {
    /// First the engine's view controller (`registrar.viewController`), then the key window
    /// of a foreground `UIWindowScene`. Never `UIApplication.keyWindow` or the app delegate's
    /// `window`, which is nil under the UIScene lifecycle. Nil when nothing is in the
    /// foreground (design §6.10).
    static func presentingController(preferred: UIViewController?) -> UIViewController? {
      if let preferred = preferred, isInForeground(preferred) {
        return topmost(from: preferred) as? UIViewController ?? preferred
      }
      for scene in UIApplication.shared.connectedScenes {
        guard let windowScene = scene as? UIWindowScene,
          isForeground(windowScene.activationState)
        else {
          continue
        }
        let window =
          windowScene.keyWindow ?? windowScene.windows.first { $0.rootViewController != nil }
        if let root = window?.rootViewController {
          return topmost(from: root) as? UIViewController ?? root
        }
      }
      return nil
    }

    private static func isInForeground(_ controller: UIViewController) -> Bool {
      guard let window = controller.viewIfLoaded?.window else {
        return false
      }
      guard let scene = window.windowScene else {
        return UIApplication.shared.applicationState != .background
      }
      return isForeground(scene.activationState)
    }

    /// Inactive counts: the scene is briefly inactive right after the camera prompt closes.
    private static func isForeground(_ state: UIScene.ActivationState) -> Bool {
      state == .foregroundActive || state == .foregroundInactive
    }
  }
#endif
