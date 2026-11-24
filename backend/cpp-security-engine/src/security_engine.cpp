#include "security_engine.hpp"
#include "telefam_crypto.hpp"

#include <cstring>
#include <string>
#include <vector>

extern "C" {

int32_t tf_sec_hash_hmac_hex(
    const uint8_t* secret, size_t secret_len,
    const char* payload,
    char* out_hex_65, size_t out_len
) {
    if (!secret || !payload || !out_hex_65 || out_len < 65) return -1;
    auto mac = telefam::crypto::hmac_sha256(
        secret, secret_len,
        reinterpret_cast<const uint8_t*>(payload), std::strlen(payload)
    );
    auto hex = telefam::crypto::to_hex(mac.data(), mac.size());
    std::memcpy(out_hex_65, hex.c_str(), 64);
    out_hex_65[64] = '\0';
    return 0;
}

int32_t tf_sec_verify_hmac_hex(
    const uint8_t* secret, size_t secret_len,
    const char* payload,
    const char* expected_hex_64
) {
    if (!secret || !payload || !expected_hex_64 || std::strlen(expected_hex_64) != 64) return 0;
    char computed[65];
    if (tf_sec_hash_hmac_hex(secret, secret_len, payload, computed, sizeof(computed)) != 0) {
        return 0;
    }
    return telefam::crypto::constant_time_eq(
        reinterpret_cast<const uint8_t*>(computed),
        reinterpret_cast<const uint8_t*>(expected_hex_64),
        64
    ) ? 1 : 0;
}

int32_t tf_sec_encrypt_at_rest(
    const uint8_t key_32[32],
    const uint8_t* plaintext, size_t pt_len,
    const char* aad,
    uint8_t* out_blob, size_t out_cap, size_t* out_len
) {
    if (!key_32 || !out_len) return -1;
    std::vector<uint8_t> blob;
    size_t aad_len = aad ? std::strlen(aad) : 0;
    if (!telefam::crypto::aead_encrypt(
        key_32, plaintext, pt_len,
        reinterpret_cast<const uint8_t*>(aad), aad_len, blob
    )) {
        return -1;
    }
    *out_len = blob.size();
    if (!out_blob || out_cap < blob.size()) return -2;
    std::memcpy(out_blob, blob.data(), blob.size());
    return 0;
}

int32_t tf_sec_decrypt_at_rest(
    const uint8_t key_32[32],
    const uint8_t* blob, size_t blob_len,
    const char* aad,
    uint8_t* out_pt, size_t out_cap, size_t* out_len
) {
    if (!key_32 || !blob || !out_len) return -1;
    std::vector<uint8_t> pt;
    size_t aad_len = aad ? std::strlen(aad) : 0;
    if (!telefam::crypto::aead_decrypt(
        key_32, blob, blob_len,
        reinterpret_cast<const uint8_t*>(aad), aad_len, pt
    )) {
        return -1;
    }
    *out_len = pt.size();
    if (!out_pt || out_cap < pt.size()) return -2;
    if (!pt.empty()) std::memcpy(out_pt, pt.data(), pt.size());
    return 0;
}

int32_t tf_sec_score_fingerprint_risk(
    const char* prev_device_fp,
    const char* curr_device_fp,
    const char* prev_ip_fp,
    const char* curr_ip_fp
) {
    int32_t score = 0;
    if (!curr_device_fp || std::strlen(curr_device_fp) != 64) return 100;
    if (!curr_ip_fp || std::strlen(curr_ip_fp) != 64) return 100;
    if (prev_device_fp && std::strlen(prev_device_fp) == 64) {
        if (!telefam::crypto::constant_time_eq(
            reinterpret_cast<const uint8_t*>(prev_device_fp),
            reinterpret_cast<const uint8_t*>(curr_device_fp), 64)) {
            score += 60;
        }
    }
    if (prev_ip_fp && std::strlen(prev_ip_fp) == 64) {
        if (!telefam::crypto::constant_time_eq(
            reinterpret_cast<const uint8_t*>(prev_ip_fp),
            reinterpret_cast<const uint8_t*>(curr_ip_fp), 64)) {
            score += 25;
        }
    }
    return score;
}

int32_t tf_sec_compute_frame_dhash(
    const uint8_t* rgb_or_rgba_pixels,
    int32_t width,
    int32_t height,
    int32_t channels,
    char* out_hex_17,
    size_t out_len
) {
    if (!rgb_or_rgba_pixels || width <= 0 || height <= 0 || (channels != 3 && channels != 4) || !out_hex_17 || out_len < 17) {
        return -1;
    }
    double luma[8][9]{};
    for (int gy = 0; gy < 8; ++gy) {
        int y0 = (gy * height) / 8;
        int y1 = ((gy + 1) * height) / 8;
        if (y1 <= y0) y1 = y0 + 1;
        for (int gx = 0; gx < 9; ++gx) {
            int x0 = (gx * width) / 9;
            int x1 = ((gx + 1) * width) / 9;
            if (x1 <= x0) x1 = x0 + 1;
            double sum = 0.0;
            int64_t count = 0;
            for (int y = y0; y < y1 && y < height; ++y) {
                const uint8_t* row = rgb_or_rgba_pixels + static_cast<size_t>(y) * static_cast<size_t>(width) * static_cast<size_t>(channels);
                for (int x = x0; x < x1 && x < width; ++x) {
                    const uint8_t* px = row + static_cast<size_t>(x) * static_cast<size_t>(channels);
                    sum += 0.299 * px[0] + 0.587 * px[1] + 0.114 * px[2];
                    ++count;
                }
            }
            luma[gy][gx] = count > 0 ? (sum / static_cast<double>(count)) : 0.0;
        }
    }
    uint64_t hash = 0;
    for (int gy = 0; gy < 8; ++gy) {
        for (int gx = 0; gx < 8; ++gx) {
            hash <<= 1ULL;
            if (luma[gy][gx] > luma[gy][gx + 1]) {
                hash |= 1ULL;
            }
        }
    }
    std::snprintf(out_hex_17, out_len, "%016llx", static_cast<unsigned long long>(hash));
    return 0;
}

int32_t tf_sec_compute_audio_frame_fp(
    const uint8_t* pcm_bytes,
    size_t pcm_len,
    const uint8_t* secret,
    size_t secret_len,
    char* out_hex_65,
    size_t out_len
) {
    if (!pcm_bytes || !secret || !out_hex_65 || out_len < 65) return -1;
    auto mac = telefam::crypto::hmac_sha256(secret, secret_len, pcm_bytes, pcm_len);
    auto hex = telefam::crypto::to_hex(mac.data(), mac.size());
    std::memcpy(out_hex_65, hex.c_str(), 64);
    out_hex_65[64] = '\0';
    return 0;
}

int32_t tf_sec_compute_media_content_id(
    const uint8_t* secret,
    size_t secret_len,
    const char* media_kind,
    const char* frame_hashes_csv,
    const char* audio_fp_hex,
    int32_t width,
    int32_t height,
    int64_t duration_ms,
    char* out_hex_65,
    size_t out_len
) {
    if (!secret || !out_hex_65 || out_len < 65) return -1;
    std::string canonical;
    canonical.reserve(512);
    canonical += (media_kind ? media_kind : "media");
    canonical += "|";
    canonical += std::to_string(width);
    canonical += "x";
    canonical += std::to_string(height);
    canonical += "|dur=";
    canonical += std::to_string(duration_ms);
    canonical += "|frames=";
    canonical += (frame_hashes_csv ? frame_hashes_csv : "");
    canonical += "|audio=";
    canonical += (audio_fp_hex ? audio_fp_hex : "");
    return tf_sec_hash_hmac_hex(secret, secret_len, canonical.c_str(), out_hex_65, out_len);
}

} // extern "C"
