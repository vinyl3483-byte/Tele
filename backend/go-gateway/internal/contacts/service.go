package contacts

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

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

type ContactDTO struct {
	UserID                string `json:"user_id"`
	FullName              string `json:"full_name"`
	Username              string `json:"username"`
	Location              string `json:"location"`
	AvatarFingerprintHash string `json:"avatar_fingerprint_hash"`
	IsFollowing           bool   `json:"is_following"`
	FollowsMe             bool   `json:"follows_me"`
	Relationship          string `json:"relationship"` // follow | follow_back | following | friends
	RiskScore             int    `json:"risk_score"`
}

type ContactsPageDTO struct {
	Contacts   []ContactDTO `json:"contacts"`
	NextCursor string       `json:"next_cursor"`
	HasMore    bool         `json:"has_more"`
}

type FollowActionRequest struct {
	TargetUserID string `json:"target_user_id"`
	Follow       bool   `json:"follow"`
}

type FollowActionResponse struct {
	TargetUserID string `json:"target_user_id"`
	IsFollowing  bool   `json:"is_following"`
	FollowsMe    bool   `json:"follows_me"`
	Relationship string `json:"relationship"`
	RiskScore    int    `json:"risk_score"`
}

func ComputeRelationship(isFollowing, followsMe bool) string {
	switch {
	case isFollowing && followsMe:
		return "friends"
	case isFollowing:
		return "following"
	case followsMe:
		return "follow_back"
	default:
		return "follow"
	}
}

func ComputeRiskScore(actionsLastMin, rateLimitHits, churnCount int) (int, string) {
	score := actionsLastMin + (rateLimitHits * 15) + (churnCount * 3)
	if score > 100 {
		score = 100
	}
	tier := "low"
	switch {
	case score >= 80:
		tier = "restricted"
	case score >= 50:
		tier = "high"
	case score >= 25:
		tier = "medium"
	}
	return score, tier
}

func (s *Service) ListContacts(
	ctx context.Context,
	viewerID uuid.UUID,
	filter string,
	query string,
	cursorStr string,
	limit int,
) (*ContactsPageDTO, int, error) {
	if limit <= 0 || limit > 50 {
		limit = 30
	}
	offset := 0
	if cursorStr != "" {
		if parsed, err := strconv.Atoi(cursorStr); err == nil && parsed >= 0 {
			offset = parsed
		}
	}
	normFilter := strings.ToLower(strings.TrimSpace(filter))
	if normFilter == "" {
		normFilter = "all"
	}
	normQuery := strings.ToLower(strings.TrimSpace(query))

	var matched []ContactDTO
	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT user_id, full_name_encrypted, username_encrypted, location_encrypted,
			       COALESCE(avatar_fingerprint_hash, ''), is_following, follows_me, risk_score
			FROM telefam_list_directory_profiles($1)
		`, viewerID)
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
			fullNameBytes, err1 := security.DecryptAtRest(s.cfg.MasterKey, encName, "profiles.full_name")
			usernameBytes, err2 := security.DecryptAtRest(s.cfg.MasterKey, encUser, "profiles.username")
			locBytes, _ := security.DecryptAtRest(s.cfg.MasterKey, encLoc, "profiles.location")
			if err1 != nil || err2 != nil {
				continue
			}

			fullName := string(fullNameBytes)
			username := string(usernameBytes)
			location := string(locBytes)
			rel := ComputeRelationship(isFollowing, followsMe)

			switch normFilter {
			case "suggestions":
				if isFollowing {
					continue
				}
			case "followers":
				if !followsMe {
					continue
				}
			case "following":
				if !isFollowing {
					continue
				}
			case "friends":
				if !(isFollowing && followsMe) {
					continue
				}
			}

			if normQuery != "" {
				if !strings.Contains(strings.ToLower(fullName), normQuery) &&
					!strings.Contains(strings.ToLower(username), normQuery) {
					continue
				}
			}

			matched = append(matched, ContactDTO{
				UserID:                uid.String(),
				FullName:              fullName,
				Username:              username,
				Location:              location,
				AvatarFingerprintHash: avatarFP,
				IsFollowing:           isFollowing,
				FollowsMe:             followsMe,
				Relationship:          rel,
				RiskScore:             riskScore,
			})
		}
		return rows.Err()
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}

	if offset >= len(matched) {
		return &ContactsPageDTO{
			Contacts:   []ContactDTO{},
			NextCursor: "",
			HasMore:    false,
		}, http.StatusOK, nil
	}
	end := offset + limit
	hasMore := false
	nextCursor := ""
	if end < len(matched) {
		hasMore = true
		nextCursor = strconv.Itoa(end)
	} else {
		end = len(matched)
	}

	return &ContactsPageDTO{
		Contacts:   matched[offset:end],
		NextCursor: nextCursor,
		HasMore:    hasMore,
	}, http.StatusOK, nil
}

func (s *Service) SetFollowState(
	ctx context.Context,
	viewerID uuid.UUID,
	targetID uuid.UUID,
	follow bool,
	deviceFP string,
	ipFP string,
) (*FollowActionResponse, int, error) {
	if targetID == uuid.Nil || targetID == viewerID {
		return nil, http.StatusBadRequest, errors.New("invalid target")
	}

	if !s.limiter.AllowFollowAction(ctx, viewerID.String(), deviceFP, ipFP) {
		s.recordRateLimitedAttempt(ctx, viewerID, targetID, deviceFP, ipFP)
		return nil, http.StatusTooManyRequests, errors.New("try again later")
	}

	actionType := "unfollow"
	if follow {
		actionType = "follow"
	}

	var isFollowing, followsMe bool
	var scoreAfter int
	err := db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		var outcome string
		if follow {
			tag, err := tx.Exec(ctx, `
				INSERT INTO user_follows (follower_id, followee_id)
				VALUES ($1, $2)
				ON CONFLICT (follower_id, followee_id) DO NOTHING
			`, viewerID, targetID)
			if err != nil {
				return err
			}
			if tag.RowsAffected() == 1 {
				outcome = "applied"
			} else {
				outcome = "noop"
			}
		} else {
			tag, err := tx.Exec(ctx, `
				DELETE FROM user_follows
				WHERE follower_id = $1 AND followee_id = $2
			`, viewerID, targetID)
			if err != nil {
				return err
			}
			if tag.RowsAffected() == 1 {
				outcome = "applied"
			} else {
				outcome = "noop"
			}
		}

		scoreAfter = s.updateRiskScoreTx(ctx, tx, viewerID, !follow && outcome == "applied", false)

		_, err := tx.Exec(ctx, `
			INSERT INTO contact_action_logs (
				actor_user_id, target_user_id, action_type, device_fp_hash, ip_fp_hash, risk_score_after, outcome
			) VALUES ($1, $2, $3, $4, $5, $6, $7)
		`, viewerID, targetID, actionType, padHex64(deviceFP), padHex64(ipFP), scoreAfter, outcome)
		if err != nil {
			return err
		}

		if err := tx.QueryRow(ctx, `
			SELECT
				EXISTS(SELECT 1 FROM user_follows WHERE follower_id = $1 AND followee_id = $2),
				EXISTS(SELECT 1 FROM user_follows WHERE follower_id = $2 AND followee_id = $1)
		`, viewerID, targetID).Scan(&isFollowing, &followsMe); err != nil {
			return err
		}
		return nil
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}

	return &FollowActionResponse{
		TargetUserID: targetID.String(),
		IsFollowing:  isFollowing,
		FollowsMe:    followsMe,
		Relationship: ComputeRelationship(isFollowing, followsMe),
		RiskScore:    scoreAfter,
	}, http.StatusOK, nil
}

func (s *Service) updateRiskScoreTx(ctx context.Context, tx pgx.Tx, userID uuid.UUID, isChurn, isRateLimited bool) int {
	now := time.Now().UTC()
	var actionsMin, rateHits, churn int
	var winStart time.Time
	err := tx.QueryRow(ctx, `
		SELECT actions_last_minute, rate_limit_hits, follow_churn_count, window_started_at
		FROM user_risk_scores
		WHERE user_id = $1
	`, userID).Scan(&actionsMin, &rateHits, &churn, &winStart)
	if err != nil {
		actionsMin = 0
		rateHits = 0
		churn = 0
		winStart = now
	}
	if now.Sub(winStart) > time.Minute {
		actionsMin = 1
		winStart = now
	} else {
		actionsMin++
	}
	if isChurn {
		churn++
	}
	if isRateLimited {
		rateHits++
	}
	score, tier := ComputeRiskScore(actionsMin, rateHits, churn)
	_, _ = tx.Exec(ctx, `
		INSERT INTO user_risk_scores (user_id, risk_score, risk_tier, actions_last_minute, rate_limit_hits, follow_churn_count, window_started_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
		ON CONFLICT (user_id) DO UPDATE SET
			risk_score = EXCLUDED.risk_score,
			risk_tier = EXCLUDED.risk_tier,
			actions_last_minute = EXCLUDED.actions_last_minute,
			rate_limit_hits = EXCLUDED.rate_limit_hits,
			follow_churn_count = EXCLUDED.follow_churn_count,
			window_started_at = EXCLUDED.window_started_at,
			updated_at = NOW()
	`, userID, score, tier, actionsMin, rateHits, churn, winStart)
	return score
}

func (s *Service) recordRateLimitedAttempt(ctx context.Context, viewerID, targetID uuid.UUID, deviceFP, ipFP string) {
	_ = db.WithUserRLS(ctx, s.pool, viewerID, func(tx pgx.Tx) error {
		scoreAfter := s.updateRiskScoreTx(ctx, tx, viewerID, false, true)
		_, err := tx.Exec(ctx, `
			INSERT INTO contact_action_logs (
				actor_user_id, target_user_id, action_type, device_fp_hash, ip_fp_hash, risk_score_after, outcome
			) VALUES ($1, $2, 'rate_limited', $3, $4, $5, 'blocked')
		`, viewerID, targetID, padHex64(deviceFP), padHex64(ipFP), scoreAfter)
		return err
	})
}

func padHex64(in string) string {
	s := strings.TrimSpace(in)
	if len(s) >= 64 {
		return s[:64]
	}
	return s + strings.Repeat("0", 64-len(s))
}
