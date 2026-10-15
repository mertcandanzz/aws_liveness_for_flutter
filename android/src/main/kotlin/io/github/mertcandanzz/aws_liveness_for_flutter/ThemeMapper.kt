package io.github.mertcandanzz.aws_liveness_for_flutter

import androidx.compose.material3.ColorScheme
import androidx.compose.ui.graphics.Color
import com.amplifyframework.ui.liveness.ui.LivenessColorScheme

/** Builds the SDK colour scheme from the Dart theme (design §3.3). */
internal object ThemeMapper {
    fun isDark(mode: ThemeModeMessage, isSystemDark: Boolean): Boolean = when (mode) {
        ThemeModeMessage.SYSTEM -> isSystemDark
        ThemeModeMessage.LIGHT -> false
        ThemeModeMessage.DARK -> true
    }

    fun colorScheme(theme: ThemeMessage, isDark: Boolean): ColorScheme {
        val base = if (isDark) {
            LivenessColorScheme.Defaults.darkColorScheme
        } else {
            LivenessColorScheme.Defaults.lightColorScheme
        }
        val overrides = (if (isDark) theme.dark else theme.light) ?: return base
        val onBackground = color(overrides.onBackground, base.onBackground)
        return base.copy(
            primary = color(overrides.primary, base.primary),
            onPrimary = color(overrides.onPrimary, base.onPrimary),
            background = color(overrides.background, base.background),
            onBackground = onBackground,
            surface = color(overrides.surface, base.surface),
            // iOS has no onSurface token; Android follows the onBackground override.
            onSurface = if (overrides.onBackground != null) onBackground else base.onSurface,
            error = color(overrides.error, base.error),
            onError = color(overrides.onError, base.onError),
            errorContainer = color(overrides.errorContainer, base.errorContainer),
            onErrorContainer = color(overrides.onErrorContainer, base.onErrorContainer),
        )
    }

    /** [argb] is an ARGB32 value from Dart's `Color.toARGB32()`. */
    private fun color(argb: Long?, fallback: Color): Color = argb?.let { Color(it.toInt()) } ?: fallback
}
