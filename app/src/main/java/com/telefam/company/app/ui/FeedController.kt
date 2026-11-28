package com.telefam.company.app.ui

import com.telefam.company.app.core.NetworkQuality
import com.telefam.company.app.data.FeedRepository
import com.telefam.company.app.data.RepoResult
import com.telefam.company.app.feed.FeedPlayerController
import com.telefam.company.app.feed.FeedPreloadTier
import com.telefam.company.app.feed.FeedReportReason
import com.telefam.company.app.feed.FeedTab
import com.telefam.company.app.network.AudioSummaryDto
import com.telefam.company.app.network.FeedVideoDto
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class FeedController(
    private val scope: CoroutineScope,
    private val feedRepository: FeedRepository,
    val playerController: FeedPlayerController,
    private val networkQualityProvider: () -> NetworkQuality,
    private val onContactsChanged: () -> Unit,
    private val onUseAudioInPost: (AudioSummaryDto) -> Unit,
    private val onOpenUserProfile: (String) -> Unit = {}
) {
    private val _state = MutableStateFlow(VideoFeedUiState())
    val state: StateFlow<VideoFeedUiState> = _state.asStateFlow()

    private val recordedInitialViews = HashSet<String>()
    private var searchDebounceJob: Job? = null

    init {
        playerController.bindStreamRefreshCallback { videoId ->
            when (val res = feedRepository.refreshStreamUrl(videoId)) {
                is RepoResult.Success -> {
                    val refreshed = res.data
                    var updatedVideo: FeedVideoDto? = null
                    updateVideoEverywhere(videoId) { v ->
                        val next = v.copy(
                            streamUrl = refreshed.streamUrl,
                            fallbackMp4Url = refreshed.fallbackMp4Url,
                            thumbnailUrl = refreshed.thumbnailUrl.ifBlank { v.thumbnailUrl },
                            streamType = refreshed.streamType,
                            urlExpiresAt = refreshed.urlExpiresAt,
                            variants = if (refreshed.variants.isNotEmpty()) refreshed.variants else v.variants
                        )
                        updatedVideo = next
                        next
                    }
                    updatedVideo
                }
                is RepoResult.Failure -> null
            }
        }
        playerController.bindWatchProgressCallback { videoId, watchDurationMs, posMs, completionPct, rewatchDelta ->
            scope.launch {
                val isInitial = recordedInitialViews.add(videoId)
                feedRepository.recordViewOrProgress(
                    videoId = videoId,
                    watchDurationMs = watchDurationMs,
                    positionMs = posMs,
                    completionPct = completionPct,
                    rewatchDelta = rewatchDelta,
                    isInitialView = isInitial
                )
            }
        }
    }

    fun updateViewerNicknames(nicknames: Map<String, String>) {
        _state.update { it.copy(viewerNicknames = nicknames) }
    }

    fun openCreatorProfile(userId: String) {
        if (userId.isBlank()) return
        playerController.pause()
        onOpenUserProfile(userId)
    }

    fun loadInitialFromCacheAndRefresh(isLoggedIn: Boolean) {
        if (!isLoggedIn) return
        scope.launch {
            val cachedForYou = feedRepository.loadCachedFeedVideos(FeedTab.FOR_YOU)
            val cachedFollowing = feedRepository.loadCachedFeedVideos(FeedTab.FOLLOWING)
            val cachedSaved = feedRepository.loadCachedSavedVideos()
            _state.update { st ->
                st.copy(
                    forYou = if (st.forYou.videos.isEmpty() && cachedForYou.isNotEmpty()) {
                        st.forYou.copy(videos = cachedForYou)
                    } else st.forYou,
                    following = if (st.following.videos.isEmpty() && cachedFollowing.isNotEmpty()) {
                        st.following.copy(videos = cachedFollowing)
                    } else st.following,
                    profileSavedAndSafety = st.profileSavedAndSafety.copy(
                        savedVideos = st.profileSavedAndSafety.savedVideos.ifEmpty { cachedSaved }
                    )
                )
            }
            if (networkQualityProvider() == NetworkQuality.ONLINE) {
                refreshFeed(FeedTab.FOR_YOU)
                refreshFeed(FeedTab.FOLLOWING)
            }
        }
    }

    fun selectFeedTab(tab: FeedTab) {
        _state.update { it.copy(selectedTab = tab) }
        val channel = if (tab == FeedTab.FOR_YOU) _state.value.forYou else _state.value.following
        if (channel.videos.isEmpty()) {
            refreshFeed(tab)
        } else {
            playAtChannelIndex(channel.currentIndex)
        }
    }

    fun refreshActiveFeed() = refreshFeed(_state.value.selectedTab)

    fun refreshFeed(tab: FeedTab) {
        if (networkQualityProvider() == NetworkQuality.OFFLINE) {
            updateChannel(tab) {
                it.copy(
                    isInitialLoading = false,
                    errorMessage = if (it.videos.isEmpty()) "No internet" else null
                )
            }
            return
        }
        scope.launch {
            updateChannel(tab) { it.copy(isInitialLoading = true, errorMessage = null) }
            when (val res = feedRepository.fetchFeedPage(tab, cursor = "", limit = 15)) {
                is RepoResult.Success -> {
                    val page = res.data
                    updateChannel(tab) {
                        val safeIdx = it.currentIndex.coerceIn(0, (page.videos.size - 1).coerceAtLeast(0))
                        it.copy(
                            videos = page.videos,
                            nextCursor = page.nextCursor,
                            hasMore = page.hasMore,
                            isInitialLoading = false,
                            errorMessage = null,
                            currentIndex = safeIdx
                        )
                    }
                    if (_state.value.selectedTab == tab && page.videos.isNotEmpty()) {
                        val idx = _state.value.activeChannel.currentIndex
                        playAtChannelIndex(idx)
                    }
                }
                is RepoResult.Failure -> {
                    updateChannel(tab) {
                        it.copy(isInitialLoading = false, errorMessage = res.userMessage)
                    }
                }
            }
        }
    }

    fun onPagerSettled(index: Int, shouldPlay: Boolean) {
        val tab = _state.value.selectedTab
        val channel = _state.value.activeChannel
        if (index < 0 || index >= channel.videos.size) return
        updateChannel(tab) { it.copy(currentIndex = index) }
        if (shouldPlay) {
            playAtChannelIndex(index)
        }
        if (channel.hasMore && !channel.isLoadingMore && index >= channel.videos.size - 4) {
            loadMore(tab)
        }
    }

    fun loadMore(tab: FeedTab = _state.value.selectedTab) {
        val ch = if (tab == FeedTab.FOR_YOU) _state.value.forYou else _state.value.following
        if (ch.isLoadingMore || !ch.hasMore || ch.nextCursor.isBlank() || networkQualityProvider() == NetworkQuality.OFFLINE) return
        scope.launch {
            updateChannel(tab) { it.copy(isLoadingMore = true) }
            when (val res = feedRepository.fetchFeedPage(tab, cursor = ch.nextCursor, limit = 15)) {
                is RepoResult.Success -> {
                    updateChannel(tab) { cur ->
                        val existingIds = cur.videos.mapTo(HashSet()) { it.videoId }
                        val merged = cur.videos + res.data.videos.filterNot { existingIds.contains(it.videoId) }
                        cur.copy(
                            videos = merged,
                            nextCursor = res.data.nextCursor,
                            hasMore = res.data.hasMore,
                            isLoadingMore = false
                        )
                    }
                }
                is RepoResult.Failure -> {
                    updateChannel(tab) { it.copy(isLoadingMore = false) }
                }
            }
        }
    }

    fun playActiveFeedVideoIfAvailable() {
        val st = _state.value
        if (st.modalPlayer.isOpen) return
        playAtChannelIndex(st.activeChannel.currentIndex)
    }

    private fun playAtChannelIndex(index: Int) {
        val ch = _state.value.activeChannel
        val active = ch.videos.getOrNull(index) ?: return
        val upcoming = if (index + 1 < ch.videos.size) ch.videos.subList(index + 1, ch.videos.size) else emptyList()
        val tier = when (networkQualityProvider()) {
            NetworkQuality.OFFLINE -> FeedPreloadTier.OFFLINE
            NetworkQuality.ONLINE -> FeedPreloadTier.WIFI_NORMAL
        }
        playerController.playVideo(active, upcoming, tier)
        scope.launch {
            val isInitial = recordedInitialViews.add(active.videoId)
            if (isInitial && networkQualityProvider() == NetworkQuality.ONLINE) {
                feedRepository.recordViewOrProgress(active.videoId, 0L, 0L, 0.0, 0, isInitialView = true)
            }
        }
    }

    fun retryActiveVideo() {
        val active = _state.value.activeChannel.videos.getOrNull(_state.value.activeChannel.currentIndex)
        if (active != null) {
            playerController.retryActive(active)
        } else {
            refreshActiveFeed()
        }
    }

    fun onDoubleTapLike(video: FeedVideoDto) {
        if (!video.isLiked) {
            toggleLike(video)
        }
    }

    fun toggleLike(video: FeedVideoDto) {
        val nextLiked = !video.isLiked
        val delta = if (nextLiked) 1L else -1L
        updateVideoEverywhere(video.videoId) { v ->
            v.copy(isLiked = nextLiked, likesCount = (v.likesCount + delta).coerceAtLeast(0L))
        }
        scope.launch {
            when (val res = feedRepository.setVideoLike(video.videoId, nextLiked)) {
                is RepoResult.Success -> {
                    updateVideoEverywhere(video.videoId) { v ->
                        v.copy(isLiked = res.data.isLiked, likesCount = res.data.likesCount)
                    }
                }
                is RepoResult.Failure -> {
                    updateVideoEverywhere(video.videoId) { v ->
                        v.copy(isLiked = video.isLiked, likesCount = video.likesCount)
                    }
                    showToast(res.userMessage)
                }
            }
        }
    }

    fun toggleSave(video: FeedVideoDto) {
        val nextSaved = !video.isSaved
        val delta = if (nextSaved) 1L else -1L
        updateVideoEverywhere(video.videoId) { v ->
            v.copy(isSaved = nextSaved, savesCount = (v.savesCount + delta).coerceAtLeast(0L))
        }
        scope.launch {
            when (val res = feedRepository.setVideoSave(video.videoId, nextSaved)) {
                is RepoResult.Success -> {
                    updateVideoEverywhere(video.videoId) { v ->
                        v.copy(isSaved = res.data.isSaved, savesCount = res.data.savesCount)
                    }
                    refreshSavedVideos()
                }
                is RepoResult.Failure -> {
                    updateVideoEverywhere(video.videoId) { v ->
                        v.copy(isSaved = video.isSaved, savesCount = video.savesCount)
                    }
                    showToast(res.userMessage)
                }
            }
        }
    }

    fun recordShare(video: FeedVideoDto, channel: String) {
        updateVideoEverywhere(video.videoId) { it.copy(sharesCount = it.sharesCount + 1L) }
        scope.launch {
            when (val res = feedRepository.recordVideoShare(video.videoId, channel)) {
                is RepoResult.Success -> {
                    updateVideoEverywhere(video.videoId) { it.copy(sharesCount = res.data.sharesCount) }
                }
                is RepoResult.Failure -> Unit
            }
        }
    }

    fun toggleFollowCreator(video: FeedVideoDto) {
        if (video.isOwner || video.creatorId.isBlank()) return
        val nextFollow = !video.isFollowingCreator
        updateCreatorFollowEverywhere(video.creatorId, nextFollow)
        scope.launch {
            when (val res = feedRepository.setCreatorFollow(video.creatorId, nextFollow, networkQualityProvider())) {
                is RepoResult.Success -> {
                    updateCreatorFollowEverywhere(video.creatorId, res.data.isFollowing)
                    onContactsChanged()
                }
                is RepoResult.Failure -> {
                    updateCreatorFollowEverywhere(video.creatorId, video.isFollowingCreator)
                    showToast(res.userMessage)
                }
            }
        }
    }

    fun toggleRepost(video: FeedVideoDto) {
        val nextRepost = !video.isReposted
        val delta = if (nextRepost) 1L else -1L
        updateVideoEverywhere(video.videoId) { v ->
            v.copy(isReposted = nextRepost, repostsCount = (v.repostsCount + delta).coerceAtLeast(0L))
        }
        _state.update { it.copy(optionsMenuVideo = null) }
        scope.launch {
            when (val res = feedRepository.setVideoRepost(video.videoId, nextRepost)) {
                is RepoResult.Success -> {
                    updateVideoEverywhere(video.videoId) { v ->
                        v.copy(isReposted = res.data.isReposted, repostsCount = res.data.repostsCount)
                    }
                    if (res.data.isReposted) showToast("Reposted")
                }
                is RepoResult.Failure -> {
                    updateVideoEverywhere(video.videoId) { v ->
                        v.copy(isReposted = video.isReposted, repostsCount = video.repostsCount)
                    }
                    showToast(res.userMessage)
                }
            }
        }
    }

    fun markNotInterested(video: FeedVideoDto) {
        _state.update { it.copy(optionsMenuVideo = null) }
        removeVideoEverywhere(video.videoId)
        scope.launch {
            feedRepository.markNotInterested(video.videoId)
        }
    }

    fun openComments(video: FeedVideoDto) {
        _state.update { it.copy(commentsVideo = video) }
    }

    fun closeComments() {
        _state.update { it.copy(commentsVideo = null) }
    }

    fun openOptionsMenu(video: FeedVideoDto) {
        _state.update { it.copy(optionsMenuVideo = video) }
    }

    fun closeOptionsMenu() {
        _state.update { it.copy(optionsMenuVideo = null) }
    }

    fun startReport(video: FeedVideoDto) {
        _state.update {
            it.copy(
                optionsMenuVideo = null,
                reportSheet = ReportSheetState(video = video, step = 1)
            )
        }
    }

    fun selectReportReason(reason: FeedReportReason) {
        _state.update {
            it.copy(reportSheet = it.reportSheet.copy(selectedReason = reason, step = 2))
        }
    }

    fun updateReportDetails(details: String) {
        _state.update {
            it.copy(reportSheet = it.reportSheet.copy(details = details.take(400)))
        }
    }

    fun backReportStep() {
        _state.update {
            it.copy(reportSheet = it.reportSheet.copy(step = 1))
        }
    }

    fun closeReportSheet() {
        _state.update { it.copy(reportSheet = ReportSheetState()) }
    }

    fun submitReport() {
        val rs = _state.value.reportSheet
        val vid = rs.video ?: return
        val reason = rs.selectedReason ?: return
        scope.launch {
            _state.update { it.copy(reportSheet = it.reportSheet.copy(isSubmitting = true)) }
            when (val res = feedRepository.reportVideo(vid.videoId, reason.apiValue, rs.details.trim())) {
                is RepoResult.Success -> {
                    _state.update { it.copy(reportSheet = ReportSheetState(), toastMessage = "Report submitted") }
                }
                is RepoResult.Failure -> {
                    _state.update {
                        it.copy(reportSheet = it.reportSheet.copy(isSubmitting = false), toastMessage = res.userMessage)
                    }
                }
            }
        }
    }

    fun requestBlockUser(video: FeedVideoDto) {
        _state.update { it.copy(optionsMenuVideo = null, confirmBlockVideo = video) }
    }

    fun dismissBlockDialog() {
        _state.update { it.copy(confirmBlockVideo = null) }
    }

    fun confirmBlockUser() {
        val vid = _state.value.confirmBlockVideo ?: return
        _state.update { it.copy(confirmBlockVideo = null) }
        removeCreatorEverywhere(vid.creatorId)
        scope.launch {
            when (val res = feedRepository.setUserBlocked(vid.creatorId, true)) {
                is RepoResult.Success -> {
                    showToast("User blocked")
                    refreshSafetyPreferences()
                }
                is RepoResult.Failure -> showToast(res.userMessage)
            }
        }
    }

    fun muteUserFromVideo(video: FeedVideoDto) {
        _state.update { it.copy(optionsMenuVideo = null) }
        removeCreatorEverywhere(video.creatorId)
        scope.launch {
            when (val res = feedRepository.setUserMuted(video.creatorId, true)) {
                is RepoResult.Success -> {
                    showToast("User muted")
                    refreshSafetyPreferences()
                }
                is RepoResult.Failure -> showToast(res.userMessage)
            }
        }
    }

    fun unmuteUser(userId: String) {
        scope.launch {
            if (feedRepository.setUserMuted(userId, false) is RepoResult.Success) {
                refreshSafetyPreferences()
                refreshActiveFeed()
            }
        }
    }

    fun unblockUser(userId: String) {
        scope.launch {
            if (feedRepository.setUserBlocked(userId, false) is RepoResult.Success) {
                refreshSafetyPreferences()
                refreshActiveFeed()
            }
        }
    }

    fun openOwnerEditSheet(video: FeedVideoDto) {
        _state.update {
            it.copy(
                optionsMenuVideo = null,
                ownerEditSheet = OwnerEditSheetState(
                    video = video,
                    title = video.title,
                    description = video.description,
                    visibility = video.visibility
                )
            )
        }
    }

    fun updateOwnerEditFields(title: String? = null, description: String? = null) {
        _state.update {
            it.copy(
                ownerEditSheet = it.ownerEditSheet.copy(
                    title = title ?: it.ownerEditSheet.title,
                    description = description ?: it.ownerEditSheet.description
                )
            )
        }
    }

    fun closeOwnerEditSheet() {
        _state.update { it.copy(ownerEditSheet = OwnerEditSheetState()) }
    }

    fun saveOwnerEditDetails() {
        val es = _state.value.ownerEditSheet
        val vid = es.video ?: return
        scope.launch {
            _state.update { it.copy(ownerEditSheet = it.ownerEditSheet.copy(isSaving = true)) }
            when (val res = feedRepository.updateOwnerVideo(
                videoId = vid.videoId,
                title = es.title.trim(),
                description = es.description.trim(),
                visibility = null
            )) {
                is RepoResult.Success -> {
                    updateVideoEverywhere(vid.videoId) { res.data }
                    _state.update { it.copy(ownerEditSheet = OwnerEditSheetState()) }
                }
                is RepoResult.Failure -> {
                    _state.update {
                        it.copy(ownerEditSheet = it.ownerEditSheet.copy(isSaving = false), toastMessage = res.userMessage)
                    }
                }
            }
        }
    }

    fun markVideoAsPrivate(video: FeedVideoDto) {
        _state.update { it.copy(optionsMenuVideo = null) }
        updateVideoVisibility(video, "private")
    }

    fun openVisibilitySheet(video: FeedVideoDto) {
        _state.update { it.copy(optionsMenuVideo = null, ownerVisibilityVideo = video) }
    }

    fun closeVisibilitySheet() {
        _state.update { it.copy(ownerVisibilityVideo = null) }
    }

    fun updateVideoVisibility(video: FeedVideoDto, visibility: String) {
        _state.update { it.copy(ownerVisibilityVideo = null) }
        scope.launch {
            when (val res = feedRepository.updateOwnerVideo(video.videoId, null, null, visibility)) {
                is RepoResult.Success -> {
                    updateVideoEverywhere(video.videoId) { res.data }
                }
                is RepoResult.Failure -> showToast(res.userMessage)
            }
        }
    }

    fun requestDeleteVideo(video: FeedVideoDto) {
        _state.update { it.copy(optionsMenuVideo = null, confirmDeleteVideo = video) }
    }

    fun dismissDeleteDialog() {
        _state.update { it.copy(confirmDeleteVideo = null) }
    }

    fun confirmDeleteVideo() {
        val vid = _state.value.confirmDeleteVideo ?: return
        _state.update { it.copy(confirmDeleteVideo = null) }
        removeVideoEverywhere(vid.videoId)
        scope.launch {
            when (val res = feedRepository.deleteOwnerVideo(vid.videoId)) {
                is RepoResult.Success -> Unit
                is RepoResult.Failure -> showToast(res.userMessage)
            }
        }
    }

    fun openLiveScreen() {
        playerController.pause()
        _state.update { it.copy(isLiveScreenOpen = true) }
    }

    fun closeLiveScreen() {
        _state.update { it.copy(isLiveScreenOpen = false) }
    }

    fun openSearch() {
        playerController.pause()
        _state.update { it.copy(search = it.search.copy(isOpen = true, errorMessage = null)) }
        executeSearch(_state.value.search.query, reset = true)
    }

    fun closeSearch() {
        playerController.releaseAllPreviews()
        _state.update { it.copy(search = FeedSearchState()) }
    }

    fun selectSearchTab(tab: FeedSearchTab) {
        _state.update { it.copy(search = it.search.copy(activeTab = tab)) }
    }

    fun updateSearchQuery(query: String) {
        _state.update { it.copy(search = it.search.copy(query = query)) }
        searchDebounceJob?.cancel()
        searchDebounceJob = scope.launch {
            delay(280L)
            executeSearch(query, reset = true)
        }
    }

    fun submitSearch(query: String) {
        _state.update { it.copy(search = it.search.copy(query = query)) }
        executeSearch(query, reset = true)
    }

    fun loadMoreSearchResults() {
        val st = _state.value.search
        if (st.isLoading || !st.hasMore || st.nextCursor.isBlank()) return
        executeSearch(st.query, reset = false)
    }

    private fun executeSearch(query: String, reset: Boolean) {
        scope.launch {
            val cursor = if (reset) "" else _state.value.search.nextCursor
            _state.update { it.copy(search = it.search.copy(isLoading = true, errorMessage = null)) }
            when (val res = feedRepository.searchAll(query, cursor)) {
                is RepoResult.Success -> {
                    val body = res.data
                    _state.update { st ->
                        val prev = st.search
                        val mergedVideos = if (reset) body.videos else {
                            val ids = prev.videos.mapTo(HashSet()) { it.videoId }
                            prev.videos + body.videos.filterNot { ids.contains(it.videoId) }
                        }
                        prev.let {
                            st.copy(
                                search = it.copy(
                                    videos = mergedVideos,
                                    hashtags = if (reset) body.hashtags else it.hashtags,
                                    creators = if (reset) body.creators else it.creators,
                                    audios = if (reset) body.audios else it.audios,
                                    recentSearches = body.recentSearches,
                                    trending = body.trending,
                                    nextCursor = body.nextCursor,
                                    hasMore = body.hasMore,
                                    isLoading = false,
                                    errorMessage = null
                                )
                            )
                        }
                    }
                }
                is RepoResult.Failure -> {
                    _state.update {
                        it.copy(search = it.search.copy(isLoading = false, errorMessage = res.userMessage))
                    }
                }
            }
        }
    }

    fun deleteRecentSearch(id: String) {
        _state.update {
            it.copy(search = it.search.copy(recentSearches = it.search.recentSearches.filterNot { item -> item.id == id }))
        }
        scope.launch { feedRepository.deleteSearchHistoryItem(id) }
    }

    fun clearRecentSearches() {
        _state.update { it.copy(search = it.search.copy(recentSearches = emptyList())) }
        scope.launch { feedRepository.clearSearchHistory() }
    }

    fun openHashtagDiscovery(tag: String) {
        val clean = tag.trim().removePrefix("#").lowercase()
        if (clean.isBlank()) return
        playerController.pause()
        _state.update {
            it.copy(
                hashtagDiscovery = HashtagDiscoveryState(
                    isOpen = true,
                    tag = clean,
                    isLoading = true
                )
            )
        }
        scope.launch {
            when (val res = feedRepository.fetchHashtagDiscovery(clean)) {
                is RepoResult.Success -> {
                    _state.update {
                        it.copy(
                            hashtagDiscovery = HashtagDiscoveryState(
                                isOpen = true,
                                tag = res.data.tag,
                                videoCount = res.data.videoCount,
                                viewsCount = res.data.viewsCount,
                                videos = res.data.videos,
                                nextCursor = res.data.nextCursor,
                                hasMore = res.data.hasMore,
                                isLoading = false
                            )
                        )
                    }
                }
                is RepoResult.Failure -> {
                    _state.update {
                        it.copy(
                            hashtagDiscovery = it.hashtagDiscovery.copy(
                                isLoading = false,
                                errorMessage = res.userMessage
                            )
                        )
                    }
                }
            }
        }
    }

    fun loadMoreHashtagVideos() {
        val hd = _state.value.hashtagDiscovery
        if (hd.isLoading || !hd.hasMore || hd.nextCursor.isBlank()) return
        scope.launch {
            _state.update { it.copy(hashtagDiscovery = it.hashtagDiscovery.copy(isLoading = true)) }
            when (val res = feedRepository.fetchHashtagDiscovery(hd.tag, hd.nextCursor)) {
                is RepoResult.Success -> {
                    _state.update { st ->
                        val ids = st.hashtagDiscovery.videos.mapTo(HashSet()) { it.videoId }
                        st.copy(
                            hashtagDiscovery = st.hashtagDiscovery.copy(
                                videos = st.hashtagDiscovery.videos + res.data.videos.filterNot { ids.contains(it.videoId) },
                                nextCursor = res.data.nextCursor,
                                hasMore = res.data.hasMore,
                                isLoading = false
                            )
                        )
                    }
                }
                is RepoResult.Failure -> {
                    _state.update { it.copy(hashtagDiscovery = it.hashtagDiscovery.copy(isLoading = false)) }
                }
            }
        }
    }

    fun closeHashtagDiscovery() {
        playerController.releaseAllPreviews()
        _state.update { it.copy(hashtagDiscovery = HashtagDiscoveryState()) }
    }

    fun openAudioDiscovery(audioId: String, seedAudio: AudioSummaryDto? = null) {
        if (audioId.isBlank()) return
        playerController.pause()
        _state.update {
            it.copy(
                audioDiscovery = AudioDiscoveryState(
                    isOpen = true,
                    audioId = audioId,
                    audio = seedAudio,
                    isLoading = true
                )
            )
        }
        scope.launch {
            when (val res = feedRepository.fetchAudioDiscovery(audioId)) {
                is RepoResult.Success -> {
                    _state.update {
                        it.copy(
                            audioDiscovery = AudioDiscoveryState(
                                isOpen = true,
                                audioId = audioId,
                                audio = res.data.audio,
                                videos = res.data.videos,
                                nextCursor = res.data.nextCursor,
                                hasMore = res.data.hasMore,
                                isLoading = false
                            )
                        )
                    }
                }
                is RepoResult.Failure -> {
                    _state.update {
                        it.copy(
                            audioDiscovery = it.audioDiscovery.copy(
                                isLoading = false,
                                errorMessage = res.userMessage
                            )
                        )
                    }
                }
            }
        }
    }

    fun closeAudioDiscovery() {
        playerController.releaseAllPreviews()
        _state.update { it.copy(audioDiscovery = AudioDiscoveryState()) }
    }

    fun useDiscoveredAudio() {
        val audio = _state.value.audioDiscovery.audio ?: return
        closeAudioDiscovery()
        closeSearch()
        closeHashtagDiscovery()
        onUseAudioInPost(audio)
    }

    fun openModalFeedPlayer(title: String, videos: List<FeedVideoDto>, index: Int) {
        if (videos.isEmpty()) return
        playerController.releaseAllPreviews()
        val safeIdx = index.coerceIn(0, videos.size - 1)
        _state.update {
            it.copy(modalPlayer = ModalFeedPlayerState(isOpen = true, title = title, videos = videos, initialIndex = safeIdx))
        }
        val active = videos[safeIdx]
        val upcoming = if (safeIdx + 1 < videos.size) videos.subList(safeIdx + 1, videos.size) else emptyList()
        playerController.playVideo(active, upcoming, FeedPreloadTier.WIFI_NORMAL)
    }

    fun onModalPlayerSettled(index: Int) {
        val mp = _state.value.modalPlayer
        val active = mp.videos.getOrNull(index) ?: return
        val upcoming = if (index + 1 < mp.videos.size) mp.videos.subList(index + 1, mp.videos.size) else emptyList()
        playerController.playVideo(active, upcoming, FeedPreloadTier.WIFI_NORMAL)
    }

    fun closeModalFeedPlayer() {
        playerController.pause()
        _state.update { it.copy(modalPlayer = ModalFeedPlayerState()) }
    }

    fun refreshSavedVideos() {
        if (networkQualityProvider() == NetworkQuality.OFFLINE) return
        scope.launch {
            _state.update {
                it.copy(profileSavedAndSafety = it.profileSavedAndSafety.copy(isLoadingSaved = true))
            }
            when (val res = feedRepository.fetchSavedVideos()) {
                is RepoResult.Success -> {
                    _state.update {
                        it.copy(
                            profileSavedAndSafety = it.profileSavedAndSafety.copy(
                                savedVideos = res.data.videos,
                                isLoadingSaved = false
                            )
                        )
                    }
                }
                is RepoResult.Failure -> {
                    _state.update {
                        it.copy(profileSavedAndSafety = it.profileSavedAndSafety.copy(isLoadingSaved = false))
                    }
                }
            }
        }
    }

    fun refreshSafetyPreferences() {
        if (networkQualityProvider() == NetworkQuality.OFFLINE) return
        scope.launch {
            _state.update {
                it.copy(profileSavedAndSafety = it.profileSavedAndSafety.copy(isLoadingSafety = true))
            }
            when (val res = feedRepository.fetchSafetyPreferences()) {
                is RepoResult.Success -> {
                    _state.update {
                        it.copy(
                            profileSavedAndSafety = it.profileSavedAndSafety.copy(
                                mutedUsers = res.data.mutedUsers,
                                blockedUsers = res.data.blockedUsers,
                                isLoadingSafety = false
                            )
                        )
                    }
                }
                is RepoResult.Failure -> {
                    _state.update {
                        it.copy(profileSavedAndSafety = it.profileSavedAndSafety.copy(isLoadingSafety = false))
                    }
                }
            }
        }
    }

    fun toggleCreatorFollowById(userId: String, currentlyFollowing: Boolean) {
        val next = !currentlyFollowing
        updateCreatorFollowEverywhere(userId, next)
        _state.update { st ->
            st.copy(
                search = st.search.copy(
                    creators = st.search.creators.map { c ->
                        if (c.userId == userId) c.copy(isFollowing = next) else c
                    }
                )
            )
        }
        scope.launch {
            when (val res = feedRepository.setCreatorFollow(userId, next, networkQualityProvider())) {
                is RepoResult.Success -> {
                    updateCreatorFollowEverywhere(userId, res.data.isFollowing)
                    _state.update { st ->
                        st.copy(
                            search = st.search.copy(
                                creators = st.search.creators.map { c ->
                                    if (c.userId == userId) c.copy(isFollowing = res.data.isFollowing) else c
                                }
                            )
                        )
                    }
                    onContactsChanged()
                }
                is RepoResult.Failure -> {
                    updateCreatorFollowEverywhere(userId, currentlyFollowing)
                    showToast(res.userMessage)
                }
            }
        }
    }

    fun clearToast() {
        _state.update { it.copy(toastMessage = null) }
    }

    private fun showToast(msg: String) {
        _state.update { it.copy(toastMessage = msg) }
    }

    fun resetOnSignOut() {
        playerController.pause()
        playerController.releaseAllPreviews()
        recordedInitialViews.clear()
        _state.value = VideoFeedUiState()
    }

    private fun updateChannel(tab: FeedTab, transform: (FeedChannelState) -> FeedChannelState) {
        _state.update { st ->
            when (tab) {
                FeedTab.FOR_YOU -> st.copy(forYou = transform(st.forYou))
                FeedTab.FOLLOWING -> st.copy(following = transform(st.following))
            }
        }
    }

    private fun updateVideoEverywhere(videoId: String, transform: (FeedVideoDto) -> FeedVideoDto) {
        _state.update { st ->
            fun mapList(list: List<FeedVideoDto>) = list.map { if (it.videoId == videoId) transform(it) else it }
            st.copy(
                forYou = st.forYou.copy(videos = mapList(st.forYou.videos)),
                following = st.following.copy(videos = mapList(st.following.videos)),
                search = st.search.copy(videos = mapList(st.search.videos)),
                hashtagDiscovery = st.hashtagDiscovery.copy(videos = mapList(st.hashtagDiscovery.videos)),
                audioDiscovery = st.audioDiscovery.copy(videos = mapList(st.audioDiscovery.videos)),
                modalPlayer = st.modalPlayer.copy(videos = mapList(st.modalPlayer.videos)),
                profileSavedAndSafety = st.profileSavedAndSafety.copy(
                    savedVideos = mapList(st.profileSavedAndSafety.savedVideos)
                )
            )
        }
    }

    private fun updateCreatorFollowEverywhere(creatorId: String, following: Boolean) {
        _state.update { st ->
            fun mapList(list: List<FeedVideoDto>) =
                list.map { if (it.creatorId == creatorId) it.copy(isFollowingCreator = following) else it }
            st.copy(
                forYou = st.forYou.copy(videos = mapList(st.forYou.videos)),
                following = st.following.copy(videos = mapList(st.following.videos)),
                search = st.search.copy(videos = mapList(st.search.videos)),
                hashtagDiscovery = st.hashtagDiscovery.copy(videos = mapList(st.hashtagDiscovery.videos)),
                audioDiscovery = st.audioDiscovery.copy(videos = mapList(st.audioDiscovery.videos)),
                modalPlayer = st.modalPlayer.copy(videos = mapList(st.modalPlayer.videos))
            )
        }
    }

    private fun removeVideoEverywhere(videoId: String) {
        _state.update { st ->
            fun filterList(list: List<FeedVideoDto>) = list.filterNot { it.videoId == videoId }
            val nextFy = filterList(st.forYou.videos)
            val nextFo = filterList(st.following.videos)
            val nextModal = filterList(st.modalPlayer.videos)
            st.copy(
                forYou = st.forYou.copy(
                    videos = nextFy,
                    currentIndex = st.forYou.currentIndex.coerceIn(0, (nextFy.size - 1).coerceAtLeast(0))
                ),
                following = st.following.copy(
                    videos = nextFo,
                    currentIndex = st.following.currentIndex.coerceIn(0, (nextFo.size - 1).coerceAtLeast(0))
                ),
                search = st.search.copy(videos = filterList(st.search.videos)),
                hashtagDiscovery = st.hashtagDiscovery.copy(videos = filterList(st.hashtagDiscovery.videos)),
                audioDiscovery = st.audioDiscovery.copy(videos = filterList(st.audioDiscovery.videos)),
                modalPlayer = st.modalPlayer.copy(
                    videos = nextModal,
                    isOpen = st.modalPlayer.isOpen && nextModal.isNotEmpty()
                ),
                profileSavedAndSafety = st.profileSavedAndSafety.copy(
                    savedVideos = filterList(st.profileSavedAndSafety.savedVideos)
                )
            )
        }
    }

    private fun removeCreatorEverywhere(creatorId: String) {
        _state.update { st ->
            fun filterList(list: List<FeedVideoDto>) = list.filterNot { it.creatorId == creatorId }
            val nextFy = filterList(st.forYou.videos)
            val nextFo = filterList(st.following.videos)
            st.copy(
                forYou = st.forYou.copy(
                    videos = nextFy,
                    currentIndex = st.forYou.currentIndex.coerceIn(0, (nextFy.size - 1).coerceAtLeast(0))
                ),
                following = st.following.copy(
                    videos = nextFo,
                    currentIndex = st.following.currentIndex.coerceIn(0, (nextFo.size - 1).coerceAtLeast(0))
                ),
                search = st.search.copy(videos = filterList(st.search.videos)),
                hashtagDiscovery = st.hashtagDiscovery.copy(videos = filterList(st.hashtagDiscovery.videos)),
                audioDiscovery = st.audioDiscovery.copy(videos = filterList(st.audioDiscovery.videos))
            )
        }
    }
}
