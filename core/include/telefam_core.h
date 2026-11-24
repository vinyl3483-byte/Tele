#ifndef TELEFAM_CORE_H
#define TELEFAM_CORE_H

#include <stdint.h>
#include <stddef.h>

#if defined(_WIN32) || defined(__CYGWIN__)
  #ifdef TELEFAM_CORE_BUILDING
    #define TELEFAM_API __declspec(dllexport)
  #else
    #define TELEFAM_API
  #endif
#else
  #define TELEFAM_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct telefam_engine_t telefam_engine_t;

typedef enum {
    TELEFAM_NET_ONLINE = 0,
    TELEFAM_NET_OFFLINE = 1
} telefam_network_state_t;

typedef enum {
    TELEFAM_OK = 0,
    TELEFAM_ERR_INVALID_INPUT = 1,
    TELEFAM_ERR_COOLDOWN_ACTIVE = 2,
    TELEFAM_ERR_RATE_LIMITED = 3,
    TELEFAM_ERR_CRYPTO = 4,
    TELEFAM_ERR_STORAGE = 5,
    TELEFAM_ERR_GENERIC = 6
} telefam_status_t;

typedef struct {
    int64_t remaining_seconds;
    int32_t tier_index;
    int32_t resend_count;
    int32_t can_resend;
} telefam_cooldown_state_t;

/* Lifecycle */
TELEFAM_API telefam_engine_t* telefam_engine_create(
    const char* vault_path,
    const uint8_t* master_key_32,
    size_t key_len
);
TELEFAM_API void telefam_engine_destroy(telefam_engine_t* engine);

/* Fingerprinting & Identity */
TELEFAM_API telefam_status_t telefam_compute_device_fingerprint(
    const char* platform_id,
    const char* hardware_model,
    const char* device_name,
    const char* hardware_secret_id,
    const char* app_salt,
    char* out_hex_65,
    size_t out_len
);

TELEFAM_API telefam_status_t telefam_compute_ip_fingerprint(
    const char* observed_ip,
    const char* subnet_prefix,
    const char* app_salt,
    char* out_hex_65,
    size_t out_len
);

/* Validation, Profile Helpers & Error Sanitization */
TELEFAM_API int32_t telefam_validate_email(const char* email);
TELEFAM_API int32_t telefam_validate_otp(const char* otp);
TELEFAM_API int32_t telefam_validate_age_13_plus(
    int32_t birth_year, int32_t birth_month, int32_t birth_day,
    int32_t now_year, int32_t now_month, int32_t now_day
);
TELEFAM_API int32_t telefam_validate_phone_number(
    const char* country_iso,
    const char* national_number
);
TELEFAM_API void telefam_suggest_country_iso(
    const char* carrier_iso,
    const char* timezone_id,
    const char* locale_country,
    char* out_iso_3,
    size_t out_len
);
TELEFAM_API void telefam_autofill_profile_from_email(
    const char* email,
    char* out_full_name, size_t full_name_cap,
    char* out_username, size_t username_cap
);
TELEFAM_API void telefam_sanitize_error(
    int32_t http_status,
    const char* raw_error,
    char* out_buf,
    size_t out_len
);

/* Persistent Encrypted OTP Cooldown (1m x3 -> 15m -> 1h -> 24h) */
TELEFAM_API telefam_status_t telefam_otp_check_cooldown(
    telefam_engine_t* engine,
    const char* email,
    int64_t now_epoch_sec,
    telefam_cooldown_state_t* out_state
);

TELEFAM_API telefam_status_t telefam_otp_record_send(
    telefam_engine_t* engine,
    const char* email,
    int64_t now_epoch_sec,
    telefam_cooldown_state_t* out_state
);

TELEFAM_API telefam_status_t telefam_otp_reset_cooldown(
    telefam_engine_t* engine,
    const char* email
);

/* Client-Side Rate Limiter (per-account, per-device, per-IP, and 50/min follow actions) */
TELEFAM_API int32_t telefam_rate_limit_allow(
    telefam_engine_t* engine,
    const char* account_key,
    const char* device_fp,
    const char* ip_fp,
    int64_t now_epoch_sec
);

TELEFAM_API int32_t telefam_follow_rate_limit_allow(
    telefam_engine_t* engine,
    const char* account_key,
    int64_t now_epoch_sec
);

/* Relationship state: 0=follow, 1=follow_back, 2=following, 3=friends */
TELEFAM_API int32_t telefam_relationship_state(
    int32_t is_following,
    int32_t follows_me
);

/* Encrypted Vault Key-Value Operations */
TELEFAM_API telefam_status_t telefam_vault_put(
    telefam_engine_t* engine,
    const char* key,
    const uint8_t* plaintext,
    size_t plaintext_len
);

TELEFAM_API telefam_status_t telefam_vault_get(
    telefam_engine_t* engine,
    const char* key,
    uint8_t* out_buf,
    size_t out_buf_cap,
    size_t* out_len
);

TELEFAM_API telefam_status_t telefam_vault_delete(
    telefam_engine_t* engine,
    const char* key
);

/* Offline-First Mutation Outbox */
TELEFAM_API telefam_status_t telefam_outbox_enqueue(
    telefam_engine_t* engine,
    const char* mutation_id,
    const char* action_type,
    const char* payload_json,
    int64_t now_epoch_ms
);

TELEFAM_API telefam_status_t telefam_outbox_peek_batch(
    telefam_engine_t* engine,
    int32_t max_items,
    char* out_json_array,
    size_t out_cap
);

TELEFAM_API telefam_status_t telefam_outbox_ack(
    telefam_engine_t* engine,
    const char* mutation_id
);

TELEFAM_API int32_t telefam_outbox_pending_count(telefam_engine_t* engine);

TELEFAM_API int64_t telefam_retry_backoff_ms(
    int32_t attempt,
    telefam_network_state_t net_state
);

TELEFAM_API int32_t telefam_adaptive_batch_size(telefam_network_state_t net_state);

/* Perceptual Frame & Deterministic Content ID Fingerprinting */
TELEFAM_API telefam_status_t telefam_compute_frame_dhash(
    const uint8_t* rgba_pixels,
    int32_t width,
    int32_t height,
    char* out_hex_17,
    size_t out_len
);

TELEFAM_API telefam_status_t telefam_compute_media_content_id(
    const char* media_kind,
    const char* frame_hashes_csv,
    const char* audio_fp_hex,
    int32_t width,
    int32_t height,
    int64_t duration_ms,
    const char* app_salt,
    char* out_hex_65,
    size_t out_len
);

#ifdef __cplusplus
}
#endif

#endif /* TELEFAM_CORE_H */
