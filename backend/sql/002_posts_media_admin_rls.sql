-- Telefam Posts, Multi-Media Pipelines, Frame Fingerprints, Hashtags & Admin RLS Bypass
-- Strict Row-Level Security (RLS) with verified Admin Bypass role support.

CREATE OR REPLACE FUNCTION telefam_is_admin_service() RETURNS BOOLEAN AS $$
    SELECT COALESCE(current_setting('app.admin_bypass_rls', true), '') = 'telefam_admin_active';
$$ LANGUAGE SQL STABLE;

-- Extend existing user/profile policies so verified admin key operations bypass RLS cleanly
DROP POLICY IF EXISTS users_admin_all ON users;
CREATE POLICY users_admin_all ON users
    FOR ALL USING (telefam_is_admin_service())
    WITH CHECK (telefam_is_admin_service());

DROP POLICY IF EXISTS profiles_admin_all ON user_profiles;
CREATE POLICY profiles_admin_all ON user_profiles
    FOR ALL USING (telefam_is_admin_service())
    WITH CHECK (telefam_is_admin_service());

DROP POLICY IF EXISTS avatars_admin_all ON profile_avatars;
CREATE POLICY avatars_admin_all ON profile_avatars
    FOR ALL USING (telefam_is_admin_service())
    WITH CHECK (telefam_is_admin_service());

CREATE TABLE IF NOT EXISTS posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_type TEXT NOT NULL CHECK (post_type IN ('text', 'photos', 'video')),
    body_encrypted BYTEA NOT NULL,
    bg_color_hex VARCHAR(16) NOT NULL DEFAULT '',
    bg_theme_id VARCHAR(48) NOT NULL DEFAULT '',
    font_family VARCHAR(48) NOT NULL DEFAULT 'classic',
    song_id VARCHAR(96) NOT NULL DEFAULT '',
    song_title_encrypted BYTEA,
    song_artist_encrypted BYTEA,
    song_preview_url TEXT NOT NULL DEFAULT '',
    mute_original_audio BOOLEAN NOT NULL DEFAULT FALSE,
    trim_start_ms BIGINT NOT NULL DEFAULT 0 CHECK (trim_start_ms >= 0),
    trim_end_ms BIGINT NOT NULL DEFAULT 0 CHECK (trim_end_ms >= 0),
    content_fingerprint_hash CHAR(64) NOT NULL,
    status TEXT NOT NULL DEFAULT 'ready' CHECK (status IN ('processing', 'ready', 'removed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_posts_author_created ON posts (author_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_content_fp ON posts (content_fingerprint_hash);

CREATE TABLE IF NOT EXISTS post_media (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    media_kind TEXT NOT NULL CHECK (media_kind IN ('photo', 'video')),
    sort_order INTEGER NOT NULL DEFAULT 0,
    renamed_filename VARCHAR(128) NOT NULL,
    stored_object_key TEXT NOT NULL,
    mime_type VARCHAR(64) NOT NULL,
    byte_size BIGINT NOT NULL CHECK (byte_size > 0 AND byte_size <= 209715200),
    width INTEGER NOT NULL DEFAULT 0,
    height INTEGER NOT NULL DEFAULT 0,
    duration_ms BIGINT NOT NULL DEFAULT 0,
    content_id CHAR(64) NOT NULL,
    audio_fingerprint_hash CHAR(64) NOT NULL DEFAULT '',
    thumbnail_object_key TEXT NOT NULL DEFAULT '',
    thumbnail_fingerprint_hash CHAR(64) NOT NULL DEFAULT '',
    qualities_json JSONB NOT NULL DEFAULT '[]'::jsonb,
    sanitized_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_post_media_post ON post_media (post_id, sort_order ASC);
CREATE INDEX IF NOT EXISTS idx_post_media_content_id ON post_media (content_id);
CREATE INDEX IF NOT EXISTS idx_post_media_author ON post_media (author_id, created_at DESC);

CREATE TABLE IF NOT EXISTS media_frame_fingerprints (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    media_id UUID NOT NULL REFERENCES post_media(id) ON DELETE CASCADE,
    stream_kind TEXT NOT NULL CHECK (stream_kind IN ('video_frame', 'audio_frame', 'image')),
    frame_index INTEGER NOT NULL,
    timestamp_ms BIGINT NOT NULL DEFAULT 0,
    perceptual_dhash CHAR(16) NOT NULL DEFAULT '',
    sha256_hash CHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_media_frames_media ON media_frame_fingerprints (media_id, stream_kind, frame_index);
CREATE INDEX IF NOT EXISTS idx_media_frames_dhash ON media_frame_fingerprints (perceptual_dhash);

CREATE TABLE IF NOT EXISTS hashtags (
    tag_normalized VARCHAR(80) PRIMARY KEY,
    display_tag VARCHAR(80) NOT NULL,
    post_count BIGINT NOT NULL DEFAULT 0 CHECK (post_count >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_hashtags_count ON hashtags (post_count DESC, tag_normalized ASC);

CREATE TABLE IF NOT EXISTS post_hashtags (
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    tag_normalized VARCHAR(80) NOT NULL REFERENCES hashtags(tag_normalized) ON DELETE CASCADE,
    PRIMARY KEY (post_id, tag_normalized)
);

CREATE TABLE IF NOT EXISTS post_tags (
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    tagged_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    PRIMARY KEY (post_id, tagged_user_id)
);

CREATE TABLE IF NOT EXISTS admin_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    action_type VARCHAR(64) NOT NULL,
    target_user_id UUID,
    target_media_id UUID,
    details_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- STRICT RLS FOR POSTS, MEDIA, FRAME FINGERPRINTS, HASHTAGS & TAGS
-- ============================================================================

ALTER TABLE posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE posts FORCE ROW LEVEL SECURITY;

ALTER TABLE post_media ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_media FORCE ROW LEVEL SECURITY;

ALTER TABLE media_frame_fingerprints ENABLE ROW LEVEL SECURITY;
ALTER TABLE media_frame_fingerprints FORCE ROW LEVEL SECURITY;

ALTER TABLE hashtags ENABLE ROW LEVEL SECURITY;
ALTER TABLE hashtags FORCE ROW LEVEL SECURITY;

ALTER TABLE post_hashtags ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_hashtags FORCE ROW LEVEL SECURITY;

ALTER TABLE post_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_tags FORCE ROW LEVEL SECURITY;

ALTER TABLE admin_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_audit_logs FORCE ROW LEVEL SECURITY;

CREATE POLICY posts_read ON posts
    FOR SELECT USING (
        telefam_is_admin_service()
        OR (status = 'ready' AND telefam_current_user_id() IS NOT NULL)
        OR author_id = telefam_current_user_id()
    );

CREATE POLICY posts_author_write ON posts
    FOR ALL USING (author_id = telefam_current_user_id() OR telefam_is_admin_service())
    WITH CHECK (author_id = telefam_current_user_id() OR telefam_is_admin_service());

CREATE POLICY post_media_read ON post_media
    FOR SELECT USING (
        telefam_is_admin_service()
        OR author_id = telefam_current_user_id()
        OR EXISTS (
            SELECT 1 FROM posts p
            WHERE p.id = post_media.post_id AND p.status = 'ready'
        )
    );

DROP POLICY IF EXISTS post_media_write ON post_media;
CREATE POLICY post_media_insert ON post_media
    FOR INSERT WITH CHECK (
        (author_id = telefam_current_user_id() AND post_id IS NULL)
        OR telefam_is_admin_service()
    );

CREATE POLICY post_media_update ON post_media
    FOR UPDATE USING (author_id = telefam_current_user_id() OR telefam_is_admin_service())
    WITH CHECK (
        telefam_is_admin_service()
        OR (
            author_id = telefam_current_user_id()
            AND (
                post_id IS NULL
                OR EXISTS (
                    SELECT 1 FROM posts p
                    WHERE p.id = post_media.post_id
                      AND p.author_id = telefam_current_user_id()
                )
            )
        )
    );

CREATE POLICY post_media_delete ON post_media
    FOR DELETE USING (author_id = telefam_current_user_id() OR telefam_is_admin_service());

CREATE POLICY media_frames_read ON media_frame_fingerprints
    FOR SELECT USING (
        telefam_is_admin_service()
        OR EXISTS (
            SELECT 1 FROM post_media pm
            WHERE pm.id = media_frame_fingerprints.media_id
              AND pm.author_id = telefam_current_user_id()
        )
    );

CREATE POLICY media_frames_write ON media_frame_fingerprints
    FOR ALL USING (
        telefam_is_admin_service()
        OR EXISTS (
            SELECT 1 FROM post_media pm
            WHERE pm.id = media_frame_fingerprints.media_id
              AND pm.author_id = telefam_current_user_id()
        )
    )
    WITH CHECK (
        telefam_is_admin_service()
        OR EXISTS (
            SELECT 1 FROM post_media pm
            WHERE pm.id = media_frame_fingerprints.media_id
              AND pm.author_id = telefam_current_user_id()
        )
    );

CREATE POLICY hashtags_read ON hashtags
    FOR SELECT USING (telefam_is_admin_service() OR telefam_current_user_id() IS NOT NULL);

DROP POLICY IF EXISTS hashtags_write ON hashtags;
CREATE POLICY hashtags_admin_all ON hashtags
    FOR ALL USING (telefam_is_admin_service())
    WITH CHECK (telefam_is_admin_service());

CREATE OR REPLACE FUNCTION telefam_bump_hashtag(p_tag VARCHAR) RETURNS VOID AS $$
DECLARE
    v_norm VARCHAR(80);
BEGIN
    IF telefam_current_user_id() IS NULL AND NOT telefam_is_admin_service() THEN
        RAISE EXCEPTION 'unauthorized hashtag mutation';
    END IF;
    v_norm := LEFT(regexp_replace(lower(trim(leading '#' from trim(COALESCE(p_tag, '')))), '[^a-z0-9_]+', '', 'g'), 64);
    IF length(v_norm) = 0 THEN
        RETURN;
    END IF;
    INSERT INTO hashtags (tag_normalized, display_tag, post_count, updated_at)
    VALUES (v_norm, v_norm, 1, NOW())
    ON CONFLICT (tag_normalized) DO UPDATE SET
        post_count = hashtags.post_count + 1,
        updated_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE POLICY post_hashtags_read ON post_hashtags
    FOR SELECT USING (telefam_is_admin_service() OR telefam_current_user_id() IS NOT NULL);

CREATE POLICY post_hashtags_write ON post_hashtags
    FOR ALL USING (
        telefam_is_admin_service()
        OR EXISTS (SELECT 1 FROM posts p WHERE p.id = post_hashtags.post_id AND p.author_id = telefam_current_user_id())
    )
    WITH CHECK (
        telefam_is_admin_service()
        OR EXISTS (SELECT 1 FROM posts p WHERE p.id = post_hashtags.post_id AND p.author_id = telefam_current_user_id())
    );

CREATE POLICY post_tags_read ON post_tags
    FOR SELECT USING (telefam_is_admin_service() OR telefam_current_user_id() IS NOT NULL);

CREATE POLICY post_tags_write ON post_tags
    FOR ALL USING (
        telefam_is_admin_service()
        OR EXISTS (SELECT 1 FROM posts p WHERE p.id = post_tags.post_id AND p.author_id = telefam_current_user_id())
    )
    WITH CHECK (
        telefam_is_admin_service()
        OR EXISTS (SELECT 1 FROM posts p WHERE p.id = post_tags.post_id AND p.author_id = telefam_current_user_id())
    );

CREATE POLICY admin_audit_only ON admin_audit_logs
    FOR ALL USING (telefam_is_admin_service())
    WITH CHECK (telefam_is_admin_service());
