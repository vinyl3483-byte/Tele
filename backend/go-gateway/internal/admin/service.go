package admin

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"os"
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

const (
	MaxFailedLoginAttempts = 3
	LockoutDuration        = 12 * time.Minute
	SessionTTL             = 12 * time.Hour
)

var AllowedStaffPermissions = map[string]struct{}{
	"view_users":          {},
	"view_posts":          {},
	"view_logs":           {},
	"remove_posts":        {},
	"request_delete_user": {},
	"suspend_users":       {},
	"sanitize_media":      {},
}

type Service struct {
	cfg  *config.Config
	pool *pgxpool.Pool
}

func NewService(cfg *config.Config, pool *pgxpool.Pool) *Service {
	return &Service{cfg: cfg, pool: pool}
}

type AdminPrincipal struct {
	ID                 uuid.UUID `json:"id"`
	Email              string    `json:"email"`
	FullName           string    `json:"full_name"`
	Role               string    `json:"role"`
	GrantedPermissions []string  `json:"granted_permissions"`
	MustChangePassword bool      `json:"must_change_password"`
	IsPaused           bool      `json:"is_paused"`
}

func (p *AdminPrincipal) HasPermission(perm string) bool {
	if p.IsPaused {
		return false
	}
	if p.Role == "super_admin" {
		return true
	}
	for _, g := range p.GrantedPermissions {
		if g == perm {
			return true
		}
	}
	return false
}

type LoginResponse struct {
	Token              string          `json:"token,omitempty"`
	ExpiresIn          int64           `json:"expires_in,omitempty"`
	MustChangePassword bool            `json:"must_change_password"`
	Admin              *AdminPrincipal `json:"admin,omitempty"`
	Locked             bool            `json:"locked,omitempty"`
	RetryAfterSeconds  int64           `json:"retry_after_seconds,omitempty"`
	Error              string          `json:"error,omitempty"`
}

type DashboardStatsDTO struct {
	TotalUsers        int64            `json:"total_users"`
	TotalPosts        int64            `json:"total_posts"`
	TotalStaff        int64            `json:"total_staff"`
	PausedStaff       int64            `json:"paused_staff"`
	PendingApprovals  int64            `json:"pending_approvals"`
	ActiveLockouts    int64            `json:"active_lockouts"`
	RecentActivityLog []ActivityLogDTO `json:"recent_logs"`
}

type UserRecordDTO struct {
	UserID           string `json:"user_id"`
	Email            string `json:"email"`
	FullName         string `json:"full_name"`
	Username         string `json:"username"`
	AuthProvider     string `json:"auth_provider"`
	ProfileCompleted bool   `json:"profile_completed"`
	IsSuspended      bool   `json:"is_suspended"`
	RiskScore        int    `json:"risk_score"`
	CreatedAt        int64  `json:"created_at"`
}

type PostRecordDTO struct {
	PostID            string `json:"post_id"`
	AuthorID          string `json:"author_id"`
	AuthorName        string `json:"author_name"`
	AuthorHandle      string `json:"author_handle"`
	PostType          string `json:"post_type"`
	Body              string `json:"body"`
	MediaCount        int    `json:"media_count"`
	PrimaryMediaID    string `json:"primary_media_id"`
	ContentFP         string `json:"content_fingerprint_hash"`
	CreatedAt         int64  `json:"created_at"`
}

type StaffMemberDTO struct {
	ID                 string   `json:"id"`
	Email              string   `json:"email"`
	FullName           string   `json:"full_name"`
	Role               string   `json:"role"`
	GrantedPermissions []string `json:"granted_permissions"`
	MustChangePassword bool     `json:"must_change_password"`
	IsPaused           bool     `json:"is_paused"`
	FailedAttempts     int      `json:"failed_attempts"`
	LockedUntilMs      int64    `json:"locked_until_ms"`
	LastActiveAtMs     int64    `json:"last_active_at_ms"`
	CreatedAtMs        int64    `json:"created_at_ms"`
}

type ActivityLogDTO struct {
	ID           string `json:"id"`
	Source       string `json:"source"` // admin | user_risk
	ActorID      string `json:"actor_id"`
	ActorEmail   string `json:"actor_email"`
	ActorRole    string `json:"actor_role"`
	ActionType   string `json:"action_type"`
	TargetUserID string `json:"target_user_id"`
	TargetPostID string `json:"target_post_id"`
	Outcome      string `json:"outcome"`
	CreatedAt    int64  `json:"created_at"`
}

type ApprovalRequestDTO struct {
	ID                string `json:"id"`
	RequestedByID     string `json:"requested_by_id"`
	RequestedByEmail  string `json:"requested_by_email"`
	RequestedByRole   string `json:"requested_by_role"`
	ActionType        string `json:"action_type"`
	TargetUserID      string `json:"target_user_id"`
	TargetUserEmail   string `json:"target_user_email"`
	TargetPostID      string `json:"target_post_id"`
	Reason            string `json:"reason"`
	Status            string `json:"status"`
	ReviewedByEmail   string `json:"reviewed_by_email"`
	ReviewNote        string `json:"review_note"`
	CreatedAt         int64  `json:"created_at"`
	ReviewedAt        int64  `json:"reviewed_at"`
}

func sanitizePermissions(perms []string) []string {
	seen := make(map[string]struct{}, len(perms))
	out := make([]string, 0, len(perms))
	for _, p := range perms {
		norm := strings.ToLower(strings.TrimSpace(p))
		if _, ok := AllowedStaffPermissions[norm]; ok {
			if _, exists := seen[norm]; !exists {
				seen[norm] = struct{}{}
				out = append(out, norm)
			}
		}
	}
	return out
}

func defaultPermissionsForRole(role string) []string {
	switch role {
	case "super_admin":
		return []string{"view_users", "view_posts", "view_logs", "remove_posts", "request_delete_user", "suspend_users", "sanitize_media"}
	case "admin":
		return []string{"view_users", "view_posts", "view_logs", "remove_posts", "request_delete_user", "suspend_users", "sanitize_media"}
	default: // moderator
		return []string{"view_users", "view_posts", "remove_posts", "request_delete_user"}
	}
}

func (s *Service) EnsureBootstrapFromEnv(ctx context.Context) error {
	if s.cfg.SuperAdminEmail == "" || s.cfg.SuperAdminPassword == "" {
		return nil
	}
	if err := security.ValidatePasswordStrength(s.cfg.SuperAdminPassword); err != nil {
		return err
	}
	initialized, err := s.IsInitialized(ctx)
	if err != nil || initialized {
		return err
	}
	_, _, err = s.BootstrapSuperAdmin(ctx, s.cfg.SuperAdminEmail, "Super Admin", s.cfg.SuperAdminPassword)
	return err
}

func (s *Service) IsInitialized(ctx context.Context) (bool, error) {
	var count int64
	err := db.WithAdminBypassRLS(ctx, s.pool, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT COUNT(*) FROM admin_accounts
			WHERE role = 'super_admin' AND is_removed = FALSE
		`).Scan(&count)
	})
	return count > 0, err
}

func (s *Service) BootstrapSuperAdmin(ctx context.Context, rawEmail, fullName, password string) (*AdminPrincipal, int, error) {
	email := strings.ToLower(strings.TrimSpace(rawEmail))
	if !strings.Contains(email, "@") || len(email) < 5 {
		return nil, http.StatusBadRequest, errors.New("invalid email")
	}
	name := strings.TrimSpace(fullName)
	if len(name) < 2 {
		name = "Super Admin"
	}
	if err := security.ValidatePasswordStrength(password); err != nil {
		return nil, http.StatusBadRequest, err
	}
	pwHash, err := security.HashPassword(password)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	emailHash := security.HashEmail(s.cfg.HMACPepper, email)
	encEmail, _ := security.EncryptAtRest(s.cfg.MasterKey, []byte(email), "admin_accounts.email")
	encName, _ := security.EncryptAtRest(s.cfg.MasterKey, []byte(name), "admin_accounts.full_name")
	perms := defaultPermissionsForRole("super_admin")
	permsJSON, _ := json.Marshal(perms)

	adminID := uuid.New()
	err = db.WithAdminBypassRLS(ctx, s.pool, func(tx pgx.Tx) error {
		// Transaction-level advisory lock prevents race condition on initial bootstrap claim
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(73530421)`); err != nil {
			return err
		}
		var count int64
		if err := tx.QueryRow(ctx, `SELECT COUNT(*) FROM admin_accounts WHERE role = 'super_admin' AND is_removed = FALSE`).Scan(&count); err != nil {
			return err
		}
		if count > 0 {
			return errors.New("already initialized")
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO admin_accounts (
				id, email_hash, email_encrypted, full_name_encrypted, password_hash,
				role, granted_permissions, must_change_password
			) VALUES ($1,$2,$3,$4,$5,'super_admin',$6::jsonb, FALSE)
		`, adminID, emailHash, encEmail, encName, pwHash, string(permsJSON)); err != nil {
			return err
		}
		_, _ = tx.Exec(ctx, `
			INSERT INTO admin_audit_logs (actor_admin_id, actor_role, action_type, outcome)
			VALUES ($1, 'super_admin', 'super_admin_bootstrap', 'success')
		`, adminID)
		return nil
	})
	if err != nil {
		if err.Error() == "already initialized" {
			return nil, http.StatusConflict, err
		}
		return nil, http.StatusInternalServerError, err
	}

	return &AdminPrincipal{
		ID:                 adminID,
		Email:              email,
		FullName:           name,
		Role:               "super_admin",
		GrantedPermissions: perms,
		MustChangePassword: false,
	}, http.StatusCreated, nil
}

func (s *Service) Login(ctx context.Context, rawEmail, password, ipFP, userAgent string) (*LoginResponse, int) {
	email := strings.ToLower(strings.TrimSpace(rawEmail))
	if email == "" || password == "" {
		return &LoginResponse{Error: "Invalid credentials."}, http.StatusBadRequest
	}
	emailHash := security.HashEmail(s.cfg.HMACPepper, email)
	emailLockKey := "email:" + emailHash
	ipLockKey := "ip:" + ipFP
	now := time.Now().UTC()

	// 1. Check persisted 3-failed-attempt / 12-minute lockout across BOTH email and IP
	var lockedUntil time.Time
	var isLocked bool
	_ = db.WithAdminBypassRLS(ctx, s.pool, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT locked_until
			FROM admin_login_lockouts
			WHERE lock_key IN ($1, $2) AND locked_until IS NOT NULL AND locked_until > $3
			ORDER BY locked_until DESC LIMIT 1
		`, emailLockKey, ipLockKey, now)
		if err != nil {
			return err
		}
		defer rows.Close()
		if rows.Next() {
			if err := rows.Scan(&lockedUntil); err == nil && lockedUntil.After(now) {
				isLocked = true
			}
		}
		return nil
	})
	if isLocked {
		retrySec := int64(lockedUntil.Sub(now).Seconds())
		if retrySec < 1 {
			retrySec = 1
		}
		return &LoginResponse{
			Locked:            true,
			RetryAfterSeconds: retrySec,
			Error:             "Too many failed attempts. Try again later.",
		}, http.StatusLocked
	}

	// 2. Fetch account & verify password
	var adminID uuid.UUID
	var encEmail, encName []byte
	var pwHash, role string
	var permsRaw []byte
	var mustChange, isPaused, isRemoved bool
	var found bool

	_ = db.WithAdminBypassRLS(ctx, s.pool, func(tx pgx.Tx) error {
		err := tx.QueryRow(ctx, `
			SELECT id, email_encrypted, full_name_encrypted, password_hash, role, granted_permissions,
			       must_change_password, is_paused, is_removed
			FROM admin_accounts
			WHERE email_hash = $1
		`, emailHash).Scan(&adminID, &encEmail, &encName, &pwHash, &role, &permsRaw, &mustChange, &isPaused, &isRemoved)
		if err == nil {
			found = true
		}
		return nil
	})

	passwordValid := found && !isRemoved && security.VerifyPassword(password, pwHash)
	if !passwordValid {
		lockedNow, retrySec := s.recordFailedLoginAttempt(ctx, emailLockKey, ipLockKey, adminID, role, ipFP)
		if lockedNow {
			return &LoginResponse{
				Locked:            true,
				RetryAfterSeconds: retrySec,
				Error:             "Too many failed attempts. Locked for 12 minutes.",
			}, http.StatusLocked
		}
		return &LoginResponse{
			Error: "Invalid email or password.",
		}, http.StatusUnauthorized
	}

	if isPaused {
		_ = db.WithAdminBypassRLS(ctx, s.pool, func(tx pgx.Tx) error {
			_, _ = tx.Exec(ctx, `
				INSERT INTO admin_audit_logs (actor_admin_id, actor_role, action_type, ip_fp_hash, outcome)
				VALUES ($1, $2, 'admin_login_blocked_paused', $3, 'blocked')
			`, adminID, role, ipFP)
			return nil
		})
		return &LoginResponse{
			Error: "Account activity is paused.",
		}, http.StatusForbidden
	}

	rawTokenBytes := make([]byte, 32)
	if _, err := rand.Read(rawTokenBytes); err != nil {
		return &LoginResponse{Error: "Error has occurred, try again later."}, http.StatusInternalServerError
	}
	rawToken := hex.EncodeToString(rawTokenBytes)
	tokenHMAC := security.HMACSHA256Hex(s.cfg.HMACPepper, rawToken)
	uaHash := security.HMACSHA256Hex(s.cfg.HMACPepper, userAgent)

	err := db.WithAdminBypassRLSAs(ctx, s.pool, adminID, func(tx pgx.Tx) error {
		// Clear email lockout counter on success
		_, _ = tx.Exec(ctx, `DELETE FROM admin_login_lockouts WHERE lock_key = $1`, emailLockKey)
		_, _ = tx.Exec(ctx, `
			UPDATE admin_accounts
			SET failed_attempts = 0, locked_until = NULL, last_active_at = NOW(), updated_at = NOW()
			WHERE id = $1
		`, adminID)
		if _, err := tx.Exec(ctx, `
			INSERT INTO admin_sessions (admin_id, token_hmac, ip_fp_hash, user_agent_hash, expires_at)
			VALUES ($1, $2, $3, $4, $5)
		`, adminID, tokenHMAC, ipFP, uaHash, now.Add(SessionTTL)); err != nil {
			return err
		}
		_, _ = tx.Exec(ctx, `
			INSERT INTO admin_audit_logs (actor_admin_id, actor_role, action_type, ip_fp_hash, outcome)
			VALUES ($1, $2, 'admin_login', $3, 'success')
		`, adminID, role, ipFP)
		return nil
	})
	if err != nil {
		return &LoginResponse{Error: "Error has occurred, try again later."}, http.StatusInternalServerError
	}

	var perms []string
	_ = json.Unmarshal(permsRaw, &perms)
	plainEmail := email
	if b, dErr := security.DecryptAtRest(s.cfg.MasterKey, encEmail, "admin_accounts.email"); dErr == nil {
		plainEmail = string(b)
	}
	plainName := role
	if b, dErr := security.DecryptAtRest(s.cfg.MasterKey, encName, "admin_accounts.full_name"); dErr == nil {
		plainName = string(b)
	}

	return &LoginResponse{
		Token:              rawToken,
		ExpiresIn:          int64(SessionTTL.Seconds()),
		MustChangePassword: mustChange,
		Admin: &AdminPrincipal{
			ID:                 adminID,
			Email:              plainEmail,
			FullName:           plainName,
			Role:               role,
			GrantedPermissions: perms,
			MustChangePassword: mustChange,
			IsPaused:           false,
		},
	}, http.StatusOK
}

func (s *Service) recordFailedLoginAttempt(ctx context.Context, emailLockKey, ipLockKey string, adminID uuid.UUID, role, ipFP string) (bool, int64) {
	now := time.Now().UTC()
	var locked bool
	var maxRetry int64

	_ = db.WithAdminBypassRLS(ctx, s.pool, func(tx pgx.Tx) error {
		for _, k := range []string{emailLockKey, ipLockKey} {
			var attempts int
			var lastAttempt time.Time
			var curLockedUntil *time.Time
			err := tx.QueryRow(ctx, `
				SELECT failed_attempts, last_attempt_at, locked_until
				FROM admin_login_lockouts WHERE lock_key = $1 FOR UPDATE
			`, k).Scan(&attempts, &lastAttempt, &curLockedUntil)
			if err != nil {
				attempts = 0
			} else if curLockedUntil != nil && now.After(*curLockedUntil) && now.Sub(lastAttempt) > LockoutDuration {
				attempts = 0
			}
			attempts++
			var nextLocked *time.Time
			if attempts >= MaxFailedLoginAttempts {
				lu := now.Add(LockoutDuration)
				nextLocked = &lu
				locked = true
				maxRetry = int64(LockoutDuration.Seconds())
			}
			_, _ = tx.Exec(ctx, `
				INSERT INTO admin_login_lockouts (lock_key, failed_attempts, locked_until, last_attempt_at)
				VALUES ($1, $2, $3, $4)
				ON CONFLICT (lock_key) DO UPDATE SET
					failed_attempts = EXCLUDED.failed_attempts,
					locked_until = EXCLUDED.locked_until,
					last_attempt_at = EXCLUDED.last_attempt_at
			`, k, attempts, nextLocked, now)
		}

		if adminID != uuid.Nil {
			var lu *time.Time
			if locked {
				t := now.Add(LockoutDuration)
				lu = &t
			}
			_, _ = tx.Exec(ctx, `
				UPDATE admin_accounts
				SET failed_attempts = failed_attempts + 1, locked_until = COALESCE($2, locked_until), updated_at = NOW()
				WHERE id = $1
			`, adminID, lu)
		}
		actorRole := role
		if actorRole == "" {
			actorRole = "unknown"
		}
		var actorPtr *uuid.UUID
		if adminID != uuid.Nil {
			actorPtr = &adminID
		}
		_, _ = tx.Exec(ctx, `
			INSERT INTO admin_audit_logs (actor_admin_id, actor_role, action_type, ip_fp_hash, outcome)
			VALUES ($1, $2, 'admin_login_failed', $3, 'denied')
		`, actorPtr, actorRole, ipFP)
		return nil
	})

	return locked, maxRetry
}

func (s *Service) AuthenticateAdmin(ctx context.Context, rawToken string) (*AdminPrincipal, error) {
	trimmed := strings.TrimSpace(rawToken)
	if len(trimmed) < 32 {
		return nil, errors.New("missing token")
	}
	tokenHMAC := security.HMACSHA256Hex(s.cfg.HMACPepper, trimmed)

	var p AdminPrincipal
	var encEmail, encName, permsRaw []byte
	err := db.WithAdminBypassRLS(ctx, s.pool, func(tx pgx.Tx) error {
		var sessID uuid.UUID
		if err := tx.QueryRow(ctx, `
			SELECT s.id, a.id, a.email_encrypted, a.full_name_encrypted, a.role,
			       a.granted_permissions, a.must_change_password, a.is_paused
			FROM admin_sessions s
			JOIN admin_accounts a ON a.id = s.admin_id
			WHERE s.token_hmac = $1
			  AND s.revoked_at IS NULL
			  AND s.expires_at > NOW()
			  AND a.is_removed = FALSE
			  AND a.is_paused = FALSE
		`, tokenHMAC).Scan(&sessID, &p.ID, &encEmail, &encName, &p.Role, &permsRaw, &p.MustChangePassword, &p.IsPaused); err != nil {
			return err
		}
		_, _ = tx.Exec(ctx, `UPDATE admin_accounts SET last_active_at = NOW() WHERE id = $1`, p.ID)
		return nil
	})
	if err != nil {
		return nil, errors.New("invalid or paused admin session")
	}
	if b, dErr := security.DecryptAtRest(s.cfg.MasterKey, encEmail, "admin_accounts.email"); dErr == nil {
		p.Email = string(b)
	}
	if b, dErr := security.DecryptAtRest(s.cfg.MasterKey, encName, "admin_accounts.full_name"); dErr == nil {
		p.FullName = string(b)
	}
	_ = json.Unmarshal(permsRaw, &p.GrantedPermissions)
	return &p, nil
}

func (s *Service) ChangePassword(ctx context.Context, actor *AdminPrincipal, currentPassword, newPassword string) (int, error) {
	if currentPassword == "" || newPassword == "" {
		return http.StatusBadRequest, errors.New("passwords required")
	}
	if currentPassword == newPassword {
		return http.StatusBadRequest, errors.New("new password must differ from temporary password")
	}
	if err := security.ValidatePasswordStrength(newPassword); err != nil {
		return http.StatusBadRequest, err
	}
	newHash, err := security.HashPassword(newPassword)
	if err != nil {
		return http.StatusInternalServerError, err
	}

	err = db.WithAdminBypassRLSAs(ctx, s.pool, actor.ID, func(tx pgx.Tx) error {
		var curHash string
		if err := tx.QueryRow(ctx, `SELECT password_hash FROM admin_accounts WHERE id = $1 AND is_removed = FALSE`, actor.ID).Scan(&curHash); err != nil {
			return err
		}
		if !security.VerifyPassword(currentPassword, curHash) {
			return errors.New("invalid current password")
		}
		if _, err := tx.Exec(ctx, `
			UPDATE admin_accounts
			SET password_hash = $2, must_change_password = FALSE, updated_at = NOW()
			WHERE id = $1
		`, actor.ID, newHash); err != nil {
			return err
		}
		_, _ = tx.Exec(ctx, `
			INSERT INTO admin_audit_logs (actor_admin_id, actor_role, action_type, outcome)
			VALUES ($1, $2, 'admin_password_rotated', 'success')
		`, actor.ID, actor.Role)
		return nil
	})
	if err != nil {
		if err.Error() == "invalid current password" {
			return http.StatusUnauthorized, err
		}
		return http.StatusInternalServerError, err
	}
	actor.MustChangePassword = false
	return http.StatusOK, nil
}

func (s *Service) Logout(ctx context.Context, rawToken string) {
	tokenHMAC := security.HMACSHA256Hex(s.cfg.HMACPepper, strings.TrimSpace(rawToken))
	_ = db.WithAdminBypassRLS(ctx, s.pool, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `UPDATE admin_sessions SET revoked_at = NOW() WHERE token_hmac = $1`, tokenHMAC)
		return err
	})
}

func (s *Service) GetDashboard(ctx context.Context, actor *AdminPrincipal) (*DashboardStatsDTO, int, error) {
	var stats DashboardStatsDTO
	err := db.WithAdminBypassRLSAs(ctx, s.pool, actor.ID, func(tx pgx.Tx) error {
		_ = tx.QueryRow(ctx, `SELECT COUNT(*) FROM users`).Scan(&stats.TotalUsers)
		_ = tx.QueryRow(ctx, `SELECT COUNT(*) FROM posts`).Scan(&stats.TotalPosts)
		_ = tx.QueryRow(ctx, `SELECT COUNT(*) FROM admin_accounts WHERE is_removed = FALSE`).Scan(&stats.TotalStaff)
		_ = tx.QueryRow(ctx, `SELECT COUNT(*) FROM admin_accounts WHERE is_removed = FALSE AND is_paused = TRUE`).Scan(&stats.PausedStaff)
		_ = tx.QueryRow(ctx, `SELECT COUNT(*) FROM admin_action_requests WHERE status = 'pending'`).Scan(&stats.PendingApprovals)
		_ = tx.QueryRow(ctx, `SELECT COUNT(*) FROM admin_login_lockouts WHERE locked_until > NOW()`).Scan(&stats.ActiveLockouts)
		return nil
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	logs, _, _ := s.ListActivityLogs(ctx, actor, 12)
	stats.RecentActivityLog = logs
	return &stats, http.StatusOK, nil
}

func (s *Service) ListUsers(ctx context.Context, actor *AdminPrincipal, q string) ([]UserRecordDTO, int, error) {
	if !actor.HasPermission("view_users") {
		return nil, http.StatusForbidden, errors.New("forbidden")
	}
	normQ := strings.ToLower(strings.TrimSpace(q))
	out := make([]UserRecordDTO, 0)
	err := db.WithAdminBypassRLSAs(ctx, s.pool, actor.ID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT u.id, u.email_encrypted, COALESCE(up.full_name_encrypted, u.display_name_encrypted),
			       COALESCE(up.username_encrypted, ''::bytea), u.auth_provider, u.profile_completed,
			       u.is_suspended, COALESCE(urs.risk_score, 0), u.created_at
			FROM users u
			LEFT JOIN user_profiles up ON up.user_id = u.id
			LEFT JOIN user_risk_scores urs ON urs.user_id = u.id
			ORDER BY u.created_at DESC
			LIMIT 500
		`)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var uid uuid.UUID
			var encEmail, encName, encUser []byte
			var provider string
			var completed, suspended bool
			var risk int
			var created time.Time
			if err := rows.Scan(&uid, &encEmail, &encName, &encUser, &provider, &completed, &suspended, &risk, &created); err != nil {
				return err
			}
			em, _ := security.DecryptAtRest(s.cfg.MasterKey, encEmail, "users.email")
			fn, errFn := security.DecryptAtRest(s.cfg.MasterKey, encName, "profiles.full_name")
			if errFn != nil || len(fn) == 0 {
				fn, _ = security.DecryptAtRest(s.cfg.MasterKey, encName, "users.display_name")
			}
			un, _ := security.DecryptAtRest(s.cfg.MasterKey, encUser, "profiles.username")
			emailStr, nameStr, userStr := string(em), string(fn), string(un)
			if normQ != "" {
				if !strings.Contains(strings.ToLower(emailStr), normQ) &&
					!strings.Contains(strings.ToLower(nameStr), normQ) &&
					!strings.Contains(strings.ToLower(userStr), normQ) {
					continue
				}
			}
			out = append(out, UserRecordDTO{
				UserID:           uid.String(),
				Email:            emailStr,
				FullName:         nameStr,
				Username:         userStr,
				AuthProvider:     provider,
				ProfileCompleted: completed,
				IsSuspended:      suspended,
				RiskScore:        risk,
				CreatedAt:        created.UnixMilli(),
			})
		}
		return rows.Err()
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return out, http.StatusOK, nil
}

func (s *Service) SetUserSuspended(ctx context.Context, actor *AdminPrincipal, targetUserID uuid.UUID, suspended bool) (int, error) {
	if !actor.HasPermission("suspend_users") {
		return http.StatusForbidden, errors.New("forbidden")
	}
	err := db.WithAdminBypassRLSAs(ctx, s.pool, actor.ID, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `UPDATE users SET is_suspended = $2, updated_at = NOW() WHERE id = $1`, targetUserID, suspended)
		if err != nil || tag.RowsAffected() == 0 {
			return errors.New("user not found")
		}
		if suspended {
			_, _ = tx.Exec(ctx, `UPDATE sessions SET revoked_at = NOW() WHERE user_id = $1 AND revoked_at IS NULL`, targetUserID)
		}
		action := "admin_unsuspend_user"
		if suspended {
			action = "admin_suspend_user"
		}
		_, _ = tx.Exec(ctx, `
			INSERT INTO admin_audit_logs (actor_admin_id, actor_role, action_type, target_user_id, outcome)
			VALUES ($1, $2, $3, $4, 'success')
		`, actor.ID, actor.Role, action, targetUserID)
		return nil
	})
	if err != nil {
		return http.StatusNotFound, err
	}
	return http.StatusOK, nil
}

func (s *Service) ListPosts(ctx context.Context, actor *AdminPrincipal, q string) ([]PostRecordDTO, int, error) {
	if !actor.HasPermission("view_posts") {
		return nil, http.StatusForbidden, errors.New("forbidden")
	}
	normQ := strings.ToLower(strings.TrimSpace(q))
	out := make([]PostRecordDTO, 0)
	err := db.WithAdminBypassRLSAs(ctx, s.pool, actor.ID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT p.id, p.author_id, p.post_type, p.body_encrypted, p.content_fingerprint_hash, p.created_at,
			       COALESCE(up.full_name_encrypted, u.display_name_encrypted),
			       COALESCE(up.username_encrypted, ''::bytea),
			       (SELECT COUNT(*) FROM post_media pm WHERE pm.post_id = p.id),
			       COALESCE((SELECT pm.id::text FROM post_media pm WHERE pm.post_id = p.id ORDER BY pm.sort_order ASC LIMIT 1), '')
			FROM posts p
			JOIN users u ON u.id = p.author_id
			LEFT JOIN user_profiles up ON up.user_id = p.author_id
			ORDER BY p.created_at DESC
			LIMIT 500
		`)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var pid, aid uuid.UUID
			var postType, contentFP, primaryMediaID string
			var encBody, encAuthorName, encAuthorUser []byte
			var created time.Time
			var mediaCount int
			if err := rows.Scan(&pid, &aid, &postType, &encBody, &contentFP, &created, &encAuthorName, &encAuthorUser, &mediaCount, &primaryMediaID); err != nil {
				return err
			}
			bodyBytes, _ := security.DecryptAtRest(s.cfg.MasterKey, encBody, "posts.body")
			nameBytes, nErr := security.DecryptAtRest(s.cfg.MasterKey, encAuthorName, "profiles.full_name")
			if nErr != nil || len(nameBytes) == 0 {
				nameBytes, _ = security.DecryptAtRest(s.cfg.MasterKey, encAuthorName, "users.display_name")
			}
			userBytes, _ := security.DecryptAtRest(s.cfg.MasterKey, encAuthorUser, "profiles.username")
			bodyStr, authorName, authorHandle := string(bodyBytes), string(nameBytes), string(userBytes)
			if normQ != "" {
				if !strings.Contains(strings.ToLower(bodyStr), normQ) &&
					!strings.Contains(strings.ToLower(authorName), normQ) &&
					!strings.Contains(strings.ToLower(authorHandle), normQ) {
					continue
				}
			}
			out = append(out, PostRecordDTO{
				PostID:         pid.String(),
				AuthorID:       aid.String(),
				AuthorName:     authorName,
				AuthorHandle:   authorHandle,
				PostType:       postType,
				Body:           bodyStr,
				MediaCount:     mediaCount,
				PrimaryMediaID: primaryMediaID,
				ContentFP:      contentFP,
				CreatedAt:      created.UnixMilli(),
			})
		}
		return rows.Err()
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return out, http.StatusOK, nil
}

func (s *Service) RemovePost(ctx context.Context, actor *AdminPrincipal, postID uuid.UUID) (int, error) {
	if !actor.HasPermission("remove_posts") {
		return http.StatusForbidden, errors.New("forbidden")
	}
	var objKeys []string
	err := db.WithAdminBypassRLSAs(ctx, s.pool, actor.ID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `SELECT stored_object_key, thumbnail_object_key FROM post_media WHERE post_id = $1`, postID)
		if err == nil {
			for rows.Next() {
				var sk, tk string
				if rows.Scan(&sk, &tk) == nil {
					if sk != "" {
						objKeys = append(objKeys, sk)
					}
					if tk != "" {
						objKeys = append(objKeys, tk)
					}
				}
			}
			rows.Close()
		}
		tag, err := tx.Exec(ctx, `DELETE FROM posts WHERE id = $1`, postID)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return errors.New("post not found")
		}
		_, _ = tx.Exec(ctx, `
			INSERT INTO admin_audit_logs (actor_admin_id, actor_role, action_type, target_post_id, outcome)
			VALUES ($1, $2, 'admin_remove_post', $3, 'success')
		`, actor.ID, actor.Role, postID)
		return nil
	})
	if err != nil {
		return http.StatusNotFound, err
	}
	for _, key := range objKeys {
		if p, pErr := media.ConfineStoragePath(s.cfg.MediaStorageDir, key); pErr == nil {
			_ = os.Remove(p)
		}
	}
	return http.StatusOK, nil
}

// DeleteUserOrRequest enforces that ONLY super_admin executes immediate deletion;
// admins and moderators must submit to the Super Admin Approval Queue.
func (s *Service) DeleteUserOrRequest(ctx context.Context, actor *AdminPrincipal, targetUserID uuid.UUID, reason string) (map[string]any, int, error) {
	if actor.Role == "super_admin" {
		err := db.WithAdminBypassRLSAs(ctx, s.pool, actor.ID, func(tx pgx.Tx) error {
			tag, err := tx.Exec(ctx, `DELETE FROM users WHERE id = $1`, targetUserID)
			if err != nil || tag.RowsAffected() == 0 {
				return errors.New("user not found")
			}
			_, _ = tx.Exec(ctx, `
				INSERT INTO admin_audit_logs (actor_admin_id, actor_role, action_type, target_user_id, outcome)
				VALUES ($1, 'super_admin', 'super_admin_delete_user', $2, 'success')
			`, actor.ID, targetUserID)
			return nil
		})
		if err != nil {
			return nil, http.StatusNotFound, err
		}
		return map[string]any{"status": "executed", "requires_approval": false}, http.StatusOK, nil
	}

	if !actor.HasPermission("request_delete_user") {
		return nil, http.StatusForbidden, errors.New("forbidden")
	}

	cleanReason := strings.TrimSpace(reason)
	if len(cleanReason) < 4 {
		cleanReason = "Policy enforcement review"
	}
	encReason, err := security.EncryptAtRest(s.cfg.MasterKey, []byte(cleanReason), "admin_action_requests.reason")
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}

	reqID := uuid.New()
	err = db.WithAdminBypassRLSAs(ctx, s.pool, actor.ID, func(tx pgx.Tx) error {
		var exists bool
		if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)`, targetUserID).Scan(&exists); err != nil || !exists {
			return errors.New("user not found")
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO admin_action_requests (
				id, requested_by_admin_id, action_type, target_user_id, reason_encrypted, status
			) VALUES ($1, $2, 'delete_user', $3, $4, 'pending')
		`, reqID, actor.ID, targetUserID, encReason); err != nil {
			return err
		}
		_, _ = tx.Exec(ctx, `
			INSERT INTO admin_audit_logs (actor_admin_id, actor_role, action_type, target_user_id, outcome)
			VALUES ($1, $2, 'request_delete_user', $3, 'pending_approval')
		`, actor.ID, actor.Role, targetUserID)
		return nil
	})
	if err != nil {
		return nil, http.StatusNotFound, err
	}
	return map[string]any{
		"request_id":        reqID.String(),
		"status":            "pending",
		"requires_approval": true,
	}, http.StatusAccepted, nil
}

func (s *Service) ListApprovals(ctx context.Context, actor *AdminPrincipal) ([]ApprovalRequestDTO, int, error) {
	out := make([]ApprovalRequestDTO, 0)
	err := db.WithAdminBypassRLSAs(ctx, s.pool, actor.ID, func(tx pgx.Tx) error {
		query := `
			SELECT r.id, r.requested_by_admin_id, reqAdmin.email_encrypted, reqAdmin.role,
			       r.action_type, COALESCE(r.target_user_id::text, ''), COALESCE(u.email_encrypted, ''::bytea),
			       COALESCE(r.target_post_id::text, ''), r.reason_encrypted, r.status,
			       COALESCE(revAdmin.email_encrypted, ''::bytea), COALESCE(r.review_note_encrypted, ''::bytea),
			       r.created_at, r.reviewed_at
			FROM admin_action_requests r
			JOIN admin_accounts reqAdmin ON reqAdmin.id = r.requested_by_admin_id
			LEFT JOIN users u ON u.id = r.target_user_id
			LEFT JOIN admin_accounts revAdmin ON revAdmin.id = r.reviewed_by_super_admin_id
		`
		var rows pgx.Rows
		var err error
		if actor.Role == "super_admin" {
			rows, err = tx.Query(ctx, query+` ORDER BY r.created_at DESC LIMIT 200`)
		} else {
			rows, err = tx.Query(ctx, query+` WHERE r.requested_by_admin_id = $1 ORDER BY r.created_at DESC LIMIT 100`, actor.ID)
		}
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var id, reqByID uuid.UUID
			var encReqEmail, encTargetUserEmail, encReason, encRevEmail, encRevNote []byte
			var reqRole, actionType, targetUID, targetPID, status string
			var createdAt time.Time
			var reviewedAt *time.Time
			if err := rows.Scan(&id, &reqByID, &encReqEmail, &reqRole, &actionType, &targetUID, &encTargetUserEmail,
				&targetPID, &encReason, &status, &encRevEmail, &encRevNote, &createdAt, &reviewedAt); err != nil {
				return err
			}
			reqEmail, _ := security.DecryptAtRest(s.cfg.MasterKey, encReqEmail, "admin_accounts.email")
			tEmail, _ := security.DecryptAtRest(s.cfg.MasterKey, encTargetUserEmail, "users.email")
			reason, _ := security.DecryptAtRest(s.cfg.MasterKey, encReason, "admin_action_requests.reason")
			revEmail, _ := security.DecryptAtRest(s.cfg.MasterKey, encRevEmail, "admin_accounts.email")
			revNote, _ := security.DecryptAtRest(s.cfg.MasterKey, encRevNote, "admin_action_requests.review_note")
			var revMs int64
			if reviewedAt != nil {
				revMs = reviewedAt.UnixMilli()
			}
			out = append(out, ApprovalRequestDTO{
				ID:               id.String(),
				RequestedByID:    reqByID.String(),
				RequestedByEmail: string(reqEmail),
				RequestedByRole:  reqRole,
				ActionType:       actionType,
				TargetUserID:     targetUID,
				TargetUserEmail:  string(tEmail),
				TargetPostID:     targetPID,
				Reason:           string(reason),
				Status:           status,
				ReviewedByEmail:  string(revEmail),
				ReviewNote:       string(revNote),
				CreatedAt:        createdAt.UnixMilli(),
				ReviewedAt:       revMs,
			})
		}
		return rows.Err()
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return out, http.StatusOK, nil
}

func (s *Service) DecideApproval(ctx context.Context, superAdmin *AdminPrincipal, requestID uuid.UUID, approve bool, note string) (int, error) {
	if superAdmin.Role != "super_admin" {
		return http.StatusForbidden, errors.New("super_admin required")
	}
	encNote, _ := security.EncryptAtRest(s.cfg.MasterKey, []byte(strings.TrimSpace(note)), "admin_action_requests.review_note")

	err := db.WithAdminBypassRLSAs(ctx, s.pool, superAdmin.ID, func(tx pgx.Tx) error {
		var actionType, curStatus string
		var targetUserID, targetPostID *uuid.UUID
		if err := tx.QueryRow(ctx, `
			SELECT action_type, target_user_id, target_post_id, status
			FROM admin_action_requests WHERE id = $1 FOR UPDATE
		`, requestID).Scan(&actionType, &targetUserID, &targetPostID, &curStatus); err != nil {
			return err
		}
		if curStatus != "pending" {
			return errors.New("request already decided")
		}

		finalStatus := "rejected"
		auditAction := "super_admin_reject_request"
		if approve {
			finalStatus = "executed"
			auditAction = "super_admin_approve_" + actionType
			if actionType == "delete_user" && targetUserID != nil {
				_, _ = tx.Exec(ctx, `DELETE FROM users WHERE id = $1`, *targetUserID)
			} else if actionType == "bulk_remove_posts" && targetPostID != nil {
				_, _ = tx.Exec(ctx, `DELETE FROM posts WHERE id = $1`, *targetPostID)
			}
		}

		if _, err := tx.Exec(ctx, `
			UPDATE admin_action_requests
			SET status = $2, reviewed_by_super_admin_id = $3, review_note_encrypted = $4, reviewed_at = NOW()
			WHERE id = $1
		`, requestID, finalStatus, superAdmin.ID, encNote); err != nil {
			return err
		}
		_, _ = tx.Exec(ctx, `
			INSERT INTO admin_audit_logs (actor_admin_id, actor_role, action_type, target_user_id, target_post_id, outcome)
			VALUES ($1, 'super_admin', $2, $3, $4, $5)
		`, superAdmin.ID, auditAction, targetUserID, targetPostID, finalStatus)
		return nil
	})
	if err != nil {
		return http.StatusBadRequest, err
	}
	return http.StatusOK, nil
}

func (s *Service) ListTeam(ctx context.Context, actor *AdminPrincipal) ([]StaffMemberDTO, int, error) {
	if actor.Role != "super_admin" {
		return nil, http.StatusForbidden, errors.New("super_admin required")
	}
	out := make([]StaffMemberDTO, 0)
	err := db.WithAdminBypassRLSAs(ctx, s.pool, actor.ID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT id, email_encrypted, full_name_encrypted, role, granted_permissions,
			       must_change_password, is_paused, failed_attempts, locked_until, last_active_at, created_at
			FROM admin_accounts
			WHERE is_removed = FALSE
			ORDER BY CASE role WHEN 'super_admin' THEN 1 WHEN 'admin' THEN 2 ELSE 3 END, created_at ASC
		`)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var id uuid.UUID
			var encEmail, encName, permsRaw []byte
			var role string
			var mustChange, isPaused bool
			var failed int
			var lockedUntil, lastActive *time.Time
			var created time.Time
			if err := rows.Scan(&id, &encEmail, &encName, &role, &permsRaw, &mustChange, &isPaused, &failed, &lockedUntil, &lastActive, &created); err != nil {
				return err
			}
			em, _ := security.DecryptAtRest(s.cfg.MasterKey, encEmail, "admin_accounts.email")
			fn, _ := security.DecryptAtRest(s.cfg.MasterKey, encName, "admin_accounts.full_name")
			var perms []string
			_ = json.Unmarshal(permsRaw, &perms)
			var lockMs, actMs int64
			if lockedUntil != nil {
				lockMs = lockedUntil.UnixMilli()
			}
			if lastActive != nil {
				actMs = lastActive.UnixMilli()
			}
			out = append(out, StaffMemberDTO{
				ID:                 id.String(),
				Email:              string(em),
				FullName:           string(fn),
				Role:               role,
				GrantedPermissions: perms,
				MustChangePassword: mustChange,
				IsPaused:           isPaused,
				FailedAttempts:     failed,
				LockedUntilMs:      lockMs,
				LastActiveAtMs:     actMs,
				CreatedAtMs:        created.UnixMilli(),
			})
		}
		return rows.Err()
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return out, http.StatusOK, nil
}

func (s *Service) CreateStaffMember(
	ctx context.Context,
	superAdmin *AdminPrincipal,
	rawEmail, fullName, role, password string,
	isTemporary bool,
	permissions []string,
) (*StaffMemberDTO, int, error) {
	if superAdmin.Role != "super_admin" {
		return nil, http.StatusForbidden, errors.New("super_admin required")
	}
	email := strings.ToLower(strings.TrimSpace(rawEmail))
	if !strings.Contains(email, "@") || len(email) < 5 {
		return nil, http.StatusBadRequest, errors.New("invalid email")
	}
	normRole := strings.ToLower(strings.TrimSpace(role))
	if normRole != "super_admin" && normRole != "admin" && normRole != "moderator" {
		return nil, http.StatusBadRequest, errors.New("invalid role")
	}
	if err := security.ValidatePasswordStrength(password); err != nil {
		return nil, http.StatusBadRequest, err
	}
	cleanName := strings.TrimSpace(fullName)
	if len(cleanName) < 2 {
		cleanName = strings.Split(email, "@")[0]
	}

	cleanedPerms := sanitizePermissions(permissions)
	if len(cleanedPerms) == 0 {
		cleanedPerms = defaultPermissionsForRole(normRole)
	}
	permsJSON, _ := json.Marshal(cleanedPerms)

	pwHash, err := security.HashPassword(password)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	emailHash := security.HashEmail(s.cfg.HMACPepper, email)
	encEmail, _ := security.EncryptAtRest(s.cfg.MasterKey, []byte(email), "admin_accounts.email")
	encName, _ := security.EncryptAtRest(s.cfg.MasterKey, []byte(cleanName), "admin_accounts.full_name")

	staffID := uuid.New()
	var created time.Time
	err = db.WithAdminBypassRLSAs(ctx, s.pool, superAdmin.ID, func(tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, `
			INSERT INTO admin_accounts (
				id, email_hash, email_encrypted, full_name_encrypted, password_hash,
				role, granted_permissions, must_change_password, created_by_admin_id
			) VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,$8,$9)
			RETURNING created_at
		`, staffID, emailHash, encEmail, encName, pwHash, normRole, string(permsJSON), isTemporary, superAdmin.ID).Scan(&created); err != nil {
			return err
		}
		_, _ = tx.Exec(ctx, `
			INSERT INTO admin_audit_logs (actor_admin_id, actor_role, action_type, target_user_id, outcome)
			VALUES ($1, 'super_admin', 'super_admin_create_staff', $2, 'success')
		`, superAdmin.ID, staffID)
		return nil
	})
	if err != nil {
		return nil, http.StatusConflict, err
	}

	return &StaffMemberDTO{
		ID:                 staffID.String(),
		Email:              email,
		FullName:           cleanName,
		Role:               normRole,
		GrantedPermissions: cleanedPerms,
		MustChangePassword: isTemporary,
		IsPaused:           false,
		CreatedAtMs:        created.UnixMilli(),
	}, http.StatusCreated, nil
}

func (s *Service) UpdateStaffRole(ctx context.Context, superAdmin *AdminPrincipal, staffID uuid.UUID, role string, permissions []string) (int, error) {
	if superAdmin.Role != "super_admin" {
		return http.StatusForbidden, errors.New("super_admin required")
	}
	normRole := strings.ToLower(strings.TrimSpace(role))
	if normRole != "super_admin" && normRole != "admin" && normRole != "moderator" {
		return http.StatusBadRequest, errors.New("invalid role")
	}
	if staffID == superAdmin.ID && normRole != "super_admin" {
		return http.StatusBadRequest, errors.New("cannot demote current super admin")
	}
	cleanedPerms := sanitizePermissions(permissions)
	if len(cleanedPerms) == 0 {
		cleanedPerms = defaultPermissionsForRole(normRole)
	}
	permsJSON, _ := json.Marshal(cleanedPerms)

	err := db.WithAdminBypassRLSAs(ctx, s.pool, superAdmin.ID, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `
			UPDATE admin_accounts
			SET role = $2, granted_permissions = $3::jsonb, updated_at = NOW()
			WHERE id = $1 AND is_removed = FALSE
		`, staffID, normRole, string(permsJSON))
		if err != nil || tag.RowsAffected() == 0 {
			return errors.New("staff member not found")
		}
		_, _ = tx.Exec(ctx, `
			INSERT INTO admin_audit_logs (actor_admin_id, actor_role, action_type, target_user_id, outcome)
			VALUES ($1, 'super_admin', 'super_admin_update_staff_role', $2, 'success')
		`, superAdmin.ID, staffID)
		return nil
	})
	if err != nil {
		return http.StatusNotFound, err
	}
	return http.StatusOK, nil
}

func (s *Service) SetStaffPaused(ctx context.Context, superAdmin *AdminPrincipal, staffID uuid.UUID, paused bool) (int, error) {
	if superAdmin.Role != "super_admin" {
		return http.StatusForbidden, errors.New("super_admin required")
	}
	if staffID == superAdmin.ID {
		return http.StatusBadRequest, errors.New("cannot pause own super admin account")
	}
	err := db.WithAdminBypassRLSAs(ctx, s.pool, superAdmin.ID, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `
			UPDATE admin_accounts SET is_paused = $2, updated_at = NOW()
			WHERE id = $1 AND is_removed = FALSE
		`, staffID, paused)
		if err != nil || tag.RowsAffected() == 0 {
			return errors.New("staff member not found")
		}
		if paused {
			_, _ = tx.Exec(ctx, `UPDATE admin_sessions SET revoked_at = NOW() WHERE admin_id = $1 AND revoked_at IS NULL`, staffID)
		}
		action := "super_admin_resume_staff"
		if paused {
			action = "super_admin_pause_staff"
		}
		_, _ = tx.Exec(ctx, `
			INSERT INTO admin_audit_logs (actor_admin_id, actor_role, action_type, target_user_id, outcome)
			VALUES ($1, 'super_admin', $2, $3, 'success')
		`, superAdmin.ID, action, staffID)
		return nil
	})
	if err != nil {
		return http.StatusNotFound, err
	}
	return http.StatusOK, nil
}

func (s *Service) RemoveStaffMember(ctx context.Context, superAdmin *AdminPrincipal, staffID uuid.UUID) (int, error) {
	if superAdmin.Role != "super_admin" {
		return http.StatusForbidden, errors.New("super_admin required")
	}
	if staffID == superAdmin.ID {
		return http.StatusBadRequest, errors.New("cannot remove own super admin account")
	}
	err := db.WithAdminBypassRLSAs(ctx, s.pool, superAdmin.ID, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `
			UPDATE admin_accounts SET is_removed = TRUE, is_paused = TRUE, updated_at = NOW()
			WHERE id = $1 AND is_removed = FALSE
		`, staffID)
		if err != nil || tag.RowsAffected() == 0 {
			return errors.New("staff member not found")
		}
		_, _ = tx.Exec(ctx, `UPDATE admin_sessions SET revoked_at = NOW() WHERE admin_id = $1 AND revoked_at IS NULL`, staffID)
		_, _ = tx.Exec(ctx, `
			INSERT INTO admin_audit_logs (actor_admin_id, actor_role, action_type, target_user_id, outcome)
			VALUES ($1, 'super_admin', 'super_admin_remove_staff', $2, 'success')
		`, superAdmin.ID, staffID)
		return nil
	})
	if err != nil {
		return http.StatusNotFound, err
	}
	return http.StatusOK, nil
}

func (s *Service) ListActivityLogs(ctx context.Context, actor *AdminPrincipal, limit int) ([]ActivityLogDTO, int, error) {
	if !actor.HasPermission("view_logs") {
		return nil, http.StatusForbidden, errors.New("forbidden")
	}
	if limit <= 0 || limit > 300 {
		limit = 150
	}
	out := make([]ActivityLogDTO, 0)
	err := db.WithAdminBypassRLSAs(ctx, s.pool, actor.ID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT l.id, COALESCE(l.actor_admin_id::text, ''), COALESCE(a.email_encrypted, ''::bytea),
			       l.actor_role, l.action_type, COALESCE(l.target_user_id::text, ''),
			       COALESCE(l.target_post_id::text, ''), l.outcome, l.created_at
			FROM admin_audit_logs l
			LEFT JOIN admin_accounts a ON a.id = l.actor_admin_id
			ORDER BY l.created_at DESC
			LIMIT $1
		`, limit)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var id uuid.UUID
			var actorID, actorRole, actionType, targetUID, targetPID, outcome string
			var encEmail []byte
			var created time.Time
			if err := rows.Scan(&id, &actorID, &encEmail, &actorRole, &actionType, &targetUID, &targetPID, &outcome, &created); err != nil {
				return err
			}
			actorEmail := "system"
			if len(encEmail) > 0 {
				if b, dErr := security.DecryptAtRest(s.cfg.MasterKey, encEmail, "admin_accounts.email"); dErr == nil {
					actorEmail = string(b)
				}
			}
			out = append(out, ActivityLogDTO{
				ID:           id.String(),
				Source:       "admin",
				ActorID:      actorID,
				ActorEmail:   actorEmail,
				ActorRole:    actorRole,
				ActionType:   actionType,
				TargetUserID: targetUID,
				TargetPostID: targetPID,
				Outcome:      outcome,
				CreatedAt:    created.UnixMilli(),
			})
		}
		if err := rows.Err(); err != nil {
			return err
		}

		// Also include contact anti-abuse risk logs for unified moderation visibility
		cRows, cErr := tx.Query(ctx, `
			SELECT c.id, c.actor_user_id::text, COALESCE(u.email_encrypted, ''::bytea),
			       c.action_type, c.target_user_id::text, c.outcome, c.created_at
			FROM contact_action_logs c
			LEFT JOIN users u ON u.id = c.actor_user_id
			ORDER BY c.created_at DESC
			LIMIT 60
		`)
		if cErr == nil {
			defer cRows.Close()
			for cRows.Next() {
				var id uuid.UUID
				var actorUID, actionType, targetUID, outcome string
				var encUserEmail []byte
				var created time.Time
				if cRows.Scan(&id, &actorUID, &encUserEmail, &actionType, &targetUID, &outcome, &created) == nil {
					uEmail := "user"
					if len(encUserEmail) > 0 {
						if b, dErr := security.DecryptAtRest(s.cfg.MasterKey, encUserEmail, "users.email"); dErr == nil {
							uEmail = string(b)
						}
					}
					out = append(out, ActivityLogDTO{
						ID:           id.String(),
						Source:       "user_risk",
						ActorID:      actorUID,
						ActorEmail:   uEmail,
						ActorRole:    "member",
						ActionType:   "contact_" + actionType,
						TargetUserID: targetUID,
						Outcome:      outcome,
						CreatedAt:    created.UnixMilli(),
					})
				}
			}
		}
		return nil
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return out, http.StatusOK, nil
}
