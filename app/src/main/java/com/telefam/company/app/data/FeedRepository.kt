package com.telefam.company.app.data

import com.telefam.company.app.core.NetworkQuality
import com.telefam.company.app.data.local.CachedFeedVideoEntity
import com.telefam.company.app.data.local.TelefamDao
import com.telefam.company.app.feed.FeedTab
import com.telefam.company.app.network.AudioDiscoveryDto
import com.telefam.company.app.network.FeedSearchResponseDto
import com.telefam.company.app.network.FeedVideoDto
import com.telefam.company.app.network.FollowActionRequest
import com.telefam.company.app.network.FollowActionResponse
import com.telefam.company.app.network.HashtagDiscoveryDto
import com.telefam.company.app.network.RefreshedStreamDto
import com.telefam.company.app.network.SafetyPreferencesDto
import com.telefam.company.app.network.TelefamApiService
import com.telefam.company.app.network.TelefamNetworkClient
import com.telefam.company.app.network.UpdateOwnerVideoRequest
import com.telefam.company.app.network.VideoFeedPageDto
import com.telefam.company.app.network.VideoLikeResponse
import com.telefam.company.app.network.VideoReportRequest
import com.telefam.company.app.network.VideoRepostResponse
import com.telefam.company.app.network.VideoSaveResponse
import com.telefam.company.app.network.VideoShareRequest
import com.telefam.company.app.network.VideoShareResponse
import com.telefam.company.app.network.WatchProgressRequest
import com.telefam.company.app.security.TelefamCryptoVault

class FeedRepository(
    private val coreRepo: TelefamRepository,
    private val dao: TelefamDao,
    private val api: TelefamApiService,
    private val vault: TelefamCryptoVault
) {
    private val videoAdapter = TelefamNetworkClient.moshi.adapter(FeedVideoDto::class.java)

    suspend fun loadCachedFeedVideos(tab: FeedTab): List<FeedVideoDto> {
        val rows = dao.getCachedFeedVideos(tab.cacheKey)
        return rows.mapNotNull { row ->
            runCatching { videoAdapter.fromJson(vault.decryptString(row.payloadEncrypted)) }.getOrNull()
        }
    }

    suspend fun loadCachedSavedVideos(): List<FeedVideoDto> {
        val rows = dao.getCachedFeedVideos("saved")
        return rows.mapNotNull { row ->
            runCatching { videoAdapter.fromJson(vault.decryptString(row.payloadEncrypted)) }.getOrNull()
        }
    }

    private suspend fun cacheFeedVideos(tabKey: String, videos: List<FeedVideoDto>, reset: Boolean) {
        if (reset) {
            dao.clearCachedFeedVideosByTab(tabKey)
        }
        val existingCount = if (reset) 0 else dao.getCachedFeedVideos(tabKey).size
        val now = System.currentTimeMillis()
        val entities = videos.mapIndexed { idx, video ->
            CachedFeedVideoEntity(
                cacheKey = "${tabKey}_${video.videoId}",
                feedTab = tabKey,
                videoId = video.videoId,
                sortOrder = existingCount + idx,
                payloadEncrypted = vault.encryptString(videoAdapter.toJson(video)),
                cachedAtMs = now
            )
        }
        if (entities.isNotEmpty()) {
            dao.upsertCachedFeedVideos(entities)
        }
    }

    suspend fun fetchFeedPage(
        tab: FeedTab,
        cursor: String,
        limit: Int = 15
    ): RepoResult<VideoFeedPageDto> {
        return try {
            val res = coreRepo.withAuthedApi { auth ->
                when (tab) {
                    FeedTab.FOR_YOU -> api.getForYouFeed(auth, cursor, limit)
                    FeedTab.FOLLOWING -> api.getFollowingFeed(auth, cursor, limit)
                }
            } ?: return RepoResult.Failure(coreRepo.bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) {
                cacheFeedVideos(tab.cacheKey, body.videos, reset = cursor.isBlank())
                RepoResult.Success(body)
            } else {
                RepoResult.Failure(coreRepo.bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(coreRepo.bridge.sanitizeError(0))
        }
    }

    suspend fun refreshStreamUrl(videoId: String): RepoResult<RefreshedStreamDto> {
        return try {
            val res = coreRepo.withAuthedApi { auth -> api.refreshStreamUrl(auth, videoId) }
                ?: return RepoResult.Failure(coreRepo.bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) RepoResult.Success(body)
            else RepoResult.Failure(coreRepo.bridge.sanitizeError(res.code()))
        } catch (_: Exception) {
            RepoResult.Failure(coreRepo.bridge.sanitizeError(0))
        }
    }

    suspend fun recordViewOrProgress(
        videoId: String,
        watchDurationMs: Long,
        positionMs: Long,
        completionPct: Double,
        rewatchDelta: Int,
        isInitialView: Boolean
    ) {
        runCatching {
            val req = WatchProgressRequest(
                watchDurationMs = watchDurationMs,
                lastPositionMs = positionMs,
                completionPct = completionPct,
                rewatchDelta = rewatchDelta
            )
            coreRepo.withAuthedApi { auth ->
                if (isInitialView) api.recordVideoView(auth, videoId, req)
                else api.recordWatchProgress(auth, videoId, req)
            }
        }
    }

    suspend fun setVideoLike(videoId: String, liked: Boolean): RepoResult<VideoLikeResponse> {
        return try {
            val res = coreRepo.withAuthedApi { auth ->
                if (liked) api.likeVideo(auth, videoId) else api.unlikeVideo(auth, videoId)
            } ?: return RepoResult.Failure(coreRepo.bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) RepoResult.Success(body)
            else RepoResult.Failure(coreRepo.bridge.sanitizeError(res.code()))
        } catch (_: Exception) {
            RepoResult.Failure(coreRepo.bridge.sanitizeError(0))
        }
    }

    suspend fun setVideoSave(videoId: String, saved: Boolean): RepoResult<VideoSaveResponse> {
        return try {
            val res = coreRepo.withAuthedApi { auth ->
                if (saved) api.saveVideo(auth, videoId) else api.unsaveVideo(auth, videoId)
            } ?: return RepoResult.Failure(coreRepo.bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) RepoResult.Success(body)
            else RepoResult.Failure(coreRepo.bridge.sanitizeError(res.code()))
        } catch (_: Exception) {
            RepoResult.Failure(coreRepo.bridge.sanitizeError(0))
        }
    }

    suspend fun recordVideoShare(videoId: String, channel: String): RepoResult<VideoShareResponse> {
        return try {
            val res = coreRepo.withAuthedApi { auth ->
                api.shareVideo(auth, videoId, VideoShareRequest(channel))
            } ?: return RepoResult.Failure(coreRepo.bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) RepoResult.Success(body)
            else RepoResult.Failure(coreRepo.bridge.sanitizeError(res.code()))
        } catch (_: Exception) {
            RepoResult.Failure(coreRepo.bridge.sanitizeError(0))
        }
    }

    suspend fun setVideoRepost(videoId: String, repost: Boolean): RepoResult<VideoRepostResponse> {
        return try {
            val res = coreRepo.withAuthedApi { auth ->
                if (repost) api.repostVideo(auth, videoId) else api.unrepostVideo(auth, videoId)
            } ?: return RepoResult.Failure(coreRepo.bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) RepoResult.Success(body)
            else RepoResult.Failure(coreRepo.bridge.sanitizeError(res.code()))
        } catch (_: Exception) {
            RepoResult.Failure(coreRepo.bridge.sanitizeError(0))
        }
    }

    suspend fun setCreatorFollow(targetUserId: String, follow: Boolean, quality: NetworkQuality): RepoResult<FollowActionResponse> {
        val session = coreRepo.loadEncryptedSession() ?: return RepoResult.Failure(coreRepo.bridge.sanitizeError(401))
        val nowSec = System.currentTimeMillis() / 1000L
        if (!coreRepo.bridge.allowFollowRateLimit(session.userId, nowSec)) {
            return RepoResult.Failure("Try again later")
        }
        if (quality == NetworkQuality.OFFLINE) {
            return RepoResult.Failure(coreRepo.bridge.sanitizeError(0))
        }
        return try {
            val res = coreRepo.withAuthedApi { auth ->
                api.setFollowState(auth, FollowActionRequest(targetUserId = targetUserId, follow = follow))
            } ?: return RepoResult.Failure(coreRepo.bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) {
                dao.updateContactFollowing(targetUserId, body.isFollowing)
                RepoResult.Success(body)
            } else if (res.code() == 429) {
                RepoResult.Failure("Try again later")
            } else {
                RepoResult.Failure(coreRepo.bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(coreRepo.bridge.sanitizeError(0))
        }
    }

    suspend fun markNotInterested(videoId: String): RepoResult<Unit> {
        dao.deleteCachedFeedVideo(videoId)
        return try {
            val res = coreRepo.withAuthedApi { auth -> api.markNotInterested(auth, videoId) }
                ?: return RepoResult.Failure(coreRepo.bridge.sanitizeError(401))
            if (res.isSuccessful) RepoResult.Success(Unit)
            else RepoResult.Failure(coreRepo.bridge.sanitizeError(res.code()))
        } catch (_: Exception) {
            RepoResult.Failure(coreRepo.bridge.sanitizeError(0))
        }
    }

    suspend fun reportVideo(videoId: String, reason: String, details: String): RepoResult<Unit> {
        return try {
            val res = coreRepo.withAuthedApi { auth ->
                api.reportVideo(auth, videoId, VideoReportRequest(reason = reason, details = details))
            } ?: return RepoResult.Failure(coreRepo.bridge.sanitizeError(401))
            if (res.isSuccessful) RepoResult.Success(Unit)
            else RepoResult.Failure(coreRepo.bridge.sanitizeError(res.code()))
        } catch (_: Exception) {
            RepoResult.Failure(coreRepo.bridge.sanitizeError(0))
        }
    }

    suspend fun updateOwnerVideo(
        videoId: String,
        title: String?,
        description: String?,
        visibility: String?
    ): RepoResult<FeedVideoDto> {
        return try {
            val res = coreRepo.withAuthedApi { auth ->
                api.updateOwnerVideo(
                    auth,
                    videoId,
                    UpdateOwnerVideoRequest(title = title, description = description, visibility = visibility)
                )
            } ?: return RepoResult.Failure(coreRepo.bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) RepoResult.Success(body)
            else RepoResult.Failure(coreRepo.bridge.sanitizeError(res.code()))
        } catch (_: Exception) {
            RepoResult.Failure(coreRepo.bridge.sanitizeError(0))
        }
    }

    suspend fun deleteOwnerVideo(videoId: String): RepoResult<Unit> {
        dao.deleteCachedFeedVideo(videoId)
        return try {
            val res = coreRepo.withAuthedApi { auth -> api.deleteOwnerVideo(auth, videoId) }
                ?: return RepoResult.Failure(coreRepo.bridge.sanitizeError(401))
            if (res.isSuccessful) RepoResult.Success(Unit)
            else RepoResult.Failure(coreRepo.bridge.sanitizeError(res.code()))
        } catch (_: Exception) {
            RepoResult.Failure(coreRepo.bridge.sanitizeError(0))
        }
    }

    suspend fun setUserBlocked(userId: String, block: Boolean): RepoResult<Unit> {
        return try {
            val res = coreRepo.withAuthedApi { auth ->
                if (block) api.blockUser(auth, userId) else api.unblockUser(auth, userId)
            } ?: return RepoResult.Failure(coreRepo.bridge.sanitizeError(401))
            if (res.isSuccessful) RepoResult.Success(Unit)
            else RepoResult.Failure(coreRepo.bridge.sanitizeError(res.code()))
        } catch (_: Exception) {
            RepoResult.Failure(coreRepo.bridge.sanitizeError(0))
        }
    }

    suspend fun setUserMuted(userId: String, mute: Boolean): RepoResult<Unit> {
        return try {
            val res = coreRepo.withAuthedApi { auth ->
                if (mute) api.muteUser(auth, userId) else api.unmuteUser(auth, userId)
            } ?: return RepoResult.Failure(coreRepo.bridge.sanitizeError(401))
            if (res.isSuccessful) RepoResult.Success(Unit)
            else RepoResult.Failure(coreRepo.bridge.sanitizeError(res.code()))
        } catch (_: Exception) {
            RepoResult.Failure(coreRepo.bridge.sanitizeError(0))
        }
    }

    suspend fun fetchSavedVideos(cursor: String = "", limit: Int = 21): RepoResult<VideoFeedPageDto> {
        return try {
            val res = coreRepo.withAuthedApi { auth -> api.listSavedVideos(auth, cursor, limit) }
                ?: return RepoResult.Failure(coreRepo.bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) {
                cacheFeedVideos("saved", body.videos, reset = cursor.isBlank())
                RepoResult.Success(body)
            } else {
                RepoResult.Failure(coreRepo.bridge.sanitizeError(res.code()))
            }
        } catch (_: Exception) {
            RepoResult.Failure(coreRepo.bridge.sanitizeError(0))
        }
    }

    suspend fun fetchSafetyPreferences(): RepoResult<SafetyPreferencesDto> {
        return try {
            val res = coreRepo.withAuthedApi { auth -> api.listSafetyPreferences(auth) }
                ?: return RepoResult.Failure(coreRepo.bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) RepoResult.Success(body)
            else RepoResult.Failure(coreRepo.bridge.sanitizeError(res.code()))
        } catch (_: Exception) {
            RepoResult.Failure(coreRepo.bridge.sanitizeError(0))
        }
    }

    suspend fun fetchHashtagDiscovery(tag: String, cursor: String = "", limit: Int = 21): RepoResult<HashtagDiscoveryDto> {
        return try {
            val cleanTag = tag.trim().removePrefix("#").lowercase()
            val res = coreRepo.withAuthedApi { auth -> api.getHashtagDiscovery(auth, cleanTag, cursor, limit) }
                ?: return RepoResult.Failure(coreRepo.bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) RepoResult.Success(body)
            else RepoResult.Failure(coreRepo.bridge.sanitizeError(res.code()))
        } catch (_: Exception) {
            RepoResult.Failure(coreRepo.bridge.sanitizeError(0))
        }
    }

    suspend fun fetchAudioDiscovery(audioId: String, cursor: String = "", limit: Int = 21): RepoResult<AudioDiscoveryDto> {
        return try {
            val res = coreRepo.withAuthedApi { auth -> api.getAudioDiscovery(auth, audioId, cursor, limit) }
                ?: return RepoResult.Failure(coreRepo.bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) RepoResult.Success(body)
            else RepoResult.Failure(coreRepo.bridge.sanitizeError(res.code()))
        } catch (_: Exception) {
            RepoResult.Failure(coreRepo.bridge.sanitizeError(0))
        }
    }

    suspend fun searchAll(query: String, cursor: String = "", limit: Int = 20): RepoResult<FeedSearchResponseDto> {
        return try {
            val res = coreRepo.withAuthedApi { auth -> api.searchAll(auth, query.trim(), cursor, limit) }
                ?: return RepoResult.Failure(coreRepo.bridge.sanitizeError(401))
            val body = res.body()
            if (res.isSuccessful && body != null) RepoResult.Success(body)
            else RepoResult.Failure(coreRepo.bridge.sanitizeError(res.code()))
        } catch (_: Exception) {
            RepoResult.Failure(coreRepo.bridge.sanitizeError(0))
        }
    }

    suspend fun clearSearchHistory(): RepoResult<Unit> {
        return try {
            val res = coreRepo.withAuthedApi { auth -> api.clearSearchHistory(auth) }
                ?: return RepoResult.Failure(coreRepo.bridge.sanitizeError(401))
            if (res.isSuccessful) RepoResult.Success(Unit)
            else RepoResult.Failure(coreRepo.bridge.sanitizeError(res.code()))
        } catch (_: Exception) {
            RepoResult.Failure(coreRepo.bridge.sanitizeError(0))
        }
    }

    suspend fun deleteSearchHistoryItem(id: String): RepoResult<Unit> {
        return try {
            val res = coreRepo.withAuthedApi { auth -> api.deleteSearchHistoryItem(auth, id) }
                ?: return RepoResult.Failure(coreRepo.bridge.sanitizeError(401))
            if (res.isSuccessful) RepoResult.Success(Unit)
            else RepoResult.Failure(coreRepo.bridge.sanitizeError(res.code()))
        } catch (_: Exception) {
            RepoResult.Failure(coreRepo.bridge.sanitizeError(0))
        }
    }
}
