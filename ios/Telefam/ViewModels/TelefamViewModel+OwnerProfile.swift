import Foundation
import UIKit

enum OwnerProfileTabIOS: String, CaseIterable, Identifiable {
    case posts = "posts"
    case reposts = "reposts"
    case locked = "locked"
    case saved = "saved"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .posts: return "Posts"
        case .reposts: return "Reposts"
        case .locked: return "Locked"
        case .saved: return "Saved"
        }
    }
}

extension TelefamViewModel {
    private var ownerCacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("TelefamOwnerCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func restoreOwnerProfileLocalCache() {
        let avatarPath = core.vaultGet(key: "owner_avatar_local_path")
            .flatMap { String(data: $0, encoding: .utf8) }
        if let avatarPath, FileManager.default.fileExists(atPath: avatarPath) {
            self.ownerLocalAvatarPath = avatarPath
        }
        self.ownerLocalBackgroundPaths = loadCachedOwnerBackgroundPaths()
        for tab in OwnerProfileTabIOS.allCases {
            if let data = core.vaultGet(key: "owner_items_\(tab.rawValue)"),
               let decoded = try? JSONDecoder().decode([OwnerProfileItem].self, from: data) {
                self.ownerItemsByCategory[tab] = decoded
            }
        }
    }

    func clearOwnerProfileLocalCache() {
        core.vaultDelete(key: "owner_avatar_local_path")
        core.vaultDelete(key: "owner_bg_cache_json")
        for tab in OwnerProfileTabIOS.allCases {
            core.vaultDelete(key: "owner_items_\(tab.rawValue)")
        }
        try? FileManager.default.removeItem(at: ownerCacheDirectory)
        ownerItemsByCategory = [:]
        ownerLocalAvatarPath = nil
        ownerLocalBackgroundPaths = []
        ownerConnectionsUsers = []
        ownerConnectionsMode = nil
        activeOwnerViewerItem = nil
        ownerProfileToast = nil
    }

    func saveOwnerAvatarLocally(jpegData: Data) -> String? {
        let url = ownerCacheDirectory.appendingPathComponent("owner_avatar.jpg")
        do {
            try jpegData.write(to: url, options: .atomic)
            if let pathData = url.path.data(using: .utf8) {
                let _ = core.vaultPut(key: "owner_avatar_local_path", data: pathData)
            }
            return url.path
        } catch {
            return nil
        }
    }

    private func loadCachedOwnerBackgroundPaths() -> [String] {
        guard let data = core.vaultGet(key: "owner_bg_cache_json"),
              let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return paths.filter { FileManager.default.fileExists(atPath: $0) }
    }

    func ensureOwnerMediaCachedLocally(profile: MyProfilePayload) async {
        guard session != nil else { return }

        // 1. Cache avatar locally if missing or hash changed
        let cachedHash = core.vaultGet(key: "owner_avatar_cached_hash")
            .flatMap { String(data: $0, encoding: .utf8) }
        let avatarPath = ownerLocalAvatarPath
        if !profile.avatar_fingerprint_hash.isEmpty,
           (avatarPath == nil || !FileManager.default.fileExists(atPath: avatarPath!) || cachedHash != profile.avatar_fingerprint_hash) {
            let downloadPath = (profile.avatar_url?.isEmpty == false) ? profile.avatar_url! : "/v1/profile/avatar"
            if let data = try? await withAuthedRetry({ tok in
                try await self.api.downloadBinary(token: tok, pathOrURL: downloadPath)
            }), let saved = saveOwnerAvatarLocally(jpegData: data) {
                if let hd = profile.avatar_fingerprint_hash.data(using: .utf8) {
                    let _ = core.vaultPut(key: "owner_avatar_cached_hash", data: hd)
                }
                self.ownerLocalAvatarPath = saved
            }
        }

        // 2. Cache up to 5 background photos locally
        let bgs = Array(profile.safeBackgroundPhotos.prefix(5))
        var paths: [String] = []
        for bg in bgs {
            let dest = ownerCacheDirectory.appendingPathComponent("bg_\(bg.id).jpg")
            if !FileManager.default.fileExists(atPath: dest.path) {
                let targetPath = bg.url.isEmpty ? "/v1/profile/backgrounds/\(bg.id)" : bg.url
                if let data = try? await withAuthedRetry({ tok in
                    try await self.api.downloadBinary(token: tok, pathOrURL: targetPath)
                }) {
                    try? data.write(to: dest, options: .atomic)
                }
            }
            if FileManager.default.fileExists(atPath: dest.path) {
                paths.append(dest.path)
            }
        }
        if let json = try? JSONEncoder().encode(paths) {
            let _ = core.vaultPut(key: "owner_bg_cache_json", data: json)
        }
        self.ownerLocalBackgroundPaths = paths
    }

    func refreshOwnerProfile(quality: TelefamNetworkQuality, isPullGesture: Bool) async {
        guard let sess = session, sess.profile_completed else { return }
        if isPullGesture {
            isRefreshingOwnerProfile = true
        }
        if quality != .offline {
            await refreshMyProfile(quality: quality)
        }
        await loadOwnerProfileItems(tab: ownerActiveCategory, quality: quality)
        isRefreshingOwnerProfile = false
    }

    func selectOwnerProfileCategory(_ tab: OwnerProfileTabIOS, quality: TelefamNetworkQuality) {
        ownerActiveCategory = tab
        Task {
            await loadOwnerProfileItems(tab: tab, quality: quality)
        }
    }

    func loadOwnerProfileItems(tab: OwnerProfileTabIOS, quality: TelefamNetworkQuality) async {
        if ownerItemsByCategory[tab]?.isEmpty != false,
           let cachedData = core.vaultGet(key: "owner_items_\(tab.rawValue)"),
           let decoded = try? JSONDecoder().decode([OwnerProfileItem].self, from: cachedData),
           !decoded.isEmpty {
            ownerItemsByCategory[tab] = decoded
        }
        guard quality != .offline, session != nil else { return }
        isLoadingOwnerItems = true
        defer { isLoadingOwnerItems = false }
        if let page = try? await withAuthedRetry({ tok in
            try await self.api.getOwnerProfileItems(token: tok, tab: tab.rawValue, cursor: "", limit: 30)
        }) {
            ownerItemsByCategory[tab] = page.items
            if let encoded = try? JSONEncoder().encode(page.items) {
                let _ = core.vaultPut(key: "owner_items_\(tab.rawValue)", data: encoded)
            }
        }
    }

    func uploadOwnerBackgroundPhotos(rawImagesData: [Data], quality: TelefamNetworkQuality) async {
        guard !rawImagesData.isEmpty else { return }
        guard quality != .offline else {
            showOwnerProfileToast("No internet")
            return
        }
        let existingCount = myProfile?.safeBackgroundPhotos.count ?? 0
        let remaining = max(0, 5 - existingCount)
        if remaining == 0 {
            showOwnerProfileToast("Maximum 5 background photos allowed")
            return
        }
        if rawImagesData.count > remaining {
            showOwnerProfileToast("Only \(remaining) more background photo(s) allowed")
        }
        let selected = Array(rawImagesData.prefix(remaining))
        var jpegs: [Data] = []
        for raw in selected {
            guard let img = UIImage(data: raw) else { continue }
            let maxEdge: CGFloat = 1920
            let scale = min(1.0, maxEdge / max(img.size.width, img.size.height))
            let targetSize = CGSize(width: max(1, floor(img.size.width * scale)), height: max(1, floor(img.size.height * scale)))
            let renderer = UIGraphicsImageRenderer(size: targetSize)
            let resized = renderer.image { _ in
                img.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            if let jpg = resized.jpegData(compressionQuality: 0.86) {
                jpegs.append(jpg)
            }
        }
        guard !jpegs.isEmpty else { return }

        isUploadingOwnerBackgrounds = true
        defer { isUploadingOwnerBackgrounds = false }
        do {
            let bgs = try await withAuthedRetry { tok in
                try await self.api.uploadBackgroundPhotos(token: tok, photosJPEG: jpegs)
            }
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
                    avatar_fingerprint_hash: existing.avatar_fingerprint_hash,
                    profile_completed: existing.profile_completed,
                    avatar_url: existing.avatar_url,
                    followers_count: existing.followers_count,
                    following_count: existing.following_count,
                    posts_count: existing.posts_count,
                    views_count: existing.views_count,
                    likes_count: existing.likes_count,
                    background_photos: bgs
                )
                self.myProfile = updated
                persistCachedMyProfile(updated)
                await ensureOwnerMediaCachedLocally(profile: updated)
            }
            showOwnerProfileToast("Background updated")
        } catch let err as TelefamAPIError {
            showOwnerProfileToast(err.message)
        } catch {
            showOwnerProfileToast(TelefamCoreBridge.sanitizeError(httpStatus: 0))
        }
    }

    func deleteOwnerBackgroundPhoto(backgroundId: String, quality: TelefamNetworkQuality) async {
        guard quality != .offline else {
            showOwnerProfileToast("No internet")
            return
        }
        isUploadingOwnerBackgrounds = true
        defer { isUploadingOwnerBackgrounds = false }
        do {
            let bgs = try await withAuthedRetry { tok in
                try await self.api.deleteBackgroundPhoto(token: tok, backgroundId: backgroundId)
            }
            let cachedFile = ownerCacheDirectory.appendingPathComponent("bg_\(backgroundId).jpg")
            try? FileManager.default.removeItem(at: cachedFile)
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
                    avatar_fingerprint_hash: existing.avatar_fingerprint_hash,
                    profile_completed: existing.profile_completed,
                    avatar_url: existing.avatar_url,
                    followers_count: existing.followers_count,
                    following_count: existing.following_count,
                    posts_count: existing.posts_count,
                    views_count: existing.views_count,
                    likes_count: existing.likes_count,
                    background_photos: bgs
                )
                self.myProfile = updated
                persistCachedMyProfile(updated)
                await ensureOwnerMediaCachedLocally(profile: updated)
            }
        } catch let err as TelefamAPIError {
            showOwnerProfileToast(err.message)
        } catch {
            showOwnerProfileToast(TelefamCoreBridge.sanitizeError(httpStatus: 0))
        }
    }

    func openConnectionsSheet(mode: String, quality: TelefamNetworkQuality) {
        ownerConnectionsMode = mode
        ownerConnectionsUsers = []
        isLoadingOwnerConnections = true
        Task {
            defer { isLoadingOwnerConnections = false }
            if quality == .offline {
                let fallback = mode == "followers"
                    ? cachedContacts.filter { $0.follows_me }
                    : cachedContacts.filter { $0.is_following }
                ownerConnectionsUsers = fallback
                return
            }
            if let page = try? await withAuthedRetry({ tok in
                try await self.api.listContacts(token: tok, filter: mode, query: "", cursor: "", limit: 50)
            }) {
                ownerConnectionsUsers = page.contacts
            }
        }
    }

    func toggleConnectionFollow(_ user: ContactUserItem, quality: TelefamNetworkQuality) async {
        await toggleFollow(user, quality: quality)
        if let idx = ownerConnectionsUsers.firstIndex(where: { $0.user_id == user.user_id }) {
            let nextFollowing = !user.is_following
            let nextRel = TelefamCoreBridge.computeRelationship(isFollowing: nextFollowing, followsMe: user.follows_me)
            ownerConnectionsUsers[idx].is_following = nextFollowing
            ownerConnectionsUsers[idx].relationship = nextRel
            if let p = myProfile {
                let delta: Int64 = nextFollowing ? 1 : -1
                let updated = MyProfilePayload(
                    user_id: p.user_id,
                    email: p.email,
                    full_name: p.full_name,
                    username: p.username,
                    country_iso: p.country_iso,
                    phone_number: p.phone_number,
                    gender: p.gender,
                    date_of_birth: p.date_of_birth,
                    location: p.location,
                    bio: p.bio,
                    avatar_fingerprint_hash: p.avatar_fingerprint_hash,
                    profile_completed: p.profile_completed,
                    avatar_url: p.avatar_url,
                    followers_count: p.followers_count,
                    following_count: max(0, p.safeFollowingCount + delta),
                    posts_count: p.posts_count,
                    views_count: p.views_count,
                    likes_count: p.likes_count,
                    background_photos: p.background_photos
                )
                self.myProfile = updated
                persistCachedMyProfile(updated)
            }
        }
    }

    func openOwnerItem(_ item: OwnerProfileItem, quality: TelefamNetworkQuality) {
        if let _ = item.video {
            let items = ownerItemsByCategory[ownerActiveCategory] ?? []
            let videos = items.compactMap { $0.video }
            let idx = videos.firstIndex(where: { $0.video_id == item.video?.video_id }) ?? 0
            openModalFeedPlayer(title: ownerActiveCategory.title, videos: videos, index: idx, quality: quality)
            return
        }
        activeOwnerViewerItem = item
        if quality != .offline {
            Task {
                if let res = try? await withAuthedRetry({ tok in
                    try await self.api.engagePost(token: tok, postId: item.post_id, action: "view", active: true)
                }) {
                    patchOwnerItem(postId: item.post_id) { cur in
                        OwnerProfileItem(
                            post_id: cur.post_id, post_type: cur.post_type, body: cur.body,
                            bg_color_hex: cur.bg_color_hex, bg_theme_id: cur.bg_theme_id, font_family: cur.font_family,
                            visibility: cur.visibility, thumbnail_url: cur.thumbnail_url, media_urls: cur.media_urls,
                            media_count: cur.media_count, likes_count: res.likes_count, views_count: res.views_count,
                            is_liked: cur.is_liked, is_saved: cur.is_saved, is_reposted: cur.is_reposted,
                            created_at: cur.created_at, video: cur.video
                        )
                    }
                }
            }
        }
    }

    func toggleOwnerPostLike(_ item: OwnerProfileItem) {
        let next = !item.is_liked
        patchOwnerItem(postId: item.post_id) { cur in
            OwnerProfileItem(
                post_id: cur.post_id, post_type: cur.post_type, body: cur.body,
                bg_color_hex: cur.bg_color_hex, bg_theme_id: cur.bg_theme_id, font_family: cur.font_family,
                visibility: cur.visibility, thumbnail_url: cur.thumbnail_url, media_urls: cur.media_urls,
                media_count: cur.media_count, likes_count: max(0, cur.likes_count + (next ? 1 : -1)), views_count: cur.views_count,
                is_liked: next, is_saved: cur.is_saved, is_reposted: cur.is_reposted,
                created_at: cur.created_at, video: cur.video
            )
        }
        Task {
            if let res = try? await withAuthedRetry({ tok in
                try await self.api.engagePost(token: tok, postId: item.post_id, action: "like", active: next)
            }) {
                patchOwnerItem(postId: item.post_id) { cur in
                    OwnerProfileItem(
                        post_id: cur.post_id, post_type: cur.post_type, body: cur.body,
                        bg_color_hex: cur.bg_color_hex, bg_theme_id: cur.bg_theme_id, font_family: cur.font_family,
                        visibility: cur.visibility, thumbnail_url: cur.thumbnail_url, media_urls: cur.media_urls,
                        media_count: cur.media_count, likes_count: res.likes_count, views_count: res.views_count,
                        is_liked: cur.is_liked, is_saved: cur.is_saved, is_reposted: cur.is_reposted,
                        created_at: cur.created_at, video: cur.video
                    )
                }
            }
        }
    }

    func toggleOwnerPostSave(_ item: OwnerProfileItem, quality: TelefamNetworkQuality) {
        let next = !item.is_saved
        patchOwnerItem(postId: item.post_id) { cur in
            OwnerProfileItem(
                post_id: cur.post_id, post_type: cur.post_type, body: cur.body,
                bg_color_hex: cur.bg_color_hex, bg_theme_id: cur.bg_theme_id, font_family: cur.font_family,
                visibility: cur.visibility, thumbnail_url: cur.thumbnail_url, media_urls: cur.media_urls,
                media_count: cur.media_count, likes_count: cur.likes_count, views_count: cur.views_count,
                is_liked: cur.is_liked, is_saved: next, is_reposted: cur.is_reposted,
                created_at: cur.created_at, video: cur.video
            )
        }
        Task {
            let _ = try? await withAuthedRetry { tok in
                try await self.api.engagePost(token: tok, postId: item.post_id, action: "save", active: next)
            }
            await loadOwnerProfileItems(tab: .saved, quality: quality)
        }
    }

    func toggleOwnerPostLock(_ item: OwnerProfileItem, quality: TelefamNetworkQuality) {
        let targetVis = item.visibility == "private" ? "public" : "private"
        Task {
            do {
                try await withAuthedRetry { tok in
                    try await self.api.setPostVisibility(token: tok, postId: item.post_id, visibility: targetVis)
                }
                activeOwnerViewerItem = nil
                showOwnerProfileToast(targetVis == "private" ? "Moved to Locked" : "Made Public")
                await loadOwnerProfileItems(tab: .posts, quality: quality)
                await loadOwnerProfileItems(tab: .locked, quality: quality)
            } catch let err as TelefamAPIError {
                showOwnerProfileToast(err.message)
            } catch {
                showOwnerProfileToast(TelefamCoreBridge.sanitizeError(httpStatus: 0))
            }
        }
    }

    private func patchOwnerItem(postId: String, transform: (OwnerProfileItem) -> OwnerProfileItem) {
        var nextMap = ownerItemsByCategory
        for (tab, list) in ownerItemsByCategory {
            nextMap[tab] = list.map { $0.post_id == postId ? transform($0) : $0 }
        }
        ownerItemsByCategory = nextMap
        if let active = activeOwnerViewerItem, active.post_id == postId {
            activeOwnerViewerItem = transform(active)
        }
    }

    func showOwnerProfileToast(_ message: String) {
        ownerProfileToast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if ownerProfileToast == message {
                ownerProfileToast = nil
            }
        }
    }
}
