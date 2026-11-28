package com.telefam.company.app.ui.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.telefam.company.app.R
import com.telefam.company.app.feed.FeedFormatter
import com.telefam.company.app.feed.FeedLoadingReason
import com.telefam.company.app.feed.FeedPlaybackState
import com.telefam.company.app.feed.FeedTab
import com.telefam.company.app.network.FeedVideoDto
import com.telefam.company.app.network.TelefamNetworkClient
import com.telefam.company.app.ui.FeedController
import com.telefam.company.app.ui.VideoFeedUiState
import com.telefam.company.app.ui.components.AdaptiveFeedVideoSurface
import com.telefam.company.app.ui.components.CommentsComingSoonSheet
import com.telefam.company.app.ui.components.ConfirmSafetyDialog
import com.telefam.company.app.ui.components.DoubleTapHeartBurst
import com.telefam.company.app.ui.components.ExpandableRichCaption
import com.telefam.company.app.ui.components.FeedAccentCoral
import com.telefam.company.app.ui.components.FeedVideoOptionsSheet
import com.telefam.company.app.ui.components.HeartBurstInstance
import com.telefam.company.app.ui.components.OfflineOrErrorFeedOverlay
import com.telefam.company.app.ui.components.OwnerEditDetailsSheet
import com.telefam.company.app.ui.components.OwnerVisibilitySheet
import com.telefam.company.app.ui.components.ReportVideoSheet
import com.telefam.company.app.ui.components.TriDotSpinner
import kotlinx.coroutines.flow.distinctUntilChanged

@Composable
fun FeedScreen(
    feedState: VideoFeedUiState,
    playbackState: FeedPlaybackState,
    feedController: FeedController,
    bottomOverlayPadding: Dp,
    isActiveTab: Boolean,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val channel = feedState.activeChannel
    val snackbarHostState = remember { SnackbarHostState() }
    var shareTargetVideo by remember { mutableStateOf<FeedVideoDto?>(null) }

    LaunchedEffect(feedState.toastMessage) {
        val msg = feedState.toastMessage
        if (!msg.isNullOrBlank()) {
            snackbarHostState.currentSnackbarData?.dismiss()
            snackbarHostState.showSnackbar(msg)
            feedController.clearToast()
        }
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Color.Black)
    ) {
        when {
            channel.isInitialLoading && channel.videos.isEmpty() -> {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    TriDotSpinner()
                }
            }

            channel.errorMessage != null && channel.videos.isEmpty() -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 24.dp),
                    contentAlignment = Alignment.Center
                ) {
                    OfflineOrErrorFeedOverlay(
                        message = channel.errorMessage,
                        isRetrying = channel.isInitialLoading,
                        onRetry = { feedController.refreshActiveFeed() }
                    )
                }
            }

            channel.videos.isEmpty() -> {
                Column(
                    modifier = Modifier
                        .align(Alignment.Center)
                        .padding(horizontal = 32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(
                        text = stringResource(
                            id = if (feedState.selectedTab == FeedTab.FOLLOWING) {
                                R.string.feed_empty_following
                            } else {
                                R.string.feed_empty_for_you
                            }
                        ),
                        color = Color.White,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Medium
                    )
                    Button(
                        onClick = { feedController.refreshActiveFeed() },
                        shape = RoundedCornerShape(24.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = FeedAccentCoral,
                            contentColor = Color.White
                        )
                    ) {
                        Text(stringResource(id = R.string.feed_retry))
                    }
                }
            }

            else -> {
                val pagerState = rememberPagerState(
                    initialPage = channel.currentIndex.coerceIn(0, (channel.videos.size - 1).coerceAtLeast(0)),
                    pageCount = { channel.videos.size }
                )

                LaunchedEffect(feedState.selectedTab, channel.videos.size) {
                    val target = channel.currentIndex.coerceIn(0, (channel.videos.size - 1).coerceAtLeast(0))
                    if (pagerState.currentPage != target && channel.videos.isNotEmpty()) {
                        pagerState.scrollToPage(target)
                    }
                }

                LaunchedEffect(pagerState, isActiveTab, channel.videos) {
                    snapshotFlow { pagerState.settledPage }
                        .distinctUntilChanged()
                        .collect { settled ->
                            feedController.onPagerSettled(
                                settled,
                                shouldPlay = isActiveTab &&
                                    !feedState.modalPlayer.isOpen &&
                                    !feedState.search.isOpen &&
                                    !feedState.hashtagDiscovery.isOpen &&
                                    !feedState.audioDiscovery.isOpen &&
                                    !feedState.isLiveScreenOpen
                            )
                        }
                }

                VerticalPager(
                    state = pagerState,
                    beyondViewportPageCount = 1,
                    key = { idx -> channel.videos.getOrNull(idx)?.videoId ?: idx },
                    modifier = Modifier
                        .fillMaxSize()
                        .testTag("feed_vertical_pager")
                ) { pageIdx ->
                    val video = channel.videos.getOrNull(pageIdx) ?: return@VerticalPager
                    val isCurrent = isActiveTab &&
                        pageIdx == pagerState.currentPage &&
                        !feedState.modalPlayer.isOpen

                    FeedVideoPageItem(
                        video = video,
                        creatorDisplayOverride = feedState.viewerNicknames[video.creatorId].orEmpty(),
                        isActive = isCurrent,
                        player = if (isCurrent) feedController.playerController.playerInstance else null,
                        playbackState = playbackState,
                        bottomOverlayPadding = bottomOverlayPadding,
                        onSingleTap = { feedController.playerController.togglePlayPause() },
                        onDoubleTapLike = { feedController.onDoubleTapLike(video) },
                        onRetry = { feedController.retryActiveVideo() },
                        onCreatorClick = { feedController.openCreatorProfile(video.creatorId) },
                        onToggleFollow = { feedController.toggleFollowCreator(video) },
                        onToggleLike = { feedController.toggleLike(video) },
                        onOpenComments = { feedController.openComments(video) },
                        onShare = { shareTargetVideo = video },
                        onToggleSave = { feedController.toggleSave(video) },
                        onOpenMore = { feedController.openOptionsMenu(video) },
                        onHashtagClick = { tag -> feedController.openHashtagDiscovery(tag) },
                        onAudioClick = {
                            if (video.audio.audioId.isNotBlank()) {
                                feedController.openAudioDiscovery(video.audio.audioId, video.audio)
                            }
                        },
                        onToggleMute = { feedController.playerController.toggleMute() }
                    )
                }
            }
        }

        // Top Bar: LIVE | Following | For You | Search
        FeedTopNavigationBar(
            selectedTab = feedState.selectedTab,
            onLiveClick = { feedController.openLiveScreen() },
            onSelectTab = { tab -> feedController.selectFeedTab(tab) },
            onSearchClick = { feedController.openSearch() },
            modifier = Modifier
                .align(Alignment.TopCenter)
                .fillMaxWidth()
                .windowInsetsPadding(WindowInsets.statusBars)
                .padding(horizontal = 12.dp, vertical = 10.dp)
        )

        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = bottomOverlayPadding + 14.dp, start = 16.dp, end = 16.dp)
        )
    }

    shareTargetVideo?.let { target ->
        ShareVideoSheet(
            video = target,
            onNativeShare = {
                shareTargetVideo = null
                feedController.recordShare(target, "system_sheet")
                val shareUrl = TelefamNetworkClient.baseUrl().trimEnd('/') + "/v/${target.videoId}"
                val shareText = buildString {
                    if (target.title.isNotBlank()) append(target.title).append("\n")
                    append(shareUrl)
                }
                val intent = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, shareText)
                }
                runCatching {
                    context.startActivity(Intent.createChooser(intent, context.getString(R.string.feed_share_title)))
                }
            },
            onCopyLink = {
                shareTargetVideo = null
                feedController.recordShare(target, "copy_link")
                val shareUrl = TelefamNetworkClient.baseUrl().trimEnd('/') + "/v/${target.videoId}"
                val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                cm?.setPrimaryClip(ClipData.newPlainText("Telefam video", shareUrl))
                android.widget.Toast.makeText(
                    context,
                    context.getString(R.string.feed_link_copied),
                    android.widget.Toast.LENGTH_SHORT
                ).show()
            },
            onDismiss = { shareTargetVideo = null }
        )
    }

    feedState.commentsVideo?.let { v ->
        CommentsComingSoonSheet(
            video = v,
            onDismiss = { feedController.closeComments() }
        )
    }

    feedState.optionsMenuVideo?.let { v ->
        FeedVideoOptionsSheet(
            video = v,
            onDismiss = { feedController.closeOptionsMenu() },
            onReport = { feedController.startReport(it) },
            onToggleRepost = { feedController.toggleRepost(it) },
            onBlockUser = { feedController.requestBlockUser(it) },
            onMuteUser = { feedController.muteUserFromVideo(it) },
            onNotInterested = { feedController.markNotInterested(it) },
            onEditDetails = { feedController.openOwnerEditSheet(it) },
            onMarkPrivate = { feedController.markVideoAsPrivate(it) },
            onChangeVisibility = { feedController.openVisibilitySheet(it) },
            onDeleteVideo = { feedController.requestDeleteVideo(it) }
        )
    }

    ReportVideoSheet(
        state = feedState.reportSheet,
        onSelectReason = { feedController.selectReportReason(it) },
        onDetailsChange = { feedController.updateReportDetails(it) },
        onBackStep = { feedController.backReportStep() },
        onSubmit = { feedController.submitReport() },
        onDismiss = { feedController.closeReportSheet() }
    )

    OwnerEditDetailsSheet(
        state = feedState.ownerEditSheet,
        onTitleChange = { feedController.updateOwnerEditFields(title = it) },
        onDescriptionChange = { feedController.updateOwnerEditFields(description = it) },
        onSave = { feedController.saveOwnerEditDetails() },
        onDismiss = { feedController.closeOwnerEditSheet() }
    )

    feedState.ownerVisibilityVideo?.let { v ->
        OwnerVisibilitySheet(
            video = v,
            onSelectVisibility = { vis -> feedController.updateVideoVisibility(v, vis) },
            onDismiss = { feedController.closeVisibilitySheet() }
        )
    }

    feedState.confirmBlockVideo?.let { v ->
        ConfirmSafetyDialog(
            title = stringResource(id = R.string.feed_confirm_block_title, v.creatorUsername.ifBlank { v.creatorName }),
            description = stringResource(id = R.string.feed_confirm_block_desc),
            onConfirm = { feedController.confirmBlockUser() },
            onDismiss = { feedController.dismissBlockDialog() }
        )
    }

    feedState.confirmDeleteVideo?.let {
        ConfirmSafetyDialog(
            title = stringResource(id = R.string.feed_confirm_delete_title),
            description = stringResource(id = R.string.feed_confirm_delete_desc),
            onConfirm = { feedController.confirmDeleteVideo() },
            onDismiss = { feedController.dismissDeleteDialog() }
        )
    }
}

@Composable
private fun FeedTopNavigationBar(
    selectedTab: FeedTab,
    onLiveClick: () -> Unit,
    onSelectTab: (FeedTab) -> Unit,
    onSearchClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        IconButton(
            onClick = onLiveClick,
            modifier = Modifier
                .size(48.dp)
                .testTag("feed_live_button")
        ) {
            Image(
                painter = painterResource(id = R.drawable.ic_live_tv),
                contentDescription = stringResource(id = R.string.feed_live),
                colorFilter = ColorFilter.tint(Color.White),
                modifier = Modifier.size(26.dp)
            )
        }

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(22.dp)
        ) {
            FeedHeaderTabLabel(
                label = stringResource(id = R.string.feed_following),
                selected = selectedTab == FeedTab.FOLLOWING,
                onClick = { onSelectTab(FeedTab.FOLLOWING) },
                testTag = "feed_tab_following"
            )
            FeedHeaderTabLabel(
                label = stringResource(id = R.string.feed_for_you),
                selected = selectedTab == FeedTab.FOR_YOU,
                onClick = { onSelectTab(FeedTab.FOR_YOU) },
                testTag = "feed_tab_for_you"
            )
        }

        IconButton(
            onClick = onSearchClick,
            modifier = Modifier
                .size(48.dp)
                .testTag("feed_search_button")
        ) {
            Image(
                painter = painterResource(id = R.drawable.ic_search),
                contentDescription = stringResource(id = R.string.feed_search_hint),
                colorFilter = ColorFilter.tint(Color.White),
                modifier = Modifier.size(24.dp)
            )
        }
    }
}

@Composable
private fun FeedHeaderTabLabel(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    testTag: String
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .clickable(onClick = onClick)
            .padding(horizontal = 6.dp, vertical = 6.dp)
            .testTag(testTag)
    ) {
        Text(
            text = label,
            color = if (selected) Color.White else Color.White.copy(alpha = 0.68f),
            fontSize = 17.sp,
            fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium
        )
        Spacer(modifier = Modifier.height(5.dp))
        Box(
            modifier = Modifier
                .width(30.dp)
                .height(3.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(if (selected) Color.White else Color.Transparent)
        )
    }
}

@Composable
fun FeedVideoPageItem(
    video: FeedVideoDto,
    creatorDisplayOverride: String = "",
    isActive: Boolean,
    player: Any?,
    playbackState: FeedPlaybackState,
    bottomOverlayPadding: Dp,
    onSingleTap: () -> Unit,
    onDoubleTapLike: () -> Unit,
    onRetry: () -> Unit,
    onCreatorClick: () -> Unit = {},
    onToggleFollow: () -> Unit,
    onToggleLike: () -> Unit,
    onOpenComments: () -> Unit,
    onShare: () -> Unit,
    onToggleSave: () -> Unit,
    onOpenMore: () -> Unit,
    onHashtagClick: (String) -> Unit,
    onAudioClick: () -> Unit,
    onToggleMute: () -> Unit
) {
    val heartBursts = remember { mutableStateListOf<HeartBurstInstance>() }
    var nextBurstId by remember { mutableLongStateOf(1L) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
    ) {
        AdaptiveFeedVideoSurface(
            video = video,
            isActive = isActive,
            player = player,
            isPlaying = playbackState.isPlaying,
            loadingReason = if (isActive && playbackState.activeVideoId == video.videoId) {
                playbackState.loadingReason
            } else {
                FeedLoadingReason.NONE
            },
            onSingleTap = onSingleTap,
            onDoubleTap = { offset ->
                heartBursts.add(HeartBurstInstance(nextBurstId++, offset))
                onDoubleTapLike()
            }
        )

        heartBursts.forEach { burst ->
            DoubleTapHeartBurst(
                burst = burst,
                onFinished = { finishedId -> heartBursts.removeAll { it.id == finishedId } }
            )
        }

        if (isActive && playbackState.activeVideoId == video.videoId &&
            (playbackState.hasPlaybackError || playbackState.loadingReason == FeedLoadingReason.UNAVAILABLE)
        ) {
            OfflineOrErrorFeedOverlay(
                message = stringResource(id = R.string.feed_video_unavailable),
                isRetrying = playbackState.loadingReason == FeedLoadingReason.RECONNECTING,
                onRetry = onRetry,
                modifier = Modifier
                    .align(Alignment.Center)
                    .padding(horizontal = 24.dp)
            )
        }

        // Bottom-left Metadata Column (matching reference screenshot)
        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(start = 14.dp, end = 86.dp, bottom = bottomOverlayPadding + 16.dp)
                .widthIn(max = 500.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            if (video.recommendationLabel.isNotBlank()) {
                Surface(
                    shape = RoundedCornerShape(14.dp),
                    color = Color.Black.copy(alpha = 0.45f),
                    modifier = Modifier.border(
                        width = 0.8.dp,
                        color = Color.White.copy(alpha = 0.16f),
                        shape = RoundedCornerShape(14.dp)
                    )
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(12.dp)
                                .clip(CircleShape)
                                .background(FeedAccentCoral),
                            contentAlignment = Alignment.Center
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(4.dp)
                                    .clip(CircleShape)
                                    .background(Color.White)
                            )
                        }
                        Text(
                            text = video.recommendationLabel,
                            color = Color.White.copy(alpha = 0.92f),
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Medium
                        )
                    }
                }
            }

            val baseHandle = video.creatorUsername.ifBlank { video.creatorName }
            val handle = creatorDisplayOverride.trim().ifBlank { baseHandle }
            if (handle.isNotBlank()) {
                Text(
                    text = handle,
                    color = Color.White,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .clip(RoundedCornerShape(6.dp))
                        .clickable(onClick = onCreatorClick)
                        .padding(vertical = 2.dp)
                        .testTag("feed_creator_name_${video.videoId}")
                )
            }

            ExpandableRichCaption(
                description = video.description.ifBlank { video.title },
                hashtags = video.hashtags,
                onHashtagClick = onHashtagClick
            )

            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .clip(RoundedCornerShape(12.dp))
                    .clickable(onClick = onAudioClick)
                    .padding(vertical = 3.dp)
                    .testTag("feed_audio_row_${video.videoId}")
            ) {
                Image(
                    painter = painterResource(id = R.drawable.ic_music_note),
                    contentDescription = null,
                    colorFilter = ColorFilter.tint(Color.White),
                    modifier = Modifier.size(16.dp)
                )
                Spacer(modifier = Modifier.width(6.dp))
                val audioLabel = if (video.audio.isOriginal || video.audio.title.isBlank()) {
                    stringResource(id = R.string.feed_original_sound)
                } else if (video.audio.artist.isNotBlank()) {
                    "${video.audio.title} · ${video.audio.artist}"
                } else {
                    video.audio.title
                }
                Text(
                    text = audioLabel,
                    color = Color.White,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Image(
                    painter = painterResource(id = R.drawable.ic_equalizer),
                    contentDescription = null,
                    colorFilter = ColorFilter.tint(Color.White),
                    modifier = Modifier.size(16.dp)
                )
                Spacer(modifier = Modifier.width(10.dp))
                Box(
                    modifier = Modifier
                        .size(28.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.45f))
                        .clickable(onClick = onToggleMute),
                    contentAlignment = Alignment.Center
                ) {
                    Image(
                        painter = painterResource(
                            id = if (playbackState.isMuted) R.drawable.ic_volume_off else R.drawable.ic_volume_on
                        ),
                        contentDescription = null,
                        colorFilter = ColorFilter.tint(Color.White),
                        modifier = Modifier.size(15.dp)
                    )
                }
            }
        }

        // Right-side Interaction Column matching screenshot closely
        Column(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(end = 12.dp, bottom = bottomOverlayPadding + 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            CreatorAvatarFollowButton(
                creatorName = creatorDisplayOverride.trim().ifBlank {
                    video.creatorName.ifBlank { video.creatorUsername }
                },
                avatarHash = video.creatorAvatarHash,
                showFollowPlus = !video.isOwner && !video.isFollowingCreator,
                onAvatarClick = onCreatorClick,
                onFollowClick = onToggleFollow
            )

            FeedActionIconButton(
                iconRes = if (video.isLiked) R.drawable.ic_heart_filled else R.drawable.ic_heart_outline,
                tint = if (video.isLiked) FeedAccentCoral else Color.White,
                countText = FeedFormatter.formatCount(video.likesCount),
                contentDescription = "Like",
                onClick = onToggleLike,
                testTag = "feed_like_button_${video.videoId}"
            )

            FeedActionIconButton(
                iconRes = R.drawable.ic_feed_comment,
                tint = Color.White,
                countText = FeedFormatter.formatCount(video.commentsCount),
                contentDescription = stringResource(id = R.string.feed_comments_coming_soon),
                onClick = onOpenComments,
                testTag = "feed_comment_button_${video.videoId}"
            )

            FeedActionIconButton(
                iconRes = R.drawable.ic_feed_share,
                tint = Color.White,
                countText = FeedFormatter.formatCount(video.sharesCount),
                contentDescription = stringResource(id = R.string.feed_share_title),
                onClick = onShare,
                testTag = "feed_share_button_${video.videoId}"
            )

            FeedActionIconButton(
                iconRes = if (video.isSaved) R.drawable.ic_bookmark_filled else R.drawable.ic_bookmark_outline,
                tint = if (video.isSaved) FeedAccentCoral else Color.White,
                countText = FeedFormatter.formatCount(video.savesCount),
                contentDescription = "Save",
                onClick = onToggleSave,
                testTag = "feed_save_button_${video.videoId}"
            )

            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    .clickable(onClick = onOpenMore)
                    .testTag("feed_more_button_${video.videoId}"),
                contentAlignment = Alignment.Center
            ) {
                Image(
                    painter = painterResource(id = R.drawable.ic_more_horiz),
                    contentDescription = "More options",
                    colorFilter = ColorFilter.tint(Color.White),
                    modifier = Modifier.size(26.dp)
                )
            }
        }

        // Thin playback progress bar at bottom above nav bar
        if (isActive && playbackState.activeVideoId == video.videoId && playbackState.durationMs > 0L) {
            val fraction = (playbackState.positionMs.toFloat() / playbackState.durationMs.toFloat()).coerceIn(0f, 1f)
            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = bottomOverlayPadding)
                    .fillMaxWidth()
                    .height(2.dp)
                    .background(Color.White.copy(alpha = 0.2f))
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth(fraction)
                        .height(2.dp)
                        .background(Color.White.copy(alpha = 0.85f))
                )
            }
        }
    }
}

@Composable
private fun CreatorAvatarFollowButton(
    creatorName: String,
    avatarHash: String,
    showFollowPlus: Boolean,
    onAvatarClick: () -> Unit,
    onFollowClick: () -> Unit
) {
    Box(
        modifier = Modifier.size(54.dp),
        contentAlignment = Alignment.TopCenter
    ) {
        Box(
            modifier = Modifier
                .size(46.dp)
                .clip(CircleShape)
                .border(1.5.dp, Color.White, CircleShape)
                .background(Color(0xFF23262F))
                .clickable(onClick = onAvatarClick)
                .testTag("feed_creator_avatar_button"),
            contentAlignment = Alignment.Center
        ) {
            if (avatarHash.startsWith("http")) {
                AsyncImage(
                    model = avatarHash,
                    contentDescription = creatorName,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize()
                )
            } else {
                Text(
                    text = creatorName.ifBlank { "T" }.take(2).uppercase(),
                    color = Color.White,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold
                )
            }
        }

        if (showFollowPlus) {
            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .size(22.dp)
                    .clip(CircleShape)
                    .background(FeedAccentCoral)
                    .clickable(onClick = onFollowClick)
                    .testTag("feed_creator_follow_button"),
                contentAlignment = Alignment.Center
            ) {
                Image(
                    painter = painterResource(id = R.drawable.ic_add),
                    contentDescription = "Follow",
                    colorFilter = ColorFilter.tint(Color.White),
                    modifier = Modifier.size(12.dp)
                )
            }
        }
    }
}

@Composable
private fun FeedActionIconButton(
    iconRes: Int,
    tint: Color,
    countText: String,
    contentDescription: String,
    onClick: () -> Unit,
    testTag: String
) {
    Column(
        modifier = Modifier
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 6.dp, vertical = 2.dp)
            .testTag(testTag),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Image(
            painter = painterResource(id = iconRes),
            contentDescription = contentDescription,
            colorFilter = ColorFilter.tint(tint),
            modifier = Modifier.size(32.dp)
        )
        Spacer(modifier = Modifier.height(3.dp))
        Text(
            text = countText,
            color = Color.White,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ShareVideoSheet(
    video: FeedVideoDto,
    onNativeShare: () -> Unit,
    onCopyLink: () -> Unit,
    onDismiss: () -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = Color(0xFF15171C),
        contentColor = Color.White
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = stringResource(id = R.string.feed_share_title),
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )
            if (video.title.isNotBlank()) {
                Text(
                    text = video.title,
                    fontSize = 13.sp,
                    color = Color.White.copy(alpha = 0.65f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Button(
                    onClick = onNativeShare,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = FeedAccentCoral,
                        contentColor = Color.White
                    ),
                    modifier = Modifier
                        .weight(1f)
                        .height(48.dp)
                        .testTag("feed_share_native_button")
                ) {
                    Text(stringResource(id = R.string.feed_share_title))
                }
                Button(
                    onClick = onCopyLink,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color(0xFF262A33),
                        contentColor = Color.White
                    ),
                    modifier = Modifier
                        .weight(1f)
                        .height(48.dp)
                        .testTag("feed_share_copy_button")
                ) {
                    Text(stringResource(id = R.string.feed_copy_link))
                }
            }
            Spacer(modifier = Modifier.height(10.dp))
        }
    }
}
