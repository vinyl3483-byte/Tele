package main

import (
	"context"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/telefam/company/backend/go-gateway/internal/admin"
	"github.com/telefam/company/backend/go-gateway/internal/auth"
	"github.com/telefam/company/backend/go-gateway/internal/chat"
	"github.com/telefam/company/backend/go-gateway/internal/config"
	"github.com/telefam/company/backend/go-gateway/internal/contacts"
	"github.com/telefam/company/backend/go-gateway/internal/feed"
	"github.com/telefam/company/backend/go-gateway/internal/media"
	"github.com/telefam/company/backend/go-gateway/internal/middleware"
	"github.com/telefam/company/backend/go-gateway/internal/posts"
	"github.com/telefam/company/backend/go-gateway/internal/profile"
	"github.com/telefam/company/backend/go-gateway/internal/ratelimit"
	"github.com/telefam/company/backend/go-gateway/internal/security"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config error: %v", err)
	}

	ctx := context.Background()
	pool, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("db connection error: %v", err)
	}
	defer pool.Close()

	limiter := ratelimit.New(pool)
	authSvc := auth.NewService(cfg, pool, limiter)
	chatSvc := chat.NewService(cfg, pool)
	profileSvc := profile.NewService(cfg, pool)
	contactsSvc := contacts.NewService(cfg, pool, limiter)
	postsSvc := posts.NewService(cfg, pool)
	feedSvc := feed.NewService(cfg, pool)
	adminSvc := admin.NewService(cfg, pool)

	if err := adminSvc.EnsureBootstrapFromEnv(ctx); err != nil {
		log.Printf("super admin env bootstrap note: %v", err)
	}

	mux := http.NewServeMux()
	clientIPFP := func(r *http.Request) string {
		return security.ComputeIPFingerprint(cfg.HMACPepper, security.ExtractClientIPTrusted(r, cfg.TrustedProxies))
	}

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		healthCtx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()
		if err := pool.Ping(healthCtx); err != nil {
			middleware.WriteJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "unavailable"})
			return
		}
		middleware.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	// =========================================================================
	// AUTHENTICATION & SESSION LIFECYCLE
	// =========================================================================

	mux.HandleFunc("POST /v1/auth/otp/send", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Email               string `json:"email"`
			DeviceFingerprint   string `json:"device_fingerprint"`
			HardwareAttestation string `json:"hardware_attestation"`
			DeviceName          string `json:"device_name"`
			Platform            string `json:"platform"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16384)).Decode(&req); err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		res, status, err := authSvc.SendOTP(r.Context(), req.Email, req.DeviceFingerprint, clientIPFP(r), req.HardwareAttestation, req.DeviceName, req.Platform)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, res)
	})

	mux.HandleFunc("POST /v1/auth/otp/verify", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Email               string `json:"email"`
			OTP                 string `json:"otp"`
			MagicToken          string `json:"magic_token"`
			DeviceFingerprint   string `json:"device_fingerprint"`
			HardwareAttestation string `json:"hardware_attestation"`
			DeviceName          string `json:"device_name"`
			Platform            string `json:"platform"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16384)).Decode(&req); err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		res, status, err := authSvc.VerifyOTPOrMagicLink(r.Context(), req.Email, req.OTP, req.MagicToken, req.DeviceFingerprint, clientIPFP(r), req.HardwareAttestation, req.DeviceName, req.Platform)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, res)
	})

	mux.HandleFunc("POST /v1/auth/oauth/{provider}", func(w http.ResponseWriter, r *http.Request) {
		provider := r.PathValue("provider")
		var req struct {
			IDToken             string `json:"id_token"`
			DeviceFingerprint   string `json:"device_fingerprint"`
			HardwareAttestation string `json:"hardware_attestation"`
			DeviceName          string `json:"device_name"`
			Platform            string `json:"platform"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 32768)).Decode(&req); err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		res, status, err := authSvc.VerifyOAuth(r.Context(), provider, req.IDToken, req.DeviceFingerprint, clientIPFP(r), req.HardwareAttestation, req.DeviceName, req.Platform)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, res)
	})

	mux.HandleFunc("POST /v1/auth/refresh", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			RefreshToken        string `json:"refresh_token"`
			DeviceFingerprint   string `json:"device_fingerprint"`
			HardwareAttestation string `json:"hardware_attestation"`
			Platform            string `json:"platform"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16384)).Decode(&req); err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		res, status, err := authSvc.RefreshSession(r.Context(), req.RefreshToken, req.DeviceFingerprint, req.HardwareAttestation, req.Platform, clientIPFP(r))
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, res)
	})

	requireAuth := func(next func(w http.ResponseWriter, r *http.Request, userID uuid.UUID, sessionID uuid.UUID, devFP string)) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			hdr := r.Header.Get("Authorization")
			if !strings.HasPrefix(hdr, "Bearer ") {
				middleware.WriteSanitizedError(w, http.StatusUnauthorized, nil)
				return
			}
			uid, sid, devFP, err := authSvc.ParseAndValidateAccessToken(r.Context(), strings.TrimPrefix(hdr, "Bearer "))
			if err != nil {
				middleware.WriteSanitizedError(w, http.StatusUnauthorized, err)
				return
			}
			if !limiter.AllowAuthenticatedAPI(r.Context(), uid.String(), devFP, clientIPFP(r)) {
				middleware.WriteSanitizedError(w, http.StatusTooManyRequests, nil)
				return
			}
			next(w, r, uid, sid, devFP)
		}
	}

	mux.HandleFunc("POST /v1/auth/logout", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, sid uuid.UUID, _ string) {
		status, err := authSvc.LogoutSession(r.Context(), uid, sid)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]bool{"logged_out": true})
	}))

	// =========================================================================
	// PROFILE, CONTACTS, NOTIFICATIONS, CHATS & POSTS
	// =========================================================================

	mux.HandleFunc("GET /v1/profile/me", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		res, status, err := profileSvc.GetMyProfile(r.Context(), uid)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, res)
	}))

	mux.HandleFunc("POST /v1/profile/avatar", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		limited := http.MaxBytesReader(w, r.Body, media.MaxUploadBytes)
		raw, err := io.ReadAll(limited)
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		fp, status, err := profileSvc.UploadAvatar(r.Context(), uid, raw)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]string{"avatar_fingerprint_hash": fp})
	}))

	mux.HandleFunc("POST /v1/profile/setup", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		var req profile.SetupRequest
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16384)).Decode(&req); err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		res, status, err := profileSvc.SetupProfile(r.Context(), uid, req)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, res)
	}))

	mux.HandleFunc("GET /v1/contacts", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		filter := r.URL.Query().Get("filter")
		query := r.URL.Query().Get("q")
		cursor := r.URL.Query().Get("cursor")
		limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
		page, status, err := contactsSvc.ListContacts(r.Context(), uid, filter, query, cursor, limit)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, page)
	}))

	mux.HandleFunc("POST /v1/contacts/follow", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, devFP string) {
		var req contacts.FollowActionRequest
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&req); err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		targetID, err := uuid.Parse(strings.TrimSpace(req.TargetUserID))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		res, status, err := contactsSvc.SetFollowState(r.Context(), uid, targetID, req.Follow, devFP, clientIPFP(r))
		if err != nil {
			if status == http.StatusTooManyRequests {
				middleware.WriteJSON(w, http.StatusTooManyRequests, map[string]string{
					"error": "Try again later",
				})
				return
			}
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, res)
	}))

	mux.HandleFunc("GET /v1/notifications", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		items, status, err := contactsSvc.ListNotifications(r.Context(), uid)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"notifications": items})
	}))

	mux.HandleFunc("POST /v1/notifications/read", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		status, err := contactsSvc.MarkNotificationsRead(r.Context(), uid)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]bool{"ok": true})
	}))

	mux.HandleFunc("GET /v1/conversations", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		items, status, err := chatSvc.ListConversations(r.Context(), uid)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"conversations": items})
	}))

	mux.HandleFunc("POST /v1/conversations", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		var req struct {
			Title string `json:"title"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8192)).Decode(&req); err != nil || strings.TrimSpace(req.Title) == "" {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		item, status, err := chatSvc.CreateConversation(r.Context(), uid, strings.TrimSpace(req.Title))
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, item)
	}))

	mux.HandleFunc("GET /v1/conversations/{id}/messages", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		convID, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		sinceMs, _ := strconv.ParseInt(r.URL.Query().Get("since_ms"), 10, 64)
		msgs, status, err := chatSvc.ListMessages(r.Context(), uid, convID, sinceMs)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"messages": msgs})
	}))

	mux.HandleFunc("POST /v1/sync/mutations", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, devFP string) {
		var req struct {
			Mutations []chat.OfflineMutation `json:"mutations"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 262144)).Decode(&req); err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		acked, status, err := chatSvc.ApplyMutationsBatch(r.Context(), uid, devFP, req.Mutations)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"acked_ids": acked})
	}))

	mux.HandleFunc("GET /v1/music/search", requireAuth(func(w http.ResponseWriter, r *http.Request, _, _ uuid.UUID, _ string) {
		q := r.URL.Query().Get("q")
		tracks, status, err := postsSvc.SearchPublicSongs(r.Context(), q)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"tracks": tracks})
	}))

	mux.HandleFunc("GET /v1/hashtags/search", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		q := r.URL.Query().Get("q")
		items, status, err := postsSvc.SearchHashtags(r.Context(), uid, q)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"hashtags": items})
	}))

	mux.HandleFunc("GET /v1/posts/feed", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		q := r.URL.Query().Get("q")
		limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
		items, status, err := postsSvc.ListFeedPosts(r.Context(), uid, q, limit)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"posts": items})
	}))

	mux.HandleFunc("POST /v1/posts/media/photos", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		r.Body = http.MaxBytesReader(w, r.Body, 100*1024*1024)
		if err := r.ParseMultipartForm(32 * 1024 * 1024); err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		defer func() {
			if r.MultipartForm != nil {
				_ = r.MultipartForm.RemoveAll()
			}
		}()
		files := r.MultipartForm.File["photos"]
		if len(files) == 0 || len(files) > 10 {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, nil)
			return
		}
		rawList := make([][]byte, 0, len(files))
		for _, fh := range files {
			f, err := fh.Open()
			if err != nil {
				middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
				return
			}
			b, rErr := io.ReadAll(io.LimitReader(f, media.MaxPostPhotoBytes+1))
			_ = f.Close()
			if rErr != nil || len(b) > media.MaxPostPhotoBytes {
				middleware.WriteSanitizedError(w, http.StatusBadRequest, rErr)
				return
			}
			rawList = append(rawList, b)
		}
		uploaded, status, err := postsSvc.UploadAndSanitizePhotos(r.Context(), uid, rawList)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"media": uploaded})
	}))

	mux.HandleFunc("POST /v1/posts/media/video", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		r.Body = http.MaxBytesReader(w, r.Body, media.MaxVideoUploadBytes+4*1024*1024)
		if err := r.ParseMultipartForm(16 * 1024 * 1024); err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		defer func() {
			if r.MultipartForm != nil {
				_ = r.MultipartForm.RemoveAll()
			}
		}()
		file, _, err := r.FormFile("video")
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		defer func() { _ = file.Close() }()

		tmpVid, err := os.CreateTemp("", "telefam-upload-*.bin")
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusInternalServerError, err)
			return
		}
		tmpPath := tmpVid.Name()
		defer func() { _ = os.Remove(tmpPath) }()

		written, err := io.Copy(tmpVid, io.LimitReader(file, media.MaxVideoUploadBytes+1))
		_ = tmpVid.Close()
		if err != nil || written == 0 || written > media.MaxVideoUploadBytes {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}

		var thumbBytes []byte
		if tf, _, tErr := r.FormFile("thumbnail"); tErr == nil {
			thumbBytes, _ = io.ReadAll(io.LimitReader(tf, media.MaxUploadBytes))
			_ = tf.Close()
		}

		trimStartMs, _ := strconv.ParseInt(r.FormValue("trim_start_ms"), 10, 64)
		trimEndMs, _ := strconv.ParseInt(r.FormValue("trim_end_ms"), 10, 64)
		thumbAtMs, _ := strconv.ParseInt(r.FormValue("thumbnail_at_ms"), 10, 64)
		muteOrig := r.FormValue("mute_original_audio") == "true"
		songPreview := r.FormValue("song_preview_url")

		res, status, err := postsSvc.UploadAndSanitizeVideo(r.Context(), uid, tmpPath, written, media.VideoSanitizeOptions{
			TrimStartMs:       trimStartMs,
			TrimEndMs:         trimEndMs,
			ThumbnailAtMs:     thumbAtMs,
			MuteOriginalAudio: muteOrig,
			SongPreviewURL:    songPreview,
			ExplicitThumbJPEG: thumbBytes,
		})
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, res)
	}))

	mux.HandleFunc("POST /v1/posts", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		var req posts.CreatePostRequest
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 65536)).Decode(&req); err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		res, status, err := postsSvc.CreatePost(r.Context(), uid, req)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, res)
	}))

	// =========================================================================
	// SHORT-VIDEO FEED, ADAPTIVE SIGNED STREAMING, DISCOVERY & RECOMMENDATIONS
	// =========================================================================

	mux.HandleFunc("GET /v1/media/signed/{token}/{rest...}", func(w http.ResponseWriter, r *http.Request) {
		feedSvc.ServeSignedMedia(w, r, r.PathValue("token"), r.PathValue("rest"))
	})

	mux.HandleFunc("GET /v1/feed/for-you", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
		page, status, err := feedSvc.GetForYouFeed(r.Context(), uid, r.URL.Query().Get("cursor"), limit)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, page)
	}))

	mux.HandleFunc("GET /v1/feed/following", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
		page, status, err := feedSvc.GetFollowingFeed(r.Context(), uid, r.URL.Query().Get("cursor"), limit)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, page)
	}))

	mux.HandleFunc("GET /v1/videos/{id}/refresh-stream-url", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		vid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		res, status, err := feedSvc.RefreshStreamURL(r.Context(), uid, vid)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, res)
	}))

	mux.HandleFunc("POST /v1/videos/{id}/view", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, devFP string) {
		vid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		var req struct {
			WatchDurationMs int64   `json:"watch_duration_ms"`
			LastPositionMs  int64   `json:"last_position_ms"`
			CompletionPct   float64 `json:"completion_pct"`
			RewatchDelta    int     `json:"rewatch_delta"`
		}
		_ = json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&req)
		status, err := feedSvc.RecordViewOrProgress(r.Context(), uid, vid, devFP, req.WatchDurationMs, req.LastPositionMs, req.CompletionPct, req.RewatchDelta)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]bool{"ok": true})
	}))

	mux.HandleFunc("POST /v1/videos/{id}/watch-progress", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, devFP string) {
		vid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		var req struct {
			WatchDurationMs int64   `json:"watch_duration_ms"`
			LastPositionMs  int64   `json:"last_position_ms"`
			CompletionPct   float64 `json:"completion_pct"`
			RewatchDelta    int     `json:"rewatch_delta"`
		}
		_ = json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&req)
		status, err := feedSvc.RecordViewOrProgress(r.Context(), uid, vid, devFP, req.WatchDurationMs, req.LastPositionMs, req.CompletionPct, req.RewatchDelta)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]bool{"ok": true})
	}))

	mux.HandleFunc("POST /v1/videos/{id}/like", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		vid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		cnt, liked, status, err := feedSvc.SetLikeState(r.Context(), uid, vid, true)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"likes_count": cnt, "is_liked": liked})
	}))

	mux.HandleFunc("DELETE /v1/videos/{id}/like", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		vid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		cnt, liked, status, err := feedSvc.SetLikeState(r.Context(), uid, vid, false)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"likes_count": cnt, "is_liked": liked})
	}))

	mux.HandleFunc("POST /v1/videos/{id}/save", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		vid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		cnt, saved, status, err := feedSvc.SetSaveState(r.Context(), uid, vid, true)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"saves_count": cnt, "is_saved": saved})
	}))

	mux.HandleFunc("DELETE /v1/videos/{id}/save", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		vid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		cnt, saved, status, err := feedSvc.SetSaveState(r.Context(), uid, vid, false)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"saves_count": cnt, "is_saved": saved})
	}))

	mux.HandleFunc("POST /v1/videos/{id}/share", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		vid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		var req struct {
			Channel string `json:"channel"`
		}
		_ = json.NewDecoder(http.MaxBytesReader(w, r.Body, 2048)).Decode(&req)
		cnt, status, err := feedSvc.RecordShare(r.Context(), uid, vid, req.Channel)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"shares_count": cnt})
	}))

	mux.HandleFunc("POST /v1/videos/{id}/repost", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		vid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		cnt, reposted, status, err := feedSvc.ToggleRepost(r.Context(), uid, vid, true)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"reposts_count": cnt, "is_reposted": reposted})
	}))

	mux.HandleFunc("DELETE /v1/videos/{id}/repost", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		vid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		cnt, reposted, status, err := feedSvc.ToggleRepost(r.Context(), uid, vid, false)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"reposts_count": cnt, "is_reposted": reposted})
	}))

	mux.HandleFunc("POST /v1/videos/{id}/not-interested", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		vid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		status, err := feedSvc.RecordNotInterested(r.Context(), uid, vid)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]bool{"ok": true})
	}))

	mux.HandleFunc("POST /v1/videos/{id}/report", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		vid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		var req struct {
			Reason  string `json:"reason"`
			Details string `json:"details"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8192)).Decode(&req); err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		status, err := feedSvc.SubmitReport(r.Context(), uid, vid, req.Reason, req.Details)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]bool{"reported": true})
	}))

	mux.HandleFunc("PATCH /v1/videos/{id}", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		vid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		var req struct {
			Title       *string `json:"title"`
			Description *string `json:"description"`
			Visibility  *string `json:"visibility"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16384)).Decode(&req); err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		res, status, err := feedSvc.UpdateOwnerVideo(r.Context(), uid, vid, req.Title, req.Description, req.Visibility)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, res)
	}))

	mux.HandleFunc("DELETE /v1/videos/{id}", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		vid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		status, err := feedSvc.DeleteOwnerVideo(r.Context(), uid, vid)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]bool{"deleted": true})
	}))

	mux.HandleFunc("POST /v1/users/{id}/block", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		tid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		status, err := feedSvc.SetBlockUser(r.Context(), uid, tid, true)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]bool{"blocked": true})
	}))

	mux.HandleFunc("DELETE /v1/users/{id}/block", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		tid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		status, err := feedSvc.SetBlockUser(r.Context(), uid, tid, false)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]bool{"blocked": false})
	}))

	mux.HandleFunc("POST /v1/users/{id}/mute", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		tid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		status, err := feedSvc.SetMuteUser(r.Context(), uid, tid, true)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]bool{"muted": true})
	}))

	mux.HandleFunc("DELETE /v1/users/{id}/mute", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		tid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		status, err := feedSvc.SetMuteUser(r.Context(), uid, tid, false)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]bool{"muted": false})
	}))

	mux.HandleFunc("GET /v1/me/saved-videos", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
		page, status, err := feedSvc.ListSavedVideos(r.Context(), uid, r.URL.Query().Get("cursor"), limit)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, page)
	}))

	mux.HandleFunc("GET /v1/me/safety", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		prefs, status, err := feedSvc.ListSafetyPreferences(r.Context(), uid)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, prefs)
	}))

	mux.HandleFunc("GET /v1/hashtags/{tag}/videos", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
		res, status, err := feedSvc.GetHashtagDiscovery(r.Context(), uid, r.PathValue("tag"), r.URL.Query().Get("cursor"), limit)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, res)
	}))

	mux.HandleFunc("GET /v1/audios/{id}/videos", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		aid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
		res, status, err := feedSvc.GetAudioDiscovery(r.Context(), uid, aid, r.URL.Query().Get("cursor"), limit)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, res)
	}))

	mux.HandleFunc("GET /v1/search", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
		res, status, err := feedSvc.SearchAll(r.Context(), uid, r.URL.Query().Get("q"), r.URL.Query().Get("cursor"), limit)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, res)
	}))

	mux.HandleFunc("DELETE /v1/search/history", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		status, err := feedSvc.DeleteSearchHistory(r.Context(), uid, "")
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]bool{"cleared": true})
	}))

	mux.HandleFunc("DELETE /v1/search/history/{id}", requireAuth(func(w http.ResponseWriter, r *http.Request, uid, _ uuid.UUID, _ string) {
		status, err := feedSvc.DeleteSearchHistory(r.Context(), uid, r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]bool{"deleted": true})
	}))

	// =========================================================================
	// ADMIN PANEL WEB APP RBAC, TEMPORARY PASSWORD ROTATION & APPROVAL QUEUE
	// =========================================================================

	mux.HandleFunc("GET /v1/admin/bootstrap/status", func(w http.ResponseWriter, r *http.Request) {
		initDone, err := adminSvc.IsInitialized(r.Context())
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusInternalServerError, err)
			return
		}
		middleware.WriteJSON(w, http.StatusOK, map[string]bool{"initialized": initDone})
	})

	mux.HandleFunc("POST /v1/admin/bootstrap", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Email    string `json:"email"`
			FullName string `json:"full_name"`
			Password string `json:"password"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16384)).Decode(&req); err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		principal, status, err := adminSvc.BootstrapSuperAdmin(r.Context(), req.Email, req.FullName, req.Password)
		if err != nil {
			middleware.WriteJSON(w, status, map[string]string{"error": err.Error()})
			return
		}
		middleware.WriteJSON(w, status, principal)
	})

	mux.HandleFunc("POST /v1/admin/auth/login", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Email    string `json:"email"`
			Password string `json:"password"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8192)).Decode(&req); err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		res, status := adminSvc.Login(r.Context(), req.Email, req.Password, clientIPFP(r), r.Header.Get("User-Agent"))
		middleware.WriteJSON(w, status, res)
	})

	requireAdminSession := func(allowPendingPasswordChange bool, next func(w http.ResponseWriter, r *http.Request, actor *admin.AdminPrincipal, rawToken string)) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			hdr := r.Header.Get("Authorization")
			if !strings.HasPrefix(hdr, "Bearer ") {
				middleware.WriteSanitizedError(w, http.StatusUnauthorized, nil)
				return
			}
			rawToken := strings.TrimPrefix(hdr, "Bearer ")
			actor, err := adminSvc.AuthenticateAdmin(r.Context(), rawToken)
			if err != nil {
				middleware.WriteSanitizedError(w, http.StatusUnauthorized, err)
				return
			}
			if !allowPendingPasswordChange && actor.MustChangePassword {
				middleware.WriteJSON(w, http.StatusForbidden, map[string]any{
					"error":                "Password change required before accessing admin dashboard.",
					"must_change_password": true,
				})
				return
			}
			next(w, r, actor, rawToken)
		}
	}

	mux.HandleFunc("GET /v1/admin/auth/me", requireAdminSession(true, func(w http.ResponseWriter, r *http.Request, actor *admin.AdminPrincipal, _ string) {
		middleware.WriteJSON(w, http.StatusOK, actor)
	}))

	mux.HandleFunc("POST /v1/admin/auth/change-password", requireAdminSession(true, func(w http.ResponseWriter, r *http.Request, actor *admin.AdminPrincipal, _ string) {
		var req struct {
			CurrentPassword string `json:"current_password"`
			NewPassword     string `json:"new_password"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8192)).Decode(&req); err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		status, err := adminSvc.ChangePassword(r.Context(), actor, req.CurrentPassword, req.NewPassword)
		if err != nil {
			middleware.WriteJSON(w, status, map[string]string{"error": err.Error()})
			return
		}
		middleware.WriteJSON(w, status, map[string]any{
			"changed":              true,
			"must_change_password": false,
		})
	}))

	mux.HandleFunc("POST /v1/admin/auth/logout", requireAdminSession(true, func(w http.ResponseWriter, r *http.Request, _ *admin.AdminPrincipal, rawToken string) {
		adminSvc.Logout(r.Context(), rawToken)
		middleware.WriteJSON(w, http.StatusOK, map[string]bool{"logged_out": true})
	}))

	mux.HandleFunc("GET /v1/admin/dashboard", requireAdminSession(false, func(w http.ResponseWriter, r *http.Request, actor *admin.AdminPrincipal, _ string) {
		stats, status, err := adminSvc.GetDashboard(r.Context(), actor)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, stats)
	}))

	mux.HandleFunc("GET /v1/admin/panel/users", requireAdminSession(false, func(w http.ResponseWriter, r *http.Request, actor *admin.AdminPrincipal, _ string) {
		items, status, err := adminSvc.ListUsers(r.Context(), actor, r.URL.Query().Get("q"))
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"users": items})
	}))

	mux.HandleFunc("POST /v1/admin/panel/users/{id}/suspend", requireAdminSession(false, func(w http.ResponseWriter, r *http.Request, actor *admin.AdminPrincipal, _ string) {
		uid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		var req struct {
			Suspended bool `json:"suspended"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&req); err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		status, err := adminSvc.SetUserSuspended(r.Context(), actor, uid, req.Suspended)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]bool{"suspended": req.Suspended})
	}))

	mux.HandleFunc("DELETE /v1/admin/panel/users/{id}", requireAdminSession(false, func(w http.ResponseWriter, r *http.Request, actor *admin.AdminPrincipal, _ string) {
		uid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		var req struct {
			Reason string `json:"reason"`
		}
		_ = json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&req)
		res, status, err := adminSvc.DeleteUserOrRequest(r.Context(), actor, uid, req.Reason)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, res)
	}))

	mux.HandleFunc("GET /v1/admin/panel/posts", requireAdminSession(false, func(w http.ResponseWriter, r *http.Request, actor *admin.AdminPrincipal, _ string) {
		items, status, err := adminSvc.ListPosts(r.Context(), actor, r.URL.Query().Get("q"))
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"posts": items})
	}))

	mux.HandleFunc("DELETE /v1/admin/panel/posts/{id}", requireAdminSession(false, func(w http.ResponseWriter, r *http.Request, actor *admin.AdminPrincipal, _ string) {
		pid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		status, err := adminSvc.RemovePost(r.Context(), actor, pid)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]bool{"removed": true})
	}))

	mux.HandleFunc("GET /v1/admin/panel/approvals", requireAdminSession(false, func(w http.ResponseWriter, r *http.Request, actor *admin.AdminPrincipal, _ string) {
		items, status, err := adminSvc.ListApprovals(r.Context(), actor)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"approvals": items})
	}))

	mux.HandleFunc("POST /v1/admin/panel/approvals/{id}/decide", requireAdminSession(false, func(w http.ResponseWriter, r *http.Request, actor *admin.AdminPrincipal, _ string) {
		reqID, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		var req struct {
			Approve bool   `json:"approve"`
			Note    string `json:"note"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&req); err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		status, err := adminSvc.DecideApproval(r.Context(), actor, reqID, req.Approve, req.Note)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]bool{"decided": true, "approved": req.Approve})
	}))

	mux.HandleFunc("GET /v1/admin/panel/staff", requireAdminSession(false, func(w http.ResponseWriter, r *http.Request, actor *admin.AdminPrincipal, _ string) {
		items, status, err := adminSvc.ListTeam(r.Context(), actor)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"staff": items})
	}))

	mux.HandleFunc("POST /v1/admin/panel/staff", requireAdminSession(false, func(w http.ResponseWriter, r *http.Request, actor *admin.AdminPrincipal, _ string) {
		var req struct {
			Email       string   `json:"email"`
			FullName    string   `json:"full_name"`
			Role        string   `json:"role"`
			Password    string   `json:"password"`
			IsTemporary bool     `json:"is_temporary"`
			Permissions []string `json:"permissions"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16384)).Decode(&req); err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		item, status, err := adminSvc.CreateStaffMember(r.Context(), actor, req.Email, req.FullName, req.Role, req.Password, req.IsTemporary, req.Permissions)
		if err != nil {
			middleware.WriteJSON(w, status, map[string]string{"error": err.Error()})
			return
		}
		middleware.WriteJSON(w, status, item)
	}))

	mux.HandleFunc("PATCH /v1/admin/panel/staff/{id}/role", requireAdminSession(false, func(w http.ResponseWriter, r *http.Request, actor *admin.AdminPrincipal, _ string) {
		sid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		var req struct {
			Role        string   `json:"role"`
			Permissions []string `json:"permissions"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8192)).Decode(&req); err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		status, err := adminSvc.UpdateStaffRole(r.Context(), actor, sid, req.Role, req.Permissions)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]bool{"updated": true})
	}))

	mux.HandleFunc("POST /v1/admin/panel/staff/{id}/pause", requireAdminSession(false, func(w http.ResponseWriter, r *http.Request, actor *admin.AdminPrincipal, _ string) {
		sid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		var req struct {
			Paused bool `json:"paused"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&req); err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		status, err := adminSvc.SetStaffPaused(r.Context(), actor, sid, req.Paused)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]bool{"paused": req.Paused})
	}))

	mux.HandleFunc("DELETE /v1/admin/panel/staff/{id}", requireAdminSession(false, func(w http.ResponseWriter, r *http.Request, actor *admin.AdminPrincipal, _ string) {
		sid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		status, err := adminSvc.RemoveStaffMember(r.Context(), actor, sid)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]bool{"removed": true})
	}))

	mux.HandleFunc("GET /v1/admin/panel/logs", requireAdminSession(false, func(w http.ResponseWriter, r *http.Request, actor *admin.AdminPrincipal, _ string) {
		limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
		items, status, err := adminSvc.ListActivityLogs(r.Context(), actor, limit)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"logs": items})
	}))

	// Service-to-service Admin RLS-Bypass Routes (X-Telefam-Admin-Key verified against TELEFAM_ADMIN_API_KEY)
	requireAdminKey := func(next http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			if !postsSvc.VerifyAdminKey(r.Header.Get("X-Telefam-Admin-Key")) {
				middleware.WriteSanitizedError(w, http.StatusForbidden, nil)
				return
			}
			next(w, r)
		}
	}

	mux.HandleFunc("GET /v1/admin/users", requireAdminKey(func(w http.ResponseWriter, r *http.Request) {
		users, status, err := postsSvc.AdminListAllUsers(r.Context())
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"users": users})
	}))

	mux.HandleFunc("POST /v1/admin/users", requireAdminKey(func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Email       string `json:"email"`
			DisplayName string `json:"display_name"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8192)).Decode(&req); err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		user, status, err := postsSvc.AdminAddUser(r.Context(), req.Email, req.DisplayName)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, user)
	}))

	mux.HandleFunc("DELETE /v1/admin/users/{id}", requireAdminKey(func(w http.ResponseWriter, r *http.Request) {
		uid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		status, err := postsSvc.AdminRemoveUser(r.Context(), uid)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]bool{"removed": true})
	}))

	mux.HandleFunc("DELETE /v1/admin/videos/{id}", requireAdminKey(func(w http.ResponseWriter, r *http.Request) {
		mid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		status, err := postsSvc.AdminRemoveVideo(r.Context(), mid)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]bool{"removed": true})
	}))

	mux.HandleFunc("POST /v1/admin/videos/{id}/sanitize", requireAdminKey(func(w http.ResponseWriter, r *http.Request) {
		mid, err := uuid.Parse(r.PathValue("id"))
		if err != nil {
			middleware.WriteSanitizedError(w, http.StatusBadRequest, err)
			return
		}
		res, status, err := postsSvc.AdminSanitizeVideo(r.Context(), mid)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, res)
	}))

	srv := &http.Server{
		Addr:              cfg.ListenAddr,
		Handler:           middleware.CORS(cfg.AdminAllowedOrigins, cfg.Env, mux),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       120 * time.Second,
		WriteTimeout:      120 * time.Second,
	}

	certFile := os.Getenv("TLS_CERT_FILE")
	keyFile := os.Getenv("TLS_KEY_FILE")
	if certFile != "" && keyFile != "" {
		log.Printf("Telefam Go Gateway TLS listening on %s", cfg.ListenAddr)
		log.Fatal(srv.ListenAndServeTLS(certFile, keyFile))
	}
	log.Printf("Telefam Go Gateway listening on %s", cfg.ListenAddr)
	log.Fatal(srv.ListenAndServe())
}
