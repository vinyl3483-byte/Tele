package com.telefam.company.app.feed

import android.content.Context
import android.media.AudioAttributes as AndroidAudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.StatFs
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.HttpDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.CacheWriter
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter
import com.telefam.company.app.network.FeedVideoDto
import com.telefam.company.app.network.TelefamNetworkClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File
import java.util.concurrent.ConcurrentHashMap

@OptIn(UnstableApi::class)
private object TelefamMediaCacheProvider {
    @Volatile
    private var cache: SimpleCache? = null

    fun getOrCreate(context: Context): SimpleCache {
        return cache ?: synchronized(this) {
            cache ?: run {
                val appContext = context.applicationContext
                val dir = File(appContext.cacheDir, "telefam_video_segments").apply { mkdirs() }
                val freeBytes = runCatching {
                    val sf = StatFs(dir.absolutePath)
                    sf.availableBytes
                }.getOrDefault(512L * 1024L * 1024L)
                // Cap local segment cache dynamically (64 MB .. 256 MB); old segments are evicted locally only.
                val maxCacheBytes = (freeBytes / 6L).coerceIn(64L * 1024L * 1024L, 256L * 1024L * 1024L)
                val evictor = LeastRecentlyUsedCacheEvictor(maxCacheBytes)
                val dbProvider = StandaloneDatabaseProvider(appContext)
                SimpleCache(dir, evictor, dbProvider).also { cache = it }
            }
        }
    }
}

@OptIn(UnstableApi::class)
class Media3FeedPlaybackController(
    context: Context
) : FeedPlayerController {

    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val simpleCache: SimpleCache = TelefamMediaCacheProvider.getOrCreate(appContext)

    private val upstreamFactory = OkHttpDataSource.Factory(TelefamNetworkClient.mediaOkHttpClient)
    private val cacheDataSourceFactory: CacheDataSource.Factory = CacheDataSource.Factory()
        .setCache(simpleCache)
        .setUpstreamDataSourceFactory(upstreamFactory)
        .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)

    private val bandwidthMeter = DefaultBandwidthMeter.Builder(appContext).build()
    private val trackSelector = DefaultTrackSelector(appContext).apply {
        setParameters(
            buildUponParameters()
                .setMaxVideoSize(1920, 1920)
                .setPreferredAudioLanguage("en")
        )
    }

    private val loadControl = DefaultLoadControl.Builder()
        .setBufferDurationsMs(
            /* minBufferMs = */ 1_800,
            /* maxBufferMs = */ 14_000,
            /* bufferForPlaybackMs = */ 700,
            /* bufferForPlaybackAfterRebufferMs = */ 1_200
        )
        .build()

    private val player: ExoPlayer = ExoPlayer.Builder(appContext)
        .setMediaSourceFactory(DefaultMediaSourceFactory(cacheDataSourceFactory))
        .setTrackSelector(trackSelector)
        .setBandwidthMeter(bandwidthMeter)
        .setLoadControl(loadControl)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build(),
            false
        )
        .build().apply {
            repeatMode = Player.REPEAT_MODE_ONE
            playWhenReady = true
        }

    private val audioManager: AudioManager? =
        runCatching { appContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager }.getOrNull()

    private var audioFocusGranted: Boolean = false
    private val focusListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        when (focusChange) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                if (player.isPlaying) {
                    player.playWhenReady = false
                }
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                if (!_playbackState.value.isMuted) {
                    player.volume = 0.25f
                }
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                player.volume = if (_playbackState.value.isMuted) 0f else 1f
            }
        }
    }
    private val focusRequest: AudioFocusRequest? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(
                AndroidAudioAttributes.Builder()
                    .setUsage(AndroidAudioAttributes.USAGE_MEDIA)
                    .setContentType(AndroidAudioAttributes.CONTENT_TYPE_MOVIE)
                    .build()
            )
            .setOnAudioFocusChangeListener(focusListener)
            .build()
    } else null

    private val _playbackState = MutableStateFlow(FeedPlaybackState())
    override val playbackState: StateFlow<FeedPlaybackState> = _playbackState.asStateFlow()
    override val playerInstance: Any
        get() = player

    private var activeVideo: FeedVideoDto? = null
    private var triedFallbackMp4: Boolean = false
    private var triedUrlRefresh: Boolean = false
    private var lastReportedBitrate: Long = 0L
    private var lastRewatchReported: Int = 0
    private var sessionWatchAccumulatedMs: Long = 0L
    private var lastTickWallMs: Long = 0L
    private var lastPositionMs: Long = 0L
    private var isAppForeground: Boolean = true
    private var userManuallyPaused: Boolean = false

    private var progressTickerJob: Job? = null
    private var preloadJob: Job? = null
    private var streamRefreshCallback: (suspend (String) -> FeedVideoDto?)? = null
    private var watchProgressCallback: ((String, Long, Long, Double, Int) -> Unit)? = null

    private val previewPool = ConcurrentHashMap<String, ExoPlayer>()
    private val previewOrder = ArrayDeque<String>()

    init {
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                val vid = activeVideo
                val nextReason = when (state) {
                    Player.STATE_BUFFERING -> {
                        val bw = bandwidthMeter.bitrateEstimate
                        when {
                            _playbackState.value.hasPlaybackError -> FeedLoadingReason.RECONNECTING
                            bw in 1L..420_000L -> FeedLoadingReason.WEAK_CONNECTION
                            activeVideo != null && lastPositionMs == 0L -> FeedLoadingReason.INITIAL_LOAD
                            else -> FeedLoadingReason.BUFFERING
                        }
                    }
                    Player.STATE_READY -> FeedLoadingReason.NONE
                    Player.STATE_IDLE -> if (_playbackState.value.hasPlaybackError) FeedLoadingReason.UNAVAILABLE else FeedLoadingReason.NONE
                    else -> FeedLoadingReason.NONE
                }
                _playbackState.update {
                    it.copy(
                        loadingReason = nextReason,
                        durationMs = player.duration.coerceAtLeast(vid?.durationMs ?: 0L),
                        bufferedPercent = player.bufferedPercentage
                    )
                }
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                _playbackState.update {
                    it.copy(
                        isPlaying = isPlaying,
                        loadingReason = if (isPlaying) FeedLoadingReason.NONE else it.loadingReason
                    )
                }
            }

            override fun onTracksChanged(tracks: Tracks) {
                var activeBps = 0L
                for (group in tracks.groups) {
                    if (group.type == C.TRACK_TYPE_VIDEO && group.isSelected) {
                        for (i in 0 until group.length) {
                            if (group.isTrackSelected(i)) {
                                activeBps = group.getTrackFormat(i).bitrate.toLong()
                                break
                            }
                        }
                    }
                }
                if (activeBps > 0L && lastReportedBitrate > 0L && activeBps != lastReportedBitrate) {
                    _playbackState.update {
                        it.copy(
                            bitrateBps = activeBps,
                            loadingReason = if (player.playbackState == Player.STATE_BUFFERING) {
                                FeedLoadingReason.QUALITY_SWITCH
                            } else it.loadingReason
                        )
                    }
                } else if (activeBps > 0L) {
                    _playbackState.update { it.copy(bitrateBps = activeBps) }
                }
                lastReportedBitrate = activeBps
            }

            override fun onPlayerError(error: PlaybackException) {
                val vid = activeVideo ?: return
                val cause = error.cause
                val httpCode = (cause as? HttpDataSource.InvalidResponseCodeException)?.responseCode ?: 0
                if ((httpCode == 401 || httpCode == 403 || httpCode == 410) && !triedUrlRefresh) {
                    triedUrlRefresh = true
                    _playbackState.update {
                        it.copy(loadingReason = FeedLoadingReason.RECONNECTING, hasPlaybackError = false)
                    }
                    scope.launch {
                        val refreshed = streamRefreshCallback?.invoke(vid.videoId)
                        if (refreshed != null && refreshed.videoId == activeVideo?.videoId) {
                            onSignedUrlRefreshed(refreshed)
                        } else {
                            fallbackOrFail(vid)
                        }
                    }
                    return
                }
                fallbackOrFail(vid)
            }
        })
        startProgressTicker()
    }

    private fun fallbackOrFail(video: FeedVideoDto) {
        val fallbackUrl = TelefamNetworkClient.resolveMediaUrl(video.fallbackMp4Url)
        val currentUrl = player.currentMediaItem?.localConfiguration?.uri?.toString().orEmpty()
        if (!triedFallbackMp4 && fallbackUrl.isNotBlank() && fallbackUrl != currentUrl) {
            triedFallbackMp4 = true
            _playbackState.update {
                it.copy(loadingReason = FeedLoadingReason.RECONNECTING, hasPlaybackError = false)
            }
            prepareMediaUrl(fallbackUrl, resumePositionMs = lastPositionMs)
            return
        }
        _playbackState.update {
            it.copy(
                isPlaying = false,
                hasPlaybackError = true,
                loadingReason = FeedLoadingReason.UNAVAILABLE
            )
        }
    }

    override fun playVideo(
        video: FeedVideoDto,
        upcomingVideos: List<FeedVideoDto>,
        preloadTier: FeedPreloadTier
    ) {
        val previous = activeVideo
        if (previous != null && previous.videoId != video.videoId) {
            flushWatchProgressForActive()
        }

        val sameVideo = previous?.videoId == video.videoId
        activeVideo = video
        if (!sameVideo) {
            triedFallbackMp4 = false
            triedUrlRefresh = false
            userManuallyPaused = false
            lastReportedBitrate = 0L
            lastRewatchReported = 0
            sessionWatchAccumulatedMs = 0L
            lastPositionMs = 0L
            lastTickWallMs = System.currentTimeMillis()
        }

        val nowEpoch = System.currentTimeMillis() / 1000L
        if (video.urlExpiresAt > 0L && video.urlExpiresAt - nowEpoch < 45L && !triedUrlRefresh) {
            triedUrlRefresh = true
            scope.launch {
                val refreshed = streamRefreshCallback?.invoke(video.videoId)
                if (refreshed != null && refreshed.videoId == activeVideo?.videoId) {
                    activeVideo = refreshed
                }
            }
        }

        val primaryUrl = TelefamNetworkClient.resolveMediaUrl(video.streamUrl.ifBlank { video.fallbackMp4Url })
        val currentlyPlayingUrl = player.currentMediaItem?.localConfiguration?.uri?.toString().orEmpty()

        if (!sameVideo || currentlyPlayingUrl != primaryUrl) {
            _playbackState.update {
                it.copy(
                    activeVideoId = video.videoId,
                    loadingReason = FeedLoadingReason.INITIAL_LOAD,
                    hasPlaybackError = false,
                    positionMs = 0L,
                    durationMs = video.durationMs,
                    rewatchCountForActive = 0
                )
            }
            if (primaryUrl.isBlank()) {
                _playbackState.update {
                    it.copy(hasPlaybackError = true, loadingReason = FeedLoadingReason.UNAVAILABLE)
                }
            } else {
                prepareMediaUrl(primaryUrl, resumePositionMs = 0L)
            }
        } else if (isAppForeground && !userManuallyPaused) {
            requestAudioFocusIfNeeded()
            player.playWhenReady = true
        }

        scheduleAheadPreload(upcomingVideos, preloadTier)
    }

    private fun prepareMediaUrl(url: String, resumePositionMs: Long) {
        if (isAppForeground && !userManuallyPaused && !_playbackState.value.isMuted) {
            requestAudioFocusIfNeeded()
        }
        player.volume = if (_playbackState.value.isMuted) 0f else 1f
        player.setMediaItem(MediaItem.fromUri(Uri.parse(url)))
        if (resumePositionMs > 0L) {
            player.seekTo(resumePositionMs)
        }
        player.playWhenReady = isAppForeground && !userManuallyPaused
        player.prepare()
    }

    override fun togglePlayPause() {
        if (player.isPlaying) {
            userManuallyPaused = true
            player.playWhenReady = false
        } else {
            userManuallyPaused = false
            if (_playbackState.value.hasPlaybackError) {
                activeVideo?.let { retryActive(it) }
                return
            }
            if (!_playbackState.value.isMuted) {
                requestAudioFocusIfNeeded()
            }
            player.playWhenReady = true
        }
    }

    override fun pause() {
        flushWatchProgressForActive()
        player.playWhenReady = false
        abandonAudioFocus()
    }

    override fun resumeIfReady() {
        if (isAppForeground && !userManuallyPaused && activeVideo != null) {
            if (!_playbackState.value.isMuted) {
                requestAudioFocusIfNeeded()
            }
            player.playWhenReady = true
        }
    }

    override fun setMuted(muted: Boolean) {
        player.volume = if (muted) 0f else 1f
        if (muted) abandonAudioFocus() else if (player.playWhenReady) requestAudioFocusIfNeeded()
        _playbackState.update { it.copy(isMuted = muted) }
    }

    override fun toggleMute() {
        setMuted(!_playbackState.value.isMuted)
    }

    override fun setAppForeground(foreground: Boolean) {
        isAppForeground = foreground
        if (!foreground) {
            pause()
            releaseAllPreviews()
        } else {
            resumeIfReady()
        }
    }

    override fun retryActive(video: FeedVideoDto) {
        triedFallbackMp4 = false
        triedUrlRefresh = false
        userManuallyPaused = false
        activeVideo = video
        _playbackState.update {
            it.copy(
                activeVideoId = video.videoId,
                hasPlaybackError = false,
                loadingReason = FeedLoadingReason.RECONNECTING
            )
        }
        val url = TelefamNetworkClient.resolveMediaUrl(video.streamUrl.ifBlank { video.fallbackMp4Url })
        if (url.isNotBlank()) {
            prepareMediaUrl(url, resumePositionMs = lastPositionMs)
        }
    }

    override fun onSignedUrlRefreshed(video: FeedVideoDto) {
        if (activeVideo?.videoId != video.videoId) return
        activeVideo = video
        val url = TelefamNetworkClient.resolveMediaUrl(video.streamUrl.ifBlank { video.fallbackMp4Url })
        if (url.isNotBlank()) {
            prepareMediaUrl(url, resumePositionMs = lastPositionMs)
        }
    }

    override fun bindStreamRefreshCallback(callback: suspend (String) -> FeedVideoDto?) {
        streamRefreshCallback = callback
    }

    override fun bindWatchProgressCallback(
        callback: (videoId: String, watchDurationMs: Long, positionMs: Long, completionPct: Double, rewatchDelta: Int) -> Unit
    ) {
        watchProgressCallback = callback
    }

    override fun bindPreviewPlayer(key: String, streamUrl: String): Any? {
        val resolved = TelefamNetworkClient.resolveMediaUrl(streamUrl)
        if (resolved.isBlank()) return null
        previewPool[key]?.let { existing ->
            existing.playWhenReady = true
            return existing
        }
        while (previewOrder.size >= 2) {
            val oldest = previewOrder.removeFirstOrNull() ?: break
            previewPool.remove(oldest)?.release()
        }
        val previewPlayer = ExoPlayer.Builder(appContext)
            .setMediaSourceFactory(DefaultMediaSourceFactory(cacheDataSourceFactory))
            .build().apply {
                volume = 0f
                repeatMode = Player.REPEAT_MODE_ONE
                setMediaItem(MediaItem.fromUri(Uri.parse(resolved)))
                playWhenReady = true
                prepare()
            }
        previewPool[key] = previewPlayer
        previewOrder.addLast(key)
        return previewPlayer
    }

    override fun releasePreviewPlayer(key: String) {
        previewOrder.remove(key)
        previewPool.remove(key)?.release()
    }

    override fun releaseAllPreviews() {
        previewOrder.clear()
        val players = previewPool.values.toList()
        previewPool.clear()
        players.forEach { runCatching { it.release() } }
    }

    override fun release() {
        flushWatchProgressForActive()
        progressTickerJob?.cancel()
        preloadJob?.cancel()
        releaseAllPreviews()
        abandonAudioFocus()
        runCatching { player.release() }
    }

    private fun scheduleAheadPreload(upcomingVideos: List<FeedVideoDto>, tier: FeedPreloadTier) {
        preloadJob?.cancel()
        if (tier.aheadCount <= 0 || upcomingVideos.isEmpty()) return
        val targets = upcomingVideos.take(tier.aheadCount)
        preloadJob = scope.launch(Dispatchers.IO) {
            for (item in targets) {
                if (!isActive) break
                val rawUrl = item.fallbackMp4Url.ifBlank { item.streamUrl }
                val resolved = TelefamNetworkClient.resolveMediaUrl(rawUrl)
                if (resolved.isBlank()) continue
                runCatching {
                    val dataSpec = DataSpec.Builder()
                        .setUri(Uri.parse(resolved))
                        .setPosition(0L)
                        .setLength(tier.prefetchBytesPerVideo)
                        .build()
                    val ds = cacheDataSourceFactory.createDataSource()
                    CacheWriter(ds, dataSpec, ByteArray(16 * 1024), null).cache()
                }
            }
        }
    }

    private fun startProgressTicker() {
        progressTickerJob?.cancel()
        progressTickerJob = scope.launch {
            var flushCounter = 0
            while (isActive) {
                delay(400L)
                val vid = activeVideo ?: continue
                if (player.isPlaying) {
                    val now = System.currentTimeMillis()
                    if (lastTickWallMs > 0L) {
                        sessionWatchAccumulatedMs += (now - lastTickWallMs).coerceIn(0L, 1_500L)
                    }
                    lastTickWallMs = now

                    val pos = player.currentPosition.coerceAtLeast(0L)
                    val dur = player.duration.coerceAtLeast(vid.durationMs).coerceAtLeast(1L)
                    // Detect loop rewatch cleanly when position wraps near zero after passing 60% of duration
                    if (lastPositionMs > (dur * 3L) / 5L && pos < (dur / 5L)) {
                        lastRewatchReported += 1
                    }
                    lastPositionMs = pos
                    _playbackState.update {
                        it.copy(
                            positionMs = pos,
                            durationMs = dur,
                            bufferedPercent = player.bufferedPercentage,
                            rewatchCountForActive = lastRewatchReported
                        )
                    }
                    flushCounter += 1
                    if (flushCounter >= 8) {
                        flushCounter = 0
                        flushWatchProgressForActive()
                    }
                } else {
                    lastTickWallMs = System.currentTimeMillis()
                }
            }
        }
    }

    private fun flushWatchProgressForActive() {
        val vid = activeVideo ?: return
        if (sessionWatchAccumulatedMs < 800L) return
        val dur = player.duration.coerceAtLeast(vid.durationMs).coerceAtLeast(1L)
        val pct = ((lastPositionMs.toDouble() / dur.toDouble()) * 100.0).coerceIn(0.0, 100.0)
        watchProgressCallback?.invoke(
            vid.videoId,
            sessionWatchAccumulatedMs,
            lastPositionMs,
            pct,
            lastRewatchReported
        )
        sessionWatchAccumulatedMs = 0L
        lastRewatchReported = 0
    }

    private fun requestAudioFocusIfNeeded() {
        if (audioFocusGranted) return
        val am = audioManager ?: return
        val res = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && focusRequest != null) {
            am.requestAudioFocus(focusRequest)
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
        }
        audioFocusGranted = res == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun abandonAudioFocus() {
        if (!audioFocusGranted) return
        val am = audioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && focusRequest != null) {
            am.abandonAudioFocusRequest(focusRequest)
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(focusListener)
        }
        audioFocusGranted = false
    }
}
