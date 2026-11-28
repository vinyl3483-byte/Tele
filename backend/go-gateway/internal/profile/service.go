package profile

import (
	"context"
	"errors"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/telefam/company/backend/go-gateway/internal/config"
	"github.com/telefam/company/backend/go-gateway/internal/db"
	"github.com/telefam/company/backend/go-gateway/internal/media"
	"github.com/telefam/company/backend/go-gateway/internal/security"
)

type Service struct {
	cfg  *config.Config
	pool *pgxpool.Pool
}

func NewService(cfg *config.Config, pool *pgxpool.Pool) *Service {
	return &Service{cfg: cfg, pool: pool}
}

type SetupRequest struct {
	FullName              string `json:"full_name"`
	Username              string `json:"username"`
	CountryISO            string `json:"country_iso"`
	PhoneNumber           string `json:"phone_number"`
	Gender                string `json:"gender"`
	DateOfBirth           string `json:"date_of_birth"` // YYYY-MM-DD
	Location              string `json:"location"`
	Bio                   string `json:"bio"`
	AvatarFingerprintHash string `json:"avatar_fingerprint_hash"`
}

type BackgroundPhotoDTO struct {
	ID              string `json:"id"`
	SortOrder       int    `json:"sort_order"`
	FingerprintHash string `json:"fingerprint_hash"`
	Width           int    `json:"width"`
	Height          int    `json:"height"`
	URL             string `json:"url"`
}

type ProfileResponse struct {
	UserID                string               `json:"user_id"`
	Email                 string               `json:"email,omitempty"`
	FullName              string               `json:"full_name"`
	Username              string               `json:"username"`
	CountryISO            string               `json:"country_iso"`
	PhoneNumber           string               `json:"phone_number"`
	Gender                string               `json:"gender"`
	DateOfBirth           string               `json:"date_of_birth"`
	Location              string               `json:"location"`
	Bio                   string               `json:"bio"`
	AvatarFingerprintHash string               `json:"avatar_fingerprint_hash"`
	AvatarURL             string               `json:"avatar_url"`
	FollowersCount        int64                `json:"followers_count"`
	FollowingCount        int64                `json:"following_count"`
	PostsCount            int64                `json:"posts_count"`
	ViewsCount            int64                `json:"views_count"`
	LikesCount            int64                `json:"likes_count"`
	BackgroundPhotos      []BackgroundPhotoDTO `json:"background_photos"`
	ProfileCompleted      bool                 `json:"profile_completed"`
}

var usernameRegex = regexp.MustCompile(`^[a-z0-9_]{3,30}$`)

func validateCountryPhone(countryISO, rawPhone string) (string, error) {
	iso := strings.ToUpper(strings.TrimSpace(countryISO))
	var digits strings.Builder
	for _, r := range rawPhone {
		if r >= '0' && r <= '9' {
			digits.WriteRune(r)
		} else if r != ' ' && r != '-' && r != '(' && r != ')' {
			return "", errors.New("invalid phone characters")
		}
	}
	num := digits.String()
	if len(num) > 6 && num[0] == '0' {
		num = num[1:]
	}
	rules := map[string][2]int{
		"KE": {9, 10}, "US": {10, 10}, "CA": {10, 10}, "GB": {10, 10},
		"NG": {10, 10}, "ZA": {9, 9}, "TZ": {9, 9}, "UG": {9, 9},
		"RW": {9, 9}, "ET": {9, 9}, "IN": {10, 10}, "DE": {10, 11},
		"FR": {9, 9}, "AE": {9, 9}, "AU": {9, 9}, "JP": {10, 10}, "BR": {10, 11},
	}
	if r, ok := rules[iso]; ok {
		if len(num) < r[0] || len(num) > r[1] {
			return "", errors.New("invalid phone length")
		}
		return iso + ":" + num, nil
	}
	if len(num) < 7 || len(num) > 15 {
		return "", errors.New("invalid phone length")
	}
	return iso + ":" + num, nil
}

func validateAge13Plus(dobStr string) (time.Time, error) {
	dob, err := time.Parse("2006-01-02", strings.TrimSpace(dobStr))
	if err != nil {
		return time.Time{}, err
	}
	now := time.Now().UTC()
	age := now.Year() - dob.Year()
	if now.Month() < dob.Month() || (now.Month() == dob.Month() && now.Day() < dob.Day()) {
		age--
	}
	if age < 13 || dob.Year() < 1900 {
		return time.Time{}, errors.New("must be at least 13 years old")
	}
	return dob, nil
}

func (s *Service) UploadAvatar(ctx context.Context, userID uuid.UUID, rawBytes []byte) (string, int, error) {
	sanitized, err := media.SanitizeAvatarInIsolation(ctx, rawBytes, s.cfg.HMACPepper)
	if err != nil {
		return "", http.StatusBadRequest, err
	}

	encBytes, err := security.EncryptAtRest(s.cfg.MasterKey, sanitized.Bytes, "profile_avatars.bytes")
	if err != nil {
		return "", http.StatusInternalServerError, err
	}

	err = db.WithUserRLS(ctx, s.pool, userID, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `
			INSERT INTO profile_avatars (user_id, mime_type, byte_size, fingerprint_hash, sanitized_bytes_encrypted)
			VALUES ($1, $2, $3, $4, $5)
			ON CONFLICT (user_id) DO UPDATE SET
				mime_type = EXCLUDED.mime_type,
				byte_size = EXCLUDED.byte_size,
				fingerprint_hash = EXCLUDED.fingerprint_hash,
				sanitized_bytes_encrypted = EXCLUDED.sanitized_bytes_encrypted,
				updated_at = NOW()
		`, userID, sanitized.MimeType, len(sanitized.Bytes), sanitized.FingerprintHash, encBytes); err != nil {
			return err
		}
		_, _ = tx.Exec(ctx, `
			UPDATE user_profiles SET avatar_fingerprint_hash = $1, updated_at = NOW()
			WHERE user_id = $2
		`, sanitized.FingerprintHash, userID)
		return nil
	})
	if err != nil {
		return "", http.StatusInternalServerError, err
	}
	return sanitized.FingerprintHash, http.StatusOK, nil
}

func (s *Service) loadProfileSummaryTx(ctx context.Context, tx pgx.Tx, userID uuid.UUID, resp *ProfileResponse) error {
	resp.BackgroundPhotos = []BackgroundPhotoDTO{}
	if resp.AvatarFingerprintHash != "" {
		resp.AvatarURL = "/v1/profile/avatar?v=" + resp.AvatarFingerprintHash
	}
	_ = tx.QueryRow(ctx, `SELECT COUNT(*) FROM user_follows WHERE followee_id = $1`, userID).Scan(&resp.FollowersCount)
	_ = tx.QueryRow(ctx, `SELECT COUNT(*) FROM user_follows WHERE follower_id = $1`, userID).Scan(&resp.FollowingCount)
	_ = tx.QueryRow(ctx, `SELECT COUNT(*) FROM posts WHERE author_id = $1 AND status = 'ready'`, userID).Scan(&resp.PostsCount)

	var videoViews, videoLikes, otherViews, otherLikes int64
	_ = tx.QueryRow(ctx, `
		SELECT COALESCE(SUM(views_count), 0), COALESCE(SUM(likes_count), 0)
		FROM videos WHERE creator_id = $1 AND processing_status = 'ready'
	`, userID).Scan(&videoViews, &videoLikes)
	_ = tx.QueryRow(ctx, `
		SELECT COALESCE(SUM(views_count), 0), COALESCE(SUM(likes_count), 0)
		FROM posts WHERE author_id = $1 AND post_type <> 'video' AND status = 'ready'
	`, userID).Scan(&otherViews, &otherLikes)
	resp.ViewsCount = videoViews + otherViews
	resp.LikesCount = videoLikes + otherLikes

	bgList, err := s.listBackgroundPhotosTx(ctx, tx, userID)
	if err == nil {
		resp.BackgroundPhotos = bgList
	}
	return nil
}

func (s *Service) GetMyProfile(ctx context.Context, userID uuid.UUID) (*ProfileResponse, int, error) {
	var resp ProfileResponse
	resp.UserID = userID.String()
	resp.BackgroundPhotos = []BackgroundPhotoDTO{}

	err := db.WithUserRLS(ctx, s.pool, userID, func(tx pgx.Tx) error {
		var encEmail, encDisp []byte
		if err := tx.QueryRow(ctx, `
			SELECT email_encrypted, display_name_encrypted, profile_completed
			FROM users WHERE id = $1
		`, userID).Scan(&encEmail, &encDisp, &resp.ProfileCompleted); err != nil {
			return err
		}
		if b, err := security.DecryptAtRest(s.cfg.MasterKey, encEmail, "users.email"); err == nil {
			resp.Email = string(b)
		}
		if b, err := security.DecryptAtRest(s.cfg.MasterKey, encDisp, "users.display_name"); err == nil {
			resp.FullName = string(b)
		}

		var encName, encUser, encPhone, encLoc, encBio []byte
		var countryISO, gender, avatarFP string
		var dob time.Time
		pErr := tx.QueryRow(ctx, `
			SELECT full_name_encrypted, username_encrypted, phone_e164_encrypted,
			       country_iso, gender, date_of_birth, location_encrypted, bio_encrypted,
			       COALESCE(avatar_fingerprint_hash, '')
			FROM user_profiles WHERE user_id = $1
		`, userID).Scan(&encName, &encUser, &encPhone, &countryISO, &gender, &dob, &encLoc, &encBio, &avatarFP)
		if pErr == nil {
			if b, err := security.DecryptAtRest(s.cfg.MasterKey, encName, "profiles.full_name"); err == nil {
				resp.FullName = string(b)
			}
			if b, err := security.DecryptAtRest(s.cfg.MasterKey, encUser, "profiles.username"); err == nil {
				resp.Username = string(b)
			}
			if b, err := security.DecryptAtRest(s.cfg.MasterKey, encPhone, "profiles.phone"); err == nil {
				rawPhone := string(b)
				if idx := strings.Index(rawPhone, ":"); idx >= 0 && idx+1 < len(rawPhone) {
					resp.PhoneNumber = rawPhone[idx+1:]
				} else {
					resp.PhoneNumber = rawPhone
				}
			}
			if b, err := security.DecryptAtRest(s.cfg.MasterKey, encLoc, "profiles.location"); err == nil {
				resp.Location = string(b)
			}
			if b, err := security.DecryptAtRest(s.cfg.MasterKey, encBio, "profiles.bio"); err == nil {
				resp.Bio = string(b)
			}
			resp.CountryISO = countryISO
			resp.Gender = gender
			resp.DateOfBirth = dob.Format("2006-01-02")
			resp.AvatarFingerprintHash = avatarFP
		}
		if resp.AvatarFingerprintHash == "" {
			_ = tx.QueryRow(ctx, `SELECT COALESCE(fingerprint_hash, '') FROM profile_avatars WHERE user_id = $1`, userID).Scan(&resp.AvatarFingerprintHash)
		}
		return s.loadProfileSummaryTx(ctx, tx, userID, &resp)
	})
	if err != nil {
		return nil, http.StatusNotFound, err
	}
	return &resp, http.StatusOK, nil
}

func (s *Service) SetupProfile(ctx context.Context, userID uuid.UUID, req SetupRequest) (*ProfileResponse, int, error) {
	fullName := strings.TrimSpace(req.FullName)
	username := strings.ToLower(strings.TrimSpace(req.Username))
	if len(fullName) < 2 || len(fullName) > 80 {
		return nil, http.StatusBadRequest, errors.New("invalid full name")
	}
	if !usernameRegex.MatchString(username) {
		return nil, http.StatusBadRequest, errors.New("invalid username")
	}
	normalizedPhone, err := validateCountryPhone(req.CountryISO, req.PhoneNumber)
	if err != nil {
		return nil, http.StatusBadRequest, err
	}
	gender := strings.ToLower(strings.TrimSpace(req.Gender))
	switch gender {
	case "male", "female", "non_binary", "prefer_not_to_say":
	default:
		return nil, http.StatusBadRequest, errors.New("invalid gender")
	}
	dob, err := validateAge13Plus(req.DateOfBirth)
	if err != nil {
		return nil, http.StatusBadRequest, err
	}
	location := strings.TrimSpace(req.Location)
	if len(location) > 100 {
		location = location[:100]
	}
	bio := strings.TrimSpace(req.Bio)
	if len([]rune(bio)) > 150 {
		return nil, http.StatusBadRequest, errors.New("bio exceeds 150 characters")
	}

	usernameHash := security.HMACSHA256Hex(s.cfg.HMACPepper, username)
	encName, _ := security.EncryptAtRest(s.cfg.MasterKey, []byte(fullName), "profiles.full_name")
	encUser, _ := security.EncryptAtRest(s.cfg.MasterKey, []byte(username), "profiles.username")
	encPhone, _ := security.EncryptAtRest(s.cfg.MasterKey, []byte(normalizedPhone), "profiles.phone")
	encLoc, _ := security.EncryptAtRest(s.cfg.MasterKey, []byte(location), "profiles.location")
	encBio, _ := security.EncryptAtRest(s.cfg.MasterKey, []byte(bio), "profiles.bio")

	err = db.WithUserRLS(ctx, s.pool, userID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO user_profiles (
				user_id, full_name_encrypted, username_hash, username_encrypted,
				phone_e164_encrypted, country_iso, gender, date_of_birth,
				location_encrypted, bio_encrypted, avatar_fingerprint_hash
			) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,NULLIF($11,''))
			ON CONFLICT (user_id) DO UPDATE SET
				full_name_encrypted = EXCLUDED.full_name_encrypted,
				username_hash = EXCLUDED.username_hash,
				username_encrypted = EXCLUDED.username_encrypted,
				phone_e164_encrypted = EXCLUDED.phone_e164_encrypted,
				country_iso = EXCLUDED.country_iso,
				gender = EXCLUDED.gender,
				date_of_birth = EXCLUDED.date_of_birth,
				location_encrypted = EXCLUDED.location_encrypted,
				bio_encrypted = EXCLUDED.bio_encrypted,
				avatar_fingerprint_hash = COALESCE(EXCLUDED.avatar_fingerprint_hash, user_profiles.avatar_fingerprint_hash),
				updated_at = NOW()
		`, userID, encName, usernameHash, encUser, encPhone, strings.ToUpper(req.CountryISO), gender, dob, encLoc, encBio, req.AvatarFingerprintHash)
		if err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `
			UPDATE users SET display_name_encrypted = $1, profile_completed = TRUE, updated_at = NOW()
			WHERE id = $2
		`, encName, userID)
		return err
	})
	if err != nil {
		return nil, http.StatusConflict, err
	}

	return s.GetMyProfile(ctx, userID)
}
