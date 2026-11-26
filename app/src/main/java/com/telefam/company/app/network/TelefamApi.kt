package com.telefam.company.app.network

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import com.telefam.company.app.BuildConfig
import com.telefam.company.app.core.NetworkQuality
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import okhttp3.MediaType
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okio.BufferedSink
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.Multipart
import retrofit2.http.POST
import retrofit2.http.Part
import retrofit2.http.Path
import retrofit2.http.Query
import java.io.InputStream
import java.util.concurrent.TimeUnit

@JsonClass(generateAdapter = true)
data class SendOtpRequest(
    val email: String,
    @Json(name = "device_fingerprint") val deviceFingerprint: String,
    @Json(name = "hardware_attestation") val hardwareAttestation: String,
    @Json(name = "device_name") val deviceName: String,
    val platform: String = "android"
)

@JsonClass(generateAdapter = true)
data class SendOtpResponse(
    val accepted: Boolean,
    @Json(name = "cooldown_seconds") val cooldownSeconds: Long
)

@JsonClass(generateAdapter = true)
data class VerifyOtpRequest(
    val email: String,
    val otp: String,
    @Json(name = "magic_token") val magicToken: String? = null,
    @Json(name = "device_fingerprint") val deviceFingerprint: String,
    @Json(name = "hardware_attestation") val hardwareAttestation: String,
    @Json(name = "device_name") val deviceName: String,
    val platform: String = "android"
)

@JsonClass(generateAdapter = true)
data class OAuthVerifyRequest(
    @Json(name = "id_token") val idToken: String,
    @Json(name = "device_fingerprint") val deviceFingerprint: String,
    @Json(name = "hardware_attestation") val hardwareAttestation: String,
    @Json(name = "device_name") val deviceName: String,
    val platform: String = "android"
)

@JsonClass(generateAdapter = true)
data class AuthSessionDto(
    @Json(name = "access_token") val accessToken: String,
    @Json(name = "refresh_token") val refreshToken: String,
    @Json(name = "expires_in") val expiresIn: Long,
    @Json(name = "user_id") val userId: String,
    val email: String,
    @Json(name = "display_name") val displayName: String,
    @Json(name = "profile_completed") val profileCompleted: Boolean = false
)

@JsonClass(generateAdapter = true)
data class AvatarUploadResponse(
    @Json(name = "avatar_fingerprint_hash") val avatarFingerprintHash: String
)

@JsonClass(generateAdapter = true)
data class ProfileSetupRequest(
    @Json(name = "full_name") val fullName: String,
    val username: String,
    @Json(name = "country_iso") val countryIso: String,
    @Json(name = "phone_number") val phoneNumber: String,
    val gender: String,
    @Json(name = "date_of_birth") val dateOfBirth: String,
    val location: String,
    val bio: String,
    @Json(name = "avatar_fingerprint_hash") val avatarFingerprintHash: String = ""
)

@JsonClass(generateAdapter = true)
data class ProfileSetupResponse(
    @Json(name = "user_id") val userId: String,
    @Json(name = "full_name") val fullName: String,
    val username: String,
    @Json(name = "profile_completed") val profileCompleted: Boolean
)

@JsonClass(generateAdapter = true)
data class RefreshSessionRequest(
    @Json(name = "refresh_token") val refreshToken: String,
    @Json(name = "device_fingerprint") val deviceFingerprint: String,
    @Json(name = "hardware_attestation") val hardwareAttestation: String,
    val platform: String = "android"
)

@JsonClass(generateAdapter = true)
data class MyProfileDto(
    @Json(name = "user_id") val userId: String = "",
    val email: String = "",
    @Json(name = "full_name") val fullName: String = "",
    val username: String = "",
    @Json(name = "country_iso") val countryIso: String = "",
    @Json(name = "phone_number") val phoneNumber: String = "",
    val gender: String = "",
    @Json(name = "date_of_birth") val dateOfBirth: String = "",
    val location: String = "",
    val bio: String = "",
    @Json(name = "avatar_fingerprint_hash") val avatarFingerprintHash: String = "",
    @Json(name = "profile_completed") val profileCompleted: Boolean = false
)

@JsonClass(generateAdapter = true)
data class FeedPostDto(
    @Json(name = "post_id") val postId: String,
    @Json(name = "author_id") val authorId: String = "",
    @Json(name = "author_name") val authorName: String = "",
    @Json(name = "author_handle") val authorHandle: String = "",
    @Json(name = "post_type") val postType: String = "text",
    val body: String = "",
    @Json(name = "bg_color_hex") val bgColorHex: String = "",
    @Json(name = "bg_theme_id") val bgThemeId: String = "",
    @Json(name = "font_family") val fontFamily: String = "classic",
    @Json(name = "song_title") val songTitle: String = "",
    @Json(name = "song_artist") val songArtist: String = "",
    @Json(name = "media_count") val mediaCount: Int = 0,
    val hashtags: List<String> = emptyList(),
    @Json(name = "created_at") val createdAt: Long = 0L
)

@JsonClass(generateAdapter = true)
data class FeedPostsResponse(
    val posts: List<FeedPostDto> = emptyList()
)

@JsonClass(generateAdapter = true)
data class NotificationDto(
    val id: String,
    val kind: String = "",
    @Json(name = "actor_name") val actorName: String = "",
    val message: String = "",
    @Json(name = "is_read") val isRead: Boolean = false,
    @Json(name = "created_at") val createdAt: Long = 0L
)

@JsonClass(generateAdapter = true)
data class NotificationsResponse(
    val notifications: List<NotificationDto> = emptyList()
)

@JsonClass(generateAdapter = true)
data class ConversationDto(
    val id: String,
    val title: String,
    @Json(name = "updated_at") val updatedAt: Long
)

@JsonClass(generateAdapter = true)
data class ConversationsListDto(
    val conversations: List<ConversationDto> = emptyList()
)

@JsonClass(generateAdapter = true)
data class CreateConversationRequest(val title: String)

@JsonClass(generateAdapter = true)
data class MessageDto(
    val id: String,
    @Json(name = "conversation_id") val conversationId: String,
    @Json(name = "sender_id") val senderId: String,
    @Json(name = "client_mutation_id") val clientMutationId: String,
    val body: String,
    @Json(name = "created_at") val createdAt: Long
)

@JsonClass(generateAdapter = true)
data class MessagesListDto(
    val messages: List<MessageDto> = emptyList()
)

@JsonClass(generateAdapter = true)
data class MutationWireItem(
    @Json(name = "mutation_id") val mutationId: String,
    @Json(name = "action_type") val actionType: String,
    val payload: Map<String, String>
)

@JsonClass(generateAdapter = true)
data class SyncMutationsRequest(
    val mutations: List<MutationWireItem>
)

@JsonClass(generateAdapter = true)
data class SyncMutationsResponse(
    @Json(name = "acked_ids") val ackedIds: List<String> = emptyList()
)

@JsonClass(generateAdapter = true)
data class ContactUserDto(
    @Json(name = "user_id") val userId: String,
    @Json(name = "full_name") val fullName: String,
    val username: String,
    val location: String = "",
    @Json(name = "avatar_fingerprint_hash") val avatarFingerprintHash: String = "",
    @Json(name = "is_following") val isFollowing: Boolean = false,
    @Json(name = "follows_me") val followsMe: Boolean = false,
    val relationship: String = "follow",
    @Json(name = "risk_score") val riskScore: Int = 0
)

@JsonClass(generateAdapter = true)
data class ContactsPageDto(
    val contacts: List<ContactUserDto> = emptyList(),
    @Json(name = "next_cursor") val nextCursor: String = "",
    @Json(name = "has_more") val hasMore: Boolean = false
)

@JsonClass(generateAdapter = true)
data class FollowActionRequest(
    @Json(name = "target_user_id") val targetUserId: String,
    val follow: Boolean
)

@JsonClass(generateAdapter = true)
data class FollowActionResponse(
    @Json(name = "target_user_id") val targetUserId: String,
    @Json(name = "is_following") val isFollowing: Boolean,
    @Json(name = "follows_me") val followsMe: Boolean,
    val relationship: String,
    @Json(name = "risk_score") val riskScore: Int = 0
)

@JsonClass(generateAdapter = true)
data class MusicTrackDto(
    @Json(name = "track_id") val trackId: String,
    val title: String,
    val artist: String,
    @Json(name = "artwork_url") val artworkUrl: String = "",
    @Json(name = "preview_url") val previewUrl: String = "",
    @Json(name = "duration_sec") val durationSec: Int = 30
)

@JsonClass(generateAdapter = true)
data class MusicSearchResponse(
    val tracks: List<MusicTrackDto> = emptyList()
)

@JsonClass(generateAdapter = true)
data class HashtagDto(
    val tag: String,
    @Json(name = "post_count") val postCount: Long = 0L
)

@JsonClass(generateAdapter = true)
data class HashtagSearchResponse(
    val hashtags: List<HashtagDto> = emptyList()
)

@JsonClass(generateAdapter = true)
data class UploadedPhotoDto(
    @Json(name = "media_id") val mediaId: String,
    @Json(name = "renamed_filename") val renamedFilename: String = "",
    @Json(name = "content_id") val contentId: String = "",
    val width: Int = 0,
    val height: Int = 0,
    @Json(name = "perceptual_dhash") val perceptualDHash: String = ""
)

@JsonClass(generateAdapter = true)
data class UploadPhotosResponse(
    val media: List<UploadedPhotoDto> = emptyList()
)

@JsonClass(generateAdapter = true)
data class VideoQualityRenditionDto(
    val label: String,
    val width: Int = 0,
    val height: Int = 0,
    @Json(name = "bitrate_kbps") val bitrateKbps: Int = 0,
    @Json(name = "object_key") val objectKey: String = ""
)

@JsonClass(generateAdapter = true)
data class UploadedVideoDto(
    @Json(name = "media_id") val mediaId: String,
    @Json(name = "renamed_filename") val renamedFilename: String = "",
    @Json(name = "content_id") val contentId: String = "",
    @Json(name = "thumbnail_object_key") val thumbnailObjectKey: String = "",
    @Json(name = "thumbnail_fingerprint") val thumbnailFingerprint: String = "",
    @Json(name = "audio_fingerprint_hash") val audioFingerprintHash: String = "",
    val width: Int = 0,
    val height: Int = 0,
    @Json(name = "duration_ms") val durationMs: Long = 0L,
    @Json(name = "frame_count") val frameCount: Int = 0,
    val qualities: List<VideoQualityRenditionDto> = emptyList()
)

@JsonClass(generateAdapter = true)
data class CreatePostRequest(
    @Json(name = "post_type") val postType: String,
    val body: String = "",
    @Json(name = "bg_color_hex") val bgColorHex: String = "",
    @Json(name = "bg_theme_id") val bgThemeId: String = "",
    @Json(name = "font_family") val fontFamily: String = "classic",
    @Json(name = "song_id") val songId: String = "",
    @Json(name = "song_title") val songTitle: String = "",
    @Json(name = "song_artist") val songArtist: String = "",
    @Json(name = "song_preview_url") val songPreviewUrl: String = "",
    @Json(name = "mute_original_audio") val muteOriginalAudio: Boolean = false,
    @Json(name = "trim_start_ms") val trimStartMs: Long = 0L,
    @Json(name = "trim_end_ms") val trimEndMs: Long = 0L,
    @Json(name = "media_ids") val mediaIds: List<String> = emptyList(),
    @Json(name = "tagged_user_ids") val taggedUserIds: List<String> = emptyList(),
    val hashtags: List<String> = emptyList()
)

@JsonClass(generateAdapter = true)
data class CreatePostResponse(
    @Json(name = "post_id") val postId: String,
    @Json(name = "video_id") val videoId: String = "",
    @Json(name = "post_type") val postType: String,
    @Json(name = "content_fingerprint_hash") val contentFingerprintHash: String = "",
    val status: String = "published"
)

@JsonClass(generateAdapter = true)
data class StreamVariantDto(
    @Json(name = "quality_label") val qualityLabel: String = "auto",
    val width: Int = 0,
    val height: Int = 0,
    @Json(name = "bitrate_kbps") val bitrateKbps: Int = 0,
    val codec: String = "h264",
    val container: String = "hls",
    @Json(name = "signed_url") val signedUrl: String = ""
)

@JsonClass(generateAdapter = true)
data class AudioSummaryDto(
    @Json(name = "audio_id") val audioId: String = "",
    @Json(name = "external_track_id") val externalTrackId: String = "",
    val title: String = "Original sound",
    val artist: String = "",
    @Json(name = "artwork_url") val artworkUrl: String = "",
    @Json(name = "preview_url") val previewUrl: String = "",
    @Json(name = "duration_ms") val durationMs: Long = 0L,
    @Json(name = "is_original") val isOriginal: Boolean = true,
    @Json(name = "usage_count") val usageCount: Long = 0L
)

@JsonClass(generateAdapter = true)
data class FeedVideoDto(
    @Json(name = "video_id") val videoId: String,
    @Json(name = "post_id") val postId: String = "",
    @Json(name = "creator_id") val creatorId: String = "",
    @Json(name = "creator_name") val creatorName: String = "",
    @Json(name = "creator_username") val creatorUsername: String = "",
    @Json(name = "creator_avatar_hash") val creatorAvatarHash: String = "",
    @Json(name = "is_following_creator") val isFollowingCreator: Boolean = false,
    @Json(name = "is_owner") val isOwner: Boolean = false,
    val title: String = "",
    val description: String = "",
    @Json(name = "recommendation_label") val recommendationLabel: String = "",
    @Json(name = "original_width") val originalWidth: Int = 720,
    @Json(name = "original_height") val originalHeight: Int = 1280,
    @Json(name = "aspect_ratio") val aspectRatio: Double = 9.0 / 16.0,
    @Json(name = "duration_ms") val durationMs: Long = 0L,
    val codec: String = "h264",
    @Json(name = "file_size") val fileSize: Long = 0L,
    val visibility: String = "public",
    @Json(name = "thumbnail_url") val thumbnailUrl: String = "",
    @Json(name = "stream_url") val streamUrl: String = "",
    @Json(name = "fallback_mp4_url") val fallbackMp4Url: String = "",
    @Json(name = "stream_type") val streamType: String = "mp4",
    @Json(name = "url_expires_at") val urlExpiresAt: Long = 0L,
    val variants: List<StreamVariantDto> = emptyList(),
    val audio: AudioSummaryDto = AudioSummaryDto(),
    val hashtags: List<String> = emptyList(),
    @Json(name = "likes_count") val likesCount: Long = 0L,
    @Json(name = "comments_count") val commentsCount: Long = 0L,
    @Json(name = "shares_count") val sharesCount: Long = 0L,
    @Json(name = "saves_count") val savesCount: Long = 0L,
    @Json(name = "reposts_count") val repostsCount: Long = 0L,
    @Json(name = "views_count") val viewsCount: Long = 0L,
    @Json(name = "is_liked") val isLiked: Boolean = false,
    @Json(name = "is_saved") val isSaved: Boolean = false,
    @Json(name = "is_reposted") val isReposted: Boolean = false,
    @Json(name = "created_at") val createdAt: Long = 0L
)

@JsonClass(generateAdapter = true)
data class VideoFeedPageDto(
    val videos: List<FeedVideoDto> = emptyList(),
    @Json(name = "next_cursor") val nextCursor: String = "",
    @Json(name = "has_more") val hasMore: Boolean = false
)

@JsonClass(generateAdapter = true)
data class RefreshedStreamDto(
    @Json(name = "video_id") val videoId: String,
    @Json(name = "stream_url") val streamUrl: String = "",
    @Json(name = "fallback_mp4_url") val fallbackMp4Url: String = "",
    @Json(name = "thumbnail_url") val thumbnailUrl: String = "",
    @Json(name = "stream_type") val streamType: String = "mp4",
    @Json(name = "url_expires_at") val urlExpiresAt: Long = 0L,
    val variants: List<StreamVariantDto> = emptyList()
)

@JsonClass(generateAdapter = true)
data class WatchProgressRequest(
    @Json(name = "watch_duration_ms") val watchDurationMs: Long,
    @Json(name = "last_position_ms") val lastPositionMs: Long,
    @Json(name = "completion_pct") val completionPct: Double,
    @Json(name = "rewatch_delta") val rewatchDelta: Int = 0
)

@JsonClass(generateAdapter = true)
data class VideoLikeResponse(
    @Json(name = "likes_count") val likesCount: Long = 0L,
    @Json(name = "is_liked") val isLiked: Boolean = false
)

@JsonClass(generateAdapter = true)
data class VideoSaveResponse(
    @Json(name = "saves_count") val savesCount: Long = 0L,
    @Json(name = "is_saved") val isSaved: Boolean = false
)

@JsonClass(generateAdapter = true)
data class VideoShareRequest(val channel: String = "link")

@JsonClass(generateAdapter = true)
data class VideoShareResponse(
    @Json(name = "shares_count") val sharesCount: Long = 0L
)

@JsonClass(generateAdapter = true)
data class VideoRepostResponse(
    @Json(name = "reposts_count") val repostsCount: Long = 0L,
    @Json(name = "is_reposted") val isReposted: Boolean = false
)

@JsonClass(generateAdapter = true)
data class VideoReportRequest(
    val reason: String,
    val details: String = ""
)

@JsonClass(generateAdapter = true)
data class UpdateOwnerVideoRequest(
    val title: String? = null,
    val description: String? = null,
    val visibility: String? = null
)

@JsonClass(generateAdapter = true)
data class HashtagDiscoveryDto(
    val tag: String,
    @Json(name = "video_count") val videoCount: Long = 0L,
    @Json(name = "views_count") val viewsCount: Long = 0L,
    val videos: List<FeedVideoDto> = emptyList(),
    @Json(name = "next_cursor") val nextCursor: String = "",
    @Json(name = "has_more") val hasMore: Boolean = false
)

@JsonClass(generateAdapter = true)
data class AudioDiscoveryDto(
    val audio: AudioSummaryDto,
    val videos: List<FeedVideoDto> = emptyList(),
    @Json(name = "next_cursor") val nextCursor: String = "",
    @Json(name = "has_more") val hasMore: Boolean = false
)

@JsonClass(generateAdapter = true)
data class CreatorSearchDto(
    @Json(name = "user_id") val userId: String,
    @Json(name = "full_name") val fullName: String = "",
    val username: String = "",
    @Json(name = "avatar_fingerprint_hash") val avatarFingerprintHash: String = "",
    @Json(name = "is_following") val isFollowing: Boolean = false
)

@JsonClass(generateAdapter = true)
data class RecentSearchDto(
    val id: String,
    val query: String
)

@JsonClass(generateAdapter = true)
data class FeedSearchResponseDto(
    val query: String = "",
    val videos: List<FeedVideoDto> = emptyList(),
    val hashtags: List<HashtagDto> = emptyList(),
    val creators: List<CreatorSearchDto> = emptyList(),
    val audios: List<AudioSummaryDto> = emptyList(),
    @Json(name = "recent_searches") val recentSearches: List<RecentSearchDto> = emptyList(),
    val trending: List<String> = emptyList(),
    @Json(name = "next_cursor") val nextCursor: String = "",
    @Json(name = "has_more") val hasMore: Boolean = false
)

@JsonClass(generateAdapter = true)
data class SafetyUserDto(
    @Json(name = "user_id") val userId: String,
    @Json(name = "full_name") val fullName: String = "",
    val username: String = "",
    @Json(name = "avatar_fingerprint_hash") val avatarFingerprintHash: String = ""
)

@JsonClass(generateAdapter = true)
data class SafetyPreferencesDto(
    @Json(name = "muted_users") val mutedUsers: List<SafetyUserDto> = emptyList(),
    @Json(name = "blocked_users") val blockedUsers: List<SafetyUserDto> = emptyList()
)

interface TelefamApiService {
    @POST("/v1/auth/otp/send")
    suspend fun sendOtp(@Body request: SendOtpRequest): Response<SendOtpResponse>

    @POST("/v1/auth/otp/verify")
    suspend fun verifyOtp(@Body request: VerifyOtpRequest): Response<AuthSessionDto>

    @POST("/v1/auth/oauth/{provider}")
    suspend fun verifyOAuth(
        @Path("provider") provider: String,
        @Body request: OAuthVerifyRequest
    ): Response<AuthSessionDto>

    @POST("/v1/auth/refresh")
    suspend fun refreshSession(@Body request: RefreshSessionRequest): Response<AuthSessionDto>

    @POST("/v1/auth/logout")
    suspend fun logoutSession(@Header("Authorization") authHeader: String): Response<Unit>

    @GET("/v1/profile/me")
    suspend fun getMyProfile(@Header("Authorization") authHeader: String): Response<MyProfileDto>

    @POST("/v1/profile/avatar")
    suspend fun uploadAvatar(
        @Header("Authorization") authHeader: String,
        @Body imageBytes: RequestBody
    ): Response<AvatarUploadResponse>

    @POST("/v1/profile/setup")
    suspend fun setupProfile(
        @Header("Authorization") authHeader: String,
        @Body request: ProfileSetupRequest
    ): Response<ProfileSetupResponse>

    @GET("/v1/notifications")
    suspend fun listNotifications(
        @Header("Authorization") authHeader: String
    ): Response<NotificationsResponse>

    @POST("/v1/notifications/read")
    suspend fun markNotificationsRead(
        @Header("Authorization") authHeader: String
    ): Response<Unit>

    @GET("/v1/contacts")
    suspend fun listContacts(
        @Header("Authorization") authHeader: String,
        @Query("filter") filter: String = "all",
        @Query("q") query: String = "",
        @Query("cursor") cursor: String = "",
        @Query("limit") limit: Int = 30
    ): Response<ContactsPageDto>

    @POST("/v1/contacts/follow")
    suspend fun setFollowState(
        @Header("Authorization") authHeader: String,
        @Body request: FollowActionRequest
    ): Response<FollowActionResponse>

    @GET("/v1/conversations")
    suspend fun listConversations(
        @Header("Authorization") authHeader: String
    ): Response<ConversationsListDto>

    @POST("/v1/conversations")
    suspend fun createConversation(
        @Header("Authorization") authHeader: String,
        @Body request: CreateConversationRequest
    ): Response<ConversationDto>

    @GET("/v1/conversations/{id}/messages")
    suspend fun listMessages(
        @Header("Authorization") authHeader: String,
        @Path("id") conversationId: String,
        @Query("since_ms") sinceMs: Long = 0L
    ): Response<MessagesListDto>

    @POST("/v1/sync/mutations")
    suspend fun syncMutations(
        @Header("Authorization") authHeader: String,
        @Body request: SyncMutationsRequest
    ): Response<SyncMutationsResponse>

    @GET("/v1/music/search")
    suspend fun searchMusic(
        @Header("Authorization") authHeader: String,
        @Query("q") query: String
    ): Response<MusicSearchResponse>

    @GET("/v1/hashtags/search")
    suspend fun searchHashtags(
        @Header("Authorization") authHeader: String,
        @Query("q") query: String
    ): Response<HashtagSearchResponse>

    @Multipart
    @POST("/v1/posts/media/photos")
    suspend fun uploadPostPhotos(
        @Header("Authorization") authHeader: String,
        @Part photos: List<MultipartBody.Part>
    ): Response<UploadPhotosResponse>

    @Multipart
    @POST("/v1/posts/media/video")
    suspend fun uploadPostVideo(
        @Header("Authorization") authHeader: String,
        @Part video: MultipartBody.Part,
        @Part thumbnail: MultipartBody.Part?,
        @Part("trim_start_ms") trimStartMs: RequestBody,
        @Part("trim_end_ms") trimEndMs: RequestBody,
        @Part("thumbnail_at_ms") thumbnailAtMs: RequestBody,
        @Part("mute_original_audio") muteOriginalAudio: RequestBody,
        @Part("song_preview_url") songPreviewUrl: RequestBody
    ): Response<UploadedVideoDto>

    @GET("/v1/posts/feed")
    suspend fun listFeedPosts(
        @Header("Authorization") authHeader: String,
        @Query("q") query: String = "",
        @Query("limit") limit: Int = 30
    ): Response<FeedPostsResponse>

    @POST("/v1/posts")
    suspend fun createPost(
        @Header("Authorization") authHeader: String,
        @Body request: CreatePostRequest
    ): Response<CreatePostResponse>

    @GET("/v1/feed/for-you")
    suspend fun getForYouFeed(
        @Header("Authorization") authHeader: String,
        @Query("cursor") cursor: String = "",
        @Query("limit") limit: Int = 15
    ): Response<VideoFeedPageDto>

    @GET("/v1/feed/following")
    suspend fun getFollowingFeed(
        @Header("Authorization") authHeader: String,
        @Query("cursor") cursor: String = "",
        @Query("limit") limit: Int = 15
    ): Response<VideoFeedPageDto>

    @GET("/v1/videos/{id}/refresh-stream-url")
    suspend fun refreshStreamUrl(
        @Header("Authorization") authHeader: String,
        @Path("id") videoId: String
    ): Response<RefreshedStreamDto>

    @POST("/v1/videos/{id}/view")
    suspend fun recordVideoView(
        @Header("Authorization") authHeader: String,
        @Path("id") videoId: String,
        @Body request: WatchProgressRequest
    ): Response<Unit>

    @POST("/v1/videos/{id}/watch-progress")
    suspend fun recordWatchProgress(
        @Header("Authorization") authHeader: String,
        @Path("id") videoId: String,
        @Body request: WatchProgressRequest
    ): Response<Unit>

    @POST("/v1/videos/{id}/like")
    suspend fun likeVideo(
        @Header("Authorization") authHeader: String,
        @Path("id") videoId: String
    ): Response<VideoLikeResponse>

    @retrofit2.http.DELETE("/v1/videos/{id}/like")
    suspend fun unlikeVideo(
        @Header("Authorization") authHeader: String,
        @Path("id") videoId: String
    ): Response<VideoLikeResponse>

    @POST("/v1/videos/{id}/save")
    suspend fun saveVideo(
        @Header("Authorization") authHeader: String,
        @Path("id") videoId: String
    ): Response<VideoSaveResponse>

    @retrofit2.http.DELETE("/v1/videos/{id}/save")
    suspend fun unsaveVideo(
        @Header("Authorization") authHeader: String,
        @Path("id") videoId: String
    ): Response<VideoSaveResponse>

    @POST("/v1/videos/{id}/share")
    suspend fun shareVideo(
        @Header("Authorization") authHeader: String,
        @Path("id") videoId: String,
        @Body request: VideoShareRequest
    ): Response<VideoShareResponse>

    @POST("/v1/videos/{id}/repost")
    suspend fun repostVideo(
        @Header("Authorization") authHeader: String,
        @Path("id") videoId: String
    ): Response<VideoRepostResponse>

    @retrofit2.http.DELETE("/v1/videos/{id}/repost")
    suspend fun unrepostVideo(
        @Header("Authorization") authHeader: String,
        @Path("id") videoId: String
    ): Response<VideoRepostResponse>

    @POST("/v1/videos/{id}/not-interested")
    suspend fun markNotInterested(
        @Header("Authorization") authHeader: String,
        @Path("id") videoId: String
    ): Response<Unit>

    @POST("/v1/videos/{id}/report")
    suspend fun reportVideo(
        @Header("Authorization") authHeader: String,
        @Path("id") videoId: String,
        @Body request: VideoReportRequest
    ): Response<Unit>

    @retrofit2.http.PATCH("/v1/videos/{id}")
    suspend fun updateOwnerVideo(
        @Header("Authorization") authHeader: String,
        @Path("id") videoId: String,
        @Body request: UpdateOwnerVideoRequest
    ): Response<FeedVideoDto>

    @retrofit2.http.DELETE("/v1/videos/{id}")
    suspend fun deleteOwnerVideo(
        @Header("Authorization") authHeader: String,
        @Path("id") videoId: String
    ): Response<Unit>

    @POST("/v1/users/{id}/block")
    suspend fun blockUser(
        @Header("Authorization") authHeader: String,
        @Path("id") userId: String
    ): Response<Unit>

    @retrofit2.http.DELETE("/v1/users/{id}/block")
    suspend fun unblockUser(
        @Header("Authorization") authHeader: String,
        @Path("id") userId: String
    ): Response<Unit>

    @POST("/v1/users/{id}/mute")
    suspend fun muteUser(
        @Header("Authorization") authHeader: String,
        @Path("id") userId: String
    ): Response<Unit>

    @retrofit2.http.DELETE("/v1/users/{id}/mute")
    suspend fun unmuteUser(
        @Header("Authorization") authHeader: String,
        @Path("id") userId: String
    ): Response<Unit>

    @GET("/v1/me/saved-videos")
    suspend fun listSavedVideos(
        @Header("Authorization") authHeader: String,
        @Query("cursor") cursor: String = "",
        @Query("limit") limit: Int = 21
    ): Response<VideoFeedPageDto>

    @GET("/v1/me/safety")
    suspend fun listSafetyPreferences(
        @Header("Authorization") authHeader: String
    ): Response<SafetyPreferencesDto>

    @GET("/v1/hashtags/{tag}/videos")
    suspend fun getHashtagDiscovery(
        @Header("Authorization") authHeader: String,
        @Path("tag") tag: String,
        @Query("cursor") cursor: String = "",
        @Query("limit") limit: Int = 21
    ): Response<HashtagDiscoveryDto>

    @GET("/v1/audios/{id}/videos")
    suspend fun getAudioDiscovery(
        @Header("Authorization") authHeader: String,
        @Path("id") audioId: String,
        @Query("cursor") cursor: String = "",
        @Query("limit") limit: Int = 21
    ): Response<AudioDiscoveryDto>

    @GET("/v1/search")
    suspend fun searchAll(
        @Header("Authorization") authHeader: String,
        @Query("q") query: String,
        @Query("cursor") cursor: String = "",
        @Query("limit") limit: Int = 20
    ): Response<FeedSearchResponseDto>

    @retrofit2.http.DELETE("/v1/search/history")
    suspend fun clearSearchHistory(
        @Header("Authorization") authHeader: String
    ): Response<Unit>

    @retrofit2.http.DELETE("/v1/search/history/{id}")
    suspend fun deleteSearchHistoryItem(
        @Header("Authorization") authHeader: String,
        @Path("id") id: String
    ): Response<Unit>
}

class CountingBytesRequestBody(
    private val bytes: ByteArray,
    private val mediaType: MediaType,
    private val onProgress: (written: Long, total: Long) -> Unit
) : RequestBody() {
    override fun contentType(): MediaType = mediaType
    override fun contentLength(): Long = bytes.size.toLong()
    override fun writeTo(sink: BufferedSink) {
        val total = bytes.size.toLong().coerceAtLeast(1L)
        var offset = 0
        val chunk = 16384
        while (offset < bytes.size) {
            val len = minOf(chunk, bytes.size - offset)
            sink.write(bytes, offset, len)
            offset += len
            onProgress(offset.toLong(), total)
        }
    }
}

class CountingStreamRequestBody(
    private val totalBytes: Long,
    private val mediaType: MediaType,
    private val openStream: () -> InputStream?,
    private val onProgress: (written: Long, total: Long) -> Unit
) : RequestBody() {
    override fun contentType(): MediaType = mediaType
    override fun contentLength(): Long = if (totalBytes > 0L) totalBytes else -1L
    override fun writeTo(sink: BufferedSink) {
        val stream = openStream() ?: throw IllegalStateException("Stream unavailable")
        stream.use { input ->
            val buf = ByteArray(32768)
            var uploaded = 0L
            val effectiveTotal = totalBytes.coerceAtLeast(1L)
            while (true) {
                val read = input.read(buf)
                if (read == -1) break
                sink.write(buf, 0, read)
                uploaded += read
                onProgress(uploaded, effectiveTotal)
            }
        }
    }
}

object TelefamNetworkClient {
    val moshi: Moshi = Moshi.Builder()
        .addLast(KotlinJsonAdapterFactory())
        .build()

    private fun resolvedBaseUrl(): String {
        val rawUrl = BuildConfig.TELEFAM_API_BASE_URL
            .trim()
            .ifBlank { "https://api.telefam.app" }
            .let { if (it.endsWith("/")) it else "$it/" }
        val uri = runCatching { java.net.URI(rawUrl) }.getOrNull()
        val host = uri?.host?.lowercase().orEmpty()
        val isLocalLoopback = host == "localhost" || host == "127.0.0.1" || host == "10.0.2.2"
        return when {
            rawUrl.startsWith("https://") && host.isNotBlank() -> rawUrl
            rawUrl.startsWith("http://") && isLocalLoopback -> rawUrl
            else -> "https://api.telefam.app/"
        }
    }

    fun baseUrl(): String = resolvedBaseUrl()

    fun resolveMediaUrl(rawPathOrUrl: String): String {
        val trimmed = rawPathOrUrl.trim()
        if (trimmed.isEmpty()) return ""
        if (trimmed.startsWith("https://") || trimmed.startsWith("http://")) return trimmed
        val base = resolvedBaseUrl().trimEnd('/')
        val path = if (trimmed.startsWith("/")) trimmed else "/$trimmed"
        return base + path
    }

    val mediaOkHttpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .build()
    }

    fun createService(uploadTimeoutSeconds: Long = 15L): TelefamApiService {
        val baseUrl = resolvedBaseUrl()
        val client = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(uploadTimeoutSeconds, TimeUnit.SECONDS)
            .writeTimeout(uploadTimeoutSeconds, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .build()

        return runCatching {
            Retrofit.Builder()
                .baseUrl(baseUrl)
                .client(client)
                .addConverterFactory(MoshiConverterFactory.create(moshi))
                .build()
                .create(TelefamApiService::class.java)
        }.getOrElse {
            Retrofit.Builder()
                .baseUrl("https://api.telefam.app/")
                .client(client)
                .addConverterFactory(MoshiConverterFactory.create(moshi))
                .build()
                .create(TelefamApiService::class.java)
        }
    }

    fun jpegBody(bytes: ByteArray): RequestBody =
        bytes.toRequestBody("image/jpeg".toMediaType())

    fun textBody(value: String): RequestBody =
        value.toRequestBody("text/plain".toMediaType())
}

class AndroidNetworkMonitor(context: Context) {
    private val cm: ConnectivityManager? =
        runCatching { context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager }.getOrNull()
    private val _quality = MutableStateFlow(currentQuality())
    val quality: StateFlow<NetworkQuality> = _quality.asStateFlow()

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            _quality.value = currentQuality()
        }

        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
            _quality.value = evaluate(capabilities)
        }

        override fun onLost(network: Network) {
            _quality.value = currentQuality()
        }
    }

    init {
        val manager = cm
        if (manager != null) {
            val req = NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()
            runCatching { manager.registerNetworkCallback(req, callback) }
        }
    }

    private fun currentQuality(): NetworkQuality {
        val manager = cm ?: return NetworkQuality.OFFLINE
        return runCatching {
            val active = manager.activeNetwork ?: return NetworkQuality.OFFLINE
            val caps = manager.getNetworkCapabilities(active) ?: return NetworkQuality.OFFLINE
            evaluate(caps)
        }.getOrDefault(NetworkQuality.OFFLINE)
    }

    private fun evaluate(caps: NetworkCapabilities): NetworkQuality {
        return if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
            NetworkQuality.ONLINE
        } else {
            NetworkQuality.OFFLINE
        }
    }
}
