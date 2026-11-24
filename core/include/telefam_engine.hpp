#ifndef TELEFAM_ENGINE_HPP
#define TELEFAM_ENGINE_HPP

#include "telefam_core.h"

#include <cstdint>
#include <deque>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace telefam {

struct CooldownEntry {
    int32_t resend_count = 0;
    int64_t blocked_until = 0;
    int64_t last_sent_at = 0;
};

struct OutboxItem {
    std::string mutation_id;
    std::string action_type;
    std::string payload_json;
    int64_t created_at_ms = 0;
};

class Engine {
public:
    Engine(std::string vault_path, const uint8_t master_key[32]);
    ~Engine();

    telefam_status_t check_cooldown(const std::string& email, int64_t now_sec, telefam_cooldown_state_t& out);
    telefam_status_t record_otp_send(const std::string& email, int64_t now_sec, telefam_cooldown_state_t& out);
    telefam_status_t reset_cooldown(const std::string& email);

    bool allow_rate_limit(const std::string& account_key, const std::string& device_fp, const std::string& ip_fp, int64_t now_sec);
    bool allow_follow_rate_limit(const std::string& account_key, int64_t now_sec);

    telefam_status_t vault_put(const std::string& key, const std::vector<uint8_t>& value);
    telefam_status_t vault_get(const std::string& key, std::vector<uint8_t>& out_value);
    telefam_status_t vault_delete(const std::string& key);

    telefam_status_t outbox_enqueue(const std::string& id, const std::string& action, const std::string& payload, int64_t now_ms);
    std::string outbox_peek_json(int32_t max_items);
    telefam_status_t outbox_ack(const std::string& id);
    int32_t outbox_count();

private:
    void load_encrypted_state();
    bool persist_encrypted_state();
    static int64_t cooldown_duration_for_count(int32_t resend_count_1_based, int32_t& out_tier);
    bool check_bucket(const std::string& bucket_key, int64_t now_sec, int32_t max_requests, int64_t window_sec);

    std::string vault_path_;
    uint8_t master_key_[32]{};
    std::mutex mu_;

    std::unordered_map<std::string, std::vector<uint8_t>> kv_store_;
    std::unordered_map<std::string, CooldownEntry> cooldowns_;
    std::vector<OutboxItem> outbox_;
    std::unordered_map<std::string, std::deque<int64_t>> rate_buckets_;
};

} // namespace telefam

#endif // TELEFAM_ENGINE_HPP
