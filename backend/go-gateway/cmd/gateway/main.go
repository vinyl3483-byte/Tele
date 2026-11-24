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
	"github.com/telefam/company/backend/go-gateway/internal/auth"
	"github.com/telefam/company/backend/go-gateway/internal/chat"
	"github.com/telefam/company/backend/go-gateway/internal/config"
	"github.com/telefam/company/backend/go-gateway/internal/contacts"
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

	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		healthCtx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()
		if err := pool.Ping(healthCtx); err != nil {
			middleware.WriteJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "unavailable"})
			return
		}
		middleware.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

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
		ipFP := security.ComputeIPFingerprint(cfg.HMACPepper, security.ExtractClientIP(r))
		res, status, err := authSvc.SendOTP(r.Context(), req.Email, req.DeviceFingerprint, ipFP, req.HardwareAttestation, req.DeviceName, req.Platform)
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
		ipFP := security.ComputeIPFingerprint(cfg.HMACPepper, security.ExtractClientIP(r))
		res, status, err := authSvc.VerifyOTPOrMagicLink(r.Context(), req.Email, req.OTP, req.MagicToken, req.DeviceFingerprint, ipFP, req.HardwareAttestation, req.DeviceName, req.Platform)
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
		ipFP := security.ComputeIPFingerprint(cfg.HMACPepper, security.ExtractClientIP(r))
		res, status, err := authSvc.VerifyOAuth(r.Context(), provider, req.IDToken, req.DeviceFingerprint, ipFP, req.HardwareAttestation, req.DeviceName, req.Platform)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, res)
	})

	requireAuth := func(next func(w http.ResponseWriter, r *http.Request, userID uuid.UUID, devFP string)) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			hdr := r.Header.Get("Authorization")
			if !strings.HasPrefix(hdr, "Bearer ") {
				middleware.WriteSanitizedError(w, http.StatusUnauthorized, nil)
				return
			}
			uid, devFP, err := authSvc.ParseAccessToken(strings.TrimPrefix(hdr, "Bearer "))
			if err != nil {
				middleware.WriteSanitizedError(w, http.StatusUnauthorized, err)
				return
			}
			ipFP := security.ComputeIPFingerprint(cfg.HMACPepper, security.ExtractClientIP(r))
			if !limiter.AllowAuthenticatedAPI(r.Context(), uid.String(), devFP, ipFP) {
				middleware.WriteSanitizedError(w, http.StatusTooManyRequests, nil)
				return
			}
			next(w, r, uid, devFP)
		}
	}

	mux.HandleFunc("POST /v1/profile/avatar", requireAuth(func(w http.ResponseWriter, r *http.Request, uid uuid.UUID, _ string) {
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

	mux.HandleFunc("POST /v1/profile/setup", requireAuth(func(w http.ResponseWriter, r *http.Request, uid uuid.UUID, _ string) {
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

	mux.HandleFunc("GET /v1/contacts", requireAuth(func(w http.ResponseWriter, r *http.Request, uid uuid.UUID, _ string) {
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

	mux.HandleFunc("POST /v1/contacts/follow", requireAuth(func(w http.ResponseWriter, r *http.Request, uid uuid.UUID, devFP string) {
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
		ipFP := security.ComputeIPFingerprint(cfg.HMACPepper, security.ExtractClientIP(r))
		res, status, err := contactsSvc.SetFollowState(r.Context(), uid, targetID, req.Follow, devFP, ipFP)
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

	mux.HandleFunc("GET /v1/conversations", requireAuth(func(w http.ResponseWriter, r *http.Request, uid uuid.UUID, _ string) {
		items, status, err := chatSvc.ListConversations(r.Context(), uid)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"conversations": items})
	}))

	mux.HandleFunc("POST /v1/conversations", requireAuth(func(w http.ResponseWriter, r *http.Request, uid uuid.UUID, _ string) {
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

	mux.HandleFunc("GET /v1/conversations/{id}/messages", requireAuth(func(w http.ResponseWriter, r *http.Request, uid uuid.UUID, _ string) {
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

	mux.HandleFunc("POST /v1/sync/mutations", requireAuth(func(w http.ResponseWriter, r *http.Request, uid uuid.UUID, devFP string) {
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

	// Public Song Search & Hashtags Search
	mux.HandleFunc("GET /v1/music/search", requireAuth(func(w http.ResponseWriter, r *http.Request, _ uuid.UUID, _ string) {
		q := r.URL.Query().Get("q")
		tracks, status, err := postsSvc.SearchPublicSongs(r.Context(), q)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"tracks": tracks})
	}))

	mux.HandleFunc("GET /v1/hashtags/search", requireAuth(func(w http.ResponseWriter, r *http.Request, uid uuid.UUID, _ string) {
		q := r.URL.Query().Get("q")
		items, status, err := postsSvc.SearchHashtags(r.Context(), uid, q)
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"hashtags": items})
	}))

	// Post Photos Upload (up to 10 photos, decoded/re-encoded/renamed/fingerprinted server-side)
	mux.HandleFunc("POST /v1/posts/media/photos", requireAuth(func(w http.ResponseWriter, r *http.Request, uid uuid.UUID, _ string) {
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

	// Post Video Upload (up to 200 MB, sanitized, trimmed, audio-merged, multi-quality & frame-fingerprinted)
	mux.HandleFunc("POST /v1/posts/media/video", requireAuth(func(w http.ResponseWriter, r *http.Request, uid uuid.UUID, _ string) {
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

	mux.HandleFunc("POST /v1/posts", requireAuth(func(w http.ResponseWriter, r *http.Request, uid uuid.UUID, _ string) {
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

	// Admin RLS-Bypass Routes (X-Telefam-Admin-Key verified against TELEFAM_ADMIN_API_KEY env var)
	requireAdmin := func(next http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			if !postsSvc.VerifyAdminKey(r.Header.Get("X-Telefam-Admin-Key")) {
				middleware.WriteSanitizedError(w, http.StatusForbidden, nil)
				return
			}
			next(w, r)
		}
	}

	mux.HandleFunc("GET /v1/admin/users", requireAdmin(func(w http.ResponseWriter, r *http.Request) {
		users, status, err := postsSvc.AdminListAllUsers(r.Context())
		if err != nil {
			middleware.WriteSanitizedError(w, status, err)
			return
		}
		middleware.WriteJSON(w, status, map[string]any{"users": users})
	}))

	mux.HandleFunc("POST /v1/admin/users", requireAdmin(func(w http.ResponseWriter, r *http.Request) {
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

	mux.HandleFunc("DELETE /v1/admin/users/{id}", requireAdmin(func(w http.ResponseWriter, r *http.Request) {
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

	mux.HandleFunc("DELETE /v1/admin/videos/{id}", requireAdmin(func(w http.ResponseWriter, r *http.Request) {
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

	mux.HandleFunc("POST /v1/admin/videos/{id}/sanitize", requireAdmin(func(w http.ResponseWriter, r *http.Request) {
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
		Handler:           mux,
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
