package posts

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
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

var validHashtagRe = regexp.MustCompile(`[^a-z0-9_]+`)

type Service struct {
	cfg  *config.Config
	pool *pgxpool.Pool
	http *http.Client
}

func NewService(cfg *config.Config, pool *pgxpool.Pool) *Service {
	return &Service{
		cfg:  cfg,
		pool: pool,
		http: &http.Client{Timeout: 8 * time.Second},
	}
}

type MusicTrackDTO struct {
	TrackID     string `json:"track_id"`
	Title       string `json:"title"`
	Artist      string `json:"artist"`
	ArtworkURL  string `json:"artwork_url"`
	PreviewURL  string `json:"preview_url"`
	DurationSec int    `json:"duration_sec"`
}

type HashtagDTO struct {
	Tag       string `json:"tag"`
	PostCount int64  `json:"post_count"`
}

type UploadedPhotoDTO struct {
	MediaID         string `json:"media_id"`
	RenamedFilename string `json:"renamed_filename"`
	ContentID       string `json:"content_id"`
	Width           int    `json:"width"`
	Height          int    `json:"height"`
	PerceptualDHash string `json:"perceptual_dhash"`
}

type UploadedVideoDTO struct {
	MediaID              string                        `json:"media_id"`
	RenamedFilename      string                        `json:"renamed_filename"`
	ContentID            string                        `json:"content_id"`
	ThumbnailObjectKey   string                        `json:"thumbnail_object_key"`
	ThumbnailFingerprint string                        `json:"thumbnail_fingerprint"`
	AudioFingerprintHash string                        `json:"audio_fingerprint_hash"`
	Width                int                           `json:"width"`
	Height               int                           `json:"height"`
	DurationMs           int64                         `json:"duration_ms"`
	FrameCount           int                           `json:"frame_count"`
	Qualities            []media.VideoQualityRendition `json:"qualities"`
}

type CreatePostRequest struct {
	PostType          string   `json:"post_type"` // text | photos | video
	Body              string   `json:"body"`
	BgColorHex        string   `json:"bg_color_hex"`
	BgThemeID         string   `json:"bg_theme_id"`
	FontFamily        string   `json:"font_family"`
	SongID            string   `json:"song_id"`
	SongTitle         string   `json:"song_title"`
	SongArtist        string   `json:"song_artist"`
	SongPreviewURL    string   `json:"song_preview_url"`
	MuteOriginalAudio bool     `json:"mute_original_audio"`
	TrimStartMs       int64    `json:"trim_start_ms"`
	TrimEndMs         int64    `json:"trim_end_ms"`
	MediaIDs          []string `json:"media_ids"`
	TaggedUserIDs     []string `json:"tagged_user_ids"`
	Hashtags          []string `json:"hashtags"`
}

type CreatePostResponse struct {
	PostID                 string `json:"post_id"`
	PostType               string `json:"post_type"`
	ContentFingerprintHash string `json:"content_fingerprint_hash"`
	Status                 string `json:"status"`
}

type AdminUserDTO struct {
	UserID           string `json:"user_id"`
	Email            string `json:"email"`
	FullName         string `json:"full_name"`
	Username         string `json:"username"`
	AuthProvider     string `json:"auth_provider"`
	ProfileCompleted bool   `json:"profile_completed"`
	CreatedAt        int64  `json:"created_at"`
}

func (s *Service) VerifyAdminKey(headerValue string) bool {
	expected := strings.TrimSpace(s.cfg.AdminAPIKey)
	if len(expected) < 16 {
		return false
	}
	provided := strings.TrimSpace(headerValue)
	if len(provided) != len(expected) {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(provided), []byte(expected)) == 1
}

func (s *Service) SearchPublicSongs(ctx context.Context, rawQuery string) ([]MusicTrackDTO, int, error) {
	q := strings.TrimSpace(rawQuery)
	if q == "" {
		q = "top hits"
	}
	if len(q) > 80 {
		q = q[:80]
	}

	tracks, err := s.queryITunes(ctx, q)
	if err == nil && len(tracks) > 0 {
		return tracks, http.StatusOK, nil
	}
	dzTracks, dzErr := s.queryDeezer(ctx, q)
	if dzErr == nil && len(dzTracks) > 0 {
		return dzTracks, http.StatusOK, nil
	}
	if err != nil {
		return []MusicTrackDTO{}, http.StatusOK, nil
	}
	return tracks, http.StatusOK, nil
}

func (s *Service) queryITunes(ctx context.Context, q string) ([]MusicTrackDTO, error) {
	base, err := url.Parse(s.cfg.ITunesSearchURL)
	if err != nil || (base.Scheme != "https" && base.Scheme != "http") {
		return nil, errors.New("invalid music upstream")
	}
	params := base.Query()
	params.Set("term", q)
	params.Set("media", "music")
	params.Set("entity", "song")
	params.Set("limit", "25")
	base.RawQuery = params.Encode()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, base.String(), nil)
	if err != nil {
		return nil, err
	}
	resp, err := s.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, errors.New("music upstream status")
	}

	var decoded struct {
		Results []struct {
			TrackID        int64  `json:"trackId"`
			TrackName      string `json:"trackName"`
			ArtistName     string `json:"artistName"`
			ArtworkURL100  string `json:"artworkUrl100"`
			PreviewURL     string `json:"previewUrl"`
			TrackTimeMills int64  `json:"trackTimeMillis"`
		} `json:"results"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 512*1024)).Decode(&decoded); err != nil {
		return nil, err
	}

	out := make([]MusicTrackDTO, 0, len(decoded.Results))
	for _, r := range decoded.Results {
		if r.TrackName == "" || r.PreviewURL == "" {
			continue
		}
		sec := int(r.TrackTimeMills / 1000)
		if sec <= 0 {
			sec = 30
		}
		out = append(out, MusicTrackDTO{
			TrackID:     "itunes_" + strconvFormatInt64(r.TrackID),
			Title:       r.TrackName,
			Artist:      r.ArtistName,
			ArtworkURL:  r.ArtworkURL100,
			PreviewURL:  r.PreviewURL,
			DurationSec: sec,
		})
	}
	return out, nil
}

func (s *Service) queryDeezer(ctx context.Context, q string) ([]MusicTrackDTO, error) {
	base, err := url.Parse(s.cfg.DeezerSearchURL)
	if err != nil || (base.Scheme != "https" && base.Scheme != "http") {
		return nil, errors.New("invalid music upstream")
	}
	params := base.Query()
	params.Set("q", q)
	params.Set("limit", "25")
	base.RawQuery = params.Encode()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, base.String(), nil)
	if err != nil {
		return nil, err
	}
	resp, err := s.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, errors.New("deezer upstream status")
	}

	var decoded struct {
		Data []struct {
			ID       int64  `json:"id"`
			Title    string `json:"title"`
			Duration int    `json:"duration"`
			Preview  string `json:"preview"`
			Artist   struct {
				Name string `json:"name"`
			} `json:"artist"`
			Album struct {
				CoverMedium string `json:"cover_medium"`
			} `json:"album"`
		} `json:"data"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 512*1024)).Decode(&decoded); err != nil {
		return nil, err
	}
	out := make([]MusicTrackDTO, 0, len(decoded.Data))
	for _, r := range decoded.Data {
		if r.Title == "" || r.Preview == "" {
			continue
		}
		out = append(out, MusicTrackDTO{
			TrackID:     "dz_" + strconvFormatInt64(r.ID),
			Title:       r.Title,
			Artist:      r.Artist.Name,
			ArtworkURL:  r.Album.CoverMedium,
			PreviewURL:  r.Preview,
			DurationSec: r.Duration,
		})
	}
	return out, nil
}

func (s *Service) SearchHashtags(ctx context.Context, viewerID uuid.UUID, rawQuery string) ([]HashtagDTO, int, error) {
	q := normalizeHashtag(rawQuery)
	out := make([]HashtagDTO, 0, 25)
	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		var rows pgx.Rows
		var err error
		if q == "" {
			rows, err = tx.Query(ctx, `
				SELECT display_tag, post_count
				FROM hashtags
				ORDER BY post_count DESC, tag_normalized ASC
				LIMIT 30
			`)
		} else {
			rows, err = tx.Query(ctx, `
				SELECT display_tag, post_count
				FROM hashtags
				WHERE tag_normalized LIKE $1
				ORDER BY post_count DESC, tag_normalized ASC
				LIMIT 30
			`, q+"%")
		}
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var tag string
			var cnt int64
			if err := rows.Scan(&tag, &cnt); err != nil {
				return err
			}
			out = append(out, HashtagDTO{Tag: tag, PostCount: cnt})
		}
		return rows.Err()
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return out, http.StatusOK, nil
}

func (s *Service) UploadAndSanitizePhotos(
	ctx context.Context,
	authorID uuid.UUID,
	rawPhotos [][]byte,
) ([]UploadedPhotoDTO, int, error) {
	if len(rawPhotos) == 0 || len(rawPhotos) > 10 {
		return nil, http.StatusBadRequest, errors.New("photos count must be between 1 and 10")
	}

	uploaded := make([]UploadedPhotoDTO, 0, len(rawPhotos))
	err := db.WithUserRLS(ctx, s.pool, authorID, func(tx pgx.Tx) error {
		for idx, raw := range rawPhotos {
			mediaID := uuid.New()
			renamed := "img_" + mediaID.String() + ".jpg"
			sanitized, err := media.SanitizePostPhotoInIsolation(ctx, raw, s.cfg.HMACPepper, renamed)
			if err != nil {
				return err
			}
			targetPath, err := media.ConfineStoragePath(s.cfg.MediaStorageDir, "photos", renamed)
			if err != nil {
				return err
			}
			if err := os.MkdirAll(filepath.Dir(targetPath), 0o750); err != nil {
				return err
			}
			if err := os.WriteFile(targetPath, sanitized.Bytes, 0o640); err != nil {
				return err
			}

			objKey := "photos/" + renamed
			_, err = tx.Exec(ctx, `
				INSERT INTO post_media (
					id, author_id, media_kind, sort_order, renamed_filename, stored_object_key,
					mime_type, byte_size, width, height, duration_ms, content_id, sanitized_at
				) VALUES ($1, $2, 'photo', $3, $4, $5, $6, $7, $8, $9, 0, $10, NOW())
			`, mediaID, authorID, idx, renamed, objKey, sanitized.MimeType, len(sanitized.Bytes), sanitized.Width, sanitized.Height, sanitized.ContentID)
			if err != nil {
				return err
			}

			_, err = tx.Exec(ctx, `
				INSERT INTO media_frame_fingerprints (
					media_id, stream_kind, frame_index, timestamp_ms, perceptual_dhash, sha256_hash
				) VALUES ($1, 'image', 0, 0, $2, $3)
			`, mediaID, sanitized.PerceptualDHash, sanitized.Sha256Hex)
			if err != nil {
				return err
			}

			uploaded = append(uploaded, UploadedPhotoDTO{
				MediaID:         mediaID.String(),
				RenamedFilename: renamed,
				ContentID:       sanitized.ContentID,
				Width:           sanitized.Width,
				Height:          sanitized.Height,
				PerceptualDHash: sanitized.PerceptualDHash,
			})
		}
		return nil
	})
	if err != nil {
		return nil, http.StatusBadRequest, err
	}
	return uploaded, http.StatusOK, nil
}

func (s *Service) UploadAndSanitizeVideo(
	ctx context.Context,
	authorID uuid.UUID,
	tempVideoPath string,
	rawSize int64,
	opts media.VideoSanitizeOptions,
) (*UploadedVideoDTO, int, error) {
	mediaID := uuid.New()
	opts.MediaStorageBaseDir = s.cfg.MediaStorageDir
	opts.RenamedVideoFile = "vid_" + mediaID.String() + ".mp4"
	opts.RenamedThumbFile = "thumb_" + mediaID.String() + ".jpg"

	res, err := media.SanitizeVideoInIsolation(ctx, tempVideoPath, rawSize, s.cfg.HMACPepper, opts)
	if err != nil {
		return nil, http.StatusBadRequest, err
	}
	qualitiesJSON, _ := json.Marshal(res.Qualities)

	err = db.WithUserRLS(ctx, s.pool, authorID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO post_media (
				id, author_id, media_kind, sort_order, renamed_filename, stored_object_key,
				mime_type, byte_size, width, height, duration_ms, content_id,
				audio_fingerprint_hash, thumbnail_object_key, thumbnail_fingerprint_hash,
				qualities_json, sanitized_at
			) VALUES ($1, $2, 'video', 0, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14::jsonb, NOW())
		`, mediaID, authorID, res.RenamedVideoFilename, res.PrimaryObjectKey,
			res.MimeType, res.ByteSize, res.Width, res.Height, res.DurationMs, res.ContentID,
			res.AudioFingerprintHash, res.ThumbnailObjectKey, res.ThumbnailFingerprint, string(qualitiesJSON))
		if err != nil {
			return err
		}

		for _, fr := range res.FrameFingerprints {
			if _, err := tx.Exec(ctx, `
				INSERT INTO media_frame_fingerprints (
					media_id, stream_kind, frame_index, timestamp_ms, perceptual_dhash, sha256_hash
				) VALUES ($1, $2, $3, $4, $5, $6)
			`, mediaID, fr.StreamKind, fr.FrameIndex, fr.TimestampMs, fr.PerceptualDHash, fr.Sha256Hex); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}

	return &UploadedVideoDTO{
		MediaID:              mediaID.String(),
		RenamedFilename:      res.RenamedVideoFilename,
		ContentID:            res.ContentID,
		ThumbnailObjectKey:   res.ThumbnailObjectKey,
		ThumbnailFingerprint: res.ThumbnailFingerprint,
		AudioFingerprintHash: res.AudioFingerprintHash,
		Width:                res.Width,
		Height:               res.Height,
		DurationMs:           res.DurationMs,
		FrameCount:           len(res.FrameFingerprints),
		Qualities:            res.Qualities,
	}, http.StatusOK, nil
}

func (s *Service) CreatePost(ctx context.Context, authorID uuid.UUID, req CreatePostRequest) (*CreatePostResponse, int, error) {
	postType := strings.ToLower(strings.TrimSpace(req.PostType))
	if postType != "text" && postType != "photos" && postType != "video" {
		return nil, http.StatusBadRequest, errors.New("invalid post_type")
	}
	body := strings.TrimSpace(req.Body)
	if postType == "text" {
		if body == "" || len([]rune(body)) > 280 {
			return nil, http.StatusBadRequest, errors.New("invalid text post length")
		}
	} else {
		if len([]rune(body)) > 2200 {
			return nil, http.StatusBadRequest, errors.New("caption too long")
		}
		if len(req.MediaIDs) == 0 {
			return nil, http.StatusBadRequest, errors.New("media required")
		}
	}

	encBody, err := security.EncryptAtRest(s.cfg.MasterKey, []byte(body), "posts.body")
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	encSongTitle, _ := security.EncryptAtRest(s.cfg.MasterKey, []byte(req.SongTitle), "posts.song_title")
	encSongArtist, _ := security.EncryptAtRest(s.cfg.MasterKey, []byte(req.SongArtist), "posts.song_artist")

	mac := hmac.New(sha256.New, s.cfg.HMACPepper)
	mac.Write([]byte(postType + "|" + body + "|" + strings.Join(req.MediaIDs, ",")))
	contentFP := hex.EncodeToString(mac.Sum(nil))

	postID := uuid.New()
	err = db.WithUserRLS(ctx, s.pool, authorID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO posts (
				id, author_id, post_type, body_encrypted, bg_color_hex, bg_theme_id, font_family,
				song_id, song_title_encrypted, song_artist_encrypted, song_preview_url,
				mute_original_audio, trim_start_ms, trim_end_ms, content_fingerprint_hash, status
			) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, 'ready')
		`, postID, authorID, postType, encBody, req.BgColorHex, req.BgThemeID, req.FontFamily,
			req.SongID, encSongTitle, encSongArtist, req.SongPreviewURL,
			req.MuteOriginalAudio, req.TrimStartMs, req.TrimEndMs, contentFP)
		if err != nil {
			return err
		}

		for idx, rawMid := range req.MediaIDs {
			mid, pErr := uuid.Parse(strings.TrimSpace(rawMid))
			if pErr != nil {
				return errors.New("invalid media_id")
			}
			tag, uErr := tx.Exec(ctx, `
				UPDATE post_media
				SET post_id = $1, sort_order = $2
				WHERE id = $3 AND author_id = $4
			`, postID, idx, mid, authorID)
			if uErr != nil || tag.RowsAffected() != 1 {
				return errors.New("media ownership validation failed")
			}
		}

		for _, rawTag := range req.Hashtags {
			norm := normalizeHashtag(rawTag)
			if norm == "" {
				continue
			}
			if _, err := tx.Exec(ctx, `
				INSERT INTO hashtags (tag_normalized, display_tag, post_count, updated_at)
				VALUES ($1, $2, 1, NOW())
				ON CONFLICT (tag_normalized) DO UPDATE SET
					post_count = hashtags.post_count + 1,
					updated_at = NOW()
			`, norm, norm); err != nil {
				return err
			}
			if _, err := tx.Exec(ctx, `
				INSERT INTO post_hashtags (post_id, tag_normalized)
				VALUES ($1, $2) ON CONFLICT DO NOTHING
			`, postID, norm); err != nil {
				return err
			}
		}

		for _, rawUid := range req.TaggedUserIDs {
			tUid, pErr := uuid.Parse(strings.TrimSpace(rawUid))
			if pErr != nil {
				continue
			}
			_, _ = tx.Exec(ctx, `
				INSERT INTO post_tags (post_id, tagged_user_id)
				VALUES ($1, $2) ON CONFLICT DO NOTHING
			`, postID, tUid)
		}

		return nil
	})
	if err != nil {
		return nil, http.StatusBadRequest, err
	}

	s.notifyErlangPostEvent(authorID, postID)

	return &CreatePostResponse{
		PostID:                 postID.String(),
		PostType:               postType,
		ContentFingerprintHash: contentFP,
		Status:                 "ready",
	}, http.StatusCreated, nil
}

// ============================================================================
// ADMIN RLS BYPASS OPERATIONS (Gated by TELEFAM_ADMIN_API_KEY)
// ============================================================================

func (s *Service) AdminListAllUsers(ctx context.Context) ([]AdminUserDTO, int, error) {
	var users []AdminUserDTO
	err := db.WithAdminBypassRLS(ctx, s.pool, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT u.id, u.email_encrypted, COALESCE(up.full_name_encrypted, u.display_name_encrypted),
			       COALESCE(up.username_encrypted, ''::bytea), u.auth_provider, u.profile_completed, u.created_at
			FROM users u
			LEFT JOIN user_profiles up ON up.user_id = u.id
			ORDER BY u.created_at DESC
			LIMIT 500
		`)
		if err != nil {
			return err
		}
		defer rows.Close()

		for rows.Next() {
			var id uuid.UUID
			var encEmail, encName, encUsername []byte
			var provider string
			var completed bool
			var created time.Time
			if err := rows.Scan(&id, &encEmail, &encName, &encUsername, &provider, &completed, &created); err != nil {
				return err
			}
			em, _ := security.DecryptAtRest(s.cfg.MasterKey, encEmail, "users.email")
			fn, _ := security.DecryptAtRest(s.cfg.MasterKey, encName, "profiles.full_name")
			if len(fn) == 0 {
				fn, _ = security.DecryptAtRest(s.cfg.MasterKey, encName, "users.display_name")
			}
			un, _ := security.DecryptAtRest(s.cfg.MasterKey, encUsername, "profiles.username")
			users = append(users, AdminUserDTO{
				UserID:           id.String(),
				Email:            string(em),
				FullName:         string(fn),
				Username:         string(un),
				AuthProvider:     provider,
				ProfileCompleted: completed,
				CreatedAt:        created.UnixMilli(),
			})
		}
		return rows.Err()
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return users, http.StatusOK, nil
}

func (s *Service) AdminAddUser(ctx context.Context, email, displayName string) (*AdminUserDTO, int, error) {
	normEmail := strings.ToLower(strings.TrimSpace(email))
	if normEmail == "" || !strings.Contains(normEmail, "@") {
		return nil, http.StatusBadRequest, errors.New("invalid email")
	}
	emailHash := security.HashEmail(s.cfg.HMACPepper, normEmail)
	encEmail, err := security.EncryptAtRest(s.cfg.MasterKey, []byte(normEmail), "users.email")
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	encName, err := security.EncryptAtRest(s.cfg.MasterKey, []byte(strings.TrimSpace(displayName)), "users.display_name")
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}

	uid := uuid.New()
	var created time.Time
	err = db.WithAdminBypassRLS(ctx, s.pool, func(tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, `
			INSERT INTO users (id, email_hash, email_encrypted, display_name_encrypted, auth_provider, profile_completed)
			VALUES ($1, $2, $3, $4, 'email_otp', FALSE)
			RETURNING created_at
		`, uid, emailHash, encEmail, encName).Scan(&created); err != nil {
			return err
		}
		_, _ = tx.Exec(ctx, `
			INSERT INTO admin_audit_logs (action_type, target_user_id) VALUES ('admin_add_user', $1)
		`, uid)
		return nil
	})
	if err != nil {
		return nil, http.StatusConflict, err
	}
	return &AdminUserDTO{
		UserID:           uid.String(),
		Email:            normEmail,
		FullName:         strings.TrimSpace(displayName),
		AuthProvider:     "email_otp",
		ProfileCompleted: false,
		CreatedAt:        created.UnixMilli(),
	}, http.StatusCreated, nil
}

func (s *Service) AdminRemoveUser(ctx context.Context, userID uuid.UUID) (int, error) {
	err := db.WithAdminBypassRLS(ctx, s.pool, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `DELETE FROM users WHERE id = $1`, userID)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return errors.New("user not found")
		}
		_, _ = tx.Exec(ctx, `
			INSERT INTO admin_audit_logs (action_type, target_user_id) VALUES ('admin_remove_user', $1)
		`, userID)
		return nil
	})
	if err != nil {
		return http.StatusNotFound, err
	}
	return http.StatusOK, nil
}

func (s *Service) AdminRemoveVideo(ctx context.Context, mediaID uuid.UUID) (int, error) {
	var storedKey, thumbKey string
	err := db.WithAdminBypassRLS(ctx, s.pool, func(tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, `
			SELECT stored_object_key, thumbnail_object_key FROM post_media WHERE id = $1
		`, mediaID).Scan(&storedKey, &thumbKey); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `DELETE FROM post_media WHERE id = $1`, mediaID)
		if err != nil {
			return err
		}
		_, _ = tx.Exec(ctx, `
			INSERT INTO admin_audit_logs (action_type, target_media_id) VALUES ('admin_remove_video', $1)
		`, mediaID)
		return nil
	})
	if err != nil {
		return http.StatusNotFound, err
	}
	if storedKey != "" {
		if p, err := media.ConfineStoragePath(s.cfg.MediaStorageDir, storedKey); err == nil {
			_ = os.Remove(p)
		}
	}
	if thumbKey != "" {
		if p, err := media.ConfineStoragePath(s.cfg.MediaStorageDir, thumbKey); err == nil {
			_ = os.Remove(p)
		}
	}
	return http.StatusOK, nil
}

func (s *Service) AdminSanitizeVideo(ctx context.Context, mediaID uuid.UUID) (*UploadedVideoDTO, int, error) {
	var storedKey string
	err := db.WithAdminBypassRLS(ctx, s.pool, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `SELECT stored_object_key FROM post_media WHERE id = $1 AND media_kind = 'video'`, mediaID).Scan(&storedKey)
	})
	if err != nil {
		return nil, http.StatusNotFound, err
	}
	srcPath, err := media.ConfineStoragePath(s.cfg.MediaStorageDir, storedKey)
	if err != nil {
		return nil, http.StatusBadRequest, err
	}
	info, err := os.Stat(srcPath)
	if err != nil {
		return nil, http.StatusNotFound, err
	}

	opts := media.VideoSanitizeOptions{
		MediaStorageBaseDir: s.cfg.MediaStorageDir,
		RenamedVideoFile:    "vid_sanitized_" + mediaID.String() + ".mp4",
		RenamedThumbFile:    "thumb_sanitized_" + mediaID.String() + ".jpg",
	}
	res, err := media.SanitizeVideoInIsolation(ctx, srcPath, info.Size(), s.cfg.HMACPepper, opts)
	if err != nil {
		return nil, http.StatusBadRequest, err
	}
	qualitiesJSON, _ := json.Marshal(res.Qualities)

	err = db.WithAdminBypassRLS(ctx, s.pool, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `
			UPDATE post_media
			SET renamed_filename = $2,
			    stored_object_key = $3,
			    byte_size = $4,
			    width = $5,
			    height = $6,
			    duration_ms = $7,
			    content_id = $8,
			    audio_fingerprint_hash = $9,
			    thumbnail_object_key = $10,
			    thumbnail_fingerprint_hash = $11,
			    qualities_json = $12::jsonb,
			    sanitized_at = NOW()
			WHERE id = $1
		`, mediaID, res.RenamedVideoFilename, res.PrimaryObjectKey, res.ByteSize, res.Width, res.Height,
			res.DurationMs, res.ContentID, res.AudioFingerprintHash, res.ThumbnailObjectKey,
			res.ThumbnailFingerprint, string(qualitiesJSON)); err != nil {
			return err
		}
		_, _ = tx.Exec(ctx, `DELETE FROM media_frame_fingerprints WHERE media_id = $1`, mediaID)
		for _, fr := range res.FrameFingerprints {
			if _, err := tx.Exec(ctx, `
				INSERT INTO media_frame_fingerprints (media_id, stream_kind, frame_index, timestamp_ms, perceptual_dhash, sha256_hash)
				VALUES ($1, $2, $3, $4, $5, $6)
			`, mediaID, fr.StreamKind, fr.FrameIndex, fr.TimestampMs, fr.PerceptualDHash, fr.Sha256Hex); err != nil {
				return err
			}
		}
		_, _ = tx.Exec(ctx, `
			INSERT INTO admin_audit_logs (action_type, target_media_id) VALUES ('admin_sanitize_video', $1)
		`, mediaID)
		return nil
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}

	return &UploadedVideoDTO{
		MediaID:              mediaID.String(),
		RenamedFilename:      res.RenamedVideoFilename,
		ContentID:            res.ContentID,
		ThumbnailObjectKey:   res.ThumbnailObjectKey,
		ThumbnailFingerprint: res.ThumbnailFingerprint,
		AudioFingerprintHash: res.AudioFingerprintHash,
		Width:                res.Width,
		Height:               res.Height,
		DurationMs:           res.DurationMs,
		FrameCount:           len(res.FrameFingerprints),
		Qualities:            res.Qualities,
	}, http.StatusOK, nil
}

func (s *Service) notifyErlangPostEvent(authorID, postID uuid.UUID) {
	if s.cfg.ErlangRouterURL == "" {
		return
	}
	payload, _ := json.Marshal(map[string]string{
		"event":     "post_created",
		"author_id": authorID.String(),
		"post_id":   postID.String(),
	})
	req, err := http.NewRequest(http.MethodPost, strings.TrimRight(s.cfg.ErlangRouterURL, "/")+"/internal/events", bytes.NewReader(payload))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/json")
	go func() {
		resp, err := s.http.Do(req)
		if err == nil {
			_ = resp.Body.Close()
		}
	}()
}

func normalizeHashtag(raw string) string {
	cleaned := strings.TrimSpace(strings.TrimPrefix(strings.ToLower(raw), "#"))
	cleaned = validHashtagRe.ReplaceAllString(cleaned, "")
	if len(cleaned) > 64 {
		cleaned = cleaned[:64]
	}
	return cleaned
}

func strconvFormatInt64(v int64) string {
	if v == 0 {
		return "0"
	}
	neg := v < 0
	if neg {
		v = -v
	}
	var buf [24]byte
	i := len(buf)
	for v > 0 {
		i--
		buf[i] = byte('0' + v%10)
		v /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}
