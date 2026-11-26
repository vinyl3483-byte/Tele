#include "telefam_engine.hpp"
#include "telefam_crypto.hpp"

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <sstream>

namespace telefam {

namespace {

std::string normalize_lower(const std::string& s) {
    std::string out;
    out.reserve(s.size());
    for (unsigned char c : s) {
        if (!std::isspace(c)) {
            out.push_back(static_cast<char>(std::tolower(c)));
        }
    }
    return out;
}

std::string to_upper_ascii(const std::string& s) {
    std::string out;
    out.reserve(s.size());
    for (unsigned char c : s) {
        if (std::isalpha(c)) out.push_back(static_cast<char>(std::toupper(c)));
    }
    return out;
}

struct CountryPhoneRule {
    const char* iso;
    int min_digits;
    int max_digits;
    const char* required_prefix;
};

constexpr CountryPhoneRule COUNTRY_PHONE_RULES[] = {
    {"KE", 9, 10, ""},
    {"US", 10, 10, ""},
    {"CA", 10, 10, ""},
    {"GB", 10, 10, ""},
    {"NG", 10, 10, ""},
    {"ZA", 9, 9, ""},
    {"TZ", 9, 9, ""},
    {"UG", 9, 9, ""},
    {"RW", 9, 9, ""},
    {"ET", 9, 9, ""},
    {"IN", 10, 10, ""},
    {"DE", 10, 11, ""},
    {"FR", 9, 9, ""},
    {"AE", 9, 9, ""},
    {"AU", 9, 9, ""},
    {"JP", 10, 10, ""},
    {"BR", 10, 11, ""},
};

struct TzCountryMap {
    const char* tz_substr;
    const char* iso;
};

constexpr TzCountryMap TZ_COUNTRY_MAP[] = {
    {"Nairobi", "KE"},
    {"Lagos", "NG"},
    {"Johannesburg", "ZA"},
    {"Dar_es_Salaam", "TZ"},
    {"Kampala", "UG"},
    {"Kigali", "RW"},
    {"Addis_Ababa", "ET"},
    {"London", "GB"},
    {"New_York", "US"},
    {"Chicago", "US"},
    {"Denver", "US"},
    {"Los_Angeles", "US"},
    {"Toronto", "CA"},
    {"Vancouver", "CA"},
    {"Kolkata", "IN"},
    {"Calcutta", "IN"},
    {"Berlin", "DE"},
    {"Paris", "FR"},
    {"Dubai", "AE"},
    {"Sydney", "AU"},
    {"Tokyo", "JP"},
    {"Sao_Paulo", "BR"},
};

void write_u32(std::vector<uint8_t>& buf, uint32_t v) {
    buf.push_back(static_cast<uint8_t>((v >> 24) & 0xff));
    buf.push_back(static_cast<uint8_t>((v >> 16) & 0xff));
    buf.push_back(static_cast<uint8_t>((v >> 8) & 0xff));
    buf.push_back(static_cast<uint8_t>(v & 0xff));
}

void write_i64(std::vector<uint8_t>& buf, int64_t v) {
    uint64_t u = static_cast<uint64_t>(v);
    for (int i = 7; i >= 0; --i) {
        buf.push_back(static_cast<uint8_t>((u >> (i * 8)) & 0xff));
    }
}

void write_str(std::vector<uint8_t>& buf, const std::string& s) {
    write_u32(buf, static_cast<uint32_t>(s.size()));
    buf.insert(buf.end(), s.begin(), s.end());
}

bool read_u32(const uint8_t* data, std::size_t len, std::size_t& off, uint32_t& out) {
    if (off + 4 > len) return false;
    out = (static_cast<uint32_t>(data[off]) << 24) |
          (static_cast<uint32_t>(data[off + 1]) << 16) |
          (static_cast<uint32_t>(data[off + 2]) << 8) |
          static_cast<uint32_t>(data[off + 3]);
    off += 4;
    return true;
}

bool read_i64(const uint8_t* data, std::size_t len, std::size_t& off, int64_t& out) {
    if (off + 8 > len) return false;
    uint64_t u = 0;
    for (int i = 0; i < 8; ++i) {
        u = (u << 8) | static_cast<uint64_t>(data[off + i]);
    }
    out = static_cast<int64_t>(u);
    off += 8;
    return true;
}

bool read_str(const uint8_t* data, std::size_t len, std::size_t& off, std::string& out) {
    uint32_t slen = 0;
    if (!read_u32(data, len, off, slen) || off + slen > len) return false;
    out.assign(reinterpret_cast<const char*>(data + off), slen);
    off += slen;
    return true;
}

std::string json_escape(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 8);
    for (char c : s) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default: out.push_back(c); break;
        }
    }
    return out;
}

} // namespace

Engine::Engine(std::string vault_path, const uint8_t master_key[32])
    : vault_path_(std::move(vault_path)) {
    std::memcpy(master_key_, master_key, 32);
    load_encrypted_state();
}

Engine::~Engine() {
    crypto::secure_zero(master_key_, sizeof(master_key_));
}

int64_t Engine::cooldown_duration_for_count(int32_t count_1_based, int32_t& out_tier) {
    if (count_1_based <= 3) {
        out_tier = 1;
        return 60LL;
    }
    if (count_1_based == 4) {
        out_tier = 2;
        return 15LL * 60LL;
    }
    if (count_1_based == 5) {
        out_tier = 3;
        return 60LL * 60LL;
    }
    out_tier = 4;
    return 24LL * 60LL * 60LL;
}

void Engine::load_encrypted_state() {
    if (vault_path_.empty()) return;
    std::ifstream in(vault_path_, std::ios::binary | std::ios::ate);
    if (!in.is_open()) return;
    auto size = in.tellg();
    if (size <= 0) return;
    in.seekg(0, std::ios::beg);
    std::vector<uint8_t> blob(static_cast<std::size_t>(size));
    if (!in.read(reinterpret_cast<char*>(blob.data()), size)) return;

    static const char* AAD = "telefam-vault-v1";
    std::vector<uint8_t> pt;
    if (!crypto::aead_decrypt(master_key_, blob.data(), blob.size(),
            reinterpret_cast<const uint8_t*>(AAD), std::strlen(AAD), pt)) {
        return;
    }

    std::size_t off = 0;
    uint32_t kv_count = 0;
    if (!read_u32(pt.data(), pt.size(), off, kv_count)) return;
    for (uint32_t i = 0; i < kv_count; ++i) {
        std::string k;
        uint32_t vlen = 0;
        if (!read_str(pt.data(), pt.size(), off, k)) return;
        if (!read_u32(pt.data(), pt.size(), off, vlen) || off + vlen > pt.size()) return;
        std::vector<uint8_t> v(pt.begin() + off, pt.begin() + off + vlen);
        off += vlen;
        kv_store_[std::move(k)] = std::move(v);
    }

    uint32_t cd_count = 0;
    if (!read_u32(pt.data(), pt.size(), off, cd_count)) return;
    for (uint32_t i = 0; i < cd_count; ++i) {
        std::string email;
        int64_t rcount = 0, blocked = 0, last = 0;
        if (!read_str(pt.data(), pt.size(), off, email)) return;
        if (!read_i64(pt.data(), pt.size(), off, rcount)) return;
        if (!read_i64(pt.data(), pt.size(), off, blocked)) return;
        if (!read_i64(pt.data(), pt.size(), off, last)) return;
        cooldowns_[std::move(email)] = CooldownEntry{
            static_cast<int32_t>(rcount), blocked, last
        };
    }

    uint32_t ob_count = 0;
    if (!read_u32(pt.data(), pt.size(), off, ob_count)) return;
    for (uint32_t i = 0; i < ob_count; ++i) {
        OutboxItem item;
        if (!read_str(pt.data(), pt.size(), off, item.mutation_id)) return;
        if (!read_str(pt.data(), pt.size(), off, item.action_type)) return;
        if (!read_str(pt.data(), pt.size(), off, item.payload_json)) return;
        if (!read_i64(pt.data(), pt.size(), off, item.created_at_ms)) return;
        outbox_.push_back(std::move(item));
    }
    crypto::secure_zero(pt.data(), pt.size());
}

bool Engine::persist_encrypted_state() {
    if (vault_path_.empty()) return true;
    std::vector<uint8_t> pt;
    write_u32(pt, static_cast<uint32_t>(kv_store_.size()));
    for (const auto& [k, v] : kv_store_) {
        write_str(pt, k);
        write_u32(pt, static_cast<uint32_t>(v.size()));
        pt.insert(pt.end(), v.begin(), v.end());
    }
    write_u32(pt, static_cast<uint32_t>(cooldowns_.size()));
    for (const auto& [email, c] : cooldowns_) {
        write_str(pt, email);
        write_i64(pt, c.resend_count);
        write_i64(pt, c.blocked_until);
        write_i64(pt, c.last_sent_at);
    }
    write_u32(pt, static_cast<uint32_t>(outbox_.size()));
    for (const auto& item : outbox_) {
        write_str(pt, item.mutation_id);
        write_str(pt, item.action_type);
        write_str(pt, item.payload_json);
        write_i64(pt, item.created_at_ms);
    }

    static const char* AAD = "telefam-vault-v1";
    std::vector<uint8_t> blob;
    bool ok = crypto::aead_encrypt(master_key_, pt.data(), pt.size(),
        reinterpret_cast<const uint8_t*>(AAD), std::strlen(AAD), blob);
    crypto::secure_zero(pt.data(), pt.size());
    if (!ok) return false;

    std::string tmp = vault_path_ + ".tmp";
    std::ofstream out(tmp, std::ios::binary | std::ios::trunc);
    if (!out.is_open()) return false;
    out.write(reinterpret_cast<const char*>(blob.data()), static_cast<std::streamsize>(blob.size()));
    out.flush();
    out.close();
    if (!out) return false;
    std::rename(tmp.c_str(), vault_path_.c_str());
    return true;
}

telefam_status_t Engine::check_cooldown(const std::string& email, int64_t now_sec, telefam_cooldown_state_t& out) {
    std::lock_guard<std::mutex> lock(mu_);
    std::string key = crypto::sha256_hex(normalize_lower(email));
    auto it = cooldowns_.find(key);
    if (it == cooldowns_.end()) {
        out = telefam_cooldown_state_t{0, 0, 0, 1};
        return TELEFAM_OK;
    }
    const auto& entry = it->second;
    int64_t rem = std::max<int64_t>(0, entry.blocked_until - now_sec);
    int32_t tier = 0;
    if (entry.resend_count > 0) {
        cooldown_duration_for_count(entry.resend_count, tier);
    }
    out.remaining_seconds = rem;
    out.tier_index = tier;
    out.resend_count = entry.resend_count;
    out.can_resend = (rem == 0) ? 1 : 0;
    return TELEFAM_OK;
}

telefam_status_t Engine::record_otp_send(const std::string& email, int64_t now_sec, telefam_cooldown_state_t& out) {
    std::lock_guard<std::mutex> lock(mu_);
    std::string key = crypto::sha256_hex(normalize_lower(email));
    auto& entry = cooldowns_[key];
    if (entry.blocked_until > now_sec) {
        int32_t tier = 0;
        cooldown_duration_for_count(std::max(1, entry.resend_count), tier);
        out = telefam_cooldown_state_t{entry.blocked_until - now_sec, tier, entry.resend_count, 0};
        return TELEFAM_ERR_COOLDOWN_ACTIVE;
    }
    if (entry.last_sent_at > 0 && (now_sec - entry.last_sent_at) > 86400LL) {
        entry.resend_count = 0;
    }
    entry.resend_count += 1;
    int32_t tier = 1;
    int64_t duration = cooldown_duration_for_count(entry.resend_count, tier);
    entry.last_sent_at = now_sec;
    entry.blocked_until = now_sec + duration;
    persist_encrypted_state();

    out.remaining_seconds = duration;
    out.tier_index = tier;
    out.resend_count = entry.resend_count;
    out.can_resend = 0;
    return TELEFAM_OK;
}

telefam_status_t Engine::reset_cooldown(const std::string& email) {
    std::lock_guard<std::mutex> lock(mu_);
    std::string key = crypto::sha256_hex(normalize_lower(email));
    cooldowns_.erase(key);
    persist_encrypted_state();
    return TELEFAM_OK;
}

bool Engine::check_bucket(const std::string& bucket_key, int64_t now_sec, int32_t max_requests, int64_t window_sec) {
    auto& q = rate_buckets_[bucket_key];
    while (!q.empty() && (now_sec - q.front()) >= window_sec) {
        q.pop_front();
    }
    if (static_cast<int32_t>(q.size()) >= max_requests) {
        return false;
    }
    q.push_back(now_sec);
    return true;
}

bool Engine::allow_rate_limit(const std::string& account_key, const std::string& device_fp, const std::string& ip_fp, int64_t now_sec) {
    std::lock_guard<std::mutex> lock(mu_);
    if (!account_key.empty() && !check_bucket("acc:" + normalize_lower(account_key), now_sec, 10, 60)) {
        return false;
    }
    if (!device_fp.empty() && !check_bucket("dev:" + device_fp, now_sec, 30, 60)) {
        return false;
    }
    if (!ip_fp.empty() && !check_bucket("ip:" + ip_fp, now_sec, 45, 60)) {
        return false;
    }
    return true;
}

bool Engine::allow_follow_rate_limit(const std::string& account_key, int64_t now_sec) {
    std::lock_guard<std::mutex> lock(mu_);
    std::string key = "follow:" + (account_key.empty() ? std::string("self") : normalize_lower(account_key));
    return check_bucket(key, now_sec, 50, 60);
}

telefam_status_t Engine::vault_put(const std::string& key, const std::vector<uint8_t>& value) {
    std::lock_guard<std::mutex> lock(mu_);
    kv_store_[key] = value;
    return persist_encrypted_state() ? TELEFAM_OK : TELEFAM_ERR_STORAGE;
}

telefam_status_t Engine::vault_get(const std::string& key, std::vector<uint8_t>& out_value) {
    std::lock_guard<std::mutex> lock(mu_);
    auto it = kv_store_.find(key);
    if (it == kv_store_.end()) return TELEFAM_ERR_STORAGE;
    out_value = it->second;
    return TELEFAM_OK;
}

telefam_status_t Engine::vault_delete(const std::string& key) {
    std::lock_guard<std::mutex> lock(mu_);
    kv_store_.erase(key);
    return persist_encrypted_state() ? TELEFAM_OK : TELEFAM_ERR_STORAGE;
}

telefam_status_t Engine::outbox_enqueue(const std::string& id, const std::string& action, const std::string& payload, int64_t now_ms) {
    std::lock_guard<std::mutex> lock(mu_);
    for (const auto& existing : outbox_) {
        if (existing.mutation_id == id) return TELEFAM_OK;
    }
    outbox_.push_back(OutboxItem{id, action, payload, now_ms});
    return persist_encrypted_state() ? TELEFAM_OK : TELEFAM_ERR_STORAGE;
}

std::string Engine::outbox_peek_json(int32_t max_items) {
    std::lock_guard<std::mutex> lock(mu_);
    std::ostringstream ss;
    ss << "[";
    int32_t limit = std::min<int32_t>(max_items, static_cast<int32_t>(outbox_.size()));
    for (int32_t i = 0; i < limit; ++i) {
        if (i > 0) ss << ",";
        ss << "{\"mutation_id\":\"" << json_escape(outbox_[i].mutation_id)
           << "\",\"action_type\":\"" << json_escape(outbox_[i].action_type)
           << "\",\"payload\":" << (outbox_[i].payload_json.empty() ? "{}" : outbox_[i].payload_json)
           << ",\"created_at_ms\":" << outbox_[i].created_at_ms << "}";
    }
    ss << "]";
    return ss.str();
}

telefam_status_t Engine::outbox_ack(const std::string& id) {
    std::lock_guard<std::mutex> lock(mu_);
    auto it = std::remove_if(outbox_.begin(), outbox_.end(),
        [&id](const OutboxItem& item) { return item.mutation_id == id; });
    if (it != outbox_.end()) {
        outbox_.erase(it, outbox_.end());
        persist_encrypted_state();
    }
    return TELEFAM_OK;
}

int32_t Engine::outbox_count() {
    std::lock_guard<std::mutex> lock(mu_);
    return static_cast<int32_t>(outbox_.size());
}

} // namespace telefam

struct telefam_engine_t {
    telefam::Engine impl;
    telefam_engine_t(std::string path, const uint8_t key[32])
        : impl(std::move(path), key) {}
};

extern "C" {

telefam_engine_t* telefam_engine_create(const char* vault_path, const uint8_t* master_key_32, size_t key_len) {
    if (!master_key_32 || key_len != 32) return nullptr;
    std::string path = vault_path ? vault_path : "";
    return new telefam_engine_t(std::move(path), master_key_32);
}

void telefam_engine_destroy(telefam_engine_t* engine) {
    delete engine;
}

telefam_status_t telefam_compute_device_fingerprint(
    const char* platform_id,
    const char* hardware_model,
    const char* device_name,
    const char* hardware_secret_id,
    const char* app_salt,
    char* out_hex_65,
    size_t out_len
) {
    if (!out_hex_65 || out_len < 65) return TELEFAM_ERR_INVALID_INPUT;
    std::string canonical;
    canonical.reserve(256);
    canonical += (platform_id ? platform_id : "");
    canonical += "|";
    canonical += (hardware_model ? hardware_model : "");
    canonical += "|";
    canonical += (device_name ? device_name : "");
    canonical += "|";
    canonical += (hardware_secret_id ? hardware_secret_id : "");

    const char* salt = app_salt ? app_salt : "telefam-device-fp-v1";
    auto mac = telefam::crypto::hmac_sha256(
        reinterpret_cast<const uint8_t*>(salt), std::strlen(salt),
        reinterpret_cast<const uint8_t*>(canonical.data()), canonical.size()
    );
    auto hex = telefam::crypto::to_hex(mac.data(), mac.size());
    std::memcpy(out_hex_65, hex.c_str(), 64);
    out_hex_65[64] = '\0';
    return TELEFAM_OK;
}

telefam_status_t telefam_compute_ip_fingerprint(
    const char* observed_ip,
    const char* subnet_prefix,
    const char* app_salt,
    char* out_hex_65,
    size_t out_len
) {
    if (!out_hex_65 || out_len < 65) return TELEFAM_ERR_INVALID_INPUT;
    std::string canonical = std::string(observed_ip ? observed_ip : "") + "|" +
                            std::string(subnet_prefix ? subnet_prefix : "");
    const char* salt = app_salt ? app_salt : "telefam-ip-fp-v1";
    auto mac = telefam::crypto::hmac_sha256(
        reinterpret_cast<const uint8_t*>(salt), std::strlen(salt),
        reinterpret_cast<const uint8_t*>(canonical.data()), canonical.size()
    );
    auto hex = telefam::crypto::to_hex(mac.data(), mac.size());
    std::memcpy(out_hex_65, hex.c_str(), 64);
    out_hex_65[64] = '\0';
    return TELEFAM_OK;
}

int32_t telefam_validate_email(const char* email) {
    if (!email) return 0;
    std::string s(email);
    if (s.size() < 5 || s.size() > 254) return 0;
    auto at = s.find('@');
    if (at == std::string::npos || at == 0 || at == s.size() - 1) return 0;
    if (s.find('@', at + 1) != std::string::npos) return 0;
    auto dot = s.find('.', at + 1);
    if (dot == std::string::npos || dot == at + 1 || dot == s.size() - 1) return 0;
    for (unsigned char c : s) {
        if (std::isspace(c) || c < 33 || c > 126) return 0;
    }
    return 1;
}

int32_t telefam_validate_otp(const char* otp) {
    if (!otp || std::strlen(otp) != 6) return 0;
    for (int i = 0; i < 6; ++i) {
        if (!std::isdigit(static_cast<unsigned char>(otp[i]))) return 0;
    }
    return 1;
}

int32_t telefam_validate_age_13_plus(
    int32_t birth_year, int32_t birth_month, int32_t birth_day,
    int32_t now_year, int32_t now_month, int32_t now_day
) {
    if (birth_year < 1900 || birth_month < 1 || birth_month > 12 || birth_day < 1 || birth_day > 31) {
        return 0;
    }
    int32_t age = now_year - birth_year;
    if (now_month < birth_month || (now_month == birth_month && now_day < birth_day)) {
        age -= 1;
    }
    return age >= 13 ? 1 : 0;
}

int32_t telefam_validate_phone_number(const char* country_iso, const char* national_number) {
    if (!country_iso || !national_number) return 0;
    std::string iso = telefam::to_upper_ascii(country_iso);
    std::string digits;
    for (const char* p = national_number; *p != '\0'; ++p) {
        if (std::isdigit(static_cast<unsigned char>(*p))) {
            digits.push_back(*p);
        } else if (*p != ' ' && *p != '-' && *p != '(' && *p != ')') {
            return 0;
        }
    }
    // Strip optional leading trunk '0' for local format entry (e.g. 0712345678 -> 712345678)
    if (digits.size() > 6 && digits[0] == '0') {
        digits.erase(0, 1);
    }
    for (const auto& rule : telefam::COUNTRY_PHONE_RULES) {
        if (iso == rule.iso) {
            int len = static_cast<int>(digits.size());
            return (len >= rule.min_digits && len <= rule.max_digits) ? 1 : 0;
        }
    }
    int len = static_cast<int>(digits.size());
    return (len >= 7 && len <= 15) ? 1 : 0;
}

void telefam_suggest_country_iso(
    const char* carrier_iso,
    const char* timezone_id,
    const char* locale_country,
    char* out_iso_3,
    size_t out_len
) {
    if (!out_iso_3 || out_len < 3) return;
    std::string carrier = telefam::to_upper_ascii(carrier_iso ? carrier_iso : "");
    if (carrier.size() == 2) {
        std::snprintf(out_iso_3, out_len, "%s", carrier.c_str());
        return;
    }
    std::string tz = timezone_id ? timezone_id : "";
    for (const auto& entry : telefam::TZ_COUNTRY_MAP) {
        if (!tz.empty() && tz.find(entry.tz_substr) != std::string::npos) {
            std::snprintf(out_iso_3, out_len, "%s", entry.iso);
            return;
        }
    }
    std::string loc = telefam::to_upper_ascii(locale_country ? locale_country : "");
    if (loc.size() == 2) {
        std::snprintf(out_iso_3, out_len, "%s", loc.c_str());
        return;
    }
    std::snprintf(out_iso_3, out_len, "KE");
}

void telefam_autofill_profile_from_email(
    const char* email,
    char* out_full_name, size_t full_name_cap,
    char* out_username, size_t username_cap
) {
    if (!email) return;
    std::string s(email);
    auto at = s.find('@');
    std::string prefix = (at == std::string::npos) ? s : s.substr(0, at);

    if (out_full_name && full_name_cap > 0) {
        std::string full;
        bool cap_next = true;
        for (unsigned char c : prefix) {
            if (c == '.' || c == '_' || c == '-') {
                if (!full.empty() && full.back() != ' ') full.push_back(' ');
                cap_next = true;
            } else if (std::isalnum(c)) {
                full.push_back(cap_next ? static_cast<char>(std::toupper(c)) : static_cast<char>(std::tolower(c)));
                cap_next = false;
            }
        }
        std::snprintf(out_full_name, full_name_cap, "%s", full.c_str());
    }
    if (out_username && username_cap > 0) {
        std::string uname;
        for (unsigned char c : prefix) {
            if (std::isalnum(c) || c == '_') {
                uname.push_back(static_cast<char>(std::tolower(c)));
            } else if (c == '.' || c == '-') {
                if (!uname.empty() && uname.back() != '_') uname.push_back('_');
            }
        }
        std::snprintf(out_username, username_cap, "%s", uname.c_str());
    }
}

void telefam_sanitize_error(int32_t http_status, const char* /*raw_error*/, char* out_buf, size_t out_len) {
    if (!out_buf || out_len == 0) return;
    const char* safe_msg = "Error has occurred, try again later.";
    if (http_status == 0) {
        safe_msg = "No internet.";
    }
    std::snprintf(out_buf, out_len, "%s", safe_msg);
}

telefam_status_t telefam_otp_check_cooldown(
    telefam_engine_t* engine, const char* email, int64_t now_epoch_sec, telefam_cooldown_state_t* out_state
) {
    if (!engine || !email || !out_state) return TELEFAM_ERR_INVALID_INPUT;
    return engine->impl.check_cooldown(email, now_epoch_sec, *out_state);
}

telefam_status_t telefam_otp_record_send(
    telefam_engine_t* engine, const char* email, int64_t now_epoch_sec, telefam_cooldown_state_t* out_state
) {
    if (!engine || !email || !out_state) return TELEFAM_ERR_INVALID_INPUT;
    return engine->impl.record_otp_send(email, now_epoch_sec, *out_state);
}

telefam_status_t telefam_otp_reset_cooldown(telefam_engine_t* engine, const char* email) {
    if (!engine || !email) return TELEFAM_ERR_INVALID_INPUT;
    return engine->impl.reset_cooldown(email);
}

int32_t telefam_rate_limit_allow(
    telefam_engine_t* engine, const char* account_key, const char* device_fp, const char* ip_fp, int64_t now_epoch_sec
) {
    if (!engine) return 0;
    return engine->impl.allow_rate_limit(
        account_key ? account_key : "",
        device_fp ? device_fp : "",
        ip_fp ? ip_fp : "",
        now_epoch_sec
    ) ? 1 : 0;
}

int32_t telefam_follow_rate_limit_allow(
    telefam_engine_t* engine, const char* account_key, int64_t now_epoch_sec
) {
    if (!engine) return 0;
    return engine->impl.allow_follow_rate_limit(
        account_key ? account_key : "",
        now_epoch_sec
    ) ? 1 : 0;
}

int32_t telefam_relationship_state(int32_t is_following, int32_t follows_me) {
    if (is_following != 0 && follows_me != 0) return 3; // friends
    if (is_following != 0) return 2;                     // following
    if (follows_me != 0) return 1;                       // follow_back
    return 0;                                            // follow
}

telefam_status_t telefam_vault_put(
    telefam_engine_t* engine, const char* key, const uint8_t* plaintext, size_t plaintext_len
) {
    if (!engine || !key || (!plaintext && plaintext_len > 0)) return TELEFAM_ERR_INVALID_INPUT;
    std::vector<uint8_t> data(plaintext, plaintext + plaintext_len);
    return engine->impl.vault_put(key, data);
}

telefam_status_t telefam_vault_get(
    telefam_engine_t* engine, const char* key, uint8_t* out_buf, size_t out_buf_cap, size_t* out_len
) {
    if (!engine || !key || !out_len) return TELEFAM_ERR_INVALID_INPUT;
    std::vector<uint8_t> data;
    auto st = engine->impl.vault_get(key, data);
    if (st != TELEFAM_OK) return st;
    *out_len = data.size();
    if (!out_buf || out_buf_cap < data.size()) return TELEFAM_ERR_STORAGE;
    if (!data.empty()) std::memcpy(out_buf, data.data(), data.size());
    return TELEFAM_OK;
}

telefam_status_t telefam_vault_delete(telefam_engine_t* engine, const char* key) {
    if (!engine || !key) return TELEFAM_ERR_INVALID_INPUT;
    return engine->impl.vault_delete(key);
}

telefam_status_t telefam_outbox_enqueue(
    telefam_engine_t* engine, const char* mutation_id, const char* action_type, const char* payload_json, int64_t now_epoch_ms
) {
    if (!engine || !mutation_id || !action_type) return TELEFAM_ERR_INVALID_INPUT;
    return engine->impl.outbox_enqueue(mutation_id, action_type, payload_json ? payload_json : "{}", now_epoch_ms);
}

telefam_status_t telefam_outbox_peek_batch(
    telefam_engine_t* engine, int32_t max_items, char* out_json_array, size_t out_cap
) {
    if (!engine || !out_json_array || out_cap == 0) return TELEFAM_ERR_INVALID_INPUT;
    std::string json = engine->impl.outbox_peek_json(max_items);
    if (json.size() + 1 > out_cap) return TELEFAM_ERR_STORAGE;
    std::memcpy(out_json_array, json.c_str(), json.size() + 1);
    return TELEFAM_OK;
}

telefam_status_t telefam_outbox_ack(telefam_engine_t* engine, const char* mutation_id) {
    if (!engine || !mutation_id) return TELEFAM_ERR_INVALID_INPUT;
    return engine->impl.outbox_ack(mutation_id);
}

int32_t telefam_outbox_pending_count(telefam_engine_t* engine) {
    return engine ? engine->impl.outbox_count() : 0;
}

int64_t telefam_retry_backoff_ms(int32_t attempt, telefam_network_state_t net_state) {
    if (net_state == TELEFAM_NET_OFFLINE) return 5000LL;
    if (attempt < 0) attempt = 0;
    if (attempt > 6) attempt = 6;
    int64_t delay = 750LL * (1LL << attempt);
    if (delay > 30000LL) delay = 30000LL;
    return delay;
}

int32_t telefam_adaptive_batch_size(telefam_network_state_t net_state) {
    return (net_state == TELEFAM_NET_ONLINE) ? 25 : 0;
}

telefam_status_t telefam_compute_frame_dhash(
    const uint8_t* rgba_pixels,
    int32_t width,
    int32_t height,
    char* out_hex_17,
    size_t out_len
) {
    if (!rgba_pixels || width <= 0 || height <= 0 || !out_hex_17 || out_len < 17) {
        return TELEFAM_ERR_INVALID_INPUT;
    }

    // 9x8 luma grid computed via block averaging for invariance to resize/compression
    double luma[8][9]{};
    for (int gy = 0; gy < 8; ++gy) {
        int y0 = (gy * height) / 8;
        int y1 = std::max(y0 + 1, ((gy + 1) * height) / 8);
        for (int gx = 0; gx < 9; ++gx) {
            int x0 = (gx * width) / 9;
            int x1 = std::max(x0 + 1, ((gx + 1) * width) / 9);
            double sum = 0.0;
            int64_t count = 0;
            for (int y = y0; y < y1 && y < height; ++y) {
                const uint8_t* row = rgba_pixels + static_cast<size_t>(y) * static_cast<size_t>(width) * 4ULL;
                for (int x = x0; x < x1 && x < width; ++x) {
                    const uint8_t* px = row + static_cast<size_t>(x) * 4ULL;
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
    return TELEFAM_OK;
}

telefam_status_t telefam_compute_media_content_id(
    const char* media_kind,
    const char* frame_hashes_csv,
    const char* audio_fp_hex,
    int32_t width,
    int32_t height,
    int64_t duration_ms,
    const char* app_salt,
    char* out_hex_65,
    size_t out_len
) {
    if (!out_hex_65 || out_len < 65) return TELEFAM_ERR_INVALID_INPUT;
    std::ostringstream canonical;
    canonical << (media_kind ? media_kind : "media")
              << "|" << width << "x" << height
              << "|dur=" << duration_ms
              << "|frames=" << (frame_hashes_csv ? frame_hashes_csv : "")
              << "|audio=" << (audio_fp_hex ? audio_fp_hex : "");

    const std::string payload = canonical.str();
    const char* salt = (app_salt && std::strlen(app_salt) > 0) ? app_salt : "telefam-content-id-v1";
    auto mac = telefam::crypto::hmac_sha256(
        reinterpret_cast<const uint8_t*>(salt), std::strlen(salt),
        reinterpret_cast<const uint8_t*>(payload.data()), payload.size()
    );
    auto hex = telefam::crypto::to_hex(mac.data(), mac.size());
    std::memcpy(out_hex_65, hex.c_str(), 64);
    out_hex_65[64] = '\0';
    return TELEFAM_OK;
}

void telefam_feed_compute_fit(
    float container_w,
    float container_h,
    int32_t video_w,
    int32_t video_h,
    double explicit_ratio,
    telefam_feed_fit_t* out_fit
) {
    if (!out_fit) return;
    if (container_w <= 0.0f || container_h <= 0.0f) {
        out_fit->width_px = 0.0f;
        out_fit->height_px = 0.0f;
        out_fit->aspect_ratio = 9.0f / 16.0f;
        out_fit->needs_ambient_backdrop = 0;
        return;
    }
    double ratio = explicit_ratio;
    if (video_w > 0 && video_h > 0) {
        ratio = static_cast<double>(video_w) / static_cast<double>(video_h);
    } else if (!(ratio > 0.05 && ratio < 10.0)) {
        ratio = 9.0 / 16.0;
    }
    const float video_ratio = static_cast<float>(std::clamp(ratio, 0.25, 4.0));
    const float container_ratio = container_w / container_h;
    float fit_w = 0.0f;
    float fit_h = 0.0f;
    if (video_ratio > container_ratio) {
        fit_w = container_w;
        fit_h = container_w / video_ratio;
    } else {
        fit_h = container_h;
        fit_w = container_h * video_ratio;
    }
    const float diff = std::abs(video_ratio - container_ratio) / std::max(0.1f, container_ratio);
    out_fit->width_px = fit_w;
    out_fit->height_px = fit_h;
    out_fit->aspect_ratio = video_ratio;
    out_fit->needs_ambient_backdrop = (diff > 0.14f) ? 1 : 0;
}

void telefam_feed_format_count(int64_t value, char* out_buf, size_t out_len) {
    if (!out_buf || out_len == 0) return;
    const int64_t safe = value < 0 ? 0 : value;
    if (safe < 1000LL) {
        std::snprintf(out_buf, out_len, "%lld", static_cast<long long>(safe));
        return;
    }
    auto format_unit = [out_buf, out_len](double divisor, char suffix) {
        const long long tenths = static_cast<long long>(std::floor(divisor));
        const long long whole = tenths / 10LL;
        const long long frac = tenths % 10LL;
        if (frac == 0LL) {
            std::snprintf(out_buf, out_len, "%lld%c", whole, suffix);
        } else {
            std::snprintf(out_buf, out_len, "%lld.%lld%c", whole, frac, suffix);
        }
    };
    if (safe < 1000000LL) {
        format_unit(static_cast<double>(safe) / 100.0, 'K');
    } else if (safe < 1000000000LL) {
        format_unit(static_cast<double>(safe) / 100000.0, 'M');
    } else {
        format_unit(static_cast<double>(safe) / 100000000.0, 'B');
    }
}

} // extern "C"
