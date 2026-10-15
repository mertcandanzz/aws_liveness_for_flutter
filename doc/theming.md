# Theming

`LivenessRequest.theme` controls the colours and the light/dark mode of the native
liveness screen.

```dart
const theme = LivenessTheme(
  mode: LivenessThemeMode.system, // system, light or dark
  light: LivenessColors(primary: Color(0xFF00695C)),
  dark: LivenessColors(
    primary: Color(0xFF4DB6AC),
    background: Color(0xFF101414),
  ),
);
```

- `mode` picks the colour set. `system` follows the device setting.
- `light` and `dark` override individual tokens. A token you leave `null` keeps the SDK
  default.
- Colours travel to native code as 32-bit ARGB values.

## Tokens

Only the tokens that exist in both SDKs are exposed:

| `LivenessColors` | Android (`LivenessColorScheme`, Material 3) | iOS (`FaceLivenessDetectorTheme.Colors`) |
|---|---|---|
| `primary` | `primary` | `primary` |
| `onPrimary` | `onPrimary` | `onPrimary` |
| `background` | `background` | `background` |
| `onBackground` | `onBackground` (and `onSurface`) | `onBackground` |
| `surface` | `surface` | `surface` |
| `error` | `error` | `error` |
| `onError` | `onError` | `onError` |
| `errorContainer` | `errorContainer` | `errorContainer` |
| `onErrorContainer` | `onErrorContainer` | `onErrorContainer` |

Android has an `onSurface` token that iOS lacks; the plugin sets it from your
`onBackground` override.

## How each platform applies it

- **Android:** the plugin starts from the SDK's light or dark `LivenessColorScheme` for the
  resolved mode and applies your overrides.
- **iOS:** in `system` mode each overridden token becomes a dynamic `UIColor` with the light
  and dark value; a forced mode also overrides the screen's interface style.

## Not exposed

- Fonts (iOS only in the SDK), shapes and typography (Android only).
- The look of the cancel control: iOS uses the SDK's close button.
- The flashing colours of the FaceMovementAndLight challenge: they are part of the check.

Contrast: the SDK screens show instructions on `background` and buttons on `primary`.
Check your overrides against WCAG contrast guidelines, and test with large text.
