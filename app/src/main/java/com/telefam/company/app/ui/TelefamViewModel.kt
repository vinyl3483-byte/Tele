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
        onUseAudioInPost = { audio -> openPostComposerWithAudio(audio) }
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
            _uiState.map { it.contactFilter to it.contactSearchQuery }.distinctUntilChanged()
        ) { cached, (filter, rawQuery) ->
            val q = rawQuery.trim().lowercase()
            cached.filter { item ->
                val matchesFilter = when (filter) {
                    ContactFilter.ALL -> true
                    ContactFilter.SUGGESTIONS -> !item.isFollowing
                    ContactFilter.FOLLOWERS -> item.followsMe
                    ContactFilter.FOLLOWING -> item.isFollowing
                    ContactFilter.FRIENDS -> item.isFollowing && item.followsMe
                }
                val matchesQuery = q.isEmpty() ||
                    item.fullName.lowercase().contains(q) ||
                    item.username.lowercase().contains(q)
                matchesFilter && matchesQuery
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
            val cachedFeed = repository.loadCachedFeedPosts()
            val cachedNotifs = repository.loadCachedNotifications()
            val prefill = saved?.let { seedProfileSetup(it.email, suggestedIso) }
                ?: ProfileSetupState(countryIso = suggestedIso)
            _uiState.update {
                it.copy(
                    initialized = true,
                    isDarkTheme = dark,
                    session = saved,
                    myProfile = cachedProfile,
                    feedPosts = cachedFeed,
                    notifications = cachedNotifs,
                    profileSetup = prefill
                )
            }
            if (saved != null && saved.profileCompleted) {
                repository.syncPendingAndRefresh(networkQuality.value, _uiState.value.selectedConversationId)
                refreshContacts(reset = true)
                refreshMyProfile()
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
            it.copy(profileSetup = it.profileSetup.copy(avatarBitmap = bitmap, errorMessage = null))
        }
        viewModelScope.launch {
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
            val bytes = out.toByteArray()
            if (networkQuality.value == NetworkQuality.ONLINE) {
                when (val res = repository.uploadSanitizedAvatar(bytes)) {
                    is RepoResult.Success -> {
                        _uiState.update {
                            it.copy(profileSetup = it.profileSetup.copy(avatarFingerprintHash = res.data))
                        }
                    }
                    is RepoResult.Failure -> Unit
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
                    _uiState.update {
                        it.copy(
                            session = res.data,
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
                refreshMyProfile()
                feedController.refreshSavedVideos()
                feedController.refreshSafetyPreferences()
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
                is RepoResult.Success -> _uiState.update { it.copy(myProfile = res.data) }
                is RepoResult.Failure -> Unit
            }
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
