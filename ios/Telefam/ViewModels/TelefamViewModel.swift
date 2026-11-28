import Foundation
import Combine
import UIKit
import AVFoundation
import CoreGraphics

enum AuthStep {
    case enterEmail
    case enterOTP
}

enum HomeTabIOS {
    case chats
    case contacts
    case feeds
    case profile
}

enum PostTabModeIOS: String, CaseIterable, Identifiable {
    case text = "text"
    case photos = "photos"
    case video = "video"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .text: return "Text"
        case .photos: return "Photos"
        case .video: return "Video"
        }
    }
}

enum PostUploadStatusIOS {
    case idle
    case uploading
    case uploaded
    case queued
    case error
}

struct ExtractedPhotoIOS: Identifiable, Equatable {
    let id: String
    let jpegData: Data
    let uiImage: UIImage
    let width: Int
    let height: Int
    let dhash: String
    let contentId: String

    static func == (lhs: ExtractedPhotoIOS, rhs: ExtractedPhotoIOS) -> Bool {
        lhs.id == rhs.id && lhs.contentId == rhs.contentId
    }
}

struct VideoFrameIOS: Identifiable, Equatable {
    let timestampMs: Int64
    let uiImage: UIImage
    let jpegData: Data
    let dhash: String
    var id: Int64 { timestampMs }

    static func == (lhs: VideoFrameIOS, rhs: VideoFrameIOS) -> Bool {
        lhs.timestampMs == rhs.timestampMs && lhs.dhash == rhs.dhash
    }
}

struct QueuedPostDraftIOS: Codable, Identifiable {
    let queue_id: String
    let post_type: String
    let body: String
    let bg_color_hex: String
    let bg_theme_id: String
    let font_family: String
    let song_id: String
    let song_title: String
    let song_artist: String
    let song_preview_url: String
    let mute_original_audio: Bool
    let trim_start_ms: Int64
    let trim_end_ms: Int64
    let thumbnail_at_ms: Int64
    let tagged_user_ids: [String]
    let hashtags: [String]
    let photo_filenames: [String]
    let video_filename: String
    let thumb_filename: String
    let created_at_ms: Int64
    var id: String { queue_id }
}

enum ContactFilterIOS: String, CaseIterable, Identifiable {
    case all = "all"
    case suggestions = "suggestions"
    case followers = "followers"
    case following = "following"
    case friends = "friends"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .suggestions: return "Suggestions"
        case .followers: return "Followers"
        case .following: return "Following"
        case .friends: return "Friends"
        }
    }
}

struct CountryCodeOption: Identifiable, Hashable {
    let iso: String
    let dialCode: String
    let flag: String
    let name: String
    var id: String { iso }
}

let SUPPORTED_COUNTRIES_IOS: [CountryCodeOption] = [
    CountryCodeOption(iso: "KE", dialCode: "+254", flag: "🇰🇪", name: "Kenya"),
    CountryCodeOption(iso: "US", dialCode: "+1", flag: "🇺🇸", name: "United States"),
    CountryCodeOption(iso: "GB", dialCode: "+44", flag: "🇬🇧", name: "United Kingdom"),
    CountryCodeOption(iso: "CA", dialCode: "+1", flag: "🇨🇦", name: "Canada"),
    CountryCodeOption(iso: "NG", dialCode: "+234", flag: "🇳🇬", name: "Nigeria"),
    CountryCodeOption(iso: "ZA", dialCode: "+27", flag: "🇿🇦", name: "South Africa"),
    CountryCodeOption(iso: "TZ", dialCode: "+255", flag: "🇹🇿", name: "Tanzania"),
    CountryCodeOption(iso: "UG", dialCode: "+256", flag: "🇺🇬", name: "Uganda"),
    CountryCodeOption(iso: "RW", dialCode: "+250", flag: "🇷🇼", name: "Rwanda"),
    CountryCodeOption(iso: "ET", dialCode: "+251", flag: "🇪🇹", name: "Ethiopia"),
    CountryCodeOption(iso: "IN", dialCode: "+91", flag: "🇮🇳", name: "India"),
    CountryCodeOption(iso: "DE", dialCode: "+49", flag: "🇩🇪", name: "Germany"),
    CountryCodeOption(iso: "FR", dialCode: "+33", flag: "🇫🇷", name: "France"),
    CountryCodeOption(iso: "AE", dialCode: "+971", flag: "🇦🇪", name: "UAE"),
    CountryCodeOption(iso: "AU", dialCode: "+61", flag: "🇦🇺", name: "Australia"),
    CountryCodeOption(iso: "JP", dialCode: "+81", flag: "🇯🇵", name: "Japan"),
    CountryCodeOption(iso: "BR", dialCode: "+55", flag: "🇧🇷", name: "Brazil")
]

@MainActor
final class TelefamViewModel: ObservableObject {
    @Published var isDarkTheme: Bool = true
    @Published var authStep: AuthStep = .enterEmail
    @Published var email: String = ""
    @Published var otpDigits: [String] = Array(repeating: "", count: 6)
    @Published var cooldownSeconds: Int64 = 0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    @Published var session: AuthSessionPayload?
    @Published var conversations: [ConversationItem] = []
    @Published var selectedConversationId: String?
    @Published var messages: [ChatMessageItem] = []
    @Published var pendingSyncCount: Int32 = 0

    // Contacts, Feeds, Profile & Notifications state
    @Published var activeTab: HomeTabIOS = .chats
    @Published var homeSearchQuery: String = ""
    @Published var contactFilter: ContactFilterIOS = .all
    @Published var contactSearchQuery: String = ""
    @Published var cachedContacts: [ContactUserItem] = []
    @Published var isLoadingContacts: Bool = false
    @Published var hasMoreContacts: Bool = false
    @Published var contactsNextCursor: String = ""
    @Published var contactsToastMessage: String?

    @Published var isEditingProfile: Bool = false
    @Published var myProfile: MyProfilePayload? = nil
    @Published var feedPosts: [FeedPostItem] = []
    @Published var isLoadingFeed: Bool = false
    @Published var notifications: [NotificationItem] = []
    @Published var isLoadingNotifications: Bool = false

    // Short-video Feed, Discovery, Search, Safety & Modals
    @Published var videoFeedTab: String = "for_you" // "for_you" | "following"
    @Published var forYouVideos: [FeedVideoItem] = []
    @Published var followingVideos: [FeedVideoItem] = []
    @Published var forYouCursor: String = ""
    @Published var followingCursor: String = ""
    @Published var forYouHasMore: Bool = false
    @Published var followingHasMore: Bool = false
    @Published var isLoadingVideoFeed: Bool = false
    @Published var isRefreshingVideoFeed: Bool = false
    @Published var videoFeedError: String? = nil
    @Published var activeForYouIndex: Int = 0
    @Published var activeFollowingIndex: Int = 0

    @Published var showLiveComingSoon: Bool = false
    @Published var showFeedSearch: Bool = false
    @Published var feedSearchQuery: String = ""
    @Published var feedSearchTab: Int = 0 // 0=Videos, 1=Hashtags, 2=Creators, 3=Sounds
    @Published var isSearchingFeed: Bool = false
    @Published var feedSearchResults: FeedSearchPayload? = nil
    @Published var localRecentSearches: [String] = []

    @Published var activeHashtagTag: String? = nil
    @Published var hashtagDiscovery: HashtagDiscoveryPayload? = nil
    @Published var isLoadingHashtagDiscovery: Bool = false

    @Published var activeAudioId: String? = nil
    @Published var audioDiscovery: AudioDiscoveryPayload? = nil
    @Published var isLoadingAudioDiscovery: Bool = false

    @Published var modalFeedVideos: [FeedVideoItem] = []
    @Published var modalFeedInitialIndex: Int = 0
    @Published var modalFeedTitle: String = ""
    @Published var showModalFeedPlayer: Bool = false

    @Published var savedVideos: [FeedVideoItem] = []
    @Published var isLoadingSavedVideos: Bool = false
    @Published var safetyPreferences: SafetyPreferencesPayload = SafetyPreferencesPayload(muted_users: [], blocked_users: [])
    @Published var isLoadingSafetyPreferences: Bool = false

    @Published var feedPlaybackState: FeedPlaybackStateIOS = FeedPlaybackStateIOS()

    // Profile setup state
    @Published var fullName: String = ""
    @Published var username: String = ""
    @Published var countryIso: String = "KE"
    @Published var phoneNumber: String = ""
    @Published var gender: String = ""
    @Published var birthDate: Date = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @Published var hasSelectedDob: Bool = false
    @Published var locationText: String = ""
    @Published var bioText: String = ""
    @Published var avatarJPEGData: Data?
    @Published var avatarFingerprintHash: String = ""
    @Published var profileErrorMessage: String?
    @Published var isSubmittingProfile: Bool = false

    // Owner Profile screen state (locally cached avatar, up to 5 backgrounds, category grids)
    @Published var ownerActiveCategory: OwnerProfileTabIOS = .posts
    @Published var ownerItemsByCategory: [OwnerProfileTabIOS: [OwnerProfileItem]] = [:]
    @Published var isLoadingOwnerItems: Bool = false
    @Published var isRefreshingOwnerProfile: Bool = false
    @Published var isUploadingOwnerBackgrounds: Bool = false
    @Published var ownerLocalAvatarPath: String? = nil
    @Published var ownerLocalBackgroundPaths: [String] = []
    @Published var ownerConnectionsMode: String? = nil
    @Published var ownerConnectionsUsers: [ContactUserItem] = []
    @Published var isLoadingOwnerConnections: Bool = false
    @Published var activeOwnerViewerItem: OwnerProfileItem? = nil
    @Published var ownerProfileToast: String? = nil

    // New Post composer state
    @Published var isPostComposerOpen: Bool = false
    @Published var postMode: PostTabModeIOS = .text
    @Published var postTextBody: String = ""
    @Published var postCaption: String = ""
    @Published var postShowImageThemes: Bool = false
    @Published var postBgColorHex: String = "#C81010"
    @Published var postImageThemeId: String? = nil
    @Published var postFont: PostFontStyleIOS = .classic
    @Published var postPhotos: [ExtractedPhotoIOS] = []
    @Published var postVideoURL: URL? = nil
    @Published var postVideoSizeBytes: Int64 = 0
    @Published var postVideoDurationMs: Int64 = 0
    @Published var postVideoFrames: [VideoFrameIOS] = []
    @Published var postTrimStartMs: Int64 = 0
    @Published var postTrimEndMs: Int64 = 0
    @Published var postSelectedThumbMs: Int64 = 0
    @Published var postSelectedThumbImage: UIImage? = nil
    @Published var postSelectedThumbJPEG: Data? = nil
    @Published var postMuteOriginalAudio: Bool = false
    @Published var postSongQuery: String = ""
    @Published var postSongResults: [MusicTrackItem] = []
    @Published var postSelectedSong: MusicTrackItem? = nil
    @Published var postIsSearchingSongs: Bool = false
    @Published var postIsPlayingSongPreview: Bool = false
    @Published var postPreviewingTrackId: String? = nil
    @Published var postTaggedContacts: [ContactUserItem] = []
    @Published var postHashtagQuery: String = ""
    @Published var postHashtagResults: [HashtagItem] = []
    @Published var postSelectedHashtags: [String] = []
    @Published var postIsSearchingHashtags: Bool = false
    @Published var postIsExtractingMedia: Bool = false
    @Published var postUploadStatus: PostUploadStatusIOS = .idle
    @Published var postUploadProgress: Int = 0
    @Published var postInlineError: String? = nil

    var canSharePost: Bool {
        if postUploadStatus == .uploading { return false }
        switch postMode {
        case .text:
            return !postTextBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .photos:
            return !postPhotos.isEmpty
        case .video:
            return postVideoURL != nil && postVideoSizeBytes > 0 && postVideoSizeBytes <= (200 * 1024 * 1024)
        }
    }

    let core: TelefamCoreBridge
    let api: TelefamAPIClient
    let feedPlayback: FeedPlaybackManager
    let appleSignIn = AppleSignInCoordinator()
    let deviceFP: String
    let hwAttest: String
    let deviceName: String

    private var cooldownTimer: Timer?
    private var contactSearchTask: Task<Void, Never>?
    private var songSearchTask: Task<Void, Never>?
    private var hashtagSearchTask: Task<Void, Never>?
    var feedSearchTask: Task<Void, Never>?
    private var feedPlaybackCancellable: AnyCancellable?
    private var audioPlayer: AVPlayer?
    private var audioEndObserver: NSObjectProtocol?

    var filteredContacts: [ContactUserItem] {
        let q = contactSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return cachedContacts.filter { item in
            let matchesFilter: Bool
            switch contactFilter {
            case .all: matchesFilter = true
            case .suggestions: matchesFilter = !item.is_following
            case .followers: matchesFilter = item.follows_me
            case .following: matchesFilter = item.is_following
            case .friends: matchesFilter = item.is_following && item.follows_me
            }
            let matchesQuery = q.isEmpty ||
                item.full_name.lowercased().contains(q) ||
                item.username.lowercased().contains(q)
            return matchesFilter && matchesQuery
        }
    }

    var filteredConversations: [ConversationItem] {
        let q = homeSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return conversations }
        return conversations.filter { $0.title.lowercased().contains(q) }
    }

    var filteredFeedPosts: [FeedPostItem] {
        let q = homeSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return feedPosts }
        return feedPosts.filter { post in
            post.body.lowercased().contains(q) ||
                post.author_name.lowercased().contains(q) ||
                post.author_handle.lowercased().contains(q) ||
                (post.hashtags ?? []).contains { $0.lowercased().contains(q) }
        }
    }

    var unreadNotificationCount: Int {
        notifications.filter { !$0.is_read }.count
    }

    init() {
        let docs = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let vaultPath = docs.appendingPathComponent("telefam_vault.dat").path
        let masterKey = KeychainVault.loadOrCreateMasterKey()
        self.core = TelefamCoreBridge(vaultPath: vaultPath, masterKey: masterKey)
        let apiClient = TelefamAPIClient()
        self.api = apiClient
        self.feedPlayback = FeedPlaybackManager(resolveURL: { raw in
            apiClient.resolveMediaURL(raw)
        })

        let hwId = KeychainVault.loadOrCreateHardwareSecretId()
        let model = KeychainVault.hardwareModel()
        self.deviceName = KeychainVault.deviceName()
        self.deviceFP = TelefamCoreBridge.computeDeviceFingerprint(
            platformId: "ios",
            hardwareModel: model,
            deviceName: deviceName,
            hardwareSecretId: hwId
        )
        self.hwAttest = TelefamCoreBridge.computeDeviceFingerprint(
            platformId: "ios-attest",
            hardwareModel: model,
            deviceName: deviceName,
            hardwareSecretId: hwId
        )

        self.feedPlaybackCancellable = self.feedPlayback.$playbackState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] st in
                self?.feedPlaybackState = st
            }

        self.feedPlayback.onRefreshSignedURL = { [weak self] videoId in
            await self?.refreshSignedVideoStreamURL(videoId: videoId)
        }
        self.feedPlayback.onReportWatchProgress = { [weak self] videoId, watchMs, posMs, pct, rewatchDelta, isViewPing in
            Task { @MainActor [weak self] in
                await self?.sendWatchProgress(
                    videoId: videoId,
                    watchMs: watchMs,
                    positionMs: posMs,
                    completionPct: pct,
                    rewatchDelta: rewatchDelta,
                    isViewPing: isViewPing
                )
            }
        }

        restoreEncryptedSession()
        restoreEncryptedVideoFeedCaches()
        restoreOwnerProfileLocalCache()
    }

    func toggleTheme() {
        isDarkTheme.toggle()
        let val = isDarkTheme ? "true" : "false"
        if let data = val.data(using: .utf8) {
            let _ = core.vaultPut(key: "theme_dark", data: data)
        }
    }

    func sendOTP(isResend: Bool = false) async {
        errorMessage = nil
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TelefamCoreBridge.validateEmail(trimmed) else {
            errorMessage = "Please enter a valid email address."
            return
        }
        email = trimmed

        let ipFP = TelefamCoreBridge.computeIPFingerprint(observedIP: "client-edge", subnetPrefix: "local")
        guard core.allowRateLimit(accountKey: trimmed, deviceFP: deviceFP, ipFP: ipFP) else {
            errorMessage = TelefamCoreBridge.sanitizeError(httpStatus: 429)
            return
        }

        let snap = core.checkCooldown(email: trimmed)
        if !snap.canResend {
            startCooldownTicker(seconds: snap.remainingSeconds)
            authStep = .enterOTP
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let res = try await api.sendOTP(email: trimmed, deviceFP: deviceFP, hwAttest: hwAttest, deviceName: deviceName)
            let (_, recorded) = core.recordOTPSend(email: trimmed)
            let secs = max(res.cooldown_seconds, recorded.remainingSeconds)
            startCooldownTicker(seconds: secs)
            authStep = .enterOTP
        } catch let TelefamAPIError.sanitized(msg) {
            errorMessage = msg
        } catch {
            errorMessage = TelefamCoreBridge.sanitizeError(httpStatus: 0)
        }
    }

    func verifyOTP(magicToken: String? = nil) async {
        errorMessage = nil
        let code = otpDigits.joined()
        if magicToken == nil && !TelefamCoreBridge.validateOTP(code) {
            errorMessage = "Please enter the 6-digit verification code."
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let sess = try await api.verifyOTP(
                email: email,
                otp: code,
                magicToken: magicToken,
                deviceFP: deviceFP,
                hwAttest: hwAttest,
                deviceName: deviceName
            )
            persistSession(sess)
            core.resetCooldown(email: email)
            if !sess.profile_completed {
                seedProfileSetup(email: sess.email)
            } else {
                await syncAll(quality: .online)
            }
        } catch let TelefamAPIError.sanitized(msg) {
            errorMessage = msg
        } catch {
            errorMessage = TelefamCoreBridge.sanitizeError(httpStatus: 0)
        }
    }

    func signInWithApple() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let token = try await appleSignIn.signInWithApple()
            let sess = try await api.verifyOAuth(
                provider: "apple",
                idToken: token,
                deviceFP: deviceFP,
                hwAttest: hwAttest,
                deviceName: deviceName
            )
            persistSession(sess)
            if !sess.profile_completed {
                seedProfileSetup(email: sess.email)
            } else {
                await syncAll(quality: .online)
            }
        } catch let TelefamAPIError.sanitized(msg) {
            errorMessage = msg
        } catch {
            errorMessage = TelefamCoreBridge.sanitizeError(httpStatus: 401)
        }
    }

    func signInWithGoogle(idToken: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let sess = try await api.verifyOAuth(
                provider: "google",
                idToken: idToken,
                deviceFP: deviceFP,
                hwAttest: hwAttest,
                deviceName: deviceName
            )
            persistSession(sess)
            if !sess.profile_completed {
                seedProfileSetup(email: sess.email)
            } else {
                await syncAll(quality: .online)
            }
        } catch let TelefamAPIError.sanitized(msg) {
            errorMessage = msg
        } catch {
            errorMessage = TelefamCoreBridge.sanitizeError(httpStatus: 401)
        }
    }

    func seedProfileSetup(email: String) {
        let (fn, un) = TelefamCoreBridge.autofillProfileFromEmail(email)
        let tz = TimeZone.current.identifier
        let localeCountry = Locale.current.region?.identifier ?? ""
        let iso = TelefamCoreBridge.suggestCountryISO(carrierISO: "", timezoneId: tz, localeCountry: localeCountry)
        self.fullName = fn
        self.username = un
        self.countryIso = iso
        self.locationText = SUPPORTED_COUNTRIES_IOS.first(where: { $0.iso == iso })?.name ?? ""
        self.profileErrorMessage = nil
    }

    func setCroppedAvatar(jpegData: Data, quality: TelefamNetworkQuality) async {
        self.avatarJPEGData = jpegData
        self.profileErrorMessage = nil
        if let localPath = saveOwnerAvatarLocally(jpegData: jpegData) {
            self.ownerLocalAvatarPath = localPath
        }
        guard let sess = session, quality != .offline else { return }
        if let res = try? await api.uploadAvatar(token: sess.access_token, jpegData: jpegData) {
            self.avatarFingerprintHash = res.avatar_fingerprint_hash
            if let existing = myProfile {
                let updated = MyProfilePayload(
                    user_id: existing.user_id,
                    email: existing.email,
                    full_name: existing.full_name,
                    username: existing.username,
                    country_iso: existing.country_iso,
                    phone_number: existing.phone_number,
                    gender: existing.gender,
                    date_of_birth: existing.date_of_birth,
                    location: existing.location,
                    bio: existing.bio,
                    avatar_fingerprint_hash: res.avatar_fingerprint_hash,
                    profile_completed: existing.profile_completed,
                    avatar_url: existing.avatar_url,
                    followers_count: existing.followers_count,
                    following_count: existing.following_count,
                    posts_count: existing.posts_count,
                    views_count: existing.views_count,
                    likes_count: existing.likes_count,
                    background_photos: existing.background_photos
                )
                self.myProfile = updated
                persistCachedMyProfile(updated)
            }
        }
    }

    func submitProfileSetup(quality: TelefamNetworkQuality) async {
        profileErrorMessage = nil
        let fn = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let un = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard fn.count >= 2, un.count >= 3, !gender.isEmpty, hasSelectedDob else {
            profileErrorMessage = "Please complete all required fields."
            return
        }
        guard TelefamCoreBridge.validatePhoneNumber(countryISO: countryIso, nationalNumber: phoneNumber) else {
            profileErrorMessage = "Please enter a valid phone number for the selected country."
            return
        }
        let cal = Calendar.current
        let bComps = cal.dateComponents([.year, .month, .day], from: birthDate)
        let nComps = cal.dateComponents([.year, .month, .day], from: Date())
        guard let by = bComps.year, let bm = bComps.month, let bd = bComps.day,
              let ny = nComps.year, let nm = nComps.month, let nd = nComps.day,
              TelefamCoreBridge.validateAge13Plus(
                birthYear: Int32(by), birthMonth: Int32(bm), birthDay: Int32(bd),
                nowYear: Int32(ny), nowMonth: Int32(nm), nowDay: Int32(nd)
              ) else {
            profileErrorMessage = "You must be at least 13 years old."
            return
        }

        guard let currentSession = session else { return }
        let dobStr = String(format: "%04d-%02d-%02d", by, bm, bd)
        let req = ProfileSetupRequest(
            full_name: fn,
            username: un,
            country_iso: countryIso,
            phone_number: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            gender: gender,
            date_of_birth: dobStr,
            location: locationText.trimmingCharacters(in: .whitespacesAndNewlines),
            bio: String(bioText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(150)),
            avatar_fingerprint_hash: avatarFingerprintHash
        )

        var updated = currentSession
        updated.profile_completed = true

        if quality == .offline {
            if let data = try? JSONEncoder().encode(req),
               let json = String(data: data, encoding: .utf8) {
                let _ = core.enqueueMutation(id: UUID().uuidString, actionType: "profile_setup", payloadJSON: json)
                pendingSyncCount = core.pendingOutboxCount()
            }
            isEditingProfile = false
            persistSession(updated)
            return
        }

        isSubmittingProfile = true
        defer { isSubmittingProfile = false }
        do {
            let savedProfile = try await withAuthedRetry { tok in
                try await self.api.setupProfile(token: tok, request: req)
            }
            self.myProfile = savedProfile
            persistCachedMyProfile(savedProfile)
            updated.profile_completed = true
            isEditingProfile = false
            persistSession(updated)
            await syncAll(quality: quality)
        } catch let err as TelefamAPIError {
            profileErrorMessage = err.message
        } catch {
            profileErrorMessage = TelefamCoreBridge.sanitizeError(httpStatus: 0)
        }
    }

    func sendMessageOfflineFirst(conversationId: String, body: String) async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let sess = session else { return }
        let mutId = UUID().uuidString
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        let optimistic = ChatMessageItem(
            id: mutId,
            conversation_id: conversationId,
            sender_id: sess.user_id,
            client_mutation_id: mutId,
            body: trimmed,
            created_at: nowMs,
            isPendingSync: true
        )
        messages.append(optimistic)
        persistCachedMessages(conversationId: conversationId, items: messages)

        let escaped = trimmed.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let payload = "{\"conversation_id\":\"\(conversationId)\",\"body\":\"\(escaped)\"}"
        let _ = core.enqueueMutation(id: mutId, actionType: "send_message", payloadJSON: payload)
        pendingSyncCount = core.pendingOutboxCount()

        await syncAll(quality: .online)
    }

    func createConversationOfflineFirst(title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let sess = session else { return }
        do {
            let created = try await api.createConversation(token: sess.access_token, title: trimmed)
            conversations.insert(created, at: 0)
            selectedConversationId = created.id
            persistCachedConversations(conversations)
        } catch {
            let localId = UUID().uuidString
            let item = ConversationItem(id: localId, title: trimmed, updated_at: Int64(Date().timeIntervalSince1970 * 1000))
            conversations.insert(item, at: 0)
            selectedConversationId = localId
            persistCachedConversations(conversations)
            let escaped = trimmed.replacingOccurrences(of: "\"", with: "\\\"")
            let _ = core.enqueueMutation(id: localId, actionType: "create_conversation", payloadJSON: "{\"title\":\"\(escaped)\"}")
            pendingSyncCount = core.pendingOutboxCount()
        }
    }

    func withAuthedRetry<T>(_ block: @escaping (String) async throws -> T) async throws -> T {
        guard let current = session else {
            throw TelefamAPIError.unauthorized(TelefamCoreBridge.sanitizeError(httpStatus: 401))
        }
        do {
            return try await block(current.access_token)
        } catch TelefamAPIError.unauthorized {
            guard !current.refresh_token.isEmpty else {
                throw TelefamAPIError.unauthorized(TelefamCoreBridge.sanitizeError(httpStatus: 401))
            }
            let refreshed = try await api.refreshSession(
                refreshToken: current.refresh_token,
                deviceFP: deviceFP,
                hwAttest: hwAttest
            )
            persistSession(refreshed)
            return try await block(refreshed.access_token)
        }
    }

    func syncAll(quality: TelefamNetworkQuality) async {
        guard let sess = session, sess.profile_completed, quality != .offline else { return }
        let batchSize = TelefamCoreBridge.adaptiveBatchSize(netState: quality)
        if batchSize > 0 && core.pendingOutboxCount() > 0 {
            let batchJSON = core.peekOutboxBatch(maxItems: batchSize)
            if let acked = try? await withAuthedRetry({ tok in
                try await self.api.syncMutationsRaw(token: tok, mutationsArrayJSON: batchJSON)
            }) {
                for id in acked { core.ackMutation(id: id) }
                pendingSyncCount = core.pendingOutboxCount()
            }
        }
        if let remoteConvs = try? await withAuthedRetry({ tok in
            try await self.api.listConversations(token: tok)
        }) {
            conversations = remoteConvs
            persistCachedConversations(remoteConvs)
        }
        if let cid = selectedConversationId,
           let remoteMsgs = try? await withAuthedRetry({ tok in
               try await self.api.listMessages(token: tok, conversationId: cid)
           }) {
            messages = remoteMsgs
            persistCachedMessages(conversationId: cid, items: remoteMsgs)
        }
        await refreshContacts(reset: true, quality: quality)
        await refreshMyProfile(quality: quality)
        await refreshFeedPosts(quality: quality)
        await refreshVideoFeed(tab: videoFeedTab, reset: true, quality: quality)
        await refreshNotifications(quality: quality)
        await flushQueuedPosts(quality: quality)
    }

    func refreshMyProfile(quality: TelefamNetworkQuality) async {
        guard session != nil, quality != .offline else { return }
        if let profile = try? await withAuthedRetry({ tok in
            try await self.api.getMyProfile(token: tok)
        }) {
            self.myProfile = profile
            persistCachedMyProfile(profile)
            await ensureOwnerMediaCachedLocally(profile: profile)
        }
    }

    func refreshFeedPosts(quality: TelefamNetworkQuality) async {
        guard session != nil, quality != .offline else {
            isLoadingFeed = false
            return
        }
        isLoadingFeed = true
        defer { isLoadingFeed = false }
        if let posts = try? await withAuthedRetry({ tok in
            try await self.api.listFeedPosts(token: tok, query: self.homeSearchQuery)
        }) {
            self.feedPosts = posts
            if homeSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                persistCachedFeed(posts)
            }
        }
    }

    func refreshNotifications(quality: TelefamNetworkQuality) async {
        guard session != nil, quality != .offline else {
            isLoadingNotifications = false
            return
        }
        isLoadingNotifications = true
        defer { isLoadingNotifications = false }
        if let items = try? await withAuthedRetry({ tok in
            try await self.api.listNotifications(token: tok)
        }) {
            self.notifications = items
            persistCachedNotifications(items)
        }
    }

    func markNotificationsRead(quality: TelefamNetworkQuality) async {
        notifications = notifications.map {
            NotificationItem(
                id: $0.id,
                kind: $0.kind,
                actor_name: $0.actor_name,
                message: $0.message,
                is_read: true,
                created_at: $0.created_at
            )
        }
        persistCachedNotifications(notifications)
        guard quality != .offline else { return }
        let _ = try? await withAuthedRetry { tok in
            try await self.api.markNotificationsRead(token: tok)
        }
    }

    func openEditProfile() {
        if let p = myProfile {
            fullName = p.full_name
            username = p.username
            if !p.country_iso.isEmpty { countryIso = p.country_iso }
            phoneNumber = p.phone_number
            gender = p.gender
            locationText = p.location
            bioText = p.bio
            avatarFingerprintHash = p.avatar_fingerprint_hash
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            if let d = df.date(from: p.date_of_birth) {
                birthDate = d
                hasSelectedDob = true
            }
        } else if let s = session {
            seedProfileSetup(email: s.email)
        }
        profileErrorMessage = nil
        isEditingProfile = true
    }

    func closeEditProfile() {
        profileErrorMessage = nil
        isEditingProfile = false
    }

    func selectContactFilter(_ filter: ContactFilterIOS, quality: TelefamNetworkQuality) {
        contactFilter = filter
        contactsNextCursor = ""
        hasMoreContacts = false
        Task { await refreshContacts(reset: true, quality: quality) }
    }

    func updateContactSearch(_ query: String, quality: TelefamNetworkQuality) {
        contactSearchQuery = query
        contactSearchTask?.cancel()
        contactSearchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.refreshContacts(reset: true, quality: quality)
        }
    }

    func refreshContacts(reset: Bool, quality: TelefamNetworkQuality) async {
        guard let sess = session, sess.profile_completed, quality != .offline else {
            isLoadingContacts = false
            return
        }
        let cursor = reset ? "" : contactsNextCursor
        if !reset && (isLoadingContacts || !hasMoreContacts || cursor.isEmpty) {
            return
        }
        isLoadingContacts = true
        defer { isLoadingContacts = false }
        do {
            let page = try await api.listContacts(
                token: sess.access_token,
                filter: contactFilter.rawValue,
                query: contactSearchQuery,
                cursor: cursor,
                limit: 30
            )
            mergeContactsIntoCache(page.contacts, replaceAll: reset && contactFilter == .all && contactSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            contactsNextCursor = page.next_cursor
            hasMoreContacts = page.has_more
        } catch {
            // Keep encrypted cached contacts rendered gracefully when offline/weak
        }
    }

    func toggleFollow(_ contact: ContactUserItem, quality: TelefamNetworkQuality) async {
        guard let sess = session else { return }
        guard core.allowFollowRateLimit(accountKey: sess.user_id) else {
            showContactsToast("Try again later")
            return
        }

        let nextFollowing = !contact.is_following
        let nextRel = TelefamCoreBridge.computeRelationship(isFollowing: nextFollowing, followsMe: contact.follows_me)
        updateCachedContact(userId: contact.user_id, isFollowing: nextFollowing, followsMe: contact.follows_me, relationship: nextRel, riskScore: contact.risk_score)

        let actionType = nextFollowing ? "follow_user" : "unfollow_user"
        let mutId = UUID().uuidString
        let payload = "{\"target_user_id\":\"\(contact.user_id)\"}"

        if quality == .offline {
            let _ = core.enqueueMutation(id: mutId, actionType: actionType, payloadJSON: payload)
            pendingSyncCount = core.pendingOutboxCount()
            return
        }

        do {
            let res = try await api.setFollowState(token: sess.access_token, targetUserId: contact.user_id, follow: nextFollowing)
            updateCachedContact(userId: contact.user_id, isFollowing: res.is_following, followsMe: res.follows_me, relationship: res.relationship, riskScore: res.risk_score)
        } catch let TelefamAPIError.sanitized(msg) {
            let prevRel = TelefamCoreBridge.computeRelationship(isFollowing: contact.is_following, followsMe: contact.follows_me)
            updateCachedContact(userId: contact.user_id, isFollowing: contact.is_following, followsMe: contact.follows_me, relationship: prevRel, riskScore: contact.risk_score)
            showContactsToast(msg)
        } catch {
            let _ = core.enqueueMutation(id: mutId, actionType: actionType, payloadJSON: payload)
            pendingSyncCount = core.pendingOutboxCount()
        }
    }

    func showContactsToast(_ message: String) {
        contactsToastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if contactsToastMessage == message {
                contactsToastMessage = nil
            }
        }
    }

    private func mergeContactsIntoCache(_ incoming: [ContactUserItem], replaceAll: Bool) {
        if replaceAll {
            cachedContacts = incoming
        } else {
            var map = Dictionary(uniqueKeysWithValues: cachedContacts.map { ($0.user_id, $0) })
            for item in incoming {
                map[item.user_id] = item
            }
            let existingOrder = cachedContacts.compactMap { map.removeValue(forKey: $0.user_id) }
            let appended = incoming.filter { item in !existingOrder.contains(where: { $0.user_id == item.user_id }) }
            cachedContacts = existingOrder + appended
        }
        persistCachedContacts(cachedContacts)
    }

    func updateCachedContact(userId: String, isFollowing: Bool, followsMe: Bool, relationship: String, riskScore: Int) {
        if let idx = cachedContacts.firstIndex(where: { $0.user_id == userId }) {
            cachedContacts[idx].is_following = isFollowing
            cachedContacts[idx].follows_me = followsMe
            cachedContacts[idx].relationship = relationship
            cachedContacts[idx].risk_score = riskScore
            persistCachedContacts(cachedContacts)
        }
    }

    func changeEmail() {
        otpDigits = Array(repeating: "", count: 6)
        errorMessage = nil
        authStep = .enterEmail
    }

    func signOut() {
        let tokenToRevoke = session?.access_token
        if let tokenToRevoke, !tokenToRevoke.isEmpty {
            let client = self.api
            Task.detached {
                await client.logoutSession(token: tokenToRevoke)
            }
        }
        stopSongPreview()
        feedPlayback.setFeedVisible(false)
        clearOwnerProfileLocalCache()
        core.vaultDelete(key: "session_json")
        core.vaultDelete(key: "conversations_json")
        core.vaultDelete(key: "contacts_cache_json")
        core.vaultDelete(key: "queued_posts_json")
        core.vaultDelete(key: "my_profile_json")
        core.vaultDelete(key: "feed_cache_json")
        core.vaultDelete(key: "video_feed_for_you_json")
        core.vaultDelete(key: "video_feed_following_json")
        core.vaultDelete(key: "video_feed_saved_json")
        core.vaultDelete(key: "feed_recent_searches_json")
        core.vaultDelete(key: "notifications_json")
        session = nil
        myProfile = nil
        feedPosts = []
        forYouVideos = []
        followingVideos = []
        savedVideos = []
        localRecentSearches = []
        feedSearchResults = nil
        notifications = []
        homeSearchQuery = ""
        isEditingProfile = false
        conversations = []
        messages = []
        cachedContacts = []
        selectedConversationId = nil
        activeTab = .chats
        authStep = .enterEmail
        isPostComposerOpen = false
    }

    // MARK: - New Post Composer

    private var postQueueDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("telefam_post_queue", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func openPostComposer() {
        postUploadStatus = .idle
        postUploadProgress = 0
        postInlineError = nil
        isPostComposerOpen = true
        if postSongResults.isEmpty { searchSongs("") }
        if postHashtagResults.isEmpty { searchHashtags("") }
    }

    func closePostComposer() {
        stopSongPreview()
        isPostComposerOpen = false
        postMode = .text
        postTextBody = ""
        postCaption = ""
        postShowImageThemes = false
        postBgColorHex = "#C81010"
        postImageThemeId = nil
        postFont = .classic
        postPhotos = []
        clearVideo()
        postSelectedSong = nil
        postTaggedContacts = []
        postSelectedHashtags = []
        postUploadStatus = .idle
        postUploadProgress = 0
        postInlineError = nil
    }

    func updatePostTextBody(_ text: String) {
        postTextBody = String(text.prefix(280))
    }

    func updatePostCaption(_ text: String) {
        postCaption = String(text.prefix(2200))
    }

    func selectBgColor(_ hex: String) {
        postBgColorHex = hex
        postImageThemeId = nil
    }

    func selectImageTheme(_ themeId: String) {
        postImageThemeId = themeId
    }

    func addPickedPhotoData(_ dataItems: [Data]) async {
        guard !dataItems.isEmpty else { return }
        postIsExtractingMedia = true
        postInlineError = nil
        defer { postIsExtractingMedia = false }

        var list = postPhotos
        let remaining = max(0, 10 - list.count)
        for rawData in dataItems.prefix(remaining) {
            guard let img = UIImage(data: rawData) else { continue }
            if let processed = compressAndFingerprintImage(img) {
                list.append(processed)
            }
        }
        postPhotos = Array(list.prefix(10))
    }

    func removePhoto(id: String) {
        postPhotos.removeAll { $0.id == id }
    }

    func selectVideoFile(_ sourceURL: URL) async {
        postIsExtractingMedia = true
        postInlineError = nil

        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scoped { sourceURL.stopAccessingSecurityScopedResource() }
            postIsExtractingMedia = false
        }

        let ext = sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension
        let stagedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tf_video_\(UUID().uuidString).\(ext)")
        do {
            if FileManager.default.fileExists(atPath: stagedURL.path) {
                try FileManager.default.removeItem(at: stagedURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: stagedURL)
        } catch {
            postInlineError = TelefamCoreBridge.sanitizeError(httpStatus: 400)
            return
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: stagedURL.path)
        let sizeBytes = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let maxBytes: Int64 = 200 * 1024 * 1024
        if sizeBytes <= 0 || sizeBytes > maxBytes {
            try? FileManager.default.removeItem(at: stagedURL)
            postInlineError = "Max 200 MB"
            return
        }

        let asset = AVURLAsset(url: stagedURL)
        let durCM = (try? await asset.load(.duration)) ?? CMTime.zero
        let durationMs = max(1000, Int64(CMTimeGetSeconds(durCM) * 1000.0))

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        generator.requestedTimeToleranceBefore = CMTime(value: 200, timescale: 1000)
        generator.requestedTimeToleranceAfter = CMTime(value: 200, timescale: 1000)

        let frameCount = 8
        var frames: [VideoFrameIOS] = []
        for idx in 0..<frameCount {
            let tsMs = (durationMs * Int64(idx)) / Int64(max(1, frameCount - 1))
            let cm = CMTime(value: tsMs, timescale: 1000)
            if let cg = try? generator.copyCGImage(at: cm, actualTime: nil) {
                let ui = UIImage(cgImage: cg)
                if let jpeg = ui.jpegData(compressionQuality: 0.85) {
                    let dhash = computeDHash(for: ui)
                    frames.append(VideoFrameIOS(timestampMs: tsMs, uiImage: ui, jpegData: jpeg, dhash: dhash))
                }
            }
        }

        if let prev = postVideoURL, prev != stagedURL {
            try? FileManager.default.removeItem(at: prev)
        }
        postVideoURL = stagedURL
        postVideoSizeBytes = sizeBytes
        postVideoDurationMs = durationMs
        postVideoFrames = frames
        postTrimStartMs = 0
        postTrimEndMs = durationMs
        let midIdx = frames.count / 2
        if let mid = (frames.indices.contains(midIdx) ? frames[midIdx] : frames.first) {
            postSelectedThumbMs = mid.timestampMs
            postSelectedThumbImage = mid.uiImage
            postSelectedThumbJPEG = mid.jpegData
        }
    }

    func clearVideo() {
        if let prev = postVideoURL {
            try? FileManager.default.removeItem(at: prev)
        }
        postVideoURL = nil
        postVideoSizeBytes = 0
        postVideoDurationMs = 0
        postVideoFrames = []
        postTrimStartMs = 0
        postTrimEndMs = 0
        postSelectedThumbMs = 0
        postSelectedThumbImage = nil
        postSelectedThumbJPEG = nil
        postInlineError = nil
    }

    func updateVideoTrim(startMs: Int64, endMs: Int64) {
        let dur = max(1000, postVideoDurationMs)
        let s = min(max(0, startMs), dur - 500)
        let e = min(max(s + 500, endMs), dur)
        postTrimStartMs = s
        postTrimEndMs = e
    }

    func selectThumbFrame(_ frame: VideoFrameIOS) {
        postSelectedThumbMs = frame.timestampMs
        postSelectedThumbImage = frame.uiImage
        postSelectedThumbJPEG = frame.jpegData
    }

    func autoSelectThumbnail() {
        guard !postVideoFrames.isEmpty else { return }
        let midTs = (postTrimStartMs + postTrimEndMs) / 2
        if let best = postVideoFrames.min(by: { abs($0.timestampMs - midTs) < abs($1.timestampMs - midTs) }) {
            selectThumbFrame(best)
        }
    }

    func toggleMuteAudio() {
        postMuteOriginalAudio.toggle()
    }

    func searchSongs(_ query: String) {
        postSongQuery = query
        songSearchTask?.cancel()
        songSearchTask = Task { [weak self] in
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try? await Task.sleep(nanoseconds: 280_000_000)
            }
            guard !Task.isCancelled, let self, let sess = self.session else { return }
            self.postIsSearchingSongs = true
            defer { self.postIsSearchingSongs = false }
            if let tracks = try? await self.api.searchMusic(token: sess.access_token, query: query) {
                self.postSongResults = tracks
            }
        }
    }

    func selectSong(_ track: MusicTrackItem?) {
        stopSongPreview()
        postSelectedSong = track
    }

    func toggleSongPreview(_ track: MusicTrackItem) {
        guard !track.preview_url.isEmpty, let url = URL(string: track.preview_url) else { return }
        if postPreviewingTrackId == track.track_id && postIsPlayingSongPreview {
            stopSongPreview()
            return
        }
        stopSongPreview()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        audioEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopSongPreview()
            }
        }
        player.play()
        self.audioPlayer = player
        self.postPreviewingTrackId = track.track_id
        self.postIsPlayingSongPreview = true
    }

    func stopSongPreview() {
        audioPlayer?.pause()
        audioPlayer = nil
        if let obs = audioEndObserver {
            NotificationCenter.default.removeObserver(obs)
            audioEndObserver = nil
        }
        postIsPlayingSongPreview = false
        postPreviewingTrackId = nil
    }

    func searchHashtags(_ query: String) {
        postHashtagQuery = query
        hashtagSearchTask?.cancel()
        hashtagSearchTask = Task { [weak self] in
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try? await Task.sleep(nanoseconds: 220_000_000)
            }
            guard !Task.isCancelled, let self, let sess = self.session else { return }
            self.postIsSearchingHashtags = true
            defer { self.postIsSearchingHashtags = false }
            if let tags = try? await self.api.searchHashtags(token: sess.access_token, query: query) {
                self.postHashtagResults = tags
            }
        }
    }

    func toggleTagContact(_ contact: ContactUserItem) {
        if postTaggedContacts.contains(where: { $0.user_id == contact.user_id }) {
            postTaggedContacts.removeAll { $0.user_id == contact.user_id }
        } else {
            postTaggedContacts.append(contact)
        }
    }

    func toggleHashtag(_ raw: String) {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        guard !clean.isEmpty else { return }
        if postSelectedHashtags.contains(clean) {
            postSelectedHashtags.removeAll { $0 == clean }
        } else if postSelectedHashtags.count < 20 {
            postSelectedHashtags.append(clean)
        }
    }

    func sharePost(quality: TelefamNetworkQuality) async {
        guard canSharePost, let sess = session else { return }
        stopSongPreview()
        postUploadStatus = .uploading
        postUploadProgress = 2
        postInlineError = nil

        let bodyText = (postMode == .text ? postTextBody : postCaption).trimmingCharacters(in: .whitespacesAndNewlines)
        let queueId = UUID().uuidString

        if quality == .offline {
            stagePostForOfflineRetry(queueId: queueId, bodyText: bodyText)
            postUploadStatus = .queued
            postUploadProgress = 100
            try? await Task.sleep(nanoseconds: 550_000_000)
            closePostComposer()
            return
        }

        do {
            var mediaIds: [String] = []
            if postMode == .photos {
                let uploaded = try await api.uploadPostPhotos(
                    token: sess.access_token,
                    photosJPEG: postPhotos.map { $0.jpegData }
                ) { pct in
                    Task { @MainActor [weak self] in
                        self?.postUploadProgress = pct
                    }
                }
                mediaIds = uploaded.map { $0.media_id }
            } else if postMode == .video, let videoURL = postVideoURL {
                let uploaded = try await api.uploadPostVideo(
                    token: sess.access_token,
                    videoFileURL: videoURL,
                    thumbnailJPEG: postSelectedThumbJPEG,
                    trimStartMs: postTrimStartMs,
                    trimEndMs: postTrimEndMs,
                    thumbnailAtMs: postSelectedThumbMs,
                    muteOriginalAudio: postMuteOriginalAudio,
                    songPreviewURL: postSelectedSong?.preview_url ?? ""
                ) { pct in
                    Task { @MainActor [weak self] in
                        self?.postUploadProgress = pct
                    }
                }
                mediaIds = [uploaded.media_id]
            }

            postUploadProgress = 95
            let req = CreatePostRequestIOS(
                post_type: postMode.rawValue,
                body: bodyText,
                bg_color_hex: postImageThemeId == nil ? postBgColorHex : "",
                bg_theme_id: postImageThemeId ?? "",
                font_family: postFont.rawValue,
                song_id: postSelectedSong?.track_id ?? "",
                song_title: postSelectedSong?.title ?? "",
                song_artist: postSelectedSong?.artist ?? "",
                song_preview_url: postSelectedSong?.preview_url ?? "",
                mute_original_audio: postMuteOriginalAudio,
                trim_start_ms: postTrimStartMs,
                trim_end_ms: postTrimEndMs,
                media_ids: mediaIds,
                tagged_user_ids: postTaggedContacts.map { $0.user_id },
                hashtags: postSelectedHashtags
            )
            let _ = try await api.createPost(token: sess.access_token, request: req)
            postUploadProgress = 100
            postUploadStatus = .uploaded
            await refreshVideoFeed(tab: videoFeedTab, reset: true, quality: quality)
            await refreshOwnerProfile(quality: quality, isPullGesture: false)
            try? await Task.sleep(nanoseconds: 700_000_000)
            closePostComposer()
        } catch let TelefamAPIError.sanitized(msg) {
            if msg == "No internet" {
                stagePostForOfflineRetry(queueId: queueId, bodyText: bodyText)
                postUploadStatus = .queued
                postUploadProgress = 100
                try? await Task.sleep(nanoseconds: 550_000_000)
                closePostComposer()
            } else {
                postUploadStatus = .error
                postInlineError = msg
            }
        } catch {
            stagePostForOfflineRetry(queueId: queueId, bodyText: bodyText)
            postUploadStatus = .queued
            postUploadProgress = 100
            try? await Task.sleep(nanoseconds: 550_000_000)
            closePostComposer()
        }
    }

    private func stagePostForOfflineRetry(queueId: String, bodyText: String) {
        let qDir = postQueueDirectory
        var photoFiles: [String] = []
        if postMode == .photos {
            for (idx, p) in postPhotos.enumerated() {
                let name = "\(queueId)_p\(idx).jpg"
                let url = qDir.appendingPathComponent(name)
                if (try? p.jpegData.write(to: url, options: .atomic)) != nil {
                    photoFiles.append(name)
                }
            }
        }
        var videoFile = ""
        var thumbFile = ""
        if postMode == .video, let src = postVideoURL {
            let vName = "\(queueId)_vid.mp4"
            let vUrl = qDir.appendingPathComponent(vName)
            if (try? FileManager.default.copyItem(at: src, to: vUrl)) != nil {
                videoFile = vName
            }
            if let tData = postSelectedThumbJPEG {
                let tName = "\(queueId)_thumb.jpg"
                let tUrl = qDir.appendingPathComponent(tName)
                if (try? tData.write(to: tUrl, options: .atomic)) != nil {
                    thumbFile = tName
                }
            }
        }

        let draft = QueuedPostDraftIOS(
            queue_id: queueId,
            post_type: postMode.rawValue,
            body: bodyText,
            bg_color_hex: postImageThemeId == nil ? postBgColorHex : "",
            bg_theme_id: postImageThemeId ?? "",
            font_family: postFont.rawValue,
            song_id: postSelectedSong?.track_id ?? "",
            song_title: postSelectedSong?.title ?? "",
            song_artist: postSelectedSong?.artist ?? "",
            song_preview_url: postSelectedSong?.preview_url ?? "",
            mute_original_audio: postMuteOriginalAudio,
            trim_start_ms: postTrimStartMs,
            trim_end_ms: postTrimEndMs,
            thumbnail_at_ms: postSelectedThumbMs,
            tagged_user_ids: postTaggedContacts.map { $0.user_id },
            hashtags: postSelectedHashtags,
            photo_filenames: photoFiles,
            video_filename: videoFile,
            thumb_filename: thumbFile,
            created_at_ms: Int64(Date().timeIntervalSince1970 * 1000)
        )
        var existing = loadQueuedPosts()
        existing.append(draft)
        saveQueuedPosts(existing)
    }

    func flushQueuedPosts(quality: TelefamNetworkQuality) async {
        guard quality != .offline, let sess = session else { return }
        let queue = loadQueuedPosts()
        guard !queue.isEmpty else { return }
        let qDir = postQueueDirectory
        var remaining: [QueuedPostDraftIOS] = []

        for item in queue {
            do {
                var mediaIds: [String] = []
                if item.post_type == "photos" {
                    let jpegs = item.photo_filenames.compactMap { try? Data(contentsOf: qDir.appendingPathComponent($0)) }
                    if !jpegs.isEmpty {
                        let uploaded = try await api.uploadPostPhotos(token: sess.access_token, photosJPEG: jpegs) { _ in }
                        mediaIds = uploaded.map { $0.media_id }
                    }
                } else if item.post_type == "video", !item.video_filename.isEmpty {
                    let vUrl = qDir.appendingPathComponent(item.video_filename)
                    let thumbData = item.thumb_filename.isEmpty ? nil : try? Data(contentsOf: qDir.appendingPathComponent(item.thumb_filename))
                    let uploaded = try await api.uploadPostVideo(
                        token: sess.access_token,
                        videoFileURL: vUrl,
                        thumbnailJPEG: thumbData,
                        trimStartMs: item.trim_start_ms,
                        trimEndMs: item.trim_end_ms,
                        thumbnailAtMs: item.thumbnail_at_ms,
                        muteOriginalAudio: item.mute_original_audio,
                        songPreviewURL: item.song_preview_url
                    ) { _ in }
                    mediaIds = [uploaded.media_id]
                }

                let req = CreatePostRequestIOS(
                    post_type: item.post_type,
                    body: item.body,
                    bg_color_hex: item.bg_color_hex,
                    bg_theme_id: item.bg_theme_id,
                    font_family: item.font_family,
                    song_id: item.song_id,
                    song_title: item.song_title,
                    song_artist: item.song_artist,
                    song_preview_url: item.song_preview_url,
                    mute_original_audio: item.mute_original_audio,
                    trim_start_ms: item.trim_start_ms,
                    trim_end_ms: item.trim_end_ms,
                    media_ids: mediaIds,
                    tagged_user_ids: item.tagged_user_ids,
                    hashtags: item.hashtags
                )
                let _ = try await api.createPost(token: sess.access_token, request: req)

                for pf in item.photo_filenames { try? FileManager.default.removeItem(at: qDir.appendingPathComponent(pf)) }
                if !item.video_filename.isEmpty { try? FileManager.default.removeItem(at: qDir.appendingPathComponent(item.video_filename)) }
                if !item.thumb_filename.isEmpty { try? FileManager.default.removeItem(at: qDir.appendingPathComponent(item.thumb_filename)) }
            } catch {
                remaining.append(item)
            }
        }
        saveQueuedPosts(remaining)
    }

    private func loadQueuedPosts() -> [QueuedPostDraftIOS] {
        guard let data = core.vaultGet(key: "queued_posts_json"),
              let list = try? JSONDecoder().decode([QueuedPostDraftIOS].self, from: data) else {
            return []
        }
        return list
    }

    private func saveQueuedPosts(_ list: [QueuedPostDraftIOS]) {
        if list.isEmpty {
            core.vaultDelete(key: "queued_posts_json")
        } else if let data = try? JSONEncoder().encode(list) {
            let _ = core.vaultPut(key: "queued_posts_json", data: data)
        }
    }

    private func compressAndFingerprintImage(_ image: UIImage) -> ExtractedPhotoIOS? {
        let maxDim: CGFloat = 1600
        let scale = min(1.0, maxDim / max(image.size.width, image.size.height))
        let targetSize = CGSize(width: max(1, floor(image.size.width * scale)), height: max(1, floor(image.size.height * scale)))

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let jpeg = scaled.jpegData(compressionQuality: 0.85) else { return nil }
        let dhash = computeDHash(for: scaled)
        let cid = TelefamCoreBridge.computeMediaContentId(
            mediaKind: "photo",
            frameHashesCsv: dhash,
            audioFpHex: "",
            width: Int32(targetSize.width),
            height: Int32(targetSize.height),
            durationMs: 0
        )
        return ExtractedPhotoIOS(
            id: UUID().uuidString,
            jpegData: jpeg,
            uiImage: scaled,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            dhash: dhash,
            contentId: cid
        )
    }

    private func computeDHash(for image: UIImage) -> String {
        guard let cg = image.cgImage else { return "" }
        let w = 64
        let h = 64
        var rgba = Data(count: w * h * 4)
        rgba.withUnsafeMutableBytes { ptr in
            if let base = ptr.baseAddress {
                let cs = CGColorSpaceCreateDeviceRGB()
                if let ctx = CGContext(
                    data: base,
                    width: w,
                    height: h,
                    bitsPerComponent: 8,
                    bytesPerRow: w * 4,
                    space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) {
                    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                }
            }
        }
        return TelefamCoreBridge.computeFrameDHash(rgbaData: rgba, width: Int32(w), height: Int32(h))
    }

    private func persistSession(_ sess: AuthSessionPayload) {
        self.session = sess
        if let data = try? JSONEncoder().encode(sess) {
            let _ = core.vaultPut(key: "session_json", data: data)
        }
    }

    private func restoreEncryptedSession() {
        if let themeData = core.vaultGet(key: "theme_dark"),
           let themeStr = String(data: themeData, encoding: .utf8) {
            self.isDarkTheme = (themeStr == "true")
        }
        if let data = core.vaultGet(key: "session_json"),
           let decoded = try? JSONDecoder().decode(AuthSessionPayload.self, from: data) {
            self.session = decoded
            if !decoded.profile_completed {
                seedProfileSetup(email: decoded.email)
            }
        }
        if let convData = core.vaultGet(key: "conversations_json"),
           let convs = try? JSONDecoder().decode([ConversationItem].self, from: convData) {
            self.conversations = convs
        }
        if let contactsData = core.vaultGet(key: "contacts_cache_json"),
           let savedContacts = try? JSONDecoder().decode([ContactUserItem].self, from: contactsData) {
            self.cachedContacts = savedContacts
        }
        if let profileData = core.vaultGet(key: "my_profile_json"),
           let savedProfile = try? JSONDecoder().decode(MyProfilePayload.self, from: profileData) {
            self.myProfile = savedProfile
        }
        if let feedData = core.vaultGet(key: "feed_cache_json"),
           let savedFeed = try? JSONDecoder().decode([FeedPostItem].self, from: feedData) {
            self.feedPosts = savedFeed
        }
        if let notifData = core.vaultGet(key: "notifications_json"),
           let savedNotifs = try? JSONDecoder().decode([NotificationItem].self, from: notifData) {
            self.notifications = savedNotifs
        }
        self.pendingSyncCount = core.pendingOutboxCount()
    }

    private func persistCachedConversations(_ items: [ConversationItem]) {
        if let data = try? JSONEncoder().encode(items) {
            let _ = core.vaultPut(key: "conversations_json", data: data)
        }
    }

    private func persistCachedContacts(_ items: [ContactUserItem]) {
        if let data = try? JSONEncoder().encode(items) {
            let _ = core.vaultPut(key: "contacts_cache_json", data: data)
        }
    }

    func persistCachedMyProfile(_ profile: MyProfilePayload) {
        if let data = try? JSONEncoder().encode(profile) {
            let _ = core.vaultPut(key: "my_profile_json", data: data)
        }
    }

    private func persistCachedFeed(_ items: [FeedPostItem]) {
        if let data = try? JSONEncoder().encode(items) {
            let _ = core.vaultPut(key: "feed_cache_json", data: data)
        }
    }

    private func persistCachedNotifications(_ items: [NotificationItem]) {
        if let data = try? JSONEncoder().encode(items) {
            let _ = core.vaultPut(key: "notifications_json", data: data)
        }
    }

    private func persistCachedMessages(conversationId: String, items: [ChatMessageItem]) {
        if let data = try? JSONEncoder().encode(items) {
            let _ = core.vaultPut(key: "msgs_\(conversationId)", data: data)
        }
    }

    private func startCooldownTicker(seconds: Int64) {
        cooldownTimer?.invalidate()
        cooldownSeconds = max(0, seconds)
        guard cooldownSeconds > 0 else { return }
        cooldownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            Task { @MainActor [weak self] in
                guard let self else { t.invalidate(); return }
                if self.cooldownSeconds > 0 {
                    self.cooldownSeconds -= 1
                } else {
                    t.invalidate()
                }
            }
        }
    }
}
