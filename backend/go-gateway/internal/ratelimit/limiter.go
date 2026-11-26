package ratelimit

import (
	"context"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/telefam/company/backend/go-gateway/internal/db"
)

type BucketRule struct {
	MaxRequests int
	Window      time.Duration
}

type Limiter struct {
	mu      sync.Mutex
	buckets map[string][]time.Time
	pool    *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Limiter {
	return &Limiter{
		buckets: make(map[string][]time.Time),
		pool:    pool,
	}
}

// AllowMulti enforces per-account, per-device, and per-IP sliding window limits simultaneously for auth routes.
func (l *Limiter) AllowMulti(ctx context.Context, accountHash, deviceFP, ipFP string) bool {
	return l.allowRules(ctx, []struct {
		key  string
		rule BucketRule
	}{
		{"acc:" + accountHash, BucketRule{MaxRequests: 8, Window: 1 * time.Minute}},
		{"dev:" + deviceFP, BucketRule{MaxRequests: 25, Window: 1 * time.Minute}},
		{"ip:" + ipFP, BucketRule{MaxRequests: 40, Window: 1 * time.Minute}},
	}, "ip:"+ipFP, 40)
}

// AllowAuthenticatedAPI limits general authenticated API calls without blocking 50/min follow bursts.
func (l *Limiter) AllowAuthenticatedAPI(ctx context.Context, userID, deviceFP, ipFP string) bool {
	return l.allowRules(ctx, []struct {
		key  string
		rule BucketRule
	}{
		{"api_u:" + userID, BucketRule{MaxRequests: 120, Window: 1 * time.Minute}},
		{"api_d:" + deviceFP, BucketRule{MaxRequests: 150, Window: 1 * time.Minute}},
		{"api_i:" + ipFP, BucketRule{MaxRequests: 180, Window: 1 * time.Minute}},
	}, "api_i:"+ipFP, 180)
}

// AllowFollowAction strictly enforces 50 follow/unfollow actions per minute per user.
func (l *Limiter) AllowFollowAction(ctx context.Context, userID, deviceFP, ipFP string) bool {
	return l.allowRules(ctx, []struct {
		key  string
		rule BucketRule
	}{
		{"follow_u:" + userID, BucketRule{MaxRequests: 50, Window: 1 * time.Minute}},
		{"follow_d:" + deviceFP, BucketRule{MaxRequests: 60, Window: 1 * time.Minute}},
		{"follow_i:" + ipFP, BucketRule{MaxRequests: 80, Window: 1 * time.Minute}},
	}, "follow_u:"+userID, 50)
}

func (l *Limiter) allowRules(ctx context.Context, rules []struct {
	key  string
	rule BucketRule
}, persistKey string, persistLimit int) bool {
	now := time.Now().UTC()

	l.mu.Lock()
	for _, item := range rules {
		if item.key == "" || item.key[len(item.key)-1] == ':' {
			continue
		}
		ts := l.buckets[item.key]
		cutoff := now.Add(-item.rule.Window)
		valid := ts[:0]
		for _, t := range ts {
			if t.After(cutoff) {
				valid = append(valid, t)
			}
		}
		if len(valid) >= item.rule.MaxRequests {
			l.buckets[item.key] = valid
			l.mu.Unlock()
			return false
		}
		l.buckets[item.key] = append(valid, now)
	}
	l.mu.Unlock()

	if l.pool != nil && persistKey != "" && persistLimit > 0 {
		var countAfter int
		err := db.WithAuthWorkerRLS(ctx, l.pool, func(tx pgx.Tx) error {
			return tx.QueryRow(ctx, `
				INSERT INTO rate_limit_buckets (bucket_key, window_start, request_count)
				VALUES ($1, $2, 1)
				ON CONFLICT (bucket_key) DO UPDATE SET
					request_count = CASE
						WHEN rate_limit_buckets.window_start < $2 - INTERVAL '1 minute' THEN 1
						ELSE rate_limit_buckets.request_count + 1
					END,
					window_start = CASE
						WHEN rate_limit_buckets.window_start < $2 - INTERVAL '1 minute' THEN $2
						ELSE rate_limit_buckets.window_start
					END
				RETURNING request_count
			`, persistKey, now).Scan(&countAfter)
		})
		if err == nil && countAfter > persistLimit {
			return false
		}
	}
	return true
}

// CooldownDuration implements: 1m x 3 times -> 15m -> 1h -> 1 day.
func CooldownDuration(resendCount int) time.Duration {
	switch {
	case resendCount <= 3:
		return 1 * time.Minute
	case resendCount == 4:
		return 15 * time.Minute
	case resendCount == 5:
		return 1 * time.Hour
	default:
		return 24 * time.Hour
	}
}
