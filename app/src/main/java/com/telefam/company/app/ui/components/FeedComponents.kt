package com.telefam.company.app.ui.components

import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.annotation.OptIn
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import coil.compose.AsyncImage
import com.telefam.company.app.R
import com.telefam.company.app.feed.FeedAspectRatioMath
import com.telefam.company.app.feed.FeedLoadingReason
import com.telefam.company.app.network.FeedVideoDto
import com.telefam.company.app.network.TelefamNetworkClient
import kotlinx.coroutines.delay
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

val FeedAccentCoral = Color(0xFFFF2D55)
val FeedSpinnerGreen = Color(0xFF22C55E)

data class HeartBurstInstance(
    val id: Long,
    val offset: Offset
)

@Composable
fun TriDotSpinner(
    modifier: Modifier = Modifier,
    dotBaseSize: Dp = 9.dp
) {
    val transition = rememberInfiniteTransition(label = "tri_dot_spinner")
    val phase by transition.animateFloat(
        initialValue = 0f,
        targetValue = (2.0 * PI).toFloat(),
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1100, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "tri_dot_phase"
    )

    val colors = remember {
        listOf(FeedAccentCoral, Color.White, FeedSpinnerGreen)
    }

    Canvas(
        modifier = modifier
            .size(width = 64.dp, height = 28.dp)
            .testTag("feed_tri_dot_spinner")
    ) {
        val centerX = size.width / 2f
        val centerY = size.height / 2f
        val orbitRx = size.width * 0.34f
        val baseR = dotBaseSize.toPx() / 2f

        val dots = colors.mapIndexed { idx, color ->
            val angle = phase + (idx * ((2.0 * PI) / 3.0)).toFloat()
            val x = centerX + cos(angle) * orbitRx
            val depth = sin(angle) // -1 (back) .. +1 (front)
            val radius = baseR * (0.72f + 0.42f * ((depth + 1f) / 2f))
            val alpha = 0.65f + 0.35f * ((depth + 1f) / 2f)
            Triple(depth, Triple(x, radius, alpha), color)
        }.sortedBy { it.first }

        dots.forEach { (_, geom, color) ->
            val (x, r, alpha) = geom
            drawCircle(
                color = Color.Black.copy(alpha = 0.25f * alpha),
                radius = r + 1.5f,
                center = Offset(x, centerY + 1.5f)
            )
            drawCircle(
                color = color.copy(alpha = alpha),
                radius = r,
                center = Offset(x, centerY)
            )
        }
    }
}

@OptIn(UnstableApi::class)
@Composable
fun AdaptiveFeedVideoSurface(
    video: FeedVideoDto,
    isActive: Boolean,
    player: Any?,
    isPlaying: Boolean,
    loadingReason: FeedLoadingReason,
    modifier: Modifier = Modifier,
    onSingleTap: () -> Unit,
    onDoubleTap: (Offset) -> Unit
) {
    val thumbUrl = remember(video.thumbnailUrl) {
        TelefamNetworkClient.resolveMediaUrl(video.thumbnailUrl)
    }
    val density = LocalDensity.current

    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .background(Color.Black)
            .pointerInput(video.videoId) {
                detectTapGestures(
                    onTap = { onSingleTap() },
                    onDoubleTap = { offset -> onDoubleTap(offset) }
                )
            }
    ) {
        val maxWPx = with(density) { maxWidth.toPx() }
        val maxHPx = with(density) { maxHeight.toPx() }
        val fitted = remember(maxWPx, maxHPx, video.originalWidth, video.originalHeight, video.aspectRatio) {
            FeedAspectRatioMath.computeFittedSize(
                containerWidthPx = maxWPx,
                containerHeightPx = maxHPx,
                videoWidth = video.originalWidth,
                videoHeight = video.originalHeight,
                explicitRatio = video.aspectRatio
            )
        }
        val fitWidthDp = with(density) { fitted.widthPx.toDp() }
        val fitHeightDp = with(density) { fitted.heightPx.toDp() }

        if (fitted.needsAmbientBackdrop && thumbUrl.isNotBlank()) {
            AsyncImage(
                model = thumbUrl,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .fillMaxSize()
                    .blur(26.dp)
            )
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.56f))
            )
        }

        Box(
            modifier = Modifier
                .align(Alignment.Center)
                .width(fitWidthDp)
                .height(fitHeightDp)
        ) {
            if (thumbUrl.isNotBlank()) {
                AsyncImage(
                    model = thumbUrl,
                    contentDescription = video.title.ifBlank { video.description },
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxSize()
                )
            }

            if (isActive && player is Player) {
                var attachedView by remember { mutableStateOf<PlayerView?>(null) }
                DisposableEffect(player) {
                    onDispose {
                        attachedView?.player = null
                    }
                }
                AndroidView(
                    factory = { ctx ->
                        PlayerView(ctx).apply {
                            layoutParams = FrameLayout.LayoutParams(
                                ViewGroup.LayoutParams.MATCH_PARENT,
                                ViewGroup.LayoutParams.MATCH_PARENT
                            )
                            useController = false
                            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                            setShutterBackgroundColor(android.graphics.Color.TRANSPARENT)
                            setKeepContentOnPlayerReset(true)
                            this.player = player
                            attachedView = this
                        }
                    },
                    update = { view ->
                        if (view.player !== player) {
                            view.player = player
                        }
                    },
                    modifier = Modifier.fillMaxSize()
                )
            }
        }

        // Top & bottom subtle readability scrims matching dark reference UI
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(128.dp)
                .align(Alignment.TopCenter)
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Black.copy(alpha = 0.58f), Color.Transparent)
                    )
                )
        )
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(240.dp)
                .align(Alignment.BottomCenter)
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Transparent, Color.Black.copy(alpha = 0.78f))
                    )
                )
        )

        if (isActive && !isPlaying && loadingReason == FeedLoadingReason.NONE) {
            Box(
                modifier = Modifier
                    .align(Alignment.Center)
                    .size(64.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.42f)),
                contentAlignment = Alignment.Center
            ) {
                Image(
                    painter = painterResource(id = R.drawable.ic_play_arrow),
                    contentDescription = null,
                    colorFilter = ColorFilter.tint(Color.White.copy(alpha = 0.9f)),
                    modifier = Modifier.size(30.dp)
                )
            }
        }

        if (isActive && loadingReason != FeedLoadingReason.NONE && loadingReason != FeedLoadingReason.UNAVAILABLE) {
            Box(
                modifier = Modifier
                    .align(Alignment.Center)
                    .clip(RoundedCornerShape(20.dp))
                    .background(Color.Black.copy(alpha = 0.45f))
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                contentAlignment = Alignment.Center
            ) {
                TriDotSpinner()
            }
        }
    }
}

@Composable
fun DoubleTapHeartBurst(
    burst: HeartBurstInstance,
    onFinished: (Long) -> Unit
) {
    var animScale by remember(burst.id) { mutableFloatStateOf(0.55f) }
    var animAlpha by remember(burst.id) { mutableFloatStateOf(1f) }
    var animRise by remember(burst.id) { mutableFloatStateOf(0f) }

    LaunchedEffect(burst.id) {
        val steps = 14
        for (i in 1..steps) {
            val t = i.toFloat() / steps.toFloat()
            animScale = if (t < 0.35f) {
                0.55f + (t / 0.35f) * 0.75f
            } else {
                1.30f - ((t - 0.35f) / 0.65f) * 0.25f
            }
            animRise = t * 90f
            animAlpha = if (t > 0.55f) (1f - ((t - 0.55f) / 0.45f)).coerceIn(0f, 1f) else 1f
            delay(28L)
        }
        onFinished(burst.id)
    }

    Image(
        painter = painterResource(id = R.drawable.ic_heart_filled),
        contentDescription = null,
        colorFilter = ColorFilter.tint(FeedAccentCoral),
        modifier = Modifier
            .offset {
                IntOffset(
                    x = (burst.offset.x - 42f).roundToInt(),
                    y = (burst.offset.y - 42f - animRise).roundToInt()
                )
            }
            .size(84.dp)
            .scale(animScale)
            .alpha(animAlpha)
    )
}

@Composable
fun ExpandableRichCaption(
    description: String,
    hashtags: List<String>,
    onHashtagClick: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val uriHandler = LocalUriHandler.current
    var expanded by remember(description) { mutableStateOf(false) }

    val fullCaption = remember(description, hashtags) {
        val base = description.trim()
        val missingTags = hashtags.filter { tag ->
            !base.contains("#$tag", ignoreCase = true)
        }
        if (missingTags.isEmpty()) base
        else listOf(base, missingTags.joinToString(" ") { "#$it" })
            .filter { it.isNotBlank() }
            .joinToString(" ")
    }

    if (fullCaption.isBlank()) return

    val needsCollapse = fullCaption.length > 96 || fullCaption.count { it == '\n' } >= 2
    val displayText = if (!expanded && needsCollapse) {
        fullCaption.take(92).trimEnd() + "..."
    } else {
        fullCaption
    }

    val tokenRegex = remember {
        Regex("""(#([A-Za-z0-9_]{1,40})|https?://[^\s<>()]+)""")
    }

    val annotated = remember(displayText) {
        buildAnnotatedString {
            var cursor = 0
            for (match in tokenRegex.findAll(displayText)) {
                if (match.range.first > cursor) {
                    withStyle(SpanStyle(color = Color.White)) {
                        append(displayText.substring(cursor, match.range.first))
                    }
                }
                val token = match.value
                if (token.startsWith("#")) {
                    val tagName = token.removePrefix("#")
                    withLink(
                        LinkAnnotation.Clickable(
                            tag = "hashtag:$tagName",
                            styles = TextLinkStyles(
                                style = SpanStyle(
                                    color = FeedAccentCoral,
                                    fontWeight = FontWeight.SemiBold
                                )
                            )
                        ) {
                            onHashtagClick(tagName)
                        }
                    ) {
                        append(token)
                    }
                } else {
                    withLink(
                        LinkAnnotation.Clickable(
                            tag = "url:$token",
                            styles = TextLinkStyles(
                                style = SpanStyle(
                                    color = Color(0xFF7DD3FC),
                                    fontWeight = FontWeight.Medium
                                )
                            )
                        ) {
                            runCatching { uriHandler.openUri(token) }
                        }
                    ) {
                        append(token)
                    }
                }
                cursor = match.range.last + 1
            }
            if (cursor < displayText.length) {
                withStyle(SpanStyle(color = Color.White)) {
                    append(displayText.substring(cursor))
                }
            }
        }
    }

    Column(modifier = modifier) {
        Text(
            text = annotated,
            fontSize = 14.sp,
            lineHeight = 19.sp,
            maxLines = if (expanded) 12 else 3,
            overflow = TextOverflow.Ellipsis
        )
        if (needsCollapse) {
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = stringResource(id = if (expanded) R.string.feed_read_less else R.string.feed_read_more),
                color = Color.White.copy(alpha = 0.78f),
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier
                    .clickable { expanded = !expanded }
                    .padding(vertical = 2.dp)
                    .testTag("feed_read_more_toggle")
            )
        }
    }
}

@Composable
fun OfflineOrErrorFeedOverlay(
    message: String,
    isRetrying: Boolean,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(20.dp))
            .background(Color(0xD9101216))
            .border(1.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(20.dp))
            .padding(horizontal = 24.dp, vertical = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        if (isRetrying) {
            TriDotSpinner()
        }
        Text(
            text = message,
            color = Color.White,
            fontSize = 15.sp,
            fontWeight = FontWeight.Medium
        )
        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Button(
                onClick = onRetry,
                shape = RoundedCornerShape(24.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = FeedAccentCoral,
                    contentColor = Color.White
                ),
                contentPadding = PaddingValues(horizontal = 18.dp, vertical = 10.dp),
                modifier = Modifier
                    .height(44.dp)
                    .testTag("feed_retry_button")
            ) {
                Text(stringResource(id = R.string.feed_retry), fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            }
            OutlinedButton(
                onClick = {
                    val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        Intent(Settings.Panel.ACTION_INTERNET_CONNECTIVITY)
                    } else {
                        Intent(Settings.ACTION_WIRELESS_SETTINGS)
                    }
                    runCatching { context.startActivity(intent) }.onFailure {
                        runCatching { context.startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS)) }
                    }
                },
                shape = RoundedCornerShape(24.dp),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp),
                modifier = Modifier
                    .height(44.dp)
                    .testTag("feed_connect_internet_button")
            ) {
                Text(stringResource(id = R.string.feed_connect_internet), fontSize = 13.sp)
            }
        }
    }
}
