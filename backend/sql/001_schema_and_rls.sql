-- Telefam PostgreSQL Schema with Strict Row-Level Security (RLS)
-- Enforces one unique email per account, 13+ age requirement, and encrypted-at-rest columns.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email_hash CHAR(64) NOT NULL UNIQUE,
    email_encrypted BYTEA NOT NULL,
    display_name_encrypted BYTEA NOT NULL,
    auth_provider TEXT NOT NULL CHECK (auth_provider IN ('email_otp', 'google', 'apple')),
    google_sub_hash CHAR(64),
    apple_sub_hash CHAR(64),
    profile_completed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    full_name_encrypted BYTEA NOT NULL,
    username_hash CHAR(64) NOT NULL UNIQUE,
    username_encrypted BYTEA NOT NULL,
    phone_e164_encrypted BYTEA NOT NULL,
    country_iso CHAR(2) NOT NULL,
    gender TEXT NOT NULL CHECK (gender IN ('male', 'female', 'non_binary', 'prefer_not_to_say')),
    date_of_birth DATE NOT NULL CHECK (date_of_birth <= (CURRENT_DATE - INTERVAL '13 years')),
    location_encrypted BYTEA NOT NULL,
    bio_encrypted BYTEA NOT NULL,
    avatar_fingerprint_hash CHAR(64),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS profile_avatars (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    mime_type TEXT NOT NULL CHECK (mime_type IN ('image/jpeg', 'image/png')),
    byte_size INTEGER NOT NULL CHECK (byte_size > 0 AND byte_size <= 2097152),
    fingerprint_hash CHAR(64) NOT NULL,
    sanitized_bytes_encrypted BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_fp_hash CHAR(64) NOT NULL,
    ip_fp_hash CHAR(64) NOT NULL,
    hardware_attestation_hash CHAR(64) NOT NULL,
    device_name_encrypted BYTEA NOT NULL,
    platform TEXT NOT NULL CHECK (platform IN ('android', 'ios', 'desktop')),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMPTZ,
    UNIQUE (user_id, device_fp_hash)
);

CREATE TABLE IF NOT EXISTS otp_challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email_hash CHAR(64) NOT NULL,
    device_fp_hash CHAR(64) NOT NULL,
    ip_fp_hash CHAR(64) NOT NULL,
    otp_hmac CHAR(64) NOT NULL,
    magic_token_hmac CHAR(64) NOT NULL,
    resend_count INTEGER NOT NULL DEFAULT 1,
    cooldown_until TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    consumed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    refresh_token_hmac CHAR(64) NOT NULL UNIQUE,
    ip_fp_hash CHAR(64) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_by UUID NOT NULL REFERENCES users(id),
    title_encrypted BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS conversation_members (
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (conversation_id, user_id)
);

CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id),
    client_mutation_id VARCHAR(96) NOT NULL,
    body_encrypted BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    UNIQUE (sender_id, client_mutation_id)
);

CREATE TABLE IF NOT EXISTS offline_mutations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_fp_hash CHAR(64) NOT NULL,
    client_mutation_id VARCHAR(96) NOT NULL,
    action_type VARCHAR(48) NOT NULL,
    payload_encrypted BYTEA NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, client_mutation_id)
);

CREATE TABLE IF NOT EXISTS rate_limit_buckets (
    bucket_key VARCHAR(160) PRIMARY KEY,
    window_start TIMESTAMPTZ NOT NULL,
    request_count INTEGER NOT NULL DEFAULT 1,
    blocked_until TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_otp_email_device ON otp_challenges (email_hash, device_fp_hash, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_conv_time ON messages (conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_devices_user ON devices (user_id);

-- ============================================================================
-- STRICT ROW-LEVEL SECURITY (RLS)
-- ============================================================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE ROW LEVEL SECURITY;

ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_profiles FORCE ROW LEVEL SECURITY;

ALTER TABLE profile_avatars ENABLE ROW LEVEL SECURITY;
ALTER TABLE profile_avatars FORCE ROW LEVEL SECURITY;

ALTER TABLE devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE devices FORCE ROW LEVEL SECURITY;

ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE sessions FORCE ROW LEVEL SECURITY;

ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations FORCE ROW LEVEL SECURITY;

ALTER TABLE conversation_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_members FORCE ROW LEVEL SECURITY;

ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages FORCE ROW LEVEL SECURITY;

ALTER TABLE offline_mutations ENABLE ROW LEVEL SECURITY;
ALTER TABLE offline_mutations FORCE ROW LEVEL SECURITY;

ALTER TABLE otp_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE otp_challenges FORCE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION telefam_current_user_id() RETURNS UUID AS $$
    SELECT NULLIF(current_setting('app.current_user_id', true), '')::UUID;
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION telefam_is_auth_service() RETURNS BOOLEAN AS $$
    SELECT COALESCE(current_setting('app.auth_service_role', true), '') = 'auth_worker';
$$ LANGUAGE SQL STABLE;

CREATE POLICY users_self_select ON users
    FOR SELECT USING (id = telefam_current_user_id() OR telefam_is_auth_service());

CREATE POLICY users_self_update ON users
    FOR UPDATE USING (id = telefam_current_user_id())
    WITH CHECK (id = telefam_current_user_id());

CREATE POLICY users_auth_insert ON users
    FOR INSERT WITH CHECK (telefam_is_auth_service());

CREATE POLICY profiles_owner_select ON user_profiles
    FOR SELECT USING (
        user_id = telefam_current_user_id()
        OR EXISTS (
            SELECT 1 FROM conversation_members cm1
            JOIN conversation_members cm2 ON cm1.conversation_id = cm2.conversation_id
            WHERE cm1.user_id = telefam_current_user_id() AND cm2.user_id = user_profiles.user_id
        )
    );

CREATE POLICY profiles_owner_write ON user_profiles
    FOR ALL USING (user_id = telefam_current_user_id())
    WITH CHECK (user_id = telefam_current_user_id());

CREATE POLICY avatars_owner_write ON profile_avatars
    FOR ALL USING (user_id = telefam_current_user_id())
    WITH CHECK (user_id = telefam_current_user_id());

CREATE POLICY devices_owner_all ON devices
    FOR ALL USING (user_id = telefam_current_user_id() OR telefam_is_auth_service())
    WITH CHECK (user_id = telefam_current_user_id() OR telefam_is_auth_service());

CREATE POLICY sessions_owner_all ON sessions
    FOR ALL USING (user_id = telefam_current_user_id() OR telefam_is_auth_service())
    WITH CHECK (user_id = telefam_current_user_id() OR telefam_is_auth_service());

CREATE POLICY otp_auth_worker_only ON otp_challenges
    FOR ALL USING (telefam_is_auth_service())
    WITH CHECK (telefam_is_auth_service());

CREATE POLICY conversations_member_select ON conversations
    FOR SELECT USING (
        created_by = telefam_current_user_id()
        OR EXISTS (
            SELECT 1 FROM conversation_members cm
            WHERE cm.conversation_id = conversations.id
              AND cm.user_id = telefam_current_user_id()
        )
    );

CREATE POLICY conversations_creator_insert ON conversations
    FOR INSERT WITH CHECK (created_by = telefam_current_user_id());

CREATE POLICY members_select ON conversation_members
    FOR SELECT USING (
        user_id = telefam_current_user_id()
        OR EXISTS (
            SELECT 1 FROM conversation_members cm2
            WHERE cm2.conversation_id = conversation_members.conversation_id
              AND cm2.user_id = telefam_current_user_id()
        )
    );

CREATE POLICY members_insert ON conversation_members
    FOR INSERT WITH CHECK (
        user_id = telefam_current_user_id()
        OR EXISTS (
            SELECT 1 FROM conversations c
            WHERE c.id = conversation_members.conversation_id
              AND c.created_by = telefam_current_user_id()
        )
    );

CREATE POLICY messages_member_select ON messages
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM conversation_members cm
            WHERE cm.conversation_id = messages.conversation_id
              AND cm.user_id = telefam_current_user_id()
        )
    );

CREATE POLICY messages_sender_insert ON messages
    FOR INSERT WITH CHECK (
        sender_id = telefam_current_user_id()
        AND EXISTS (
            SELECT 1 FROM conversation_members cm
            WHERE cm.conversation_id = messages.conversation_id
              AND cm.user_id = telefam_current_user_id()
        )
    );

CREATE POLICY messages_sender_update ON messages
    FOR UPDATE USING (sender_id = telefam_current_user_id())
    WITH CHECK (sender_id = telefam_current_user_id());

CREATE POLICY offline_mutations_owner ON offline_mutations
    FOR ALL USING (user_id = telefam_current_user_id())
    WITH CHECK (user_id = telefam_current_user_id());

-- ============================================================================
-- CONTACTS DIRECTORY, FOLLOW GRAPH, RISK SCORES & ACTION AUDIT LOGS
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_follows (
    follower_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    followee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (follower_id, followee_id),
    CHECK (follower_id <> followee_id)
);

CREATE INDEX IF NOT EXISTS idx_user_follows_follower ON user_follows (follower_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_follows_followee ON user_follows (followee_id, created_at DESC);

CREATE TABLE IF NOT EXISTS user_risk_scores (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    risk_score INTEGER NOT NULL DEFAULT 0 CHECK (risk_score >= 0 AND risk_score <= 100),
    risk_tier TEXT NOT NULL DEFAULT 'low' CHECK (risk_tier IN ('low', 'medium', 'high', 'restricted')),
    actions_last_minute INTEGER NOT NULL DEFAULT 0,
    rate_limit_hits INTEGER NOT NULL DEFAULT 0,
    follow_churn_count INTEGER NOT NULL DEFAULT 0,
    window_started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS contact_action_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    action_type TEXT NOT NULL CHECK (action_type IN ('follow', 'unfollow', 'rate_limited')),
    device_fp_hash CHAR(64) NOT NULL,
    ip_fp_hash CHAR(64) NOT NULL,
    risk_score_after INTEGER NOT NULL DEFAULT 0 CHECK (risk_score_after >= 0 AND risk_score_after <= 100),
    outcome TEXT NOT NULL CHECK (outcome IN ('applied', 'noop', 'blocked')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_contact_action_logs_actor_time
    ON contact_action_logs (actor_user_id, created_at DESC);

ALTER TABLE user_follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_follows FORCE ROW LEVEL SECURITY;

ALTER TABLE user_risk_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_risk_scores FORCE ROW LEVEL SECURITY;

ALTER TABLE contact_action_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE contact_action_logs FORCE ROW LEVEL SECURITY;

CREATE POLICY user_follows_select ON user_follows
    FOR SELECT USING (
        follower_id = telefam_current_user_id()
        OR followee_id = telefam_current_user_id()
    );

CREATE POLICY user_follows_insert ON user_follows
    FOR INSERT WITH CHECK (follower_id = telefam_current_user_id());

CREATE POLICY user_follows_delete ON user_follows
    FOR DELETE USING (follower_id = telefam_current_user_id());

CREATE POLICY user_risk_scores_owner ON user_risk_scores
    FOR ALL USING (user_id = telefam_current_user_id() OR telefam_is_auth_service())
    WITH CHECK (user_id = telefam_current_user_id() OR telefam_is_auth_service());

CREATE POLICY contact_action_logs_owner ON contact_action_logs
    FOR SELECT USING (actor_user_id = telefam_current_user_id() OR telefam_is_auth_service());

CREATE POLICY contact_action_logs_insert ON contact_action_logs
    FOR INSERT WITH CHECK (actor_user_id = telefam_current_user_id() OR telefam_is_auth_service());

-- Directory projection returning strictly public profile columns for authenticated viewers
CREATE OR REPLACE FUNCTION telefam_list_directory_profiles(p_viewer_id UUID)
RETURNS TABLE (
    user_id UUID,
    full_name_encrypted BYTEA,
    username_encrypted BYTEA,
    location_encrypted BYTEA,
    avatar_fingerprint_hash CHAR(64),
    is_following BOOLEAN,
    follows_me BOOLEAN,
    risk_score INTEGER,
    updated_at TIMESTAMPTZ
) AS $$
BEGIN
    IF p_viewer_id IS NULL OR p_viewer_id <> telefam_current_user_id() THEN
        RAISE EXCEPTION 'unauthorized directory query';
    END IF;
    RETURN QUERY
    SELECT
        u.id AS user_id,
        up.full_name_encrypted,
        up.username_encrypted,
        up.location_encrypted,
        up.avatar_fingerprint_hash,
        EXISTS (
            SELECT 1 FROM user_follows uf1
            WHERE uf1.follower_id = p_viewer_id AND uf1.followee_id = u.id
        ) AS is_following,
        EXISTS (
            SELECT 1 FROM user_follows uf2
            WHERE uf2.follower_id = u.id AND uf2.followee_id = p_viewer_id
        ) AS follows_me,
        COALESCE(urs.risk_score, 0) AS risk_score,
        up.updated_at
    FROM users u
    JOIN user_profiles up ON up.user_id = u.id
    LEFT JOIN user_risk_scores urs ON urs.user_id = u.id
    WHERE u.profile_completed = TRUE
      AND u.id <> p_viewer_id
    ORDER BY up.updated_at DESC, u.id ASC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

