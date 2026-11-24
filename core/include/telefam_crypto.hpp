#ifndef TELEFAM_CRYPTO_HPP
#define TELEFAM_CRYPTO_HPP

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace telefam::crypto {

void secure_zero(void* ptr, std::size_t len);
bool constant_time_eq(const uint8_t* a, const uint8_t* b, std::size_t len);

std::vector<uint8_t> sha256(const uint8_t* data, std::size_t len);
std::string sha256_hex(const std::string& input);

std::vector<uint8_t> hmac_sha256(
    const uint8_t* key, std::size_t key_len,
    const uint8_t* data, std::size_t data_len
);

std::vector<uint8_t> hkdf_sha256(
    const uint8_t* ikm, std::size_t ikm_len,
    const uint8_t* salt, std::size_t salt_len,
    const uint8_t* info, std::size_t info_len,
    std::size_t out_len
);

// Encrypt-then-MAC AEAD: 16-byte nonce || AES-256-CTR ciphertext || 32-byte HMAC-SHA256 tag
bool aead_encrypt(
    const uint8_t key_32[32],
    const uint8_t* plaintext, std::size_t plaintext_len,
    const uint8_t* aad, std::size_t aad_len,
    std::vector<uint8_t>& out_blob
);

bool aead_decrypt(
    const uint8_t key_32[32],
    const uint8_t* blob, std::size_t blob_len,
    const uint8_t* aad, std::size_t aad_len,
    std::vector<uint8_t>& out_plaintext
);

bool random_bytes(uint8_t* out, std::size_t len);
std::string to_hex(const uint8_t* data, std::size_t len);

} // namespace telefam::crypto

#endif // TELEFAM_CRYPTO_HPP
