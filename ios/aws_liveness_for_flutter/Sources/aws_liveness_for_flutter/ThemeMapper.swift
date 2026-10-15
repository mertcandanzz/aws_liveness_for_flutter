import Foundation

#if canImport(UIKit)
  import UIKit
#endif
#if canImport(FaceLiveness)
  import FaceLiveness
  import SwiftUI
#endif

/// An ARGB32 colour from Dart's `Color.toARGB32()`, split into 0...1 components.
struct ArgbColor: Equatable {
  let red: Double
  let green: Double
  let blue: Double
  let alpha: Double

  init(argb: Int64) {
    let value = UInt32(truncatingIfNeeded: argb)
    alpha = Double((value >> 24) & 0xFF) / 255
    red = Double((value >> 16) & 0xFF) / 255
    green = Double((value >> 8) & 0xFF) / 255
    blue = Double(value & 0xFF) / 255
  }
}

#if canImport(UIKit)
  extension UIColor {
    convenience init(argb: Int64) {
      let color = ArgbColor(argb: argb)
      self.init(
        red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue),
        alpha: CGFloat(color.alpha))
    }
  }

  /// Builds the SDK theme from the Dart theme (design §3.3).
  @MainActor
  enum ThemeMapper {
    /// Forced modes also force the hosting controller's appearance, so the SDK's own views
    /// (alerts, system controls) match.
    static func interfaceStyle(for mode: ThemeModeMessage) -> UIUserInterfaceStyle {
      switch mode {
      case .system: return .unspecified
      case .light: return .light
      case .dark: return .dark
      }
    }
  }

  #if canImport(FaceLiveness)
    extension ThemeMapper {
      struct Token {
        let sdk: WritableKeyPath<FaceLivenessDetectorTheme.Colors, Color>
        let dart: KeyPath<ColorsMessage, Int64?>
      }

      /// The nine colour tokens both SDKs share.
      static func tokens() -> [Token] {
        [
          Token(sdk: \.primary, dart: \.primary),
          Token(sdk: \.onPrimary, dart: \.onPrimary),
          Token(sdk: \.background, dart: \.background),
          Token(sdk: \.onBackground, dart: \.onBackground),
          Token(sdk: \.surface, dart: \.surface),
          Token(sdk: \.error, dart: \.error),
          Token(sdk: \.onError, dart: \.onError),
          Token(sdk: \.errorContainer, dart: \.errorContainer),
          Token(sdk: \.onErrorContainer, dart: \.onErrorContainer),
        ]
      }

      static func theme(for message: ThemeMessage) -> FaceLivenessDetectorTheme {
        switch message.mode {
        case .light:
          return fixed(.light, overrides: message.light)
        case .dark:
          return fixed(.dark, overrides: message.dark)
        case .system:
          return adaptive(light: message.light, dark: message.dark)
        }
      }

      private static func fixed(_ scheme: ColorScheme, overrides: ColorsMessage?)
        -> FaceLivenessDetectorTheme
      {
        let theme = FaceLivenessDetectorTheme(colorScheme: scheme)
        guard let overrides = overrides else {
          return theme
        }
        for token in tokens() {
          if let argb = overrides[keyPath: token.dart] {
            theme.colors[keyPath: token.sdk] = Color(uiColor: UIColor(argb: argb))
          }
        }
        return theme
      }

      /// Overridden tokens become dynamic colours; a side without an override keeps the
      /// SDK default for that appearance.
      private static func adaptive(light: ColorsMessage?, dark: ColorsMessage?)
        -> FaceLivenessDetectorTheme
      {
        let theme = FaceLivenessDetectorTheme()
        guard light != nil || dark != nil else {
          return theme
        }
        let lightDefaults = FaceLivenessDetectorTheme(colorScheme: .light).colors
        let darkDefaults = FaceLivenessDetectorTheme(colorScheme: .dark).colors
        for token in tokens() {
          let lightArgb = light?[keyPath: token.dart]
          let darkArgb = dark?[keyPath: token.dart]
          guard lightArgb != nil || darkArgb != nil else {
            continue
          }
          let lightColor = lightArgb.map { UIColor(argb: $0) } ?? UIColor(lightDefaults[keyPath: token.sdk])
          let darkColor = darkArgb.map { UIColor(argb: $0) } ?? UIColor(darkDefaults[keyPath: token.sdk])
          theme.colors[keyPath: token.sdk] = Color(
            uiColor: UIColor { traits in
              traits.userInterfaceStyle == .dark ? darkColor : lightColor
            })
        }
        return theme
      }
    }
  #endif
#endif
