package com.telefam.company.app.ui

import android.graphics.Bitmap
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.telefam.company.app.core.NetworkQuality
import com.telefam.company.app.data.ContactModel
import com.telefam.company.app.data.ConversationModel
import com.telefam.company.app.data.ExtractedPhotoItem
import com.telefam.company.app.data.FeedRepository
import com.telefam.company.app.data.MessageModel
import com.telefam.company.app.data.QueuedPostPayload
import com.telefam.company.app.data.RepoResult
import com.telefam.company.app.data.TelefamRepository
import com.telefam.company.app.data.VideoFrameItem
import com.telefam.company.app.feed.FeedPlaybackState
import com.telefam.company.app.feed.FeedPlayerController
import com.telefam.company.app.network.AndroidNetworkMonitor
import com.telefam.company.app.network.AudioSummaryDto
import com.telefam.company.app.network.AuthSessionDto
import com.telefam.company.app.network.FeedPostDto
import com.telefam.company.app.network.HashtagDto
import com.telefam.company.app.network.MusicTrackDto
import com.telefam.company.app.network.MyProfileDto
import com.telefam.company.app.network.NotificationDto
import com.telefam.company.app.network.OtherUserProfileDto
import com.telefam.company.app.network.OwnerProfileItemDto
import com.telefam.company.app.network.ProfileSetupRequest
import com.telefam.company.app.ui.theme.PostFontStyle
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream
import java.util.Calendar
import java.util.UUID

enum class AuthStep {
    ENTER_EMAIL,
    ENTER_OTP
}

enum class HomeTab {
    CHATS,
    CONTACTS,
    FEEDS,
    PROFILE
}

enum class ContactFilter(val apiValue: String) {
    ALL("all"),
    SUGGESTIONS("suggestions"),
    FOLLOWERS("followers"),
    FOLLOWING("following"),
    FRIENDS("friends")
}

data class CountryCodeOption(
    val iso: String,
    val dialCode: String,
    val flag: String,
    val name: String
)

val SUPPORTED_COUNTRIES = listOf(
    CountryCodeOption("KE", "+254", "\uD83C\uDDF0\uD83C\uDDEA", "Kenya"),
    CountryCodeOption("US", "+1", "\uD83C\uDDFA\uD83C\uDDF8", "United States"),
    CountryCodeOption("GB", "+44", "\uD83C\uDDEC\uD83C\uDDE7", "United Kingdom"),
    CountryCodeOption("CA", "+1", "\uD83C\uDDE8\uD83C\uDDE6", "Canada"),
    CountryCodeOption("NG", "+234", "\uD83C\uDDF3\uD83C\uDDEC", "Nigeria"),
    CountryCodeOption("ZA", "+27", "\uD83C\uDDFF\uD83C\uDDE6", "South Africa"),
    CountryCodeOption("TZ", "+255", "\uD83C\uDDF9\uD83C\uDDFF", "Tanzania"),
    CountryCodeOption("UG", "+256", "\uD83C\uDDFA\uD83C\uDDEC", "Uganda"),
    CountryCodeOption("RW", "+250", "\uD83C\uDDF7\uD83C\uDDFC", "Rwanda"),
    CountryCodeOption("ET", "+251", "\uD83C\uDDEA\uD83C\uDDF9", "Ethiopia"),
    CountryCodeOption("IN", "+91", "\uD83C\uDDEE\uD83C\uDDF3", "India"),
    CountryCodeOption("DE", "+49", "\uD83C\uDDE9\uD83C\uDDEA", "Germany"),
    CountryCodeOption("FR", "+33", "\uD83C\uDDEB\uD83C\uDDF7", "France"),
    CountryCodeOption("AE", "+971", "\uD83C\uDDE6\uD83C\uDDEA", "UAE"),
    CountryCodeOption("AU", "+61", "\uD83C\uDDE6\uD83C\uDDFA", "Australia"),
    CountryCodeOption("JP", "+81", "\uD83C\uDDEF\uD83C\uDDF5", "Japan"),
    CountryCodeOption("BR", "+55", "\uD83C\uDDE7\uD83C\uDDF7", "Brazil")
)

data class ProfileSetupState(
    val fullName: String = "",
    val username: String = "",
    val countryIso: String = "KE",
    val phoneNumber: String = "",
    val gender: String = "",
    val birthYear: Int? = null,
    val birthMonth: Int? = null,
    val birthDay: Int? = null,
    val location: String = "",
    val bio: String = "",
    val avatarBitmap: Bitmap? = null,
    val avatarFingerprintHash: String = "",
    val errorMessage: String? = null,
    val isSubmitting: Boolean = false
)

enum class PostTabMode(val apiValue: String) {
    TEXT("text"),
    PHOTOS("photos"),
    VIDEO("video")
}

enum class PostUploadStatus {
    IDLE,
    UPLOADING,
    UPLOADED,
    QUEUED,
    ERROR
}

data class PostComposerState(
    val isOpen: Boolean = false,
    val mode: PostTabMode = PostTabMode.TEXT,
    val textBody: String = "",
    val selectedBgColorHex: String = "#C81010",
    val selectedImageThemeId: String? = null,
    val showImageThemes: Boolean = false,
    val selectedFont: PostFontStyle = PostFontStyle.CLASSIC,
    val selectedPhotos: List<ExtractedPhotoItem> = emptyList(),
    val videoUri: Uri? = null,
    val videoSizeBytes: Long = 0L,
    val videoDurationMs: Long = 0L,
    val videoFrames: List<VideoFrameItem> = emptyList(),
    val trimStartMs: Long = 0L,
    val trimEndMs: Long = 0L,
    val selectedThumbTimestampMs: Long = 0L,
    val selectedThumbBitmap: Bitmap? = null,
    val muteOriginalAudio: Boolean = false,
    val caption: String = "",
    val selectedSong: MusicTrackDto? = null,
    val isPlayingSongPreview: Boolean = false,
    val previewingTrackId: String? = null,
    val songQuery: String = "",
    val songResults: List<MusicTrackDto> = emptyList(),
    val isSearchingSongs: Boolean = false,
    val taggedContacts: List<ContactModel> = emptyList(),
    val selectedHashtags: List<String> = emptyList(),
    val hashtagQuery: String = "",
    val hashtagResults: List<HashtagDto> = emptyList(),
    val isSearchingHashtags: Boolean = false,
    val isExtractingMedia: Boolean = false,
    val uploadStatus: PostUploadStatus = PostUploadStatus.IDLE,
    val uploadProgress: Int = 0,
    val inlineError: String? = null
) {
    val canShare: Boolean
        get() = when (mode) {
            PostTabMode.TEXT -> textBody.trim().isNotEmpty()
            PostTabMode.PHOTOS -> selectedPhotos.isNotEmpty()
            PostTabMode.VIDEO -> videoUri != null && inlineError == null
        } && uploadStatus != PostUploadStatus.UPLOADING
}

enum class OwnerProfileTab(val apiValue: String) {
    POSTS("posts"),
    REPOSTS("reposts"),
    LOCKED("locked"),
    SAVED("saved")
}

data class OwnerProfileUiState(
    val activeCategory: OwnerProfileTab = OwnerProfileTab.POSTS,
    val itemsByCategory: Map<OwnerProfileTab, List<OwnerProfileItemDto>> = emptyMap(),
    val isLoadingItems: Boolean = false,
    val isRefreshing: Boolean = false,
    val isUploadingBackgrounds: Boolean = false,
    val isUploadingAvatar: Boolean = false,
    val localAvatarPath: String? = null,
    val localBackgroundPaths: List<String> = emptyList(),
    val connectionsSheetMode: String? = null,
    val connectionsUsers: List<ContactModel> = emptyList(),
    val isLoadingConnections: Boolean = false,
    val activeViewerItem: OwnerProfileItemDto? = null,
    val toastMessage: String? = null
)

enum class OtherProfileTab(val apiValue: String) {
    POSTS("posts"),
    REPOSTS("reposts")
}

enum class UserReportCategory(
    val apiValue: String,
    val title: String,
    val subReasons: List<String>
) {
    SPAM(
        apiValue = "spam",
        title = "Spam & fake engagement",
        subReasons = listOf("Bot or automated behavior", "Repetitive unsolicited links", "Fake followers or engagement")
    ),
    HARASSMENT(
        apiValue = "harassment",
        title = "Harassment or bullying",
        subReasons = listOf("Targeted abuse", "Threats or intimidation", "Unwanted repeated contact")
    ),
    IMPERSONATION(
        apiValue = "impersonation",
        title = "Impersonation",
        subReasons = listOf("Pretending to be me", "Pretending to be someone else", "Misleading brand or public figure")
    ),
    HATE_SPEECH(
        apiValue = "hate_speech",
        title = "Hate speech or symbols",
        subReasons = listOf("Attacks on protected groups", "Dehumanizing language", "Promotes discrimination")
    ),
    VIOLENCE(
        apiValue = "violence",
        title = "Violence or dangerous behavior",
        subReasons = listOf("Graphic violence", "Threats of physical harm", "Dangerous challenges")
    ),
    NUDITY(
        apiValue = "nudity_or_sexual_content",
        title = "Adult nudity or sexual content",
        subReasons = listOf("Explicit imagery", "Sexual solicitation", "Non-consensual content")
    ),
    SCAM(
        apiValue = "scam_or_fraud",
        title = "Scam or fraud",
        subReasons = listOf("Financial scam", "Phishing links", "Counterfeit goods or giveaways")
    ),
    OTHER(
        apiValue = "other",
        title = "Other safety issue",
        subReasons = listOf("Inappropriate profile info", "Underage account concern", "Other policy violation")
    )
}

data class UserReportSheetState(
    val isOpen: Boolean = false,
    val targetUserId: String = "",
    val step: Int = 1,
    val selectedCategory: UserReportCategory? = null,
    val selectedSubReason: String = "",
    val details: String = "",
    val isSubmitting: Boolean = false
)

data class OtherProfileInstanceState(
    val userId: String,
    val profile: OtherUserProfileDto? = null,
    val activeCategory: OtherProfileTab = OtherProfileTab.POSTS,
    val itemsByCategory: Map<OtherProfileTab, List<OwnerProfileItemDto>> = emptyMap(),
    val localAvatarPath: String? = null,
    val localBackgroundPaths: List<String> = emptyList(),
    val isLoadingProfile: Boolean = false,
    val isLoadingItems: Boolean = false,
    val isRefreshing: Boolean = false,
    val connectionsSheetMode: String? = null,
    val connectionsUsers: List<ContactModel> = emptyList(),
    val isLoadingConnections: Boolean = false,
    val activeViewerItem: OwnerProfileItemDto? = null
)

data class OtherProfileUiState(
    val stack: List<OtherProfileInstanceState> = emptyList(),
    val viewerNicknames: Map<String, String> = emptyMap(),
    val reportSheet: UserReportSheetState = UserReportSheetState(),
    val toastMessage: String? = null
) {
    val top: OtherProfileInstanceState? get() = stack.lastOrNull()
}

data class TelefamUiState(
    val initialized: Boolean = false,
    val isDarkTheme: Boolean = true,
    val session: AuthSessionDto? = null,
    val authStep: AuthStep = AuthStep.ENTER_EMAIL,
    val email: String = "",
    val otpDigits: List<String> = List(6) { "" },
    val cooldownSeconds: Long = 0L,
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val profileSetup: ProfileSetupState = ProfileSetupState(),
    val selectedConversationId: String? = null,
    val searchQuery: String = "",
    val activeTab: HomeTab = HomeTab.CHATS,
    val contactFilter: ContactFilter = ContactFilter.ALL,
    val contactSearchQuery: String = "",
    val isLoadingContacts: Boolean = false,
    val hasMoreContacts: Boolean = false,
    val contactsNextCursor: String = "",
    val contactsToastMessage: String? = null,
    val isEditingProfile: Boolean = false,
    val myProfile: MyProfileDto? = null,
    val ownerProfile: OwnerProfileUiState = OwnerProfileUiState(),
    val otherProfile: OtherProfileUiState = OtherProfileUiState(),
    val feedPosts: List<FeedPostDto> = emptyList(),
    val isLoadingFeed: Boolean = false,
    val notifications: List<NotificationDto> = emptyList(),
    val isLoadingNotifications: Boolean = false,
    val postComposer: PostComposerState = PostComposerState()
)

class TelefamViewModel(
    private val repository: TelefamRepository,
    feedRepository: FeedRepository,
    networkMonitor: AndroidNetworkMonitor,
    private val feedPlayerController: FeedPlayerController
) : ViewModel() {

    private val _uiState = MutableStateFlow(TelefamUiState())
    val uiState: StateFlow<TelefamUiState> = _uiState.asStateFlow()

    val deviceDisplayName: String = repository.deviceIdentity.deviceName
    val networkQuality: StateFlow<NetworkQuality> = networkMonitor.quality

    val feedController: FeedController = FeedController(
        scope = viewModelScope,
        feedRepository = feedRepository,
        playerController = feedPlayerController,
        networkQualityProvider = { networkQuality.value },
        onContactsChanged = { refreshContacts(reset = true) },
        onUseAudioInPost = { audio -> openPostComposerWithAudio(audio) },
        onOpenUserProfile = { userId -> openUserProfile(userId) }
    )
    val videoFeedState: StateFlow<VideoFeedUiState> = feedController.state
    val feedPlaybackState: StateFlow<FeedPlaybackState> = feedPlayerController.playbackState

    val conversations: StateFlow<List<ConversationModel>> =
        repository.observeConversations()
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val pendingSyncCount: StateFlow<Int> =
        repository.observePendingSyncCount()
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), 0)

    val contacts: StateFlow<List<ContactModel>> =
        combine(
            repository.observeCachedContacts(),
            _uiState.map {
                Triple(it.contactFilter, it.contactSearchQuery, it.otherProfile.viewerNicknames)
            }.distinctUntilChanged()
        ) { cached, (filter, rawQuery, nicknames) ->
            val q = rawQuery.trim().lowercase()
            cached.mapNotNull { rawItem ->
                val nick = nicknames[rawItem.userId]?.trim().orEmpty()
                val item = if (nick.isNotEmpty()) rawItem.copy(fullName = nick) else rawItem
                val matchesFilter = when (filter) {
                    ContactFilter.ALL -> true
                    ContactFilter.SUGGESTIONS -> !item.isFollowing
                    ContactFilter.FOLLOWERS -> item.followsMe
                    ContactFilter.FOLLOWING -> item.isFollowing
                    ContactFilter.FRIENDS -> item.isFollowing && item.followsMe
                }
                val matchesQuery = q.isEmpty() ||
                    item.fullName.lowercase().contains(q) ||
                    rawItem.fullName.lowercase().contains(q) ||
                    item.username.lowercase().contains(q)
                if (matchesFilter && matchesQuery) item else null
            }
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    val messages: StateFlow<List<MessageModel>> =
        _uiState
            .flatMapLatest { state ->
                val cid = state.selectedConversationId
                if (cid == null) flowOf(emptyList()) else repository.observeMessages(cid)
            }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    private var cooldownTickerJob: Job? = null
    private var contactsSearchJob: Job? = null
    private var songSearchJob: Job? = null
    private var hashtagSearchJob: Job? = null
    private var mediaPlayer: MediaPlayer? = null

    init {
        viewModelScope.launch {
            val saved = repository.loadEncryptedSession()
            val dark = repository.loadThemeDark()
            val suggestedIso = repository.suggestDeviceCountryIso()
            val cachedProfile = repository.loadCachedMyProfile()
            val cachedAvatarPath = repository.loadCachedAvatarPath()
            val cachedBgPaths = repository.loadCachedBackgroundPaths()
            val cachedOwnerMap = OwnerProfileTab.entries.associateWith { tab ->
                repository.loadCachedOwnerProfileItems(tab.apiValue)?.items.orEmpty()
            }.filterValues { it.isNotEmpty() }
            val cachedFeed = repository.loadCachedFeedPosts()
            val cachedNotifs = repository.loadCachedNotifications()
            val cachedNicknames = repository.loadCachedViewerNicknames()
            feedController.updateViewerNicknames(cachedNicknames)
            val prefill = saved?.let { seedProfileSetup(it.email, suggestedIso) }
                ?: ProfileSetupState(countryIso = suggestedIso)
            _uiState.update {
                it.copy(
                    initialized = true,
                    isDarkTheme = dark,
                    session = saved,
                    myProfile = cachedProfile,
                    ownerProfile = it.ownerProfile.copy(
                        localAvatarPath = cachedAvatarPath,
                        localBackgroundPaths = cachedBgPaths,
                        itemsByCategory = cachedOwnerMap
                    ),
                    otherProfile = it.otherProfile.copy(viewerNicknames = cachedNicknames),
                    feedPosts = cachedFeed,
                    notifications = cachedNotifs,
                    profileSetup = prefill
                )
            }
            if (saved != null && saved.profileCompleted) {
                repository.syncPendingAndRefresh(networkQuality.value, _uiState.value.selectedConversationId)
                refreshViewerNicknames()
                refreshContacts(reset = true)
                refreshMyProfile()
                loadOwnerProfileItems(_uiState.value.ownerProfile.activeCategory)
                refreshFeedPosts()
                feedController.loadInitialFromCacheAndRefresh(true)
                refreshNotifications()
                if (networkQuality.value == NetworkQuality.ONLINE) {
                    repository.flushQueuedPosts()
                }
            }
        }
        viewModelScope.launch {
            networkQuality.collectLatest { quality ->
                val s = _uiState.value.session
                if (quality == NetworkQuality.ONLINE && s != null && s.profileCompleted) {
                    repository.syncPendingAndRefresh(quality, _uiState.value.selectedConversationId)
                    refreshViewerNicknames()
                    refreshContacts(reset = true)
                    refreshMyProfile()
                    refreshFeedPosts()
                    feedController.loadInitialFromCacheAndRefresh(true)
                    refreshNotifications()
                    repository.flushQueuedPosts()
                }
            }
        }
    }

    override fun onCleared() {
        stopSongPreviewInternal()
        feedPlayerController.pause()
        super.onCleared()
    }

    fun setAppForeground(foreground: Boolean) {
        val activeTab = _uiState.value.activeTab
        val modalOpen = feedController.state.value.modalPlayer.isOpen
        if (!foreground) {
            feedPlayerController.setAppForeground(false)
        } else {
            feedPlayerController.setAppForeground(
                activeTab == HomeTab.FEEDS || modalOpen
            )
        }
    }

    fun toggleTheme() {
        val next = !_uiState.value.isDarkTheme
        _uiState.update { it.copy(isDarkTheme = next) }
        viewModelScope.launch { repository.saveThemeDark(next) }
    }

    fun updateEmail(value: String) {
        _uiState.update { it.copy(email = value, errorMessage = null) }
    }

    fun updateOtpDigit(index: Int, value: String) {
        val digitsOnly = value.filter { it.isDigit() }
        _uiState.update { state ->
            val updated = state.otpDigits.toMutableList()
            if (digitsOnly.length > 1) {
                digitsOnly.take(6).forEachIndexed { idx, ch ->
                    updated[idx] = ch.toString()
                }
            } else {
                updated[index] = digitsOnly.take(1)
            }
            state.copy(otpDigits = updated, errorMessage = null)
        }
    }

    fun sendOtp() {
        val email = _uiState.value.email.trim()
        viewModelScope.launch {
            val existingCooldown = repository.checkCooldown(email)
            if (!existingCooldown.canResend) {
                startCooldownTicker(existingCooldown.remainingSeconds)
                _uiState.update { it.copy(authStep = AuthStep.ENTER_OTP, errorMessage = null) }
                return@launch
            }
            _uiState.update { it.copy(isLoading = true, errorMessage = null) }
            when (val res = repository.sendOtp(email)) {
                is RepoResult.Success -> {
                    startCooldownTicker(res.data)
                    _uiState.update {
                        it.copy(isLoading = false, email = email, authStep = AuthStep.ENTER_OTP)
                    }
                }
                is RepoResult.Failure -> {
                    _uiState.update { it.copy(isLoading = false, errorMessage = res.userMessage) }
                }
            }
        }
    }

    fun verifyOtp(magicToken: String? = null, emailFromLink: String? = null) {
        val currentEmail = (emailFromLink ?: _uiState.value.email).trim()
        val otp = _uiState.value.otpDigits.joinToString("")
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, errorMessage = null, email = currentEmail) }
            when (val res = repository.verifyOtpOrMagicLink(currentEmail, otp, magicToken)) {
                is RepoResult.Success -> {
                    cooldownTickerJob?.cancel()
                    val sess = res.data
                    val suggestedIso = repository.suggestDeviceCountryIso()
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            session = sess,
                            otpDigits = List(6) { "" },
                            cooldownSeconds = 0L,
                            profileSetup = if (sess.profileCompleted) it.profileSetup
                            else seedProfileSetup(sess.email, suggestedIso)
                        )
                    }
                    if (sess.profileCompleted) {
                        repository.syncPendingAndRefresh(networkQuality.value, null)
                        feedController.loadInitialFromCacheAndRefresh(true)
                    }
                }
                is RepoResult.Failure -> {
                    _uiState.update { it.copy(isLoading = false, errorMessage = res.userMessage) }
                }
            }
        }
    }

    fun signInWithGoogleToken(idToken: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, errorMessage = null) }
            when (val res = repository.verifyGoogleIdToken(idToken)) {
                is RepoResult.Success -> {
                    val sess = res.data
                    val suggestedIso = repository.suggestDeviceCountryIso()
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            session = sess,
                            profileSetup = if (sess.profileCompleted) it.profileSetup
                            else seedProfileSetup(sess.email, suggestedIso)
                        )
                    }
                    if (sess.profileCompleted) {
                        repository.syncPendingAndRefresh(networkQuality.value, null)
                        feedController.loadInitialFromCacheAndRefresh(true)
                    }
                }
                is RepoResult.Failure -> {
                    _uiState.update { it.copy(isLoading = false, errorMessage = res.userMessage) }
                }
            }
        }
    }

    fun reportSanitizedError(message: String) {
        _uiState.update { it.copy(isLoading = false, errorMessage = message) }
    }

    fun changeEmail() {
        _uiState.update {
            it.copy(authStep = AuthStep.ENTER_EMAIL, otpDigits = List(6) { "" }, errorMessage = null)
        }
    }

    private fun seedProfileSetup(email: String, countryIso: String): ProfileSetupState {
        val (fullName, username) = repository.bridge.autofillProfileFromEmail(email)
        val countryName = SUPPORTED_COUNTRIES.firstOrNull { it.iso == countryIso }?.name.orEmpty()
        return ProfileSetupState(
            fullName = fullName,
            username = username,
            countryIso = countryIso,
            location = countryName
        )
    }

    fun updateProfileField(transform: (ProfileSetupState) -> ProfileSetupState) {
        _uiState.update { it.copy(profileSetup = transform(it.profileSetup).copy(errorMessage = null)) }
    }

    fun setCroppedAvatar(bitmap: Bitmap) {
        _uiState.update {
            it.copy(
                profileSetup = it.profileSetup.copy(avatarBitmap = bitmap, errorMessage = null),
                ownerProfile = it.ownerProfile.copy(isUploadingAvatar = true)
            )
        }
        viewModelScope.launch {
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
            val bytes = out.toByteArray()
            if (networkQuality.value == NetworkQuality.ONLINE) {
                when (val res = repository.uploadSanitizedAvatar(bytes)) {
                    is RepoResult.Success -> {
                        val localPath = repository.loadCachedAvatarPath()
                        val updatedProfile = repository.loadCachedMyProfile()
                        _uiState.update { st ->
                            st.copy(
                                myProfile = updatedProfile ?: st.myProfile?.copy(
                                    avatarFingerprintHash = res.data,
                                    avatarUrl = "/v1/profile/avatar?v=${res.data}"
                                ),
                                profileSetup = st.profileSetup.copy(avatarFingerprintHash = res.data),
                                ownerProfile = st.ownerProfile.copy(
                                    isUploadingAvatar = false,
                                    localAvatarPath = localPath ?: st.ownerProfile.localAvatarPath
                                )
                            )
                        }
                    }
                    is RepoResult.Failure -> {
                        _uiState.update {
                            it.copy(
                                ownerProfile = it.ownerProfile.copy(
                                    isUploadingAvatar = false,
                                    toastMessage = res.userMessage
                                )
                            )
                        }
                    }
                }
            } else {
                val localPath = repository.saveLocalAvatarBytes("pending_${System.currentTimeMillis()}", bytes)
                _uiState.update {
                    it.copy(
                        ownerProfile = it.ownerProfile.copy(
                            isUploadingAvatar = false,
                            localAvatarPath = localPath
                        )
                    )
                }
            }
        }
    }

    fun submitProfileSetup() {
        val p = _uiState.value.profileSetup
        val fullName = p.fullName.trim()
        val username = p.username.trim().lowercase()
        if (fullName.length < 2 || username.length < 3 || p.gender.isBlank()) {
            _uiState.update {
                it.copy(profileSetup = it.profileSetup.copy(errorMessage = "Please complete all required fields."))
            }
            return
        }
        if (!repository.bridge.validatePhoneNumber(p.countryIso, p.phoneNumber)) {
            _uiState.update {
                it.copy(profileSetup = it.profileSetup.copy(errorMessage = "Please enter a valid phone number for the selected country."))
            }
            return
        }
        val by = p.birthYear
        val bm = p.birthMonth
        val bd = p.birthDay
        val cal = Calendar.getInstance()
        if (by == null || bm == null || bd == null ||
            !repository.bridge.validateAge13Plus(
                by, bm, bd,
                cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH)
            )
        ) {
            _uiState.update {
                it.copy(profileSetup = it.profileSetup.copy(errorMessage = "You must be at least 13 years old."))
            }
            return
        }

        val dobIso = "%04d-%02d-%02d".format(by, bm, bd)
        viewModelScope.launch {
            _uiState.update { it.copy(profileSetup = it.profileSetup.copy(isSubmitting = true, errorMessage = null)) }
            val req = ProfileSetupRequest(
                fullName = fullName,
                username = username,
                countryIso = p.countryIso,
                phoneNumber = p.phoneNumber.trim(),
                gender = p.gender,
                dateOfBirth = dobIso,
                location = p.location.trim(),
                bio = p.bio.trim().take(150),
                avatarFingerprintHash = p.avatarFingerprintHash
            )
            when (val res = repository.completeProfileSetup(req, networkQuality.value)) {
                is RepoResult.Success -> {
                    val immediateProfile = repository.loadCachedMyProfile()
                    _uiState.update {
                        it.copy(
                            session = res.data,
                            myProfile = immediateProfile ?: it.myProfile,
                            isEditingProfile = false,
                            profileSetup = it.profileSetup.copy(isSubmitting = false)
                        )
                    }
                    repository.syncPendingAndRefresh(networkQuality.value, null)
                    refreshMyProfile()
                }
                is RepoResult.Failure -> {
                    _uiState.update {
                        it.copy(
                            profileSetup = it.profileSetup.copy(isSubmitting = false, errorMessage = res.userMessage)
                        )
                    }
                }
            }
        }
    }

    fun updateSearchQuery(query: String) {
        _uiState.update { it.copy(searchQuery = query) }
        if (_uiState.value.activeTab == HomeTab.FEEDS) {
            refreshFeedPosts(query)
        }
    }

    fun selectHomeTab(tab: HomeTab) {
        _uiState.update { it.copy(activeTab = tab) }
        if (tab != HomeTab.FEEDS && !feedController.state.value.modalPlayer.isOpen) {
            feedPlayerController.pause()
        }
        when (tab) {
            HomeTab.CHATS -> Unit
            HomeTab.CONTACTS -> refreshContacts(reset = true)
            HomeTab.FEEDS -> {
                feedPlayerController.setAppForeground(true)
                val activeVideos = feedController.state.value.activeChannel.videos
                if (activeVideos.isEmpty()) {
                    feedController.refreshActiveFeed()
                } else {
                    feedController.playActiveFeedVideoIfAvailable()
                }
            }
            HomeTab.PROFILE -> {
                refreshOwnerProfile(isPullGesture = false)
            }
        }
    }

    fun syncNow() {
        val sess = _uiState.value.session ?: return
        if (!sess.profileCompleted) return
        viewModelScope.launch {
            repository.syncPendingAndRefresh(networkQuality.value, _uiState.value.selectedConversationId)
            refreshContacts(reset = true)
            refreshFeedPosts()
            refreshMyProfile()
            refreshNotifications()
            if (networkQuality.value == NetworkQuality.ONLINE) {
                repository.flushQueuedPosts()
            }
        }
    }

    fun refreshMyProfile() {
        val sess = _uiState.value.session ?: return
        if (!sess.profileCompleted || networkQuality.value == NetworkQuality.OFFLINE) return
        viewModelScope.launch {
            when (val res = repository.fetchMyProfile()) {
                is RepoResult.Success -> {
                    _uiState.update { it.copy(myProfile = res.data) }
                    val localAvatar = repository.ensureAvatarCachedLocally(res.data)
                    val localBgs = repository.ensureBackgroundsCachedLocally(res.data.backgroundPhotos)
                    _uiState.update { st ->
                        st.copy(
                            ownerProfile = st.ownerProfile.copy(
                                localAvatarPath = localAvatar ?: st.ownerProfile.localAvatarPath,
                                localBackgroundPaths = localBgs
                            )
                        )
                    }
                }
                is RepoResult.Failure -> Unit
            }
        }
    }

    fun refreshOwnerProfile(isPullGesture: Boolean) {
        val sess = _uiState.value.session ?: return
        if (!sess.profileCompleted) return
        viewModelScope.launch {
            if (isPullGesture) {
                _uiState.update { it.copy(ownerProfile = it.ownerProfile.copy(isRefreshing = true)) }
            }
            if (networkQuality.value == NetworkQuality.ONLINE) {
                when (val res = repository.fetchMyProfile()) {
                    is RepoResult.Success -> {
                        _uiState.update { it.copy(myProfile = res.data) }
                        val localAvatar = repository.ensureAvatarCachedLocally(res.data)
                        val localBgs = repository.ensureBackgroundsCachedLocally(res.data.backgroundPhotos)
                        _uiState.update { st ->
                            st.copy(
                                ownerProfile = st.ownerProfile.copy(
                                    localAvatarPath = localAvatar ?: st.ownerProfile.localAvatarPath,
                                    localBackgroundPaths = localBgs
                                )
                            )
                        }
                    }
                    is RepoResult.Failure -> Unit
                }
            }
            loadOwnerProfileItemsInternal(_uiState.value.ownerProfile.activeCategory)
            _uiState.update { it.copy(ownerProfile = it.ownerProfile.copy(isRefreshing = false)) }
        }
    }

    fun selectOwnerProfileCategory(tab: OwnerProfileTab) {
        _uiState.update { st ->
            st.copy(ownerProfile = st.ownerProfile.copy(activeCategory = tab))
        }
        loadOwnerProfileItems(tab)
    }

    fun loadOwnerProfileItems(tab: OwnerProfileTab) {
        viewModelScope.launch {
            loadOwnerProfileItemsInternal(tab)
        }
    }

    private suspend fun loadOwnerProfileItemsInternal(tab: OwnerProfileTab) {
        val cached = repository.loadCachedOwnerProfileItems(tab.apiValue)?.items
        if (!cached.isNullOrEmpty() && _uiState.value.ownerProfile.itemsByCategory[tab].isNullOrEmpty()) {
            _uiState.update { st ->
                st.copy(
                    ownerProfile = st.ownerProfile.copy(
                        itemsByCategory = st.ownerProfile.itemsByCategory + (tab to cached)
                    )
                )
            }
        }
        if (networkQuality.value == NetworkQuality.OFFLINE) return
        _uiState.update { st ->
            st.copy(ownerProfile = st.ownerProfile.copy(isLoadingItems = true))
        }
        when (val res = repository.fetchOwnerProfileItems(tab.apiValue)) {
            is RepoResult.Success -> {
                _uiState.update { st ->
                    st.copy(
                        ownerProfile = st.ownerProfile.copy(
                            isLoadingItems = false,
                            itemsByCategory = st.ownerProfile.itemsByCategory + (tab to res.data.items)
                        )
                    )
                }
            }
            is RepoResult.Failure -> {
                _uiState.update { st ->
                    st.copy(ownerProfile = st.ownerProfile.copy(isLoadingItems = false))
                }
            }
        }
    }

    fun uploadOwnerBackgroundPhotos(uris: List<Uri>) {
        if (uris.isEmpty()) return
        val existingCount = _uiState.value.myProfile?.backgroundPhotos?.size ?: 0
        val remaining = (5 - existingCount).coerceAtLeast(0)
        if (remaining == 0 || uris.size > remaining) {
            _uiState.update {
                it.copy(
                    ownerProfile = it.ownerProfile.copy(
                        toastMessage = "Maximum 5 background photos allowed"
                    )
                )
            }
            if (remaining == 0) return
        }
        val toUpload = uris.take(remaining)
        viewModelScope.launch {
            _uiState.update { it.copy(ownerProfile = it.ownerProfile.copy(isUploadingBackgrounds = true)) }
            when (val res = repository.uploadBackgroundPhotos(toUpload)) {
                is RepoResult.Success -> {
                    val localBgs = repository.loadCachedBackgroundPaths()
                    _uiState.update { st ->
                        st.copy(
                            myProfile = st.myProfile?.copy(backgroundPhotos = res.data),
                            ownerProfile = st.ownerProfile.copy(
                                isUploadingBackgrounds = false,
                                localBackgroundPaths = localBgs
                            )
                        )
                    }
                }
                is RepoResult.Failure -> {
                    _uiState.update {
                        it.copy(
                            ownerProfile = it.ownerProfile.copy(
                                isUploadingBackgrounds = false,
                                toastMessage = res.userMessage
                            )
                        )
                    }
                }
            }
        }
    }

    fun deleteOwnerBackgroundPhoto(bgId: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(ownerProfile = it.ownerProfile.copy(isUploadingBackgrounds = true)) }
            when (val res = repository.deleteBackgroundPhoto(bgId)) {
                is RepoResult.Success -> {
                    val localBgs = repository.loadCachedBackgroundPaths()
                    _uiState.update { st ->
                        st.copy(
                            myProfile = st.myProfile?.copy(backgroundPhotos = res.data),
                            ownerProfile = st.ownerProfile.copy(
                                isUploadingBackgrounds = false,
                                localBackgroundPaths = localBgs
                            )
                        )
                    }
                }
                is RepoResult.Failure -> {
                    _uiState.update {
                        it.copy(
                            ownerProfile = it.ownerProfile.copy(
                                isUploadingBackgrounds = false,
                                toastMessage = res.userMessage
                            )
                        )
                    }
                }
            }
        }
    }

    fun openConnectionsSheet(mode: String) {
        _uiState.update {
            it.copy(
                ownerProfile = it.ownerProfile.copy(
                    connectionsSheetMode = mode,
                    connectionsUsers = emptyList(),
                    isLoadingConnections = true
                )
            )
        }
        viewModelScope.launch {
            when (val res = repository.fetchConnectionsList(mode)) {
                is RepoResult.Success -> {
                    _uiState.update {
                        it.copy(
                            ownerProfile = it.ownerProfile.copy(
                                connectionsUsers = res.data,
                                isLoadingConnections = false
                            )
                        )
                    }
                }
                is RepoResult.Failure -> {
                    _uiState.update {
                        it.copy(
                            ownerProfile = it.ownerProfile.copy(
                                isLoadingConnections = false,
                                toastMessage = res.userMessage
                            )
                        )
                    }
                }
            }
        }
    }

    fun closeConnectionsSheet() {
        _uiState.update {
            it.copy(ownerProfile = it.ownerProfile.copy(connectionsSheetMode = null))
        }
    }

    fun toggleConnectionFollow(contact: ContactModel) {
        viewModelScope.launch {
            when (val res = repository.toggleFollowOfflineFirst(contact, networkQuality.value)) {
                is RepoResult.Success -> {
                    _uiState.update { st ->
                        val updatedList = st.ownerProfile.connectionsUsers.map {
                            if (it.userId == contact.userId) res.data else it
                        }
                        val delta = if (res.data.isFollowing != contact.isFollowing) {
                            if (res.data.isFollowing) 1L else -1L
                        } else 0L
                        val nextProfile = st.myProfile?.let { p ->
                            p.copy(followingCount = (p.followingCount + delta).coerceAtLeast(0L))
                        }
                        st.copy(
                            myProfile = nextProfile,
                            ownerProfile = st.ownerProfile.copy(connectionsUsers = updatedList)
                        )
                    }
                    refreshContacts(reset = true)
                }
                is RepoResult.Failure -> {
                    _uiState.update {
                        it.copy(ownerProfile = it.ownerProfile.copy(toastMessage = res.userMessage))
                    }
                }
            }
        }
    }

    fun openOwnerItemViewer(item: OwnerProfileItemDto) {
        val currentTab = _uiState.value.ownerProfile.activeCategory
        val items = _uiState.value.ownerProfile.itemsByCategory[currentTab].orEmpty()
        if (item.video != null) {
            val videoList = items.mapNotNull { it.video }
            val idx = videoList.indexOfFirst { it.videoId == item.video.videoId }.coerceAtLeast(0)
            val title = when (currentTab) {
                OwnerProfileTab.POSTS -> "Posts"
                OwnerProfileTab.REPOSTS -> "Reposts"
                OwnerProfileTab.LOCKED -> "Locked"
                OwnerProfileTab.SAVED -> "Saved"
            }
            feedController.openModalFeedPlayer(title, videoList, idx)
            return
        }
        _uiState.update {
            it.copy(ownerProfile = it.ownerProfile.copy(activeViewerItem = item))
        }
        if (item.postId.isNotBlank() && networkQuality.value == NetworkQuality.ONLINE) {
            viewModelScope.launch {
                when (val res = repository.engagePost(item.postId, "view", true)) {
                    is RepoResult.Success -> {
                        patchOwnerItem(item.postId) { cur ->
                            cur.copy(likesCount = res.data.likesCount, viewsCount = res.data.viewsCount)
                        }
                    }
                    is RepoResult.Failure -> Unit
                }
            }
        }
    }

    fun closeOwnerItemViewer() {
        _uiState.update {
            it.copy(ownerProfile = it.ownerProfile.copy(activeViewerItem = null))
        }
    }

    fun toggleOwnerPostLike(item: OwnerProfileItemDto) {
        val postId = item.postId.ifBlank { return }
        val next = !item.isLiked
        patchOwnerItem(postId) { cur ->
            cur.copy(
                isLiked = next,
                likesCount = (cur.likesCount + if (next) 1L else -1L).coerceAtLeast(0L)
            )
        }
        viewModelScope.launch {
            when (val res = repository.engagePost(postId, "like", next)) {
                is RepoResult.Success -> {
                    patchOwnerItem(postId) { cur ->
                        cur.copy(likesCount = res.data.likesCount, viewsCount = res.data.viewsCount)
                    }
                }
                is RepoResult.Failure -> Unit
            }
        }
    }

    fun toggleOwnerPostSave(item: OwnerProfileItemDto) {
        val postId = item.postId.ifBlank { return }
        val next = !item.isSaved
        patchOwnerItem(postId) { cur -> cur.copy(isSaved = next) }
        viewModelScope.launch {
            repository.engagePost(postId, "save", next)
            loadOwnerProfileItemsInternal(OwnerProfileTab.SAVED)
        }
    }

    fun toggleOwnerPostLock(item: OwnerProfileItemDto) {
        val postId = item.postId.ifBlank { return }
        val targetVis = if (item.visibility == "private") "public" else "private"
        viewModelScope.launch {
            when (repository.setPostVisibility(postId, targetVis)) {
                is RepoResult.Success -> {
                    _uiState.update {
                        it.copy(
                            ownerProfile = it.ownerProfile.copy(
                                activeViewerItem = null,
                                toastMessage = if (targetVis == "private") "Moved to Locked" else "Made Public"
                            )
                        )
                    }
                    loadOwnerProfileItemsInternal(OwnerProfileTab.POSTS)
                    loadOwnerProfileItemsInternal(OwnerProfileTab.LOCKED)
                }
                is RepoResult.Failure -> Unit
            }
        }
    }

    private fun patchOwnerItem(postId: String, transform: (OwnerProfileItemDto) -> OwnerProfileItemDto) {
        _uiState.update { st ->
            val updatedMap = st.ownerProfile.itemsByCategory.mapValues { (_, list) ->
                list.map { if (it.postId == postId) transform(it) else it }
            }
            val updatedViewer = st.ownerProfile.activeViewerItem?.let { v ->
                if (v.postId == postId) transform(v) else v
            }
            st.copy(
                ownerProfile = st.ownerProfile.copy(
                    itemsByCategory = updatedMap,
                    activeViewerItem = updatedViewer
                )
            )
        }
    }

    fun showOwnerProfileToast(message: String) {
        _uiState.update {
            it.copy(ownerProfile = it.ownerProfile.copy(toastMessage = message))
        }
    }

    fun clearOwnerProfileToast() {
        _uiState.update {
            it.copy(ownerProfile = it.ownerProfile.copy(toastMessage = null))
        }
    }

    // =========================================================================
    // OTHER USER PROFILE NAVIGATION, CACHING, NICKNAME, BLOCK/MUTE, REPORT
    // =========================================================================

    fun refreshViewerNicknames() {
        if (networkQuality.value == NetworkQuality.OFFLINE) return
        viewModelScope.launch {
            val map = repository.fetchViewerNicknames() ?: return@launch
            feedController.updateViewerNicknames(map)
            _uiState.update { st ->
                val updatedStack = st.otherProfile.stack.map { inst ->
                    val nick = map[inst.userId].orEmpty()
                    inst.copy(profile = inst.profile?.copy(nickname = nick))
                }
                st.copy(
                    otherProfile = st.otherProfile.copy(
                        viewerNicknames = map,
                        stack = updatedStack
                    )
                )
            }
        }
    }

    fun openUserProfile(userId: String) {
        val targetId = userId.trim()
        if (targetId.isEmpty()) return

        // Always close modal player / discovery overlays above the profile layer if open
        if (feedController.state.value.modalPlayer.isOpen) {
            feedController.closeModalFeedPlayer()
        }
        if (feedController.state.value.audioDiscovery.isOpen) {
            feedController.closeAudioDiscovery()
        }
        if (feedController.state.value.hashtagDiscovery.isOpen) {
            feedController.closeHashtagDiscovery()
        }

        val myId = _uiState.value.session?.userId.orEmpty()
        if (myId.isNotEmpty() && targetId == myId) {
            clearOtherProfileStack()
            if (feedController.state.value.search.isOpen) {
                feedController.closeSearch()
            }
            if (feedController.state.value.isLiveScreenOpen) {
                feedController.closeLiveScreen()
            }
            selectHomeTab(HomeTab.PROFILE)
            return
        }

        feedPlayerController.pause()

        // Avoid pushing duplicate consecutive instance of the exact same user
        if (_uiState.value.otherProfile.top?.userId == targetId) {
            refreshOtherProfile(isPullGesture = false)
            return
        }

        viewModelScope.launch {
            val cachedProfile = repository.loadCachedOtherProfile(targetId)
            val cachedAvatar = repository.loadCachedOtherAvatarPath(targetId)
            val cachedBgs = repository.loadCachedOtherBackgroundPaths(targetId)
            val cachedItemsMap = OtherProfileTab.entries.associateWith { tab ->
                repository.loadCachedOtherProfileItems(targetId, tab.apiValue)?.items.orEmpty()
            }.filterValues { it.isNotEmpty() }

            val seedInstance = OtherProfileInstanceState(
                userId = targetId,
                profile = cachedProfile,
                localAvatarPath = cachedAvatar,
                localBackgroundPaths = cachedBgs,
                itemsByCategory = cachedItemsMap,
                isLoadingProfile = cachedProfile == null,
                isLoadingItems = cachedItemsMap[OtherProfileTab.POSTS].isNullOrEmpty()
            )
            _uiState.update { st ->
                st.copy(
                    otherProfile = st.otherProfile.copy(
                        stack = st.otherProfile.stack + seedInstance
                    )
                )
            }
            refreshOtherProfileInternal(targetId, isPullGesture = false)
        }
    }

    fun closeTopOtherProfile() {
        _uiState.update { st ->
            val current = st.otherProfile.stack
            val nextStack = if (current.isNotEmpty()) current.dropLast(1) else emptyList()
            st.copy(
                otherProfile = st.otherProfile.copy(
                    stack = nextStack,
                    reportSheet = UserReportSheetState()
                )
            )
        }
        val st = _uiState.value
        val modalClosed = !feedController.state.value.modalPlayer.isOpen &&
            !feedController.state.value.search.isOpen &&
            !feedController.state.value.hashtagDiscovery.isOpen &&
            !feedController.state.value.audioDiscovery.isOpen &&
            !feedController.state.value.isLiveScreenOpen
        if (st.otherProfile.stack.isEmpty() && st.activeTab == HomeTab.FEEDS && modalClosed) {
            feedController.playActiveFeedVideoIfAvailable()
        }
    }

    fun clearOtherProfileStack() {
        _uiState.update {
            it.copy(
                otherProfile = it.otherProfile.copy(
                    stack = emptyList(),
                    reportSheet = UserReportSheetState()
                )
            )
        }
    }

    fun refreshOtherProfile(isPullGesture: Boolean) {
        val topId = _uiState.value.otherProfile.top?.userId ?: return
        viewModelScope.launch {
            refreshOtherProfileInternal(topId, isPullGesture)
        }
    }

    private suspend fun refreshOtherProfileInternal(targetId: String, isPullGesture: Boolean) {
        if (isPullGesture) {
            updateOtherInstance(targetId) { it.copy(isRefreshing = true) }
        }
        if (networkQuality.value == NetworkQuality.ONLINE) {
            when (val res = repository.fetchOtherProfile(targetId)) {
                is RepoResult.Success -> {
                    val dto = res.data
                    val updatedNickMap = _uiState.value.otherProfile.viewerNicknames.toMutableMap().apply {
                        if (dto.nickname.isNotBlank()) put(targetId, dto.nickname) else remove(targetId)
                    }
                    feedController.updateViewerNicknames(updatedNickMap)
                    _uiState.update { st ->
                        st.copy(otherProfile = st.otherProfile.copy(viewerNicknames = updatedNickMap))
                    }
                    updateOtherInstance(targetId) { inst ->
                        inst.copy(profile = dto, isLoadingProfile = false)
                    }
                    val avatarPath = repository.ensureOtherAvatarCachedLocally(targetId, dto.avatarFingerprintHash)
                    val bgPaths = repository.ensureOtherBackgroundsCachedLocally(targetId, dto.backgroundPhotos)
                    updateOtherInstance(targetId) { inst ->
                        inst.copy(
                            localAvatarPath = avatarPath ?: inst.localAvatarPath,
                            localBackgroundPaths = bgPaths
                        )
                    }
                }
                is RepoResult.Failure -> {
                    updateOtherInstance(targetId) { it.copy(isLoadingProfile = false) }
                    if (isPullGesture) showOtherProfileToast(res.userMessage)
                }
            }
        } else {
            updateOtherInstance(targetId) { it.copy(isLoadingProfile = false) }
        }

        val activeCat = _uiState.value.otherProfile.stack.lastOrNull { it.userId == targetId }?.activeCategory
            ?: OtherProfileTab.POSTS
        loadOtherProfileItemsInternal(targetId, activeCat)
        updateOtherInstance(targetId) { it.copy(isRefreshing = false) }
    }

    fun selectOtherProfileCategory(tab: OtherProfileTab) {
        val topId = _uiState.value.otherProfile.top?.userId ?: return
        updateOtherInstance(topId) { it.copy(activeCategory = tab) }
        viewModelScope.launch {
            loadOtherProfileItemsInternal(topId, tab)
        }
    }

    private suspend fun loadOtherProfileItemsInternal(targetId: String, tab: OtherProfileTab) {
        val cached = repository.loadCachedOtherProfileItems(targetId, tab.apiValue)?.items
        val existing = _uiState.value.otherProfile.stack.lastOrNull { it.userId == targetId }?.itemsByCategory?.get(tab)
        if (!cached.isNullOrEmpty() && existing.isNullOrEmpty()) {
            updateOtherInstance(targetId) { inst ->
                inst.copy(itemsByCategory = inst.itemsByCategory + (tab to cached))
            }
        }
        if (networkQuality.value == NetworkQuality.OFFLINE) return
        updateOtherInstance(targetId) { it.copy(isLoadingItems = true) }
        when (val res = repository.fetchOtherProfileItems(targetId, tab.apiValue)) {
            is RepoResult.Success -> {
                updateOtherInstance(targetId) { inst ->
                    inst.copy(
                        isLoadingItems = false,
                        itemsByCategory = inst.itemsByCategory + (tab to res.data.items)
                    )
                }
            }
            is RepoResult.Failure -> {
                updateOtherInstance(targetId) { it.copy(isLoadingItems = false) }
            }
        }
    }

    fun toggleOtherProfileFollow() {
        val inst = _uiState.value.otherProfile.top ?: return
        val profile = inst.profile ?: return
        if (profile.isBlocked || profile.isBlockedBy) return
        val contact = ContactModel(
            userId = profile.userId,
            fullName = profile.fullName,
            username = profile.username,
            location = profile.location,
            avatarFingerprintHash = profile.avatarFingerprintHash,
            isFollowing = profile.isFollowing,
            followsMe = profile.followsMe,
            relationship = profile.relationship,
            riskScore = 0
        )
        viewModelScope.launch {
            when (val res = repository.toggleFollowOfflineFirst(contact, networkQuality.value)) {
                is RepoResult.Success -> {
                    val delta = if (res.data.isFollowing != profile.isFollowing) {
                        if (res.data.isFollowing) 1L else -1L
                    } else 0L
                    val updatedProfile = profile.copy(
                        isFollowing = res.data.isFollowing,
                        followsMe = res.data.followsMe,
                        relationship = res.data.relationship,
                        followersCount = (profile.followersCount + delta).coerceAtLeast(0L)
                    )
                    repository.cacheOtherProfile(updatedProfile)
                    updateOtherInstance(inst.userId) { cur ->
                        cur.copy(profile = updatedProfile)
                    }
                    refreshContacts(reset = true)
                    refreshMyProfile()
                }
                is RepoResult.Failure -> showOtherProfileToast(res.userMessage)
            }
        }
    }

    fun openOtherProfileConnections(kind: String) {
        val topId = _uiState.value.otherProfile.top?.userId ?: return
        updateOtherInstance(topId) {
            it.copy(
                connectionsSheetMode = kind,
                connectionsUsers = emptyList(),
                isLoadingConnections = true
            )
        }
        viewModelScope.launch {
            when (val res = repository.fetchOtherUserConnections(topId, kind)) {
                is RepoResult.Success -> {
                    updateOtherInstance(topId) {
                        it.copy(connectionsUsers = res.data, isLoadingConnections = false)
                    }
                }
                is RepoResult.Failure -> {
                    updateOtherInstance(topId) { it.copy(isLoadingConnections = false) }
                    showOtherProfileToast(res.userMessage)
                }
            }
        }
    }

    fun closeOtherProfileConnections() {
        val topId = _uiState.value.otherProfile.top?.userId ?: return
        updateOtherInstance(topId) { it.copy(connectionsSheetMode = null) }
    }

    fun toggleOtherConnectionFollow(contact: ContactModel) {
        val topId = _uiState.value.otherProfile.top?.userId ?: return
        viewModelScope.launch {
            when (val res = repository.toggleFollowOfflineFirst(contact, networkQuality.value)) {
                is RepoResult.Success -> {
                    updateOtherInstance(topId) { inst ->
                        val updated = inst.connectionsUsers.map {
                            if (it.userId == contact.userId) res.data else it
                        }
                        inst.copy(connectionsUsers = updated)
                    }
                    refreshContacts(reset = true)
                }
                is RepoResult.Failure -> showOtherProfileToast(res.userMessage)
            }
        }
    }

    fun setOtherUserNickname(rawNickname: String) {
        val topId = _uiState.value.otherProfile.top?.userId ?: return
        viewModelScope.launch {
            when (val res = repository.setUserNickname(topId, rawNickname)) {
                is RepoResult.Success -> {
                    val saved = res.data
                    val updatedMap = _uiState.value.otherProfile.viewerNicknames.toMutableMap().apply {
                        if (saved.isEmpty()) remove(topId) else put(topId, saved)
                    }
                    feedController.updateViewerNicknames(updatedMap)
                    _uiState.update { st ->
                        val updatedStack = st.otherProfile.stack.map { inst ->
                            if (inst.userId == topId) {
                                inst.copy(profile = inst.profile?.copy(nickname = saved))
                            } else inst
                        }
                        st.copy(
                            otherProfile = st.otherProfile.copy(
                                stack = updatedStack,
                                viewerNicknames = updatedMap,
                                toastMessage = if (saved.isEmpty()) "Nickname removed" else "Nickname updated"
                            )
                        )
                    }
                }
                is RepoResult.Failure -> showOtherProfileToast(res.userMessage)
            }
        }
    }

    fun toggleOtherUserBlock() {
        val inst = _uiState.value.otherProfile.top ?: return
        val profile = inst.profile ?: return
        val nextBlocked = !profile.isBlocked
        viewModelScope.launch {
            when (val res = repository.setUserBlocked(inst.userId, nextBlocked)) {
                is RepoResult.Success -> {
                    val nextFollowers = if (nextBlocked && profile.isFollowing) {
                        (profile.followersCount - 1L).coerceAtLeast(0L)
                    } else profile.followersCount
                    val updatedProfile = profile.copy(
                        isBlocked = res.data,
                        isFollowing = if (res.data) false else profile.isFollowing,
                        relationship = if (res.data) "follow" else profile.relationship,
                        followersCount = nextFollowers
                    )
                    updateOtherInstance(inst.userId) { cur ->
                        cur.copy(
                            profile = updatedProfile,
                            itemsByCategory = if (res.data) emptyMap() else cur.itemsByCategory
                        )
                    }
                    if (!res.data) {
                        loadOtherProfileItemsInternal(inst.userId, inst.activeCategory)
                    }
                    feedController.refreshSafetyPreferences()
                    feedController.refreshActiveFeed()
                    refreshContacts(reset = true)
                    showOtherProfileToast(if (res.data) "User blocked" else "User unblocked")
                }
                is RepoResult.Failure -> showOtherProfileToast(res.userMessage)
            }
        }
    }

    fun toggleOtherUserMute() {
        val inst = _uiState.value.otherProfile.top ?: return
        val profile = inst.profile ?: return
        val nextMuted = !profile.isMuted
        viewModelScope.launch {
            when (val res = repository.setUserMuted(inst.userId, nextMuted)) {
                is RepoResult.Success -> {
                    updateOtherInstance(inst.userId) { cur ->
                        cur.copy(profile = cur.profile?.copy(isMuted = res.data))
                    }
                    feedController.refreshSafetyPreferences()
                    feedController.refreshActiveFeed()
                    showOtherProfileToast(if (res.data) "User muted" else "User unmuted")
                }
                is RepoResult.Failure -> showOtherProfileToast(res.userMessage)
            }
        }
    }

    fun openOtherReportSheet() {
        val topId = _uiState.value.otherProfile.top?.userId ?: return
        _uiState.update { st ->
            st.copy(
                otherProfile = st.otherProfile.copy(
                    reportSheet = UserReportSheetState(
                        isOpen = true,
                        targetUserId = topId,
                        step = 1
                    )
                )
            )
        }
    }

    fun selectOtherReportCategory(category: UserReportCategory) {
        _uiState.update { st ->
            st.copy(
                otherProfile = st.otherProfile.copy(
                    reportSheet = st.otherProfile.reportSheet.copy(
                        selectedCategory = category,
                        selectedSubReason = category.subReasons.firstOrNull().orEmpty(),
                        step = 2
                    )
                )
            )
        }
    }

    fun selectOtherReportSubReason(subReason: String) {
        _uiState.update { st ->
            st.copy(
                otherProfile = st.otherProfile.copy(
                    reportSheet = st.otherProfile.reportSheet.copy(selectedSubReason = subReason)
                )
            )
        }
    }

    fun updateOtherReportDetails(details: String) {
        _uiState.update { st ->
            st.copy(
                otherProfile = st.otherProfile.copy(
                    reportSheet = st.otherProfile.reportSheet.copy(details = details.take(400))
                )
            )
        }
    }

    fun backOtherReportStep() {
        _uiState.update { st ->
            val curStep = st.otherProfile.reportSheet.step
            st.copy(
                otherProfile = st.otherProfile.copy(
                    reportSheet = st.otherProfile.reportSheet.copy(step = if (curStep <= 1) 1 else 1)
                )
            )
        }
    }

    fun submitOtherReport() {
        val rs = _uiState.value.otherProfile.reportSheet
        val category = rs.selectedCategory ?: return
        if (rs.targetUserId.isBlank() || rs.isSubmitting) return
        viewModelScope.launch {
            _uiState.update { st ->
                st.copy(
                    otherProfile = st.otherProfile.copy(
                        reportSheet = st.otherProfile.reportSheet.copy(isSubmitting = true)
                    )
                )
            }
            when (val res = repository.submitUserReport(
                userId = rs.targetUserId,
                category = category.apiValue,
                subReason = rs.selectedSubReason,
                details = rs.details.trim()
            )) {
                is RepoResult.Success -> {
                    _uiState.update { st ->
                        st.copy(
                            otherProfile = st.otherProfile.copy(
                                reportSheet = st.otherProfile.reportSheet.copy(
                                    step = 3,
                                    isSubmitting = false
                                )
                            )
                        )
                    }
                }
                is RepoResult.Failure -> {
                    _uiState.update { st ->
                        st.copy(
                            otherProfile = st.otherProfile.copy(
                                reportSheet = st.otherProfile.reportSheet.copy(isSubmitting = false),
                                toastMessage = res.userMessage
                            )
                        )
                    }
                }
            }
        }
    }

    fun closeOtherReportSheet() {
        _uiState.update { st ->
            st.copy(
                otherProfile = st.otherProfile.copy(reportSheet = UserReportSheetState())
            )
        }
    }

    fun openOtherProfileItem(item: OwnerProfileItemDto) {
        val inst = _uiState.value.otherProfile.top ?: return
        val items = inst.itemsByCategory[inst.activeCategory].orEmpty()
        if (item.video != null) {
            val videoList = items.mapNotNull { it.video }
            val idx = videoList.indexOfFirst { it.videoId == item.video.videoId }.coerceAtLeast(0)
            val displayName = inst.profile?.let { p -> p.nickname.ifBlank { p.fullName } }.orEmpty()
            val title = when (inst.activeCategory) {
                OtherProfileTab.POSTS -> if (displayName.isNotBlank()) "$displayName · Posts" else "Posts"
                OtherProfileTab.REPOSTS -> if (displayName.isNotBlank()) "$displayName · Reposts" else "Reposts"
            }
            feedController.openModalFeedPlayer(title, videoList, idx)
            return
        }
        updateOtherInstance(inst.userId) { it.copy(activeViewerItem = item) }
        if (item.postId.isNotBlank() && networkQuality.value == NetworkQuality.ONLINE) {
            viewModelScope.launch {
                when (val res = repository.engagePost(item.postId, "view", true)) {
                    is RepoResult.Success -> {
                        patchOtherItem(inst.userId, item.postId) { cur ->
                            cur.copy(likesCount = res.data.likesCount, viewsCount = res.data.viewsCount)
                        }
                    }
                    is RepoResult.Failure -> Unit
                }
            }
        }
    }

    fun closeOtherProfileItemViewer() {
        val topId = _uiState.value.otherProfile.top?.userId ?: return
        updateOtherInstance(topId) { it.copy(activeViewerItem = null) }
    }

    fun toggleOtherPostLike(item: OwnerProfileItemDto) {
        val topId = _uiState.value.otherProfile.top?.userId ?: return
        val postId = item.postId.ifBlank { return }
        val next = !item.isLiked
        patchOtherItem(topId, postId) { cur ->
            cur.copy(
                isLiked = next,
                likesCount = (cur.likesCount + if (next) 1L else -1L).coerceAtLeast(0L)
            )
        }
        viewModelScope.launch {
            when (val res = repository.engagePost(postId, "like", next)) {
                is RepoResult.Success -> {
                    patchOtherItem(topId, postId) { cur ->
                        cur.copy(likesCount = res.data.likesCount, viewsCount = res.data.viewsCount)
                    }
                }
                is RepoResult.Failure -> Unit
            }
        }
    }

    fun toggleOtherPostSave(item: OwnerProfileItemDto) {
        val topId = _uiState.value.otherProfile.top?.userId ?: return
        val postId = item.postId.ifBlank { return }
        val next = !item.isSaved
        patchOtherItem(topId, postId) { cur -> cur.copy(isSaved = next) }
        viewModelScope.launch {
            repository.engagePost(postId, "save", next)
            loadOwnerProfileItemsInternal(OwnerProfileTab.SAVED)
        }
    }

    fun showOtherProfileToast(message: String) {
        _uiState.update {
            it.copy(otherProfile = it.otherProfile.copy(toastMessage = message))
        }
    }

    fun clearOtherProfileToast() {
        _uiState.update {
            it.copy(otherProfile = it.otherProfile.copy(toastMessage = null))
        }
    }

    private fun updateOtherInstance(
        userId: String,
        transform: (OtherProfileInstanceState) -> OtherProfileInstanceState
    ) {
        _uiState.update { st ->
            val idx = st.otherProfile.stack.indexOfLast { it.userId == userId }
            if (idx < 0) return@update st
            val mutable = st.otherProfile.stack.toMutableList()
            mutable[idx] = transform(mutable[idx])
            st.copy(otherProfile = st.otherProfile.copy(stack = mutable))
        }
    }

    private fun patchOtherItem(
        userId: String,
        postId: String,
        transform: (OwnerProfileItemDto) -> OwnerProfileItemDto
    ) {
        updateOtherInstance(userId) { inst ->
            val updatedMap = inst.itemsByCategory.mapValues { (_, list) ->
                list.map { if (it.postId == postId) transform(it) else it }
            }
            val updatedViewer = inst.activeViewerItem?.let { v ->
                if (v.postId == postId) transform(v) else v
            }
            inst.copy(itemsByCategory = updatedMap, activeViewerItem = updatedViewer)
        }
    }

    fun refreshFeedPosts(query: String = _uiState.value.searchQuery) {
        val sess = _uiState.value.session ?: return
        if (!sess.profileCompleted || networkQuality.value == NetworkQuality.OFFLINE) return
        viewModelScope.launch {
            _uiState.update { it.copy(isLoadingFeed = true) }
            when (val res = repository.fetchFeedPosts(query)) {
                is RepoResult.Success -> _uiState.update {
                    it.copy(feedPosts = res.data, isLoadingFeed = false)
                }
                is RepoResult.Failure -> _uiState.update { it.copy(isLoadingFeed = false) }
            }
        }
    }

    fun refreshNotifications() {
        val sess = _uiState.value.session ?: return
        if (!sess.profileCompleted || networkQuality.value == NetworkQuality.OFFLINE) return
        viewModelScope.launch {
            _uiState.update { it.copy(isLoadingNotifications = true) }
            when (val res = repository.fetchNotifications()) {
                is RepoResult.Success -> _uiState.update {
                    it.copy(notifications = res.data, isLoadingNotifications = false)
                }
                is RepoResult.Failure -> _uiState.update { it.copy(isLoadingNotifications = false) }
            }
        }
    }

    fun markNotificationsRead() {
        viewModelScope.launch {
            if (repository.markNotificationsRead()) {
                _uiState.update { st ->
                    st.copy(notifications = st.notifications.map { it.copy(isRead = true) })
                }
            }
        }
    }

    fun openEditProfile() {
        val existing = _uiState.value.myProfile
        val suggestedIso = existing?.countryIso?.takeIf { it.isNotBlank() } ?: repository.suggestDeviceCountryIso()
        val dobParts = existing?.dateOfBirth?.split("-")
        val by = dobParts?.getOrNull(0)?.toIntOrNull()
        val bm = dobParts?.getOrNull(1)?.toIntOrNull()
        val bd = dobParts?.getOrNull(2)?.toIntOrNull()
        _uiState.update { st ->
            st.copy(
                isEditingProfile = true,
                profileSetup = ProfileSetupState(
                    fullName = existing?.fullName?.takeIf { it.isNotBlank() } ?: st.session?.displayName.orEmpty(),
                    username = existing?.username.orEmpty(),
                    countryIso = suggestedIso,
                    phoneNumber = existing?.phoneNumber.orEmpty(),
                    gender = existing?.gender.orEmpty(),
                    birthYear = by,
                    birthMonth = bm,
                    birthDay = bd,
                    location = existing?.location.orEmpty(),
                    bio = existing?.bio.orEmpty(),
                    avatarBitmap = st.profileSetup.avatarBitmap,
                    avatarFingerprintHash = existing?.avatarFingerprintHash.orEmpty()
                )
            )
        }
        refreshMyProfile()
    }

    fun closeEditProfile() {
        _uiState.update { it.copy(isEditingProfile = false) }
    }

    fun selectContactFilter(filter: ContactFilter) {
        _uiState.update {
            it.copy(contactFilter = filter, contactsNextCursor = "", hasMoreContacts = false)
        }
        refreshContacts(reset = true)
    }

    fun updateContactSearchQuery(query: String) {
        _uiState.update { it.copy(contactSearchQuery = query) }
        contactsSearchJob?.cancel()
        contactsSearchJob = viewModelScope.launch {
            delay(280L)
            refreshContacts(reset = true)
        }
    }

    fun loadMoreContacts() {
        val st = _uiState.value
        if (st.isLoadingContacts || !st.hasMoreContacts || st.contactsNextCursor.isBlank()) return
        refreshContacts(reset = false)
    }

    fun refreshContacts(reset: Boolean) {
        val st = _uiState.value
        val sess = st.session ?: return
        if (!sess.profileCompleted) return
        if (networkQuality.value == NetworkQuality.OFFLINE) {
            _uiState.update { it.copy(isLoadingContacts = false) }
            return
        }
        val cursor = if (reset) "" else st.contactsNextCursor
        viewModelScope.launch {
            _uiState.update { it.copy(isLoadingContacts = true) }
            when (val res = repository.fetchContactsPage(
                filter = st.contactFilter.apiValue,
                query = st.contactSearchQuery,
                cursor = cursor,
                limit = 30
            )) {
                is RepoResult.Success -> {
                    _uiState.update {
                        it.copy(
                            isLoadingContacts = false,
                            hasMoreContacts = res.data.hasMore,
                            contactsNextCursor = res.data.nextCursor
                        )
                    }
                }
                is RepoResult.Failure -> {
                    _uiState.update { it.copy(isLoadingContacts = false) }
                }
            }
        }
    }

    fun toggleFollow(contact: ContactModel) {
        viewModelScope.launch {
            when (val res = repository.toggleFollowOfflineFirst(contact, networkQuality.value)) {
                is RepoResult.Success -> Unit
                is RepoResult.Failure -> {
                    _uiState.update { it.copy(contactsToastMessage = res.userMessage) }
                }
            }
        }
    }

    fun clearContactsToast() {
        _uiState.update { it.copy(contactsToastMessage = null) }
    }

    fun selectConversation(conversationId: String?) {
        _uiState.update { it.copy(selectedConversationId = conversationId) }
        if (conversationId != null) {
            viewModelScope.launch {
                repository.syncPendingAndRefresh(networkQuality.value, conversationId)
            }
        }
    }

    fun createConversation(title: String) {
        viewModelScope.launch {
            when (val res = repository.createConversationOfflineFirst(title, networkQuality.value)) {
                is RepoResult.Success -> selectConversation(res.data)
                is RepoResult.Failure -> Unit
            }
        }
    }

    fun sendMessage(body: String) {
        val cid = _uiState.value.selectedConversationId ?: return
        viewModelScope.launch {
            repository.sendMessageOfflineFirst(cid, body, networkQuality.value)
        }
    }

    fun deleteMessage(messageId: String) {
        viewModelScope.launch {
            repository.deleteMessageOfflineFirst(messageId, networkQuality.value)
        }
    }

    fun openPostComposer() {
        feedPlayerController.pause()
        _uiState.update {
            it.copy(
                postComposer = it.postComposer.copy(
                    isOpen = true,
                    uploadStatus = PostUploadStatus.IDLE,
                    uploadProgress = 0,
                    inlineError = null
                )
            )
        }
        if (_uiState.value.postComposer.songResults.isEmpty()) {
            searchSongs("")
        }
        if (_uiState.value.postComposer.hashtagResults.isEmpty()) {
            searchHashtags("")
        }
    }

    fun openPostComposerWithAudio(audio: AudioSummaryDto) {
        feedPlayerController.pause()
        val track = MusicTrackDto(
            trackId = audio.externalTrackId.ifBlank { audio.audioId },
            title = audio.title,
            artist = audio.artist,
            artworkUrl = audio.artworkUrl,
            previewUrl = audio.previewUrl,
            durationSec = ((audio.durationMs / 1000L).toInt()).coerceAtLeast(15)
        )
        _uiState.update {
            it.copy(
                postComposer = PostComposerState(
                    isOpen = true,
                    mode = PostTabMode.VIDEO,
                    selectedSong = track
                )
            )
        }
        searchSongs(audio.title)
        searchHashtags("")
    }

    fun closePostComposer() {
        stopSongPreviewInternal()
        _uiState.update {
            it.copy(postComposer = PostComposerState())
        }
        if (_uiState.value.activeTab == HomeTab.FEEDS) {
            feedController.playActiveFeedVideoIfAvailable()
        }
    }

    fun selectPostMode(mode: PostTabMode) {
        _uiState.update {
            it.copy(postComposer = it.postComposer.copy(mode = mode, inlineError = null))
        }
    }

    fun updatePostTextBody(text: String) {
        val clipped = text.take(280)
        _uiState.update {
            it.copy(postComposer = it.postComposer.copy(textBody = clipped))
        }
    }

    fun updatePostCaption(caption: String) {
        val clipped = caption.take(2200)
        _uiState.update {
            it.copy(postComposer = it.postComposer.copy(caption = clipped))
        }
    }

    fun togglePostPaletteMode(showImageThemes: Boolean) {
        _uiState.update {
            it.copy(postComposer = it.postComposer.copy(showImageThemes = showImageThemes))
        }
    }

    fun selectPostBgColor(hex: String) {
        _uiState.update {
            it.copy(
                postComposer = it.postComposer.copy(
                    selectedBgColorHex = hex,
                    selectedImageThemeId = null
                )
            )
        }
    }

    fun selectPostImageTheme(themeId: String) {
        _uiState.update {
            it.copy(
                postComposer = it.postComposer.copy(
                    selectedImageThemeId = themeId
                )
            )
        }
    }

    fun selectPostFont(font: PostFontStyle) {
        _uiState.update {
            it.copy(postComposer = it.postComposer.copy(selectedFont = font))
        }
    }

    fun addSelectedPhotos(uris: List<Uri>) {
        if (uris.isEmpty()) return
        viewModelScope.launch {
            _uiState.update {
                it.copy(postComposer = it.postComposer.copy(isExtractingMedia = true, inlineError = null))
            }
            val current = _uiState.value.postComposer.selectedPhotos.toMutableList()
            val remaining = (10 - current.size).coerceAtLeast(0)
            for (uri in uris.take(remaining)) {
                if (current.any { it.uri == uri }) continue
                val item = repository.loadPhotoPreviewItem(uri)
                if (item != null) {
                    current.add(item)
                }
            }
            _uiState.update {
                it.copy(
                    postComposer = it.postComposer.copy(
                        selectedPhotos = current.take(10),
                        isExtractingMedia = false
                    )
                )
            }
        }
    }

    fun removeSelectedPhoto(uri: Uri) {
        _uiState.update {
            it.copy(
                postComposer = it.postComposer.copy(
                    selectedPhotos = it.postComposer.selectedPhotos.filterNot { item -> item.uri == uri }
                )
            )
        }
    }

    fun selectPostVideo(uri: Uri) {
        viewModelScope.launch {
            _uiState.update {
                it.copy(postComposer = it.postComposer.copy(isExtractingMedia = true, inlineError = null))
            }
            val info = repository.extractVideoMetadataAndFrames(uri)
            if (info == null) {
                _uiState.update {
                    it.copy(
                        postComposer = it.postComposer.copy(
                            isExtractingMedia = false,
                            inlineError = repository.bridge.sanitizeError(400)
                        )
                    )
                }
                return@launch
            }
            val maxBytes = 200L * 1024L * 1024L
            if (info.sizeBytes > maxBytes) {
                _uiState.update {
                    it.copy(
                        postComposer = it.postComposer.copy(
                            isExtractingMedia = false,
                            inlineError = "Max 200 MB"
                        )
                    )
                }
                return@launch
            }
            val autoThumb = info.frames.getOrNull(info.frames.size / 2) ?: info.frames.firstOrNull()
            _uiState.update {
                it.copy(
                    postComposer = it.postComposer.copy(
                        videoUri = uri,
                        videoSizeBytes = info.sizeBytes,
                        videoDurationMs = info.durationMs,
                        videoFrames = info.frames,
                        trimStartMs = 0L,
                        trimEndMs = info.durationMs,
                        selectedThumbTimestampMs = autoThumb?.timestampMs ?: 0L,
                        selectedThumbBitmap = autoThumb?.thumbnail,
                        isExtractingMedia = false,
                        inlineError = null
                    )
                )
            }
        }
    }

    fun clearSelectedVideo() {
        _uiState.update {
            it.copy(
                postComposer = it.postComposer.copy(
                    videoUri = null,
                    videoSizeBytes = 0L,
                    videoDurationMs = 0L,
                    videoFrames = emptyList(),
                    trimStartMs = 0L,
                    trimEndMs = 0L,
                    selectedThumbTimestampMs = 0L,
                    selectedThumbBitmap = null,
                    inlineError = null
                )
            )
        }
    }

    fun updateVideoTrim(startMs: Long, endMs: Long) {
        val dur = _uiState.value.postComposer.videoDurationMs.coerceAtLeast(1000L)
        val safeStart = startMs.coerceIn(0L, dur - 500L)
        val safeEnd = endMs.coerceIn(safeStart + 500L, dur)
        _uiState.update {
            it.copy(
                postComposer = it.postComposer.copy(
                    trimStartMs = safeStart,
                    trimEndMs = safeEnd
                )
            )
        }
    }

    fun selectVideoThumbnailFrame(frame: VideoFrameItem) {
        _uiState.update {
            it.copy(
                postComposer = it.postComposer.copy(
                    selectedThumbTimestampMs = frame.timestampMs,
                    selectedThumbBitmap = frame.thumbnail
                )
            )
        }
    }

    fun autoSelectVideoThumbnail() {
        val frames = _uiState.value.postComposer.videoFrames
        if (frames.isEmpty()) return
        val trimStart = _uiState.value.postComposer.trimStartMs
        val trimEnd = _uiState.value.postComposer.trimEndMs
        val midTs = (trimStart + trimEnd) / 2L
        val best = frames.minByOrNull { kotlin.math.abs(it.timestampMs - midTs) } ?: frames.first()
        selectVideoThumbnailFrame(best)
    }

    fun toggleMuteOriginalAudio() {
        _uiState.update {
            it.copy(
                postComposer = it.postComposer.copy(
                    muteOriginalAudio = !it.postComposer.muteOriginalAudio
                )
            )
        }
    }

    fun searchSongs(query: String) {
        _uiState.update { it.copy(postComposer = it.postComposer.copy(songQuery = query)) }
        songSearchJob?.cancel()
        songSearchJob = viewModelScope.launch {
            if (query.isNotBlank()) delay(280L)
            _uiState.update { it.copy(postComposer = it.postComposer.copy(isSearchingSongs = true)) }
            when (val res = repository.searchPublicSongs(query)) {
                is RepoResult.Success -> {
                    _uiState.update {
                        it.copy(
                            postComposer = it.postComposer.copy(
                                songResults = res.data,
                                isSearchingSongs = false
                            )
                        )
                    }
                }
                is RepoResult.Failure -> {
                    _uiState.update {
                        it.copy(postComposer = it.postComposer.copy(isSearchingSongs = false))
                    }
                }
            }
        }
    }

    fun selectSong(track: MusicTrackDto?) {
        stopSongPreviewInternal()
        _uiState.update {
            it.copy(postComposer = it.postComposer.copy(selectedSong = track))
        }
    }

    fun toggleSongPreview(track: MusicTrackDto) {
        if (track.previewUrl.isBlank()) return
        val currentId = _uiState.value.postComposer.previewingTrackId
        val isPlaying = _uiState.value.postComposer.isPlayingSongPreview
        if (currentId == track.trackId && isPlaying) {
            stopSongPreviewInternal()
            return
        }
        stopSongPreviewInternal()
        runCatching {
            val player = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .build()
                )
                setDataSource(track.previewUrl)
                setOnPreparedListener { mp ->
                    mp.start()
                    _uiState.update {
                        it.copy(
                            postComposer = it.postComposer.copy(
                                isPlayingSongPreview = true,
                                previewingTrackId = track.trackId
                            )
                        )
                    }
                }
                setOnCompletionListener {
                    stopSongPreviewInternal()
                }
                setOnErrorListener { _, _, _ ->
                    stopSongPreviewInternal()
                    true
                }
                prepareAsync()
            }
            mediaPlayer = player
        }.onFailure {
            stopSongPreviewInternal()
        }
    }

    private fun stopSongPreviewInternal() {
        runCatching {
            mediaPlayer?.stop()
        }
        runCatching {
            mediaPlayer?.release()
        }
        mediaPlayer = null
        _uiState.update {
            it.copy(
                postComposer = it.postComposer.copy(
                    isPlayingSongPreview = false,
                    previewingTrackId = null
                )
            )
        }
    }

    fun toggleTagContact(contact: ContactModel) {
        _uiState.update { st ->
            val current = st.postComposer.taggedContacts
            val updated = if (current.any { it.userId == contact.userId }) {
                current.filterNot { it.userId == contact.userId }
            } else {
                current + contact
            }
            st.copy(postComposer = st.postComposer.copy(taggedContacts = updated))
        }
    }

    fun searchHashtags(query: String) {
        _uiState.update { it.copy(postComposer = it.postComposer.copy(hashtagQuery = query)) }
        hashtagSearchJob?.cancel()
        hashtagSearchJob = viewModelScope.launch {
            if (query.isNotBlank()) delay(220L)
            _uiState.update { it.copy(postComposer = it.postComposer.copy(isSearchingHashtags = true)) }
            when (val res = repository.searchHashtags(query)) {
                is RepoResult.Success -> {
                    _uiState.update {
                        it.copy(
                            postComposer = it.postComposer.copy(
                                hashtagResults = res.data,
                                isSearchingHashtags = false
                            )
                        )
                    }
                }
                is RepoResult.Failure -> {
                    _uiState.update {
                        it.copy(postComposer = it.postComposer.copy(isSearchingHashtags = false))
                    }
                }
            }
        }
    }

    fun toggleHashtag(rawTag: String) {
        val clean = rawTag.trim().removePrefix("#").lowercase().filter { it.isLetterOrDigit() || it == '_' }
        if (clean.isBlank()) return
        _uiState.update { st ->
            val current = st.postComposer.selectedHashtags
            val updated = if (current.contains(clean)) {
                current.filterNot { it == clean }
            } else if (current.size < 20) {
                current + clean
            } else {
                current
            }
            st.copy(postComposer = st.postComposer.copy(selectedHashtags = updated))
        }
    }

    fun shareCurrentPost() {
        val pc = _uiState.value.postComposer
        if (!pc.canShare) return
        stopSongPreviewInternal()

        val bodyText = if (pc.mode == PostTabMode.TEXT) pc.textBody.trim() else pc.caption.trim()
        val draft = QueuedPostPayload(
            queueId = UUID.randomUUID().toString(),
            postType = pc.mode.apiValue,
            body = bodyText,
            bgColorHex = if (pc.selectedImageThemeId == null) pc.selectedBgColorHex else "",
            bgThemeId = pc.selectedImageThemeId.orEmpty(),
            fontFamily = pc.selectedFont.id,
            songId = pc.selectedSong?.trackId.orEmpty(),
            songTitle = pc.selectedSong?.title.orEmpty(),
            songArtist = pc.selectedSong?.artist.orEmpty(),
            songPreviewUrl = pc.selectedSong?.previewUrl.orEmpty(),
            muteOriginalAudio = pc.muteOriginalAudio,
            trimStartMs = pc.trimStartMs,
            trimEndMs = pc.trimEndMs,
            thumbnailAtMs = pc.selectedThumbTimestampMs,
            taggedUserIds = pc.taggedContacts.map { it.userId },
            hashtags = pc.selectedHashtags
        )

        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    postComposer = it.postComposer.copy(
                        uploadStatus = PostUploadStatus.UPLOADING,
                        uploadProgress = 1,
                        inlineError = null
                    )
                )
            }
            val res = repository.submitOrQueuePost(
                draft = draft,
                photoUris = pc.selectedPhotos.map { it.uri },
                videoUri = pc.videoUri,
                thumbBitmap = pc.selectedThumbBitmap,
                quality = networkQuality.value
            ) { pct ->
                _uiState.update {
                    it.copy(postComposer = it.postComposer.copy(uploadProgress = pct.coerceIn(1, 100)))
                }
            }
            when (res) {
                is RepoResult.Success -> {
                    val status = if (res.data == "queued") PostUploadStatus.QUEUED else PostUploadStatus.UPLOADED
                    _uiState.update {
                        it.copy(
                            postComposer = it.postComposer.copy(
                                uploadStatus = status,
                                uploadProgress = 100
                            )
                        )
                    }
                    delay(750L)
                    closePostComposer()
                    refreshFeedPosts()
                    refreshOwnerProfile(isPullGesture = false)
                    feedController.refreshActiveFeed()
                }
                is RepoResult.Failure -> {
                    _uiState.update {
                        it.copy(
                            postComposer = it.postComposer.copy(
                                uploadStatus = PostUploadStatus.ERROR,
                                inlineError = res.userMessage
                            )
                        )
                    }
                }
            }
        }
    }

    fun signOut() {
        viewModelScope.launch {
            stopSongPreviewInternal()
            feedController.resetOnSignOut()
            repository.logoutFromServer()
            val dark = _uiState.value.isDarkTheme
            _uiState.update {
                TelefamUiState(initialized = true, isDarkTheme = dark)
            }
        }
    }

    private fun startCooldownTicker(seconds: Long) {
        cooldownTickerJob?.cancel()
        _uiState.update { it.copy(cooldownSeconds = seconds.coerceAtLeast(0L)) }
        if (seconds <= 0L) return
        cooldownTickerJob = viewModelScope.launch {
            var rem = seconds
            while (rem > 0) {
                delay(1000L)
                rem -= 1
                _uiState.update { it.copy(cooldownSeconds = rem) }
            }
        }
    }

    class Factory(
        private val repository: TelefamRepository,
        private val feedRepository: FeedRepository,
        private val networkMonitor: AndroidNetworkMonitor,
        private val feedPlayerController: FeedPlayerController
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            return TelefamViewModel(repository, feedRepository, networkMonitor, feedPlayerController) as T
        }
    }
}
