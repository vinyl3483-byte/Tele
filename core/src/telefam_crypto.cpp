#include "telefam_crypto.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <cstring>
#include <random>

namespace telefam::crypto {

void secure_zero(void* ptr, std::size_t len) {
    if (!ptr || len == 0) return;
    volatile uint8_t* p = static_cast<volatile uint8_t*>(ptr);
    while (len--) {
        *p++ = 0;
    }
}

bool constant_time_eq(const uint8_t* a, const uint8_t* b, std::size_t len) {
    if (!a || !b) return false;
    uint8_t diff = 0;
    for (std::size_t i = 0; i < len; ++i) {
        diff |= static_cast<uint8_t>(a[i] ^ b[i]);
    }
    return diff == 0;
}

namespace {

constexpr std::array<uint32_t, 64> K256 = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
    0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
    0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu, 0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
    0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u, 0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
    0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u, 0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
    0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u, 0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u
};

inline uint32_t rotr(uint32_t x, uint32_t n) {
    return (x >> n) | (x << (32 - n));
}

// Standard FIPS-197 AES S-Box & Rcon for AES-256
constexpr std::array<uint8_t, 256> AES_SBOX = {
    0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
    0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
    0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
    0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
    0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
    0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
    0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
    0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
    0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
    0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
    0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
    0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
    0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
    0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
    0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
    0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16
};

constexpr std::array<uint8_t, 11> AES_RCON = {
    0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36
};

inline uint8_t xtime(uint8_t x) {
    return static_cast<uint8_t>((x << 1) ^ (((x >> 7) & 1) * 0x1b));
}

void aes256_key_expansion(const uint8_t key[32], uint8_t round_keys[240]) {
    std::memcpy(round_keys, key, 32);
    int bytes_generated = 32;
    int rcon_iter = 1;
    uint8_t temp[4]{};
    while (bytes_generated < 240) {
        for (int i = 0; i < 4; ++i) {
            temp[i] = round_keys[bytes_generated - 4 + i];
        }
        if (bytes_generated % 32 == 0) {
            uint8_t t = temp[0];
            temp[0] = AES_SBOX[temp[1]] ^ AES_RCON[rcon_iter++];
            temp[1] = AES_SBOX[temp[2]];
            temp[2] = AES_SBOX[temp[3]];
            temp[3] = AES_SBOX[t];
        } else if (bytes_generated % 32 == 16) {
            for (int i = 0; i < 4; ++i) temp[i] = AES_SBOX[temp[i]];
        }
        for (int i = 0; i < 4; ++i) {
            round_keys[bytes_generated] = round_keys[bytes_generated - 32] ^ temp[i];
            ++bytes_generated;
        }
    }
    secure_zero(temp, sizeof(temp));
}

void aes256_encrypt_block(const uint8_t round_keys[240], const uint8_t in[16], uint8_t out[16]) {
    uint8_t state[16];
    for (int i = 0; i < 16; ++i) state[i] = in[i] ^ round_keys[i];

    for (int round = 1; round <= 14; ++round) {
        for (int i = 0; i < 16; ++i) state[i] = AES_SBOX[state[i]];

        // ShiftRows (column-major state)
        uint8_t t = state[1]; state[1] = state[5]; state[5] = state[9]; state[9] = state[13]; state[13] = t;
        t = state[2]; uint8_t t2 = state[6]; state[2] = state[10]; state[6] = state[14]; state[10] = t; state[14] = t2;
        t = state[15]; state[15] = state[11]; state[11] = state[7]; state[7] = state[3]; state[3] = t;

        if (round < 14) {
            for (int col = 0; col < 4; ++col) {
                int idx = col * 4;
                uint8_t a = state[idx], b = state[idx + 1], c = state[idx + 2], d = state[idx + 3];
                uint8_t xo = a ^ b ^ c ^ d;
                state[idx]     ^= xo ^ xtime(a ^ b);
                state[idx + 1] ^= xo ^ xtime(b ^ c);
                state[idx + 2] ^= xo ^ xtime(c ^ d);
                state[idx + 3] ^= xo ^ xtime(d ^ a);
            }
        }

        const uint8_t* rk = round_keys + round * 16;
        for (int i = 0; i < 16; ++i) state[i] ^= rk[i];
    }
    std::memcpy(out, state, 16);
    secure_zero(state, sizeof(state));
}

void aes256_ctr_xor(const uint8_t key[32], const uint8_t nonce16[16], const uint8_t* in, uint8_t* out, std::size_t len) {
    uint8_t round_keys[240];
    aes256_key_expansion(key, round_keys);
    uint8_t counter[16];
    std::memcpy(counter, nonce16, 16);
    uint8_t keystream[16];

    std::size_t offset = 0;
    while (offset < len) {
        aes256_encrypt_block(round_keys, counter, keystream);
        std::size_t chunk = std::min<std::size_t>(16, len - offset);
        for (std::size_t i = 0; i < chunk; ++i) {
            out[offset + i] = in[offset + i] ^ keystream[i];
        }
        offset += chunk;
        for (int i = 15; i >= 0; --i) {
            if (++counter[i] != 0) break;
        }
    }
    secure_zero(round_keys, sizeof(round_keys));
    secure_zero(counter, sizeof(counter));
    secure_zero(keystream, sizeof(keystream));
}

} // namespace

std::vector<uint8_t> sha256(const uint8_t* data, std::size_t len) {
    std::array<uint32_t, 8> h = {
        0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
        0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u
    };

    std::vector<uint8_t> msg(data, data + len);
    uint64_t bit_len = static_cast<uint64_t>(len) * 8ULL;
    msg.push_back(0x80);
    while ((msg.size() % 64) != 56) {
        msg.push_back(0x00);
    }
    for (int i = 7; i >= 0; --i) {
        msg.push_back(static_cast<uint8_t>((bit_len >> (i * 8)) & 0xff));
    }

    uint32_t w[64];
    for (std::size_t chunk = 0; chunk < msg.size(); chunk += 64) {
        for (int i = 0; i < 16; ++i) {
            w[i] = (static_cast<uint32_t>(msg[chunk + i * 4]) << 24) |
                   (static_cast<uint32_t>(msg[chunk + i * 4 + 1]) << 16) |
                   (static_cast<uint32_t>(msg[chunk + i * 4 + 2]) << 8) |
                   (static_cast<uint32_t>(msg[chunk + i * 4 + 3]));
        }
        for (int i = 16; i < 64; ++i) {
            uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
            uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16] + s0 + w[i - 7] + s1;
        }
        uint32_t a = h[0], b = h[1], c = h[2], d = h[3];
        uint32_t e = h[4], f = h[5], g = h[6], hh = h[7];
        for (int i = 0; i < 64; ++i) {
            uint32_t S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
            uint32_t ch = (e & f) ^ ((~e) & g);
            uint32_t temp1 = hh + S1 + ch + K256[i] + w[i];
            uint32_t S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
            uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
            uint32_t temp2 = S0 + maj;
            hh = g; g = f; f = e; e = d + temp1;
            d = c; c = b; b = a; a = temp1 + temp2;
        }
        h[0] += a; h[1] += b; h[2] += c; h[3] += d;
        h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
    }

    std::vector<uint8_t> out(32);
    for (int i = 0; i < 8; ++i) {
        out[i * 4]     = static_cast<uint8_t>((h[i] >> 24) & 0xff);
        out[i * 4 + 1] = static_cast<uint8_t>((h[i] >> 16) & 0xff);
        out[i * 4 + 2] = static_cast<uint8_t>((h[i] >> 8) & 0xff);
        out[i * 4 + 3] = static_cast<uint8_t>(h[i] & 0xff);
    }
    secure_zero(w, sizeof(w));
    return out;
}

std::string to_hex(const uint8_t* data, std::size_t len) {
    static constexpr char HEX[] = "0123456789abcdef";
    std::string out;
    out.reserve(len * 2);
    for (std::size_t i = 0; i < len; ++i) {
        out.push_back(HEX[(data[i] >> 4) & 0x0f]);
        out.push_back(HEX[data[i] & 0x0f]);
    }
    return out;
}

std::string sha256_hex(const std::string& input) {
    auto d = sha256(reinterpret_cast<const uint8_t*>(input.data()), input.size());
    return to_hex(d.data(), d.size());
}

std::vector<uint8_t> hmac_sha256(
    const uint8_t* key, std::size_t key_len,
    const uint8_t* data, std::size_t data_len
) {
    uint8_t k0[64]{};
    if (key_len > 64) {
        auto hashed = sha256(key, key_len);
        std::memcpy(k0, hashed.data(), 32);
    } else if (key_len > 0) {
        std::memcpy(k0, key, key_len);
    }

    std::vector<uint8_t> inner(64 + data_len);
    std::vector<uint8_t> outer(64 + 32);
    for (int i = 0; i < 64; ++i) {
        inner[i] = static_cast<uint8_t>(k0[i] ^ 0x36);
        outer[i] = static_cast<uint8_t>(k0[i] ^ 0x5c);
    }
    if (data_len > 0) {
        std::memcpy(inner.data() + 64, data, data_len);
    }
    auto ih = sha256(inner.data(), inner.size());
    std::memcpy(outer.data() + 64, ih.data(), 32);
    auto mac = sha256(outer.data(), outer.size());

    secure_zero(k0, sizeof(k0));
    secure_zero(inner.data(), inner.size());
    secure_zero(outer.data(), outer.size());
    return mac;
}

std::vector<uint8_t> hkdf_sha256(
    const uint8_t* ikm, std::size_t ikm_len,
    const uint8_t* salt, std::size_t salt_len,
    const uint8_t* info, std::size_t info_len,
    std::size_t out_len
) {
    uint8_t zero_salt[32]{};
    const uint8_t* actual_salt = (salt && salt_len > 0) ? salt : zero_salt;
    std::size_t actual_salt_len = (salt && salt_len > 0) ? salt_len : 32;

    auto prk = hmac_sha256(actual_salt, actual_salt_len, ikm, ikm_len);
    std::vector<uint8_t> okm;
    okm.reserve(out_len);
    std::vector<uint8_t> t;
    uint8_t counter = 1;
    while (okm.size() < out_len) {
        std::vector<uint8_t> msg;
        msg.reserve(t.size() + info_len + 1);
        msg.insert(msg.end(), t.begin(), t.end());
        if (info && info_len > 0) {
            msg.insert(msg.end(), info, info + info_len);
        }
        msg.push_back(counter++);
        t = hmac_sha256(prk.data(), prk.size(), msg.data(), msg.size());
        std::size_t need = std::min(t.size(), out_len - okm.size());
        okm.insert(okm.end(), t.begin(), t.begin() + need);
    }
    secure_zero(prk.data(), prk.size());
    return okm;
}

bool random_bytes(uint8_t* out, std::size_t len) {
    if (!out || len == 0) return false;
    std::random_device rd;
    for (std::size_t i = 0; i < len; i += 4) {
        uint32_t r = rd() ^ static_cast<uint32_t>(
            std::chrono::high_resolution_clock::now().time_since_epoch().count()
        );
        std::size_t copy = std::min<std::size_t>(4, len - i);
        std::memcpy(out + i, &r, copy);
    }
    return true;
}

bool aead_encrypt(
    const uint8_t key_32[32],
    const uint8_t* plaintext, std::size_t plaintext_len,
    const uint8_t* aad, std::size_t aad_len,
    std::vector<uint8_t>& out_blob
) {
    if (!key_32) return false;
    static const char* INFO_ENC = "telefam-aead-enc-v1";
    static const char* INFO_MAC = "telefam-aead-mac-v1";
    auto enc_key = hkdf_sha256(key_32, 32, nullptr, 0,
        reinterpret_cast<const uint8_t*>(INFO_ENC), std::strlen(INFO_ENC), 32);
    auto mac_key = hkdf_sha256(key_32, 32, nullptr, 0,
        reinterpret_cast<const uint8_t*>(INFO_MAC), std::strlen(INFO_MAC), 32);

    uint8_t nonce[16];
    if (!random_bytes(nonce, 16)) return false;

    out_blob.resize(16 + plaintext_len + 32);
    std::memcpy(out_blob.data(), nonce, 16);
    if (plaintext_len > 0 && plaintext) {
        aes256_ctr_xor(enc_key.data(), nonce, plaintext, out_blob.data() + 16, plaintext_len);
    }

    std::vector<uint8_t> mac_input;
    mac_input.reserve(aad_len + 16 + plaintext_len);
    if (aad && aad_len > 0) mac_input.insert(mac_input.end(), aad, aad + aad_len);
    mac_input.insert(mac_input.end(), out_blob.begin(), out_blob.begin() + 16 + plaintext_len);

    auto tag = hmac_sha256(mac_key.data(), mac_key.size(), mac_input.data(), mac_input.size());
    std::memcpy(out_blob.data() + 16 + plaintext_len, tag.data(), 32);

    secure_zero(enc_key.data(), enc_key.size());
    secure_zero(mac_key.data(), mac_key.size());
    return true;
}

bool aead_decrypt(
    const uint8_t key_32[32],
    const uint8_t* blob, std::size_t blob_len,
    const uint8_t* aad, std::size_t aad_len,
    std::vector<uint8_t>& out_plaintext
) {
    if (!key_32 || !blob || blob_len < 48) return false;
    static const char* INFO_ENC = "telefam-aead-enc-v1";
    static const char* INFO_MAC = "telefam-aead-mac-v1";
    auto enc_key = hkdf_sha256(key_32, 32, nullptr, 0,
        reinterpret_cast<const uint8_t*>(INFO_ENC), std::strlen(INFO_ENC), 32);
    auto mac_key = hkdf_sha256(key_32, 32, nullptr, 0,
        reinterpret_cast<const uint8_t*>(INFO_MAC), std::strlen(INFO_MAC), 32);

    std::size_t ct_len = blob_len - 48;
    std::vector<uint8_t> mac_input;
    mac_input.reserve(aad_len + 16 + ct_len);
    if (aad && aad_len > 0) mac_input.insert(mac_input.end(), aad, aad + aad_len);
    mac_input.insert(mac_input.end(), blob, blob + 16 + ct_len);

    auto expected_tag = hmac_sha256(mac_key.data(), mac_key.size(), mac_input.data(), mac_input.size());
    const uint8_t* actual_tag = blob + 16 + ct_len;

    bool valid = constant_time_eq(expected_tag.data(), actual_tag, 32);
    if (valid) {
        out_plaintext.resize(ct_len);
        if (ct_len > 0) {
            aes256_ctr_xor(enc_key.data(), blob, blob + 16, out_plaintext.data(), ct_len);
        }
    }

    secure_zero(enc_key.data(), enc_key.size());
    secure_zero(mac_key.data(), mac_key.size());
    return valid;
}

} // namespace telefam::crypto
