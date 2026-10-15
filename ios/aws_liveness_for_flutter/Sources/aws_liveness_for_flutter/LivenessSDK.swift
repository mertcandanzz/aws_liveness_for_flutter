import Foundation

#if canImport(FaceLiveness)
  import FaceLiveness
#endif

/// Whether the FaceLiveness Swift package is usable in this build (design §8).
enum LivenessSDK {
  /// False in CocoaPods builds: FaceLiveness ships only through Swift Package Manager.
  static var isLinked: Bool {
    #if canImport(FaceLiveness)
      return true
    #else
      return false
    #endif
  }

  /// The SDK's face detector model. `FaceLivenessDetectorView.init` loads it with
  /// `try! FaceDetectorShortRange.Model()`, which crashes if the model is missing, so the
  /// plugin looks for it before it creates the view.
  static let faceDetectorModelName = "face_detection_short_range.mlmodelc"

  /// Cached: the app bundle does not change while the process runs.
  static let isFaceDetectorModelBundled: Bool = containsFaceDetectorModel(
    in: Bundle.main.bundleURL)

  /// Searches [root] (the app bundle) a few levels deep, which covers SwiftPM resource
  /// bundles at the root and inside embedded frameworks. Flutter assets are skipped.
  static func containsFaceDetectorModel(
    in root: URL, maxDepth: Int = 4, fileManager: FileManager = .default
  ) -> Bool {
    guard
      let enumerator = fileManager.enumerator(
        at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    else {
      return false
    }
    for case let url as URL in enumerator {
      let name = url.lastPathComponent
      if name == faceDetectorModelName {
        return true
      }
      if name == "flutter_assets" || name.hasSuffix(".mlmodelc") || enumerator.level >= maxDepth {
        enumerator.skipDescendants()
      }
    }
    return false
  }
}
