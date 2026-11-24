package config

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"os"
)

type Config struct {
	ListenAddr       string
	DatabaseURL      string
	JWTSecret        []byte
	MasterKey        [32]byte
	HMACPepper       []byte
	AdminAPIKey      string
	MediaStorageDir  string
	ITunesSearchURL  string
	DeezerSearchURL  string
	GoogleClientID   string
	AppleBundleID    string
	ErlangRouterURL  string
	MagicLinkBaseURL string
	SMTPHost         string
	SMTPPort         string
	SMTPUser         string
	SMTPPass         string
	SMTPFrom         string
}

func Load() (*Config, error) {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		return nil, errors.New("DATABASE_URL is required")
	}

	jwtSecret := []byte(os.Getenv("TELEFAM_JWT_SECRET"))
	if len(jwtSecret) < 32 {
		jwtSecret = make([]byte, 32)
		if _, err := rand.Read(jwtSecret); err != nil {
			return nil, err
		}
	}

	var masterKey [32]byte
	if mkHex := os.Getenv("TELEFAM_MASTER_KEY_HEX"); len(mkHex) == 64 {
		decoded, err := hex.DecodeString(mkHex)
		if err != nil || len(decoded) != 32 {
			return nil, errors.New("invalid TELEFAM_MASTER_KEY_HEX")
		}
		copy(masterKey[:], decoded)
	} else {
		if _, err := rand.Read(masterKey[:]); err != nil {
			return nil, err
		}
	}

	pepper := []byte(os.Getenv("TELEFAM_HMAC_PEPPER"))
	if len(pepper) < 16 {
		pepper = make([]byte, 32)
		if _, err := rand.Read(pepper); err != nil {
			return nil, err
		}
	}

	addr := os.Getenv("TELEFAM_LISTEN_ADDR")
	if addr == "" {
		addr = ":8080"
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
		ListenAddr:       addr,
		DatabaseURL:      dbURL,
		JWTSecret:        jwtSecret,
		MasterKey:        masterKey,
		HMACPepper:       pepper,
		AdminAPIKey:      os.Getenv("TELEFAM_ADMIN_API_KEY"),
		MediaStorageDir:  mediaDir,
		ITunesSearchURL:  itunesURL,
		DeezerSearchURL:  deezerURL,
		GoogleClientID:   os.Getenv("GOOGLE_CLIENT_ID"),
		AppleBundleID:    os.Getenv("APPLE_BUNDLE_ID"),
		ErlangRouterURL:  os.Getenv("ERLANG_ROUTER_URL"),
		MagicLinkBaseURL: magicBase,
		SMTPHost:         os.Getenv("SMTP_HOST"),
		SMTPPort:         os.Getenv("SMTP_PORT"),
		SMTPUser:         os.Getenv("SMTP_USER"),
		SMTPPass:         os.Getenv("SMTP_PASS"),
		SMTPFrom:         os.Getenv("SMTP_FROM"),
	}, nil
}
