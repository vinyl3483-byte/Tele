package security

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"io"
	"net"
	"net/http"
	"strings"
)

func HMACSHA256Hex(secret []byte, data string) string {
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte(data))
	return hex.EncodeToString(mac.Sum(nil))
}

func HashEmail(secret []byte, email string) string {
	return HMACSHA256Hex(secret, email)
}

func ConstantTimeHexEqual(a, b string) bool {
	if len(a) != len(b) {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(a), []byte(b)) == 1
}

func EncryptAtRest(key [32]byte, plaintext []byte, aad string) ([]byte, error) {
	block, err := aes.NewCipher(key[:])
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return nil, err
	}
	sealed := gcm.Seal(nonce, nonce, plaintext, []byte(aad))
	return sealed, nil
}

func DecryptAtRest(key [32]byte, ciphertext []byte, aad string) ([]byte, error) {
	block, err := aes.NewCipher(key[:])
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	if len(ciphertext) < gcm.NonceSize() {
		return nil, errors.New("invalid ciphertext")
	}
	nonce := ciphertext[:gcm.NonceSize()]
	payload := ciphertext[gcm.NonceSize():]
	return gcm.Open(nil, nonce, payload, []byte(aad))
}

func ExtractClientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		parts := strings.Split(xff, ",")
		if ip := strings.TrimSpace(parts[0]); net.ParseIP(ip) != nil {
			return ip
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil && net.ParseIP(host) != nil {
		return host
	}
	if net.ParseIP(r.RemoteAddr) != nil {
		return r.RemoteAddr
	}
	return "0.0.0.0"
}

func ComputeIPFingerprint(pepper []byte, rawIP string) string {
	parsed := net.ParseIP(rawIP)
	subnet := "unknown"
	if parsed != nil {
		if v4 := parsed.To4(); v4 != nil {
			subnet = v4.Mask(net.CIDRMask(24, 32)).String()
		} else {
			subnet = parsed.Mask(net.CIDRMask(48, 128)).String()
		}
	}
	return HMACSHA256Hex(pepper, rawIP+"|"+subnet)
}

func CanonicalizeDeviceFingerprint(pepper []byte, clientFP, hardwareAttestation, platform string) string {
	return HMACSHA256Hex(pepper, strings.ToLower(platform)+"|"+clientFP+"|"+hardwareAttestation)
}
