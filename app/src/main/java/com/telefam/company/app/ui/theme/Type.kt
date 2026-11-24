package com.telefam.company.app.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.telefam.company.app.R

val PlusJakartaFamily = FontFamily(
    Font(R.font.plus_jakarta_sans, FontWeight.Normal),
    Font(R.font.plus_jakarta_sans, FontWeight.SemiBold),
    Font(R.font.plus_jakarta_sans, FontWeight.Bold)
)

val InterFamily = FontFamily(
    Font(R.font.inter, FontWeight.Normal),
    Font(R.font.inter, FontWeight.Medium),
    Font(R.font.inter, FontWeight.SemiBold)
)

val PlayfairDisplayFamily = FontFamily(
    Font(R.font.playfair_display, FontWeight.Normal),
    Font(R.font.playfair_display, FontWeight.Bold)
)

val PacificoFamily = FontFamily(
    Font(R.font.pacifico, FontWeight.Normal)
)

val JetBrainsMonoFamily = FontFamily(
    Font(R.font.jetbrains_mono, FontWeight.Normal),
    Font(R.font.jetbrains_mono, FontWeight.Bold)
)

val OswaldFamily = FontFamily(
    Font(R.font.oswald, FontWeight.Normal),
    Font(R.font.oswald, FontWeight.Bold)
)

val OutfitFamily = FontFamily(
    Font(R.font.outfit, FontWeight.Normal),
    Font(R.font.outfit, FontWeight.Medium),
    Font(R.font.outfit, FontWeight.Bold)
)

val RobotoSlabFamily = FontFamily(
    Font(R.font.roboto_slab, FontWeight.Normal),
    Font(R.font.roboto_slab, FontWeight.Bold)
)

val CaveatFamily = FontFamily(
    Font(R.font.caveat, FontWeight.Normal),
    Font(R.font.caveat, FontWeight.Bold)
)

enum class PostFontStyle(
    val id: String,
    val label: String,
    val badge: String,
    val fontFamily: FontFamily,
    val fontWeight: FontWeight,
    val fontStyle: FontStyle = FontStyle.Normal
) {
    CLASSIC("classic", "Classic", "Aa", PlusJakartaFamily, FontWeight.SemiBold),
    SERIF("serif", "Serif", "Aa", PlayfairDisplayFamily, FontWeight.Normal),
    HAND("hand", "Hand", "Aa", PacificoFamily, FontWeight.Normal),
    TYPEWRITER("typewriter", "Typewriter", "Aa", RobotoSlabFamily, FontWeight.Normal),
    BOLD("bold", "Bold", "AA", OswaldFamily, FontWeight.Bold),
    MONO("mono", "Mono", "Aa", JetBrainsMonoFamily, FontWeight.Normal),
    DISPLAY("display", "Display", "Aa", OutfitFamily, FontWeight.Bold),
    ROUNDED("rounded", "Rounded", "Aa", OutfitFamily, FontWeight.Medium),
    ITALIC("italic", "Italic", "Aa", PlayfairDisplayFamily, FontWeight.Normal, FontStyle.Italic),
    SCRIPT("script", "Script", "Aa", CaveatFamily, FontWeight.Bold),
    SLAB("slab", "Slab", "Aa", RobotoSlabFamily, FontWeight.Bold),
    CONDENSED("condensed", "Condensed", "Aa", OswaldFamily, FontWeight.Normal);

    companion object {
        fun fromId(id: String): PostFontStyle =
            entries.firstOrNull { it.id == id } ?: CLASSIC
    }
}

val TelefamTypography = Typography(
    headlineLarge = TextStyle(
        fontFamily = PlusJakartaFamily,
        fontWeight = FontWeight.Bold,
        fontSize = 32.sp,
        lineHeight = 38.sp,
        letterSpacing = (-0.5).sp
    ),
    titleLarge = TextStyle(
        fontFamily = PlusJakartaFamily,
        fontWeight = FontWeight.Bold,
        fontSize = 21.sp,
        lineHeight = 28.sp
    ),
    titleMedium = TextStyle(
        fontFamily = PlusJakartaFamily,
        fontWeight = FontWeight.SemiBold,
        fontSize = 16.sp,
        lineHeight = 22.sp
    ),
    bodyLarge = TextStyle(
        fontFamily = InterFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 15.sp,
        lineHeight = 22.sp
    ),
    bodyMedium = TextStyle(
        fontFamily = InterFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 13.sp,
        lineHeight = 18.sp
    ),
    labelLarge = TextStyle(
        fontFamily = PlusJakartaFamily,
        fontWeight = FontWeight.SemiBold,
        fontSize = 15.sp,
        lineHeight = 20.sp
    ),
    labelSmall = TextStyle(
        fontFamily = InterFamily,
        fontWeight = FontWeight.Medium,
        fontSize = 11.sp,
        lineHeight = 16.sp
    )
)
