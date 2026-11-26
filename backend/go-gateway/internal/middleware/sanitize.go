package middleware

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"
)

type SanitizedErrorResponse struct {
	Error string `json:"error"`
}

func WriteSanitizedError(w http.ResponseWriter, statusCode int, internalErr error) {
	if internalErr != nil {
		log.Printf("[sanitized] status=%d err=%v", statusCode, internalErr)
	}
	SetSecurityHeaders(w)
	w.WriteHeader(statusCode)
	_ = json.NewEncoder(w).Encode(SanitizedErrorResponse{
		Error: "Error has occurred, try again later.",
	})
}

func WriteJSON(w http.ResponseWriter, statusCode int, payload any) {
	SetSecurityHeaders(w)
	w.WriteHeader(statusCode)
	_ = json.NewEncoder(w).Encode(payload)
}

func SetSecurityHeaders(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("X-Frame-Options", "DENY")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
}

func CORS(allowedOrigins []string, env string, next http.Handler) http.Handler {
	allowMap := make(map[string]struct{}, len(allowedOrigins))
	for _, o := range allowedOrigins {
		cleaned := strings.TrimRight(strings.TrimSpace(o), "/")
		if cleaned != "" {
			allowMap[cleaned] = struct{}{}
		}
	}
	isDev := env != "production" && env != "prod"

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := strings.TrimRight(strings.TrimSpace(r.Header.Get("Origin")), "/")
		if origin != "" {
			_, ok := allowMap[origin]
			if !ok && isDev && (strings.HasPrefix(origin, "http://localhost:") || strings.HasPrefix(origin, "http://127.0.0.1:")) {
				ok = true
			}
			if ok {
				w.Header().Set("Vary", "Origin")
				w.Header().Set("Access-Control-Allow-Origin", origin)
				w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
				w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Telefam-Admin-Key, X-Telefam-Device-FP, X-Telefam-Device-Platform")
				w.Header().Set("Access-Control-Max-Age", "600")
			} else if r.Method == http.MethodOptions {
				SetSecurityHeaders(w)
				w.WriteHeader(http.StatusForbidden)
				return
			}
		}
		if r.Method == http.MethodOptions {
			SetSecurityHeaders(w)
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
