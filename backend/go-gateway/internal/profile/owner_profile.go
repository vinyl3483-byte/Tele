package profile

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/telefam/company/backend/go-gateway/internal/db"
	"github.com/telefam/company/backend/go-gateway/internal/feed"
	"github.com/telefam/company/backend/go-gateway/internal/media"
	"github.com/telefam/company/backend/go-gateway/internal/security"
)

const MaxBackgroundPhotos = 5

type OwnerProfileItemDTO struct {
	ItemID        string             `json:"item_id"`
	PostID        string             `json:"post_id"`
	VideoID       string             `json:"video_id,omitempty"`
	MediaType     string             `json:"media_type"` // video | photos | text
	Visibility    string             `json:"visibility"` // public | followers | private
	Body          string             `json:"body"`
	BgColorHex    string             `json:"bg_color_hex"`
	BgThemeID     string             `json:"bg_theme_id"`
	FontFamily    string             `json:"font_family"`
	SongTitle     string             `json:"song_title"`
	SongArtist    string             `json:"song_artist"`
	ThumbnailURL  string             `json:"thumbnail_url"`
	PhotoURLs     []string           `json:"photo_urls"`
	Hashtags      []string           `json:"hashtags"`
	LikesCount    int64              `json:"likes_count"`
	ViewsCount    int64              `json:"views_count"`
	IsLiked       bool               `json:"is_liked"`
	IsSaved       bool               `json:"is_saved"`
	IsReposted    bool               `json:"is_reposted"`
	Video         *feed.FeedVideoDTO `json:"video,omitempty"`
	CreatedAt     int64              `json:"created_at"`
}

type OwnerProfileItemsPageDTO struct {
	Tab        string                `json:"tab"`
	Items      []OwnerProfileItemDTO `json:"items"`
	NextCursor string                `json:"next_cursor"`
	HasMore    bool                  `json:"has_more"`
}

type signedPostPhotoToken struct {
	MediaID string `json:"m"`
	UserID  string `json:"u"`
	Exp     int64  `json:"e"`
}

func (s *Service) signPostPhotoToken(mediaID, viewerID uuid.UUID, exp time.Time) string {
	raw, _ := json.Marshal(signedPostPhotoToken{
		MediaID: mediaID.String(),
		UserID:  viewerID.String(),
		Exp:     exp.Unix(),
	})
	b64 := base64.RawURLEncoding.EncodeToString(raw)
	mac := hmac.New(sha256.New, s.cfg.HMACPepper)
	mac.Write([]byte("post_photo|" + b64))
	sig := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	return b64 + "." + sig
}

func (s *Service) verifyPostPhotoToken(token string) (*signedPostPhotoToken, error) {
	parts := strings.Split(strings.TrimSpace(token), ".")
	if len(parts) != 2 {
		return nil, errors.New("invalid token format")
	}
	mac := hmac.New(sha256.New, s.cfg.HMACPepper)
	mac.Write([]byte("post_photo|" + parts[0]))
	expectedSig := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	if len(parts[1]) != len(expectedSig) || subtle.ConstantTimeCompare([]byte(parts[1]), []byte(expectedSig)) != 1 {
		return nil, errors.New("invalid token signature")
	}
	raw, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return nil, err
	}
	var payload signedPostPhotoToken
	if err := json.Unmarshal(raw, &payload); err != nil {
		return nil, err
	}
	if payload.Exp <= time.Now().UTC().Unix() {
		return nil, errors.New("expired")
	}
	return &payload, nil
}

func (s *Service) GetAvatarBytes(ctx context.Context, requesterID, targetUserID uuid.UUID) ([]byte, string, string, int, error) {
	var encBytes []byte
	var mimeType, fpHash string
	err := db.WithUserRLS(ctx, s.pool, requesterID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT mime_type, fingerprint_hash, sanitized_bytes_encrypted
			FROM profile_avatars WHERE user_id = $1
		`, targetUserID).Scan(&mimeType, &fpHash, &encBytes)
	})
	if err != nil {
		return nil, "", "", http.StatusNotFound, err
	}
	plain, err := security.DecryptAtRest(s.cfg.MasterKey, encBytes, "profile_avatars.bytes")
	if err != nil {
		return nil, "", "", http.StatusInternalServerError, err
	}
	if mimeType == "" {
		mimeType = "image/jpeg"
	}
	return plain, mimeType, fpHash, http.StatusOK, nil
}

func (s *Service) listBackgroundPhotosTx(ctx context.Context, tx pgx.Tx, userID uuid.UUID) ([]BackgroundPhotoDTO, error) {
	rows, err := tx.Query(ctx, `
		SELECT id, sort_order, fingerprint_hash, width, height
		FROM profile_backgrounds
		WHERE user_id = $1
		ORDER BY sort_order ASC, created_at ASC
		LIMIT 5
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]BackgroundPhotoDTO, 0, MaxBackgroundPhotos)
	for rows.Next() {
		var id uuid.UUID
		var sortOrder, w, h int
		var fp string
		if err := rows.Scan(&id, &sortOrder, &fp, &w, &h); err == nil {
			out = append(out, BackgroundPhotoDTO{
				ID:              id.String(),
				SortOrder:       sortOrder,
				FingerprintHash: fp,
				Width:           w,
				Height:          h,
				URL:             "/v1/profile/backgrounds/" + id.String() + "?v=" + fp,
			})
		}
	}
	return out, rows.Err()
}

func (s *Service) ListBackgroundPhotos(ctx context.Context, userID uuid.UUID) ([]BackgroundPhotoDTO, int, error) {
	var out []BackgroundPhotoDTO
	err := db.WithUserRLS(ctx, s.pool, userID, func(tx pgx.Tx) error {
		var qErr error
		out, qErr = s.listBackgroundPhotosTx(ctx, tx, userID)
		return qErr
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	if out == nil {
		out = []BackgroundPhotoDTO{}
	}
	return out, http.StatusOK, nil
}

func (s *Service) UploadBackgroundPhotos(ctx context.Context, userID uuid.UUID, rawImages [][]byte) ([]BackgroundPhotoDTO, int, error) {
	if len(rawImages) == 0 {
		return nil, http.StatusBadRequest, errors.New("at least one background photo is required")
	}
	if len(rawImages) > MaxBackgroundPhotos {
		return nil, http.StatusBadRequest, errors.New("maximum 5 background photos allowed")
	}

	// Sanitize every uploaded image in bounded isolation before touching database
	type preparedBg struct {
		clean *media.SanitizedCoverPhoto
		enc   []byte
	}
	prepared := make([]preparedBg, 0, len(rawImages))
	for _, raw := range rawImages {
		sanitized, err := media.SanitizeCoverPhotoInIsolation(ctx, raw, s.cfg.HMACPepper)
		if err != nil {
			return nil, http.StatusBadRequest, err
		}
		enc, err := security.EncryptAtRest(s.cfg.MasterKey, sanitized.Bytes, "profile_backgrounds.bytes")
		if err != nil {
			return nil, http.StatusInternalServerError, err
		}
		prepared = append(prepared, preparedBg{clean: sanitized, enc: enc})
	}

	var out []BackgroundPhotoDTO
	var limitExceeded bool
	err := db.WithUserRLS(ctx, s.pool, userID, func(tx pgx.Tx) error {
		var existingCount int
		if err := tx.QueryRow(ctx, `SELECT COUNT(*) FROM profile_backgrounds WHERE user_id = $1`, userID).Scan(&existingCount); err != nil {
			return err
		}
		if existingCount+len(prepared) > MaxBackgroundPhotos {
			limitExceeded = true
			return errors.New("maximum 5 background photos allowed")
		}
		for i, item := range prepared {
			id := uuid.New()
			if _, err := tx.Exec(ctx, `
				INSERT INTO profile_backgrounds (
					id, user_id, sort_order, mime_type, byte_size, width, height, fingerprint_hash, sanitized_bytes_encrypted
				) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
			`, id, userID, existingCount+i, item.clean.MimeType, len(item.clean.Bytes),
				item.clean.Width, item.clean.Height, item.clean.FingerprintHash, item.enc); err != nil {
				return err
			}
		}
		var qErr error
		out, qErr = s.listBackgroundPhotosTx(ctx, tx, userID)
		return qErr
	})
	if err != nil {
		if limitExceeded {
			return nil, http.StatusBadRequest, err
		}
		return nil, http.StatusInternalServerError, err
	}
	return out, http.StatusOK, nil
}

func (s *Service) DeleteBackgroundPhoto(ctx context.Context, userID, bgID uuid.UUID) ([]BackgroundPhotoDTO, int, error) {
	var out []BackgroundPhotoDTO
	err := db.WithUserRLS(ctx, s.pool, userID, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `DELETE FROM profile_backgrounds WHERE id = $1 AND user_id = $2`, bgID, userID)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return errors.New("background photo not found")
		}
		// Re-compact sort_order 0..N-1 cleanly
		rows, err := tx.Query(ctx, `
			SELECT id FROM profile_backgrounds WHERE user_id = $1 ORDER BY sort_order ASC, created_at ASC
		`, userID)
		if err != nil {
			return err
		}
		var ids []uuid.UUID
		for rows.Next() {
			var id uuid.UUID
			if err := rows.Scan(&id); err == nil {
				ids = append(ids, id)
			}
		}
		rows.Close()
		for idx, id := range ids {
			_, _ = tx.Exec(ctx, `UPDATE profile_backgrounds SET sort_order = $1, updated_at = NOW() WHERE id = $2 AND user_id = $3`, idx, id, userID)
		}
		var qErr error
		out, qErr = s.listBackgroundPhotosTx(ctx, tx, userID)
		return qErr
	})
	if err != nil {
		return nil, http.StatusNotFound, err
	}
	if out == nil {
		out = []BackgroundPhotoDTO{}
	}
	return out, http.StatusOK, nil
}

func (s *Service) GetBackgroundPhotoBytes(ctx context.Context, userID, bgID uuid.UUID) ([]byte, string, string, int, error) {
	var encBytes []byte
	var mimeType, fpHash string
	err := db.WithUserRLS(ctx, s.pool, userID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT mime_type, fingerprint_hash, sanitized_bytes_encrypted
			FROM profile_backgrounds WHERE id = $1 AND user_id = $2
		`, bgID, userID).Scan(&mimeType, &fpHash, &encBytes)
	})
	if err != nil {
		return nil, "", "", http.StatusNotFound, err
	}
	plain, err := security.DecryptAtRest(s.cfg.MasterKey, encBytes, "profile_backgrounds.bytes")
	if err != nil {
		return nil, "", "", http.StatusInternalServerError, err
	}
	if mimeType == "" {
		mimeType = "image/jpeg"
	}
	return plain, mimeType, fpHash, http.StatusOK, nil
}

func (s *Service) ServeSignedPostPhoto(w http.ResponseWriter, r *http.Request, token string) {
	payload, err := s.verifyPostPhotoToken(token)
	if err != nil {
		http.Error(w, "Error has occurred, try again later.", http.StatusUnauthorized)
		return
	}
	mid, err := uuid.Parse(payload.MediaID)
	if err != nil {
		http.Error(w, "Error has occurred, try again later.", http.StatusForbidden)
		return
	}
	uid, err := uuid.Parse(payload.UserID)
	if err != nil {
		http.Error(w, "Error has occurred, try again later.", http.StatusForbidden)
		return
	}

	var storedKey, mimeType string
	err = db.WithUserRLS(r.Context(), s.pool, uid, func(tx pgx.Tx) error {
		return tx.QueryRow(r.Context(), `
			SELECT stored_object_key, mime_type
			FROM post_media WHERE id = $1 AND media_kind = 'photo'
		`, mid).Scan(&storedKey, &mimeType)
	})
	if err != nil || storedKey == "" {
		http.Error(w, "Error has occurred, try again later.", http.StatusForbidden)
		return
	}

	absPath, err := media.ConfineStoragePath(s.cfg.MediaStorageDir, storedKey)
	if err != nil {
		http.Error(w, "Error has occurred, try again later.", http.StatusForbidden)
		return
	}
	raw, err := os.ReadFile(absPath)
	if err != nil {
		http.Error(w, "Error has occurred, try again later.", http.StatusNotFound)
		return
	}
	if mimeType == "" {
		mimeType = "image/jpeg"
	}
	w.Header().Set("Content-Type", mimeType)
	w.Header().Set("Cache-Control", "private, max-age=300")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(raw)
}

func (s *Service) GetOwnerProfileItems(
	ctx context.Context,
	feedSvc *feed.Service,
	ownerID uuid.UUID,
	tab, cursorStr string,
	limit int,
) (*OwnerProfileItemsPageDTO, int, error) {
	normTab := strings.ToLower(strings.TrimSpace(tab))
	switch normTab {
	case "", "posts":
		normTab = "posts"
	case "reposts", "locked", "saved":
	default:
		return nil, http.StatusBadRequest, errors.New("invalid tab")
	}
	if limit <= 0 || limit > 48 {
		limit = 24
	}
	offset := 0
	if parsed, err := strconv.Atoi(strings.TrimSpace(cursorStr)); err == nil && parsed > 0 {
		offset = parsed
	}

	allItems := make([]OwnerProfileItemDTO, 0, 32)
	err := db.WithUserRLS(ctx, s.pool, ownerID, func(tx pgx.Tx) error {
		// 1) Collect matching posts rows (including video posts and non-video posts)
		var postWhere string
		switch normTab {
		case "posts":
			postWhere = `p.author_id = $1 AND p.status = 'ready' AND p.visibility <> 'private'`
		case "locked":
			postWhere = `p.author_id = $1 AND p.status = 'ready' AND (p.visibility = 'private' OR COALESCE(v.visibility, '') = 'private')`
		case "reposts":
			postWhere = `p.status = 'ready' AND (
				EXISTS (SELECT 1 FROM post_reposts pr WHERE pr.post_id = p.id AND pr.user_id = $1)
				OR (v.id IS NOT NULL AND EXISTS (SELECT 1 FROM reposts r WHERE r.video_id = v.id AND r.user_id = $1))
			)`
		case "saved":
			postWhere = `p.status = 'ready' AND (
				EXISTS (SELECT 1 FROM saved_posts sp WHERE sp.post_id = p.id AND sp.user_id = $1)
				OR (v.id IS NOT NULL AND EXISTS (SELECT 1 FROM saved_videos sv WHERE sv.video_id = v.id AND sv.user_id = $1))
			)`
		}

		rows, err := tx.Query(ctx, `
			SELECT p.id, p.post_type, p.visibility, p.body_encrypted, p.bg_color_hex, p.bg_theme_id, p.font_family,
			       COALESCE(p.song_title_encrypted, ''::bytea), COALESCE(p.song_artist_encrypted, ''::bytea),
			       p.likes_count, p.views_count, p.created_at,
			       COALESCE(v.id::text, ''), COALESCE(v.visibility, p.visibility),
			       EXISTS(SELECT 1 FROM post_likes pl WHERE pl.post_id = p.id AND pl.user_id = $1) AS is_liked,
			       EXISTS(SELECT 1 FROM saved_posts sp WHERE sp.post_id = p.id AND sp.user_id = $1) AS is_saved,
			       EXISTS(SELECT 1 FROM post_reposts pr WHERE pr.post_id = p.id AND pr.user_id = $1) AS is_reposted
			FROM posts p
			LEFT JOIN videos v ON v.post_id = p.id
			WHERE `+postWhere+`
			ORDER BY p.created_at DESC
			LIMIT 200
		`, ownerID)
		if err != nil {
			return err
		}

		type rawRow struct {
			postID     uuid.UUID
			videoIDStr string
			item       OwnerProfileItemDTO
		}
		collected := make([]rawRow, 0, 32)
		postIDs := make([]uuid.UUID, 0, 32)
		videoIDs := make([]uuid.UUID, 0, 32)
		seenVideoIDs := make(map[uuid.UUID]struct{})

		for rows.Next() {
			var pid uuid.UUID
			var postType, pVis, bgColor, bgTheme, fontFam, videoIDStr, effVis string
			var encBody, encSongT, encSongA []byte
			var likesCnt, viewsCnt int64
			var createdAt time.Time
			var isLiked, isSaved, isReposted bool

			if err := rows.Scan(
				&pid, &postType, &pVis, &encBody, &bgColor, &bgTheme, &fontFam,
				&encSongT, &encSongA, &likesCnt, &viewsCnt, &createdAt,
				&videoIDStr, &effVis, &isLiked, &isSaved, &isReposted,
			); err != nil {
				rows.Close()
				return err
			}
			bodyB, _ := security.DecryptAtRest(s.cfg.MasterKey, encBody, "posts.body")
			songTB, _ := security.DecryptAtRest(s.cfg.MasterKey, encSongT, "posts.song_title")
			songAB, _ := security.DecryptAtRest(s.cfg.MasterKey, encSongA, "posts.song_artist")

			if effVis == "" {
				effVis = pVis
			}
			dto := OwnerProfileItemDTO{
				ItemID:     pid.String(),
				PostID:     pid.String(),
				VideoID:    videoIDStr,
				MediaType:  postType,
				Visibility: effVis,
				Body:       string(bodyB),
				BgColorHex: bgColor,
				BgThemeID:  bgTheme,
				FontFamily: fontFam,
				SongTitle:  string(songTB),
				SongArtist: string(songAB),
				PhotoURLs:  []string{},
				Hashtags:   []string{},
				LikesCount: likesCnt,
				ViewsCount: viewsCnt,
				IsLiked:    isLiked,
				IsSaved:    isSaved,
				IsReposted: isReposted,
				CreatedAt:  createdAt.UnixMilli(),
			}
			collected = append(collected, rawRow{postID: pid, videoIDStr: videoIDStr, item: dto})
			postIDs = append(postIDs, pid)
			if vid, vErr := uuid.Parse(videoIDStr); vErr == nil && vid != uuid.Nil {
				videoIDs = append(videoIDs, vid)
				seenVideoIDs[vid] = struct{}{}
			}
		}
		rows.Close()

		// 2) Also include standalone feed videos (without a posts row) that belong to this tab
		var extraVideoWhere string
		switch normTab {
		case "posts":
			extraVideoWhere = `AND v.creator_id = $1 AND v.post_id IS NULL AND v.visibility <> 'private'`
		case "locked":
			extraVideoWhere = `AND v.creator_id = $1 AND v.post_id IS NULL AND v.visibility = 'private'`
		case "reposts":
			extraVideoWhere = `AND v.post_id IS NULL AND EXISTS (SELECT 1 FROM reposts r WHERE r.video_id = v.id AND r.user_id = $1)`
		case "saved":
			extraVideoWhere = `AND v.post_id IS NULL AND EXISTS (SELECT 1 FROM saved_videos sv WHERE sv.video_id = v.id AND sv.user_id = $1)`
		}
		vExtraRows, _ := tx.Query(ctx, `SELECT v.id FROM videos v WHERE v.processing_status = 'ready' `+extraVideoWhere, ownerID)
		if vExtraRows != nil {
			for vExtraRows.Next() {
				var vid uuid.UUID
				if err := vExtraRows.Scan(&vid); err == nil {
					if _, exists := seenVideoIDs[vid]; !exists {
						videoIDs = append(videoIDs, vid)
						seenVideoIDs[vid] = struct{}{}
						collected = append(collected, rawRow{
							videoIDStr: vid.String(),
							item: OwnerProfileItemDTO{
								ItemID:    vid.String(),
								VideoID:   vid.String(),
								MediaType: "video",
								PhotoURLs: []string{},
								Hashtags:  []string{},
							},
						})
					}
				}
			}
			vExtraRows.Close()
		}

		// Batch fetch signed FeedVideoDTOs
		var videoMap map[string]feed.FeedVideoDTO
		if feedSvc != nil && len(videoIDs) > 0 {
			videoMap, _ = feedSvc.QueryFeedVideosByIDs(ctx, tx, ownerID, videoIDs)
		}

		// Batch fetch photo URLs for photo posts
		photoURLsByPost := make(map[uuid.UUID][]string)
		if len(postIDs) > 0 {
			exp := time.Now().UTC().Add(15 * time.Minute)
			pRows, pErr := tx.Query(ctx, `
				SELECT id, post_id FROM post_media
				WHERE post_id = ANY($1) AND media_kind = 'photo'
				ORDER BY sort_order ASC
			`, postIDs)
			if pErr == nil {
				for pRows.Next() {
					var mid, pid uuid.UUID
					if err := pRows.Scan(&mid, &pid); err == nil {
						tok := s.signPostPhotoToken(mid, ownerID, exp)
						photoURLsByPost[pid] = append(photoURLsByPost[pid], "/v1/posts/media/signed/"+tok)
					}
				}
				pRows.Close()
			}

			hRows, hErr := tx.Query(ctx, `
				SELECT post_id, tag_normalized FROM post_hashtags WHERE post_id = ANY($1)
			`, postIDs)
			if hErr == nil {
				tagsByPost := make(map[uuid.UUID][]string)
				for hRows.Next() {
					var pid uuid.UUID
					var tag string
					if err := hRows.Scan(&pid, &tag); err == nil {
						tagsByPost[pid] = append(tagsByPost[pid], tag)
					}
				}
				hRows.Close()
				for i := range collected {
					if tags, ok := tagsByPost[collected[i].postID]; ok {
						collected[i].item.Hashtags = tags
					}
				}
			}
		}

		for i := range collected {
			item := collected[i].item
			if urls, ok := photoURLsByPost[collected[i].postID]; ok && len(urls) > 0 {
				item.PhotoURLs = urls
				item.ThumbnailURL = urls[0]
			}
			if vidDTO, ok := videoMap[collected[i].videoIDStr]; ok {
				copyDTO := vidDTO
				item.Video = &copyDTO
				item.ThumbnailURL = vidDTO.ThumbnailURL
				item.LikesCount = vidDTO.LikesCount
				item.ViewsCount = vidDTO.ViewsCount
				item.IsLiked = vidDTO.IsLiked
				item.IsSaved = vidDTO.IsSaved
				item.IsReposted = vidDTO.IsReposted
				item.Visibility = vidDTO.Visibility
				item.CreatedAt = vidDTO.CreatedAt
				if item.Body == "" {
					item.Body = vidDTO.Description
				}
				if len(vidDTO.Hashtags) > 0 {
					item.Hashtags = vidDTO.Hashtags
				}
			}
			allItems = append(allItems, item)
		}
		return nil
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}

	sort.Slice(allItems, func(i, j int) bool {
		return allItems[i].CreatedAt > allItems[j].CreatedAt
	})

	if offset >= len(allItems) {
		return &OwnerProfileItemsPageDTO{
			Tab:     normTab,
			Items:   []OwnerProfileItemDTO{},
			HasMore: false,
		}, http.StatusOK, nil
	}
	end := offset + limit
	hasMore := false
	nextCursor := ""
	if end < len(allItems) {
		hasMore = true
		nextCursor = strconv.Itoa(end)
	} else {
		end = len(allItems)
	}

	return &OwnerProfileItemsPageDTO{
		Tab:        normTab,
		Items:      allItems[offset:end],
		NextCursor: nextCursor,
		HasMore:    hasMore,
	}, http.StatusOK, nil
}

func (s *Service) SetPostVisibility(ctx context.Context, ownerID, postID uuid.UUID, visibility string) (string, int, error) {
	v := strings.ToLower(strings.TrimSpace(visibility))
	if v != "public" && v != "followers" && v != "private" {
		return "", http.StatusBadRequest, errors.New("invalid visibility")
	}
	err := db.WithUserRLS(ctx, s.pool, ownerID, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `
			UPDATE posts SET visibility = $1, updated_at = NOW()
			WHERE id = $2 AND author_id = $3
		`, v, postID, ownerID)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return errors.New("post not found")
		}
		_, _ = tx.Exec(ctx, `UPDATE videos SET visibility = $1, updated_at = NOW() WHERE post_id = $2 AND creator_id = $3`, v, postID, ownerID)
		return nil
	})
	if err != nil {
		return "", http.StatusNotFound, err
	}
	return v, http.StatusOK, nil
}

func (s *Service) SetPostEngagement(ctx context.Context, viewerID, postID uuid.UUID, action string, active bool) (int64, int64, int, error) {
	act := strings.ToLower(strings.TrimSpace(action))
	var likesCount, viewsCount int64
	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		switch act {
		case "like":
			if active {
				_, _ = tx.Exec(ctx, `INSERT INTO post_likes (post_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`, postID, viewerID)
			} else {
				_, _ = tx.Exec(ctx, `DELETE FROM post_likes WHERE post_id = $1 AND user_id = $2`, postID, viewerID)
			}
			_, _ = tx.Exec(ctx, `UPDATE posts SET likes_count = (SELECT COUNT(*) FROM post_likes WHERE post_id = $1) WHERE id = $1`, postID)
		case "save":
			if active {
				_, _ = tx.Exec(ctx, `INSERT INTO saved_posts (user_id, post_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`, viewerID, postID)
			} else {
				_, _ = tx.Exec(ctx, `DELETE FROM saved_posts WHERE user_id = $1 AND post_id = $2`, viewerID, postID)
			}
		case "repost":
			if active {
				_, _ = tx.Exec(ctx, `INSERT INTO post_reposts (user_id, post_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`, viewerID, postID)
			} else {
				_, _ = tx.Exec(ctx, `DELETE FROM post_reposts WHERE user_id = $1 AND post_id = $2`, viewerID, postID)
			}
		case "view":
			_, _ = tx.Exec(ctx, `UPDATE posts SET views_count = views_count + 1 WHERE id = $1`, postID)
		default:
			return errors.New("invalid action")
		}
		return tx.QueryRow(ctx, `SELECT likes_count, views_count FROM posts WHERE id = $1`, postID).Scan(&likesCount, &viewsCount)
	})
	if err != nil {
		return 0, 0, http.StatusBadRequest, err
	}
	return likesCount, viewsCount, http.StatusOK, nil
}
