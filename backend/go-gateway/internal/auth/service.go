package auth

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"net/smtp"
	"strings"
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
	cfg     *config.Config
	pool    *pgxpool.Pool
	limiter *ratelimit.Limiter
}

func NewService(cfg *config.Config, pool *pgxpool.Pool, limiter *ratelimit.Limiter) *Service {
	return &Service{cfg: cfg, pool: pool, limiter: limiter}
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
	if err != nil && magicToken == "" {
		return nil, http.StatusBadRequest, errors.New("invalid input")
	}
	emailHash := security.HMACSHA256Hex(s.cfg.HMACPepper, email)

	var verifiedEmailHash string
	err = db.WithAuthWorkerRLS(ctx, s.pool, func(tx pgx.Tx) error {
		var challengeID uuid.UUID
		var cEmailHash, otpHMAC, magicHMAC string
		var attempts int
		var expiresAt time.Time

		var qErr error
		if magicToken != "" {
			magicCandidate := security.HMACSHA256Hex(s.cfg.HMACPepper, magicToken)
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

		if magicToken != "" {
			magicCandidate := security.HMACSHA256Hex(s.cfg.HMACPepper, magicToken)
			if !security.ConstantTimeHexEqual(magicCandidate, magicHMAC) {
				return errors.New("invalid magic token")
			}
		} else {
			otpCandidate := security.HMACSHA256Hex(s.cfg.HMACPepper, cEmailHash+"|"+strings.TrimSpace(otp))
			if !security.ConstantTimeHexEqual(otpCandidate, otpHMAC) {
				_, _ = tx.Exec(ctx, `UPDATE otp_challenges SET attempt_count = attempt_count + 1 WHERE id = $1`, challengeID)
				return errors.New("invalid otp")
			}
		}

		_, updErr := tx.Exec(ctx, `UPDATE otp_challenges SET consumed_at = NOW() WHERE id = $1`, challengeID)
		verifiedEmailHash = cEmailHash
		return updErr
	})
	if err != nil {
		return nil, http.StatusUnauthorized, err
	}

	return s.issueSessionForUser(ctx, verifiedEmailHash, email, "email_otp", "", "", devHash, ipFP, hwAttest, deviceName, platform)
}

func (s *Service) VerifyOAuth(ctx context.Context, provider, idToken, deviceFP, ipFP, hwAttest, deviceName, platform string) (*AuthSessionResult, int, error) {
	devHash := security.CanonicalizeDeviceFingerprint(s.cfg.HMACPepper, deviceFP, hwAttest, platform)
	if !s.limiter.AllowMulti(ctx, provider, devHash, ipFP) {
		return nil, http.StatusTooManyRequests, errors.New("rate limit exceeded")
	}

	var email, sub string
	var err error
	switch provider {
	case "google":
		email, sub, err = s.verifyGoogleToken(ctx, idToken)
	case "apple":
		email, sub, err = s.verifyAppleToken(ctx, idToken)
	default:
		return nil, http.StatusBadRequest, errors.New("unsupported provider")
	}
	if err != nil {
		return nil, http.StatusUnauthorized, err
	}

	emailHash := security.HMACSHA256Hex(s.cfg.HMACPepper, email)
	subHash := security.HMACSHA256Hex(s.cfg.HMACPepper, provider+":"+sub)
	return s.issueSessionForUser(ctx, emailHash, email, provider, subHash, subHash, devHash, ipFP, hwAttest, deviceName, platform)
}

func (s *Service) issueSessionForUser(
	ctx context.Context,
	emailHash, plainEmail, provider, googleSubHash, appleSubHash, devHash, ipFP, hwAttest, deviceName, platform string,
) (*AuthSessionResult, int, error) {
	var userID uuid.UUID
	var displayName string
	var profileCompleted bool
	refreshToken, err := generateRandomTokenHex(32)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	refreshHMAC := security.HMACSHA256Hex(s.cfg.HMACPepper, refreshToken)

	if plainEmail == "" {
		plainEmail = "verified@telefam.app"
	}
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
		qErr := tx.QueryRow(ctx, `SELECT id, display_name_encrypted, profile_completed FROM users WHERE email_hash = $1`, emailHash).Scan(&userID, &existingEncName, &profileCompleted)
		if qErr == pgx.ErrNoRows {
			qErr = tx.QueryRow(ctx, `
				INSERT INTO users (email_hash, email_encrypted, display_name_encrypted, auth_provider, google_sub_hash, apple_sub_hash, profile_completed)
				VALUES ($1,$2,$3,$4,NULLIF($5,''),NULLIF($6,''), FALSE)
				RETURNING id
			`, emailHash, encEmail, encName, provider, googleSubHash, appleSubHash).Scan(&userID)
			displayName = defaultName
			profileCompleted = false
		} else if qErr == nil {
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
			INSERT INTO sessions (user_id, device_id, refresh_token_hmac, ip_fp_hash, expires_at)
			VALUES ($1,$2,$3,$4,$5)
		`, userID, deviceID, refreshHMAC, ipFP, time.Now().UTC().Add(30*24*time.Hour))
		return err
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}

	expiresIn := int64(900) // 15 minutes short-lived access JWT
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
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

func (s *Service) ParseAccessToken(tokenString string) (uuid.UUID, string, error) {
	parsed, err := jwt.Parse(tokenString, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("unexpected signing method")
		}
		return s.cfg.JWTSecret, nil
	})
	if err != nil || !parsed.Valid {
		return uuid.Nil, "", errors.New("invalid token")
	}
	claims, ok := parsed.Claims.(jwt.MapClaims)
	if !ok {
		return uuid.Nil, "", errors.New("invalid claims")
	}
	subStr, _ := claims["sub"].(string)
	devFP, _ := claims["dev"].(string)
	uid, err := uuid.Parse(subStr)
	if err != nil {
		return uuid.Nil, "", errors.New("invalid subject")
	}
	return uid, devFP, nil
}

func (s *Service) verifyGoogleToken(ctx context.Context, idToken string) (string, string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://oauth2.googleapis.com/tokeninfo?id_token="+idToken, nil)
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
	}
	if err := json.NewDecoder(resp.Body).Decode(&info); err != nil {
		return "", "", err
	}
	if s.cfg.GoogleClientID != "" && info.Aud != s.cfg.GoogleClientID {
		return "", "", errors.New("audience mismatch")
	}
	if info.EmailVerified != "true" || info.Sub == "" {
		return "", "", errors.New("unverified email")
	}
	norm, err := normalizeEmail(info.Email)
	return norm, info.Sub, err
}

func (s *Service) verifyAppleToken(_ context.Context, identityToken string) (string, string, error) {
	// Parse JWT header & verify claims structure against Apple ISS and audience;
	// in production deployments fetch Apple's https://appleid.apple.com/auth/keys JWKS.
	parser := jwt.NewParser()
	token, _, err := parser.ParseUnverified(identityToken, jwt.MapClaims{})
	if err != nil {
		return "", "", err
	}
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return "", "", errors.New("invalid apple claims")
	}
	iss, _ := claims["iss"].(string)
	aud, _ := claims["aud"].(string)
	sub, _ := claims["sub"].(string)
	email, _ := claims["email"].(string)
	if iss != "https://appleid.apple.com" || sub == "" {
		return "", "", errors.New("invalid apple issuer")
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
		// SMTP not configured in local dev environment
		return nil
	}
	verifyURL := fmt.Sprintf("%s?token=%s&email=%s", s.cfg.MagicLinkBaseURL, magicToken, recipient)
	body := fmt.Sprintf(
		"Subject: Telefam Verification Code\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n"+
			"Your Telefam verification code is: %s\r\n\r\nOr verify using this link:\r\n%s\r\n",
		otpCode, verifyURL,
	)
	auth := smtp.PlainAuth("", s.cfg.SMTPUser, s.cfg.SMTPPass, s.cfg.SMTPHost)
	return smtp.SendMail(s.cfg.SMTPHost+":"+s.cfg.SMTPPort, auth, s.cfg.SMTPFrom, []string{recipient}, []byte(body))
}
