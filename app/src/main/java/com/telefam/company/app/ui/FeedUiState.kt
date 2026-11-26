package com.telefam.company.app.ui

import com.telefam.company.app.feed.FeedReportReason
import com.telefam.company.app.feed.FeedTab
import com.telefam.company.app.network.AudioSummaryDto
import com.telefam.company.app.network.CreatorSearchDto
import com.telefam.company.app.network.FeedVideoDto
import com.telefam.company.app.network.HashtagDto
import com.telefam.company.app.network.RecentSearchDto
import com.telefam.company.app.network.SafetyUserDto

enum class FeedSearchTab {
    VIDEOS,
    HASHTAGS,
    CREATORS,
    SOUNDS
}

data class ReportSheetState(
    val video: FeedVideoDto? = null,
    val step: Int = 1,
    val selectedReason: FeedReportReason? = null,
    val details: String = "",
    val isSubmitting: Boolean = false
)

data class OwnerEditSheetState(
    val video: FeedVideoDto? = null,
    val title: String = "",
    val description: String = "",
    val visibility: String = "public",
    val isSaving: Boolean = false
)

data class FeedChannelState(
    val videos: List<FeedVideoDto> = emptyList(),
    val nextCursor: String = "",
    val hasMore: Boolean = false,
    val isInitialLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val errorMessage: String? = null,
    val currentIndex: Int = 0
)

data class HashtagDiscoveryState(
    val isOpen: Boolean = false,
    val tag: String = "",
    val videoCount: Long = 0L,
    val viewsCount: Long = 0L,
    val videos: List<FeedVideoDto> = emptyList(),
    val nextCursor: String = "",
    val hasMore: Boolean = false,
    val isLoading: Boolean = false,
    val errorMessage: String? = null
)

data class AudioDiscoveryState(
    val isOpen: Boolean = false,
    val audioId: String = "",
    val audio: AudioSummaryDto? = null,
    val videos: List<FeedVideoDto> = emptyList(),
    val nextCursor: String = "",
    val hasMore: Boolean = false,
    val isLoading: Boolean = false,
    val errorMessage: String? = null
)

data class FeedSearchState(
    val isOpen: Boolean = false,
    val query: String = "",
    val activeTab: FeedSearchTab = FeedSearchTab.VIDEOS,
    val videos: List<FeedVideoDto> = emptyList(),
    val hashtags: List<HashtagDto> = emptyList(),
    val creators: List<CreatorSearchDto> = emptyList(),
    val audios: List<AudioSummaryDto> = emptyList(),
    val recentSearches: List<RecentSearchDto> = emptyList(),
    val trending: List<String> = emptyList(),
    val nextCursor: String = "",
    val hasMore: Boolean = false,
    val isLoading: Boolean = false,
    val errorMessage: String? = null
)

data class ModalFeedPlayerState(
    val isOpen: Boolean = false,
    val title: String = "",
    val videos: List<FeedVideoDto> = emptyList(),
    val initialIndex: Int = 0
)

data class ProfileSavedAndSafetyState(
    val savedVideos: List<FeedVideoDto> = emptyList(),
    val isLoadingSaved: Boolean = false,
    val mutedUsers: List<SafetyUserDto> = emptyList(),
    val blockedUsers: List<SafetyUserDto> = emptyList(),
    val isLoadingSafety: Boolean = false
)

data class VideoFeedUiState(
    val selectedTab: FeedTab = FeedTab.FOR_YOU,
    val forYou: FeedChannelState = FeedChannelState(),
    val following: FeedChannelState = FeedChannelState(),
    val isLiveScreenOpen: Boolean = false,
    val search: FeedSearchState = FeedSearchState(),
    val hashtagDiscovery: HashtagDiscoveryState = HashtagDiscoveryState(),
    val audioDiscovery: AudioDiscoveryState = AudioDiscoveryState(),
    val modalPlayer: ModalFeedPlayerState = ModalFeedPlayerState(),
    val reportSheet: ReportSheetState = ReportSheetState(),
    val ownerEditSheet: OwnerEditSheetState = OwnerEditSheetState(),
    val commentsVideo: FeedVideoDto? = null,
    val optionsMenuVideo: FeedVideoDto? = null,
    val ownerVisibilityVideo: FeedVideoDto? = null,
    val confirmBlockVideo: FeedVideoDto? = null,
    val confirmDeleteVideo: FeedVideoDto? = null,
    val toastMessage: String? = null,
    val profileSavedAndSafety: ProfileSavedAndSafetyState = ProfileSavedAndSafetyState()
) {
    val activeChannel: FeedChannelState
        get() = if (selectedTab == FeedTab.FOR_YOU) forYou else following
}
