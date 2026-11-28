package com.telefam.company.app.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.telephony.TelephonyManager
import android.media.MediaMetadataRetriever
import android.provider.OpenableColumns
import com.squareup.moshi.JsonClass
import com.squareup.moshi.Types
import com.telefam.company.app.core.CooldownState
import com.telefam.company.app.core.NetworkQuality
import com.telefam.company.app.core.TelefamNativeBridge
import com.telefam.company.app.data.local.CachedContactEntity
import com.telefam.company.app.data.local.ConversationEntity
import com.telefam.company.app.data.local.CooldownEntity
import com.telefam.company.app.data.local.EncryptedKvEntity
import com.telefam.company.app.data.local.MessageEntity
import com.telefam.company.app.data.local.OutboxMutationEntity
import com.telefam.company.app.data.local.QueuedPostEntity
import com.telefam.company.app.data.local.TelefamDao
import com.telefam.company.app.network.AuthSessionDto
import com.telefam.company.app.network.BackgroundPhotoDto
import com.telefam.company.app.network.CountingBytesRequestBody
import com.telefam.company.app.network.CountingStreamRequestBody
import com.telefam.company.app.network.CreateConversationRequest
import com.telefam.company.app.network.CreatePostRequest
import com.telefam.company.app.network.CreatePostResponse
import com.telefam.company.app.network.FeedPostDto
import com.telefam.company.app.network.FeedPostsResponse
import com.telefam.company.app.network.FollowActionRequest
import com.telefam.company.app.network.HashtagDto
import com.telefam.company.app.network.MusicTrackDto
import com.telefam.company.app.network.MutationWireItem
import com.telefam.company.app.network.MyProfileDto
import com.telefam.company.app.network.NotificationDto
import com.telefam.company.app.network.NotificationsResponse
import com.telefam.company.app.network.OAuthVerifyRequest
import com.telefam.company.app.network.OtherUserProfileDto
import com.telefam.company.app.network.OwnerProfileItemsPageDto
import com.telefam.company.app.network.PostEngageRequest
import com.telefam.company.app.network.PostEngageResponse
import com.telefam.company.app.network.ProfileSetupRequest
import com.telefam.company.app.network.RefreshSessionRequest
import com.telefam.company.app.network.SendOtpRequest
import com.telefam.company.app.network.SetPostVisibilityRequest
import com.telefam.company.app.network.SetUserNicknameRequest
import com.telefam.company.app.network.SubmitUserReportRequest
import com.telefam.company.app.network.SyncMutationsRequest
import com.telefam.company.app.network.TelefamApiService
import com.telefam.company.app.network.TelefamNetworkClient
import com.telefam.company.app.network.VerifyOtpRequest
import com.telefam.company.app.network.ViewerNicknamesResponse
import com.telefam.company.app.security.DeviceIdentity
import com.telefam.company.app.security.TelefamCryptoVault
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

data class ConversationModel(
    val id: String,
    val title: String,
    val updatedAtMs: Long
)

data class MessageModel(
    val id: String,
    val conversationId: String,
    val senderId: String,
    val clientMutationId: String,
    val body: String,
    val createdAtMs: Long,
    val isPendingSync: Boolean
)

data class ContactModel(
    val userId: String,
    val fullName: String,
    val username: String,
    val location: String,
    val avatarFingerprintHash: String,
    val isFollowing: Boolean,
    val followsMe: Boolean,
    val relationship: String,
    val riskScore: Int
)

data class ContactsPageModel(
    val contacts: List<ContactModel>,
    val nextCursor: String,
    val hasMore: Boolean
)

@JsonClass(generateAdapter = true)
data class QueuedPostPayload(
    val queueId: String,
    val postType: String,
    val body: String = "",
    val bgColorHex: String = "",
    val bgThemeId: String = "",
    val fontFamily: String = "classic",
    val songId: String = "",
    val songTitle: String = "",
    val songArtist: String = "",
    val songPreviewUrl: String = "",
    val muteOriginalAudio: Boolean = false,
    val trimStartMs: Long = 0L,
    val trimEndMs: Long = 0L,
    val thumbnailAtMs: Long = 0L,
    val cachedPhotoPaths: List<String> = emptyList(),
    val cachedVideoPath: String = "",
    val cachedThumbPath: String = "",
    val taggedUserIds: List<String> = emptyList(),
    val hashtags: List<String> = emptyList()
)

data class ExtractedPhotoItem(
    val uri: Uri,
    val thumbnail: Bitmap,
    val dhash: String,
    val contentId: String
)

data class VideoFrameItem(
    val timestampMs: Long,
    val thumbnail: Bitmap,
    val dhash: String
)

data class ExtractedVideoInfo(
    val uri: Uri,
    val sizeBytes: Long,
    val width: Int,
    val height: Int,
    val durationMs: Long,
    val frames: List<VideoFrameItem>,
    val contentId: String
)

sealed interface RepoResult<out T> {
    data class Success<T>(val data: T) : RepoResult<T>
    data class Failure(val userMessage: String) : RepoResult<Nothing>
}

class TelefamRepository(
    private val context: Context,
    private val dao: TelefamDao,
    private val api: TelefamApiService,
    private val vault: TelefamCryptoVault,
    val bridge: TelefamNativeBridge,
    val deviceIdentity: DeviceIdentity
) {
    private val sessionAdapter = TelefamNetworkClient.moshi.adapter(AuthSessionDto::class.java)
    private val myProfileAdapter = TelefamNetworkClient.moshi.adapter(MyProfileDto::class.java)
    private val otherProfileAdapter = TelefamNetworkClient.moshi.adapter(OtherUserProfileDto::class.java)
    private val viewerNicknamesAdapter = TelefamNetworkClient.moshi.adapter(ViewerNicknamesResponse::class.java)
    private val ownerItemsPageAdapter = TelefamNetworkClient.moshi.adapter(OwnerProfileItemsPageDto::class.java)
    private val bgPathListType = Types.newParameterizedType(List::class.java, String::class.java)
    private val bgPathListAdapter = TelefamNetworkClient.moshi.adapter<List<String>>(bgPathListType)
    private val feedResponseAdapter = TelefamNetworkClient.moshi.adapter(FeedPostsResponse::class.java)
    private val notificationsResponseAdapter = TelefamNetworkClient.moshi.adapter(NotificationsResponse::class.java)
    private val mapType = Types.newParameterizedType(Map::class.java, String::class.java, String::class.java)
    private val payloadAdapter = TelefamNetworkClient.moshi.adapter<Map<String, String>>(mapType)
    private val queuedPostAdapter = TelefamNetworkClient.moshi.adapter(QueuedPostPayload::class.java)
    private val uploadApi: TelefamApiService by lazy {
        TelefamNetworkClient.createService(uploadTimeoutSeconds = 120L)
    }
    private val ownerMediaCacheDir: File by lazy {
        File(context.filesDir, "owner_profile_cache").apply { mkdirs() }
    }
    private val otherMediaCacheDir: File by lazy {
        File(context.cacheDir, "other_profile_cache").apply { mkdirs() }
    }

    fun observeConversations(): Flow<List<ConversationModel>> =
        dao.observeConversations().map { rows ->
            rows.mapNotNull { row ->
                runCatching {
                    ConversationModel(
                        id = row.id,
                        title = vault.decryptString(row.titleEncrypted),
                        updatedAtMs = row.updatedAtMs
                    )
                }.getOrNull()
            }
        }

    fun observeMessages(conversationId: String): Flow<List<MessageModel>> =
        dao.observeMessages(conversationId).map { rows ->
            rows.mapNotNull { row ->
                runCatching {
                    MessageModel(
                        id = row.id,
                        conversationId = row.conversationId,
                        senderId = row.senderId,
                        clientMutationId = row.clientMutationId,
                        body = vault.decryptString(row.bodyEncrypted),
                        createdAtMs = row.createdAtMs,
                        isPendingSync = row.isPendingSync
                    )
                }.getOrNull()
            }
        }

    fun observePendingSyncCount(): Flow<Int> = dao.observePendingCount()

    fun observeCachedContacts(): Flow<List<ContactModel>> =
        dao.observeCachedContacts().map { rows ->
            rows.mapNotNull { row ->
                runCatching {
                    ContactModel(
                        userId = row.userId,
                        fullName = vault.decryptString(row.fullNameEncrypted),
                        username = vault.decryptString(row.usernameEncrypted),
                        location = vault.decryptString(row.locationEncrypted),
                        avatarFingerprintHash = row.avatarFingerprintHash,
                        isFollowing = row.isFollowing,
                        followsMe = row.followsMe,
                        relationship = bridge.computeRelationship(row.isFollowing, row.followsMe),
                        riskScore = row.riskScore
                    )
                }.getOrNull()
            }
        }

    suspend fun loadThemeDark(): Boolean {
        val raw = dao.getKv("theme_dark") ?: return true
        return runCatching { vault.decryptString(raw) == "true" }.getOrDefault(true)
    }

    suspend fun saveThemeDark(isDark: Boolean) {
        dao.putKv(EncryptedKvEntity("theme_dark", vault.encryptString(isDark.toString())))
    }

    suspend fun loadEncryptedSession(): AuthSessionDto? {
        val raw = dao.getKv("session_json") ?: return null
        return runCatching {
            sessionAdapter.fromJson(vault.decryptString(raw))
        }.getOrNull()
    }

    suspend fun saveEncryptedSession(session: AuthSessionDto) {
        val json = sessionAdapter.toJson(session)
        dao.putKv(EncryptedKvEntity(key = "session_json", valueEncrypted = vault.encryptString(json)))
    }

    suspend fun clearSession() {
        dao.deleteKv("session_json")
        dao.deleteKv("my_profile_json")
        dao.deleteKv("owner_avatar_local_path")
        dao.deleteKv("owner_bg_cache_json")
        for (tab in listOf("posts", "reposts", "locked", "saved")) {
            dao.deleteKv("owner_items_$tab")
        }
        dao.deleteKv("feed_cache_json")
        dao.deleteKv("notifications_json")
        dao.clearConversations()
        dao.clearMessages()
        dao.clearOutbox()
        dao.clearCachedContacts()
        dao.clearQueuedPosts()
        dao.clearAllCachedFeedVideos()
        runCatching { ownerMediaCacheDir.deleteRecursively() }
    }

    suspend fun logoutFromServer() {
        val session = loadEncryptedSession()
        if (session != null && session.accessToken.isNotBlank()) {
            runCatching { api.logoutSession("Bearer ${session.accessToken}") }
        }
        clearSession()
    }

    suspend fun refreshSessionToken(): AuthSessionDto? {
        val current = loadEncryptedSession() ?: return null
        if (current.refreshToken.isBlank()) return null
        return runCatching {
            val res = api.refreshSession(
                RefreshSessionRequest(
                    refreshToken = current.refreshToken,
                    deviceFingerprint = deviceIdentity.deviceFingerprint,
                    hardwareAttestation = deviceIdentity.hardwareAttestationHash
                )
            )
            val body = res.body()
            if (res.isSuccessful && body != null) {
                saveEncryptedSession(body)
                body
            } else {
                null
            }
        }.getOrNull()
    }

    internal suspend fun <T> withAuthedApi(call: suspend (String) -> retrofit2.Response<T>): retrofit2.Response<T>? {
        val session = loadEncryptedSession() ?: return null
        val first = call("Bearer ${session.accessToken}")
        if (first.code() != 401) return first
        val refreshed = refreshSessionToken() ?: return first
        return call("Bearer ${refreshed.accessToken}")
    }

    suspend fun loadCachedMyProfile(): MyProfileDto? {
        val raw = dao.getKv("my_profile_json") ?: return null
        return runCatching { myProfileAdapter.fromJson(vault.decryptString(raw)) }.getOrNull()
    }

    suspend fun cacheMyProfile(profile: MyProfileDto) {
        dao.putKv(EncryptedKvEntity("my_profile_json", vault.encryptString(myProfileAdapter.toJson(profile))))
    }

    suspend fun fetchMyProfile(): RepoResult<MyProfileDto> {
        return try {
            val res = withAuthedApi { auth -> api.getMyProfile(auth) }
                ?: return RepoResult.Failure(bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) {
                cacheMyProfile(body)
                RepoResult.Success(body)
            } else {
                RepoResult.Failure(bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    suspend fun loadCachedFeedPosts(): List<FeedPostDto> {
        val raw = dao.getKv("feed_cache_json") ?: return emptyList()
        return runCatching {
            feedResponseAdapter.fromJson(vault.decryptString(raw))?.posts.orEmpty()
        }.getOrDefault(emptyList())
    }

    suspend fun fetchFeedPosts(query: String): RepoResult<List<FeedPostDto>> {
        return try {
            val trimmed = query.trim()
            val res = withAuthedApi { auth -> api.listFeedPosts(auth, trimmed, 30) }
                ?: return RepoResult.Failure(bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) {
                if (trimmed.isEmpty()) {
                    dao.putKv(EncryptedKvEntity("feed_cache_json", vault.encryptString(feedResponseAdapter.toJson(body))))
                }
                RepoResult.Success(body.posts)
            } else {
                RepoResult.Failure(bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    suspend fun loadCachedNotifications(): List<NotificationDto> {
        val raw = dao.getKv("notifications_json") ?: return emptyList()
        return runCatching {
            notificationsResponseAdapter.fromJson(vault.decryptString(raw))?.notifications.orEmpty()
        }.getOrDefault(emptyList())
    }

    suspend fun fetchNotifications(): RepoResult<List<NotificationDto>> {
        return try {
            val res = withAuthedApi { auth -> api.listNotifications(auth) }
                ?: return RepoResult.Failure(bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) {
                dao.putKv(
                    EncryptedKvEntity(
                        "notifications_json",
                        vault.encryptString(notificationsResponseAdapter.toJson(body))
                    )
                )
                RepoResult.Success(body.notifications)
            } else {
                RepoResult.Failure(bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    suspend fun markNotificationsRead(): Boolean {
        return runCatching {
            val res = withAuthedApi { auth -> api.markNotificationsRead(auth) } ?: return false
            res.isSuccessful
        }.getOrDefault(false)
    }

    fun suggestDeviceCountryIso(): String {
        val carrierIso = runCatching {
            val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            tm?.networkCountryIso?.takeIf { it.isNotBlank() } ?: tm?.simCountryIso.orEmpty()
        }.getOrDefault("")
        val tzId = TimeZone.getDefault().id
        val localeIso = Locale.getDefault().country
        return bridge.suggestCountryIso(carrierIso, tzId, localeIso)
    }

    suspend fun checkCooldown(email: String): CooldownState {
        val nowSec = System.currentTimeMillis() / 1000L
        val hash = TelefamNativeBridge.sha256Hex(email.trim().lowercase())
        val record = dao.getCooldown(hash) ?: return CooldownState(0L, 0, 0, true)
        val rem = (record.blockedUntilSec - nowSec).coerceAtLeast(0L)
        val tier = if (record.resendCount > 0) {
            TelefamNativeBridge.cooldownDurationForCount(record.resendCount).second
        } else 0
        return CooldownState(
            remainingSeconds = rem,
            tierIndex = tier,
            resendCount = record.resendCount,
            canResend = rem == 0L
        )
    }

    suspend fun sendOtp(email: String): RepoResult<Long> {
        val trimmed = email.trim()
        if (!bridge.validateEmail(trimmed)) {
            return RepoResult.Failure("Please enter a valid email address.")
        }
        val nowSec = System.currentTimeMillis() / 1000L
        val ipFp = bridge.computeIpFingerprint("android-edge", "local")
        if (!bridge.allowRateLimit(trimmed, deviceIdentity.deviceFingerprint, ipFp, nowSec)) {
            return RepoResult.Failure(bridge.sanitizeError(429))
        }

        val currentCooldown = checkCooldown(trimmed)
        if (!currentCooldown.canResend) {
            return RepoResult.Success(currentCooldown.remainingSeconds)
        }

        return try {
            val response = api.sendOtp(
                SendOtpRequest(
                    email = trimmed,
                    deviceFingerprint = deviceIdentity.deviceFingerprint,
                    hardwareAttestation = deviceIdentity.hardwareAttestationHash,
                    deviceName = deviceIdentity.deviceName
                )
            )
            if (response.isSuccessful && response.body() != null) {
                val hash = TelefamNativeBridge.sha256Hex(trimmed.lowercase())
                val prev = dao.getCooldown(hash)
                val nextCount = if (prev != null && (nowSec - prev.lastSentAtSec) <= 86_400L) {
                    prev.resendCount + 1
                } else {
                    1
                }
                val (localDur, _) = TelefamNativeBridge.cooldownDurationForCount(nextCount)
                val effectiveDur = maxOf(localDur, response.body()!!.cooldownSeconds)
                dao.upsertCooldown(
                    CooldownEntity(
                        emailHash = hash,
                        resendCount = nextCount,
                        blockedUntilSec = nowSec + effectiveDur,
                        lastSentAtSec = nowSec
                    )
                )
                RepoResult.Success(effectiveDur)
            } else {
                RepoResult.Failure(bridge.sanitizeError(response.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    suspend fun verifyOtpOrMagicLink(
        email: String,
        otp: String,
        magicToken: String? = null
    ): RepoResult<AuthSessionDto> {
        val trimmedEmail = email.trim()
        if (magicToken == null && !bridge.validateOtp(otp)) {
            return RepoResult.Failure("Please enter the 6-digit verification code.")
        }
        return try {
            val response = api.verifyOtp(
                VerifyOtpRequest(
                    email = trimmedEmail,
                    otp = otp,
                    magicToken = magicToken,
                    deviceFingerprint = deviceIdentity.deviceFingerprint,
                    hardwareAttestation = deviceIdentity.hardwareAttestationHash,
                    deviceName = deviceIdentity.deviceName
                )
            )
            val body = response.body()
            if (response.isSuccessful && body != null) {
                dao.deleteCooldown(TelefamNativeBridge.sha256Hex(trimmedEmail.lowercase()))
                saveEncryptedSession(body)
                RepoResult.Success(body)
            } else {
                RepoResult.Failure(bridge.sanitizeError(response.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    suspend fun verifyGoogleIdToken(idToken: String): RepoResult<AuthSessionDto> {
        return try {
            val response = api.verifyOAuth(
                provider = "google",
                request = OAuthVerifyRequest(
                    idToken = idToken,
                    deviceFingerprint = deviceIdentity.deviceFingerprint,
                    hardwareAttestation = deviceIdentity.hardwareAttestationHash,
                    deviceName = deviceIdentity.deviceName
                )
            )
            val body = response.body()
            if (response.isSuccessful && body != null) {
                saveEncryptedSession(body)
                RepoResult.Success(body)
            } else {
                RepoResult.Failure(bridge.sanitizeError(response.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    suspend fun uploadSanitizedAvatar(jpegBytes: ByteArray): RepoResult<String> {
        return try {
            val res = withAuthedApi { auth ->
                api.uploadAvatar(
                    authHeader = auth,
                    imageBytes = TelefamNetworkClient.jpegBody(jpegBytes)
                )
            } ?: return RepoResult.Failure(bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) {
                saveLocalAvatarBytes(body.avatarFingerprintHash, jpegBytes)
                val cached = loadCachedMyProfile()
                if (cached != null) {
                    cacheMyProfile(
                        cached.copy(
                            avatarFingerprintHash = body.avatarFingerprintHash,
                            avatarUrl = "/v1/profile/avatar?v=${body.avatarFingerprintHash}"
                        )
                    )
                }
                RepoResult.Success(body.avatarFingerprintHash)
            } else {
                RepoResult.Failure(bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    suspend fun completeProfileSetup(
        request: ProfileSetupRequest,
        quality: NetworkQuality
    ): RepoResult<AuthSessionDto> {
        val session = loadEncryptedSession() ?: return RepoResult.Failure(bridge.sanitizeError(401))
        val updatedSession = session.copy(
            displayName = request.fullName.trim(),
            profileCompleted = true
        )
        val existingCached = loadCachedMyProfile()
        val optimisticProfile = (existingCached ?: MyProfileDto(userId = session.userId, email = session.email)).copy(
            fullName = request.fullName.trim(),
            username = request.username.trim().lowercase(),
            countryIso = request.countryIso.uppercase(),
            phoneNumber = request.phoneNumber.trim(),
            gender = request.gender,
            dateOfBirth = request.dateOfBirth,
            location = request.location.trim(),
            bio = request.bio.trim().take(150),
            avatarFingerprintHash = request.avatarFingerprintHash.ifBlank { existingCached?.avatarFingerprintHash.orEmpty() },
            profileCompleted = true
        )

        if (quality == NetworkQuality.OFFLINE) {
            val payloadMap = mapOf(
                "full_name" to request.fullName,
                "username" to request.username,
                "country_iso" to request.countryIso,
                "phone_number" to request.phoneNumber,
                "gender" to request.gender,
                "date_of_birth" to request.dateOfBirth,
                "location" to request.location,
                "bio" to request.bio,
                "avatar_fingerprint_hash" to request.avatarFingerprintHash
            )
            dao.enqueueOutbox(
                OutboxMutationEntity(
                    mutationId = UUID.randomUUID().toString(),
                    actionType = "profile_setup",
                    payloadEncrypted = vault.encryptString(payloadAdapter.toJson(payloadMap)),
                    createdAtMs = System.currentTimeMillis(),
                    attemptCount = 0
                )
            )
            saveEncryptedSession(updatedSession)
            cacheMyProfile(optimisticProfile)
            return RepoResult.Success(updatedSession)
        }

        return try {
            val res = withAuthedApi { auth -> api.setupProfile(auth, request) }
                ?: return RepoResult.Failure(bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) {
                saveEncryptedSession(updatedSession)
                cacheMyProfile(body)
                RepoResult.Success(updatedSession)
            } else {
                RepoResult.Failure(bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    suspend fun fetchContactsPage(
        filter: String,
        query: String,
        cursor: String,
        limit: Int = 30
    ): RepoResult<ContactsPageModel> {
        val session = loadEncryptedSession() ?: return RepoResult.Failure(bridge.sanitizeError(401))
        return try {
            val res = api.listContacts(
                authHeader = "Bearer ${session.accessToken}",
                filter = filter,
                query = query,
                cursor = cursor,
                limit = limit
            )
            val body = res.body()
            if (res.isSuccessful && body != null) {
                val baseOffset = cursor.toIntOrNull() ?: 0
                val models = body.contacts.map { dto ->
                    ContactModel(
                        userId = dto.userId,
                        fullName = dto.fullName,
                        username = dto.username,
                        location = dto.location,
                        avatarFingerprintHash = dto.avatarFingerprintHash,
                        isFollowing = dto.isFollowing,
                        followsMe = dto.followsMe,
                        relationship = bridge.computeRelationship(dto.isFollowing, dto.followsMe),
                        riskScore = dto.riskScore
                    )
                }
                val entities = models.mapIndexed { idx, c ->
                    CachedContactEntity(
                        userId = c.userId,
                        fullNameEncrypted = vault.encryptString(c.fullName),
                        usernameEncrypted = vault.encryptString(c.username),
                        locationEncrypted = vault.encryptString(c.location),
                        avatarFingerprintHash = c.avatarFingerprintHash,
                        isFollowing = c.isFollowing,
                        followsMe = c.followsMe,
                        riskScore = c.riskScore,
                        updatedOrder = (baseOffset + idx).toLong()
                    )
                }
                if (filter == "all" && query.isBlank() && cursor.isBlank()) {
                    dao.clearCachedContacts()
                }
                if (entities.isNotEmpty()) {
                    dao.upsertCachedContacts(entities)
                }
                RepoResult.Success(
                    ContactsPageModel(
                        contacts = models,
                        nextCursor = body.nextCursor,
                        hasMore = body.hasMore
                    )
                )
            } else {
                RepoResult.Failure(bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    suspend fun toggleFollowOfflineFirst(
        contact: ContactModel,
        quality: NetworkQuality
    ): RepoResult<ContactModel> {
        val session = loadEncryptedSession() ?: return RepoResult.Failure(bridge.sanitizeError(401))
        val nowSec = System.currentTimeMillis() / 1000L
        if (!bridge.allowFollowRateLimit(session.userId, nowSec)) {
            return RepoResult.Failure("Try again later")
        }

        val nextFollowing = !contact.isFollowing
        val optimistic = contact.copy(
            isFollowing = nextFollowing,
            relationship = bridge.computeRelationship(nextFollowing, contact.followsMe)
        )
        dao.updateContactFollowing(contact.userId, nextFollowing)

        val actionType = if (nextFollowing) "follow_user" else "unfollow_user"
        val enqueueMutation: suspend () -> Unit = {
            val payloadJson = payloadAdapter.toJson(mapOf("target_user_id" to contact.userId))
            dao.enqueueOutbox(
                OutboxMutationEntity(
                    mutationId = UUID.randomUUID().toString(),
                    actionType = actionType,
                    payloadEncrypted = vault.encryptString(payloadJson),
                    createdAtMs = System.currentTimeMillis(),
                    attemptCount = 0
                )
            )
        }

        if (quality == NetworkQuality.OFFLINE) {
            enqueueMutation()
            return RepoResult.Success(optimistic)
        }

        return try {
            val res = api.setFollowState(
                authHeader = "Bearer ${session.accessToken}",
                request = FollowActionRequest(
                    targetUserId = contact.userId,
                    follow = nextFollowing
                )
            )
            val body = res.body()
            if (res.isSuccessful && body != null) {
                dao.updateContactFollowing(contact.userId, body.isFollowing)
                RepoResult.Success(
                    contact.copy(
                        isFollowing = body.isFollowing,
                        followsMe = body.followsMe,
                        relationship = bridge.computeRelationship(body.isFollowing, body.followsMe),
                        riskScore = body.riskScore
                    )
                )
            } else if (res.code() == 429) {
                dao.updateContactFollowing(contact.userId, contact.isFollowing)
                RepoResult.Failure("Try again later")
            } else {
                dao.updateContactFollowing(contact.userId, contact.isFollowing)
                RepoResult.Failure(bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            enqueueMutation()
            RepoResult.Success(optimistic)
        }
    }

    suspend fun createConversationOfflineFirst(title: String, quality: NetworkQuality): RepoResult<String> {
        val trimmed = title.trim()
        if (trimmed.isEmpty()) return RepoResult.Failure(bridge.sanitizeError(400))
        val session = loadEncryptedSession() ?: return RepoResult.Failure(bridge.sanitizeError(401))

        if (quality != NetworkQuality.OFFLINE) {
            runCatching {
                val res = api.createConversation("Bearer ${session.accessToken}", CreateConversationRequest(trimmed))
                if (res.isSuccessful && res.body() != null) {
                    val dto = res.body()!!
                    dao.upsertConversations(
                        listOf(
                            ConversationEntity(
                                id = dto.id,
                                titleEncrypted = vault.encryptString(dto.title),
                                updatedAtMs = dto.updatedAt
                            )
                        )
                    )
                    return RepoResult.Success(dto.id)
                }
            }
        }

        val localId = UUID.randomUUID().toString()
        val nowMs = System.currentTimeMillis()
        dao.upsertConversations(
            listOf(
                ConversationEntity(
                    id = localId,
                    titleEncrypted = vault.encryptString(trimmed),
                    updatedAtMs = nowMs
                )
            )
        )
        val payloadJson = payloadAdapter.toJson(mapOf("title" to trimmed, "local_id" to localId))
        dao.enqueueOutbox(
            OutboxMutationEntity(
                mutationId = localId,
                actionType = "create_conversation",
                payloadEncrypted = vault.encryptString(payloadJson),
                createdAtMs = nowMs,
                attemptCount = 0
            )
        )
        return RepoResult.Success(localId)
    }

    suspend fun sendMessageOfflineFirst(
        conversationId: String,
        body: String,
        quality: NetworkQuality
    ) {
        val trimmed = body.trim()
        if (trimmed.isEmpty()) return
        val session = loadEncryptedSession() ?: return
        val mutId = UUID.randomUUID().toString()
        val nowMs = System.currentTimeMillis()

        dao.upsertMessages(
            listOf(
                MessageEntity(
                    id = mutId,
                    conversationId = conversationId,
                    senderId = session.userId,
                    clientMutationId = mutId,
                    bodyEncrypted = vault.encryptString(trimmed),
                    createdAtMs = nowMs,
                    isPendingSync = true
                )
            )
        )
        val payloadJson = payloadAdapter.toJson(
            mapOf("conversation_id" to conversationId, "body" to trimmed)
        )
        dao.enqueueOutbox(
            OutboxMutationEntity(
                mutationId = mutId,
                actionType = "send_message",
                payloadEncrypted = vault.encryptString(payloadJson),
                createdAtMs = nowMs,
                attemptCount = 0
            )
        )
        if (quality != NetworkQuality.OFFLINE) {
            syncPendingAndRefresh(quality, conversationId)
        }
    }

    suspend fun deleteMessageOfflineFirst(messageId: String, quality: NetworkQuality) {
        dao.deleteMessageById(messageId)
        val mutId = UUID.randomUUID().toString()
        val payloadJson = payloadAdapter.toJson(mapOf("message_id" to messageId))
        dao.enqueueOutbox(
            OutboxMutationEntity(
                mutationId = mutId,
                actionType = "delete_message",
                payloadEncrypted = vault.encryptString(payloadJson),
                createdAtMs = System.currentTimeMillis(),
                attemptCount = 0
            )
        )
        if (quality != NetworkQuality.OFFLINE) {
            syncPendingAndRefresh(quality, null)
        }
    }

    suspend fun syncPendingAndRefresh(quality: NetworkQuality, activeConversationId: String?) {
        if (quality == NetworkQuality.OFFLINE) return
        val session = loadEncryptedSession() ?: return
        val authHeader = "Bearer ${session.accessToken}"
        val batchSize = bridge.adaptiveBatchSize(quality).coerceAtLeast(1)

        val pending = dao.peekOutbox(batchSize)
        if (pending.isNotEmpty()) {
            val wireItems = pending.mapNotNull { entry ->
                runCatching {
                    val map = payloadAdapter.fromJson(vault.decryptString(entry.payloadEncrypted)).orEmpty()
                    MutationWireItem(
                        mutationId = entry.mutationId,
                        actionType = entry.actionType,
                        payload = map
                    )
                }.getOrNull()
            }
            if (wireItems.isNotEmpty()) {
                runCatching {
                    val res = api.syncMutations(authHeader, SyncMutationsRequest(wireItems))
                    if (res.isSuccessful && res.body() != null) {
                        val acked = res.body()!!.ackedIds
                        if (acked.isNotEmpty()) {
                            dao.ackOutbox(acked)
                            dao.markMessagesSynced(acked)
                        }
                    } else {
                        dao.incrementOutboxAttempts(pending.map { it.mutationId })
                    }
                }.onFailure {
                    dao.incrementOutboxAttempts(pending.map { it.mutationId })
                }
            }
        }

        runCatching {
            val convRes = api.listConversations(authHeader)
            if (convRes.isSuccessful && convRes.body() != null) {
                val entities = convRes.body()!!.conversations.map {
                    ConversationEntity(
                        id = it.id,
                        titleEncrypted = vault.encryptString(it.title),
                        updatedAtMs = it.updatedAt
                    )
                }
                if (entities.isNotEmpty()) dao.upsertConversations(entities)
            }
        }

        if (activeConversationId != null) {
            runCatching {
                val msgRes = api.listMessages(authHeader, activeConversationId)
                if (msgRes.isSuccessful && msgRes.body() != null) {
                    val entities = msgRes.body()!!.messages.map {
                        MessageEntity(
                            id = it.id,
                            conversationId = it.conversationId,
                            senderId = it.senderId,
                            clientMutationId = it.clientMutationId,
                            bodyEncrypted = vault.encryptString(it.body),
                            createdAtMs = it.createdAt,
                            isPendingSync = false
                        )
                    }
                    if (entities.isNotEmpty()) dao.upsertMessages(entities)
                }
            }
        }
    }

    fun observeQueuedPostsCount(): Flow<Int> = dao.observeQueuedPostsCount()

    suspend fun searchPublicSongs(query: String): RepoResult<List<MusicTrackDto>> {
        val session = loadEncryptedSession() ?: return RepoResult.Failure(bridge.sanitizeError(401))
        return try {
            val res = api.searchMusic("Bearer ${session.accessToken}", query.trim())
            if (res.isSuccessful && res.body() != null) {
                RepoResult.Success(res.body()!!.tracks)
            } else {
                RepoResult.Failure(bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    suspend fun searchHashtags(query: String): RepoResult<List<HashtagDto>> {
        val session = loadEncryptedSession() ?: return RepoResult.Failure(bridge.sanitizeError(401))
        return try {
            val res = api.searchHashtags("Bearer ${session.accessToken}", query.trim())
            if (res.isSuccessful && res.body() != null) {
                RepoResult.Success(res.body()!!.hashtags)
            } else {
                RepoResult.Failure(bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    suspend fun compressPhotoBytes(uri: Uri): Pair<ByteArray, String>? = withContext(Dispatchers.IO) {
        runCatching {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            val maxDim = 1600
            var sampleSize = 1
            val longest = maxOf(bounds.outWidth, bounds.outHeight)
            while (longest / sampleSize > maxDim * 2) {
                sampleSize *= 2
            }
            val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sampleSize }
            val decoded = context.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, decodeOpts)
            } ?: return@withContext null

            val scale = if (maxOf(decoded.width, decoded.height) > maxDim) {
                maxDim.toFloat() / maxOf(decoded.width, decoded.height).toFloat()
            } else 1f
            val bmp = if (scale < 1f) {
                Bitmap.createScaledBitmap(
                    decoded,
                    (decoded.width * scale).toInt().coerceAtLeast(1),
                    (decoded.height * scale).toInt().coerceAtLeast(1),
                    true
                ).also { if (it !== decoded) decoded.recycle() }
            } else decoded

            val thumb = Bitmap.createScaledBitmap(bmp, 72, 64, true)
            val rgbaBuf = ByteBuffer.allocate(thumb.width * thumb.height * 4)
            thumb.copyPixelsToBuffer(rgbaBuf)
            val dhash = bridge.computeFrameDHash(rgbaBuf.array(), thumb.width, thumb.height)
            if (thumb !== bmp) thumb.recycle()

            val out = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.JPEG, 82, out)
            bmp.recycle()
            out.toByteArray() to dhash
        }.getOrNull()
    }

    suspend fun submitOrQueuePost(
        draft: QueuedPostPayload,
        photoUris: List<Uri>,
        videoUri: Uri?,
        thumbBitmap: Bitmap?,
        quality: NetworkQuality,
        onProgress: (Int) -> Unit
    ): RepoResult<String> = withContext(Dispatchers.IO) {
        val session = loadEncryptedSession() ?: return@withContext RepoResult.Failure(bridge.sanitizeError(401))
        val stagedDraft = stageDraftMediaToPrivateDir(draft, photoUris, videoUri, thumbBitmap)

        if (quality == NetworkQuality.OFFLINE) {
            savePostToQueue(stagedDraft)
            return@withContext RepoResult.Success("queued")
        }

        val res = executeQueuedPostUpload(session.accessToken, stagedDraft, onProgress)
        if (res is RepoResult.Success) {
            cleanupStagedFiles(stagedDraft)
            return@withContext res
        }

        savePostToQueue(stagedDraft)
        RepoResult.Success("queued")
    }

    suspend fun flushQueuedPosts(onProgress: ((Int) -> Unit)? = null) = withContext(Dispatchers.IO) {
        val session = loadEncryptedSession() ?: return@withContext
        val items = dao.listQueuedPosts()
        for (entity in items) {
            val payload = runCatching {
                queuedPostAdapter.fromJson(vault.decryptString(entity.payloadEncrypted))
            }.getOrNull() ?: continue
            val res = executeQueuedPostUpload(session.accessToken, payload) { pct ->
                onProgress?.invoke(pct)
            }
            if (res is RepoResult.Success) {
                dao.deleteQueuedPost(entity.queueId)
                cleanupStagedFiles(payload)
            } else {
                dao.incrementQueuedPostAttempts(entity.queueId)
                break
            }
        }
    }

    private suspend fun stageDraftMediaToPrivateDir(
        draft: QueuedPostPayload,
        photoUris: List<Uri>,
        videoUri: Uri?,
        thumbBitmap: Bitmap?
    ): QueuedPostPayload {
        val queueDir = File(context.filesDir, "post_queue").apply { mkdirs() }
        val photoPaths = if (draft.cachedPhotoPaths.isNotEmpty()) {
            draft.cachedPhotoPaths
        } else {
            photoUris.take(10).mapIndexedNotNull { idx, uri ->
                val pair = compressPhotoBytes(uri) ?: return@mapIndexedNotNull null
                val f = File(queueDir, "${draft.queueId}_p${idx}.jpg")
                f.writeBytes(pair.first)
                f.absolutePath
            }
        }
        val videoPath = if (draft.cachedVideoPath.isNotBlank()) {
            draft.cachedVideoPath
        } else if (videoUri != null) {
            val vf = File(queueDir, "${draft.queueId}_vid.mp4")
            runCatching {
                context.contentResolver.openInputStream(videoUri)?.use { input ->
                    vf.outputStream().use { out -> input.copyTo(out, 32768) }
                }
                vf.absolutePath
            }.getOrDefault("")
        } else ""

        val thumbPath = if (draft.cachedThumbPath.isNotBlank()) {
            draft.cachedThumbPath
        } else if (thumbBitmap != null) {
            val tf = File(queueDir, "${draft.queueId}_thumb.jpg")
            runCatching {
                tf.outputStream().use { out -> thumbBitmap.compress(Bitmap.CompressFormat.JPEG, 85, out) }
                tf.absolutePath
            }.getOrDefault("")
        } else ""

        return draft.copy(
            cachedPhotoPaths = photoPaths,
            cachedVideoPath = videoPath,
            cachedThumbPath = thumbPath
        )
    }

    private suspend fun savePostToQueue(draft: QueuedPostPayload) {
        val json = queuedPostAdapter.toJson(draft)
        dao.upsertQueuedPost(
            QueuedPostEntity(
                queueId = draft.queueId,
                postType = draft.postType,
                payloadEncrypted = vault.encryptString(json),
                createdAtMs = System.currentTimeMillis(),
                attemptCount = 0
            )
        )
    }

    private fun cleanupStagedFiles(draft: QueuedPostPayload) {
        draft.cachedPhotoPaths.forEach { runCatching { File(it).delete() } }
        if (draft.cachedVideoPath.isNotBlank()) runCatching { File(draft.cachedVideoPath).delete() }
        if (draft.cachedThumbPath.isNotBlank()) runCatching { File(draft.cachedThumbPath).delete() }
    }

    private suspend fun executeQueuedPostUpload(
        accessToken: String,
        draft: QueuedPostPayload,
        onProgress: (Int) -> Unit
    ): RepoResult<String> {
        val authHeader = "Bearer $accessToken"
        return try {
            val uploadedMediaIds = mutableListOf<String>()

            if (draft.postType == "photos" && draft.cachedPhotoPaths.isNotEmpty()) {
                val files = draft.cachedPhotoPaths.map { File(it) }.filter { it.exists() }
                val totalBytes = files.sumOf { it.length().coerceAtLeast(1L) }.coerceAtLeast(1L)
                var prevFilesBytes = 0L
                val parts = files.mapIndexed { idx, file ->
                    val bytes = file.readBytes()
                    val base = prevFilesBytes
                    prevFilesBytes += bytes.size
                    val body = CountingBytesRequestBody(bytes, "image/jpeg".toMediaType()) { written, _ ->
                        val pct = (((base + written) * 90L) / totalBytes).toInt().coerceIn(5, 90)
                        onProgress(pct)
                    }
                    MultipartBody.Part.createFormData("photos", "photo_${idx}.jpg", body)
                }
                if (parts.isNotEmpty()) {
                    val uploadRes = uploadApi.uploadPostPhotos(authHeader, parts)
                    if (!uploadRes.isSuccessful || uploadRes.body() == null) {
                        return RepoResult.Failure(bridge.sanitizeError(uploadRes.code()))
                    }
                    uploadedMediaIds.addAll(uploadRes.body()!!.media.map { it.mediaId })
                }
            } else if (draft.postType == "video" && draft.cachedVideoPath.isNotBlank()) {
                val videoFile = File(draft.cachedVideoPath)
                if (!videoFile.exists()) return RepoResult.Failure(bridge.sanitizeError(400))
                val vLen = videoFile.length().coerceAtLeast(1L)
                val vBody = CountingStreamRequestBody(
                    totalBytes = vLen,
                    mediaType = "video/mp4".toMediaType(),
                    openStream = { videoFile.inputStream() }
                ) { written, total ->
                    val pct = ((written * 90L) / total).toInt().coerceIn(2, 92)
                    onProgress(pct)
                }
                val videoPart = MultipartBody.Part.createFormData("video", "video.mp4", vBody)
                val thumbPart = draft.cachedThumbPath.takeIf { it.isNotBlank() }?.let { path ->
                    val tf = File(path)
                    if (tf.exists()) {
                        MultipartBody.Part.createFormData(
                            "thumbnail",
                            "thumb.jpg",
                            TelefamNetworkClient.jpegBody(tf.readBytes())
                        )
                    } else null
                }
                val uploadRes = uploadApi.uploadPostVideo(
                    authHeader = authHeader,
                    video = videoPart,
                    thumbnail = thumbPart,
                    trimStartMs = TelefamNetworkClient.textBody(draft.trimStartMs.toString()),
                    trimEndMs = TelefamNetworkClient.textBody(draft.trimEndMs.toString()),
                    thumbnailAtMs = TelefamNetworkClient.textBody(draft.thumbnailAtMs.toString()),
                    muteOriginalAudio = TelefamNetworkClient.textBody(draft.muteOriginalAudio.toString()),
                    songPreviewUrl = TelefamNetworkClient.textBody(draft.songPreviewUrl)
                )
                if (!uploadRes.isSuccessful || uploadRes.body() == null) {
                    return RepoResult.Failure(bridge.sanitizeError(uploadRes.code()))
                }
                uploadedMediaIds.add(uploadRes.body()!!.mediaId)
            } else {
                onProgress(65)
            }

            onProgress(95)
            val createRes = api.createPost(
                authHeader = authHeader,
                request = CreatePostRequest(
                    postType = draft.postType,
                    body = draft.body,
                    bgColorHex = draft.bgColorHex,
                    bgThemeId = draft.bgThemeId,
                    fontFamily = draft.fontFamily,
                    songId = draft.songId,
                    songTitle = draft.songTitle,
                    songArtist = draft.songArtist,
                    songPreviewUrl = draft.songPreviewUrl,
                    muteOriginalAudio = draft.muteOriginalAudio,
                    trimStartMs = draft.trimStartMs,
                    trimEndMs = draft.trimEndMs,
                    mediaIds = uploadedMediaIds,
                    taggedUserIds = draft.taggedUserIds,
                    hashtags = draft.hashtags
                )
            )
            if (createRes.isSuccessful && createRes.body() != null) {
                onProgress(100)
                RepoResult.Success("uploaded")
            } else {
                RepoResult.Failure(bridge.sanitizeError(createRes.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    suspend fun loadPhotoPreviewItem(uri: Uri): ExtractedPhotoItem? = withContext(Dispatchers.IO) {
        val compressed = compressPhotoBytes(uri) ?: return@withContext null
        val thumb = BitmapFactory.decodeByteArray(compressed.first, 0, compressed.first.size)
            ?: return@withContext null
        val preview = Bitmap.createScaledBitmap(
            thumb,
            minOf(420, thumb.width).coerceAtLeast(1),
            ((minOf(420, thumb.width).toFloat() / thumb.width.coerceAtLeast(1)) * thumb.height).toInt().coerceAtLeast(1),
            true
        )
        val cid = bridge.computeMediaContentId(
            mediaKind = "photo",
            frameHashesCsv = compressed.second,
            audioFpHex = "",
            width = thumb.width,
            height = thumb.height,
            durationMs = 0L
        )
        if (preview !== thumb) thumb.recycle()
        ExtractedPhotoItem(
            uri = uri,
            thumbnail = preview,
            dhash = compressed.second,
            contentId = cid
        )
    }

    suspend fun extractVideoMetadataAndFrames(uri: Uri): ExtractedVideoInfo? = withContext(Dispatchers.IO) {
        val sizeBytes = queryUriFileSize(uri)
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(context, uri)
            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 720
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 1280

            val frameList = mutableListOf<VideoFrameItem>()
            val count = if (durationMs > 0L) 8 else 1
            for (i in 0 until count) {
                val tsMs = if (durationMs <= 0L) 0L else (durationMs * i) / maxOf(1, count - 1)
                val rawBmp = retriever.getFrameAtTime(tsMs * 1000L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    ?: retriever.frameAtTime
                    ?: continue
                val scaledH = 160
                val scaledW = ((rawBmp.width.toFloat() / rawBmp.height.coerceAtLeast(1)) * scaledH).toInt().coerceIn(90, 280)
                val thumb = Bitmap.createScaledBitmap(rawBmp, scaledW, scaledH, true)
                if (thumb !== rawBmp) rawBmp.recycle()

                val small = Bitmap.createScaledBitmap(thumb, 72, 64, true)
                val rgba = ByteBuffer.allocate(small.width * small.height * 4)
                small.copyPixelsToBuffer(rgba)
                val dhash = bridge.computeFrameDHash(rgba.array(), small.width, small.height)
                if (small !== thumb) small.recycle()

                frameList.add(VideoFrameItem(timestampMs = tsMs, thumbnail = thumb, dhash = dhash))
            }

            val contentId = bridge.computeMediaContentId(
                mediaKind = "video",
                frameHashesCsv = frameList.joinToString(",") { it.dhash },
                audioFpHex = "",
                width = width,
                height = height,
                durationMs = durationMs
            )

            ExtractedVideoInfo(
                uri = uri,
                sizeBytes = sizeBytes,
                width = width,
                height = height,
                durationMs = durationMs,
                frames = frameList,
                contentId = contentId
            )
        } catch (_: Exception) {
            null
        } finally {
            runCatching { retriever.release() }
        }
    }

    private fun queryUriFileSize(uri: Uri): Long {
        runCatching {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (idx >= 0) return cursor.getLong(idx)
                }
            }
        }
        return runCatching {
            context.contentResolver.openAssetFileDescriptor(uri, "r")?.use { it.length } ?: 0L
        }.getOrDefault(0L)
    }

    // =========================================================================
    // OWNER PROFILE LOCAL CACHE, BACKGROUND SLIDESHOW & GRID TABS
    // =========================================================================

    suspend fun loadCachedAvatarPath(): String? = withContext(Dispatchers.IO) {
        val raw = dao.getKv("owner_avatar_local_path") ?: return@withContext null
        val path = runCatching { vault.decryptString(raw) }.getOrNull().orEmpty()
        path.takeIf { it.isNotBlank() && File(it).exists() }
    }

    suspend fun saveLocalAvatarBytes(fpHash: String, bytes: ByteArray): String = withContext(Dispatchers.IO) {
        val safeHash = fpHash.ifBlank { "latest" }.take(32)
        ownerMediaCacheDir.mkdirs()
        ownerMediaCacheDir.listFiles()?.forEach { f ->
            if (f.name.startsWith("avatar_") && f.name != "avatar_$safeHash.jpg") {
                f.delete()
            }
        }
        val target = File(ownerMediaCacheDir, "avatar_$safeHash.jpg")
        target.writeBytes(bytes)
        dao.putKv(EncryptedKvEntity("owner_avatar_local_path", vault.encryptString(target.absolutePath)))
        target.absolutePath
    }

    suspend fun ensureAvatarCachedLocally(profile: MyProfileDto): String? = withContext(Dispatchers.IO) {
        val fp = profile.avatarFingerprintHash.trim()
        if (fp.isEmpty()) return@withContext null
        val expectedFile = File(ownerMediaCacheDir, "avatar_${fp.take(32)}.jpg")
        if (expectedFile.exists() && expectedFile.length() > 0L) {
            dao.putKv(EncryptedKvEntity("owner_avatar_local_path", vault.encryptString(expectedFile.absolutePath)))
            return@withContext expectedFile.absolutePath
        }
        val res = runCatching {
            withAuthedApi { auth -> api.downloadMyAvatar(auth) }
        }.getOrNull()
        val bytes = res?.takeIf { it.isSuccessful }?.body()?.bytes()
        if (bytes != null && bytes.isNotEmpty()) {
            return@withContext saveLocalAvatarBytes(fp, bytes)
        }
        loadCachedAvatarPath()
    }

    suspend fun loadCachedBackgroundPaths(): List<String> = withContext(Dispatchers.IO) {
        val raw = dao.getKv("owner_bg_cache_json") ?: return@withContext emptyList()
        val list = runCatching {
            bgPathListAdapter.fromJson(vault.decryptString(raw))
        }.getOrNull().orEmpty()
        list.filter { File(it).exists() }
    }

    suspend fun ensureBackgroundsCachedLocally(backgrounds: List<BackgroundPhotoDto>): List<String> = withContext(Dispatchers.IO) {
        ownerMediaCacheDir.mkdirs()
        val keepNames = mutableSetOf<String>()
        val resultPaths = mutableListOf<String>()
        for (bg in backgrounds.take(5)) {
            val safeId = bg.id.replace(Regex("[^a-zA-Z0-9_-]"), "")
            val safeHash = bg.fingerprintHash.take(24)
            if (safeId.isBlank()) continue
            val fileName = "bg_${safeId}_$safeHash.jpg"
            keepNames.add(fileName)
            val file = File(ownerMediaCacheDir, fileName)
            if (!file.exists() || file.length() == 0L) {
                val res = runCatching {
                    withAuthedApi { auth -> api.downloadBackgroundPhoto(auth, bg.id) }
                }.getOrNull()
                val bytes = res?.takeIf { it.isSuccessful }?.body()?.bytes()
                if (bytes != null && bytes.isNotEmpty()) {
                    file.writeBytes(bytes)
                }
            }
            if (file.exists() && file.length() > 0L) {
                resultPaths.add(file.absolutePath)
            }
        }
        ownerMediaCacheDir.listFiles()?.forEach { f ->
            if (f.name.startsWith("bg_") && !keepNames.contains(f.name)) {
                f.delete()
            }
        }
        dao.putKv(EncryptedKvEntity("owner_bg_cache_json", vault.encryptString(bgPathListAdapter.toJson(resultPaths))))
        resultPaths
    }

    suspend fun uploadBackgroundPhotos(uris: List<Uri>): RepoResult<List<BackgroundPhotoDto>> = withContext(Dispatchers.IO) {
        if (uris.isEmpty()) return@withContext RepoResult.Failure("No photos selected")
        val parts = mutableListOf<MultipartBody.Part>()
        uris.take(5).forEachIndexed { idx, uri ->
            val jpegBytes = compressImageUriToJpeg(uri, maxEdge = 1920, quality = 86) ?: return@forEachIndexed
            val reqBody = TelefamNetworkClient.jpegBody(jpegBytes)
            parts.add(MultipartBody.Part.createFormData("photos", "cover_$idx.jpg", reqBody))
        }
        if (parts.isEmpty()) return@withContext RepoResult.Failure("Unable to read selected photos")

        try {
            val res = withAuthedApi { auth -> uploadApi.uploadBackgroundPhotos(auth, parts) }
                ?: return@withContext RepoResult.Failure(bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) {
                val cached = loadCachedMyProfile()
                if (cached != null) {
                    cacheMyProfile(cached.copy(backgroundPhotos = body.backgroundPhotos))
                }
                ensureBackgroundsCachedLocally(body.backgroundPhotos)
                RepoResult.Success(body.backgroundPhotos)
            } else {
                RepoResult.Failure(
                    if (res.code() == 400) "Maximum 5 background photos allowed" else bridge.sanitizeError(res.code())
                )
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    suspend fun deleteBackgroundPhoto(bgId: String): RepoResult<List<BackgroundPhotoDto>> = withContext(Dispatchers.IO) {
        try {
            val res = withAuthedApi { auth -> api.deleteBackgroundPhoto(auth, bgId) }
                ?: return@withContext RepoResult.Failure(bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) {
                val cached = loadCachedMyProfile()
                if (cached != null) {
                    cacheMyProfile(cached.copy(backgroundPhotos = body.backgroundPhotos))
                }
                ensureBackgroundsCachedLocally(body.backgroundPhotos)
                RepoResult.Success(body.backgroundPhotos)
            } else {
                RepoResult.Failure(bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    private fun compressImageUriToJpeg(uri: Uri, maxEdge: Int, quality: Int): ByteArray? {
        return runCatching {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, bounds)
            }
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return@runCatching null
            var sample = 1
            val largest = maxOf(bounds.outWidth, bounds.outHeight)
            while (largest / sample > maxEdge * 2) {
                sample *= 2
            }
            val opts = BitmapFactory.Options().apply { inSampleSize = sample }
            val decoded = context.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, opts)
            } ?: return@runCatching null

            val ratio = minOf(maxEdge.toFloat() / decoded.width.coerceAtLeast(1), maxEdge.toFloat() / decoded.height.coerceAtLeast(1))
            val outBmp = if (ratio < 1f) {
                Bitmap.createScaledBitmap(
                    decoded,
                    (decoded.width * ratio).toInt().coerceAtLeast(1),
                    (decoded.height * ratio).toInt().coerceAtLeast(1),
                    true
                ).also { if (it !== decoded) decoded.recycle() }
            } else decoded

            val baos = ByteArrayOutputStream()
            outBmp.compress(Bitmap.CompressFormat.JPEG, quality, baos)
            outBmp.recycle()
            baos.toByteArray()
        }.getOrNull()
    }

    suspend fun loadCachedOwnerProfileItems(tab: String): OwnerProfileItemsPageDto? {
        val raw = dao.getKv("owner_items_${tab.lowercase()}") ?: return null
        return runCatching { ownerItemsPageAdapter.fromJson(vault.decryptString(raw)) }.getOrNull()
    }

    suspend fun fetchOwnerProfileItems(tab: String, cursor: String = ""): RepoResult<OwnerProfileItemsPageDto> {
        return try {
            val normTab = tab.lowercase()
            val res = withAuthedApi { auth -> api.getOwnerProfileItems(auth, normTab, cursor, 24) }
                ?: return RepoResult.Failure(bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) {
                if (cursor.isBlank()) {
                    dao.putKv(EncryptedKvEntity("owner_items_$normTab", vault.encryptString(ownerItemsPageAdapter.toJson(body))))
                }
                RepoResult.Success(body)
            } else {
                RepoResult.Failure(bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    suspend fun setPostVisibility(postId: String, visibility: String): RepoResult<String> {
        return try {
            val res = withAuthedApi { auth -> api.setPostVisibility(auth, postId, SetPostVisibilityRequest(visibility)) }
                ?: return RepoResult.Failure(bridge.sanitizeError(401))
            if (res.isSuccessful) {
                RepoResult.Success(visibility)
            } else {
                RepoResult.Failure(bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    suspend fun engagePost(postId: String, action: String, active: Boolean): RepoResult<PostEngageResponse> {
        return try {
            val res = withAuthedApi { auth -> api.engagePost(auth, postId, PostEngageRequest(action, active)) }
                ?: return RepoResult.Failure(bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) {
                RepoResult.Success(body)
            } else {
                RepoResult.Failure(bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    suspend fun fetchConnectionsList(filter: String): RepoResult<List<ContactModel>> {
        return try {
            val res = withAuthedApi { auth -> api.listContacts(auth, filter = filter, query = "", cursor = "", limit = 50) }
                ?: return RepoResult.Failure(bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) {
                val list = body.contacts.map { dto ->
                    ContactModel(
                        userId = dto.userId,
                        fullName = dto.fullName,
                        username = dto.username,
                        location = dto.location,
                        avatarFingerprintHash = dto.avatarFingerprintHash,
                        isFollowing = dto.isFollowing,
                        followsMe = dto.followsMe,
                        relationship = bridge.computeRelationship(dto.isFollowing, dto.followsMe),
                        riskScore = dto.riskScore
                    )
                }
                RepoResult.Success(list)
            } else {
                RepoResult.Failure(bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    // =========================================================================
    // OTHER USER PROFILE, PRIVATE NICKNAMES, SLIDESHOW & ITEMS CACHE
    // =========================================================================

    private fun safeUserCacheKey(userId: String): String =
        userId.replace(Regex("[^a-zA-Z0-9_-]"), "").take(48).ifBlank { "unknown" }

    suspend fun loadCachedViewerNicknames(): Map<String, String> {
        val raw = dao.getKv("viewer_nicknames_json") ?: return emptyMap()
        return runCatching {
            viewerNicknamesAdapter.fromJson(vault.decryptString(raw))?.nicknames.orEmpty()
        }.getOrDefault(emptyMap())
    }

    suspend fun fetchViewerNicknames(): Map<String, String>? {
        return runCatching {
            val res = withAuthedApi { auth -> api.getViewerNicknames(auth) } ?: return null
            val body = res.body()
            if (res.isSuccessful && body != null) {
                dao.putKv(
                    EncryptedKvEntity(
                        "viewer_nicknames_json",
                        vault.encryptString(viewerNicknamesAdapter.toJson(body))
                    )
                )
                body.nicknames
            } else null
        }.getOrNull()
    }

    suspend fun loadCachedOtherProfile(userId: String): OtherUserProfileDto? {
        val raw = dao.getKv("other_profile_${safeUserCacheKey(userId)}") ?: return null
        return runCatching {
            otherProfileAdapter.fromJson(vault.decryptString(raw))
        }.getOrNull()
    }

    suspend fun cacheOtherProfile(profile: OtherUserProfileDto) {
        val key = "other_profile_${safeUserCacheKey(profile.userId)}"
        dao.putKv(EncryptedKvEntity(key, vault.encryptString(otherProfileAdapter.toJson(profile))))
    }

    suspend fun fetchOtherProfile(userId: String): RepoResult<OtherUserProfileDto> {
        return try {
            val res = withAuthedApi { auth -> api.getOtherUserProfile(auth, userId) }
                ?: return RepoResult.Failure(bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) {
                cacheOtherProfile(body)
                RepoResult.Success(body)
            } else {
                RepoResult.Failure(bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    suspend fun loadCachedOtherAvatarPath(userId: String): String? = withContext(Dispatchers.IO) {
        val raw = dao.getKv("other_avatar_path_${safeUserCacheKey(userId)}") ?: return@withContext null
        val path = runCatching { vault.decryptString(raw) }.getOrNull().orEmpty()
        path.takeIf { it.isNotBlank() && File(it).exists() && File(it).length() > 0L }
    }

    suspend fun ensureOtherAvatarCachedLocally(userId: String, avatarFpHash: String): String? = withContext(Dispatchers.IO) {
        val fp = avatarFpHash.trim()
        if (fp.isEmpty()) return@withContext null
        val userDir = File(otherMediaCacheDir, safeUserCacheKey(userId)).apply { mkdirs() }
        val target = File(userDir, "avatar_${fp.take(32)}.jpg")
        if (target.exists() && target.length() > 0L) {
            dao.putKv(EncryptedKvEntity("other_avatar_path_${safeUserCacheKey(userId)}", vault.encryptString(target.absolutePath)))
            return@withContext target.absolutePath
        }
        val res = runCatching {
            withAuthedApi { auth -> api.downloadOtherUserAvatar(auth, userId) }
        }.getOrNull()
        val bytes = res?.takeIf { it.isSuccessful }?.body()?.bytes()
        if (bytes != null && bytes.isNotEmpty()) {
            userDir.listFiles()?.forEach { f ->
                if (f.name.startsWith("avatar_") && f.name != target.name) f.delete()
            }
            target.writeBytes(bytes)
            dao.putKv(EncryptedKvEntity("other_avatar_path_${safeUserCacheKey(userId)}", vault.encryptString(target.absolutePath)))
            return@withContext target.absolutePath
        }
        loadCachedOtherAvatarPath(userId)
    }

    suspend fun loadCachedOtherBackgroundPaths(userId: String): List<String> = withContext(Dispatchers.IO) {
        val raw = dao.getKv("other_bg_paths_${safeUserCacheKey(userId)}") ?: return@withContext emptyList()
        val list = runCatching {
            bgPathListAdapter.fromJson(vault.decryptString(raw))
        }.getOrNull().orEmpty()
        list.filter { File(it).exists() && File(it).length() > 0L }
    }

    suspend fun ensureOtherBackgroundsCachedLocally(userId: String, backgrounds: List<BackgroundPhotoDto>): List<String> = withContext(Dispatchers.IO) {
        val userDir = File(otherMediaCacheDir, safeUserCacheKey(userId)).apply { mkdirs() }
        val keepNames = mutableSetOf<String>()
        val resultPaths = mutableListOf<String>()
        for (bg in backgrounds.take(5)) {
            val safeId = bg.id.replace(Regex("[^a-zA-Z0-9_-]"), "")
            val safeHash = bg.fingerprintHash.take(24)
            if (safeId.isBlank()) continue
            val fileName = "bg_${safeId}_$safeHash.jpg"
            keepNames.add(fileName)
            val file = File(userDir, fileName)
            if (!file.exists() || file.length() == 0L) {
                val res = runCatching {
                    withAuthedApi { auth -> api.downloadOtherUserBackgroundPhoto(auth, userId, bg.id) }
                }.getOrNull()
                val bytes = res?.takeIf { it.isSuccessful }?.body()?.bytes()
                if (bytes != null && bytes.isNotEmpty()) {
                    file.writeBytes(bytes)
                }
            }
            if (file.exists() && file.length() > 0L) {
                resultPaths.add(file.absolutePath)
            }
        }
        userDir.listFiles()?.forEach { f ->
            if (f.name.startsWith("bg_") && !keepNames.contains(f.name)) f.delete()
        }
        dao.putKv(
            EncryptedKvEntity(
                "other_bg_paths_${safeUserCacheKey(userId)}",
                vault.encryptString(bgPathListAdapter.toJson(resultPaths))
            )
        )
        resultPaths
    }

    suspend fun loadCachedOtherProfileItems(userId: String, tab: String): OwnerProfileItemsPageDto? {
        val key = "other_items_${safeUserCacheKey(userId)}_${tab.lowercase()}"
        val raw = dao.getKv(key) ?: return null
        return runCatching { ownerItemsPageAdapter.fromJson(vault.decryptString(raw)) }.getOrNull()
    }

    suspend fun fetchOtherProfileItems(userId: String, tab: String, cursor: String = ""): RepoResult<OwnerProfileItemsPageDto> {
        return try {
            val normTab = tab.lowercase()
            val res = withAuthedApi { auth -> api.getOtherUserItems(auth, userId, normTab, cursor, 24) }
                ?: return RepoResult.Failure(bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) {
                if (cursor.isBlank()) {
                    val key = "other_items_${safeUserCacheKey(userId)}_$normTab"
                    dao.putKv(EncryptedKvEntity(key, vault.encryptString(ownerItemsPageAdapter.toJson(body))))
                }
                RepoResult.Success(body)
            } else {
                RepoResult.Failure(bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    suspend fun fetchOtherUserConnections(userId: String, kind: String): RepoResult<List<ContactModel>> {
        return try {
            val res = withAuthedApi { auth -> api.getOtherUserConnections(auth, userId, kind) }
                ?: return RepoResult.Failure(bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) {
                val list = body.contacts.map { dto ->
                    ContactModel(
                        userId = dto.userId,
                        fullName = dto.fullName,
                        username = dto.username,
                        location = dto.location,
                        avatarFingerprintHash = dto.avatarFingerprintHash,
                        isFollowing = dto.isFollowing,
                        followsMe = dto.followsMe,
                        relationship = bridge.computeRelationship(dto.isFollowing, dto.followsMe),
                        riskScore = dto.riskScore
                    )
                }
                RepoResult.Success(list)
            } else {
                RepoResult.Failure(bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    suspend fun setUserNickname(userId: String, nickname: String): RepoResult<String> {
        return try {
            val clean = nickname.trim().take(60)
            val res = withAuthedApi { auth ->
                if (clean.isEmpty()) api.deleteUserNickname(auth, userId)
                else api.setUserNickname(auth, userId, SetUserNicknameRequest(clean))
            } ?: return RepoResult.Failure(bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) {
                val saved = body.nickname.trim()
                val existingMap = loadCachedViewerNicknames().toMutableMap()
                if (saved.isEmpty()) existingMap.remove(userId) else existingMap[userId] = saved
                dao.putKv(
                    EncryptedKvEntity(
                        "viewer_nicknames_json",
                        vault.encryptString(viewerNicknamesAdapter.toJson(ViewerNicknamesResponse(existingMap)))
                    )
                )
                loadCachedOtherProfile(userId)?.let { cached ->
                    cacheOtherProfile(cached.copy(nickname = saved))
                }
                RepoResult.Success(saved)
            } else {
                RepoResult.Failure(bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    suspend fun setUserBlocked(userId: String, blocked: Boolean): RepoResult<Boolean> {
        return try {
            val res = withAuthedApi { auth ->
                if (blocked) api.blockUser(auth, userId) else api.unblockUser(auth, userId)
            } ?: return RepoResult.Failure(bridge.sanitizeError(401))
            if (res.isSuccessful) {
                loadCachedOtherProfile(userId)?.let { cached ->
                    cacheOtherProfile(
                        cached.copy(
                            isBlocked = blocked,
                            isFollowing = if (blocked) false else cached.isFollowing
                        )
                    )
                }
                RepoResult.Success(blocked)
            } else {
                RepoResult.Failure(bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    suspend fun setUserMuted(userId: String, muted: Boolean): RepoResult<Boolean> {
        return try {
            val res = withAuthedApi { auth ->
                if (muted) api.muteUser(auth, userId) else api.unmuteUser(auth, userId)
            } ?: return RepoResult.Failure(bridge.sanitizeError(401))
            if (res.isSuccessful) {
                loadCachedOtherProfile(userId)?.let { cached ->
                    cacheOtherProfile(cached.copy(isMuted = muted))
                }
                RepoResult.Success(muted)
            } else {
                RepoResult.Failure(bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }

    suspend fun submitUserReport(
        userId: String,
        category: String,
        subReason: String,
        details: String
    ): RepoResult<Unit> {
        return try {
            val res = withAuthedApi { auth ->
                api.submitUserReport(auth, userId, SubmitUserReportRequest(category, subReason, details))
            } ?: return RepoResult.Failure(bridge.sanitizeError(401))
            if (res.isSuccessful) {
                RepoResult.Success(Unit)
            } else {
                RepoResult.Failure(bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(bridge.sanitizeError(0))
        }
    }
}
