#ifndef TELEFAM_BACKEND_SECURITY_ENGINE_HPP
#define TELEFAM_BACKEND_SECURITY_ENGINE_HPP

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t tf_sec_verify_hmac_hex(
    const uint8_t* secret, size_t secret_len,
    const char* payload,
    const char* expected_hex_64
);

int32_t tf_sec_hash_hmac_hex(
    const uint8_t* secret, size_t secret_len,
    const char* payload,
    char* out_hex_65, size_t out_len
);

int32_t tf_sec_encrypt_at_rest(
    const uint8_t key_32[32],
    const uint8_t* plaintext, size_t pt_len,
    const char* aad,
    uint8_t* out_blob, size_t out_cap, size_t* out_len
);

int32_t tf_sec_decrypt_at_rest(
    const uint8_t key_32[32],
    const uint8_t* blob, size_t blob_len,
    const char* aad,
    uint8_t* out_pt, size_t out_cap, size_t* out_len
);

int32_t tf_sec_score_fingerprint_risk(
    const char* prev_device_fp,
    const char* curr_device_fp,
    const char* prev_ip_fp,
    const char* curr_ip_fp
);

int32_t tf_sec_compute_frame_dhash(
    const uint8_t* rgb_or_rgba_pixels,
    int32_t width,
    int32_t height,
    int32_t channels,
    char* out_hex_17,
    size_t out_len
);

int32_t tf_sec_compute_audio_frame_fp(
    const uint8_t* pcm_bytes,
    size_t pcm_len,
    const uint8_t* secret,
    size_t secret_len,
    char* out_hex_65,
    size_t out_len
);

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
);

#ifdef __cplusplus
}
#endif

#endif
