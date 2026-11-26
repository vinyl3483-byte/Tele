package config

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"net"
	"os"
	"strings"
)

type Config struct {
	Env                 string
	ListenAddr          string
	DatabaseURL         string
	JWTSecret           []byte
	MasterKey           [32]byte
	HMACPepper          []byte
	AdminAPIKey         string
	SuperAdminEmail     string
	SuperAdminPassword  string
	AdminAllowedOrigins []string
	TrustedProxies      []*net.IPNet
	MediaStorageDir     string
	ITunesSearchURL     string
	DeezerSearchURL     string
	GoogleClientID      string
	AppleBundleID       string
	ErlangRouterURL     string
	MagicLinkBaseURL    string
	SMTPHost            string
	SMTPPort            string
	SMTPUser            string
	SMTPPass            string
	SMTPFrom            string
}

func isPlaceholder(val string) bool {
	upper := strings.ToUpper(strings.TrimSpace(val))
	return upper == "" || strings.Contains(upper, "CHANGE_ME")
}

func Load() (*Config, error) {
	env := strings.ToLower(strings.TrimSpace(os.Getenv("TELEFAM_ENV")))
	if env == "" {
		env = "development"
	}
	isProd := env == "production" || env == "prod"

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		return nil, errors.New("DATABASE_URL is required")
	}

	rawJWT := os.Getenv("TELEFAM_JWT_SECRET")
	if isProd && (len(rawJWT) < 32 || isPlaceholder(rawJWT)) {
		return nil, errors.New("TELEFAM_JWT_SECRET must be at least 32 non-placeholder bytes in production")
	}
	jwtSecret := []byte(rawJWT)
	if len(jwtSecret) < 32 {
		jwtSecret = make([]byte, 32)
		if _, err := rand.Read(jwtSecret); err != nil {
			return nil, err
		}
	}

	var masterKey [32]byte
	mkHex := strings.TrimSpace(os.Getenv("TELEFAM_MASTER_KEY_HEX"))
	if len(mkHex) == 64 {
		decoded, err := hex.DecodeString(mkHex)
		if err != nil || len(decoded) != 32 {
			return nil, errors.New("invalid TELEFAM_MASTER_KEY_HEX")
		}
		allZero := true
		for _, b := range decoded {
			if b != 0 {
				allZero = false
				break
			}
		}
		if isProd && allZero {
			return nil, errors.New("TELEFAM_MASTER_KEY_HEX cannot be all zeros in production")
		}
		copy(masterKey[:], decoded)
	} else {
		if isProd {
			return nil, errors.New("TELEFAM_MASTER_KEY_HEX (64 hex chars) is required in production")
		}
		if _, err := rand.Read(masterKey[:]); err != nil {
			return nil, err
		}
	}

	rawPepper := os.Getenv("TELEFAM_HMAC_PEPPER")
	if isProd && (len(rawPepper) < 16 || isPlaceholder(rawPepper)) {
		return nil, errors.New("TELEFAM_HMAC_PEPPER must be at least 16 non-placeholder bytes in production")
	}
	pepper := []byte(rawPepper)
	if len(pepper) < 16 {
		pepper = make([]byte, 32)
		if _, err := rand.Read(pepper); err != nil {
			return nil, err
		}
	}

	adminAPIKey := strings.TrimSpace(os.Getenv("TELEFAM_ADMIN_API_KEY"))
	if isProd && adminAPIKey != "" && (len(adminAPIKey) < 24 || isPlaceholder(adminAPIKey)) {
		return nil, errors.New("TELEFAM_ADMIN_API_KEY must not be a placeholder and must be >= 24 chars in production")
	}

	var trustedProxies []*net.IPNet
	for _, entry := range strings.Split(os.Getenv("TELEFAM_TRUSTED_PROXIES"), ",") {
		cidr := strings.TrimSpace(entry)
		if cidr == "" {
			continue
		}
		if !strings.Contains(cidr, "/") {
			if ip := net.ParseIP(cidr); ip != nil {
				if ip.To4() != nil {
					cidr += "/32"
				} else {
					cidr += "/128"
				}
			}
		}
		if _, network, err := net.ParseCIDR(cidr); err == nil {
			trustedProxies = append(trustedProxies, network)
		}
	}

	var allowedOrigins []string
	for _, origin := range strings.Split(os.Getenv("TELEFAM_ADMIN_ALLOWED_ORIGINS"), ",") {
		trimmed := strings.TrimRight(strings.TrimSpace(origin), "/")
		if trimmed != "" {
			allowedOrigins = append(allowedOrigins, trimmed)
		}
	}

	googleClientID := strings.TrimSpace(os.Getenv("GOOGLE_CLIENT_ID"))
	appleBundleID := strings.TrimSpace(os.Getenv("APPLE_BUNDLE_ID"))
	if isProd && (googleClientID == "" || appleBundleID == "") {
		return nil, errors.New("GOOGLE_CLIENT_ID and APPLE_BUNDLE_ID must be configured in production")
	}

	addr := os.Getenv("TELEFAM_LISTEN_ADDR")
	if addr == "" {
		port := os.Getenv("PORT")
		if port == "" {
			port = "8080"
		}
		addr = ":" + port
	}

	magicBase := os.Getenv("TELEFAM_MAGIC_LINK_BASE")
	if magicBase == "" {
		magicBase = "https://telefam.app/verify"
	}

	mediaDir := os.Getenv("TELEFAM_MEDIA_DIR")
	if mediaDir == "" {
		mediaDir = "/tmp/telefam_media"
	}

	itunesURL := os.Getenv("ITUNES_SEARCH_URL")
	if itunesURL == "" {
		itunesURL = "https://itunes.apple.com/search"
	}

	deezerURL := os.Getenv("DEEZER_SEARCH_URL")
	if deezerURL == "" {
		deezerURL = "https://api.deezer.com/search"
	}

	return &Config{
		Env:                 env,
		ListenAddr:          addr,
		DatabaseURL:         dbURL,
		JWTSecret:           jwtSecret,
		MasterKey:           masterKey,
		HMACPepper:          pepper,
		AdminAPIKey:         adminAPIKey,
		SuperAdminEmail:     strings.ToLower(strings.TrimSpace(os.Getenv("TELEFAM_SUPER_ADMIN_EMAIL"))),
		SuperAdminPassword:  os.Getenv("TELEFAM_SUPER_ADMIN_PASSWORD"),
		AdminAllowedOrigins: allowedOrigins,
		TrustedProxies:      trustedProxies,
		MediaStorageDir:     mediaDir,
		ITunesSearchURL:     itunesURL,
		DeezerSearchURL:     deezerURL,
		GoogleClientID:      googleClientID,
		AppleBundleID:       appleBundleID,
		ErlangRouterURL:     os.Getenv("ERLANG_ROUTER_URL"),
		MagicLinkBaseURL:    magicBase,
		SMTPHost:            os.Getenv("SMTP_HOST"),
		SMTPPort:            os.Getenv("SMTP_PORT"),
		SMTPUser:            os.Getenv("SMTP_USER"),
		SMTPPass:            os.Getenv("SMTP_PASS"),
		SMTPFrom:            os.Getenv("SMTP_FROM"),
	}, nil
}
