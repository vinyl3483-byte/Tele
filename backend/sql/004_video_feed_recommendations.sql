-- Telefam Short-Video Feed, Adaptive HLS Streaming, Signed URLs, Social Graph Extensions,
-- Multi-Step Moderation Reports, and Personalized Recommendation Engine Schema.
-- Reuses existing users, user_profiles, user_follows, posts, post_media, and hashtags tables.

-- ============================================================================
-- 1. AUDIOS & AUDIO USAGE
-- ============================================================================

CREATE TABLE IF NOT EXISTS audios (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    external_track_id VARCHAR(128) UNIQUE,
    creator_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    title_encrypted BYTEA NOT NULL,
    artist_encrypted BYTEA NOT NULL,
    artwork_url TEXT NOT NULL DEFAULT '',
    preview_url TEXT NOT NULL DEFAULT '',
    duration_ms BIGINT NOT NULL DEFAULT 0 CHECK (duration_ms >= 0),
    is_original BOOLEAN NOT NULL DEFAULT TRUE,
    usage_count BIGINT NOT NULL DEFAULT 0 CHECK (usage_count >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audios_usage_count ON audios (usage_count DESC, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audios_creator ON audios (creator_user_id, created_at DESC);

-- ============================================================================
-- 2. VIDEOS, ASSETS & STREAM VARIANTS (240p - 1080p HLS / DASH / MP4)
-- ============================================================================

CREATE TABLE IF NOT EXISTS videos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID UNIQUE REFERENCES posts(id) ON DELETE CASCADE,
    creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    audio_id UUID REFERENCES audios(id) ON DELETE SET NULL,
    title_encrypted BYTEA NOT NULL DEFAULT ''::bytea,
    description_encrypted BYTEA NOT NULL DEFAULT ''::bytea,
    original_width INTEGER NOT NULL CHECK (original_width > 0),
    original_height INTEGER NOT NULL CHECK (original_height > 0),
    aspect_ratio DOUBLE PRECISION NOT NULL CHECK (aspect_ratio > 0),
    duration_ms BIGINT NOT NULL DEFAULT 0 CHECK (duration_ms >= 0),
    codec VARCHAR(32) NOT NULL DEFAULT 'h264',
    file_size BIGINT NOT NULL DEFAULT 0 CHECK (file_size >= 0),
    thumbnail_object_key TEXT NOT NULL DEFAULT '',
    hls_master_object_key TEXT NOT NULL DEFAULT '',
    dash_manifest_object_key TEXT NOT NULL DEFAULT '',
    primary_object_key TEXT NOT NULL DEFAULT '',
    processing_status TEXT NOT NULL DEFAULT 'ready'
        CHECK (processing_status IN ('queued', 'processing', 'ready', 'failed', 'removed')),
    visibility TEXT NOT NULL DEFAULT 'public'
        CHECK (visibility IN ('public', 'followers', 'private')),
    likes_count BIGINT NOT NULL DEFAULT 0 CHECK (likes_count >= 0),
    comments_count BIGINT NOT NULL DEFAULT 0 CHECK (comments_count >= 0),
    shares_count BIGINT NOT NULL DEFAULT 0 CHECK (shares_count >= 0),
    saves_count BIGINT NOT NULL DEFAULT 0 CHECK (saves_count >= 0),
    reposts_count BIGINT NOT NULL DEFAULT 0 CHECK (reposts_count >= 0),
    views_count BIGINT NOT NULL DEFAULT 0 CHECK (views_count >= 0),
    avg_completion_rate DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    content_fingerprint_hash CHAR(64) NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_videos_creator_created ON videos (creator_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_videos_feed_candidates ON videos (processing_status, visibility, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_videos_audio_created ON videos (audio_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_videos_aspect_ratio ON videos (aspect_ratio);

CREATE TABLE IF NOT EXISTS video_assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    media_id UUID REFERENCES post_media(id) ON DELETE SET NULL,
    asset_kind TEXT NOT NULL CHECK (asset_kind IN ('original_sanitized', 'thumbnail', 'hls_master', 'dash_manifest')),
    object_key TEXT NOT NULL,
    mime_type VARCHAR(64) NOT NULL,
    byte_size BIGINT NOT NULL DEFAULT 0 CHECK (byte_size >= 0),
    sha256_hash CHAR(64) NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (video_id, asset_kind, object_key)
);

CREATE INDEX IF NOT EXISTS idx_video_assets_video ON video_assets (video_id);

CREATE TABLE IF NOT EXISTS video_stream_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    quality_label VARCHAR(16) NOT NULL CHECK (quality_label IN ('240p', '360p', '480p', '720p', '1080p', 'auto')),
    width INTEGER NOT NULL CHECK (width > 0),
    height INTEGER NOT NULL CHECK (height > 0),
    bitrate_kbps INTEGER NOT NULL CHECK (bitrate_kbps > 0),
    codec VARCHAR(32) NOT NULL DEFAULT 'h264',
    container TEXT NOT NULL DEFAULT 'hls' CHECK (container IN ('hls', 'dash', 'mp4')),
    playlist_object_key TEXT NOT NULL,
    mp4_object_key TEXT NOT NULL DEFAULT '',
    byte_size BIGINT NOT NULL DEFAULT 0 CHECK (byte_size >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (video_id, quality_label, container)
);

CREATE INDEX IF NOT EXISTS idx_video_variants_video ON video_stream_variants (video_id, bitrate_kbps ASC);

CREATE TABLE IF NOT EXISTS audio_usage (
    audio_id UUID NOT NULL REFERENCES audios(id) ON DELETE CASCADE,
    video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (audio_id, video_id)
);

CREATE TABLE IF NOT EXISTS video_hashtags (
    video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    tag_normalized VARCHAR(80) NOT NULL REFERENCES hashtags(tag_normalized) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (video_id, tag_normalized)
);

CREATE INDEX IF NOT EXISTS idx_video_hashtags_tag ON video_hashtags (tag_normalized, created_at DESC);

-- ============================================================================
-- 3. ENGAGEMENT, WATCH TELEMETRY, SAVES, REPOSTS & FUTURE-READY COMMENTS
-- ============================================================================

CREATE TABLE IF NOT EXISTS video_views (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    viewer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_fp_hash CHAR(64) NOT NULL DEFAULT '',
    watch_duration_ms BIGINT NOT NULL DEFAULT 0 CHECK (watch_duration_ms >= 0),
    completion_pct DOUBLE PRECISION NOT NULL DEFAULT 0.0 CHECK (completion_pct >= 0.0 AND completion_pct <= 100.0),
    rewatch_count INTEGER NOT NULL DEFAULT 0 CHECK (rewatch_count >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_video_views_video ON video_views (video_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_video_views_viewer ON video_views (viewer_id, created_at DESC);

CREATE TABLE IF NOT EXISTS watch_history (
    viewer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    last_position_ms BIGINT NOT NULL DEFAULT 0 CHECK (last_position_ms >= 0),
    max_watch_pct DOUBLE PRECISION NOT NULL DEFAULT 0.0 CHECK (max_watch_pct >= 0.0 AND max_watch_pct <= 100.0),
    total_watch_ms BIGINT NOT NULL DEFAULT 0 CHECK (total_watch_ms >= 0),
    play_count INTEGER NOT NULL DEFAULT 1 CHECK (play_count >= 1),
    completed BOOLEAN NOT NULL DEFAULT FALSE,
    last_watched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (viewer_id, video_id)
);

CREATE INDEX IF NOT EXISTS idx_watch_history_recent ON watch_history (viewer_id, last_watched_at DESC);

CREATE TABLE IF NOT EXISTS video_likes (
    video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (video_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_video_likes_user ON video_likes (user_id, created_at DESC);

-- Future-ready comments table (UI displays Coming Soon; schema enforces strict RLS)
CREATE TABLE IF NOT EXISTS video_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parent_comment_id UUID REFERENCES video_comments(id) ON DELETE CASCADE,
    body_encrypted BYTEA NOT NULL,
    likes_count BIGINT NOT NULL DEFAULT 0 CHECK (likes_count >= 0),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_video_comments_video ON video_comments (video_id, created_at DESC);

CREATE TABLE IF NOT EXISTS saved_videos (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    collection_name VARCHAR(64) NOT NULL DEFAULT 'Favorites',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, video_id)
);

CREATE INDEX IF NOT EXISTS idx_saved_videos_user ON saved_videos (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS reposts (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, video_id)
);

CREATE INDEX IF NOT EXISTS idx_reposts_video ON reposts (video_id, created_at DESC);

CREATE TABLE IF NOT EXISTS video_shares (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    share_channel VARCHAR(32) NOT NULL DEFAULT 'link',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_video_shares_video ON video_shares (video_id, created_at DESC);

-- ============================================================================
-- 4. SAFETY CONTROLS, REPORTS, RECOMMENDATION EVENTS & USER INTERESTS
-- ============================================================================

CREATE TABLE IF NOT EXISTS muted_users (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    muted_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, muted_user_id),
    CHECK (user_id <> muted_user_id)
);

CREATE TABLE IF NOT EXISTS blocked_users (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, blocked_user_id),
    CHECK (user_id <> blocked_user_id)
);

CREATE TABLE IF NOT EXISTS video_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    reporter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason TEXT NOT NULL CHECK (reason IN (
        'spam', 'harassment', 'hate_speech', 'violence',
        'nudity_or_sexual_content', 'misinformation', 'copyright_violation', 'other'
    )),
    details_encrypted BYTEA NOT NULL DEFAULT ''::bytea,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'reviewing', 'resolved', 'dismissed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (video_id, reporter_id, reason)
);

CREATE INDEX IF NOT EXISTS idx_video_reports_status ON video_reports (status, created_at DESC);

CREATE TABLE IF NOT EXISTS recommendation_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    video_id UUID REFERENCES videos(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL CHECK (event_type IN (
        'impression', 'watch_progress', 'complete', 'rewatch',
        'like', 'unlike', 'share', 'save', 'unsave', 'repost',
        'follow', 'not_interested', 'search_query', 'hashtag_tap', 'audio_tap'
    )),
    signal_value DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    context_tag VARCHAR(80) NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rec_events_user_time ON recommendation_events (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_rec_events_video_type ON recommendation_events (video_id, event_type);

CREATE TABLE IF NOT EXISTS user_interests (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    interest_kind TEXT NOT NULL CHECK (interest_kind IN ('hashtag', 'audio', 'creator', 'keyword')),
    interest_key VARCHAR(128) NOT NULL,
    affinity_score DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, interest_kind, interest_key)
);

CREATE INDEX IF NOT EXISTS idx_user_interests_top ON user_interests (user_id, affinity_score DESC);

CREATE TABLE IF NOT EXISTS user_search_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    query_encrypted BYTEA NOT NULL,
    query_hash CHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, query_hash)
);

-- Compatibility views matching standard naming conventions without duplicating tables
CREATE OR REPLACE VIEW follows AS SELECT follower_id, followee_id, created_at FROM user_follows;
CREATE OR REPLACE VIEW likes AS SELECT video_id, user_id, created_at FROM video_likes;
CREATE OR REPLACE VIEW comments AS SELECT * FROM video_comments;
CREATE OR REPLACE VIEW shares AS SELECT * FROM video_shares;
CREATE OR REPLACE VIEW reports AS SELECT * FROM video_reports;

-- ============================================================================
-- 5. STRICT ROW-LEVEL SECURITY (RLS) FOR VIDEO FEED & RECOMMENDATIONS
-- ============================================================================

ALTER TABLE audios ENABLE ROW LEVEL SECURITY;
ALTER TABLE audios FORCE ROW LEVEL SECURITY;
ALTER TABLE videos ENABLE ROW LEVEL SECURITY;
ALTER TABLE videos FORCE ROW LEVEL SECURITY;
ALTER TABLE video_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE video_assets FORCE ROW LEVEL SECURITY;
ALTER TABLE video_stream_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE video_stream_variants FORCE ROW LEVEL SECURITY;
ALTER TABLE audio_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE audio_usage FORCE ROW LEVEL SECURITY;
ALTER TABLE video_hashtags ENABLE ROW LEVEL SECURITY;
ALTER TABLE video_hashtags FORCE ROW LEVEL SECURITY;
ALTER TABLE video_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE video_views FORCE ROW LEVEL SECURITY;
ALTER TABLE watch_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE watch_history FORCE ROW LEVEL SECURITY;
ALTER TABLE video_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE video_likes FORCE ROW LEVEL SECURITY;
ALTER TABLE video_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE video_comments FORCE ROW LEVEL SECURITY;
ALTER TABLE saved_videos ENABLE ROW LEVEL SECURITY;
ALTER TABLE saved_videos FORCE ROW LEVEL SECURITY;
ALTER TABLE reposts ENABLE ROW LEVEL SECURITY;
ALTER TABLE reposts FORCE ROW LEVEL SECURITY;
ALTER TABLE video_shares ENABLE ROW LEVEL SECURITY;
ALTER TABLE video_shares FORCE ROW LEVEL SECURITY;
ALTER TABLE muted_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE muted_users FORCE ROW LEVEL SECURITY;
ALTER TABLE blocked_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE blocked_users FORCE ROW LEVEL SECURITY;
ALTER TABLE video_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE video_reports FORCE ROW LEVEL SECURITY;
ALTER TABLE recommendation_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE recommendation_events FORCE ROW LEVEL SECURITY;
ALTER TABLE user_interests ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_interests FORCE ROW LEVEL SECURITY;
ALTER TABLE user_search_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_search_history FORCE ROW LEVEL SECURITY;

-- Audios
CREATE POLICY audios_read ON audios
    FOR SELECT USING (telefam_is_admin_service() OR telefam_current_user_id() IS NOT NULL);
CREATE POLICY audios_write ON audios
    FOR ALL USING (creator_user_id = telefam_current_user_id() OR telefam_is_admin_service())
    WITH CHECK (creator_user_id = telefam_current_user_id() OR telefam_is_admin_service());

-- Videos (enforces private/followers visibility, blocks, and author ownership)
CREATE POLICY videos_read ON videos
    FOR SELECT USING (
        telefam_is_admin_service()
        OR creator_id = telefam_current_user_id()
        OR (
            processing_status = 'ready'
            AND telefam_current_user_id() IS NOT NULL
            AND NOT EXISTS (
                SELECT 1 FROM blocked_users b
                WHERE (b.user_id = telefam_current_user_id() AND b.blocked_user_id = videos.creator_id)
                   OR (b.user_id = videos.creator_id AND b.blocked_user_id = telefam_current_user_id())
            )
            AND (
                visibility = 'public'
                OR (
                    visibility = 'followers'
                    AND EXISTS (
                        SELECT 1 FROM user_follows uf
                        WHERE uf.follower_id = telefam_current_user_id()
                          AND uf.followee_id = videos.creator_id
                    )
                )
            )
        )
    );

CREATE POLICY videos_owner_write ON videos
    FOR ALL USING (creator_id = telefam_current_user_id() OR telefam_is_admin_service())
    WITH CHECK (creator_id = telefam_current_user_id() OR telefam_is_admin_service());

-- Video Assets & Variants inherit readable visibility from parent video
CREATE POLICY video_assets_read ON video_assets
    FOR SELECT USING (
        telefam_is_admin_service()
        OR EXISTS (SELECT 1 FROM videos v WHERE v.id = video_assets.video_id)
    );
CREATE POLICY video_assets_owner_write ON video_assets
    FOR ALL USING (
        telefam_is_admin_service()
        OR EXISTS (SELECT 1 FROM videos v WHERE v.id = video_assets.video_id AND v.creator_id = telefam_current_user_id())
    )
    WITH CHECK (
        telefam_is_admin_service()
        OR EXISTS (SELECT 1 FROM videos v WHERE v.id = video_assets.video_id AND v.creator_id = telefam_current_user_id())
    );

CREATE POLICY video_variants_read ON video_stream_variants
    FOR SELECT USING (
        telefam_is_admin_service()
        OR EXISTS (SELECT 1 FROM videos v WHERE v.id = video_stream_variants.video_id)
    );
CREATE POLICY video_variants_owner_write ON video_stream_variants
    FOR ALL USING (
        telefam_is_admin_service()
        OR EXISTS (SELECT 1 FROM videos v WHERE v.id = video_stream_variants.video_id AND v.creator_id = telefam_current_user_id())
    )
    WITH CHECK (
        telefam_is_admin_service()
        OR EXISTS (SELECT 1 FROM videos v WHERE v.id = video_stream_variants.video_id AND v.creator_id = telefam_current_user_id())
    );

CREATE POLICY audio_usage_read ON audio_usage
    FOR SELECT USING (telefam_is_admin_service() OR telefam_current_user_id() IS NOT NULL);
CREATE POLICY audio_usage_write ON audio_usage
    FOR ALL USING (
        telefam_is_admin_service()
        OR EXISTS (SELECT 1 FROM videos v WHERE v.id = audio_usage.video_id AND v.creator_id = telefam_current_user_id())
    )
    WITH CHECK (
        telefam_is_admin_service()
        OR EXISTS (SELECT 1 FROM videos v WHERE v.id = audio_usage.video_id AND v.creator_id = telefam_current_user_id())
    );

CREATE POLICY video_hashtags_read ON video_hashtags
    FOR SELECT USING (telefam_is_admin_service() OR telefam_current_user_id() IS NOT NULL);
CREATE POLICY video_hashtags_write ON video_hashtags
    FOR ALL USING (
        telefam_is_admin_service()
        OR EXISTS (SELECT 1 FROM videos v WHERE v.id = video_hashtags.video_id AND v.creator_id = telefam_current_user_id())
    )
    WITH CHECK (
        telefam_is_admin_service()
        OR EXISTS (SELECT 1 FROM videos v WHERE v.id = video_hashtags.video_id AND v.creator_id = telefam_current_user_id())
    );

-- User-scoped engagement & preference tables
CREATE POLICY video_views_owner ON video_views
    FOR ALL USING (viewer_id = telefam_current_user_id() OR telefam_is_admin_service())
    WITH CHECK (viewer_id = telefam_current_user_id() OR telefam_is_admin_service());

CREATE POLICY watch_history_owner ON watch_history
    FOR ALL USING (viewer_id = telefam_current_user_id() OR telefam_is_admin_service())
    WITH CHECK (viewer_id = telefam_current_user_id() OR telefam_is_admin_service());

CREATE POLICY video_likes_read ON video_likes
    FOR SELECT USING (telefam_is_admin_service() OR telefam_current_user_id() IS NOT NULL);
CREATE POLICY video_likes_owner ON video_likes
    FOR ALL USING (user_id = telefam_current_user_id() OR telefam_is_admin_service())
    WITH CHECK (user_id = telefam_current_user_id() OR telefam_is_admin_service());

CREATE POLICY video_comments_read ON video_comments
    FOR SELECT USING (
        telefam_is_admin_service()
        OR (NOT is_deleted AND EXISTS (SELECT 1 FROM videos v WHERE v.id = video_comments.video_id))
    );
CREATE POLICY video_comments_owner ON video_comments
    FOR ALL USING (author_id = telefam_current_user_id() OR telefam_is_admin_service())
    WITH CHECK (author_id = telefam_current_user_id() OR telefam_is_admin_service());

CREATE POLICY saved_videos_owner ON saved_videos
    FOR ALL USING (user_id = telefam_current_user_id() OR telefam_is_admin_service())
    WITH CHECK (user_id = telefam_current_user_id() OR telefam_is_admin_service());

CREATE POLICY reposts_read ON reposts
    FOR SELECT USING (telefam_is_admin_service() OR telefam_current_user_id() IS NOT NULL);
CREATE POLICY reposts_owner ON reposts
    FOR ALL USING (user_id = telefam_current_user_id() OR telefam_is_admin_service())
    WITH CHECK (user_id = telefam_current_user_id() OR telefam_is_admin_service());

CREATE POLICY video_shares_owner ON video_shares
    FOR ALL USING (user_id = telefam_current_user_id() OR telefam_is_admin_service())
    WITH CHECK (user_id = telefam_current_user_id() OR telefam_is_admin_service());

CREATE POLICY muted_users_owner ON muted_users
    FOR ALL USING (user_id = telefam_current_user_id() OR telefam_is_admin_service())
    WITH CHECK (user_id = telefam_current_user_id() OR telefam_is_admin_service());

CREATE POLICY blocked_users_owner ON blocked_users
    FOR ALL USING (user_id = telefam_current_user_id() OR telefam_is_admin_service())
    WITH CHECK (user_id = telefam_current_user_id() OR telefam_is_admin_service());

CREATE POLICY video_reports_owner ON video_reports
    FOR SELECT USING (reporter_id = telefam_current_user_id() OR telefam_is_admin_service());
CREATE POLICY video_reports_insert ON video_reports
    FOR INSERT WITH CHECK (reporter_id = telefam_current_user_id() OR telefam_is_admin_service());

CREATE POLICY rec_events_owner ON recommendation_events
    FOR ALL USING (user_id = telefam_current_user_id() OR telefam_is_admin_service())
    WITH CHECK (user_id = telefam_current_user_id() OR telefam_is_admin_service());

CREATE POLICY user_interests_owner ON user_interests
    FOR ALL USING (user_id = telefam_current_user_id() OR telefam_is_admin_service())
    WITH CHECK (user_id = telefam_current_user_id() OR telefam_is_admin_service());

CREATE POLICY search_history_owner ON user_search_history
    FOR ALL USING (user_id = telefam_current_user_id() OR telefam_is_admin_service())
    WITH CHECK (user_id = telefam_current_user_id() OR telefam_is_admin_service());

-- Public creator metadata projection for video feed, search, hashtag, and audio screens under strict RLS
CREATE OR REPLACE FUNCTION telefam_get_video_creators(p_viewer_id UUID)
RETURNS TABLE (
    user_id UUID,
    full_name_encrypted BYTEA,
    username_encrypted BYTEA,
    display_name_encrypted BYTEA,
    avatar_fingerprint_hash CHAR(64),
    is_following BOOLEAN
) AS $$
BEGIN
    IF p_viewer_id IS NULL OR p_viewer_id <> telefam_current_user_id() THEN
        RAISE EXCEPTION 'unauthorized creator lookup';
    END IF;
    RETURN QUERY
    SELECT
        u.id AS user_id,
        COALESCE(up.full_name_encrypted, ''::bytea) AS full_name_encrypted,
        COALESCE(up.username_encrypted, ''::bytea) AS username_encrypted,
        u.display_name_encrypted,
        COALESCE(up.avatar_fingerprint_hash, ''::char(64)) AS avatar_fingerprint_hash,
        EXISTS (
            SELECT 1 FROM user_follows uf
            WHERE uf.follower_id = p_viewer_id AND uf.followee_id = u.id
        ) AS is_following
    FROM users u
    LEFT JOIN user_profiles up ON up.user_id = u.id
    WHERE COALESCE(u.is_suspended, FALSE) = FALSE;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- Narrow SECURITY DEFINER counter sync so viewers can like/save/share/repost/view another creator's video under videos RLS
CREATE OR REPLACE FUNCTION telefam_sync_video_counters(p_video_id UUID)
RETURNS VOID AS $$
BEGIN
    IF telefam_current_user_id() IS NULL AND NOT telefam_is_admin_service() THEN
        RAISE EXCEPTION 'unauthorized counter sync';
    END IF;
    UPDATE videos v
    SET
        likes_count = (SELECT COUNT(*) FROM video_likes vl WHERE vl.video_id = v.id),
        saves_count = (SELECT COUNT(*) FROM saved_videos sv WHERE sv.video_id = v.id),
        reposts_count = (SELECT COUNT(*) FROM reposts r WHERE r.video_id = v.id),
        shares_count = (SELECT COUNT(*) FROM video_shares vs WHERE vs.video_id = v.id),
        views_count = (SELECT COUNT(*) FROM video_views vv WHERE vv.video_id = v.id),
        avg_completion_rate = COALESCE((SELECT AVG(vv.completion_pct) FROM video_views vv WHERE vv.video_id = v.id), 0.0),
        updated_at = NOW()
    WHERE v.id = p_video_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

