import Foundation

struct AuthSessionPayload: Codable {
    let access_token: String
    let refresh_token: String
    let expires_in: Int64
    let user_id: String
    let email: String
    let display_name: String
    var profile_completed: Bool
}

struct SendOTPResponse: Codable {
    let accepted: Bool
    let cooldown_seconds: Int64
}

struct AvatarUploadResponse: Codable {
    let avatar_fingerprint_hash: String
}

struct ProfileSetupRequest: Codable {
    let full_name: String
    let username: String
    let country_iso: String
    let phone_number: String
    let gender: String
    let date_of_birth: String
    let location: String
    let bio: String
    let avatar_fingerprint_hash: String
}

struct ProfileSetupResponse: Codable {
    let user_id: String
    let full_name: String
    let username: String
    let profile_completed: Bool
}

struct ConversationItem: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let updated_at: Int64
}

struct ChatMessageItem: Codable, Identifiable, Equatable {
    let id: String
    let conversation_id: String
    let sender_id: String
    let client_mutation_id: String
    let body: String
    let created_at: Int64
    var isPendingSync: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, conversation_id, sender_id, client_mutation_id, body, created_at
    }
}

struct ContactUserItem: Codable, Identifiable, Equatable {
    let user_id: String
    let full_name: String
    let username: String
    let location: String
    let avatar_fingerprint_hash: String
    var is_following: Bool
    var follows_me: Bool
    var relationship: String
    var risk_score: Int

    var id: String { user_id }
}

struct ContactsPagePayload: Codable {
    let contacts: [ContactUserItem]
    let next_cursor: String
    let has_more: Bool
}

struct FollowActionRequest: Codable {
    let target_user_id: String
    let follow: Bool
}

struct FollowActionResponse: Codable {
    let target_user_id: String
    let is_following: Bool
    let follows_me: Bool
    let relationship: String
    let risk_score: Int
}

struct MusicTrackItem: Codable, Identifiable, Equatable {
    let track_id: String
    let title: String
    let artist: String
    let artwork_url: String
    let preview_url: String
    let duration_sec: Int
    var id: String { track_id }
}

struct HashtagItem: Codable, Identifiable, Equatable {
    let tag: String
    let post_count: Int64
    var id: String { tag }
}

struct UploadedPhotoItem: Codable {
    let media_id: String
    let renamed_filename: String
    let content_id: String
    let width: Int
    let height: Int
    let perceptual_dhash: String
}

struct VideoQualityRenditionItem: Codable {
    let label: String
    let width: Int
    let height: Int
    let bitrate_kbps: Int
    let object_key: String
}

struct UploadedVideoItem: Codable {
    let media_id: String
    let renamed_filename: String
    let content_id: String
    let thumbnail_object_key: String
    let thumbnail_fingerprint: String
    let audio_fingerprint_hash: String
    let width: Int
    let height: Int
    let duration_ms: Int64
    let frame_count: Int
    let qualities: [VideoQualityRenditionItem]
}

struct CreatePostRequestIOS: Codable {
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
    let media_ids: [String]
    let tagged_user_ids: [String]
    let hashtags: [String]
}

struct CreatePostResponseIOS: Codable {
    let post_id: String
    let post_type: String
    let content_fingerprint_hash: String
    let status: String
}

enum TelefamAPIError: Error {
    case sanitized(String)
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let onProgress: (Int) -> Void

    init(onProgress: @escaping (Int) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let pct = min(92, max(2, Int((totalBytesSent * 90) / totalBytesExpectedToSend)))
        onProgress(pct)
    }
}

final class TelefamAPIClient {
    private let baseURL: URL
    private let session: URLSession
    private let uploadConfig: URLSessionConfiguration

    private static let fallbackBaseURL: URL = {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "api.telefam.app"
        return comps.url ?? URL(fileURLWithPath: "/")
    }()

    init(baseURL: URL? = nil) {
        if let provided = baseURL {
            self.baseURL = provided
        } else if let raw = Bundle.main.object(forInfoDictionaryKey: "TELEFAM_API_BASE_URL") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty,
               (trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://")),
               let parsed = URL(string: trimmed) {
                self.baseURL = parsed
            } else {
                self.baseURL = Self.fallbackBaseURL
            }
        } else {
            self.baseURL = Self.fallbackBaseURL
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)

        let uConfig = URLSessionConfiguration.default
        uConfig.timeoutIntervalForRequest = 120
        uConfig.timeoutIntervalForResource = 120
        uConfig.waitsForConnectivity = false
        self.uploadConfig = uConfig
    }

    func sendOTP(email: String, deviceFP: String, hwAttest: String, deviceName: String) async throws -> SendOTPResponse {
        let body: [String: String] = [
            "email": email,
            "device_fingerprint": deviceFP,
            "hardware_attestation": hwAttest,
            "device_name": deviceName,
            "platform": "ios"
        ]
        return try await post(path: "/v1/auth/otp/send", body: body, token: nil)
    }

    func verifyOTP(email: String, otp: String, magicToken: String?, deviceFP: String, hwAttest: String, deviceName: String) async throws -> AuthSessionPayload {
        var body: [String: String] = [
            "email": email,
            "otp": otp,
            "device_fingerprint": deviceFP,
            "hardware_attestation": hwAttest,
            "device_name": deviceName,
            "platform": "ios"
        ]
        if let magicToken { body["magic_token"] = magicToken }
        return try await post(path: "/v1/auth/otp/verify", body: body, token: nil)
    }

    func verifyOAuth(provider: String, idToken: String, deviceFP: String, hwAttest: String, deviceName: String) async throws -> AuthSessionPayload {
        let body: [String: String] = [
            "id_token": idToken,
            "device_fingerprint": deviceFP,
            "hardware_attestation": hwAttest,
            "device_name": deviceName,
            "platform": "ios"
        ]
        return try await post(path: "/v1/auth/oauth/\(provider)", body: body, token: nil)
    }

    func uploadAvatar(token: String, jpegData: Data) async throws -> AvatarUploadResponse {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/profile/avatar"))
        req.httpMethod = "POST"
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = jpegData
        let (data, response) = try await perform(req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw TelefamAPIError.sanitized(TelefamCoreBridge.sanitizeError(httpStatus: Int32(code)))
        }
        return try JSONDecoder().decode(AvatarUploadResponse.self, from: data)
    }

    func setupProfile(token: String, request: ProfileSetupRequest) async throws -> ProfileSetupResponse {
        try await post(path: "/v1/profile/setup", body: request, token: token)
    }

    func listConversations(token: String) async throws -> [ConversationItem] {
        struct Wrapper: Codable { let conversations: [ConversationItem]? }
        let res: Wrapper = try await get(path: "/v1/conversations", token: token)
        return res.conversations ?? []
    }

    func createConversation(token: String, title: String) async throws -> ConversationItem {
        try await post(path: "/v1/conversations", body: ["title": title], token: token)
    }

    func listMessages(token: String, conversationId: String) async throws -> [ChatMessageItem] {
        struct Wrapper: Codable { let messages: [ChatMessageItem]? }
        let res: Wrapper = try await get(path: "/v1/conversations/\(conversationId)/messages", token: token)
        return res.messages ?? []
    }

    func listContacts(token: String, filter: String, query: String, cursor: String, limit: Int = 30) async throws -> ContactsPagePayload {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("/v1/contacts"), resolvingAgainstBaseURL: false) else {
            throw TelefamAPIError.sanitized(TelefamCoreBridge.sanitizeError(httpStatus: 400))
        }
        components.queryItems = [
            URLQueryItem(name: "filter", value: filter),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "cursor", value: cursor),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components.url else {
            throw TelefamAPIError.sanitized(TelefamCoreBridge.sanitizeError(httpStatus: 400))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await perform(req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw TelefamAPIError.sanitized(TelefamCoreBridge.sanitizeError(httpStatus: Int32(code)))
        }
        return try JSONDecoder().decode(ContactsPagePayload.self, from: data)
    }

    func setFollowState(token: String, targetUserId: String, follow: Bool) async throws -> FollowActionResponse {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/contacts/follow"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(FollowActionRequest(target_user_id: targetUserId, follow: follow))
        let (data, response) = try await perform(req)
        guard let http = response as? HTTPURLResponse else {
            throw TelefamAPIError.sanitized(TelefamCoreBridge.sanitizeError(httpStatus: 0))
        }
        if http.statusCode == 429 {
            throw TelefamAPIError.sanitized("Try again later")
        }
        guard (200...299).contains(http.statusCode) else {
            throw TelefamAPIError.sanitized(TelefamCoreBridge.sanitizeError(httpStatus: Int32(http.statusCode)))
        }
        return try JSONDecoder().decode(FollowActionResponse.self, from: data)
    }

    func syncMutationsRaw(token: String, mutationsArrayJSON: String) async throws -> [String] {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/sync/mutations"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = "{\"mutations\":\(mutationsArrayJSON)}".data(using: .utf8)

        let (data, response) = try await perform(req)
        guard let http = response as? HTTPURLResponse else {
            throw TelefamAPIError.sanitized(TelefamCoreBridge.sanitizeError(httpStatus: 0))
        }
        guard (200...299).contains(http.statusCode) else {
            throw TelefamAPIError.sanitized(TelefamCoreBridge.sanitizeError(httpStatus: Int32(http.statusCode)))
        }
        struct AckRes: Codable { let acked_ids: [String]? }
        let decoded = try JSONDecoder().decode(AckRes.self, from: data)
        return decoded.acked_ids ?? []
    }

    func searchMusic(token: String, query: String) async throws -> [MusicTrackItem] {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("/v1/music/search"), resolvingAgainstBaseURL: false) else {
            return []
        }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await perform(req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw TelefamAPIError.sanitized(TelefamCoreBridge.sanitizeError(httpStatus: Int32(code)))
        }
        struct Wrapper: Codable { let tracks: [MusicTrackItem]? }
        return try JSONDecoder().decode(Wrapper.self, from: data).tracks ?? []
    }

    func searchHashtags(token: String, query: String) async throws -> [HashtagItem] {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("/v1/hashtags/search"), resolvingAgainstBaseURL: false) else {
            return []
        }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await perform(req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw TelefamAPIError.sanitized(TelefamCoreBridge.sanitizeError(httpStatus: Int32(code)))
        }
        struct Wrapper: Codable { let hashtags: [HashtagItem]? }
        return try JSONDecoder().decode(Wrapper.self, from: data).hashtags ?? []
    }

    func uploadPostPhotos(
        token: String,
        photosJPEG: [Data],
        onProgress: @escaping (Int) -> Void
    ) async throws -> [UploadedPhotoItem] {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        for (idx, jpeg) in photosJPEG.enumerated() {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"photos\"; filename=\"photo_\(idx).jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(jpeg)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/posts/media/photos"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let delegate = UploadProgressDelegate(onProgress: onProgress)
        let uploadSession = URLSession(configuration: uploadConfig, delegate: delegate, delegateQueue: nil)
        defer { uploadSession.finishTasksAndInvalidate() }

        let (data, response) = try await uploadSession.upload(for: req, from: body)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw TelefamAPIError.sanitized(TelefamCoreBridge.sanitizeError(httpStatus: Int32(code)))
        }
        struct Wrapper: Codable { let media: [UploadedPhotoItem]? }
        return try JSONDecoder().decode(Wrapper.self, from: data).media ?? []
    }

    func uploadPostVideo(
        token: String,
        videoFileURL: URL,
        thumbnailJPEG: Data?,
        trimStartMs: Int64,
        trimEndMs: Int64,
        thumbnailAtMs: Int64,
        muteOriginalAudio: Bool,
        songPreviewURL: String,
        onProgress: @escaping (Int) -> Void
    ) async throws -> UploadedVideoItem {
        let boundary = "Boundary-\(UUID().uuidString)"
        let tempMultipartURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload_\(UUID().uuidString).multipart")
        defer { try? FileManager.default.removeItem(at: tempMultipartURL) }

        FileManager.default.createFile(atPath: tempMultipartURL.path, contents: nil)
        let outHandle = try FileHandle(forWritingTo: tempMultipartURL)
        defer { try? outHandle.close() }

        func appendTextField(_ name: String, _ value: String) throws {
            let part = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
            if let d = part.data(using: .utf8) { try outHandle.write(contentsOf: d) }
        }

        try appendTextField("trim_start_ms", String(trimStartMs))
        try appendTextField("trim_end_ms", String(trimEndMs))
        try appendTextField("thumbnail_at_ms", String(thumbnailAtMs))
        try appendTextField("mute_original_audio", muteOriginalAudio ? "true" : "false")
        try appendTextField("song_preview_url", songPreviewURL)

        if let thumb = thumbnailJPEG {
            try outHandle.write(contentsOf: "--\(boundary)\r\nContent-Disposition: form-data; name=\"thumbnail\"; filename=\"thumb.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            try outHandle.write(contentsOf: thumb)
            try outHandle.write(contentsOf: "\r\n".data(using: .utf8)!)
        }

        try outHandle.write(contentsOf: "--\(boundary)\r\nContent-Disposition: form-data; name=\"video\"; filename=\"video.mp4\"\r\nContent-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        let inHandle = try FileHandle(forReadingFrom: videoFileURL)
        defer { try? inHandle.close() }
        while true {
            let chunk = try inHandle.read(upToCount: 65536) ?? Data()
            if chunk.isEmpty { break }
            try outHandle.write(contentsOf: chunk)
        }
        try outHandle.write(contentsOf: "\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        try outHandle.close()

        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/posts/media/video"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let delegate = UploadProgressDelegate(onProgress: onProgress)
        let uploadSession = URLSession(configuration: uploadConfig, delegate: delegate, delegateQueue: nil)
        defer { uploadSession.finishTasksAndInvalidate() }

        let (data, response) = try await uploadSession.upload(for: req, fromFile: tempMultipartURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw TelefamAPIError.sanitized(TelefamCoreBridge.sanitizeError(httpStatus: Int32(code)))
        }
        return try JSONDecoder().decode(UploadedVideoItem.self, from: data)
    }

    func createPost(token: String, request: CreatePostRequestIOS) async throws -> CreatePostResponseIOS {
        try await post(path: "/v1/posts", body: request, token: token)
    }

    private func get<T: Decodable>(path: String, token: String?) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "GET"
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await perform(req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw TelefamAPIError.sanitized(TelefamCoreBridge.sanitizeError(httpStatus: Int32(code)))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<B: Encodable, T: Decodable>(path: String, body: B, token: String?) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await perform(req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw TelefamAPIError.sanitized(TelefamCoreBridge.sanitizeError(httpStatus: Int32(code)))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func perform(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: req)
        } catch {
            throw TelefamAPIError.sanitized(TelefamCoreBridge.sanitizeError(httpStatus: 0))
        }
    }
}
