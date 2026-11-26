package feed

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"math"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
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

const signedURLTTL = 15 * time.Minute

type Service struct {
	cfg  *config.Config
	pool *pgxpool.Pool
}

func NewService(cfg *config.Config, pool *pgxpool.Pool) *Service {
	return &Service{cfg: cfg, pool: pool}
}

type StreamVariantDTO struct {
	QualityLabel string `json:"quality_label"`
	Width        int    `json:"width"`
	Height       int    `json:"height"`
	BitrateKbps  int    `json:"bitrate_kbps"`
	Codec        string `json:"codec"`
	Container    string `json:"container"`
	SignedURL    string `json:"signed_url"`
}

type AudioSummaryDTO struct {
	AudioID         string `json:"audio_id"`
	ExternalTrackID string `json:"external_track_id"`
	Title           string `json:"title"`
	Artist          string `json:"artist"`
	ArtworkURL      string `json:"artwork_url"`
	PreviewURL      string `json:"preview_url"`
	DurationMs      int64  `json:"duration_ms"`
	IsOriginal      bool   `json:"is_original"`
	UsageCount      int64  `json:"usage_count"`
}

type FeedVideoDTO struct {
	VideoID             string             `json:"video_id"`
	PostID              string             `json:"post_id"`
	CreatorID           string             `json:"creator_id"`
	CreatorName         string             `json:"creator_name"`
	CreatorUsername     string             `json:"creator_username"`
	CreatorAvatarHash   string             `json:"creator_avatar_hash"`
	IsFollowingCreator  bool               `json:"is_following_creator"`
	IsOwner             bool               `json:"is_owner"`
	Title               string             `json:"title"`
	Description         string             `json:"description"`
	RecommendationLabel string             `json:"recommendation_label"`
	OriginalWidth       int                `json:"original_width"`
	OriginalHeight      int                `json:"original_height"`
	AspectRatio         float64            `json:"aspect_ratio"`
	DurationMs          int64              `json:"duration_ms"`
	Codec               string             `json:"codec"`
	FileSize            int64              `json:"file_size"`
	Visibility          string             `json:"visibility"`
	ThumbnailURL        string             `json:"thumbnail_url"`
	StreamURL           string             `json:"stream_url"`
	FallbackMP4URL      string             `json:"fallback_mp4_url"`
	StreamType          string             `json:"stream_type"` // hls | mp4
	URLExpiresAt        int64              `json:"url_expires_at"`
	Variants            []StreamVariantDTO `json:"variants"`
	Audio               AudioSummaryDTO    `json:"audio"`
	Hashtags            []string           `json:"hashtags"`
	LikesCount          int64              `json:"likes_count"`
	CommentsCount       int64              `json:"comments_count"`
	SharesCount         int64              `json:"shares_count"`
	SavesCount          int64              `json:"saves_count"`
	RepostsCount        int64              `json:"reposts_count"`
	ViewsCount          int64              `json:"views_count"`
	IsLiked             bool               `json:"is_liked"`
	IsSaved             bool               `json:"is_saved"`
	IsReposted          bool               `json:"is_reposted"`
	CreatedAt           int64              `json:"created_at"`
}

type FeedPageDTO struct {
	Videos     []FeedVideoDTO `json:"videos"`
	NextCursor string         `json:"next_cursor"`
	HasMore    bool           `json:"has_more"`
}

type RefreshedStreamDTO struct {
	VideoID        string             `json:"video_id"`
	StreamURL      string             `json:"stream_url"`
	FallbackMP4URL string             `json:"fallback_mp4_url"`
	ThumbnailURL   string             `json:"thumbnail_url"`
	StreamType     string             `json:"stream_type"`
	URLExpiresAt   int64              `json:"url_expires_at"`
	Variants       []StreamVariantDTO `json:"variants"`
}

type HashtagDiscoveryDTO struct {
	Tag        string         `json:"tag"`
	VideoCount int64          `json:"video_count"`
	ViewsCount int64          `json:"views_count"`
	Videos     []FeedVideoDTO `json:"videos"`
	NextCursor string         `json:"next_cursor"`
	HasMore    bool           `json:"has_more"`
}

type AudioDiscoveryDTO struct {
	Audio      AudioSummaryDTO `json:"audio"`
	Videos     []FeedVideoDTO  `json:"videos"`
	NextCursor string          `json:"next_cursor"`
	HasMore    bool            `json:"has_more"`
}

type CreatorSearchDTO struct {
	UserID            string `json:"user_id"`
	FullName          string `json:"full_name"`
	Username          string `json:"username"`
	AvatarFingerprint string `json:"avatar_fingerprint_hash"`
	IsFollowing       bool   `json:"is_following"`
}

type HashtagStatsDTO struct {
	Tag       string `json:"tag"`
	PostCount int64  `json:"post_count"`
}

type RecentSearchDTO struct {
	ID    string `json:"id"`
	Query string `json:"query"`
}

type FeedSearchResponseDTO struct {
	Query          string            `json:"query"`
	Videos         []FeedVideoDTO    `json:"videos"`
	Hashtags       []HashtagStatsDTO `json:"hashtags"`
	Creators       []CreatorSearchDTO `json:"creators"`
	Audios         []AudioSummaryDTO `json:"audios"`
	RecentSearches []RecentSearchDTO `json:"recent_searches"`
	Trending       []string          `json:"trending"`
	NextCursor     string            `json:"next_cursor"`
	HasMore        bool              `json:"has_more"`
}

type SafetyUserDTO struct {
	UserID            string `json:"user_id"`
	FullName          string `json:"full_name"`
	Username          string `json:"username"`
	AvatarFingerprint string `json:"avatar_fingerprint_hash"`
}

type SafetyPreferencesDTO struct {
	MutedUsers   []SafetyUserDTO `json:"muted_users"`
	BlockedUsers []SafetyUserDTO `json:"blocked_users"`
}

type creatorProjection struct {
	UserID            uuid.UUID
	FullName          string
	Username          string
	AvatarFingerprint string
	IsFollowing       bool
}

type signedTokenPayload struct {
	VideoID string `json:"v"`
	UserID  string `json:"u"`
	Scope   string `json:"s"`
	Exp     int64  `json:"e"`
}

type candidateVideo struct {
	dto             FeedVideoDTO
	createdTime     time.Time
	avgCompletion   float64
	watchedPct      float64
	primaryHashtag  string
	creatorUUID     uuid.UUID
	audioUUID       uuid.UUID
	score           float64
}

func (s *Service) signMediaToken(videoID, viewerID uuid.UUID, scope string, expiresAt time.Time) string {
	payload := signedTokenPayload{
		VideoID: videoID.String(),
		UserID:  viewerID.String(),
		Scope:   scope,
		Exp:     expiresAt.Unix(),
	}
	raw, _ := json.Marshal(payload)
	b64 := base64.RawURLEncoding.EncodeToString(raw)
	mac := hmac.New(sha256.New, s.cfg.HMACPepper)
	mac.Write([]byte(b64))
	sig := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	return b64 + "." + sig
}

func (s *Service) verifyMediaToken(token string) (*signedTokenPayload, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 2 {
		return nil, errors.New("invalid token format")
	}
	mac := hmac.New(sha256.New, s.cfg.HMACPepper)
	mac.Write([]byte(parts[0]))
	expectedSig := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	if len(parts[1]) != len(expectedSig) || subtle.ConstantTimeCompare([]byte(parts[1]), []byte(expectedSig)) != 1 {
		return nil, errors.New("invalid token signature")
	}
	decoded, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return nil, err
	}
	var payload signedTokenPayload
	if err := json.Unmarshal(decoded, &payload); err != nil {
		return nil, err
	}
	if payload.Exp <= time.Now().UTC().Unix() {
		return nil, errors.New("signed url expired")
	}
	return &payload, nil
}

func signedMediaURL(token, objectKey string) string {
	clean := strings.TrimLeft(strings.TrimSpace(objectKey), "/")
	if clean == "" || token == "" {
		return ""
	}
	return "/v1/media/signed/" + token + "/" + clean
}

func (s *Service) ServeSignedMedia(w http.ResponseWriter, r *http.Request, token, relObjectKey string) {
	payload, err := s.verifyMediaToken(strings.TrimSpace(token))
	if err != nil {
		http.Error(w, "Error has occurred, try again later.", http.StatusUnauthorized)
		return
	}
	vid, err := uuid.Parse(payload.VideoID)
	if err != nil {
		http.Error(w, "Error has occurred, try again later.", http.StatusForbidden)
		return
	}
	uid, err := uuid.Parse(payload.UserID)
	if err != nil {
		http.Error(w, "Error has occurred, try again later.", http.StatusForbidden)
		return
	}

	cleanedRel := filepath.ToSlash(filepath.Clean("/" + relObjectKey))
	cleanedRel = strings.TrimPrefix(cleanedRel, "/")
	if cleanedRel == "" || strings.Contains(cleanedRel, "..") {
		http.Error(w, "Error has occurred, try again later.", http.StatusBadRequest)
		return
	}

	var authorized bool
	err = db.WithUserRLS(r.Context(), s.pool, uid, func(tx pgx.Tx) error {
		var thumbKey, hlsMaster, primaryKey string
		if err := tx.QueryRow(r.Context(), `
			SELECT thumbnail_object_key, hls_master_object_key, primary_object_key
			FROM videos WHERE id = $1
		`, vid).Scan(&thumbKey, &hlsMaster, &primaryKey); err != nil {
			return err
		}
		if payload.Scope == "thumb" {
			if cleanedRel == strings.TrimPrefix(thumbKey, "/") {
				authorized = true
			}
			return nil
		}
		if cleanedRel == strings.TrimPrefix(primaryKey, "/") || cleanedRel == strings.TrimPrefix(hlsMaster, "/") {
			authorized = true
			return nil
		}
		if hlsMaster != "" {
			hlsDir := filepath.ToSlash(filepath.Dir(strings.TrimPrefix(hlsMaster, "/")))
			if hlsDir != "." && strings.HasPrefix(cleanedRel, hlsDir+"/") {
				authorized = true
				return nil
			}
		}
		var variantMatch bool
		_ = tx.QueryRow(r.Context(), `
			SELECT EXISTS(
				SELECT 1 FROM video_stream_variants
				WHERE video_id = $1 AND (playlist_object_key = $2 OR mp4_object_key = $2)
			)
		`, vid, cleanedRel).Scan(&variantMatch)
		authorized = variantMatch
		return nil
	})
	if err != nil || !authorized {
		http.Error(w, "Error has occurred, try again later.", http.StatusForbidden)
		return
	}

	absPath, err := media.ConfineStoragePath(s.cfg.MediaStorageDir, cleanedRel)
	if err != nil {
		http.Error(w, "Error has occurred, try again later.", http.StatusForbidden)
		return
	}
	f, err := os.Open(absPath)
	if err != nil {
		http.Error(w, "Error has occurred, try again later.", http.StatusNotFound)
		return
	}
	defer func() { _ = f.Close() }()

	stat, err := f.Stat()
	if err != nil || stat.IsDir() {
		http.Error(w, "Error has occurred, try again later.", http.StatusNotFound)
		return
	}

	ext := strings.ToLower(filepath.Ext(absPath))
	ct := mime.TypeByExtension(ext)
	switch ext {
	case ".m3u8":
		ct = "application/vnd.apple.mpegurl"
	case ".ts":
		ct = "video/mp2t"
	case ".mp4":
		ct = "video/mp4"
	case ".mpd":
		ct = "application/dash+xml"
	case ".jpg", ".jpeg":
		ct = "image/jpeg"
	}
	if ct != "" {
		w.Header().Set("Content-Type", ct)
	}
	w.Header().Set("Cache-Control", "private, max-age=300")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	http.ServeContent(w, r, filepath.Base(absPath), stat.ModTime(), f)
}

func (s *Service) loadCreatorMap(ctx context.Context, tx pgx.Tx, viewerID uuid.UUID) (map[uuid.UUID]creatorProjection, error) {
	rows, err := tx.Query(ctx, `
		SELECT user_id, full_name_encrypted, username_encrypted, display_name_encrypted,
		       COALESCE(avatar_fingerprint_hash, ''), is_following
		FROM telefam_get_video_creators($1)
	`, viewerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make(map[uuid.UUID]creatorProjection)
	for rows.Next() {
		var uid uuid.UUID
		var encFull, encUser, encDisplay []byte
		var avatarFP string
		var isFollowing bool
		if err := rows.Scan(&uid, &encFull, &encUser, &encDisplay, &avatarFP, &isFollowing); err != nil {
			return nil, err
		}
		fullName := s.decryptName(encFull, encDisplay)
		usernameBytes, _ := security.DecryptAtRest(s.cfg.MasterKey, encUser, "profiles.username")
		username := strings.TrimSpace(string(usernameBytes))
		if username == "" && fullName != "" {
			username = strings.ToLower(strings.ReplaceAll(fullName, " ", "."))
		}
		out[uid] = creatorProjection{
			UserID:            uid,
			FullName:          fullName,
			Username:          username,
			AvatarFingerprint: strings.TrimSpace(avatarFP),
			IsFollowing:       isFollowing,
		}
	}
	return out, rows.Err()
}

func (s *Service) decryptName(encFull, encDisplay []byte) string {
	if len(encFull) > 0 {
		if b, err := security.DecryptAtRest(s.cfg.MasterKey, encFull, "profiles.full_name"); err == nil && len(b) > 0 {
			return strings.TrimSpace(string(b))
		}
	}
	if len(encDisplay) > 0 {
		if b, err := security.DecryptAtRest(s.cfg.MasterKey, encDisplay, "users.display_name"); err == nil && len(b) > 0 {
			return strings.TrimSpace(string(b))
		}
	}
	return "Telefam Creator"
}

func (s *Service) queryFeedCandidates(
	ctx context.Context,
	tx pgx.Tx,
	viewerID uuid.UUID,
	whereSQL string,
	args ...any,
) ([]candidateVideo, error) {
	creators, err := s.loadCreatorMap(ctx, tx, viewerID)
	if err != nil {
		return nil, err
	}

	sqlQuery := `
		SELECT v.id, COALESCE(v.post_id::text, ''), v.creator_id, COALESCE(v.audio_id::text, ''),
		       v.title_encrypted, v.description_encrypted,
		       v.original_width, v.original_height, v.aspect_ratio, v.duration_ms,
		       v.codec, v.file_size, v.visibility,
		       v.thumbnail_object_key, v.hls_master_object_key, v.primary_object_key,
		       v.likes_count, v.comments_count, v.shares_count, v.saves_count, v.reposts_count,
		       v.views_count, v.avg_completion_rate, v.created_at,
		       COALESCE(a.external_track_id, ''), COALESCE(a.title_encrypted, ''::bytea),
		       COALESCE(a.artist_encrypted, ''::bytea), COALESCE(a.artwork_url, ''),
		       COALESCE(a.preview_url, ''), COALESCE(a.duration_ms, 0), COALESCE(a.is_original, TRUE),
		       COALESCE(a.usage_count, 0),
		       EXISTS(SELECT 1 FROM video_likes vl WHERE vl.video_id = v.id AND vl.user_id = $1) AS is_liked,
		       EXISTS(SELECT 1 FROM saved_videos sv WHERE sv.video_id = v.id AND sv.user_id = $1) AS is_saved,
		       EXISTS(SELECT 1 FROM reposts r WHERE r.video_id = v.id AND r.user_id = $1) AS is_reposted,
		       COALESCE((SELECT wh.max_watch_pct FROM watch_history wh WHERE wh.viewer_id = $1 AND wh.video_id = v.id), 0.0) AS watched_pct
		FROM videos v
		LEFT JOIN audios a ON a.id = v.audio_id
		WHERE v.processing_status = 'ready'
	` + whereSQL + `
		ORDER BY v.created_at DESC
		LIMIT 200
	`

	allArgs := append([]any{viewerID}, args...)
	rows, err := tx.Query(ctx, sqlQuery, allArgs...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	expiresAt := time.Now().UTC().Add(signedURLTTL)
	candidates := make([]candidateVideo, 0, 64)
	videoIDs := make([]uuid.UUID, 0, 64)

	for rows.Next() {
		var vid, creatorID uuid.UUID
		var postIDStr, audioIDStr, codec, visibility string
		var thumbKey, hlsMasterKey, primaryKey string
		var extTrackID, artworkURL, previewURL string
		var encTitle, encDesc, encAudioTitle, encAudioArtist []byte
		var origW, origH int
		var durMs, fileSize, audioDurMs, audioUsage int64
		var likesCnt, commentsCnt, sharesCnt, savesCnt, repostsCnt, viewsCnt int64
		var aspectRatio, avgCompletion, watchedPct float64
		var isOrigAudio, isLiked, isSaved, isReposted bool
		var createdAt time.Time

		if err := rows.Scan(
			&vid, &postIDStr, &creatorID, &audioIDStr,
			&encTitle, &encDesc,
			&origW, &origH, &aspectRatio, &durMs,
			&codec, &fileSize, &visibility,
			&thumbKey, &hlsMasterKey, &primaryKey,
			&likesCnt, &commentsCnt, &sharesCnt, &savesCnt, &repostsCnt,
			&viewsCnt, &avgCompletion, &createdAt,
			&extTrackID, &encAudioTitle, &encAudioArtist, &artworkURL,
			&previewURL, &audioDurMs, &isOrigAudio, &audioUsage,
			&isLiked, &isSaved, &isReposted, &watchedPct,
		); err != nil {
			return nil, err
		}

		titleBytes, _ := security.DecryptAtRest(s.cfg.MasterKey, encTitle, "posts.body")
		descBytes, _ := security.DecryptAtRest(s.cfg.MasterKey, encDesc, "posts.body")
		audioTitleBytes, _ := security.DecryptAtRest(s.cfg.MasterKey, encAudioTitle, "audios.title")
		audioArtistBytes, _ := security.DecryptAtRest(s.cfg.MasterKey, encAudioArtist, "audios.artist")

		audioTitle := strings.TrimSpace(string(audioTitleBytes))
		if audioTitle == "" {
			audioTitle = "Original sound"
		}

		streamToken := s.signMediaToken(vid, viewerID, "stream", expiresAt)
		thumbToken := s.signMediaToken(vid, viewerID, "thumb", expiresAt)

		thumbURL := signedMediaURL(thumbToken, thumbKey)
		mp4URL := signedMediaURL(streamToken, primaryKey)
		hlsURL := signedMediaURL(streamToken, hlsMasterKey)
		streamURL := mp4URL
		streamType := "mp4"
		if hlsURL != "" {
			if absHLS, aErr := media.ConfineStoragePath(s.cfg.MediaStorageDir, hlsMasterKey); aErr == nil {
				if _, statErr := os.Stat(absHLS); statErr == nil {
					streamURL = hlsURL
					streamType = "hls"
				}
			}
		}

		creator := creators[creatorID]
		if creator.UserID == uuid.Nil {
			creator = creatorProjection{
				UserID:   creatorID,
				FullName: "Telefam Creator",
				Username: "creator",
			}
		}

		audioUUID, _ := uuid.Parse(audioIDStr)
		dto := FeedVideoDTO{
			VideoID:            vid.String(),
			PostID:             postIDStr,
			CreatorID:          creatorID.String(),
			CreatorName:        creator.FullName,
			CreatorUsername:    creator.Username,
			CreatorAvatarHash:  creator.AvatarFingerprint,
			IsFollowingCreator: creator.IsFollowing,
			IsOwner:            creatorID == viewerID,
			Title:              string(titleBytes),
			Description:        string(descBytes),
			OriginalWidth:      origW,
			OriginalHeight:     origH,
			AspectRatio:        aspectRatio,
			DurationMs:         durMs,
			Codec:              codec,
			FileSize:           fileSize,
			Visibility:         visibility,
			ThumbnailURL:       thumbURL,
			StreamURL:          streamURL,
			FallbackMP4URL:     mp4URL,
			StreamType:         streamType,
			URLExpiresAt:       expiresAt.UnixMilli(),
			Variants:           []StreamVariantDTO{},
			Audio: AudioSummaryDTO{
				AudioID:         audioIDStr,
				ExternalTrackID: extTrackID,
				Title:           audioTitle,
				Artist:          string(audioArtistBytes),
				ArtworkURL:      artworkURL,
				PreviewURL:      previewURL,
				DurationMs:      audioDurMs,
				IsOriginal:      isOrigAudio,
				UsageCount:      audioUsage,
			},
			Hashtags:      []string{},
			LikesCount:    likesCnt,
			CommentsCount: commentsCnt,
			SharesCount:   sharesCnt,
			SavesCount:    savesCnt,
			RepostsCount:  repostsCnt,
			ViewsCount:    viewsCnt,
			IsLiked:       isLiked,
			IsSaved:       isSaved,
			IsReposted:    isReposted,
			CreatedAt:     createdAt.UnixMilli(),
		}

		candidates = append(candidates, candidateVideo{
			dto:           dto,
			createdTime:   createdAt,
			avgCompletion: avgCompletion,
			watchedPct:    watchedPct,
			creatorUUID:   creatorID,
			audioUUID:     audioUUID,
		})
		videoIDs = append(videoIDs, vid)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	if len(videoIDs) > 0 {
		idxByID := make(map[uuid.UUID]int, len(videoIDs))
		for idx, id := range videoIDs {
			idxByID[id] = idx
		}

		// Batch fetch hashtags
		tagRows, tErr := tx.Query(ctx, `
			SELECT video_id, tag_normalized FROM video_hashtags WHERE video_id = ANY($1)
		`, videoIDs)
		if tErr == nil {
			for tagRows.Next() {
				var vid uuid.UUID
				var tag string
				if err := tagRows.Scan(&vid, &tag); err == nil {
					if i, ok := idxByID[vid]; ok {
						candidates[i].dto.Hashtags = append(candidates[i].dto.Hashtags, tag)
						if candidates[i].primaryHashtag == "" {
							candidates[i].primaryHashtag = tag
						}
					}
				}
			}
			tagRows.Close()
		}

		// Batch fetch adaptive variants
		varRows, vErr := tx.Query(ctx, `
			SELECT video_id, quality_label, width, height, bitrate_kbps, codec, container,
			       playlist_object_key, mp4_object_key
			FROM video_stream_variants
			WHERE video_id = ANY($1)
			ORDER BY bitrate_kbps ASC
		`, videoIDs)
		if vErr == nil {
			for varRows.Next() {
				var vid uuid.UUID
				var qLabel, vCodec, container, plKey, mp4Key string
				var w, h, kbps int
				if err := varRows.Scan(&vid, &qLabel, &w, &h, &kbps, &vCodec, &container, &plKey, &mp4Key); err == nil {
					if i, ok := idxByID[vid]; ok {
						token := s.signMediaToken(vid, viewerID, "stream", expiresAt)
						objKey := mp4Key
						if container == "hls" && plKey != "" {
							objKey = plKey
						}
						candidates[i].dto.Variants = append(candidates[i].dto.Variants, StreamVariantDTO{
							QualityLabel: qLabel,
							Width:        w,
							Height:       h,
							BitrateKbps:  kbps,
							Codec:        vCodec,
							Container:    container,
							SignedURL:    signedMediaURL(token, objKey),
						})
					}
				}
			}
			varRows.Close()
		}
	}

	return candidates, nil
}

func (s *Service) GetForYouFeed(ctx context.Context, viewerID uuid.UUID, cursorStr string, limit int) (*FeedPageDTO, int, error) {
	if limit <= 0 || limit > 30 {
		limit = 15
	}
	offset := parseCursor(cursorStr)

	var candidates []candidateVideo
	hashtagAffinity := make(map[string]float64)
	audioAffinity := make(map[string]float64)
	creatorAffinity := make(map[string]float64)

	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		iRows, iErr := tx.Query(ctx, `
			SELECT interest_kind, interest_key, affinity_score
			FROM user_interests WHERE user_id = $1
			ORDER BY affinity_score DESC LIMIT 120
		`, viewerID)
		if iErr == nil {
			for iRows.Next() {
				var kind, key string
				var score float64
				if err := iRows.Scan(&kind, &key, &score); err == nil {
					switch kind {
					case "hashtag":
						hashtagAffinity[key] = score
					case "audio":
						audioAffinity[key] = score
					case "creator":
						creatorAffinity[key] = score
					}
				}
			}
			iRows.Close()
		}

		var qErr error
		candidates, qErr = s.queryFeedCandidates(ctx, tx, viewerID, `
			AND NOT EXISTS (
				SELECT 1 FROM muted_users m WHERE m.user_id = $1 AND m.muted_user_id = v.creator_id
			)
			AND NOT EXISTS (
				SELECT 1 FROM recommendation_events re
				WHERE re.user_id = $1 AND re.video_id = v.id AND re.event_type = 'not_interested'
			)
		`)
		return qErr
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}

	now := time.Now().UTC()
	hourBucket := strconv.FormatInt(now.Unix()/3600, 10)
	for i := range candidates {
		c := &candidates[i]
		views := float64(c.dto.ViewsCount)
		denom := math.Max(1.0, views)
		likeRate := float64(c.dto.LikesCount) / denom
		shareRate := float64(c.dto.SharesCount) / denom
		saveRate := float64(c.dto.SavesCount) / denom
		repostRate := float64(c.dto.RepostsCount) / denom

		engagementScore := math.Log1p(views)*0.65 +
			(c.avgCompletion/100.0)*3.2 +
			likeRate*2.8 +
			shareRate*4.5 +
			saveRate*4.0 +
			repostRate*3.4

		interestBoost := 0.0
		for _, tag := range c.dto.Hashtags {
			interestBoost += math.Min(4.0, hashtagAffinity[tag]*0.45)
		}
		if c.dto.Audio.AudioID != "" {
			interestBoost += math.Min(3.5, audioAffinity[c.dto.Audio.AudioID]*0.55)
		}
		interestBoost += math.Min(3.5, creatorAffinity[c.dto.CreatorID]*0.5)

		ageHours := math.Max(0.0, now.Sub(c.createdTime).Hours())
		freshnessFactor := 1.0 / (1.0 + (ageHours / 48.0))

		// Deterministic exploration noise per viewer+video+hour so feed is non-chronological and fresh
		noise := deterministicUnitFloat(viewerID.String()+"|"+c.dto.VideoID+"|"+hourBucket) * 1.15

		watchedPenalty := 0.0
		if c.watchedPct >= 80.0 {
			watchedPenalty = 5.5
		} else if c.watchedPct >= 25.0 {
			watchedPenalty = 2.0
		}

		c.score = (engagementScore + interestBoost + noise) * (0.45 + 0.55*freshnessFactor) - watchedPenalty
		if !c.dto.IsFollowingCreator && !c.dto.IsOwner && (interestBoost > 0.25 || engagementScore > 1.2) {
			c.dto.RecommendationLabel = "You might like this"
		}
	}

	sort.SliceStable(candidates, func(i, j int) bool {
		return candidates[i].score > candidates[j].score
	})

	diverse := diversifyCandidates(candidates)
	return sliceFeedPage(diverse, offset, limit), http.StatusOK, nil
}

func (s *Service) GetFollowingFeed(ctx context.Context, viewerID uuid.UUID, cursorStr string, limit int) (*FeedPageDTO, int, error) {
	if limit <= 0 || limit > 30 {
		limit = 15
	}
	offset := parseCursor(cursorStr)

	var candidates []candidateVideo
	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		var qErr error
		candidates, qErr = s.queryFeedCandidates(ctx, tx, viewerID, `
			AND (
				v.creator_id = $1
				OR EXISTS (
					SELECT 1 FROM user_follows uf
					WHERE uf.follower_id = $1 AND uf.followee_id = v.creator_id
				)
			)
			AND NOT EXISTS (
				SELECT 1 FROM muted_users m WHERE m.user_id = $1 AND m.muted_user_id = v.creator_id
			)
		`)
		return qErr
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}

	now := time.Now().UTC()
	for i := range candidates {
		c := &candidates[i]
		ageHours := math.Max(0.0, now.Sub(c.createdTime).Hours())
		unwatchedBonus := 0.0
		if c.watchedPct < 20.0 {
			unwatchedBonus = 2.5
		}
		c.score = unwatchedBonus + math.Log1p(float64(c.dto.LikesCount))*0.4 + (3.0 / (1.0 + ageHours/24.0))
	}
	sort.SliceStable(candidates, func(i, j int) bool {
		return candidates[i].score > candidates[j].score
	})
	return sliceFeedPage(candidates, offset, limit), http.StatusOK, nil
}

func (s *Service) RefreshStreamURL(ctx context.Context, viewerID, videoID uuid.UUID) (*RefreshedStreamDTO, int, error) {
	var dto *RefreshedStreamDTO
	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		list, err := s.queryFeedCandidates(ctx, tx, viewerID, `AND v.id = $2`, videoID)
		if err != nil || len(list) == 0 {
			return errors.New("not found")
		}
		v := list[0].dto
		dto = &RefreshedStreamDTO{
			VideoID:        v.VideoID,
			StreamURL:      v.StreamURL,
			FallbackMP4URL: v.FallbackMP4URL,
			ThumbnailURL:   v.ThumbnailURL,
			StreamType:     v.StreamType,
			URLExpiresAt:   v.URLExpiresAt,
			Variants:       v.Variants,
		}
		return nil
	})
	if err != nil || dto == nil {
		return nil, http.StatusNotFound, errors.New("video unavailable")
	}
	return dto, http.StatusOK, nil
}

func (s *Service) GetHashtagDiscovery(ctx context.Context, viewerID uuid.UUID, rawTag, cursorStr string, limit int) (*HashtagDiscoveryDTO, int, error) {
	normTag := normalizeTag(rawTag)
	if normTag == "" {
		return nil, http.StatusBadRequest, errors.New("invalid hashtag")
	}
	if limit <= 0 || limit > 40 {
		limit = 21
	}
	offset := parseCursor(cursorStr)

	var candidates []candidateVideo
	var totalViews, postCount int64
	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		_ = tx.QueryRow(ctx, `SELECT COALESCE(post_count, 0) FROM hashtags WHERE tag_normalized = $1`, normTag).Scan(&postCount)
		var qErr error
		candidates, qErr = s.queryFeedCandidates(ctx, tx, viewerID, `
			AND EXISTS (
				SELECT 1 FROM video_hashtags vh WHERE vh.video_id = v.id AND vh.tag_normalized = $2
			)
		`, normTag)
		if qErr != nil {
			return qErr
		}
		for _, c := range candidates {
			totalViews += c.dto.ViewsCount
		}
		if offset == 0 {
			s.bumpInterestTx(ctx, tx, viewerID, nil, "hashtag_tap", 1.2, "hashtag", normTag)
		}
		return nil
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}

	sort.SliceStable(candidates, func(i, j int) bool {
		scoreI := float64(candidates[i].dto.ViewsCount+candidates[i].dto.LikesCount*3) + float64(candidates[i].dto.CreatedAt)/1e12
		scoreJ := float64(candidates[j].dto.ViewsCount+candidates[j].dto.LikesCount*3) + float64(candidates[j].dto.CreatedAt)/1e12
		return scoreI > scoreJ
	})

	effectiveCount := int64(len(candidates))
	if postCount > effectiveCount {
		effectiveCount = postCount
	}
	page := sliceFeedPage(candidates, offset, limit)
	return &HashtagDiscoveryDTO{
		Tag:        normTag,
		VideoCount: effectiveCount,
		ViewsCount: totalViews,
		Videos:     page.Videos,
		NextCursor: page.NextCursor,
		HasMore:    page.HasMore,
	}, http.StatusOK, nil
}

func (s *Service) GetAudioDiscovery(ctx context.Context, viewerID, audioID uuid.UUID, cursorStr string, limit int) (*AudioDiscoveryDTO, int, error) {
	if limit <= 0 || limit > 40 {
		limit = 21
	}
	offset := parseCursor(cursorStr)

	var summary AudioSummaryDTO
	var candidates []candidateVideo
	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		var extID, artwork, preview string
		var encTitle, encArtist []byte
		var durMs, usage int64
		var isOrig bool
		if err := tx.QueryRow(ctx, `
			SELECT COALESCE(external_track_id, ''), title_encrypted, artist_encrypted,
			       COALESCE(artwork_url, ''), COALESCE(preview_url, ''), duration_ms, is_original, usage_count
			FROM audios WHERE id = $1
		`, audioID).Scan(&extID, &encTitle, &encArtist, &artwork, &preview, &durMs, &isOrig, &usage); err != nil {
			return err
		}
		titleB, _ := security.DecryptAtRest(s.cfg.MasterKey, encTitle, "audios.title")
		artistB, _ := security.DecryptAtRest(s.cfg.MasterKey, encArtist, "audios.artist")
		titleStr := strings.TrimSpace(string(titleB))
		if titleStr == "" {
			titleStr = "Original sound"
		}
		summary = AudioSummaryDTO{
			AudioID:         audioID.String(),
			ExternalTrackID: extID,
			Title:           titleStr,
			Artist:          string(artistB),
			ArtworkURL:      artwork,
			PreviewURL:      preview,
			DurationMs:      durMs,
			IsOriginal:      isOrig,
			UsageCount:      usage,
		}

		var qErr error
		candidates, qErr = s.queryFeedCandidates(ctx, tx, viewerID, `AND v.audio_id = $2`, audioID)
		if qErr != nil {
			return qErr
		}
		if offset == 0 {
			s.bumpInterestTx(ctx, tx, viewerID, nil, "audio_tap", 1.4, "audio", audioID.String())
		}
		return nil
	})
	if err != nil {
		return nil, http.StatusNotFound, err
	}

	page := sliceFeedPage(candidates, offset, limit)
	return &AudioDiscoveryDTO{
		Audio:      summary,
		Videos:     page.Videos,
		NextCursor: page.NextCursor,
		HasMore:    page.HasMore,
	}, http.StatusOK, nil
}

func (s *Service) SearchAll(ctx context.Context, viewerID uuid.UUID, rawQuery, cursorStr string, limit int) (*FeedSearchResponseDTO, int, error) {
	q := strings.TrimSpace(rawQuery)
	if len(q) > 80 {
		q = q[:80]
	}
	normQ := strings.ToLower(strings.TrimPrefix(q, "#"))
	if limit <= 0 || limit > 40 {
		limit = 20
	}
	offset := parseCursor(cursorStr)

	resp := &FeedSearchResponseDTO{
		Query:          q,
		Videos:         []FeedVideoDTO{},
		Hashtags:       []HashtagStatsDTO{},
		Creators:       []CreatorSearchDTO{},
		Audios:         []AudioSummaryDTO{},
		RecentSearches: []RecentSearchDTO{},
		Trending:       []string{},
	}

	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		// Record non-empty search into encrypted search history + interest model
		if normQ != "" && offset == 0 {
			if encQ, eErr := security.EncryptAtRest(s.cfg.MasterKey, []byte(q), "search_history.query"); eErr == nil {
				qHash := security.HMACSHA256Hex(s.cfg.HMACPepper, strings.ToLower(q))
				_, _ = tx.Exec(ctx, `
					INSERT INTO user_search_history (user_id, query_encrypted, query_hash, created_at)
					VALUES ($1, $2, $3, NOW())
					ON CONFLICT (user_id, query_hash) DO UPDATE SET
						query_encrypted = EXCLUDED.query_encrypted,
						created_at = NOW()
				`, viewerID, encQ, qHash)
			}
			s.bumpInterestTx(ctx, tx, viewerID, nil, "search_query", 1.1, "keyword", normQ)
		}

		// Load recent searches
		rRows, rErr := tx.Query(ctx, `
			SELECT id, query_encrypted FROM user_search_history
			WHERE user_id = $1 ORDER BY created_at DESC LIMIT 10
		`, viewerID)
		if rErr == nil {
			for rRows.Next() {
				var sid uuid.UUID
				var enc []byte
				if err := rRows.Scan(&sid, &enc); err == nil {
					if pt, dErr := security.DecryptAtRest(s.cfg.MasterKey, enc, "search_history.query"); dErr == nil {
						resp.RecentSearches = append(resp.RecentSearches, RecentSearchDTO{
							ID:    sid.String(),
							Query: string(pt),
						})
					}
				}
			}
			rRows.Close()
		}

		// Trending hashtags & suggestions
		hRows, hErr := tx.Query(ctx, `
			SELECT display_tag, post_count FROM hashtags ORDER BY post_count DESC, tag_normalized ASC LIMIT 30
		`)
		if hErr == nil {
			for hRows.Next() {
				var tag string
				var cnt int64
				if err := hRows.Scan(&tag, &cnt); err == nil {
					clean := strings.TrimPrefix(tag, "#")
					if len(resp.Trending) < 10 {
						resp.Trending = append(resp.Trending, "#"+clean)
					}
					if normQ == "" || strings.Contains(strings.ToLower(clean), normQ) {
						resp.Hashtags = append(resp.Hashtags, HashtagStatsDTO{Tag: clean, PostCount: cnt})
					}
				}
			}
			hRows.Close()
		}

		// Creators
		creators, _ := s.loadCreatorMap(ctx, tx, viewerID)
		for _, c := range creators {
			if c.UserID == viewerID {
				continue
			}
			if normQ == "" ||
				strings.Contains(strings.ToLower(c.FullName), normQ) ||
				strings.Contains(strings.ToLower(c.Username), normQ) {
				resp.Creators = append(resp.Creators, CreatorSearchDTO{
					UserID:            c.UserID.String(),
					FullName:          c.FullName,
					Username:          c.Username,
					AvatarFingerprint: c.AvatarFingerprint,
					IsFollowing:       c.IsFollowing,
				})
				if len(resp.Creators) >= 20 {
					break
				}
			}
		}

		// Audios
		aRows, aErr := tx.Query(ctx, `
			SELECT id, COALESCE(external_track_id, ''), title_encrypted, artist_encrypted,
			       COALESCE(artwork_url, ''), COALESCE(preview_url, ''), duration_ms, is_original, usage_count
			FROM audios ORDER BY usage_count DESC, created_at DESC LIMIT 60
		`)
		if aErr == nil {
			for aRows.Next() {
				var aid uuid.UUID
				var extID, artwork, preview string
				var encT, encA []byte
				var durMs, usage int64
				var isOrig bool
				if err := aRows.Scan(&aid, &extID, &encT, &encA, &artwork, &preview, &durMs, &isOrig, &usage); err == nil {
					tB, _ := security.DecryptAtRest(s.cfg.MasterKey, encT, "audios.title")
					aB, _ := security.DecryptAtRest(s.cfg.MasterKey, encA, "audios.artist")
					tStr := strings.TrimSpace(string(tB))
					aStr := strings.TrimSpace(string(aB))
					if normQ == "" ||
						strings.Contains(strings.ToLower(tStr), normQ) ||
						strings.Contains(strings.ToLower(aStr), normQ) {
						resp.Audios = append(resp.Audios, AudioSummaryDTO{
							AudioID:         aid.String(),
							ExternalTrackID: extID,
							Title:           tStr,
							Artist:          aStr,
							ArtworkURL:      artwork,
							PreviewURL:      preview,
							DurationMs:      durMs,
							IsOriginal:      isOrig,
							UsageCount:      usage,
						})
						if len(resp.Audios) >= 20 {
							break
						}
					}
				}
			}
			aRows.Close()
		}

		// Video results (matched in memory after decryption + RLS filtering)
		allCandidates, vErr := s.queryFeedCandidates(ctx, tx, viewerID, ``)
		if vErr != nil {
			return vErr
		}
		matched := make([]candidateVideo, 0, len(allCandidates))
		for _, c := range allCandidates {
			if normQ == "" {
				matched = append(matched, c)
				continue
			}
			matchesHashtag := false
			for _, t := range c.dto.Hashtags {
				if strings.Contains(strings.ToLower(t), normQ) {
					matchesHashtag = true
					break
				}
			}
			if matchesHashtag ||
				strings.Contains(strings.ToLower(c.dto.Title), normQ) ||
				strings.Contains(strings.ToLower(c.dto.Description), normQ) ||
				strings.Contains(strings.ToLower(c.dto.CreatorName), normQ) ||
				strings.Contains(strings.ToLower(c.dto.CreatorUsername), normQ) ||
				strings.Contains(strings.ToLower(c.dto.Audio.Title), normQ) ||
				strings.Contains(strings.ToLower(c.dto.Audio.Artist), normQ) {
				matched = append(matched, c)
			}
		}

		page := sliceFeedPage(matched, offset, limit)
		resp.Videos = page.Videos
		resp.NextCursor = page.NextCursor
		resp.HasMore = page.HasMore
		return nil
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return resp, http.StatusOK, nil
}

func (s *Service) DeleteSearchHistory(ctx context.Context, viewerID uuid.UUID, itemID string) (int, error) {
	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		if itemID == "" {
			_, err := tx.Exec(ctx, `DELETE FROM user_search_history WHERE user_id = $1`, viewerID)
			return err
		}
		id, pErr := uuid.Parse(itemID)
		if pErr != nil {
			return pErr
		}
		_, err := tx.Exec(ctx, `DELETE FROM user_search_history WHERE id = $1 AND user_id = $2`, id, viewerID)
		return err
	})
	if err != nil {
		return http.StatusBadRequest, err
	}
	return http.StatusOK, nil
}

func (s *Service) RecordViewOrProgress(
	ctx context.Context,
	viewerID, videoID uuid.UUID,
	deviceFP string,
	watchDurationMs, lastPositionMs int64,
	completionPct float64,
	rewatchDelta int,
) (int, error) {
	if watchDurationMs < 0 {
		watchDurationMs = 0
	}
	if lastPositionMs < 0 {
		lastPositionMs = 0
	}
	if completionPct < 0 {
		completionPct = 0
	}
	if completionPct > 100 {
		completionPct = 100
	}

	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		var creatorID uuid.UUID
		var audioIDStr string
		if err := tx.QueryRow(ctx, `
			SELECT creator_id, COALESCE(audio_id::text, '') FROM videos WHERE id = $1
		`, videoID).Scan(&creatorID, &audioIDStr); err != nil {
			return err
		}

		_, err := tx.Exec(ctx, `
			INSERT INTO video_views (video_id, viewer_id, device_fp_hash, watch_duration_ms, completion_pct, rewatch_count)
			VALUES ($1, $2, $3, $4, $5, $6)
		`, videoID, viewerID, padHash64(deviceFP), watchDurationMs, completionPct, rewatchDelta)
		if err != nil {
			return err
		}

		completed := completionPct >= 85.0
		_, err = tx.Exec(ctx, `
			INSERT INTO watch_history (viewer_id, video_id, last_position_ms, max_watch_pct, total_watch_ms, play_count, completed, last_watched_at)
			VALUES ($1, $2, $3, $4, $5, 1, $6, NOW())
			ON CONFLICT (viewer_id, video_id) DO UPDATE SET
				last_position_ms = EXCLUDED.last_position_ms,
				max_watch_pct = GREATEST(watch_history.max_watch_pct, EXCLUDED.max_watch_pct),
				total_watch_ms = watch_history.total_watch_ms + EXCLUDED.total_watch_ms,
				play_count = watch_history.play_count + CASE WHEN $7 > 0 THEN $7 ELSE 0 END,
				completed = watch_history.completed OR EXCLUDED.completed,
				last_watched_at = NOW()
		`, viewerID, videoID, lastPositionMs, completionPct, watchDurationMs, completed, rewatchDelta)
		if err != nil {
			return err
		}

		_, err = tx.Exec(ctx, `SELECT telefam_sync_video_counters($1)`, videoID)
		if err != nil {
			return err
		}

		if completed || rewatchDelta > 0 {
			evType := "complete"
			weight := 1.6
			if rewatchDelta > 0 {
				evType = "rewatch"
				weight = 2.2
			}
			s.bumpVideoAffinityTx(ctx, tx, viewerID, videoID, creatorID, audioIDStr, evType, weight)
		}
		return nil
	})
	if err != nil {
		return http.StatusNotFound, err
	}
	return http.StatusOK, nil
}

func (s *Service) SetLikeState(ctx context.Context, viewerID, videoID uuid.UUID, like bool) (int64, bool, int, error) {
	var count int64
	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		var creatorID uuid.UUID
		var audioIDStr string
		if err := tx.QueryRow(ctx, `
			SELECT creator_id, COALESCE(audio_id::text, '') FROM videos WHERE id = $1
		`, videoID).Scan(&creatorID, &audioIDStr); err != nil {
			return err
		}
		if like {
			if _, err := tx.Exec(ctx, `
				INSERT INTO video_likes (video_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING
			`, videoID, viewerID); err != nil {
				return err
			}
			s.bumpVideoAffinityTx(ctx, tx, viewerID, videoID, creatorID, audioIDStr, "like", 2.0)
		} else {
			if _, err := tx.Exec(ctx, `
				DELETE FROM video_likes WHERE video_id = $1 AND user_id = $2
			`, videoID, viewerID); err != nil {
				return err
			}
			s.bumpVideoAffinityTx(ctx, tx, viewerID, videoID, creatorID, audioIDStr, "unlike", -0.8)
		}
		if _, err := tx.Exec(ctx, `SELECT telefam_sync_video_counters($1)`, videoID); err != nil {
			return err
		}
		return tx.QueryRow(ctx, `SELECT likes_count FROM videos WHERE id = $1`, videoID).Scan(&count)
	})
	if err != nil {
		return 0, false, http.StatusNotFound, err
	}
	return count, like, http.StatusOK, nil
}

func (s *Service) SetSaveState(ctx context.Context, viewerID, videoID uuid.UUID, save bool) (int64, bool, int, error) {
	var count int64
	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		var creatorID uuid.UUID
		var audioIDStr string
		if err := tx.QueryRow(ctx, `
			SELECT creator_id, COALESCE(audio_id::text, '') FROM videos WHERE id = $1
		`, videoID).Scan(&creatorID, &audioIDStr); err != nil {
			return err
		}
		if save {
			if _, err := tx.Exec(ctx, `
				INSERT INTO saved_videos (user_id, video_id) VALUES ($1, $2) ON CONFLICT DO NOTHING
			`, viewerID, videoID); err != nil {
				return err
			}
			s.bumpVideoAffinityTx(ctx, tx, viewerID, videoID, creatorID, audioIDStr, "save", 2.5)
		} else {
			if _, err := tx.Exec(ctx, `
				DELETE FROM saved_videos WHERE user_id = $1 AND video_id = $2
			`, videoID, viewerID); err != nil {
				return err
			}
			s.bumpVideoAffinityTx(ctx, tx, viewerID, videoID, creatorID, audioIDStr, "unsave", -0.8)
		}
		if _, err := tx.Exec(ctx, `SELECT telefam_sync_video_counters($1)`, videoID); err != nil {
			return err
		}
		return tx.QueryRow(ctx, `SELECT saves_count FROM videos WHERE id = $1`, videoID).Scan(&count)
	})
	if err != nil {
		return 0, false, http.StatusNotFound, err
	}
	return count, save, http.StatusOK, nil
}

func (s *Service) RecordShare(ctx context.Context, viewerID, videoID uuid.UUID, channel string) (int64, int, error) {
	ch := strings.TrimSpace(channel)
	if ch == "" || len(ch) > 30 {
		ch = "link"
	}
	var count int64
	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		var creatorID uuid.UUID
		var audioIDStr string
		if err := tx.QueryRow(ctx, `
			SELECT creator_id, COALESCE(audio_id::text, '') FROM videos WHERE id = $1
		`, videoID).Scan(&creatorID, &audioIDStr); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO video_shares (video_id, user_id, share_channel) VALUES ($1, $2, $3)
		`, videoID, viewerID, ch); err != nil {
			return err
		}
		s.bumpVideoAffinityTx(ctx, tx, viewerID, videoID, creatorID, audioIDStr, "share", 3.0)
		if _, err := tx.Exec(ctx, `SELECT telefam_sync_video_counters($1)`, videoID); err != nil {
			return err
		}
		return tx.QueryRow(ctx, `SELECT shares_count FROM videos WHERE id = $1`, videoID).Scan(&count)
	})
	if err != nil {
		return 0, http.StatusNotFound, err
	}
	return count, http.StatusOK, nil
}

func (s *Service) ToggleRepost(ctx context.Context, viewerID, videoID uuid.UUID, repost bool) (int64, bool, int, error) {
	var count int64
	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		var creatorID uuid.UUID
		var audioIDStr string
		if err := tx.QueryRow(ctx, `
			SELECT creator_id, COALESCE(audio_id::text, '') FROM videos WHERE id = $1
		`, videoID).Scan(&creatorID, &audioIDStr); err != nil {
			return err
		}
		if repost {
			if _, err := tx.Exec(ctx, `
				INSERT INTO reposts (user_id, video_id) VALUES ($1, $2) ON CONFLICT DO NOTHING
			`, viewerID, videoID); err != nil {
				return err
			}
			s.bumpVideoAffinityTx(ctx, tx, viewerID, videoID, creatorID, audioIDStr, "repost", 2.2)
		} else {
			if _, err := tx.Exec(ctx, `
				DELETE FROM reposts WHERE user_id = $1 AND video_id = $2
			`, viewerID, videoID); err != nil {
				return err
			}
		}
		if _, err := tx.Exec(ctx, `SELECT telefam_sync_video_counters($1)`, videoID); err != nil {
			return err
		}
		return tx.QueryRow(ctx, `SELECT reposts_count FROM videos WHERE id = $1`, videoID).Scan(&count)
	})
	if err != nil {
		return 0, false, http.StatusNotFound, err
	}
	return count, repost, http.StatusOK, nil
}

func (s *Service) RecordNotInterested(ctx context.Context, viewerID, videoID uuid.UUID) (int, error) {
	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		var creatorID uuid.UUID
		var audioIDStr string
		if err := tx.QueryRow(ctx, `
			SELECT creator_id, COALESCE(audio_id::text, '') FROM videos WHERE id = $1
		`, videoID).Scan(&creatorID, &audioIDStr); err != nil {
			return err
		}
		s.bumpVideoAffinityTx(ctx, tx, viewerID, videoID, creatorID, audioIDStr, "not_interested", -3.0)
		return nil
	})
	if err != nil {
		return http.StatusNotFound, err
	}
	return http.StatusOK, nil
}

func (s *Service) SubmitReport(ctx context.Context, viewerID, videoID uuid.UUID, reason, details string) (int, error) {
	normReason := strings.ToLower(strings.TrimSpace(reason))
	switch normReason {
	case "spam", "harassment", "hate_speech", "violence",
		"nudity_or_sexual_content", "misinformation", "copyright_violation", "other":
	default:
		return http.StatusBadRequest, errors.New("invalid reason")
	}
	cleanDetails := strings.TrimSpace(details)
	if len([]rune(cleanDetails)) > 600 {
		cleanDetails = string([]rune(cleanDetails)[:600])
	}
	encDetails, err := security.EncryptAtRest(s.cfg.MasterKey, []byte(cleanDetails), "video_reports.details")
	if err != nil {
		return http.StatusInternalServerError, err
	}

	err = db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO video_reports (video_id, reporter_id, reason, details_encrypted, status)
			VALUES ($1, $2, $3, $4, 'open')
			ON CONFLICT (video_id, reporter_id, reason) DO UPDATE SET
				details_encrypted = EXCLUDED.details_encrypted
		`, videoID, viewerID, normReason, encDetails)
		return err
	})
	if err != nil {
		return http.StatusBadRequest, err
	}
	return http.StatusCreated, nil
}

func (s *Service) SetBlockUser(ctx context.Context, viewerID, targetID uuid.UUID, block bool) (int, error) {
	if targetID == uuid.Nil || targetID == viewerID {
		return http.StatusBadRequest, errors.New("invalid target")
	}
	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		if block {
			if _, err := tx.Exec(ctx, `
				INSERT INTO blocked_users (user_id, blocked_user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING
			`, viewerID, targetID); err != nil {
				return err
			}
			_, _ = tx.Exec(ctx, `
				DELETE FROM user_follows WHERE (follower_id = $1 AND followee_id = $2) OR (follower_id = $2 AND followee_id = $1)
			`, viewerID, targetID)
		} else {
			_, err := tx.Exec(ctx, `
				DELETE FROM blocked_users WHERE user_id = $1 AND blocked_user_id = $2
			`, viewerID, targetID)
			return err
		}
		return nil
	})
	if err != nil {
		return http.StatusBadRequest, err
	}
	return http.StatusOK, nil
}

func (s *Service) SetMuteUser(ctx context.Context, viewerID, targetID uuid.UUID, mute bool) (int, error) {
	if targetID == uuid.Nil || targetID == viewerID {
		return http.StatusBadRequest, errors.New("invalid target")
	}
	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		if mute {
			_, err := tx.Exec(ctx, `
				INSERT INTO muted_users (user_id, muted_user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING
			`, viewerID, targetID)
			return err
		}
		_, err := tx.Exec(ctx, `
			DELETE FROM muted_users WHERE user_id = $1 AND muted_user_id = $2
		`, viewerID, targetID)
		return err
	})
	if err != nil {
		return http.StatusBadRequest, err
	}
	return http.StatusOK, nil
}

func (s *Service) ListSafetyPreferences(ctx context.Context, viewerID uuid.UUID) (*SafetyPreferencesDTO, int, error) {
	res := &SafetyPreferencesDTO{
		MutedUsers:   []SafetyUserDTO{},
		BlockedUsers: []SafetyUserDTO{},
	}
	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		creators, err := s.loadCreatorMap(ctx, tx, viewerID)
		if err != nil {
			return err
		}
		mRows, err := tx.Query(ctx, `SELECT muted_user_id FROM muted_users WHERE user_id = $1 ORDER BY created_at DESC`, viewerID)
		if err == nil {
			for mRows.Next() {
				var tid uuid.UUID
				if err := mRows.Scan(&tid); err == nil {
					c := creators[tid]
					res.MutedUsers = append(res.MutedUsers, SafetyUserDTO{
						UserID:            tid.String(),
						FullName:          c.FullName,
						Username:          c.Username,
						AvatarFingerprint: c.AvatarFingerprint,
					})
				}
			}
			mRows.Close()
		}
		bRows, err := tx.Query(ctx, `SELECT blocked_user_id FROM blocked_users WHERE user_id = $1 ORDER BY created_at DESC`, viewerID)
		if err == nil {
			for bRows.Next() {
				var tid uuid.UUID
				if err := bRows.Scan(&tid); err == nil {
					c := creators[tid]
					res.BlockedUsers = append(res.BlockedUsers, SafetyUserDTO{
						UserID:            tid.String(),
						FullName:          c.FullName,
						Username:          c.Username,
						AvatarFingerprint: c.AvatarFingerprint,
					})
				}
			}
			bRows.Close()
		}
		return nil
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return res, http.StatusOK, nil
}

func (s *Service) ListSavedVideos(ctx context.Context, viewerID uuid.UUID, cursorStr string, limit int) (*FeedPageDTO, int, error) {
	if limit <= 0 || limit > 40 {
		limit = 21
	}
	offset := parseCursor(cursorStr)
	var candidates []candidateVideo
	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		var qErr error
		candidates, qErr = s.queryFeedCandidates(ctx, tx, viewerID, `
			AND EXISTS (SELECT 1 FROM saved_videos sv WHERE sv.video_id = v.id AND sv.user_id = $1)
		`)
		return qErr
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return sliceFeedPage(candidates, offset, limit), http.StatusOK, nil
}

func (s *Service) UpdateOwnerVideo(ctx context.Context, ownerID, videoID uuid.UUID, title, description, visibility *string) (*FeedVideoDTO, int, error) {
	var updated *FeedVideoDTO
	err := db.WithUserRLS(ctx, s.pool, ownerID, func(tx pgx.Tx) error {
		var curTitleEnc, curDescEnc []byte
		var curVis string
		if err := tx.QueryRow(ctx, `
			SELECT title_encrypted, description_encrypted, visibility
			FROM videos WHERE id = $1 AND creator_id = $2
		`, videoID, ownerID).Scan(&curTitleEnc, &curDescEnc, &curVis); err != nil {
			return err
		}

		nextTitleEnc := curTitleEnc
		nextDescEnc := curDescEnc
		nextVis := curVis

		if title != nil {
			clean := strings.TrimSpace(*title)
			if len([]rune(clean)) > 2200 {
				return errors.New("title too long")
			}
			enc, eErr := security.EncryptAtRest(s.cfg.MasterKey, []byte(clean), "posts.body")
			if eErr != nil {
				return eErr
			}
			nextTitleEnc = enc
		}
		if description != nil {
			clean := strings.TrimSpace(*description)
			if len([]rune(clean)) > 2200 {
				return errors.New("description too long")
			}
			enc, eErr := security.EncryptAtRest(s.cfg.MasterKey, []byte(clean), "posts.body")
			if eErr != nil {
				return eErr
			}
			nextDescEnc = enc
		}
		if visibility != nil {
			v := strings.ToLower(strings.TrimSpace(*visibility))
			if v != "public" && v != "followers" && v != "private" {
				return errors.New("invalid visibility")
			}
			nextVis = v
		}

		if _, err := tx.Exec(ctx, `
			UPDATE videos
			SET title_encrypted = $1, description_encrypted = $2, visibility = $3, updated_at = NOW()
			WHERE id = $4 AND creator_id = $5
		`, nextTitleEnc, nextDescEnc, nextVis, videoID, ownerID); err != nil {
			return err
		}

		list, qErr := s.queryFeedCandidates(ctx, tx, ownerID, `AND v.id = $2`, videoID)
		if qErr != nil || len(list) == 0 {
			return errors.New("not found")
		}
		dto := list[0].dto
		updated = &dto
		return nil
	})
	if err != nil {
		return nil, http.StatusBadRequest, err
	}
	return updated, http.StatusOK, nil
}

func (s *Service) DeleteOwnerVideo(ctx context.Context, ownerID, videoID uuid.UUID) (int, error) {
	var primaryKey, thumbKey, hlsMasterKey string
	var postID *uuid.UUID
	err := db.WithUserRLS(ctx, s.pool, ownerID, func(tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, `
			SELECT post_id, primary_object_key, thumbnail_object_key, hls_master_object_key
			FROM videos WHERE id = $1 AND creator_id = $2
		`, videoID, ownerID).Scan(&postID, &primaryKey, &thumbKey, &hlsMasterKey); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `DELETE FROM videos WHERE id = $1 AND creator_id = $2`, videoID, ownerID); err != nil {
			return err
		}
		if postID != nil && *postID != uuid.Nil {
			_, _ = tx.Exec(ctx, `DELETE FROM posts WHERE id = $1 AND author_id = $2`, *postID, ownerID)
		}
		return nil
	})
	if err != nil {
		return http.StatusNotFound, err
	}
	for _, key := range []string{primaryKey, thumbKey} {
		if key != "" {
			if p, err := media.ConfineStoragePath(s.cfg.MediaStorageDir, key); err == nil {
				_ = os.Remove(p)
			}
		}
	}
	if hlsMasterKey != "" {
		dirRel := filepath.Dir(hlsMasterKey)
		if dirRel != "." && strings.HasPrefix(dirRel, "hls/") {
			if p, err := media.ConfineStoragePath(s.cfg.MediaStorageDir, dirRel); err == nil {
				_ = os.RemoveAll(p)
			}
		}
	}
	return http.StatusOK, nil
}

func (s *Service) bumpVideoAffinityTx(
	ctx context.Context,
	tx pgx.Tx,
	viewerID, videoID, creatorID uuid.UUID,
	audioIDStr, eventType string,
	weight float64,
) {
	_, _ = tx.Exec(ctx, `
		INSERT INTO recommendation_events (user_id, video_id, event_type, signal_value)
		VALUES ($1, $2, $3, $4)
	`, viewerID, videoID, eventType, weight)

	_, _ = tx.Exec(ctx, `
		INSERT INTO user_interests (user_id, interest_kind, interest_key, affinity_score, updated_at)
		VALUES ($1, 'creator', $2, GREATEST(-10.0, LEAST(40.0, $3)), NOW())
		ON CONFLICT (user_id, interest_kind, interest_key) DO UPDATE SET
			affinity_score = GREATEST(-10.0, LEAST(40.0, user_interests.affinity_score + $3)),
			updated_at = NOW()
	`, viewerID, creatorID.String(), weight)

	if audioIDStr != "" {
		_, _ = tx.Exec(ctx, `
			INSERT INTO user_interests (user_id, interest_kind, interest_key, affinity_score, updated_at)
			VALUES ($1, 'audio', $2, GREATEST(-10.0, LEAST(40.0, $3)), NOW())
			ON CONFLICT (user_id, interest_kind, interest_key) DO UPDATE SET
				affinity_score = GREATEST(-10.0, LEAST(40.0, user_interests.affinity_score + $3)),
				updated_at = NOW()
		`, viewerID, audioIDStr, weight)
	}

	tagRows, err := tx.Query(ctx, `SELECT tag_normalized FROM video_hashtags WHERE video_id = $1`, videoID)
	if err == nil {
		var tags []string
		for tagRows.Next() {
			var t string
			if err := tagRows.Scan(&t); err == nil {
				tags = append(tags, t)
			}
		}
		tagRows.Close()
		for _, t := range tags {
			_, _ = tx.Exec(ctx, `
				INSERT INTO user_interests (user_id, interest_kind, interest_key, affinity_score, updated_at)
				VALUES ($1, 'hashtag', $2, GREATEST(-10.0, LEAST(40.0, $3)), NOW())
				ON CONFLICT (user_id, interest_kind, interest_key) DO UPDATE SET
					affinity_score = GREATEST(-10.0, LEAST(40.0, user_interests.affinity_score + $3)),
					updated_at = NOW()
			`, viewerID, t, weight)
		}
	}
}

func (s *Service) bumpInterestTx(
	ctx context.Context,
	tx pgx.Tx,
	viewerID uuid.UUID,
	videoID *uuid.UUID,
	eventType string,
	weight float64,
	kind, key string,
) {
	_, _ = tx.Exec(ctx, `
		INSERT INTO recommendation_events (user_id, video_id, event_type, signal_value, context_tag)
		VALUES ($1, $2, $3, $4, $5)
	`, viewerID, videoID, eventType, weight, key)
	_, _ = tx.Exec(ctx, `
		INSERT INTO user_interests (user_id, interest_kind, interest_key, affinity_score, updated_at)
		VALUES ($1, $2, $3, GREATEST(-10.0, LEAST(40.0, $4)), NOW())
		ON CONFLICT (user_id, interest_kind, interest_key) DO UPDATE SET
			affinity_score = GREATEST(-10.0, LEAST(40.0, user_interests.affinity_score + $4)),
			updated_at = NOW()
	`, viewerID, kind, key, weight)
}

func diversifyCandidates(sorted []candidateVideo) []candidateVideo {
	if len(sorted) <= 2 {
		return sorted
	}
	remaining := append([]candidateVideo(nil), sorted...)
	result := make([]candidateVideo, 0, len(remaining))
	for len(remaining) > 0 {
		chosenIdx := 0
		if len(result) >= 2 {
			last := result[len(result)-1]
			prev := result[len(result)-2]
			for idx, cand := range remaining {
				sameCreatorTwice := cand.creatorUUID == last.creatorUUID && last.creatorUUID == prev.creatorUUID
				sameTagTwice := cand.primaryHashtag != "" && cand.primaryHashtag == last.primaryHashtag && last.primaryHashtag == prev.primaryHashtag
				if !sameCreatorTwice && !sameTagTwice {
					chosenIdx = idx
					break
				}
			}
		}
		result = append(result, remaining[chosenIdx])
		remaining = append(remaining[:chosenIdx], remaining[chosenIdx+1:]...)
	}
	return result
}

func sliceFeedPage(candidates []candidateVideo, offset, limit int) *FeedPageDTO {
	if offset >= len(candidates) {
		return &FeedPageDTO{
			Videos:     []FeedVideoDTO{},
			NextCursor: "",
			HasMore:    false,
		}
	}
	end := offset + limit
	hasMore := false
	nextCursor := ""
	if end < len(candidates) {
		hasMore = true
		nextCursor = strconv.Itoa(end)
	} else {
		end = len(candidates)
	}
	out := make([]FeedVideoDTO, 0, end-offset)
	for _, c := range candidates[offset:end] {
		out = append(out, c.dto)
	}
	return &FeedPageDTO{
		Videos:     out,
		NextCursor: nextCursor,
		HasMore:    hasMore,
	}
}

func parseCursor(raw string) int {
	if v, err := strconv.Atoi(strings.TrimSpace(raw)); err == nil && v >= 0 {
		return v
	}
	return 0
}

func normalizeTag(raw string) string {
	clean := strings.TrimSpace(strings.TrimPrefix(strings.ToLower(raw), "#"))
	var b strings.Builder
	for _, r := range clean {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '_' {
			b.WriteRune(r)
		}
	}
	res := b.String()
	if len(res) > 64 {
		res = res[:64]
	}
	return res
}

func padHash64(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}

func deterministicUnitFloat(seed string) float64 {
	sum := sha256.Sum256([]byte(seed))
	v := uint32(sum[0])<<24 | uint32(sum[1])<<16 | uint32(sum[2])<<8 | uint32(sum[3])
	return float64(v) / float64(math.MaxUint32)
}
