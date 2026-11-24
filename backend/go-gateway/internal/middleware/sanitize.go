package middleware

import (
	"encoding/json"
	"log"
	"net/http"
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
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
}
