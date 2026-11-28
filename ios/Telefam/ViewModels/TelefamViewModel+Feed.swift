import Foundation

enum FeedReportReasonIOS: String, CaseIterable, Identifiable {
    case spam = "spam"
    case harassment = "harassment"
    case nudity = "nudity"
    case violence = "violence"
    case misinformation = "misinformation"
    case hateSpeech = "hate_speech"
    case copyright = "copyright"
    case other = "other"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .spam: return "Spam or misleading"
        case .harassment: return "Harassment or bullying"
        case .nudity: return "Nudity or sexual content"
        case .violence: return "Violence or dangerous acts"
        case .misinformation: return "False information"
        case .hateSpeech: return "Hate speech"
        case .copyright: return "Intellectual property"
        case .other: return "Other"
        }
    }
}

@MainActor
extension TelefamViewModel {
    var activeFeedVideos: [FeedVideoItem] {
        videoFeedTab == "following" ? followingVideos : forYouVideos
    }

    var activeVideoIndex: Int {
        videoFeedTab == "following" ? activeFollowingIndex : activeForYouIndex
    }

    func restoreEncryptedVideoFeedCaches() {
        if let d = core.vaultGet(key: "video_feed_for_you_json"),
           let list = try? JSONDecoder().decode([FeedVideoItem].self, from: d) {
            self.forYouVideos = list
        }
        if let d = core.vaultGet(key: "video_feed_following_json"),
           let list = try? JSONDecoder().decode([FeedVideoItem].self, from: d) {
            self.followingVideos = list
        }
        if let d = core.vaultGet(key: "video_feed_saved_json"),
           let list = try? JSONDecoder().decode([FeedVideoItem].self, from: d) {
            self.savedVideos = list
        }
        if let d = core.vaultGet(key: "feed_recent_searches_json"),
           let list = try? JSONDecoder().decode([String].self, from: d) {
            self.localRecentSearches = list
        }
    }

    private func persistVideoFeedCache(tab: String, videos: [FeedVideoItem]) {
        let key = tab == "following" ? "video_feed_following_json" : "video_feed_for_you_json"
        if let d = try? JSONEncoder().encode(Array(videos.prefix(60))) {
            let _ = core.vaultPut(key: key, data: d)
        }
    }

    func selectVideoFeedTab(_ tab: String, quality: TelefamNetworkQuality) {
        guard videoFeedTab != tab else { return }
        videoFeedTab = tab
        let list = activeFeedVideos
        if list.isEmpty {
            Task { await refreshVideoFeed(tab: tab, reset: true, quality: quality) }
        } else {
            onFeedVideoSettled(index: activeVideoIndex, quality: quality)
        }
    }

    func refreshVideoFeed(tab: String, reset: Bool, quality: TelefamNetworkQuality) async {
        guard session != nil else { return }
        if quality == .offline {
            if activeFeedVideos.isEmpty {
                videoFeedError = "No internet."
            }
            isLoadingVideoFeed = false
            isRefreshingVideoFeed = false
            return
        }

        let currentList = (tab == "following") ? followingVideos : forYouVideos
        let cursor = reset ? "" : ((tab == "following") ? followingCursor : forYouCursor)
        let hasMore = (tab == "following") ? followingHasMore : forYouHasMore
        if !reset && (isLoadingVideoFeed || !hasMore || cursor.isEmpty) { return }

        if reset && currentList.isEmpty {
            isLoadingVideoFeed = true
        } else if reset {
            isRefreshingVideoFeed = true
        } else {
            isLoadingVideoFeed = true
        }
        videoFeedError = nil

        defer {
            isLoadingVideoFeed = false
            isRefreshingVideoFeed = false
        }

        do {
            let page = try await withAuthedRetry { tok in
                if tab == "following" {
                    return try await self.api.getFollowingFeed(token: tok, cursor: cursor, limit: 15)
                } else {
                    return try await self.api.getForYouFeed(token: tok, cursor: cursor, limit: 15)
                }
            }

            let merged: [FeedVideoItem]
            if reset {
                merged = page.videos
            } else {
                var seen = Set(currentList.map { $0.video_id })
                var next = currentList
                for v in page.videos where !seen.contains(v.video_id) {
                    seen.insert(v.video_id)
                    next.append(v)
                }
                merged = next
            }

            if tab == "following" {
                followingVideos = merged
                followingCursor = page.next_cursor
                followingHasMore = page.has_more
                if reset { activeFollowingIndex = 0 }
            } else {
                forYouVideos = merged
                forYouCursor = page.next_cursor
                forYouHasMore = page.has_more
                if reset { activeForYouIndex = 0 }
            }
            persistVideoFeedCache(tab: tab, videos: merged)

            if activeTab == .feeds && videoFeedTab == tab {
                onFeedVideoSettled(index: activeVideoIndex, quality: quality)
            }
        } catch let err as TelefamAPIError {
            if currentList.isEmpty {
                videoFeedError = err.message
            }
        } catch {
            if currentList.isEmpty {
                videoFeedError = TelefamCoreBridge.sanitizeError(httpStatus: 0)
            }
        }
    }

    func onFeedVideoSettled(index: Int, quality: TelefamNetworkQuality) {
        let list = activeFeedVideos
        guard list.indices.contains(index) else { return }
        if videoFeedTab == "following" {
            activeFollowingIndex = index
        } else {
            activeForYouIndex = index
        }

        let current = list[index]
        let upcoming = Array(list.dropFirst(index + 1).prefix(5))
        feedPlayback.playVideo(current, upcoming: upcoming, networkQuality: quality)

        if index >= list.count - 4 {
            let hasMore = (videoFeedTab == "following") ? followingHasMore : forYouHasMore
            if hasMore && !isLoadingVideoFeed {
                Task { await refreshVideoFeed(tab: videoFeedTab, reset: false, quality: quality) }
            }
        }
    }

    func refreshSignedVideoStreamURL(videoId: String) async -> FeedVideoItem? {
        guard let refreshed = try? await withAuthedRetry({ tok in
            try await self.api.refreshStreamURL(token: tok, videoId: videoId)
        }) else { return nil }

        var updatedItem: FeedVideoItem?
        mutateVideoEverywhere(videoId: videoId) { v in
            v.stream_url = refreshed.stream_url
            v.fallback_mp4_url = refreshed.fallback_mp4_url
            v.thumbnail_url = refreshed.thumbnail_url
            v.stream_type = refreshed.stream_type
            v.url_expires_at = refreshed.url_expires_at
            v.variants = refreshed.variants
            updatedItem = v
        }
        return updatedItem
    }

    func sendWatchProgress(
        videoId: String,
        watchMs: Int64,
        positionMs: Int64,
        completionPct: Double,
        rewatchDelta: Int,
        isViewPing: Bool
    ) async {
        let payload = WatchProgressPayload(
            watch_duration_ms: watchMs,
            last_position_ms: positionMs,
            completion_pct: completionPct,
            rewatch_delta: rewatchDelta
        )
        let _ = try? await withAuthedRetry { tok in
            if isViewPing {
                try await self.api.recordVideoView(token: tok, videoId: videoId, progress: payload)
            } else {
                try await self.api.recordWatchProgress(token: tok, videoId: videoId, progress: payload)
            }
        }
    }

    func toggleVideoLike(_ video: FeedVideoItem, forceLikeOnly: Bool = false) async {
        if forceLikeOnly && video.is_liked { return }
        let nextLiked = forceLikeOnly ? true : !video.is_liked
        let nextCount = max(0, video.likes_count + (nextLiked ? 1 : -1))
        mutateVideoEverywhere(videoId: video.video_id) { v in
            v.is_liked = nextLiked
            v.likes_count = nextCount
        }
        do {
            let res = try await withAuthedRetry { tok in
                try await self.api.setVideoLiked(token: tok, videoId: video.video_id, liked: nextLiked)
            }
            mutateVideoEverywhere(videoId: video.video_id) { v in
                v.is_liked = res.is_liked
                v.likes_count = res.likes_count
            }
        } catch let err as TelefamAPIError {
            mutateVideoEverywhere(videoId: video.video_id) { v in
                v.is_liked = video.is_liked
                v.likes_count = video.likes_count
            }
            showContactsToast(err.message)
        } catch {
            mutateVideoEverywhere(videoId: video.video_id) { v in
                v.is_liked = video.is_liked
                v.likes_count = video.likes_count
            }
        }
    }

    func toggleVideoSave(_ video: FeedVideoItem) async {
        let nextSaved = !video.is_saved
        let nextCount = max(0, video.saves_count + (nextSaved ? 1 : -1))
        mutateVideoEverywhere(videoId: video.video_id) { v in
            v.is_saved = nextSaved
            v.saves_count = nextCount
        }
        do {
            let res = try await withAuthedRetry { tok in
                try await self.api.setVideoSaved(token: tok, videoId: video.video_id, saved: nextSaved)
            }
            mutateVideoEverywhere(videoId: video.video_id) { v in
                v.is_saved = res.is_saved
                v.saves_count = res.saves_count
            }
        } catch {
            mutateVideoEverywhere(videoId: video.video_id) { v in
                v.is_saved = video.is_saved
                v.saves_count = video.saves_count
            }
        }
    }

    func recordVideoShare(_ video: FeedVideoItem, channel: String) async {
        mutateVideoEverywhere(videoId: video.video_id) { v in
            v.shares_count += 1
        }
        if let res = try? await withAuthedRetry({ tok in
            try await self.api.shareVideo(token: tok, videoId: video.video_id, channel: channel)
        }) {
            mutateVideoEverywhere(videoId: video.video_id) { v in
                v.shares_count = res.shares_count
            }
        }
    }

    func toggleFollowFromFeed(_ video: FeedVideoItem) async {
        guard let sess = session else { return }
        guard core.allowFollowRateLimit(accountKey: sess.user_id) else {
            showContactsToast("Try again later")
            return
        }
        let nextFollow = !video.is_following_creator
        mutateCreatorFollowingEverywhere(creatorId: video.creator_id, following: nextFollow)
        do {
            let res = try await withAuthedRetry { tok in
                try await self.api.setFollowState(token: tok, targetUserId: video.creator_id, follow: nextFollow)
            }
            mutateCreatorFollowingEverywhere(creatorId: video.creator_id, following: res.is_following)
        } catch let err as TelefamAPIError {
            mutateCreatorFollowingEverywhere(creatorId: video.creator_id, following: video.is_following_creator)
            showContactsToast(err.message)
        } catch {
            mutateCreatorFollowingEverywhere(creatorId: video.creator_id, following: video.is_following_creator)
        }
    }

    func toggleRepost(_ video: FeedVideoItem) async {
        let next = !video.is_reposted
        let nextCount = max(0, video.reposts_count + (next ? 1 : -1))
        mutateVideoEverywhere(videoId: video.video_id) { v in
            v.is_reposted = next
            v.reposts_count = nextCount
        }
        do {
            let res = try await withAuthedRetry { tok in
                try await self.api.setVideoReposted(token: tok, videoId: video.video_id, reposted: next)
            }
            mutateVideoEverywhere(videoId: video.video_id) { v in
                v.is_reposted = res.is_reposted
                v.reposts_count = res.reposts_count
            }
            showContactsToast(res.is_reposted ? "Reposted" : "Repost removed")
        } catch {
            mutateVideoEverywhere(videoId: video.video_id) { v in
                v.is_reposted = video.is_reposted
                v.reposts_count = video.reposts_count
            }
        }
    }

    func markVideoNotInterested(_ video: FeedVideoItem) async {
        removeVideoEverywhere(videoId: video.video_id)
        let _ = try? await withAuthedRetry { tok in
            try await self.api.markNotInterested(token: tok, videoId: video.video_id)
        }
        showContactsToast("We will show fewer videos like this")
    }

    func submitVideoReport(_ video: FeedVideoItem, reason: FeedReportReasonIOS, details: String) async {
        do {
            try await withAuthedRetry { tok in
                try await self.api.reportVideo(token: tok, videoId: video.video_id, reason: reason.rawValue, details: details)
            }
            showContactsToast("Report submitted")
        } catch let err as TelefamAPIError {
            showContactsToast(err.message)
        } catch {
            showContactsToast(TelefamCoreBridge.sanitizeError(httpStatus: 0))
        }
    }

    func blockCreator(_ creatorId: String) async {
        removeCreatorVideosEverywhere(creatorId: creatorId)
        do {
            try await withAuthedRetry { tok in
                try await self.api.setUserBlocked(token: tok, userId: creatorId, blocked: true)
            }
            showContactsToast("User blocked")
        } catch let err as TelefamAPIError {
            showContactsToast(err.message)
        } catch {
            showContactsToast(TelefamCoreBridge.sanitizeError(httpStatus: 0))
        }
    }

    func muteCreator(_ creatorId: String) async {
        removeCreatorVideosEverywhere(creatorId: creatorId)
        do {
            try await withAuthedRetry { tok in
                try await self.api.setUserMuted(token: tok, userId: creatorId, muted: true)
            }
            showContactsToast("User muted")
        } catch let err as TelefamAPIError {
            showContactsToast(err.message)
        } catch {
            showContactsToast(TelefamCoreBridge.sanitizeError(httpStatus: 0))
        }
    }

    func updateOwnerVideo(_ video: FeedVideoItem, title: String?, description: String?, visibility: String?) async {
        do {
            let updated = try await withAuthedRetry { tok in
                try await self.api.updateOwnerVideo(
                    token: tok,
                    videoId: video.video_id,
                    payload: UpdateOwnerVideoPayload(title: title, description: description, visibility: visibility)
                )
            }
            mutateVideoEverywhere(videoId: video.video_id) { v in
                v.title = updated.title
                v.description = updated.description
                v.visibility = updated.visibility
            }
            showContactsToast("Updated")
        } catch let err as TelefamAPIError {
            showContactsToast(err.message)
        } catch {
            showContactsToast(TelefamCoreBridge.sanitizeError(httpStatus: 0))
        }
    }

    func deleteOwnerVideo(_ video: FeedVideoItem) async {
        do {
            try await withAuthedRetry { tok in
                try await self.api.deleteOwnerVideo(token: tok, videoId: video.video_id)
            }
            removeVideoEverywhere(videoId: video.video_id)
            showContactsToast("Video deleted")
        } catch let err as TelefamAPIError {
            showContactsToast(err.message)
        } catch {
            showContactsToast(TelefamCoreBridge.sanitizeError(httpStatus: 0))
        }
    }

    // MARK: - Discovery, Search, Saved & Safety

    func openHashtagDiscovery(tag: String, quality: TelefamNetworkQuality) {
        let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .lowercased()
        guard !clean.isEmpty else { return }
        feedPlayback.setFeedVisible(false)
        activeHashtagTag = clean
        hashtagDiscovery = nil
        Task { await loadHashtagDiscovery(tag: clean, reset: true, quality: quality) }
    }

    func loadHashtagDiscovery(tag: String, reset: Bool, quality: TelefamNetworkQuality) async {
        if quality == .offline { return }
        let cursor = reset ? "" : (hashtagDiscovery?.next_cursor ?? "")
        if !reset && (isLoadingHashtagDiscovery || hashtagDiscovery?.has_more != true || cursor.isEmpty) { return }
        isLoadingHashtagDiscovery = true
        defer { isLoadingHashtagDiscovery = false }
        if let res = try? await withAuthedRetry({ tok in
            try await self.api.getHashtagDiscovery(token: tok, tag: tag, cursor: cursor, limit: 21)
        }) {
            if reset || hashtagDiscovery == nil {
                hashtagDiscovery = res
            } else if let prev = hashtagDiscovery {
                var seen = Set(prev.videos.map { $0.video_id })
                let merged = prev.videos + res.videos.filter { seen.insert($0.video_id).inserted }
                hashtagDiscovery = HashtagDiscoveryPayload(
                    tag: res.tag,
                    video_count: res.video_count,
                    views_count: res.views_count,
                    videos: merged,
                    next_cursor: res.next_cursor,
                    has_more: res.has_more
                )
            }
        }
    }

    func openAudioDiscovery(audioId: String, quality: TelefamNetworkQuality) {
        guard !audioId.isEmpty else { return }
        feedPlayback.setFeedVisible(false)
        activeAudioId = audioId
        audioDiscovery = nil
        Task { await loadAudioDiscovery(audioId: audioId, reset: true, quality: quality) }
    }

    func loadAudioDiscovery(audioId: String, reset: Bool, quality: TelefamNetworkQuality) async {
        if quality == .offline { return }
        let cursor = reset ? "" : (audioDiscovery?.next_cursor ?? "")
        if !reset && (isLoadingAudioDiscovery || audioDiscovery?.has_more != true || cursor.isEmpty) { return }
        isLoadingAudioDiscovery = true
        defer { isLoadingAudioDiscovery = false }
        if let res = try? await withAuthedRetry({ tok in
            try await self.api.getAudioDiscovery(token: tok, audioId: audioId, cursor: cursor, limit: 21)
        }) {
            if reset || audioDiscovery == nil {
                audioDiscovery = res
            } else if let prev = audioDiscovery {
                var seen = Set(prev.videos.map { $0.video_id })
                let merged = prev.videos + res.videos.filter { seen.insert($0.video_id).inserted }
                audioDiscovery = AudioDiscoveryPayload(
                    audio: res.audio,
                    videos: merged,
                    next_cursor: res.next_cursor,
                    has_more: res.has_more
                )
            }
        }
    }

    func useSoundInPostComposer(_ audio: AudioSummaryItem) {
        activeAudioId = nil
        activeHashtagTag = nil
        showFeedSearch = false
        showModalFeedPlayer = false
        postMode = .video
        postSelectedSong = MusicTrackItem(
            track_id: audio.external_track_id.isEmpty ? audio.audio_id : audio.external_track_id,
            title: audio.title,
            artist: audio.artist,
            artwork_url: audio.artwork_url,
            preview_url: audio.preview_url,
            duration_sec: max(15, Int(audio.duration_ms / 1000))
        )
        openPostComposer()
    }

    func openFeedSearch(quality: TelefamNetworkQuality) {
        feedPlayback.setFeedVisible(false)
        showFeedSearch = true
        Task { await executeFeedSearch(query: feedSearchQuery, reset: true, quality: quality) }
    }

    func updateFeedSearchQuery(_ query: String, quality: TelefamNetworkQuality) {
        feedSearchQuery = query
        feedSearchTask?.cancel()
        feedSearchTask = Task { [weak self] in
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try? await Task.sleep(nanoseconds: 280_000_000)
            }
            guard !Task.isCancelled, let self else { return }
            await self.executeFeedSearch(query: query, reset: true, quality: quality)
        }
    }

    func executeFeedSearch(query: String, reset: Bool, quality: TelefamNetworkQuality) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && reset {
            recordLocalRecentSearch(trimmed)
        }
        guard quality != .offline else { return }
        let cursor = reset ? "" : (feedSearchResults?.next_cursor ?? "")
        if !reset && (isSearchingFeed || feedSearchResults?.has_more != true || cursor.isEmpty) { return }
        isSearchingFeed = true
        defer { isSearchingFeed = false }
        if let res = try? await withAuthedRetry({ tok in
            try await self.api.searchAll(token: tok, query: trimmed, cursor: cursor, limit: 20)
        }) {
            if reset || feedSearchResults == nil {
                feedSearchResults = res
            } else if let prev = feedSearchResults {
                var seen = Set(prev.videos.map { $0.video_id })
                let merged = prev.videos + res.videos.filter { seen.insert($0.video_id).inserted }
                feedSearchResults = FeedSearchPayload(
                    query: res.query,
                    videos: merged,
                    hashtags: res.hashtags,
                    creators: res.creators,
                    audios: res.audios,
                    recent_searches: res.recent_searches,
                    trending: res.trending,
                    next_cursor: res.next_cursor,
                    has_more: res.has_more
                )
            }
        }
    }

    func clearAllSearchHistory(quality: TelefamNetworkQuality) async {
        localRecentSearches = []
        core.vaultDelete(key: "feed_recent_searches_json")
        if let prev = feedSearchResults {
            feedSearchResults = FeedSearchPayload(
                query: prev.query,
                videos: prev.videos,
                hashtags: prev.hashtags,
                creators: prev.creators,
                audios: prev.audios,
                recent_searches: [],
                trending: prev.trending,
                next_cursor: prev.next_cursor,
                has_more: prev.has_more
            )
        }
        if quality != .offline {
            let _ = try? await withAuthedRetry { tok in
                try await self.api.clearSearchHistory(token: tok)
            }
        }
    }

    func deleteRecentSearch(id: String, query: String, quality: TelefamNetworkQuality) async {
        localRecentSearches.removeAll { $0.caseInsensitiveCompare(query) == .orderedSame }
        if let d = try? JSONEncoder().encode(localRecentSearches) {
            let _ = core.vaultPut(key: "feed_recent_searches_json", data: d)
        }
        if let prev = feedSearchResults {
            feedSearchResults = FeedSearchPayload(
                query: prev.query,
                videos: prev.videos,
                hashtags: prev.hashtags,
                creators: prev.creators,
                audios: prev.audios,
                recent_searches: prev.recent_searches.filter { $0.id != id && $0.query != query },
                trending: prev.trending,
                next_cursor: prev.next_cursor,
                has_more: prev.has_more
            )
        }
        if quality != .offline && !id.isEmpty {
            let _ = try? await withAuthedRetry { tok in
                try await self.api.deleteSearchHistoryItem(token: tok, id: id)
            }
        }
    }

    private func recordLocalRecentSearch(_ query: String) {
        var next = localRecentSearches.filter { $0.caseInsensitiveCompare(query) != .orderedSame }
        next.insert(query, at: 0)
        localRecentSearches = Array(next.prefix(12))
        if let d = try? JSONEncoder().encode(localRecentSearches) {
            let _ = core.vaultPut(key: "feed_recent_searches_json", data: d)
        }
    }

    func openModalFeedPlayer(videos: [FeedVideoItem], initialIndex: Int, title: String) {
        guard !videos.isEmpty else { return }
        modalFeedVideos = videos
        modalFeedInitialIndex = min(max(0, initialIndex), videos.count - 1)
        modalFeedTitle = title
        showModalFeedPlayer = true
        feedPlayback.setFeedVisible(true)
    }

    func closeModalFeedPlayer(quality: TelefamNetworkQuality = .online) {
        showModalFeedPlayer = false
        modalFeedVideos = []
        resumeMainFeedIfVisible(quality: quality)
    }

    func resumeMainFeedIfVisible(quality: TelefamNetworkQuality) {
        if activeTab == .feeds && !showFeedSearch && activeHashtagTag == nil && activeAudioId == nil && !showModalFeedPlayer && !showLiveComingSoon {
            feedPlayback.setFeedVisible(true)
            let list = activeFeedVideos
            let idx = activeVideoIndex
            if list.indices.contains(idx) {
                let upcoming = Array(list.dropFirst(idx + 1).prefix(5))
                feedPlayback.playVideo(list[idx], upcoming: upcoming, networkQuality: quality)
            }
        } else {
            feedPlayback.setFeedVisible(false)
        }
    }

    func loadSavedVideos(quality: TelefamNetworkQuality) async {
        guard quality != .offline else { return }
        isLoadingSavedVideos = true
        defer { isLoadingSavedVideos = false }
        if let page = try? await withAuthedRetry({ tok in
            try await self.api.listSavedVideos(token: tok, cursor: "", limit: 30)
        }) {
            savedVideos = page.videos
            if let d = try? JSONEncoder().encode(page.videos) {
                let _ = core.vaultPut(key: "video_feed_saved_json", data: d)
            }
        }
    }

    func loadSafetyPreferences(quality: TelefamNetworkQuality) async {
        guard quality != .offline else { return }
        isLoadingSafetyPreferences = true
        defer { isLoadingSafetyPreferences = false }
        if let prefs = try? await withAuthedRetry({ tok in
            try await self.api.listSafetyPreferences(token: tok)
        }) {
            safetyPreferences = prefs
        }
    }

    func unblockUserFromSafety(_ userId: String) async {
        safetyPreferences = SafetyPreferencesPayload(
            muted_users: safetyPreferences.muted_users,
            blocked_users: safetyPreferences.blocked_users.filter { $0.user_id != userId }
        )
        let _ = try? await withAuthedRetry { tok in
            try await self.api.setUserBlocked(token: tok, userId: userId, blocked: false)
        }
    }

    func unmuteUserFromSafety(_ userId: String) async {
        safetyPreferences = SafetyPreferencesPayload(
            muted_users: safetyPreferences.muted_users.filter { $0.user_id != userId },
            blocked_users: safetyPreferences.blocked_users
        )
        let _ = try? await withAuthedRetry { tok in
            try await self.api.setUserMuted(token: tok, userId: userId, muted: false)
        }
    }

    private func mutateVideoEverywhere(videoId: String, mutate: (inout FeedVideoItem) -> Void) {
        if let idx = forYouVideos.firstIndex(where: { $0.video_id == videoId }) {
            mutate(&forYouVideos[idx])
            persistVideoFeedCache(tab: "for_you", videos: forYouVideos)
        }
        if let idx = followingVideos.firstIndex(where: { $0.video_id == videoId }) {
            mutate(&followingVideos[idx])
            persistVideoFeedCache(tab: "following", videos: followingVideos)
        }
        if let idx = modalFeedVideos.firstIndex(where: { $0.video_id == videoId }) {
            mutate(&modalFeedVideos[idx])
        }
        if let idx = savedVideos.firstIndex(where: { $0.video_id == videoId }) {
            mutate(&savedVideos[idx])
        }
    }

    private func mutateCreatorFollowingEverywhere(creatorId: String, following: Bool) {
        for idx in forYouVideos.indices where forYouVideos[idx].creator_id == creatorId {
            forYouVideos[idx].is_following_creator = following
        }
        for idx in followingVideos.indices where followingVideos[idx].creator_id == creatorId {
            followingVideos[idx].is_following_creator = following
        }
        for idx in modalFeedVideos.indices where modalFeedVideos[idx].creator_id == creatorId {
            modalFeedVideos[idx].is_following_creator = following
        }
    }

    private func removeVideoEverywhere(videoId: String) {
        forYouVideos.removeAll { $0.video_id == videoId }
        followingVideos.removeAll { $0.video_id == videoId }
        modalFeedVideos.removeAll { $0.video_id == videoId }
        savedVideos.removeAll { $0.video_id == videoId }
        persistVideoFeedCache(tab: "for_you", videos: forYouVideos)
        persistVideoFeedCache(tab: "following", videos: followingVideos)
    }

    private func removeCreatorVideosEverywhere(creatorId: String) {
        forYouVideos.removeAll { $0.creator_id == creatorId }
        followingVideos.removeAll { $0.creator_id == creatorId }
        modalFeedVideos.removeAll { $0.creator_id == creatorId }
        persistVideoFeedCache(tab: "for_you", videos: forYouVideos)
        persistVideoFeedCache(tab: "following", videos: followingVideos)
    }
}
