-- Telefam Owner Profile Background Photos (up to 5 animated crossfade covers),
-- Post Visibility (Locked/Private/Public/Followers), Post Engagement & Strict RLS.

CREATE TABLE IF NOT EXISTS profile_backgrounds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sort_order INTEGER NOT NULL DEFAULT 0 CHECK (sort_order >= 0 AND sort_order < 5),
    mime_type TEXT NOT NULL DEFAULT 'image/jpeg' CHECK (mime_type IN ('image/jpeg', 'image/png')),
    byte_size INTEGER NOT NULL CHECK (byte_size > 0 AND byte_size <= 10485760),
    width INTEGER NOT NULL DEFAULT 0,
    height INTEGER NOT NULL DEFAULT 0,
    fingerprint_hash CHAR(64) NOT NULL,
    sanitized_bytes_encrypted BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_profile_backgrounds_user
    ON profile_backgrounds (user_id, sort_order ASC, created_at ASC);

ALTER TABLE profile_backgrounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE profile_backgrounds FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS profile_backgrounds_owner_rw ON profile_backgrounds;
CREATE POLICY profile_backgrounds_owner_rw ON profile_backgrounds
    FOR ALL USING (user_id = telefam_current_user_id() OR telefam_is_admin_service())
    WITH CHECK (user_id = telefam_current_user_id() OR telefam_is_admin_service());

-- Allow authenticated non-suspended avatar fetches across Contacts / Feed / Followers sheets
DROP POLICY IF EXISTS avatars_auth_read ON profile_avatars;
CREATE POLICY avatars_auth_read ON profile_avatars
    FOR SELECT USING (
        telefam_is_admin_service()
        OR user_id = telefam_current_user_id()
        OR (
            telefam_current_user_id() IS NOT NULL
            AND EXISTS (SELECT 1 FROM users u WHERE u.id = profile_avatars.user_id AND u.is_suspended = FALSE)
        )
    );

-- Support Locked (private) / Followers / Public visibility and engagement metrics on posts
ALTER TABLE posts ADD COLUMN IF NOT EXISTS visibility TEXT NOT NULL DEFAULT 'public'
    CHECK (visibility IN ('public', 'followers', 'private'));
ALTER TABLE posts ADD COLUMN IF NOT EXISTS likes_count BIGINT NOT NULL DEFAULT 0;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS views_count BIGINT NOT NULL DEFAULT 0;

DROP POLICY IF EXISTS posts_read ON posts;
CREATE POLICY posts_read ON posts
    FOR SELECT USING (
        telefam_is_admin_service()
        OR author_id = telefam_current_user_id()
        OR (
            status = 'ready'
            AND telefam_current_user_id() IS NOT NULL
            AND (
                visibility = 'public'
                OR (
                    visibility = 'followers'
                    AND EXISTS (
                        SELECT 1 FROM user_follows uf
                        WHERE uf.follower_id = telefam_current_user_id()
                          AND uf.followee_id = posts.author_id
                    )
                )
            )
        )
    );

CREATE TABLE IF NOT EXISTS post_likes (
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS saved_posts (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, post_id)
);

CREATE TABLE IF NOT EXISTS post_reposts (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, post_id)
);

ALTER TABLE post_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_likes FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS post_likes_read ON post_likes;
CREATE POLICY post_likes_read ON post_likes
    FOR SELECT USING (telefam_current_user_id() IS NOT NULL OR telefam_is_admin_service());
DROP POLICY IF EXISTS post_likes_owner_write ON post_likes;
CREATE POLICY post_likes_owner_write ON post_likes
    FOR ALL USING (user_id = telefam_current_user_id() OR telefam_is_admin_service())
    WITH CHECK (user_id = telefam_current_user_id() OR telefam_is_admin_service());

ALTER TABLE saved_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE saved_posts FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS saved_posts_owner_rw ON saved_posts;
CREATE POLICY saved_posts_owner_rw ON saved_posts
    FOR ALL USING (user_id = telefam_current_user_id() OR telefam_is_admin_service())
    WITH CHECK (user_id = telefam_current_user_id() OR telefam_is_admin_service());

ALTER TABLE post_reposts ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_reposts FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS post_reposts_read ON post_reposts;
CREATE POLICY post_reposts_read ON post_reposts
    FOR SELECT USING (telefam_current_user_id() IS NOT NULL OR telefam_is_admin_service());
DROP POLICY IF EXISTS post_reposts_owner_write ON post_reposts;
CREATE POLICY post_reposts_owner_write ON post_reposts
    FOR ALL USING (user_id = telefam_current_user_id() OR telefam_is_admin_service())
    WITH CHECK (user_id = telefam_current_user_id() OR telefam_is_admin_service());
