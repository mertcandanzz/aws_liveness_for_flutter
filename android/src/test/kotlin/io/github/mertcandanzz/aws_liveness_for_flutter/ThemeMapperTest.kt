package io.github.mertcandanzz.aws_liveness_for_flutter

import androidx.compose.ui.graphics.Color
import com.amplifyframework.ui.liveness.ui.LivenessColorScheme
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ThemeMapperTest {
    private val light = LivenessColorScheme.Defaults.lightColorScheme
    private val dark = LivenessColorScheme.Defaults.darkColorScheme

    @Test
    fun `mode resolves light or dark`() {
        assertTrue(ThemeMapper.isDark(ThemeModeMessage.SYSTEM, isSystemDark = true))
        assertFalse(ThemeMapper.isDark(ThemeModeMessage.SYSTEM, isSystemDark = false))
        assertFalse(ThemeMapper.isDark(ThemeModeMessage.LIGHT, isSystemDark = true))
        assertTrue(ThemeMapper.isDark(ThemeModeMessage.DARK, isSystemDark = false))
    }

    @Test
    fun `no overrides keeps the SDK defaults`() {
        val theme = ThemeMessage(mode = ThemeModeMessage.SYSTEM)
        assertEquals(light, ThemeMapper.colorScheme(theme, isDark = false))
        assertEquals(dark, ThemeMapper.colorScheme(theme, isDark = true))
    }

    @Test
    fun `overrides apply per brightness and keep unset tokens`() {
        val theme = ThemeMessage(
            mode = ThemeModeMessage.SYSTEM,
            light = ColorsMessage(primary = 0xFF112233, error = 0x80FF0000),
            dark = ColorsMessage(background = 0xFF000000),
        )

        val lightScheme = ThemeMapper.colorScheme(theme, isDark = false)
        assertEquals(Color(0xFF112233), lightScheme.primary)
        assertEquals(Color(0x80FF0000), lightScheme.error)
        assertEquals(light.background, lightScheme.background)
        assertEquals(light.onSurface, lightScheme.onSurface)

        val darkScheme = ThemeMapper.colorScheme(theme, isDark = true)
        assertEquals(Color(0xFF000000), darkScheme.background)
        assertEquals(dark.primary, darkScheme.primary)
    }

    @Test
    fun `every shared token is mapped`() {
        val colors = ColorsMessage(
            primary = 0xFF000001,
            onPrimary = 0xFF000002,
            background = 0xFF000003,
            onBackground = 0xFF000004,
            surface = 0xFF000005,
            error = 0xFF000006,
            onError = 0xFF000007,
            errorContainer = 0xFF000008,
            onErrorContainer = 0xFF000009,
        )
        val scheme = ThemeMapper.colorScheme(ThemeMessage(ThemeModeMessage.LIGHT, light = colors), isDark = false)
        assertEquals(
            listOf(
                scheme.primary, scheme.onPrimary, scheme.background, scheme.onBackground, scheme.surface,
                scheme.error, scheme.onError, scheme.errorContainer, scheme.onErrorContainer,
            ),
            (1L..9L).map { Color(0xFF000000 + it) },
        )
        assertEquals(scheme.onBackground, scheme.onSurface, "onSurface follows onBackground")
    }
}
