package media

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const (
	MaxVideoUploadBytes = 200 * 1024 * 1024 // 200 MB
	VideoProcessTimeout = 90 * time.Second
)

type VideoQualityRendition struct {
	Label     string `json:"label"`
	Width     int    `json:"width"`
	Height    int    `json:"height"`
	Bitrate   string `json:"bitrate"`
	ObjectKey string `json:"object_key"`
	ByteSize  int64  `json:"byte_size"`
}

type FrameFingerprintRecord struct {
	StreamKind      string `json:"stream_kind"` // video_frame | audio_frame | image
	FrameIndex      int    `json:"frame_index"`
	TimestampMs     int64  `json:"timestamp_ms"`
	PerceptualDHash string `json:"perceptual_dhash"`
	Sha256Hex       string `json:"sha256_hash"`
}

type VideoSanitizeOptions struct {
	TrimStartMs         int64
	TrimEndMs           int64
	ThumbnailAtMs       int64
	MuteOriginalAudio   bool
	SongPreviewURL      string
	ExplicitThumbJPEG   []byte
	MediaStorageBaseDir string
	RenamedVideoFile    string
	RenamedThumbFile    string
}

type SanitizedVideoResult struct {
	RenamedVideoFilename string
	PrimaryObjectKey     string
	ThumbnailObjectKey   string
	ThumbnailFingerprint string
	MimeType             string
	ByteSize             int64
	Width                int
	Height               int
	DurationMs           int64
	AudioFingerprintHash string
	ContentID            string
	Qualities            []VideoQualityRendition
	FrameFingerprints    []FrameFingerprintRecord
}

func ConfineStoragePath(baseDir string, relParts ...string) (string, error) {
	absBase, err := filepath.Abs(baseDir)
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(absBase, 0o750); err != nil {
		return "", err
	}
	joined := filepath.Join(append([]string{absBase}, relParts...)...)
	absTarget, err := filepath.Abs(joined)
	if err != nil {
		return "", err
	}
	if !strings.HasPrefix(absTarget, absBase+string(filepath.Separator)) && absTarget != absBase {
		return "", errors.New("path traversal blocked")
	}
	return absTarget, nil
}

func ValidateVideoContainerMagic(header []byte) (string, bool) {
	if len(header) < 12 {
		return "", false
	}
	// ISO Base Media File Format (MP4 / QuickTime MOV): box size + 'ftyp'
	if string(header[4:8]) == "ftyp" {
		return "video/mp4", true
	}
	// Matroska / WebM EBML header
	if header[0] == 0x1A && header[1] == 0x45 && header[2] == 0xDF && header[3] == 0xA3 {
		return "video/webm", true
	}
	return "", false
}

func SanitizeVideoInIsolation(ctx context.Context, rawVideoPath string, rawSize int64, pepper []byte, opts VideoSanitizeOptions) (*SanitizedVideoResult, error) {
	if rawSize <= 0 || rawSize > MaxVideoUploadBytes {
		return nil, errors.New("video size exceeds 200 MB limit")
	}

	f, err := os.Open(rawVideoPath)
	if err != nil {
		return nil, err
	}
	hdr := make([]byte, 32)
	n, _ := io.ReadFull(f, hdr)
	_ = f.Close()
	if _, ok := ValidateVideoContainerMagic(hdr[:n]); !ok {
		return nil, errors.New("unsupported video container")
	}

	procCtx, cancel := context.WithTimeout(ctx, VideoProcessTimeout)
	defer cancel()

	outPrimary, err := ConfineStoragePath(opts.MediaStorageBaseDir, "videos", opts.RenamedVideoFile)
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(filepath.Dir(outPrimary), 0o750); err != nil {
		return nil, err
	}
	outThumb, err := ConfineStoragePath(opts.MediaStorageBaseDir, "thumbs", opts.RenamedThumbFile)
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(filepath.Dir(outThumb), 0o750); err != nil {
		return nil, err
	}

	ffmpegPath, ffErr := exec.LookPath("ffmpeg")
	ffprobePath, fpErr := exec.LookPath("ffprobe")

	var width, height int
	var durationMs int64
	if fpErr == nil {
		width, height, durationMs = probeVideoMetadata(procCtx, ffprobePath, rawVideoPath)
	}
	if width <= 0 {
		width = 1280
	}
	if height <= 0 {
		height = 720
	}
	if durationMs <= 0 {
		durationMs = 15000
	}

	var songPath string
	if opts.SongPreviewURL != "" {
		if sp, dlErr := downloadAllowlistedSongPreview(procCtx, opts.SongPreviewURL); dlErr == nil {
			songPath = sp
			defer func() { _ = os.Remove(sp) }()
		}
	}

	qualities := []VideoQualityRendition{}
	if ffErr == nil {
		// Primary re-encoded clean H.264/AAC MP4 (strips metadata, applies trim, mutes/merges audio)
		if err := transcodeCleanMP4(procCtx, ffmpegPath, rawVideoPath, outPrimary, songPath, opts, 1080); err != nil {
			// Fallback copy-repack without shell
			_ = copyFileSafe(rawVideoPath, outPrimary)
		}

		// Adaptive quality ladder (1080p, 720p, 480p, 360p) capped at source height
		for _, spec := range []struct {
			label   string
			height  int
			bitrate string
		}{
			{"1080p", 1080, "4500k"},
			{"720p", 720, "2400k"},
			{"480p", 480, "1200k"},
			{"360p", 360, "700k"},
		} {
			if height < spec.height && spec.height > 480 {
				continue
			}
			rendName := strings.TrimSuffix(opts.RenamedVideoFile, ".mp4") + "_" + spec.label + ".mp4"
			rendPath, pErr := ConfineStoragePath(opts.MediaStorageBaseDir, "videos", rendName)
			if pErr != nil {
				continue
			}
			if spec.label == "720p" && height <= 720 {
				_ = copyFileSafe(outPrimary, rendPath)
			} else if err := transcodeCleanMP4(procCtx, ffmpegPath, outPrimary, rendPath, "", VideoSanitizeOptions{MuteOriginalAudio: opts.MuteOriginalAudio}, spec.height); err != nil {
				continue
			}
			if info, stErr := os.Stat(rendPath); stErr == nil {
				scaledW := (width * spec.height) / height
				if scaledW%2 == 1 {
					scaledW++
				}
				qualities = append(qualities, VideoQualityRendition{
					Label:     spec.label,
					Width:     scaledW,
					Height:    spec.height,
					Bitrate:   spec.bitrate,
					ObjectKey: "videos/" + rendName,
					ByteSize:  info.Size(),
				})
			}
		}
	} else {
		if err := copyFileSafe(rawVideoPath, outPrimary); err != nil {
			return nil, err
		}
		if info, stErr := os.Stat(outPrimary); stErr == nil {
			qualities = append(qualities, VideoQualityRendition{
				Label:     "720p",
				Width:     width,
				Height:    height,
				Bitrate:   "2400k",
				ObjectKey: "videos/" + opts.RenamedVideoFile,
				ByteSize:  info.Size(),
			})
		}
	}

	// Sanitize or extract thumbnail frame
	thumbFP, err := sanitizeOrExtractThumbnail(procCtx, ffmpegPath, ffErr == nil, outPrimary, outThumb, durationMs, opts, pepper)
	if err != nil {
		return nil, err
	}

	// Compute per-frame video + audio fingerprints + composite deterministic Content ID
	frames, audioFP := computeVideoAndAudioFrameFingerprints(procCtx, ffmpegPath, ffErr == nil, outPrimary, durationMs, pepper)

	var frameCsvBuilder strings.Builder
	for i, fr := range frames {
		if fr.StreamKind == "video_frame" {
			if frameCsvBuilder.Len() > 0 {
				frameCsvBuilder.WriteByte(',')
			}
			frameCsvBuilder.WriteString(fr.PerceptualDHash)
			if i > 240 {
				break
			}
		}
	}

	mac := hmac.New(sha256.New, pepper)
	mac.Write([]byte("video|"))
	mac.Write([]byte(strconv.Itoa(width)))
	mac.Write([]byte("x"))
	mac.Write([]byte(strconv.Itoa(height)))
	mac.Write([]byte("|dur="))
	mac.Write([]byte(strconv.FormatInt(durationMs, 10)))
	mac.Write([]byte("|frames="))
	mac.Write([]byte(frameCsvBuilder.String()))
	mac.Write([]byte("|audio="))
	mac.Write([]byte(audioFP))
	contentID := hex.EncodeToString(mac.Sum(nil))

	finalInfo, err := os.Stat(outPrimary)
	if err != nil {
		return nil, err
	}

	return &SanitizedVideoResult{
		RenamedVideoFilename: opts.RenamedVideoFile,
		PrimaryObjectKey:     "videos/" + opts.RenamedVideoFile,
		ThumbnailObjectKey:   "thumbs/" + opts.RenamedThumbFile,
		ThumbnailFingerprint: thumbFP,
		MimeType:             "video/mp4",
		ByteSize:             finalInfo.Size(),
		Width:                width,
		Height:               height,
		DurationMs:           durationMs,
		AudioFingerprintHash: audioFP,
		ContentID:            contentID,
		Qualities:            qualities,
		FrameFingerprints:    frames,
	}, nil
}

func probeVideoMetadata(ctx context.Context, ffprobeBin, filePath string) (int, int, int64) {
	cmd := exec.CommandContext(ctx, ffprobeBin,
		"-v", "quiet",
		"-print_format", "json",
		"-show_streams",
		"-show_format",
		filePath,
	)
	out, err := cmd.Output()
	if err != nil {
		return 0, 0, 0
	}
	var parsed struct {
		Streams []struct {
			CodecType string `json:"codec_type"`
			Width     int    `json:"width"`
			Height    int    `json:"height"`
		} `json:"streams"`
		Format struct {
			Duration string `json:"duration"`
		} `json:"format"`
	}
	if json.Unmarshal(out, &parsed) != nil {
		return 0, 0, 0
	}
	var w, h int
	for _, s := range parsed.Streams {
		if s.CodecType == "video" && s.Width > 0 && s.Height > 0 {
			w, h = s.Width, s.Height
			break
		}
	}
	var durMs int64
	if secs, err := strconv.ParseFloat(strings.TrimSpace(parsed.Format.Duration), 64); err == nil && secs > 0 {
		durMs = int64(secs * 1000.0)
	}
	return w, h, durMs
}

func transcodeCleanMP4(
	ctx context.Context,
	ffmpegBin string,
	inputPath string,
	outputPath string,
	songPath string,
	opts VideoSanitizeOptions,
	targetHeight int,
) error {
	args := []string{"-y", "-hide_banner", "-loglevel", "error"}
	if opts.TrimStartMs > 0 {
		args = append(args, "-ss", fmt.Sprintf("%.3f", float64(opts.TrimStartMs)/1000.0))
	}
	if opts.TrimEndMs > opts.TrimStartMs && opts.TrimEndMs > 0 {
		args = append(args, "-to", fmt.Sprintf("%.3f", float64(opts.TrimEndMs)/1000.0))
	}
	args = append(args, "-i", inputPath)
	if songPath != "" {
		args = append(args, "-stream_loop", "-1", "-i", songPath)
	}

	scaleExpr := fmt.Sprintf("scale=-2:'min(%d,ih)'", targetHeight)
	args = append(args,
		"-map_metadata", "-1",
		"-vf", scaleExpr,
		"-c:v", "libx264",
		"-preset", "veryfast",
		"-crf", "24",
		"-pix_fmt", "yuv420p",
	)

	if opts.MuteOriginalAudio && songPath == "" {
		args = append(args, "-an")
	} else if songPath != "" && opts.MuteOriginalAudio {
		args = append(args, "-map", "0:v:0", "-map", "1:a:0", "-c:a", "aac", "-b:a", "128k", "-shortest")
	} else if songPath != "" {
		// Decode original audio and added song track, resample & merge cleanly
		args = append(args,
			"-filter_complex", "[0:a?]aresample=44100[a0];[1:a]aresample=44100[a1];[a0][a1]amix=inputs=2:duration=first:dropout_transition=2[aout]",
			"-map", "0:v:0",
			"-map", "[aout]",
			"-c:a", "aac",
			"-b:a", "128k",
			"-shortest",
		)
	} else {
		args = append(args, "-c:a", "aac", "-b:a", "128k")
	}

	args = append(args, "-movflags", "+faststart", outputPath)
	cmd := exec.CommandContext(ctx, ffmpegBin, args...)
	return cmd.Run()
}

func sanitizeOrExtractThumbnail(
	ctx context.Context,
	ffmpegBin string,
	hasFFmpeg bool,
	videoPath string,
	outThumbPath string,
	durationMs int64,
	opts VideoSanitizeOptions,
	pepper []byte,
) (string, error) {
	if len(opts.ExplicitThumbJPEG) > 0 {
		sanitized, err := SanitizePostPhotoInIsolation(ctx, opts.ExplicitThumbJPEG, pepper, opts.RenamedThumbFile)
		if err == nil {
			if wErr := os.WriteFile(outThumbPath, sanitized.Bytes, 0o640); wErr == nil {
				return sanitized.ContentID, nil
			}
		}
	}

	if hasFFmpeg {
		seekMs := opts.ThumbnailAtMs
		if seekMs <= 0 && durationMs > 0 {
			seekMs = durationMs / 2
		}
		tempRawThumb := outThumbPath + ".raw.jpg"
		defer func() { _ = os.Remove(tempRawThumb) }()
		cmd := exec.CommandContext(ctx, ffmpegBin,
			"-y", "-hide_banner", "-loglevel", "error",
			"-ss", fmt.Sprintf("%.3f", float64(seekMs)/1000.0),
			"-i", videoPath,
			"-frames:v", "1",
			"-q:v", "2",
			tempRawThumb,
		)
		if err := cmd.Run(); err == nil {
			if rawBytes, rErr := os.ReadFile(tempRawThumb); rErr == nil {
				if sanitized, sErr := SanitizePostPhotoInIsolation(ctx, rawBytes, pepper, opts.RenamedThumbFile); sErr == nil {
					if wErr := os.WriteFile(outThumbPath, sanitized.Bytes, 0o640); wErr == nil {
						return sanitized.ContentID, nil
					}
				}
			}
		}
	}

	// Safe deterministic fallback poster frame JPEG (clean RGB image, zero EXIF)
	poster := image.NewRGBA(image.Rect(0, 0, 320, 180))
	for y := 0; y < 180; y++ {
		for x := 0; x < 320; x++ {
			poster.Set(x, y, color.RGBA{R: 28, G: 30, B: 36, A: 255})
		}
	}
	var buf bytes.Buffer
	_ = jpeg.Encode(&buf, poster, &jpeg.Options{Quality: 84})
	if err := os.WriteFile(outThumbPath, buf.Bytes(), 0o640); err != nil {
		return "", err
	}
	mac := hmac.New(sha256.New, pepper)
	mac.Write(buf.Bytes())
	return hex.EncodeToString(mac.Sum(nil)), nil
}

func computeVideoAndAudioFrameFingerprints(
	ctx context.Context,
	ffmpegBin string,
	hasFFmpeg bool,
	videoPath string,
	durationMs int64,
	pepper []byte,
) ([]FrameFingerprintRecord, string) {
	records := make([]FrameFingerprintRecord, 0, 64)
	audioMac := hmac.New(sha256.New, pepper)

	if hasFFmpeg {
		tmpDir, err := os.MkdirTemp("", "telefam-frames-*")
		if err == nil {
			defer func() { _ = os.RemoveAll(tmpDir) }()
			// Extract 1 frame per second cleanly to JPEGs for perceptual dHash + SHA-256
			cmd := exec.CommandContext(ctx, ffmpegBin,
				"-hide_banner", "-loglevel", "error",
				"-i", videoPath,
				"-vf", "fps=1,scale=160:-2",
				filepath.Join(tmpDir, "frame_%05d.jpg"),
			)
			if cmd.Run() == nil {
				entries, _ := os.ReadDir(tmpDir)
				for idx, e := range entries {
					if e.IsDir() || !strings.HasSuffix(e.Name(), ".jpg") {
						continue
					}
					b, rErr := os.ReadFile(filepath.Join(tmpDir, e.Name()))
					if rErr != nil {
						continue
					}
					img, dErr := jpeg.Decode(bytes.NewReader(b))
					if dErr != nil {
						continue
					}
					dhash := ComputeImageDHash(img)
					sum := sha256.Sum256(b)
					records = append(records, FrameFingerprintRecord{
						StreamKind:      "video_frame",
						FrameIndex:      idx,
						TimestampMs:     int64(idx) * 1000,
						PerceptualDHash: dhash,
						Sha256Hex:       hex.EncodeToString(sum[:]),
					})
				}
			}

			// Extract mono 16kHz 16-bit PCM audio frames (1s chunks) and fingerprint every audio frame
			pcmOut, aErr := exec.CommandContext(ctx, ffmpegBin,
				"-hide_banner", "-loglevel", "error",
				"-i", videoPath,
				"-vn", "-ac", "1", "-ar", "16000", "-f", "s16le", "pipe:1",
			).Output()
			if aErr == nil && len(pcmOut) > 0 {
				const oneSecBytes = 32000 // 16000 samples * 2 bytes
				idx := 0
				for off := 0; off < len(pcmOut); off += oneSecBytes {
					end := off + oneSecBytes
					if end > len(pcmOut) {
						end = len(pcmOut)
					}
					chunk := pcmOut[off:end]
					audioMac.Write(chunk)
					sum := sha256.Sum256(chunk)
					records = append(records, FrameFingerprintRecord{
						StreamKind:      "audio_frame",
						FrameIndex:      idx,
						TimestampMs:     int64(idx) * 1000,
						PerceptualDHash: "",
						Sha256Hex:       hex.EncodeToString(sum[:]),
					})
					idx++
				}
			}
		}
	}

	if len(records) == 0 {
		// Deterministic chunked container fingerprint fallback
		if f, err := os.Open(videoPath); err == nil {
			defer func() { _ = f.Close() }()
			buf := make([]byte, 262144)
			idx := 0
			for {
				n, rErr := f.Read(buf)
				if n > 0 {
					chunk := buf[:n]
					sum := sha256.Sum256(chunk)
					audioMac.Write(sum[:])
					ts := int64(0)
					if durationMs > 0 {
						ts = int64(idx) * 1000
					}
					records = append(records, FrameFingerprintRecord{
						StreamKind:      "video_frame",
						FrameIndex:      idx,
						TimestampMs:     ts,
						PerceptualDHash: hex.EncodeToString(sum[:8]),
						Sha256Hex:       hex.EncodeToString(sum[:]),
					})
					idx++
				}
				if rErr != nil {
					break
				}
			}
		}
	}

	return records, hex.EncodeToString(audioMac.Sum(nil))
}

func downloadAllowlistedSongPreview(ctx context.Context, rawURL string) (string, error) {
	parsed, err := url.Parse(strings.TrimSpace(rawURL))
	if err != nil || parsed.Scheme != "https" {
		return "", errors.New("invalid song preview url")
	}
	host := strings.ToLower(parsed.Hostname())
	allowed := strings.HasSuffix(host, ".mzstatic.com") ||
		strings.HasSuffix(host, ".apple.com") ||
		strings.HasSuffix(host, ".dzcdn.net") ||
		strings.HasSuffix(host, ".deezer.com")
	if !allowed {
		return "", errors.New("host not allowlisted")
	}
	if ip := net.ParseIP(host); ip != nil && (ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast()) {
		return "", errors.New("private ip blocked")
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, parsed.String(), nil)
	if err != nil {
		return "", err
	}
	client := &http.Client{Timeout: 8 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", errors.New("music preview fetch failed")
	}
	tmp, err := os.CreateTemp("", "telefam-song-*")
	if err != nil {
		return "", err
	}
	defer func() { _ = tmp.Close() }()
	if _, err := io.Copy(tmp, io.LimitReader(resp.Body, 5*1024*1024)); err != nil {
		_ = os.Remove(tmp.Name())
		return "", err
	}
	return tmp.Name(), nil
}

func copyFileSafe(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer func() { _ = in.Close() }()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o640)
	if err != nil {
		return err
	}
	defer func() { _ = out.Close() }()
	_, err = io.Copy(out, in)
	return err
}
