package profile

import (
	"context"
	"errors"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/telefam/company/backend/go-gateway/internal/contacts"
	"github.com/telefam/company/backend/go-gateway/internal/db"
	"github.com/telefam/company/backend/go-gateway/internal/feed"
	"github.com/telefam/company/backend/go-gateway/internal/security"
)

type OtherUserProfileDTO struct {
	UserID                string               `json:"user_id"`
	FullName              string               `json:"full_name"`
	Nickname              string               `json:"nickname"`
	Username              string               `json:"username"`
	Location              string               `json:"location"`
	Bio                   string               `json:"bio"`
	AvatarFingerprintHash string               `json:"avatar_fingerprint_hash"`
	AvatarURL             string               `json:"avatar_url"`
	FollowersCount        int64                `json:"followers_count"`
	FollowingCount        int64                `json:"following_count"`
	SubscribersCount      int64                `json:"subscribers_count"`
	PostsCount            int64                `json:"posts_count"`
	IsFollowing           bool                 `json:"is_following"`
	FollowsMe             bool                 `json:"follows_me"`
	Relationship          string               `json:"relationship"`
	IsBlocked             bool                 `json:"is_blocked"`
	IsBlockedBy           bool                 `json:"is_blocked_by"`
	IsMuted               bool                 `json:"is_muted"`
	BackgroundPhotos      []BackgroundPhotoDTO `json:"background_photos"`
}

func (s *Service) listPublicBackgroundPhotosTx(ctx context.Context, tx pgx.Tx, targetUserID uuid.UUID) ([]BackgroundPhotoDTO, error) {
	rows, err := tx.Query(ctx, `
		SELECT id, sort_order, fingerprint_hash, width, height
		FROM profile_backgrounds
		WHERE user_id = $1
		ORDER BY sort_order ASC, created_at ASC
		LIMIT 5
	`, targetUserID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]BackgroundPhotoDTO, 0, MaxBackgroundPhotos)
	prefix := "/v1/users/" + targetUserID.String() + "/backgrounds/"
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
				URL:             prefix + id.String() + "?v=" + fp,
			})
		}
	}
	return out, rows.Err()
}

func (s *Service) loadViewerNicknamesTx(ctx context.Context, tx pgx.Tx, viewerID uuid.UUID) map[uuid.UUID]string {
	out := make(map[uuid.UUID]string)
	rows, err := tx.Query(ctx, `
		SELECT target_user_id, nickname_encrypted
		FROM user_nicknames
		WHERE owner_id = $1
	`, viewerID)
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var tid uuid.UUID
		var enc []byte
		if err := rows.Scan(&tid, &enc); err == nil {
			if plain, dErr := security.DecryptAtRest(s.cfg.MasterKey, enc, "user_nicknames.nickname"); dErr == nil {
				val := strings.TrimSpace(string(plain))
				if val != "" {
					out[tid] = val
				}
			}
		}
	}
	return out
}

func (s *Service) ListViewerNicknames(ctx context.Context, viewerID uuid.UUID) (map[string]string, int, error) {
	res := make(map[string]string)
	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		nickMap := s.loadViewerNicknamesTx(ctx, tx, viewerID)
		for tid, nick := range nickMap {
			res[tid.String()] = nick
		}
		return nil
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return res, http.StatusOK, nil
}

func (s *Service) GetOtherUserProfile(ctx context.Context, viewerID, targetID uuid.UUID) (*OtherUserProfileDTO, int, error) {
	if targetID == uuid.Nil {
		return nil, http.StatusBadRequest, errors.New("invalid user")
	}

	var out OtherUserProfileDTO
	out.BackgroundPhotos = []BackgroundPhotoDTO{}

	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		var uid uuid.UUID
		var encName, encUser, encLoc, encBio []byte
		var avatarFP string
		var isFollowing, followsMe, isBlocked, isBlockedBy, isMuted bool
		var followersCnt, followingCnt, subsCnt, postsCnt int64

		err := tx.QueryRow(ctx, `
			SELECT user_id, full_name_encrypted, username_encrypted, location_encrypted, bio_encrypted,
			       avatar_fingerprint_hash, is_following, follows_me, is_blocked, is_blocked_by, is_muted,
			       followers_count, following_count, subscribers_count, posts_count
			FROM telefam_get_user_public_profile($1, $2)
		`, viewerID, targetID).Scan(
			&uid, &encName, &encUser, &encLoc, &encBio,
			&avatarFP, &isFollowing, &followsMe, &isBlocked, &isBlockedBy, &isMuted,
			&followersCnt, &followingCnt, &subsCnt, &postsCnt,
		)
		if err != nil {
			return err
		}

		out.UserID = uid.String()
		if b, dErr := security.DecryptAtRest(s.cfg.MasterKey, encName, "profiles.full_name"); dErr == nil && len(b) > 0 {
			out.FullName = string(b)
		} else if b, dErr := security.DecryptAtRest(s.cfg.MasterKey, encName, "users.display_name"); dErr == nil && len(b) > 0 {
			out.FullName = string(b)
		}
		if b, dErr := security.DecryptAtRest(s.cfg.MasterKey, encUser, "profiles.username"); dErr == nil {
			out.Username = string(b)
		}
		if b, dErr := security.DecryptAtRest(s.cfg.MasterKey, encLoc, "profiles.location"); dErr == nil {
			out.Location = string(b)
		}
		if b, dErr := security.DecryptAtRest(s.cfg.MasterKey, encBio, "profiles.bio"); dErr == nil {
			out.Bio = string(b)
		}
		avatarFP = strings.TrimSpace(avatarFP)
		out.AvatarFingerprintHash = avatarFP
		if avatarFP != "" {
			out.AvatarURL = "/v1/users/" + uid.String() + "/avatar?v=" + avatarFP
		}
		out.IsFollowing = isFollowing
		out.FollowsMe = followsMe
		out.Relationship = contacts.ComputeRelationship(isFollowing, followsMe)
		out.IsBlocked = isBlocked
		out.IsBlockedBy = isBlockedBy
		out.IsMuted = isMuted
		out.FollowersCount = followersCnt
		out.FollowingCount = followingCnt
		out.SubscribersCount = subsCnt
		out.PostsCount = postsCnt

		// Load viewer's personal TikTok-style nickname for this user if set
		var encNick []byte
		if nErr := tx.QueryRow(ctx, `
			SELECT nickname_encrypted FROM user_nicknames
			WHERE owner_id = $1 AND target_user_id = $2
		`, viewerID, targetID).Scan(&encNick); nErr == nil {
			if nb, dErr := security.DecryptAtRest(s.cfg.MasterKey, encNick, "user_nicknames.nickname"); dErr == nil {
				out.Nickname = strings.TrimSpace(string(nb))
			}
		}

		if isBlocked || isBlockedBy {
			out.Bio = ""
			out.PostsCount = 0
			out.BackgroundPhotos = []BackgroundPhotoDTO{}
			return nil
		}

		if bgs, bgErr := s.listPublicBackgroundPhotosTx(ctx, tx, targetID); bgErr == nil && bgs != nil {
			out.BackgroundPhotos = bgs
		}
		return nil
	})
	if err != nil {
		return nil, http.StatusNotFound, err
	}
	return &out, http.StatusOK, nil
}

func (s *Service) GetOtherUserBackgroundPhotoBytes(ctx context.Context, viewerID, targetID, bgID uuid.UUID) ([]byte, string, string, int, error) {
	var encBytes []byte
	var mimeType, fpHash string
	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT mime_type, fingerprint_hash, sanitized_bytes_encrypted
			FROM profile_backgrounds WHERE id = $1 AND user_id = $2
		`, bgID, targetID).Scan(&mimeType, &fpHash, &encBytes)
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

func (s *Service) GetOtherUserProfileItems(
	ctx context.Context,
	feedSvc *feed.Service,
	viewerID, targetID uuid.UUID,
	tab, cursorStr string,
	limit int,
) (*OwnerProfileItemsPageDTO, int, error) {
	normTab := strings.ToLower(strings.TrimSpace(tab))
	switch normTab {
	case "", "posts":
		normTab = "posts"
	case "reposts":
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

	allItems := make([]OwnerProfileItemDTO, 0, 24)
	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		var blocked bool
		_ = tx.QueryRow(ctx, `
			SELECT EXISTS(
				SELECT 1 FROM blocked_users
				WHERE (user_id = $1 AND blocked_user_id = $2) OR (user_id = $2 AND blocked_user_id = $1)
			)
		`, viewerID, targetID).Scan(&blocked)
		if blocked {
			return nil
		}

		var postWhere string
		if normTab == "posts" {
			postWhere = `p.author_id = $2 AND p.status = 'ready' AND p.visibility <> 'private' AND COALESCE(v.visibility, p.visibility) <> 'private'`
		} else {
			postWhere = `p.status = 'ready' AND p.visibility <> 'private' AND COALESCE(v.visibility, p.visibility) <> 'private' AND (
				EXISTS (SELECT 1 FROM post_reposts pr WHERE pr.post_id = p.id AND pr.user_id = $2)
				OR (v.id IS NOT NULL AND EXISTS (SELECT 1 FROM reposts r WHERE r.video_id = v.id AND r.user_id = $2))
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
		`, viewerID, targetID)
		if err != nil {
			return err
		}

		type rawRow struct {
			postID     uuid.UUID
			videoIDStr string
			item       OwnerProfileItemDTO
		}
		collected := make([]rawRow, 0, 24)
		postIDs := make([]uuid.UUID, 0, 24)
		videoIDs := make([]uuid.UUID, 0, 24)
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

		var extraWhere string
		if normTab == "posts" {
			extraWhere = `AND v.creator_id = $1 AND v.post_id IS NULL AND v.visibility <> 'private'`
		} else {
			extraWhere = `AND v.post_id IS NULL AND v.visibility <> 'private' AND EXISTS (SELECT 1 FROM reposts r WHERE r.video_id = v.id AND r.user_id = $1)`
		}
		vExtraRows, _ := tx.Query(ctx, `SELECT v.id FROM videos v WHERE v.processing_status = 'ready' `+extraWhere, targetID)
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

		var videoMap map[string]feed.FeedVideoDTO
		if feedSvc != nil && len(videoIDs) > 0 {
			videoMap, _ = feedSvc.QueryFeedVideosByIDs(ctx, tx, viewerID, videoIDs)
		}

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
						tok := s.signPostPhotoToken(mid, viewerID, exp)
						photoURLsByPost[pid] = append(photoURLsByPost[pid], "/v1/posts/media/signed/"+tok)
					}
				}
				pRows.Close()
			}
			hRows, hErr := tx.Query(ctx, `SELECT post_id, tag_normalized FROM post_hashtags WHERE post_id = ANY($1)`, postIDs)
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

func (s *Service) ListOtherUserConnections(ctx context.Context, viewerID, targetID uuid.UUID, kind string) ([]contacts.ContactDTO, int, error) {
	normKind := strings.ToLower(strings.TrimSpace(kind))
	if normKind != "following" {
		normKind = "followers"
	}
	out := make([]contacts.ContactDTO, 0)
	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		nickMap := s.loadViewerNicknamesTx(ctx, tx, viewerID)
		rows, err := tx.Query(ctx, `
			SELECT user_id, full_name_encrypted, username_encrypted, location_encrypted,
			       COALESCE(avatar_fingerprint_hash, ''), is_following, follows_me, risk_score
			FROM telefam_list_user_connections($1, $2, $3)
		`, viewerID, targetID, normKind)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var uid uuid.UUID
			var encName, encUser, encLoc []byte
			var avatarFP string
			var isFollowing, followsMe bool
			var riskScore int
			if err := rows.Scan(&uid, &encName, &encUser, &encLoc, &avatarFP, &isFollowing, &followsMe, &riskScore); err != nil {
				return err
			}
			fullName := ""
			if b, dErr := security.DecryptAtRest(s.cfg.MasterKey, encName, "profiles.full_name"); dErr == nil && len(b) > 0 {
				fullName = string(b)
			} else if b, dErr := security.DecryptAtRest(s.cfg.MasterKey, encName, "users.display_name"); dErr == nil && len(b) > 0 {
				fullName = string(b)
			}
			if nick, ok := nickMap[uid]; ok && nick != "" {
				fullName = nick
			}
			username := ""
			if b, dErr := security.DecryptAtRest(s.cfg.MasterKey, encUser, "profiles.username"); dErr == nil {
				username = string(b)
			}
			location := ""
			if b, dErr := security.DecryptAtRest(s.cfg.MasterKey, encLoc, "profiles.location"); dErr == nil {
				location = string(b)
			}
			out = append(out, contacts.ContactDTO{
				UserID:                uid.String(),
				FullName:              fullName,
				Username:              username,
				Location:              location,
				AvatarFingerprintHash: strings.TrimSpace(avatarFP),
				IsFollowing:           isFollowing,
				FollowsMe:             followsMe,
				Relationship:          contacts.ComputeRelationship(isFollowing, followsMe),
				RiskScore:             riskScore,
			})
		}
		return rows.Err()
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return out, http.StatusOK, nil
}

func (s *Service) SetUserNickname(ctx context.Context, viewerID, targetID uuid.UUID, rawNickname string) (string, int, error) {
	if targetID == uuid.Nil || targetID == viewerID {
		return "", http.StatusBadRequest, errors.New("invalid target")
	}
	clean := strings.TrimSpace(rawNickname)
	if len([]rune(clean)) > 60 {
		clean = string([]rune(clean)[:60])
	}

	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		if clean == "" {
			_, err := tx.Exec(ctx, `
				DELETE FROM user_nicknames WHERE owner_id = $1 AND target_user_id = $2
			`, viewerID, targetID)
			return err
		}
		enc, eErr := security.EncryptAtRest(s.cfg.MasterKey, []byte(clean), "user_nicknames.nickname")
		if eErr != nil {
			return eErr
		}
		_, err := tx.Exec(ctx, `
			INSERT INTO user_nicknames (owner_id, target_user_id, nickname_encrypted, updated_at)
			VALUES ($1, $2, $3, NOW())
			ON CONFLICT (owner_id, target_user_id) DO UPDATE SET
				nickname_encrypted = EXCLUDED.nickname_encrypted,
				updated_at = NOW()
		`, viewerID, targetID, enc)
		return err
	})
	if err != nil {
		return "", http.StatusInternalServerError, err
	}
	return clean, http.StatusOK, nil
}

func (s *Service) SubmitUserReport(ctx context.Context, viewerID, targetID uuid.UUID, category, subReason, details string) (int, error) {
	if targetID == uuid.Nil || targetID == viewerID {
		return http.StatusBadRequest, errors.New("invalid target")
	}
	normCat := strings.ToLower(strings.TrimSpace(category))
	switch normCat {
	case "spam", "harassment", "impersonation", "hate_speech",
		"violence", "nudity_or_sexual_content", "scam_or_fraud", "misinformation", "other":
	default:
		return http.StatusBadRequest, errors.New("invalid report category")
	}
	cleanSub := strings.TrimSpace(subReason)
	if len([]rune(cleanSub)) > 120 {
		cleanSub = string([]rune(cleanSub)[:120])
	}
	cleanDetails := strings.TrimSpace(details)
	if len([]rune(cleanDetails)) > 800 {
		cleanDetails = string([]rune(cleanDetails)[:800])
	}
	encDetails, err := security.EncryptAtRest(s.cfg.MasterKey, []byte(cleanDetails), "user_reports.details")
	if err != nil {
		return http.StatusInternalServerError, err
	}

	err = db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO user_reports (target_user_id, reporter_id, category, sub_reason, details_encrypted, status)
			VALUES ($1, $2, $3, $4, $5, 'open')
		`, targetID, viewerID, normCat, cleanSub, encDetails)
		return err
	})
	if err != nil {
		return http.StatusBadRequest, err
	}
	return http.StatusCreated, nil
}
