package media

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"image"
	"image/draw"
	"image/jpeg"
	"image/png"
	"net/http"
	"time"
)

const (
	MaxUploadBytes     = 5 * 1024 * 1024
	MaxSourceDimension = 4096
	TargetAvatarSize   = 512
	SanitizeTimeout    = 8 * time.Second
)

type SanitizedAvatar struct {
	Bytes           []byte
	MimeType        string
	FingerprintHash string
}

// SanitizeAvatarInIsolation validates MIME, size, and dimensions inside a bounded timeout,
// decodes to raw pixels, strips all EXIF/metadata, center-crops/resizes to 512x512,
// re-encodes as clean JPEG, and computes an HMAC-SHA256 content fingerprint.
func SanitizeAvatarInIsolation(ctx context.Context, raw []byte, pepper []byte) (*SanitizedAvatar, error) {
	if len(raw) == 0 || len(raw) > MaxUploadBytes {
		return nil, errors.New("invalid upload size")
	}

	isoCtx, cancel := context.WithTimeout(ctx, SanitizeTimeout)
	defer cancel()

	type result struct {
		out *SanitizedAvatar
		err error
	}
	ch := make(chan result, 1)

	go func() {
		detected := http.DetectContentType(raw)
		if detected != "image/jpeg" && detected != "image/png" {
			ch <- result{nil, errors.New("unsupported image type")}
			return
		}

		cfg, format, err := image.DecodeConfig(bytes.NewReader(raw))
		if err != nil || (format != "jpeg" && format != "png") {
			ch <- result{nil, errors.New("invalid image header")}
			return
		}
		if cfg.Width <= 0 || cfg.Height <= 0 || cfg.Width > MaxSourceDimension || cfg.Height > MaxSourceDimension {
			ch <- result{nil, errors.New("image dimensions out of bounds")}
			return
		}

		var src image.Image
		switch format {
		case "jpeg":
			src, err = jpeg.Decode(bytes.NewReader(raw))
		case "png":
			src, err = png.Decode(bytes.NewReader(raw))
		}
		if err != nil {
			ch <- result{nil, errors.New("decode failure")}
			return
		}

		bounds := src.Bounds()
		side := bounds.Dx()
		if bounds.Dy() < side {
			side = bounds.Dy()
		}
		offsetX := bounds.Min.X + (bounds.Dx()-side)/2
		offsetY := bounds.Min.Y + (bounds.Dy()-side)/2

		dst := image.NewRGBA(image.Rect(0, 0, TargetAvatarSize, TargetAvatarSize))
		for y := 0; y < TargetAvatarSize; y++ {
			sy := offsetY + (y*side)/TargetAvatarSize
			for x := 0; x < TargetAvatarSize; x++ {
				sx := offsetX + (x*side)/TargetAvatarSize
				dst.Set(x, y, src.At(sx, sy))
			}
		}
		_ = draw.Src

		var encoded bytes.Buffer
		if err := jpeg.Encode(&encoded, dst, &jpeg.Options{Quality: 88}); err != nil {
			ch <- result{nil, errors.New("re-encode failure")}
			return
		}
		cleanBytes := encoded.Bytes()

		mac := hmac.New(sha256.New, pepper)
		mac.Write(cleanBytes)
		fp := hex.EncodeToString(mac.Sum(nil))

		ch <- result{
			out: &SanitizedAvatar{
				Bytes:           cleanBytes,
				MimeType:        "image/jpeg",
				FingerprintHash: fp,
			},
		}
	}()

	select {
	case <-isoCtx.Done():
		return nil, errors.New("upload processing timeout")
	case res := <-ch:
		return res.out, res.err
	}
}

const (
	MaxPostPhotoBytes     = 10 * 1024 * 1024
	MaxPostPhotoDimension = 8192
	TargetPostMaxEdge     = 1920
)

type SanitizedPostPhoto struct {
	Bytes           []byte
	MimeType        string
	RenamedFilename string
	Width           int
	Height          int
	PerceptualDHash string
	Sha256Hex       string
	ContentID       string
}

// ComputeImageDHash computes a 64-bit horizontal gradient difference hash (9x8 luminance grid)
// over decoded pixels, matching the C++ core engine's telefam_compute_frame_dhash algorithm.
func ComputeImageDHash(src image.Image) string {
	b := src.Bounds()
	w := b.Dx()
	h := b.Dy()
	if w <= 0 || h <= 0 {
		return "0000000000000000"
	}
	var luma [8][9]float64
	for gy := 0; gy < 8; gy++ {
		y0 := b.Min.Y + (gy*h)/8
		y1 := b.Min.Y + ((gy+1)*h)/8
		if y1 <= y0 {
			y1 = y0 + 1
		}
		for gx := 0; gx < 9; gx++ {
			x0 := b.Min.X + (gx*w)/9
			x1 := b.Min.X + ((gx+1)*w)/9
			if x1 <= x0 {
				x1 = x0 + 1
			}
			var sum float64
			var count int64
			for y := y0; y < y1 && y < b.Max.Y; y++ {
				for x := x0; x < x1 && x < b.Max.X; x++ {
					r, g, bl, _ := src.At(x, y).RGBA()
					rf := float64(r >> 8)
					gf := float64(g >> 8)
					bf := float64(bl >> 8)
					sum += 0.299*rf + 0.587*gf + 0.114*bf
					count++
				}
			}
			if count > 0 {
				luma[gy][gx] = sum / float64(count)
			}
		}
	}
	var hash uint64
	for gy := 0; gy < 8; gy++ {
		for gx := 0; gx < 8; gx++ {
			hash <<= 1
			if luma[gy][gx] > luma[gy][gx+1] {
				hash |= 1
			}
		}
	}
	const hexDigits = "0123456789abcdef"
	var out [16]byte
	for i := 15; i >= 0; i-- {
		out[i] = hexDigits[hash&0xf]
		hash >>= 4
	}
	return string(out[:])
}

func SanitizePostPhotoInIsolation(ctx context.Context, raw []byte, pepper []byte, renamedFilename string) (*SanitizedPostPhoto, error) {
	if len(raw) == 0 || len(raw) > MaxPostPhotoBytes {
		return nil, errors.New("invalid photo upload size")
	}

	isoCtx, cancel := context.WithTimeout(ctx, 12*time.Second)
	defer cancel()

	type result struct {
		out *SanitizedPostPhoto
		err error
	}
	ch := make(chan result, 1)

	go func() {
		detected := http.DetectContentType(raw)
		if detected != "image/jpeg" && detected != "image/png" {
			ch <- result{nil, errors.New("unsupported image type")}
			return
		}

		cfg, format, err := image.DecodeConfig(bytes.NewReader(raw))
		if err != nil || (format != "jpeg" && format != "png") {
			ch <- result{nil, errors.New("invalid image header")}
			return
		}
		if cfg.Width <= 0 || cfg.Height <= 0 || cfg.Width > MaxPostPhotoDimension || cfg.Height > MaxPostPhotoDimension {
			ch <- result{nil, errors.New("image dimensions out of bounds")}
			return
		}

		var src image.Image
		switch format {
		case "jpeg":
			src, err = jpeg.Decode(bytes.NewReader(raw))
		case "png":
			src, err = png.Decode(bytes.NewReader(raw))
		}
		if err != nil {
			ch <- result{nil, errors.New("decode failure")}
			return
		}

		b := src.Bounds()
		dstW, dstH := b.Dx(), b.Dy()
		if dstW > TargetPostMaxEdge || dstH > TargetPostMaxEdge {
			if dstW >= dstH {
				dstH = (dstH * TargetPostMaxEdge) / dstW
				dstW = TargetPostMaxEdge
			} else {
				dstW = (dstW * TargetPostMaxEdge) / dstH
				dstH = TargetPostMaxEdge
			}
		}
		if dstW < 1 {
			dstW = 1
		}
		if dstH < 1 {
			dstH = 1
		}

		dst := image.NewRGBA(image.Rect(0, 0, dstW, dstH))
		for y := 0; y < dstH; y++ {
			sy := b.Min.Y + (y*b.Dy())/dstH
			for x := 0; x < dstW; x++ {
				sx := b.Min.X + (x*b.Dx())/dstW
				dst.Set(x, y, src.At(sx, sy))
			}
		}

		var encoded bytes.Buffer
		if err := jpeg.Encode(&encoded, dst, &jpeg.Options{Quality: 86}); err != nil {
			ch <- result{nil, errors.New("re-encode failure")}
			return
		}
		cleanBytes := encoded.Bytes()

		sum := sha256.Sum256(cleanBytes)
		shaHex := hex.EncodeToString(sum[:])
		dhash := ComputeImageDHash(dst)

		mac := hmac.New(sha256.New, pepper)
		mac.Write([]byte("photo|"))
		mac.Write([]byte(dhash))
		mac.Write([]byte("|"))
		mac.Write([]byte(shaHex))
		contentID := hex.EncodeToString(mac.Sum(nil))

		ch <- result{
			out: &SanitizedPostPhoto{
				Bytes:           cleanBytes,
				MimeType:        "image/jpeg",
				RenamedFilename: renamedFilename,
				Width:           dstW,
				Height:          dstH,
				PerceptualDHash: dhash,
				Sha256Hex:       shaHex,
				ContentID:       contentID,
			},
		}
	}()

	select {
	case <-isoCtx.Done():
		return nil, errors.New("upload processing timeout")
	case res := <-ch:
		return res.out, res.err
	}
}
