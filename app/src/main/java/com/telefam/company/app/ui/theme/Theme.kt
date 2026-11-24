package com.telefam.company.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val TelefamLightScheme = lightColorScheme(
    primary = TelefamCrimson,
    onPrimary = Color.White,
    primaryContainer = TelefamCrimsonSoft,
    onPrimaryContainer = TelefamCrimsonDark,
    secondary = TelefamInkPrimary,
    onSecondary = Color.White,
    background = TelefamSurfaceWhite,
    onBackground = TelefamInkPrimary,
    surface = TelefamSurfaceWhite,
    onSurface = TelefamInkPrimary,
    surfaceVariant = TelefamSurfaceSubtle,
    onSurfaceVariant = TelefamInkSecondary,
    outline = TelefamBorderLight,
    outlineVariant = TelefamDividerLight,
    error = TelefamCrimson,
    onError = Color.White
)

private val TelefamDarkScheme = darkColorScheme(
    primary = TelefamCrimson,
    onPrimary = Color.White,
    primaryContainer = TelefamCrimsonDark,
    onPrimaryContainer = Color.White,
    secondary = Color.White,
    onSecondary = TelefamDarkBackground,
    background = TelefamDarkBackground,
    onBackground = Color.White,
    surface = TelefamDarkSurface,
    onSurface = Color.White,
    surfaceVariant = TelefamDarkBar,
    onSurfaceVariant = TelefamDarkSecondaryText,
    outline = TelefamDarkBorder,
    outlineVariant = TelefamDarkBorder,
    error = TelefamCrimsonSoft,
    onError = TelefamCrimsonDark
)

@Composable
fun TelefamTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val scheme = if (darkTheme) TelefamDarkScheme else TelefamLightScheme
    MaterialTheme(
        colorScheme = scheme,
        typography = TelefamTypography,
        content = content
    )
}
