import Foundation
import CTelefamCore

enum TelefamNetworkQuality: Int32 {
    case online = 0
    case offline = 1
}

struct CooldownSnapshot {
    let remainingSeconds: Int64
    let tierIndex: Int32
    let resendCount: Int32
    let canResend: Bool
}

final class TelefamCoreBridge {
    private var engine: OpaquePointer?

    init(vaultPath: String, masterKey: Data) {
        precondition(masterKey.count == 32, "Master key must be 32 bytes")
        self.engine = masterKey.withUnsafeBytes { rawBuf in
            guard let ptr = rawBuf.bindMemory(to: UInt8.self).baseAddress else { return nil }
            return vaultPath.withCString { pathPtr in
                telefam_engine_create(pathPtr, ptr, 32)
            }
        }
    }

    deinit {
        if let engine {
            telefam_engine_destroy(engine)
        }
    }

    static func computeDeviceFingerprint(
        platformId: String,
        hardwareModel: String,
        deviceName: String,
        hardwareSecretId: String,
        appSalt: String = "telefam-ios-fp-v1"
    ) -> String {
        var buf = [CChar](repeating: 0, count: 65)
        let _ = telefam_compute_device_fingerprint(
            platformId,
            hardwareModel,
            deviceName,
            hardwareSecretId,
            appSalt,
            &buf,
            buf.count
        )
        return String(cString: buf)
    }

    static func computeIPFingerprint(observedIP: String, subnetPrefix: String, appSalt: String = "telefam-ios-ip-v1") -> String {
        var buf = [CChar](repeating: 0, count: 65)
        let _ = telefam_compute_ip_fingerprint(observedIP, subnetPrefix, appSalt, &buf, buf.count)
        return String(cString: buf)
    }

    static func validateEmail(_ email: String) -> Bool {
        telefam_validate_email(email) == 1
    }

    static func validateOTP(_ otp: String) -> Bool {
        telefam_validate_otp(otp) == 1
    }

    static func validateAge13Plus(
        birthYear: Int32, birthMonth: Int32, birthDay: Int32,
        nowYear: Int32, nowMonth: Int32, nowDay: Int32
    ) -> Bool {
        telefam_validate_age_13_plus(birthYear, birthMonth, birthDay, nowYear, nowMonth, nowDay) == 1
    }

    static func validatePhoneNumber(countryISO: String, nationalNumber: String) -> Bool {
        telefam_validate_phone_number(countryISO, nationalNumber) == 1
    }

    static func suggestCountryISO(carrierISO: String, timezoneId: String, localeCountry: String) -> String {
        var buf = [CChar](repeating: 0, count: 4)
        telefam_suggest_country_iso(carrierISO, timezoneId, localeCountry, &buf, buf.count)
        return String(cString: buf)
    }

    static func autofillProfileFromEmail(_ email: String) -> (fullName: String, username: String) {
        var nameBuf = [CChar](repeating: 0, count: 96)
        var userBuf = [CChar](repeating: 0, count: 48)
        telefam_autofill_profile_from_email(email, &nameBuf, nameBuf.count, &userBuf, userBuf.count)
        return (String(cString: nameBuf), String(cString: userBuf))
    }

    static func sanitizeError(httpStatus: Int32, raw: String? = nil) -> String {
        var buf = [CChar](repeating: 0, count: 160)
        telefam_sanitize_error(httpStatus, raw, &buf, buf.count)
        return String(cString: buf)
    }

    func checkCooldown(email: String, nowEpochSec: Int64 = Int64(Date().timeIntervalSince1970)) -> CooldownSnapshot {
        guard let engine else { return CooldownSnapshot(remainingSeconds: 0, tierIndex: 0, resendCount: 0, canResend: true) }
        var state = telefam_cooldown_state_t()
        let _ = telefam_otp_check_cooldown(engine, email, nowEpochSec, &state)
        return CooldownSnapshot(
            remainingSeconds: state.remaining_seconds,
            tierIndex: state.tier_index,
            resendCount: state.resend_count,
            canResend: state.can_resend == 1
        )
    }

    func recordOTPSend(email: String, nowEpochSec: Int64 = Int64(Date().timeIntervalSince1970)) -> (allowed: Bool, snapshot: CooldownSnapshot) {
        guard let engine else {
            return (false, CooldownSnapshot(remainingSeconds: 60, tierIndex: 1, resendCount: 1, canResend: false))
        }
        var state = telefam_cooldown_state_t()
        let status = telefam_otp_record_send(engine, email, nowEpochSec, &state)
        let snap = CooldownSnapshot(
            remainingSeconds: state.remaining_seconds,
            tierIndex: state.tier_index,
            resendCount: state.resend_count,
            canResend: state.can_resend == 1
        )
        return (status == TELEFAM_OK, snap)
    }

    func resetCooldown(email: String) {
        guard let engine else { return }
        let _ = telefam_otp_reset_cooldown(engine, email)
    }

    func allowRateLimit(accountKey: String, deviceFP: String, ipFP: String) -> Bool {
        guard let engine else { return false }
        return telefam_rate_limit_allow(engine, accountKey, deviceFP, ipFP, Int64(Date().timeIntervalSince1970)) == 1
    }

    func allowFollowRateLimit(accountKey: String, nowEpochSec: Int64 = Int64(Date().timeIntervalSince1970)) -> Bool {
        guard let engine else { return false }
        return telefam_follow_rate_limit_allow(engine, accountKey, nowEpochSec) == 1
    }

    static func computeRelationship(isFollowing: Bool, followsMe: Bool) -> String {
        let code = telefam_relationship_state(isFollowing ? 1 : 0, followsMe ? 1 : 0)
        switch code {
        case 3: return "friends"
        case 2: return "following"
        case 1: return "follow_back"
        default: return "follow"
        }
    }

    func vaultPut(key: String, data: Data) -> Bool {
        guard let engine else { return false }
        return data.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: UInt8.self).baseAddress
            return telefam_vault_put(engine, key, ptr, data.count) == TELEFAM_OK
        }
    }

    func vaultGet(key: String) -> Data? {
        guard let engine else { return nil }
        var outLen: Int = 0
        var cap = 65536
        var buf = [UInt8](repeating: 0, count: cap)
        var status = telefam_vault_get(engine, key, &buf, cap, &outLen)
        if status == TELEFAM_ERR_STORAGE && outLen > cap {
            cap = outLen
            buf = [UInt8](repeating: 0, count: cap)
            status = telefam_vault_get(engine, key, &buf, cap, &outLen)
        }
        guard status == TELEFAM_OK else { return nil }
        return Data(buf.prefix(outLen))
    }

    func vaultDelete(key: String) {
        guard let engine else { return }
        let _ = telefam_vault_delete(engine, key)
    }

    func enqueueMutation(id: String, actionType: String, payloadJSON: String) -> Bool {
        guard let engine else { return false }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        return telefam_outbox_enqueue(engine, id, actionType, payloadJSON, nowMs) == TELEFAM_OK
    }

    func peekOutboxBatch(maxItems: Int32) -> String {
        guard let engine, maxItems > 0 else { return "[]" }
        var buf = [CChar](repeating: 0, count: 65536)
        if telefam_outbox_peek_batch(engine, maxItems, &buf, buf.count) == TELEFAM_OK {
            return String(cString: buf)
        }
        return "[]"
    }

    func ackMutation(id: String) {
        guard let engine else { return }
        let _ = telefam_outbox_ack(engine, id)
    }

    func pendingOutboxCount() -> Int32 {
        guard let engine else { return 0 }
        return telefam_outbox_pending_count(engine)
    }

    static func backoffMillis(attempt: Int32, netState: TelefamNetworkQuality) -> Int64 {
        telefam_retry_backoff_ms(attempt, telefam_network_state_t(rawValue: UInt32(netState.rawValue)))
    }

    static func adaptiveBatchSize(netState: TelefamNetworkQuality) -> Int32 {
        telefam_adaptive_batch_size(telefam_network_state_t(rawValue: UInt32(netState.rawValue)))
    }

    static func computeFrameDHash(rgbaData: Data, width: Int32, height: Int32) -> String {
        guard width > 0, height > 0, rgbaData.count >= Int(width) * Int(height) * 4 else { return "" }
        var out = [CChar](repeating: 0, count: 17)
        rgbaData.withUnsafeBytes { raw in
            if let ptr = raw.bindMemory(to: UInt8.self).baseAddress {
                let _ = telefam_compute_frame_dhash(ptr, width, height, &out, out.count)
            }
        }
        return String(cString: out)
    }

    static func computeMediaContentId(
        mediaKind: String,
        frameHashesCsv: String,
        audioFpHex: String,
        width: Int32,
        height: Int32,
        durationMs: Int64,
        salt: String = "telefam-content-id-v1"
    ) -> String {
        var out = [CChar](repeating: 0, count: 65)
        let _ = telefam_compute_media_content_id(
            mediaKind,
            frameHashesCsv,
            audioFpHex,
            width,
            height,
            durationMs,
            salt,
            &out,
            out.count
        )
        return String(cString: out)
    }

    struct FeedFittedSize {
        let width: CGFloat
        let height: CGFloat
        let aspectRatio: CGFloat
        let needsAmbientBackdrop: Bool
    }

    static func computeFeedFit(
        containerWidth: CGFloat,
        containerHeight: CGFloat,
        videoWidth: Int,
        videoHeight: Int,
        explicitRatio: Double
    ) -> FeedFittedSize {
        var fit = telefam_feed_fit_t()
        telefam_feed_compute_fit(
            Float(containerWidth),
            Float(containerHeight),
            Int32(videoWidth),
            Int32(videoHeight),
            explicitRatio,
            &fit
        )
        return FeedFittedSize(
            width: CGFloat(fit.width_px),
            height: CGFloat(fit.height_px),
            aspectRatio: CGFloat(fit.aspect_ratio),
            needsAmbientBackdrop: fit.needs_ambient_backdrop == 1
        )
    }

    static func formatFeedCount(_ value: Int64) -> String {
        var buf = [CChar](repeating: 0, count: 24)
        telefam_feed_format_count(value, &buf, buf.count)
        return String(cString: buf)
    }
}
