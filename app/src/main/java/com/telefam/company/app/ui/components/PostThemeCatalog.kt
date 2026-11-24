package com.telefam.company.app.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import kotlin.math.cos
import kotlin.math.sin

data class PostBgColorOption(
    val hex: String,
    val color: Color,
    val isDarkText: Boolean = false
)

data class PostImageThemeOption(
    val id: String,
    val name: String,
    val primaryColor: Color,
    val secondaryColor: Color,
    val accentColor: Color,
    val isDarkText: Boolean = false
)

val POST_BG_COLORS: List<PostBgColorOption> = listOf(
    PostBgColorOption("#C81010", Color(0xFFC81010)),
    PostBgColorOption("#FF9E5E", Color(0xFFFF9E5E)),
    PostBgColorOption("#169AE6", Color(0xFF169AE6)),
    PostBgColorOption("#149A5A", Color(0xFF149A5A)),
    PostBgColorOption("#8B5CF6", Color(0xFF8B5CF6)),
    PostBgColorOption("#232B38", Color(0xFF232B38)),
    PostBgColorOption("#F5EEDC", Color(0xFFF5EEDC), isDarkText = true),
    PostBgColorOption("#E11D48", Color(0xFFE11D48)),
    PostBgColorOption("#0D9488", Color(0xFF0D9488)),
    PostBgColorOption("#4338CA", Color(0xFF4338CA)),
    PostBgColorOption("#D97706", Color(0xFFD97706)),
    PostBgColorOption("#BE185D", Color(0xFFBE185D)),
    PostBgColorOption("#0F172A", Color(0xFF0F172A)),
    PostBgColorOption("#10B981", Color(0xFF10B981))
)

val POST_IMAGE_THEMES: List<PostImageThemeOption> = listOf(
    PostImageThemeOption("aurora", "Aurora", Color(0xFF081C24), Color(0xFF10B981), Color(0xFF38BDF8)),
    PostImageThemeOption("sunset_peaks", "Sunset Peaks", Color(0xFF7C2D12), Color(0xFFFB7185), Color(0xFFFBBF24)),
    PostImageThemeOption("starry_night", "Starry Night", Color(0xFF0B1026), Color(0xFF1E3A8A), Color(0xFFFDE047)),
    PostImageThemeOption("ocean_waves", "Ocean Waves", Color(0xFF042F4B), Color(0xFF0284C7), Color(0xFF7DD3FC)),
    PostImageThemeOption("desert_dunes", "Desert Dunes", Color(0xFF9A3412), Color(0xFFF59E0B), Color(0xFFFED7AA)),
    PostImageThemeOption("sakura_blossom", "Sakura", Color(0xFF831843), Color(0xFFF472B6), Color(0xFFFCE7F3)),
    PostImageThemeOption("cyber_grid", "Cyber Grid", Color(0xFF090D16), Color(0xFF9333EA), Color(0xFF22D3EE)),
    PostImageThemeOption("forest_mist", "Forest Mist", Color(0xFF064E3B), Color(0xFF059669), Color(0xFFA7F3D0)),
    PostImageThemeOption("marble_gold", "Marble Gold", Color(0xFF1C1917), Color(0xFF44403C), Color(0xFFFBBF24)),
    PostImageThemeOption("neon_horizon", "Neon Horizon", Color(0xFF311042), Color(0xFFEC4899), Color(0xFFFACC15)),
    PostImageThemeOption("abstract_prism", "Prism", Color(0xFF1E1B4B), Color(0xFF6366F1), Color(0xFFF43F5E)),
    PostImageThemeOption("rainy_glass", "Rainy Glass", Color(0xFF1E293B), Color(0xFF475569), Color(0xFF93C5FD)),
    PostImageThemeOption("warm_bokeh", "Warm Bokeh", Color(0xFF450A0A), Color(0xFFDC2626), Color(0xFFFDBA74)),
    PostImageThemeOption("midnight_clouds", "Midnight Clouds", Color(0xFF0F172A), Color(0xFF334155), Color(0xFFC084FC)),
    PostImageThemeOption("coral_reef", "Coral Reef", Color(0xFF134E4A), Color(0xFFFB7185), Color(0xFF2DD4BF))
)

@Composable
fun PostThemeArtwork(
    theme: PostImageThemeOption,
    modifier: Modifier = Modifier
) {
    Canvas(modifier = modifier) {
        drawRect(
            brush = Brush.linearGradient(
                colors = listOf(theme.primaryColor, theme.secondaryColor),
                start = Offset.Zero,
                end = Offset(size.width, size.height)
            )
        )
        when (theme.id) {
            "aurora" -> drawAurora(theme)
            "sunset_peaks" -> drawPeaks(theme)
            "starry_night" -> drawStars(theme)
            "ocean_waves" -> drawWaves(theme)
            "desert_dunes" -> drawDunes(theme)
            "sakura_blossom" -> drawSakura(theme)
            "cyber_grid" -> drawCyberGrid(theme)
            "forest_mist" -> drawForest(theme)
            "marble_gold" -> drawMarble(theme)
            "neon_horizon" -> drawNeonHorizon(theme)
            "abstract_prism" -> drawPrism(theme)
            "rainy_glass" -> drawRain(theme)
            "warm_bokeh" -> drawBokeh(theme)
            "midnight_clouds" -> drawClouds(theme)
            else -> drawCoral(theme)
        }
    }
}

private fun DrawScope.drawAurora(t: PostImageThemeOption) {
    val ribbon = Path().apply {
        moveTo(0f, size.height * 0.45f)
        cubicTo(size.width * 0.28f, size.height * 0.15f, size.width * 0.65f, size.height * 0.65f, size.width, size.height * 0.22f)
        lineTo(size.width, size.height * 0.55f)
        cubicTo(size.width * 0.62f, size.height * 0.85f, size.width * 0.30f, size.height * 0.36f, 0f, size.height * 0.7f)
        close()
    }
    drawPath(ribbon, brush = Brush.horizontalGradient(listOf(t.accentColor.copy(alpha = 0.45f), t.secondaryColor.copy(alpha = 0.55f), Color.White.copy(alpha = 0.25f))))
    drawCircle(t.accentColor.copy(alpha = 0.22f), radius = size.minDimension * 0.38f, center = Offset(size.width * 0.75f, size.height * 0.25f))
}

private fun DrawScope.drawPeaks(t: PostImageThemeOption) {
    drawCircle(t.accentColor.copy(alpha = 0.85f), radius = size.minDimension * 0.18f, center = Offset(size.width * 0.5f, size.height * 0.34f))
    val p1 = Path().apply {
        moveTo(0f, size.height)
        lineTo(size.width * 0.32f, size.height * 0.52f)
        lineTo(size.width * 0.62f, size.height * 0.78f)
        lineTo(size.width * 0.85f, size.height * 0.46f)
        lineTo(size.width, size.height * 0.68f)
        lineTo(size.width, size.height)
        close()
    }
    drawPath(p1, Color.Black.copy(alpha = 0.32f))
    val p2 = Path().apply {
        moveTo(0f, size.height)
        lineTo(size.width * 0.18f, size.height * 0.72f)
        lineTo(size.width * 0.52f, size.height * 0.58f)
        lineTo(size.width, size.height * 0.82f)
        lineTo(size.width, size.height)
        close()
    }
    drawPath(p2, Color.Black.copy(alpha = 0.45f))
}

private fun DrawScope.drawStars(t: PostImageThemeOption) {
    drawCircle(t.accentColor.copy(alpha = 0.9f), radius = size.minDimension * 0.1f, center = Offset(size.width * 0.8f, size.height * 0.22f))
    drawCircle(t.secondaryColor, radius = size.minDimension * 0.095f, center = Offset(size.width * 0.83f, size.height * 0.2f))
    for (i in 0 until 24) {
        val x = ((i * 73 + 19) % 100) / 100f * size.width
        val y = ((i * 41 + 11) % 85) / 100f * size.height
        val r = if (i % 4 == 0) size.minDimension * 0.012f else size.minDimension * 0.006f
        drawCircle(Color.White.copy(alpha = 0.4f + (i % 5) * 0.12f), radius = r, center = Offset(x, y))
    }
}

private fun DrawScope.drawWaves(t: PostImageThemeOption) {
    for (row in 0..3) {
        val base = size.height * (0.48f + row * 0.13f)
        val path = Path().apply {
            moveTo(0f, base)
            cubicTo(size.width * 0.28f, base - size.height * 0.08f, size.width * 0.65f, base + size.height * 0.08f, size.width, base - size.height * 0.03f)
            lineTo(size.width, size.height)
            lineTo(0f, size.height)
            close()
        }
        drawPath(path, t.accentColor.copy(alpha = 0.16f + row * 0.08f))
    }
}

private fun DrawScope.drawDunes(t: PostImageThemeOption) {
    drawCircle(t.accentColor.copy(alpha = 0.65f), radius = size.minDimension * 0.22f, center = Offset(size.width * 0.28f, size.height * 0.28f))
    val dune1 = Path().apply {
        moveTo(0f, size.height * 0.62f)
        quadraticTo(size.width * 0.4f, size.height * 0.44f, size.width, size.height * 0.68f)
        lineTo(size.width, size.height)
        lineTo(0f, size.height)
        close()
    }
    drawPath(dune1, t.primaryColor.copy(alpha = 0.55f))
    val dune2 = Path().apply {
        moveTo(0f, size.height * 0.78f)
        quadraticTo(size.width * 0.6f, size.height * 0.58f, size.width, size.height * 0.82f)
        lineTo(size.width, size.height)
        lineTo(0f, size.height)
        close()
    }
    drawPath(dune2, Color.Black.copy(alpha = 0.25f))
}

private fun DrawScope.drawSakura(t: PostImageThemeOption) {
    for (i in 0 until 14) {
        val x = ((i * 67 + 13) % 96 + 2) / 100f * size.width
        val y = ((i * 53 + 7) % 92 + 4) / 100f * size.height
        val r = size.minDimension * (0.025f + (i % 3) * 0.014f)
        drawCircle(t.accentColor.copy(alpha = 0.52f), radius = r, center = Offset(x, y))
        drawCircle(Color.White.copy(alpha = 0.45f), radius = r * 0.45f, center = Offset(x + r * 0.25f, y - r * 0.2f))
    }
}

private fun DrawScope.drawCyberGrid(t: PostImageThemeOption) {
    val horizon = size.height * 0.54f
    drawLine(t.accentColor.copy(alpha = 0.7f), Offset(0f, horizon), Offset(size.width, horizon), strokeWidth = 2.5f)
    for (i in 1..6) {
        val y = horizon + (size.height - horizon) * (i / 6f) * (i / 6f)
        drawLine(t.accentColor.copy(alpha = 0.35f), Offset(0f, y), Offset(size.width, y), strokeWidth = 1.5f)
    }
    for (i in -4..4) {
        val topX = size.width * 0.5f + i * size.width * 0.06f
        val botX = size.width * 0.5f + i * size.width * 0.24f
        drawLine(t.secondaryColor.copy(alpha = 0.4f), Offset(topX, horizon), Offset(botX, size.height), strokeWidth = 1.5f)
    }
}

private fun DrawScope.drawForest(t: PostImageThemeOption) {
    for (i in 0..6) {
        val cx = size.width * (0.08f + i * 0.14f)
        val top = size.height * (0.45f + (i % 2) * 0.12f)
        val tree = Path().apply {
            moveTo(cx, top)
            lineTo(cx - size.width * 0.1f, size.height)
            lineTo(cx + size.width * 0.1f, size.height)
            close()
        }
        drawPath(tree, Color.Black.copy(alpha = 0.28f))
    }
    drawRect(
        brush = Brush.verticalGradient(listOf(Color.Transparent, t.accentColor.copy(alpha = 0.32f))),
        topLeft = Offset(0f, size.height * 0.55f),
        size = Size(size.width, size.height * 0.45f)
    )
}

private fun DrawScope.drawMarble(t: PostImageThemeOption) {
    for (i in 0..4) {
        val p = Path().apply {
            moveTo(0f, size.height * (0.15f + i * 0.18f))
            cubicTo(
                size.width * 0.35f, size.height * (0.05f + i * 0.2f),
                size.width * 0.7f, size.height * (0.35f + i * 0.12f),
                size.width, size.height * (0.22f + i * 0.16f)
            )
        }
        drawPath(p, color = t.accentColor.copy(alpha = 0.38f), style = Stroke(width = 2.5f))
    }
}

private fun DrawScope.drawNeonHorizon(t: PostImageThemeOption) {
    drawCircle(
        brush = Brush.verticalGradient(listOf(t.accentColor, t.secondaryColor)),
        radius = size.minDimension * 0.24f,
        center = Offset(size.width * 0.5f, size.height * 0.46f)
    )
    drawRect(t.primaryColor.copy(alpha = 0.78f), topLeft = Offset(0f, size.height * 0.56f), size = Size(size.width, size.height * 0.44f))
    drawLine(t.secondaryColor, Offset(0f, size.height * 0.56f), Offset(size.width, size.height * 0.56f), strokeWidth = 3f)
}

private fun DrawScope.drawPrism(t: PostImageThemeOption) {
    val poly1 = Path().apply {
        moveTo(size.width * 0.2f, 0f)
        lineTo(size.width * 0.85f, size.height * 0.45f)
        lineTo(size.width * 0.1f, size.height * 0.85f)
        close()
    }
    drawPath(poly1, t.accentColor.copy(alpha = 0.32f))
    val poly2 = Path().apply {
        moveTo(size.width, size.height * 0.15f)
        lineTo(size.width * 0.4f, size.height)
        lineTo(size.width, size.height)
        close()
    }
    drawPath(poly2, Color.White.copy(alpha = 0.14f))
}

private fun DrawScope.drawRain(t: PostImageThemeOption) {
    for (i in 0 until 20) {
        val x = ((i * 59 + 17) % 100) / 100f * size.width
        val y = ((i * 37 + 9) % 100) / 100f * size.height
        val len = size.minDimension * (0.06f + (i % 3) * 0.03f)
        drawLine(t.accentColor.copy(alpha = 0.42f), Offset(x, y), Offset(x - len * 0.25f, y + len), strokeWidth = 2f)
    }
}

private fun DrawScope.drawBokeh(t: PostImageThemeOption) {
    for (i in 0 until 12) {
        val x = ((i * 83 + 15) % 94 + 3) / 100f * size.width
        val y = ((i * 47 + 21) % 90 + 5) / 100f * size.height
        val r = size.minDimension * (0.06f + (i % 4) * 0.03f)
        drawCircle(t.accentColor.copy(alpha = 0.22f), radius = r, center = Offset(x, y))
    }
}

private fun DrawScope.drawClouds(t: PostImageThemeOption) {
    for (i in 0..4) {
        val cx = size.width * (0.15f + i * 0.2f)
        val cy = size.height * (0.28f + (i % 2) * 0.4f)
        drawCircle(t.accentColor.copy(alpha = 0.18f), radius = size.minDimension * 0.24f, center = Offset(cx, cy))
        drawCircle(Color.White.copy(alpha = 0.10f), radius = size.minDimension * 0.16f, center = Offset(cx + size.width * 0.06f, cy - size.height * 0.04f))
    }
}

private fun DrawScope.drawCoral(t: PostImageThemeOption) {
    for (i in 0..7) {
        val angle = (i * 45.0) * Math.PI / 180.0
        val cx = size.width * 0.5f + (cos(angle) * size.minDimension * 0.28f).toFloat()
        val cy = size.height * 0.5f + (sin(angle) * size.minDimension * 0.28f).toFloat()
        drawCircle(t.accentColor.copy(alpha = 0.25f), radius = size.minDimension * 0.14f, center = Offset(cx, cy))
    }
    drawCircle(t.secondaryColor.copy(alpha = 0.28f), radius = size.minDimension * 0.2f, center = Offset(size.width * 0.5f, size.height * 0.5f))
}
