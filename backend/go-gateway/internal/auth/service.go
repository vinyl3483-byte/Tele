package auth

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"net/smtp"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/telefam/company/backend/go-gateway/internal/config"
	"github.com/telefam/company/backend/go-gateway/internal/db"
	"github.com/telefam/company/backend/go-gateway/internal/ratelimit"
	"github.com/telefam/company/backend/go-gateway/internal/security"
)

type Service struct {
	cfg       *config.Config
	pool      *pgxpool.Pool
	limiter   *ratelimit.Limiter
	jwksMu    sync.RWMutex
	appleKeys map[string]*rsa.PublicKey
	appleExp  time.Time
}

func NewService(cfg *config.Config, pool *pgxpool.Pool, limiter *ratelimit.Limiter) *Service {
	return &Service{
		cfg:       cfg,
		pool:      pool,
		limiter:   limiter,
		appleKeys: make(map[string]*rsa.PublicKey),
	}
}

type SendOTPResult struct {
	Accepted        bool  `json:"accepted"`
	CooldownSeconds int64 `json:"cooldown_seconds"`
}

type AuthSessionResult struct {
	AccessToken      string `json:"access_token"`
	RefreshToken     string `json:"refresh_token"`
	ExpiresIn        int64  `json:"expires_in"`
	UserID           string `json:"user_id"`
	Email            string `json:"email"`
	DisplayName      string `json:"display_name"`
	ProfileCompleted bool   `json:"profile_completed"`
}

func normalizeEmail(email string) (string, error) {
	e := strings.ToLower(strings.TrimSpace(email))
	if len(e) < 5 || len(e) > 254 || !strings.Contains(e, "@") || !strings.Contains(e, ".") {
		return "", errors.New("invalid email")
	}
	return e, nil
}

func generateNumericOTP() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1000000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}

func generateRandomTokenHex(byteLen int) (string, error) {
	b := make([]byte, byteLen)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func (s *Service) SendOTP(ctx context.Context, rawEmail, deviceFP, ipFP, hwAttest, deviceName, platform string) (*SendOTPResult, int, error) {
	email, err := normalizeEmail(rawEmail)
	if err != nil {
		return nil, http.StatusBadRequest, err
	}
	emailHash := security.HMACSHA256Hex(s.cfg.HMACPepper, email)
	devHash := security.CanonicalizeDeviceFingerprint(s.cfg.HMACPepper, deviceFP, hwAttest, platform)

	if !s.limiter.AllowMulti(ctx, emailHash, devHash, ipFP) {
		return nil, http.StatusTooManyRequests, errors.New("rate limit exceeded")
	}

	now := time.Now().UTC()
	var cooldownSec int64
	var otpCode string
	var magicToken string

	err = db.WithAuthWorkerRLS(ctx, s.pool, func(tx pgx.Tx) error {
		var prevResend int
		var cooldownUntil time.Time
		var createdAt time.Time
		qErr := tx.QueryRow(ctx, `
			SELECT resend_count, cooldown_until, created_at
			FROM otp_challenges
			WHERE email_hash = $1 AND device_fp_hash = $2
			ORDER BY created_at DESC LIMIT 1
		`, emailHash, devHash).Scan(&prevResend, &cooldownUntil, &createdAt)

		nextCount := 1
		if qErr == nil {
			if cooldownUntil.After(now) {
				cooldownSec = int64(cooldownUntil.Sub(now).Seconds())
				return errors.New("cooldown active")
			}
			if now.Sub(createdAt) <= 24*time.Hour {
				nextCount = prevResend + 1
			}
		}

		dur := ratelimit.CooldownDuration(nextCount)
		cooldownSec = int64(dur.Seconds())

		var genErr error
		otpCode, genErr = generateNumericOTP()
		if genErr != nil {
			return genErr
		}
		magicToken, genErr = generateRandomTokenHex(24)
		if genErr != nil {
			return genErr
		}

		otpHMAC := security.HMACSHA256Hex(s.cfg.HMACPepper, emailHash+"|"+otpCode)
		magicHMAC := security.HMACSHA256Hex(s.cfg.HMACPepper, magicToken)

		_, insErr := tx.Exec(ctx, `
			INSERT INTO otp_challenges (
				email_hash, device_fp_hash, ip_fp_hash,
				otp_hmac, magic_token_hmac, resend_count,
				cooldown_until, expires_at
			) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
		`, emailHash, devHash, ipFP, otpHMAC, magicHMAC, nextCount, now.Add(dur), now.Add(10*time.Minute))
		return insErr
	})

	if err != nil {
		if err.Error() == "cooldown active" {
			return &SendOTPResult{Accepted: false, CooldownSeconds: cooldownSec}, http.StatusTooManyRequests, err
		}
		return nil, http.StatusInternalServerError, err
	}

	if err := s.dispatchOTPEmail(email, otpCode, magicToken); err != nil {
		return nil, http.StatusBadGateway, err
	}

	return &SendOTPResult{
		Accepted:        true,
		CooldownSeconds: cooldownSec,
	}, http.StatusOK, nil
}

func (s *Service) VerifyOTPOrMagicLink(ctx context.Context, rawEmail, otp, magicToken, deviceFP, ipFP, hwAttest, deviceName, platform string) (*AuthSessionResult, int, error) {
	devHash := security.CanonicalizeDeviceFingerprint(s.cfg.HMACPepper, deviceFP, hwAttest, platform)
	if !s.limiter.AllowMulti(ctx, rawEmail, devHash, ipFP) {
		return nil, http.StatusTooManyRequests, errors.New("rate limit exceeded")
	}

	email, err := normalizeEmail(rawEmail)
	if err != nil && strings.TrimSpace(magicToken) == "" {
		return nil, http.StatusBadRequest, errors.New("invalid input")
	}
	var emailHash string
	if err == nil {
		emailHash = security.HMACSHA256Hex(s.cfg.HMACPepper, email)
	}

	var verifiedEmailHash string
	var resolvedEmail = email
	err = db.WithAuthWorkerRLS(ctx, s.pool, func(tx pgx.Tx) error {
		var challengeID uuid.UUID
		var cEmailHash, otpHMAC, magicHMAC string
		var attempts int
		var expiresAt time.Time

		var qErr error
		if strings.TrimSpace(magicToken) != "" {
			magicCandidate := security.HMACSHA256Hex(s.cfg.HMACPepper, strings.TrimSpace(magicToken))
			qErr = tx.QueryRow(ctx, `
				SELECT id, email_hash, otp_hmac, magic_token_hmac, attempt_count, expires_at
				FROM otp_challenges
				WHERE magic_token_hmac = $1 AND consumed_at IS NULL
				ORDER BY created_at DESC LIMIT 1
			`, magicCandidate).Scan(&challengeID, &cEmailHash, &otpHMAC, &magicHMAC, &attempts, &expiresAt)
		} else {
			qErr = tx.QueryRow(ctx, `
				SELECT id, email_hash, otp_hmac, magic_token_hmac, attempt_count, expires_at
				FROM otp_challenges
				WHERE email_hash = $1 AND consumed_at IS NULL
				ORDER BY created_at DESC LIMIT 1
			`, emailHash).Scan(&challengeID, &cEmailHash, &otpHMAC, &magicHMAC, &attempts, &expiresAt)
		}
		if qErr != nil {
			return errors.New("challenge not found")
		}
		if time.Now().UTC().After(expiresAt) || attempts >= 5 {
			return errors.New("challenge expired")
		}

		if strings.TrimSpace(magicToken) != "" {
			magicCandidate := security.HMACSHA256Hex(s.cfg.HMACPepper, strings.TrimSpace(magicToken))
			if !security.ConstantTimeHexEqual(magicCandidate, magicHMAC) {
				_, _ = tx.Exec(ctx, `UPDATE otp_challenges SET attempt_count = attempt_count + 1 WHERE id = $1`, challengeID)
				return errors.New("invalid magic token")
			}
			if resolvedEmail == "" {
				var encEmail []byte
				if eErr := tx.QueryRow(ctx, `SELECT email_encrypted FROM users WHERE email_hash = $1`, cEmailHash).Scan(&encEmail); eErr == nil {
					if dec, dErr := security.DecryptAtRest(s.cfg.MasterKey, encEmail, "users.email"); dErr == nil {
						resolvedEmail = string(dec)
					}
				}
			}
		} else {
			otpCandidate := security.HMACSHA256Hex(s.cfg.HMACPepper, cEmailHash+"|"+strings.TrimSpace(otp))
			if !security.ConstantTimeHexEqual(otpCandidate, otpHMAC) {
				_, _ = tx.Exec(ctx, `UPDATE otp_challenges SET attempt_count = attempt_count + 1 WHERE id = $1`, challengeID)
				return errors.New("invalid otp")
			}
		}

		if resolvedEmail == "" {
			return errors.New("email verification required")
		}

		_, updErr := tx.Exec(ctx, `UPDATE otp_challenges SET consumed_at = NOW() WHERE id = $1`, challengeID)
		verifiedEmailHash = cEmailHash
		return updErr
	})
	if err != nil {
		return nil, http.StatusUnauthorized, err
	}

	return s.issueSessionForUser(ctx, verifiedEmailHash, resolvedEmail, "email_otp", "", "", devHash, ipFP, hwAttest, deviceName, platform)
}

func (s *Service) VerifyOAuth(ctx context.Context, provider, idToken, deviceFP, ipFP, hwAttest, deviceName, platform string) (*AuthSessionResult, int, error) {
	devHash := security.CanonicalizeDeviceFingerprint(s.cfg.HMACPepper, deviceFP, hwAttest, platform)
	if !s.limiter.AllowMulti(ctx, provider, devHash, ipFP) {
		return nil, http.StatusTooManyRequests, errors.New("rate limit exceeded")
	}

	var email, sub string
	var err error
	var googleSubHash, appleSubHash string
	switch strings.ToLower(strings.TrimSpace(provider)) {
	case "google":
		email, sub, err = s.verifyGoogleToken(ctx, idToken)
		if err == nil {
			googleSubHash = security.HMACSHA256Hex(s.cfg.HMACPepper, "google:"+sub)
		}
	case "apple":
		email, sub, err = s.verifyAppleToken(ctx, idToken)
		if err == nil {
			appleSubHash = security.HMACSHA256Hex(s.cfg.HMACPepper, "apple:"+sub)
		}
	default:
		return nil, http.StatusBadRequest, errors.New("unsupported provider")
	}
	if err != nil {
		return nil, http.StatusUnauthorized, err
	}

	emailHash := security.HMACSHA256Hex(s.cfg.HMACPepper, email)
	return s.issueSessionForUser(ctx, emailHash, email, provider, googleSubHash, appleSubHash, devHash, ipFP, hwAttest, deviceName, platform)
}

func (s *Service) issueSessionForUser(
	ctx context.Context,
	emailHash, plainEmail, provider, googleSubHash, appleSubHash, devHash, ipFP, hwAttest, deviceName, platform string,
) (*AuthSessionResult, int, error) {
	var userID uuid.UUID
	var displayName string
	var profileCompleted bool
	var suspended bool
	sessionID := uuid.New()
	refreshToken, err := generateRandomTokenHex(32)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	refreshHMAC := security.HMACSHA256Hex(s.cfg.HMACPepper, refreshToken)

	defaultName := strings.Split(plainEmail, "@")[0]
	encEmail, err := security.EncryptAtRest(s.cfg.MasterKey, []byte(plainEmail), "users.email")
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	encName, err := security.EncryptAtRest(s.cfg.MasterKey, []byte(defaultName), "users.display_name")
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	encDeviceName, err := security.EncryptAtRest(s.cfg.MasterKey, []byte(deviceName), "devices.name")
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}

	err = db.WithAuthWorkerRLS(ctx, s.pool, func(tx pgx.Tx) error {
		var existingEncName []byte
		qErr := tx.QueryRow(ctx, `
			SELECT id, display_name_encrypted, profile_completed, is_suspended
			FROM users WHERE email_hash = $1
		`, emailHash).Scan(&userID, &existingEncName, &profileCompleted, &suspended)
		if qErr == pgx.ErrNoRows {
			qErr = tx.QueryRow(ctx, `
				INSERT INTO users (email_hash, email_encrypted, display_name_encrypted, auth_provider, google_sub_hash, apple_sub_hash, profile_completed)
				VALUES ($1,$2,$3,$4,NULLIF($5,''),NULLIF($6,''), FALSE)
				RETURNING id
			`, emailHash, encEmail, encName, provider, googleSubHash, appleSubHash).Scan(&userID)
			displayName = defaultName
			profileCompleted = false
		} else if qErr == nil {
			if suspended {
				return errors.New("account suspended")
			}
			if pt, dErr := security.DecryptAtRest(s.cfg.MasterKey, existingEncName, "users.display_name"); dErr == nil {
				displayName = string(pt)
			} else {
				displayName = defaultName
			}
		}
		if qErr != nil {
			return qErr
		}

		var deviceID uuid.UUID
		err := tx.QueryRow(ctx, `
			INSERT INTO devices (user_id, device_fp_hash, ip_fp_hash, hardware_attestation_hash, device_name_encrypted, platform)
			VALUES ($1,$2,$3,$4,$5,$6)
			ON CONFLICT (user_id, device_fp_hash) DO UPDATE SET
				ip_fp_hash = EXCLUDED.ip_fp_hash,
				hardware_attestation_hash = EXCLUDED.hardware_attestation_hash,
				device_name_encrypted = EXCLUDED.device_name_encrypted,
				last_seen_at = NOW(),
				revoked_at = NULL
			RETURNING id
		`, userID, devHash, ipFP, hwAttest, encDeviceName, platform).Scan(&deviceID)
		if err != nil {
			return err
		}

		_, err = tx.Exec(ctx, `
			INSERT INTO sessions (id, user_id, device_id, refresh_token_hmac, ip_fp_hash, expires_at)
			VALUES ($1,$2,$3,$4,$5,$6)
		`, sessionID, userID, deviceID, refreshHMAC, ipFP, time.Now().UTC().Add(30*24*time.Hour))
		return err
	})
	if err != nil {
		if err.Error() == "account suspended" {
			return nil, http.StatusForbidden, err
		}
		return nil, http.StatusInternalServerError, err
	}

	expiresIn := int64(900) // 15 minutes short-lived access JWT
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"jti": sessionID.String(),
		"sub": userID.String(),
		"dev": devHash,
		"ipf": ipFP,
		"iat": time.Now().UTC().Unix(),
		"exp": time.Now().UTC().Add(time.Duration(expiresIn) * time.Second).Unix(),
	})
	accessToken, err := tok.SignedString(s.cfg.JWTSecret)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}

	return &AuthSessionResult{
		AccessToken:      accessToken,
		RefreshToken:     refreshToken,
		ExpiresIn:        expiresIn,
		UserID:           userID.String(),
		Email:            plainEmail,
		DisplayName:      displayName,
		ProfileCompleted: profileCompleted,
	}, http.StatusOK, nil
}

func (s *Service) ParseAndValidateAccessToken(ctx context.Context, tokenString string) (uuid.UUID, uuid.UUID, string, error) {
	parsed, err := jwt.Parse(tokenString, func(t *jwt.Token) (any, error) {
		if t.Method.Alg() != jwt.SigningMethodHS256.Alg() {
			return nil, errors.New("unexpected signing method")
		}
		return s.cfg.JWTSecret, nil
	}, jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}), jwt.WithExpirationRequired())
	if err != nil || !parsed.Valid {
		return uuid.Nil, uuid.Nil, "", errors.New("invalid token")
	}
	claims, ok := parsed.Claims.(jwt.MapClaims)
	if !ok {
		return uuid.Nil, uuid.Nil, "", errors.New("invalid claims")
	}
	subStr, _ := claims["sub"].(string)
	jtiStr, _ := claims["jti"].(string)
	devFP, _ := claims["dev"].(string)
	uid, err := uuid.Parse(subStr)
	if err != nil {
		return uuid.Nil, uuid.Nil, "", errors.New("invalid subject")
	}
	sid, err := uuid.Parse(jtiStr)
	if err != nil {
		return uuid.Nil, uuid.Nil, "", errors.New("invalid session id")
	}

	var active bool
	err = db.WithAuthWorkerRLS(ctx, s.pool, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT EXISTS(
				SELECT 1
				FROM sessions s
				JOIN devices d ON d.id = s.device_id
				JOIN users u ON u.id = s.user_id
				WHERE s.id = $1
				  AND s.user_id = $2
				  AND s.revoked_at IS NULL
				  AND s.expires_at > NOW()
				  AND d.revoked_at IS NULL
				  AND u.is_suspended = FALSE
			)
		`, sid, uid).Scan(&active)
	})
	if err != nil || !active {
		return uuid.Nil, uuid.Nil, "", errors.New("session revoked or suspended")
	}
	return uid, sid, devFP, nil
}

func (s *Service) RefreshSession(ctx context.Context, refreshToken, deviceFP, hwAttest, platform, ipFP string) (*AuthSessionResult, int, error) {
	rt := strings.TrimSpace(refreshToken)
	if len(rt) < 32 {
		return nil, http.StatusUnauthorized, errors.New("invalid refresh token")
	}
	rtHMAC := security.HMACSHA256Hex(s.cfg.HMACPepper, rt)
	devHash := security.CanonicalizeDeviceFingerprint(s.cfg.HMACPepper, deviceFP, hwAttest, platform)

	newRefresh, err := generateRandomTokenHex(32)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	newRefreshHMAC := security.HMACSHA256Hex(s.cfg.HMACPepper, newRefresh)
	newSessionID := uuid.New()

	var userID uuid.UUID
	var plainEmail, displayName string
	var profileCompleted bool

	err = db.WithAuthWorkerRLS(ctx, s.pool, func(tx pgx.Tx) error {
		var oldSessID, devID uuid.UUID
		var encEmail, encName []byte
		var suspended bool
		var storedDevFP string
		err := tx.QueryRow(ctx, `
			SELECT s.id, s.user_id, s.device_id, d.device_fp_hash, u.email_encrypted, u.display_name_encrypted, u.profile_completed, u.is_suspended
			FROM sessions s
			JOIN devices d ON d.id = s.device_id
			JOIN users u ON u.id = s.user_id
			WHERE s.refresh_token_hmac = $1
			  AND s.revoked_at IS NULL
			  AND s.expires_at > NOW()
			  AND d.revoked_at IS NULL
			FOR UPDATE
		`, rtHMAC).Scan(&oldSessID, &userID, &devID, &storedDevFP, &encEmail, &encName, &profileCompleted, &suspended)
		if err != nil {
			return errors.New("refresh token invalid")
		}
		if suspended {
			return errors.New("account suspended")
		}
		if devHash != "" && storedDevFP != "" && !security.ConstantTimeHexEqual(devHash, storedDevFP) {
			return errors.New("device binding mismatch")
		}

		tag, err := tx.Exec(ctx, `UPDATE sessions SET revoked_at = NOW() WHERE id = $1 AND revoked_at IS NULL`, oldSessID)
		if err != nil || tag.RowsAffected() != 1 {
			return errors.New("refresh race detected")
		}

		if _, err := tx.Exec(ctx, `
			INSERT INTO sessions (id, user_id, device_id, refresh_token_hmac, ip_fp_hash, expires_at)
			VALUES ($1,$2,$3,$4,$5,$6)
		`, newSessionID, userID, devID, newRefreshHMAC, ipFP, time.Now().UTC().Add(30*24*time.Hour)); err != nil {
			return err
		}

		if pt, dErr := security.DecryptAtRest(s.cfg.MasterKey, encEmail, "users.email"); dErr == nil {
			plainEmail = string(pt)
		}
		if pt, dErr := security.DecryptAtRest(s.cfg.MasterKey, encName, "users.display_name"); dErr == nil {
			displayName = string(pt)
		}
		return nil
	})
	if err != nil {
		return nil, http.StatusUnauthorized, err
	}

	expiresIn := int64(900)
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"jti": newSessionID.String(),
		"sub": userID.String(),
		"dev": devHash,
		"ipf": ipFP,
		"iat": time.Now().UTC().Unix(),
		"exp": time.Now().UTC().Add(time.Duration(expiresIn) * time.Second).Unix(),
	})
	accessToken, err := tok.SignedString(s.cfg.JWTSecret)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}

	return &AuthSessionResult{
		AccessToken:      accessToken,
		RefreshToken:     newRefresh,
		ExpiresIn:        expiresIn,
		UserID:           userID.String(),
		Email:            plainEmail,
		DisplayName:      displayName,
		ProfileCompleted: profileCompleted,
	}, http.StatusOK, nil
}

func (s *Service) LogoutSession(ctx context.Context, userID, sessionID uuid.UUID) (int, error) {
	err := db.WithAuthWorkerRLS(ctx, s.pool, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `UPDATE sessions SET revoked_at = NOW() WHERE id = $1 AND user_id = $2`, sessionID, userID)
		return err
	})
	if err != nil {
		return http.StatusInternalServerError, err
	}
	return http.StatusOK, nil
}

func (s *Service) verifyGoogleToken(ctx context.Context, idToken string) (string, string, error) {
	u, _ := url.Parse("https://oauth2.googleapis.com/tokeninfo")
	q := u.Query()
	q.Set("id_token", strings.TrimSpace(idToken))
	u.RawQuery = q.Encode()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return "", "", err
	}
	client := &http.Client{Timeout: 8 * time.Second}
	resp, err := client.Do(req)
	if err != nil || resp.StatusCode != http.StatusOK {
		return "", "", errors.New("google verification failed")
	}
	defer resp.Body.Close()

	var info struct {
		Aud           string `json:"aud"`
		Sub           string `json:"sub"`
		Email         string `json:"email"`
		EmailVerified string `json:"email_verified"`
		Exp           string `json:"exp"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&info); err != nil {
		return "", "", err
	}
	if s.cfg.GoogleClientID != "" && info.Aud != s.cfg.GoogleClientID {
		return "", "", errors.New("audience mismatch")
	}
	expUnix, err := strconv.ParseInt(info.Exp, 10, 64)
	if err != nil || time.Now().UTC().Unix() >= expUnix {
		return "", "", errors.New("google token expired")
	}
	if info.EmailVerified != "true" || info.Sub == "" {
		return "", "", errors.New("unverified email")
	}
	norm, err := normalizeEmail(info.Email)
	return norm, info.Sub, err
}

func (s *Service) fetchApplePublicKey(ctx context.Context, kid string) (*rsa.PublicKey, error) {
	now := time.Now().UTC()
	s.jwksMu.RLock()
	if now.Before(s.appleExp) {
		if k, ok := s.appleKeys[kid]; ok {
			s.jwksMu.RUnlock()
			return k, nil
		}
	}
	s.jwksMu.RUnlock()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://appleid.apple.com/auth/keys", nil)
	if err != nil {
		return nil, err
	}
	resp, err := (&http.Client{Timeout: 8 * time.Second}).Do(req)
	if err != nil || resp.StatusCode != http.StatusOK {
		return nil, errors.New("apple jwks fetch failed")
	}
	defer resp.Body.Close()

	var jwks struct {
		Keys []struct {
			Kty string `json:"kty"`
			Kid string `json:"kid"`
			Alg string `json:"alg"`
			N   string `json:"n"`
			E   string `json:"e"`
		} `json:"keys"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&jwks); err != nil {
		return nil, err
	}

	next := make(map[string]*rsa.PublicKey, len(jwks.Keys))
	for _, k := range jwks.Keys {
		if k.Kty != "RSA" || k.Kid == "" {
			continue
		}
		nBytes, err1 := base64.RawURLEncoding.DecodeString(k.N)
		eBytes, err2 := base64.RawURLEncoding.DecodeString(k.E)
		if err1 != nil || err2 != nil || len(nBytes) == 0 || len(eBytes) == 0 {
			continue
		}
		var eBuf [8]byte
		copy(eBuf[8-len(eBytes):], eBytes)
		eVal := int(binary.BigEndian.Uint64(eBuf[:]))
		next[k.Kid] = &rsa.PublicKey{
			N: new(big.Int).SetBytes(nBytes),
			E: eVal,
		}
	}

	s.jwksMu.Lock()
	s.appleKeys = next
	s.appleExp = now.Add(15 * time.Minute)
	s.jwksMu.Unlock()

	pub, ok := next[kid]
	if !ok {
		return nil, errors.New("apple key not found")
	}
	return pub, nil
}

func (s *Service) verifyAppleToken(ctx context.Context, identityToken string) (string, string, error) {
	token, err := jwt.Parse(identityToken, func(t *jwt.Token) (any, error) {
		if t.Method.Alg() != jwt.SigningMethodRS256.Alg() {
			return nil, errors.New("unexpected apple signing algorithm")
		}
		kid, _ := t.Header["kid"].(string)
		if kid == "" {
			return nil, errors.New("missing apple kid header")
		}
		return s.fetchApplePublicKey(ctx, kid)
	}, jwt.WithValidMethods([]string{jwt.SigningMethodRS256.Alg()}), jwt.WithIssuer("https://appleid.apple.com"), jwt.WithExpirationRequired())
	if err != nil || !token.Valid {
		return "", "", errors.New("invalid apple token signature")
	}
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return "", "", errors.New("invalid apple claims")
	}
	aud, _ := claims["aud"].(string)
	sub, _ := claims["sub"].(string)
	email, _ := claims["email"].(string)
	if sub == "" {
		return "", "", errors.New("missing apple subject")
	}
	if s.cfg.AppleBundleID != "" && aud != s.cfg.AppleBundleID {
		return "", "", errors.New("invalid apple audience")
	}
	if email == "" {
		email = sub + "@privaterelay.appleid.com"
	}
	norm, err := normalizeEmail(email)
	return norm, sub, err
}

func (s *Service) dispatchOTPEmail(recipient, otpCode, magicToken string) error {
	if s.cfg.SMTPHost == "" {
		return nil
	}
	verifyURL := fmt.Sprintf("%s?token=%s&email=%s", s.cfg.MagicLinkBaseURL, url.QueryEscape(magicToken), url.QueryEscape(recipient))
	body := fmt.Sprintf(
		"Subject: Telefam Verification Code\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n"+
			"Your Telefam verification code is: %s\r\n\r\nOr verify using this link:\r\n%s\r\n",
		otpCode, verifyURL,
	)
	auth := smtp.PlainAuth("", s.cfg.SMTPUser, s.cfg.SMTPPass, s.cfg.SMTPHost)
	return smtp.SendMail(s.cfg.SMTPHost+":"+s.cfg.SMTPPort, auth, s.cfg.SMTPFrom, []string{recipient}, []byte(body))
}
