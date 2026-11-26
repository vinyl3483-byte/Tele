package com.telefam.company.app.feed

import androidx.annotation.StringRes
import com.telefam.company.app.R
import com.telefam.company.app.network.FeedVideoDto
import kotlinx.coroutines.flow.StateFlow
import kotlin.math.abs
import kotlin.math.floor

enum class FeedTab(val apiValue: String, val cacheKey: String) {
    FOLLOWING("following", "following"),
    FOR_YOU("for_you", "for_you")
}

enum class FeedLoadingReason {
    NONE,
    INITIAL_LOAD,
    BUFFERING,
    WEAK_CONNECTION,
    QUALITY_SWITCH,
    RECONNECTING,
    UNAVAILABLE
}

enum class FeedPreloadTier(val aheadCount: Int, val prefetchBytesPerVideo: Long) {
    WIFI_NORMAL(aheadCount = 5, prefetchBytesPerVideo = 768L * 1024L),
    METERED_WEAK(aheadCount = 2, prefetchBytesPerVideo = 384L * 1024L),
    OFFLINE(aheadCount = 0, prefetchBytesPerVideo = 0L)
}

enum class FeedReportReason(
    val apiValue: String,
    @param:StringRes val labelRes: Int
) {
    SPAM("spam", R.string.feed_report_reason_spam),
    HARASSMENT("harassment", R.string.feed_report_reason_harassment),
    HATE_SPEECH("hate_speech", R.string.feed_report_reason_hate),
    VIOLENCE("violence", R.string.feed_report_reason_violence),
    NUDITY("nudity", R.string.feed_report_reason_nudity),
    MISINFORMATION("misinformation", R.string.feed_report_reason_misinfo),
    COPYRIGHT("copyright", R.string.feed_report_reason_copyright),
    OTHER("other", R.string.feed_report_reason_other)
}

enum class FeedVideoVisibility(
    val apiValue: String,
    @param:StringRes val labelRes: Int
) {
    PUBLIC("public", R.string.feed_visibility_public),
    FOLLOWERS("followers", R.string.feed_visibility_followers),
    PRIVATE("private", R.string.feed_visibility_private);

    companion object {
        fun fromApi(raw: String): FeedVideoVisibility =
            entries.firstOrNull { it.apiValue == raw.lowercase() } ?: PUBLIC
    }
}

data class FeedPlaybackState(
    val activeVideoId: String? = null,
    val isPlaying: Boolean = false,
    val isMuted: Boolean = false,
    val loadingReason: FeedLoadingReason = FeedLoadingReason.NONE,
    val positionMs: Long = 0L,
    val durationMs: Long = 0L,
    val bitrateBps: Long = 0L,
    val bufferedPercent: Int = 0,
    val rewatchCountForActive: Int = 0,
    val hasPlaybackError: Boolean = false
)

object FeedAspectRatioMath {
    data class FittedSize(
        val widthPx: Float,
        val heightPx: Float,
        val aspectRatio: Float,
        val needsAmbientBackdrop: Boolean
    )

    fun normalizedRatio(width: Int, height: Int, explicitRatio: Double): Float {
        if (width > 0 && height > 0) {
            return (width.toFloat() / height.toFloat()).coerceIn(0.25f, 4.0f)
        }
        if (explicitRatio > 0.05) {
            return explicitRatio.toFloat().coerceIn(0.25f, 4.0f)
        }
        return 9f / 16f
    }

    fun computeFittedSize(
        containerWidthPx: Float,
        containerHeightPx: Float,
        videoWidth: Int,
        videoHeight: Int,
        explicitRatio: Double
    ): FittedSize {
        if (containerWidthPx <= 0f || containerHeightPx <= 0f) {
            val r = normalizedRatio(videoWidth, videoHeight, explicitRatio)
            return FittedSize(0f, 0f, r, false)
        }
        val videoRatio = normalizedRatio(videoWidth, videoHeight, explicitRatio)
        val containerRatio = containerWidthPx / containerHeightPx
        val fitWidth: Float
        val fitHeight: Float
        if (videoRatio > containerRatio) {
            fitWidth = containerWidthPx
            fitHeight = containerWidthPx / videoRatio
        } else {
            fitHeight = containerHeightPx
            fitWidth = containerHeightPx * videoRatio
        }
        val ratioDiff = abs(videoRatio - containerRatio) / containerRatio.coerceAtLeast(0.1f)
        val needsBackdrop = ratioDiff > 0.14f
        return FittedSize(
            widthPx = fitWidth,
            heightPx = fitHeight,
            aspectRatio = videoRatio,
            needsAmbientBackdrop = needsBackdrop
        )
    }
}

object FeedFormatter {
    private val hashtagRegex = Regex("""#([A-Za-z0-9_]{1,40})""")
    private val urlRegex = Regex("""https?://[^\s<>()]+""", RegexOption.IGNORE_CASE)

    fun formatCount(value: Long): String {
        val safe = value.coerceAtLeast(0L)
        return when {
            safe < 1_000L -> safe.toString()
            safe < 1_000_000L -> {
                val tenths = floor((safe / 100.0)).toLong()
                val whole = tenths / 10L
                val frac = tenths % 10L
                if (frac == 0L) "${whole}K" else "${whole}.${frac}K"
            }
            safe < 1_000_000_000L -> {
                val tenths = floor((safe / 100_000.0)).toLong()
                val whole = tenths / 10L
                val frac = tenths % 10L
                if (frac == 0L) "${whole}M" else "${whole}.${frac}M"
            }
            else -> {
                val tenths = floor((safe / 100_000_000.0)).toLong()
                val whole = tenths / 10L
                val frac = tenths % 10L
                if (frac == 0L) "${whole}B" else "${whole}.${frac}B"
            }
        }
    }

    fun extractHashtags(text: String): List<String> =
        hashtagRegex.findAll(text).map { it.groupValues[1].lowercase() }.distinct().toList()

    fun extractUrls(text: String): List<String> =
        urlRegex.findAll(text).map { it.value }.distinct().toList()
}

interface FeedPlayerController {
    val playbackState: StateFlow<FeedPlaybackState>
    val playerInstance: Any?

    fun playVideo(
        video: FeedVideoDto,
        upcomingVideos: List<FeedVideoDto>,
        preloadTier: FeedPreloadTier
    )

    fun togglePlayPause()
    fun pause()
    fun resumeIfReady()
    fun setMuted(muted: Boolean)
    fun toggleMute()
    fun setAppForeground(foreground: Boolean)
    fun retryActive(video: FeedVideoDto)
    fun onSignedUrlRefreshed(video: FeedVideoDto)
    fun bindStreamRefreshCallback(callback: suspend (String) -> FeedVideoDto?)
    fun bindWatchProgressCallback(callback: (videoId: String, watchDurationMs: Long, positionMs: Long, completionPct: Double, rewatchDelta: Int) -> Unit)
    fun bindPreviewPlayer(key: String, streamUrl: String): Any?
    fun releasePreviewPlayer(key: String)
    fun releaseAllPreviews()
    fun release()
}
