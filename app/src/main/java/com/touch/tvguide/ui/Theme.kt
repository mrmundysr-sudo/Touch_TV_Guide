package com.touch.tvguide.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import com.touch.tvguide.data.ThemeMode

private val Dark = darkColorScheme(
    primary = Color(0xFFFFC247), onPrimary = Color(0xFF241A00), primaryContainer = Color(0xFF3A2D00), onPrimaryContainer = Color(0xFFFFE08A),
    secondary = Color(0xFF8FB4FF), onSecondary = Color(0xFF002A6B), secondaryContainer = Color(0xFF1F3560), onSecondaryContainer = Color(0xFFD8E4FF),
    background = Color(0xFF10141C), onBackground = Color(0xFFE6E9F0), surface = Color(0xFF10141C), onSurface = Color(0xFFE6E9F0),
    surfaceVariant = Color(0xFF232A38), onSurfaceVariant = Color(0xFFC3C8D6), error = Color(0xFFFFB4AB), outline = Color(0xFF8C93A3),
)
private val Light = lightColorScheme(
    primary = Color(0xFF7A5200), onPrimary = Color.White, primaryContainer = Color(0xFFFFDEA0), onPrimaryContainer = Color(0xFF261900),
    secondary = Color(0xFF1F4FA6), onSecondary = Color.White, secondaryContainer = Color(0xFFD8E4FF), onSecondaryContainer = Color(0xFF001A44),
    background = Color(0xFFF8F9FC), onBackground = Color(0xFF14181F), surface = Color(0xFFF8F9FC), onSurface = Color(0xFF14181F),
    surfaceVariant = Color(0xFFE3E6EE), onSurfaceVariant = Color(0xFF424754), error = Color(0xFFB3261E), outline = Color(0xFF707584),
)

@Composable
fun TvGuideTheme(mode: ThemeMode, fontScale: Float, content: @Composable () -> Unit) {
    val dark = when (mode) { ThemeMode.System -> isSystemInDarkTheme(); ThemeMode.Dark -> true; ThemeMode.Light -> false }
    val d = LocalDensity.current
    CompositionLocalProvider(LocalDensity provides Density(d.density, d.fontScale * fontScale)) {
        MaterialTheme(colorScheme = if (dark) Dark else Light, content = content)
    }
}
