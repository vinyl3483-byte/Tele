package com.telefam.company.app.ui.screens

import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import coil.compose.AsyncImage
import com.telefam.company.app.R
import com.telefam.company.app.feed.FeedFormatter
import com.telefam.company.app.feed.FeedPlaybackState
import com.telefam.company.app.feed.FeedPlayerController
import com.telefam.company.app.network.AudioSummaryDto
import com.telefam.company.app.network.CreatorSearchDto
import com.telefam.company.app.network.FeedVideoDto
import com.telefam.company.app.network.HashtagDto
import com.telefam.company.app.network.TelefamNetworkClient
import com.telefam.company.app.ui.AudioDiscoveryState
import com.telefam.company.app.ui.FeedController
import com.telefam.company.app.ui.FeedSearchState
import com.telefam.company.app.ui.FeedSearchTab
import com.telefam.company.app.ui.HashtagDiscoveryState
import com.telefam.company.app.ui.ModalFeedPlayerState
import com.telefam.company.app.ui.components.FeedAccentCoral
import com.telefam.company.app.ui.components.OfflineOrErrorFeedOverlay
import com.telefam.company.app.ui.components.TriDotSpinner
import kotlinx.coroutines.flow.distinctUntilChanged

@kotlin.OptIn(ExperimentalLayoutApi::class)
@Composable
fun FeedSearchScreen(
    state: FeedSearchState,
    feedController: FeedController,
    onClose: () -> Unit
) {
    BackHandler(onBack = onClose)

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .windowInsetsPadding(WindowInsets.statusBars)
            .windowInsetsPadding(WindowInsets.navigationBars)
    ) {
        val columns = if (maxWidth >= 600.dp) 3 else 2

        Column(modifier = Modifier.fillMaxSize()) {
            // Search header
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 10.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(
                    onClick = onClose,
                    modifier = Modifier
                        .size(48.dp)
                        .testTag("search_back_button")
                ) {
                    Image(
                        painter = painterResource(id = R.drawable.ic_back),
                        contentDescription = "Back",
                        colorFilter = ColorFilter.tint(Color.White),
                        modifier = Modifier.size(22.dp)
                    )
                }

                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(44.dp)
                        .clip(RoundedCornerShape(22.dp))
                        .background(Color(0xFF171A21))
                        .padding(horizontal = 14.dp),
                    contentAlignment = Alignment.CenterStart
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                        Image(
                            painter = painterResource(id = R.drawable.ic_search),
                            contentDescription = null,
                            colorFilter = ColorFilter.tint(Color.White.copy(alpha = 0.6f)),
                            modifier = Modifier.size(18.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Box(modifier = Modifier.weight(1f)) {
                            if (state.query.isEmpty()) {
                                Text(
                                    text = stringResource(id = R.string.feed_search_hint),
                                    color = Color.White.copy(alpha = 0.45f),
                                    fontSize = 14.sp,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                            BasicTextField(
                                value = state.query,
                                onValueChange = { feedController.updateSearchQuery(it) },
                                singleLine = true,
                                textStyle = TextStyle(color = Color.White, fontSize = 14.sp),
                                cursorBrush = SolidColor(FeedAccentCoral),
                                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                                keyboardActions = KeyboardActions(onSearch = { feedController.submitSearch(state.query) }),
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .testTag("feed_search_input")
                            )
                        }
                        if (state.query.isNotEmpty()) {
                            Image(
                                painter = painterResource(id = R.drawable.ic_close_white),
                                contentDescription = "Clear",
                                colorFilter = ColorFilter.tint(Color.White.copy(alpha = 0.7f)),
                                modifier = Modifier
                                    .size(18.dp)
                                    .clickable { feedController.updateSearchQuery("") }
                            )
                        }
                    }
                }
            }

            // Tabs
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 14.dp, vertical = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                listOf(
                    FeedSearchTab.VIDEOS to R.string.feed_search_videos_tab,
                    FeedSearchTab.HASHTAGS to R.string.feed_search_hashtags_tab,
                    FeedSearchTab.CREATORS to R.string.feed_search_creators_tab,
                    FeedSearchTab.SOUNDS to R.string.feed_search_sounds_tab
                ).forEach { (tab, labelRes) ->
                    val selected = state.activeTab == tab
                    Surface(
                        shape = RoundedCornerShape(18.dp),
                        color = if (selected) FeedAccentCoral else Color(0xFF171A21),
                        modifier = Modifier
                            .clickable { feedController.selectSearchTab(tab) }
                            .testTag("search_tab_${tab.name.lowercase()}")
                    ) {
                        Text(
                            text = stringResource(id = labelRes),
                            color = Color.White,
                            fontSize = 13.sp,
                            fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                            modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp)
                        )
                    }
                }
            }

            if (state.query.isBlank() && (state.recentSearches.isNotEmpty() || state.trending.isNotEmpty())) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    if (state.recentSearches.isNotEmpty()) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = stringResource(id = R.string.feed_search_recent),
                                color = Color.White.copy(alpha = 0.72f),
                                fontSize = 13.sp,
                                fontWeight = FontWeight.SemiBold
                            )
                            Text(
                                text = stringResource(id = R.string.feed_search_clear),
                                color = FeedAccentCoral,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Medium,
                                modifier = Modifier.clickable { feedController.clearRecentSearches() }
                            )
                        }
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            state.recentSearches.take(8).forEach { item ->
                                Surface(
                                    shape = RoundedCornerShape(16.dp),
                                    color = Color(0xFF171A21)
                                ) {
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        modifier = Modifier.padding(start = 12.dp, end = 8.dp, top = 6.dp, bottom = 6.dp)
                                    ) {
                                        Text(
                                            text = item.query,
                                            color = Color.White,
                                            fontSize = 13.sp,
                                            modifier = Modifier.clickable { feedController.submitSearch(item.query) }
                                        )
                                        Spacer(modifier = Modifier.width(6.dp))
                                        Image(
                                            painter = painterResource(id = R.drawable.ic_close_white),
                                            contentDescription = "Remove",
                                            colorFilter = ColorFilter.tint(Color.White.copy(alpha = 0.55f)),
                                            modifier = Modifier
                                                .size(14.dp)
                                                .clickable { feedController.deleteRecentSearch(item.id) }
                                        )
                                    }
                                }
                            }
                        }
                    }

                    if (state.trending.isNotEmpty()) {
                        Text(
                            text = stringResource(id = R.string.feed_search_trending),
                            color = Color.White.copy(alpha = 0.72f),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            state.trending.take(10).forEach { chip ->
                                Surface(
                                    shape = RoundedCornerShape(16.dp),
                                    color = Color(0xFF1E1418),
                                    modifier = Modifier.clickable {
                                        if (chip.startsWith("#")) {
                                            feedController.openHashtagDiscovery(chip)
                                        } else {
                                            feedController.submitSearch(chip)
                                        }
                                    }
                                ) {
                                    Text(
                                        text = chip,
                                        color = FeedAccentCoral,
                                        fontSize = 13.sp,
                                        fontWeight = FontWeight.Medium,
                                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)
                                    )
                                }
                            }
                        }
                    }
                }
            }

            Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                when {
                    state.errorMessage != null && state.videos.isEmpty() && state.hashtags.isEmpty() && state.creators.isEmpty() -> {
                        Box(modifier = Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                            OfflineOrErrorFeedOverlay(
                                message = state.errorMessage,
                                isRetrying = state.isLoading,
                                onRetry = { feedController.submitSearch(state.query) }
                            )
                        }
                    }

                    state.isLoading && state.videos.isEmpty() && state.hashtags.isEmpty() && state.creators.isEmpty() -> {
                        DiscoverySkeletonGrid(columns = columns)
                    }

                    state.activeTab == FeedSearchTab.VIDEOS -> {
                        if (state.videos.isEmpty()) {
                            EmptyDiscoveryPlaceholder()
                        } else {
                            VideoDiscoveryGrid(
                                videos = state.videos,
                                columns = columns,
                                hasMore = state.hasMore,
                                playerController = feedController.playerController,
                                enableAutoplayPreview = true,
                                onLoadMore = { feedController.loadMoreSearchResults() },
                                onVideoClick = { idx ->
                                    feedController.openModalFeedPlayer(
                                        title = state.query.ifBlank { "Explore" },
                                        videos = state.videos,
                                        index = idx
                                    )
                                }
                            )
                        }
                    }

                    state.activeTab == FeedSearchTab.HASHTAGS -> {
                        if (state.hashtags.isEmpty()) {
                            EmptyDiscoveryPlaceholder()
                        } else {
                            LazyColumn(
                                contentPadding = PaddingValues(16.dp),
                                verticalArrangement = Arrangement.spacedBy(10.dp)
                            ) {
                                items(state.hashtags, key = { it.tag }) { tag ->
                                    HashtagResultRow(tag = tag) {
                                        feedController.openHashtagDiscovery(tag.tag)
                                    }
                                }
                            }
                        }
                    }

                    state.activeTab == FeedSearchTab.CREATORS -> {
                        if (state.creators.isEmpty()) {
                            EmptyDiscoveryPlaceholder()
                        } else {
                            LazyColumn(
                                contentPadding = PaddingValues(16.dp),
                                verticalArrangement = Arrangement.spacedBy(10.dp)
                            ) {
                                items(state.creators, key = { it.userId }) { creator ->
                                    CreatorResultRow(
                                        creator = creator,
                                        onFollowToggle = {
                                            feedController.toggleCreatorFollowById(creator.userId, creator.isFollowing)
                                        }
                                    )
                                }
                            }
                        }
                    }

                    state.activeTab == FeedSearchTab.SOUNDS -> {
                        if (state.audios.isEmpty()) {
                            EmptyDiscoveryPlaceholder()
                        } else {
                            LazyColumn(
                                contentPadding = PaddingValues(16.dp),
                                verticalArrangement = Arrangement.spacedBy(10.dp)
                            ) {
                                items(state.audios, key = { it.audioId }) { audio ->
                                    AudioResultRow(audio = audio) {
                                        feedController.openAudioDiscovery(audio.audioId, audio)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun HashtagDiscoveryScreen(
    state: HashtagDiscoveryState,
    feedController: FeedController,
    onClose: () -> Unit
) {
    BackHandler(onBack = onClose)

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .windowInsetsPadding(WindowInsets.statusBars)
            .windowInsetsPadding(WindowInsets.navigationBars)
    ) {
        val columns = if (maxWidth >= 600.dp) 3 else 2

        Column(modifier = Modifier.fillMaxSize()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 10.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onClose, modifier = Modifier.size(48.dp)) {
                    Image(
                        painter = painterResource(id = R.drawable.ic_back),
                        contentDescription = "Back",
                        colorFilter = ColorFilter.tint(Color.White),
                        modifier = Modifier.size(22.dp)
                    )
                }
                Text(
                    text = "#${state.tag}",
                    color = Color.White,
                    fontSize = 19.sp,
                    fontWeight = FontWeight.Bold
                )
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(18.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    modifier = Modifier
                        .size(56.dp)
                        .clip(RoundedCornerShape(16.dp))
                        .background(Color(0xFF1B1E26)),
                    contentAlignment = Alignment.Center
                ) {
                    Text("#", color = FeedAccentCoral, fontSize = 26.sp, fontWeight = FontWeight.Bold)
                }
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = "#${state.tag}",
                        color = Color.White,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = "${stringResource(id = R.string.feed_videos_count_fmt, FeedFormatter.formatCount(state.videoCount))} · ${
                            stringResource(id = R.string.feed_views_count_fmt, FeedFormatter.formatCount(state.viewsCount))
                        }",
                        color = Color.White.copy(alpha = 0.68f),
                        fontSize = 13.sp
                    )
                }
            }

            HorizontalDivider(color = Color(0xFF1F222A), modifier = Modifier.padding(vertical = 8.dp))

            Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                when {
                    state.isLoading && state.videos.isEmpty() -> DiscoverySkeletonGrid(columns = columns)
                    state.errorMessage != null && state.videos.isEmpty() -> {
                        Box(modifier = Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                            OfflineOrErrorFeedOverlay(
                                message = state.errorMessage,
                                isRetrying = state.isLoading,
                                onRetry = { feedController.openHashtagDiscovery(state.tag) }
                            )
                        }
                    }
                    state.videos.isEmpty() -> EmptyDiscoveryPlaceholder()
                    else -> {
                        VideoDiscoveryGrid(
                            videos = state.videos,
                            columns = columns,
                            hasMore = state.hasMore,
                            playerController = feedController.playerController,
                            enableAutoplayPreview = false,
                            onLoadMore = { feedController.loadMoreHashtagVideos() },
                            onVideoClick = { idx ->
                                feedController.openModalFeedPlayer("#${state.tag}", state.videos, idx)
                            }
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun AudioDiscoveryScreen(
    state: AudioDiscoveryState,
    feedController: FeedController,
    onClose: () -> Unit
) {
    BackHandler(onBack = onClose)

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .windowInsetsPadding(WindowInsets.statusBars)
            .windowInsetsPadding(WindowInsets.navigationBars)
    ) {
        val columns = if (maxWidth >= 600.dp) 3 else 2
        val audio = state.audio

        Column(modifier = Modifier.fillMaxSize()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 10.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onClose, modifier = Modifier.size(48.dp)) {
                    Image(
                        painter = painterResource(id = R.drawable.ic_back),
                        contentDescription = "Back",
                        colorFilter = ColorFilter.tint(Color.White),
                        modifier = Modifier.size(22.dp)
                    )
                }
                Text(
                    text = audio?.title ?: stringResource(id = R.string.feed_original_sound),
                    color = Color.White,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    modifier = Modifier
                        .size(72.dp)
                        .clip(RoundedCornerShape(16.dp))
                        .background(Color(0xFF1B1E26)),
                    contentAlignment = Alignment.Center
                ) {
                    val artwork = audio?.artworkUrl?.takeIf { it.isNotBlank() }
                    if (artwork != null) {
                        AsyncImage(
                            model = TelefamNetworkClient.resolveMediaUrl(artwork),
                            contentDescription = audio.title,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxSize()
                        )
                    } else {
                        Image(
                            painter = painterResource(id = R.drawable.ic_music_note),
                            contentDescription = null,
                            colorFilter = ColorFilter.tint(FeedAccentCoral),
                            modifier = Modifier.size(30.dp)
                        )
                    }
                }
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = audio?.title ?: stringResource(id = R.string.feed_original_sound),
                        color = Color.White,
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = audio?.artist?.takeIf { it.isNotBlank() }
                            ?: stringResource(id = R.string.feed_original_sound),
                        color = Color.White.copy(alpha = 0.7f),
                        fontSize = 13.sp
                    )
                    Text(
                        text = stringResource(
                            id = R.string.feed_videos_count_fmt,
                            FeedFormatter.formatCount(audio?.usageCount ?: state.videos.size.toLong())
                        ),
                        color = Color.White.copy(alpha = 0.6f),
                        fontSize = 12.sp
                    )
                }
            }

            Button(
                onClick = { feedController.useDiscoveredAudio() },
                shape = RoundedCornerShape(24.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = FeedAccentCoral,
                    contentColor = Color.White
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 8.dp)
                    .height(48.dp)
                    .testTag("use_this_sound_button")
            ) {
                Image(
                    painter = painterResource(id = R.drawable.ic_music_note),
                    contentDescription = null,
                    colorFilter = ColorFilter.tint(Color.White),
                    modifier = Modifier.size(18.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(stringResource(id = R.string.feed_use_sound), fontWeight = FontWeight.Bold)
            }

            HorizontalDivider(color = Color(0xFF1F222A), modifier = Modifier.padding(vertical = 6.dp))

            Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                when {
                    state.isLoading && state.videos.isEmpty() -> DiscoverySkeletonGrid(columns = columns)
                    state.videos.isEmpty() -> EmptyDiscoveryPlaceholder()
                    else -> {
                        VideoDiscoveryGrid(
                            videos = state.videos,
                            columns = columns,
                            hasMore = state.hasMore,
                            playerController = feedController.playerController,
                            enableAutoplayPreview = true,
                            onLoadMore = {},
                            onVideoClick = { idx ->
                                feedController.openModalFeedPlayer(
                                    audio?.title ?: "Audio",
                                    state.videos,
                                    idx
                                )
                            }
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun FeedModalPlayerScreen(
    state: ModalFeedPlayerState,
    playbackState: FeedPlaybackState,
    feedController: FeedController,
    onClose: () -> Unit
) {
    BackHandler(onBack = onClose)
    if (state.videos.isEmpty()) return

    val pagerState = rememberPagerState(
        initialPage = state.initialIndex.coerceIn(0, state.videos.size - 1),
        pageCount = { state.videos.size }
    )

    LaunchedEffect(pagerState) {
        snapshotFlow { pagerState.settledPage }
            .distinctUntilChanged()
            .collect { settled ->
                feedController.onModalPlayerSettled(settled)
            }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
    ) {
        VerticalPager(
            state = pagerState,
            key = { idx -> state.videos[idx].videoId },
            modifier = Modifier.fillMaxSize()
        ) { idx ->
            val video = state.videos[idx]
            val isCurrent = idx == pagerState.currentPage
            FeedVideoPageItem(
                video = video,
                isActive = isCurrent,
                player = if (isCurrent) feedController.playerController.playerInstance else null,
                playbackState = playbackState,
                bottomOverlayPadding = 24.dp,
                onSingleTap = { feedController.playerController.togglePlayPause() },
                onDoubleTapLike = { feedController.onDoubleTapLike(video) },
                onRetry = { feedController.onModalPlayerSettled(idx) },
                onToggleFollow = { feedController.toggleFollowCreator(video) },
                onToggleLike = { feedController.toggleLike(video) },
                onOpenComments = { feedController.openComments(video) },
                onShare = { feedController.recordShare(video, "modal_share") },
                onToggleSave = { feedController.toggleSave(video) },
                onOpenMore = { feedController.openOptionsMenu(video) },
                onHashtagClick = { tag ->
                    onClose()
                    feedController.openHashtagDiscovery(tag)
                },
                onAudioClick = {
                    if (video.audio.audioId.isNotBlank()) {
                        onClose()
                        feedController.openAudioDiscovery(video.audio.audioId, video.audio)
                    }
                },
                onToggleMute = { feedController.playerController.toggleMute() }
            )
        }

        Row(
            modifier = Modifier
                .align(Alignment.TopStart)
                .windowInsetsPadding(WindowInsets.statusBars)
                .padding(horizontal = 10.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(
                onClick = onClose,
                modifier = Modifier
                    .size(48.dp)
                    .testTag("modal_player_back")
            ) {
                Image(
                    painter = painterResource(id = R.drawable.ic_back),
                    contentDescription = "Back",
                    colorFilter = ColorFilter.tint(Color.White),
                    modifier = Modifier.size(22.dp)
                )
            }
            if (state.title.isNotBlank()) {
                Text(
                    text = state.title,
                    color = Color.White,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}

@Composable
fun LiveComingSoonScreen(onClose: () -> Unit) {
    BackHandler(onBack = onClose)

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .windowInsetsPadding(WindowInsets.statusBars)
            .windowInsetsPadding(WindowInsets.navigationBars)
    ) {
        IconButton(
            onClick = onClose,
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(12.dp)
                .size(48.dp)
                .testTag("live_back_button")
        ) {
            Image(
                painter = painterResource(id = R.drawable.ic_back),
                contentDescription = "Back",
                colorFilter = ColorFilter.tint(Color.White),
                modifier = Modifier.size(22.dp)
            )
        }

        Column(
            modifier = Modifier
                .align(Alignment.Center)
                .padding(horizontal = 32.dp)
                .widthIn(max = 420.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(84.dp)
                    .clip(CircleShape)
                    .background(FeedAccentCoral.copy(alpha = 0.18f))
                    .border(1.dp, FeedAccentCoral.copy(alpha = 0.4f), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Image(
                    painter = painterResource(id = R.drawable.ic_live_tv),
                    contentDescription = null,
                    colorFilter = ColorFilter.tint(FeedAccentCoral),
                    modifier = Modifier.size(40.dp)
                )
            }
            Surface(
                shape = RoundedCornerShape(14.dp),
                color = FeedAccentCoral.copy(alpha = 0.2f)
            ) {
                Text(
                    text = stringResource(id = R.string.feed_coming_soon_badge),
                    color = FeedAccentCoral,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp)
                )
            }
            Text(
                text = stringResource(id = R.string.feed_live_coming_soon_title),
                color = Color.White,
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center
            )
            Text(
                text = stringResource(id = R.string.feed_live_coming_soon_desc),
                color = Color.White.copy(alpha = 0.72f),
                fontSize = 14.sp,
                lineHeight = 20.sp,
                textAlign = TextAlign.Center
            )
        }
    }
}

@OptIn(UnstableApi::class)
@Composable
private fun VideoDiscoveryGrid(
    videos: List<FeedVideoDto>,
    columns: Int,
    hasMore: Boolean,
    playerController: FeedPlayerController,
    enableAutoplayPreview: Boolean,
    onLoadMore: () -> Unit,
    onVideoClick: (Int) -> Unit
) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(columns),
        contentPadding = PaddingValues(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier.fillMaxSize()
    ) {
        itemsIndexed(videos, key = { _, item -> item.videoId }) { index, video ->
            if (hasMore && index >= videos.size - 4) {
                LaunchedEffect(videos.size) { onLoadMore() }
            }
            val shouldPreview = enableAutoplayPreview && index < 2
            val previewKey = "grid_${video.videoId}"
            val thumb = remember(video.thumbnailUrl) { TelefamNetworkClient.resolveMediaUrl(video.thumbnailUrl) }

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(0.68f)
                    .clip(RoundedCornerShape(12.dp))
                    .background(Color(0xFF14161D))
                    .clickable { onVideoClick(index) }
                    .testTag("discovery_video_card_${video.videoId}")
            ) {
                if (thumb.isNotBlank()) {
                    AsyncImage(
                        model = thumb,
                        contentDescription = video.title.ifBlank { video.description },
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize()
                    )
                }

                if (shouldPreview) {
                    val previewUrl = remember(video.fallbackMp4Url, video.streamUrl) {
                        video.fallbackMp4Url.ifBlank { video.streamUrl }
                    }
                    val previewPlayer = remember(previewKey, previewUrl) {
                        playerController.bindPreviewPlayer(previewKey, previewUrl)
                    }
                    DisposableEffect(previewKey) {
                        onDispose { playerController.releasePreviewPlayer(previewKey) }
                    }
                    if (previewPlayer is Player) {
                        AndroidView(
                            factory = { ctx ->
                                PlayerView(ctx).apply {
                                    layoutParams = FrameLayout.LayoutParams(
                                        ViewGroup.LayoutParams.MATCH_PARENT,
                                        ViewGroup.LayoutParams.MATCH_PARENT
                                    )
                                    useController = false
                                    resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                                    player = previewPlayer
                                }
                            },
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                }

                Row(
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .fillMaxWidth()
                        .background(Color.Black.copy(alpha = 0.55f))
                        .padding(horizontal = 8.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = "@${video.creatorUsername.ifBlank { video.creatorName }}",
                        color = Color.White,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Medium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f)
                    )
                    Text(
                        text = FeedFormatter.formatCount(video.viewsCount),
                        color = Color.White.copy(alpha = 0.8f),
                        fontSize = 11.sp
                    )
                }
            }
        }
    }
}

@Composable
private fun DiscoverySkeletonGrid(columns: Int) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(columns),
        contentPadding = PaddingValues(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier.fillMaxSize()
    ) {
        items(6) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(0.68f)
                    .clip(RoundedCornerShape(12.dp))
                    .background(Color(0xFF171A21))
            )
        }
    }
}

@Composable
private fun EmptyDiscoveryPlaceholder() {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(
            text = stringResource(id = R.string.feed_search_empty),
            color = Color.White.copy(alpha = 0.65f),
            fontSize = 15.sp
        )
    }
}

@Composable
private fun HashtagResultRow(tag: HashtagDto, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(Color(0xFF14161D))
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(FeedAccentCoral.copy(alpha = 0.16f)),
                contentAlignment = Alignment.Center
            ) {
                Text("#", color = FeedAccentCoral, fontSize = 18.sp, fontWeight = FontWeight.Bold)
            }
            Text("#${tag.tag}", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        }
        Text(
            text = stringResource(id = R.string.feed_videos_count_fmt, FeedFormatter.formatCount(tag.postCount)),
            color = Color.White.copy(alpha = 0.65f),
            fontSize = 13.sp
        )
    }
}

@Composable
private fun CreatorResultRow(creator: CreatorSearchDto, onFollowToggle: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(Color(0xFF14161D))
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(CircleShape)
                .background(Color(0xFF232732)),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = creator.fullName.ifBlank { creator.username }.take(2).uppercase(),
                color = Color.White,
                fontWeight = FontWeight.Bold
            )
        }
        Spacer(modifier = Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(creator.fullName.ifBlank { creator.username }, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            Text("@${creator.username}", color = Color.White.copy(alpha = 0.65f), fontSize = 13.sp)
        }
        TextButton(onClick = onFollowToggle) {
            Text(
                text = if (creator.isFollowing) "Following" else "Follow",
                color = if (creator.isFollowing) Color.White.copy(alpha = 0.7f) else FeedAccentCoral,
                fontWeight = FontWeight.Bold
            )
        }
    }
}

@Composable
private fun AudioResultRow(audio: AudioSummaryDto, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(Color(0xFF14161D))
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(FeedAccentCoral.copy(alpha = 0.16f)),
            contentAlignment = Alignment.Center
        ) {
            Image(
                painter = painterResource(id = R.drawable.ic_music_note),
                contentDescription = null,
                colorFilter = ColorFilter.tint(FeedAccentCoral),
                modifier = Modifier.size(20.dp)
            )
        }
        Spacer(modifier = Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(audio.title, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                text = audio.artist.ifBlank { stringResource(id = R.string.feed_original_sound) },
                color = Color.White.copy(alpha = 0.65f),
                fontSize = 13.sp
            )
        }
        Text(
            text = stringResource(id = R.string.feed_videos_count_fmt, FeedFormatter.formatCount(audio.usageCount)),
            color = Color.White.copy(alpha = 0.65f),
            fontSize = 12.sp
        )
    }
}
