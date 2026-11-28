-- Telefam Other User Profile Social Features:
-- 1) Per-viewer private user nicknames (TikTok-style alias without altering target user's account)
-- 2) Multi-step user moderation reports with encrypted details
-- 3) Authenticated read RLS on profile_backgrounds for public cover slideshows
-- 4) SECURITY DEFINER public profile & connections directory lookups under strict RLS

CREATE TABLE IF NOT EXISTS user_nicknames (
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    nickname_encrypted BYTEA NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (owner_id, target_user_id),
    CHECK (owner_id <> target_user_id)
);

CREATE INDEX IF NOT EXISTS idx_user_nicknames_owner ON user_nicknames (owner_id, updated_at DESC);

ALTER TABLE user_nicknames ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_nicknames FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_nicknames_owner_rw ON user_nicknames;
CREATE POLICY user_nicknames_owner_rw ON user_nicknames
    FOR ALL USING (owner_id = telefam_current_user_id() OR telefam_is_admin_service())
    WITH CHECK (owner_id = telefam_current_user_id() OR telefam_is_admin_service());

CREATE TABLE IF NOT EXISTS user_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reporter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    category TEXT NOT NULL CHECK (category IN (
        'spam', 'harassment', 'impersonation', 'hate_speech',
        'violence', 'nudity_or_sexual_content', 'scam_or_fraud', 'misinformation', 'other'
    )),
    sub_reason TEXT NOT NULL DEFAULT '',
    details_encrypted BYTEA NOT NULL DEFAULT ''::bytea,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'reviewing', 'resolved', 'dismissed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (target_user_id <> reporter_id)
);

CREATE INDEX IF NOT EXISTS idx_user_reports_target ON user_reports (target_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_reports_status ON user_reports (status, created_at DESC);

ALTER TABLE user_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_reports FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_reports_owner_read ON user_reports;
CREATE POLICY user_reports_owner_read ON user_reports
    FOR SELECT USING (reporter_id = telefam_current_user_id() OR telefam_is_admin_service());

DROP POLICY IF EXISTS user_reports_insert ON user_reports;
CREATE POLICY user_reports_insert ON user_reports
    FOR INSERT WITH CHECK (reporter_id = telefam_current_user_id());

DROP POLICY IF EXISTS user_reports_admin_update ON user_reports;
CREATE POLICY user_reports_admin_update ON user_reports
    FOR UPDATE USING (telefam_is_admin_service())
    WITH CHECK (telefam_is_admin_service());

-- Allow authenticated non-suspended viewers to read profile cover backgrounds
DROP POLICY IF EXISTS profile_backgrounds_auth_read ON profile_backgrounds;
CREATE POLICY profile_backgrounds_auth_read ON profile_backgrounds
    FOR SELECT USING (
        telefam_is_admin_service()
        OR user_id = telefam_current_user_id()
        OR (
            telefam_current_user_id() IS NOT NULL
            AND EXISTS (SELECT 1 FROM users u WHERE u.id = profile_backgrounds.user_id AND u.is_suspended = FALSE)
        )
    );

-- Public profile lookup function respecting viewer identity and block/mute boundaries
CREATE OR REPLACE FUNCTION telefam_get_user_public_profile(p_viewer_id UUID, p_target_id UUID)
RETURNS TABLE (
    user_id UUID,
    full_name_encrypted BYTEA,
    username_encrypted BYTEA,
    location_encrypted BYTEA,
    bio_encrypted BYTEA,
    avatar_fingerprint_hash CHAR(64),
    is_following BOOLEAN,
    follows_me BOOLEAN,
    is_blocked BOOLEAN,
    is_blocked_by BOOLEAN,
    is_muted BOOLEAN,
    followers_count BIGINT,
    following_count BIGINT,
    subscribers_count BIGINT,
    posts_count BIGINT
) AS $$
BEGIN
    IF p_viewer_id IS NULL OR p_viewer_id <> telefam_current_user_id() THEN
        RAISE EXCEPTION 'unauthorized profile lookup';
    END IF;
    RETURN QUERY
    SELECT
        u.id AS user_id,
        COALESCE(up.full_name_encrypted, u.display_name_encrypted, ''::bytea) AS full_name_encrypted,
        COALESCE(up.username_encrypted, ''::bytea) AS username_encrypted,
        COALESCE(up.location_encrypted, ''::bytea) AS location_encrypted,
        COALESCE(up.bio_encrypted, ''::bytea) AS bio_encrypted,
        COALESCE(up.avatar_fingerprint_hash, ''::char(64)) AS avatar_fingerprint_hash,
        EXISTS (
            SELECT 1 FROM user_follows uf1
            WHERE uf1.follower_id = p_viewer_id AND uf1.followee_id = u.id
        ) AS is_following,
        EXISTS (
            SELECT 1 FROM user_follows uf2
            WHERE uf2.follower_id = u.id AND uf2.followee_id = p_viewer_id
        ) AS follows_me,
        EXISTS (
            SELECT 1 FROM blocked_users bu1
            WHERE bu1.user_id = p_viewer_id AND bu1.blocked_user_id = u.id
        ) AS is_blocked,
        EXISTS (
            SELECT 1 FROM blocked_users bu2
            WHERE bu2.user_id = u.id AND bu2.blocked_user_id = p_viewer_id
        ) AS is_blocked_by,
        EXISTS (
            SELECT 1 FROM muted_users mu
            WHERE mu.user_id = p_viewer_id AND mu.muted_user_id = u.id
        ) AS is_muted,
        (SELECT COUNT(*) FROM user_follows f1 WHERE f1.followee_id = u.id) AS followers_count,
        (SELECT COUNT(*) FROM user_follows f2 WHERE f2.follower_id = u.id) AS following_count,
        0::BIGINT AS subscribers_count,
        (SELECT COUNT(*) FROM posts p WHERE p.author_id = u.id AND p.status = 'ready' AND p.visibility <> 'private') AS posts_count
    FROM users u
    LEFT JOIN user_profiles up ON up.user_id = u.id
    WHERE u.id = p_target_id
      AND COALESCE(u.is_suspended, FALSE) = FALSE;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- List another user's followers or following with viewer's relationship status
CREATE OR REPLACE FUNCTION telefam_list_user_connections(p_viewer_id UUID, p_owner_id UUID, p_kind TEXT)
RETURNS TABLE (
    user_id UUID,
    full_name_encrypted BYTEA,
    username_encrypted BYTEA,
    location_encrypted BYTEA,
    avatar_fingerprint_hash CHAR(64),
    is_following BOOLEAN,
    follows_me BOOLEAN,
    risk_score INTEGER
) AS $$
BEGIN
    IF p_viewer_id IS NULL OR p_viewer_id <> telefam_current_user_id() THEN
        RAISE EXCEPTION 'unauthorized connections lookup';
    END IF;
    IF p_kind = 'followers' THEN
        RETURN QUERY
        SELECT
            u.id AS user_id,
            COALESCE(up.full_name_encrypted, u.display_name_encrypted, ''::bytea) AS full_name_encrypted,
            COALESCE(up.username_encrypted, ''::bytea) AS username_encrypted,
            COALESCE(up.location_encrypted, ''::bytea) AS location_encrypted,
            COALESCE(up.avatar_fingerprint_hash, ''::char(64)) AS avatar_fingerprint_hash,
            EXISTS (SELECT 1 FROM user_follows vf1 WHERE vf1.follower_id = p_viewer_id AND vf1.followee_id = u.id) AS is_following,
            EXISTS (SELECT 1 FROM user_follows vf2 WHERE vf2.follower_id = u.id AND vf2.followee_id = p_viewer_id) AS follows_me,
            COALESCE(urs.risk_score, 0) AS risk_score
        FROM user_follows uf
        JOIN users u ON u.id = uf.follower_id
        LEFT JOIN user_profiles up ON up.user_id = u.id
        LEFT JOIN user_risk_scores urs ON urs.user_id = u.id
        WHERE uf.followee_id = p_owner_id
          AND COALESCE(u.is_suspended, FALSE) = FALSE
        ORDER BY uf.created_at DESC
        LIMIT 100;
    ELSE
        RETURN QUERY
        SELECT
            u.id AS user_id,
            COALESCE(up.full_name_encrypted, u.display_name_encrypted, ''::bytea) AS full_name_encrypted,
            COALESCE(up.username_encrypted, ''::bytea) AS username_encrypted,
            COALESCE(up.location_encrypted, ''::bytea) AS location_encrypted,
            COALESCE(up.avatar_fingerprint_hash, ''::char(64)) AS avatar_fingerprint_hash,
            EXISTS (SELECT 1 FROM user_follows vf1 WHERE vf1.follower_id = p_viewer_id AND vf1.followee_id = u.id) AS is_following,
            EXISTS (SELECT 1 FROM user_follows vf2 WHERE vf2.follower_id = u.id AND vf2.followee_id = p_viewer_id) AS follows_me,
            COALESCE(urs.risk_score, 0) AS risk_score
        FROM user_follows uf
        JOIN users u ON u.id = uf.followee_id
        LEFT JOIN user_profiles up ON up.user_id = u.id
        LEFT JOIN user_risk_scores urs ON urs.user_id = u.id
        WHERE uf.follower_id = p_owner_id
          AND COALESCE(u.is_suspended, FALSE) = FALSE
        ORDER BY uf.created_at DESC
        LIMIT 100;
    END IF;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;
