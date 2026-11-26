-- Telefam Admin RBAC, Temporary Password Rotation, Super Admin Approval Queue,
-- 3-Strike 12-Minute Lockouts, Notifications, and Strict RLS Enforcement.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS is_suspended BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE admin_audit_logs
    ADD COLUMN IF NOT EXISTS actor_admin_id UUID,
    ADD COLUMN IF NOT EXISTS actor_role VARCHAR(32) NOT NULL DEFAULT 'system',
    ADD COLUMN IF NOT EXISTS target_post_id UUID,
    ADD COLUMN IF NOT EXISTS ip_fp_hash CHAR(64) NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS outcome VARCHAR(32) NOT NULL DEFAULT 'success';

CREATE INDEX IF NOT EXISTS idx_admin_audit_created ON admin_audit_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_actor ON admin_audit_logs (actor_admin_id, created_at DESC);

CREATE OR REPLACE FUNCTION telefam_current_admin_id() RETURNS UUID AS $$
    SELECT NULLIF(current_setting('app.admin_actor_id', true), '')::UUID;
$$ LANGUAGE SQL STABLE;

CREATE TABLE IF NOT EXISTS admin_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email_hash CHAR(64) NOT NULL UNIQUE,
    email_encrypted BYTEA NOT NULL,
    full_name_encrypted BYTEA NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('super_admin', 'admin', 'moderator')),
    granted_permissions JSONB NOT NULL DEFAULT '[]'::jsonb,
    must_change_password BOOLEAN NOT NULL DEFAULT TRUE,
    is_paused BOOLEAN NOT NULL DEFAULT FALSE,
    is_removed BOOLEAN NOT NULL DEFAULT FALSE,
    failed_attempts INTEGER NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
    locked_until TIMESTAMPTZ,
    last_active_at TIMESTAMPTZ,
    created_by_admin_id UUID REFERENCES admin_accounts(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_accounts_role ON admin_accounts (role, is_removed);

CREATE TABLE IF NOT EXISTS admin_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id UUID NOT NULL REFERENCES admin_accounts(id) ON DELETE CASCADE,
    token_hmac CHAR(64) NOT NULL UNIQUE,
    ip_fp_hash CHAR(64) NOT NULL,
    user_agent_hash CHAR(64) NOT NULL DEFAULT '',
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_sessions_admin ON admin_sessions (admin_id, expires_at DESC);

CREATE TABLE IF NOT EXISTS admin_login_lockouts (
    lock_key VARCHAR(160) PRIMARY KEY,
    failed_attempts INTEGER NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
    locked_until TIMESTAMPTZ,
    last_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS admin_action_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requested_by_admin_id UUID NOT NULL REFERENCES admin_accounts(id) ON DELETE CASCADE,
    action_type TEXT NOT NULL CHECK (action_type IN ('delete_user', 'bulk_remove_posts', 'purge_media')),
    target_user_id UUID,
    target_post_id UUID,
    reason_encrypted BYTEA NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'executed')),
    reviewed_by_super_admin_id UUID REFERENCES admin_accounts(id) ON DELETE SET NULL,
    review_note_encrypted BYTEA,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_admin_action_requests_status ON admin_action_requests (status, created_at DESC);

CREATE TABLE IF NOT EXISTS user_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    kind TEXT NOT NULL CHECK (kind IN ('follow', 'tag', 'system')),
    message_encrypted BYTEA NOT NULL,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_notifications_recipient ON user_notifications (recipient_user_id, created_at DESC);

-- ============================================================================
-- STRICT ROW-LEVEL SECURITY (RLS) FOR ADMIN RBAC & NOTIFICATIONS
-- ============================================================================

ALTER TABLE admin_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_accounts FORCE ROW LEVEL SECURITY;

ALTER TABLE admin_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_sessions FORCE ROW LEVEL SECURITY;

ALTER TABLE admin_login_lockouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_login_lockouts FORCE ROW LEVEL SECURITY;

ALTER TABLE admin_action_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_action_requests FORCE ROW LEVEL SECURITY;

ALTER TABLE user_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_notifications FORCE ROW LEVEL SECURITY;

ALTER TABLE rate_limit_buckets ENABLE ROW LEVEL SECURITY;
ALTER TABLE rate_limit_buckets FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_accounts_service_only ON admin_accounts;
CREATE POLICY admin_accounts_service_only ON admin_accounts
    FOR ALL USING (telefam_is_admin_service())
    WITH CHECK (telefam_is_admin_service());

DROP POLICY IF EXISTS admin_sessions_service_only ON admin_sessions;
CREATE POLICY admin_sessions_service_only ON admin_sessions
    FOR ALL USING (telefam_is_admin_service())
    WITH CHECK (telefam_is_admin_service());

DROP POLICY IF EXISTS admin_lockouts_service_only ON admin_login_lockouts;
CREATE POLICY admin_lockouts_service_only ON admin_login_lockouts
    FOR ALL USING (telefam_is_admin_service())
    WITH CHECK (telefam_is_admin_service());

DROP POLICY IF EXISTS admin_action_requests_service_only ON admin_action_requests;
CREATE POLICY admin_action_requests_service_only ON admin_action_requests
    FOR ALL USING (telefam_is_admin_service())
    WITH CHECK (telefam_is_admin_service());

DROP POLICY IF EXISTS rate_limit_buckets_service_only ON rate_limit_buckets;
CREATE POLICY rate_limit_buckets_service_only ON rate_limit_buckets
    FOR ALL USING (telefam_is_auth_service() OR telefam_is_admin_service())
    WITH CHECK (telefam_is_auth_service() OR telefam_is_admin_service());

DROP POLICY IF EXISTS notifications_owner_select ON user_notifications;
CREATE POLICY notifications_owner_select ON user_notifications
    FOR SELECT USING (recipient_user_id = telefam_current_user_id() OR telefam_is_admin_service());

DROP POLICY IF EXISTS notifications_owner_update ON user_notifications;
CREATE POLICY notifications_owner_update ON user_notifications
    FOR UPDATE USING (recipient_user_id = telefam_current_user_id())
    WITH CHECK (recipient_user_id = telefam_current_user_id());

DROP POLICY IF EXISTS notifications_actor_insert ON user_notifications;
CREATE POLICY notifications_actor_insert ON user_notifications
    FOR INSERT WITH CHECK (actor_user_id = telefam_current_user_id() OR telefam_is_admin_service());

-- Ensure application database role never holds BYPASSRLS or SUPERUSER privileges
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'telefam_app_role') THEN
        CREATE ROLE telefam_app_role NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
    ELSE
        ALTER ROLE telefam_app_role NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
    END IF;
END
$$;
