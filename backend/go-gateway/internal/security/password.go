package security

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"math/bits"
	"strconv"
	"strings"
	"unicode"
)

const (
	scryptN = 32768 // Memory-hard cost factor (~32 MiB) making offline cracking expensive
	scryptR = 8
	scryptP = 1
	scryptK = 32
)

func ValidatePasswordStrength(pw string) error {
	if len(pw) < 10 || len(pw) > 128 {
		return errors.New("password must be 10-128 characters")
	}
	var hasUpper, hasLower, hasDigitOrSym bool
	for _, r := range pw {
		switch {
		case unicode.IsUpper(r):
			hasUpper = true
		case unicode.IsLower(r):
			hasLower = true
		case unicode.IsDigit(r) || unicode.IsPunct(r) || unicode.IsSymbol(r):
			hasDigitOrSym = true
		}
	}
	if !hasUpper || !hasLower || !hasDigitOrSym {
		return errors.New("password requires upper, lower, and digit/symbol characters")
	}
	return nil
}

func HashPassword(password string) (string, error) {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	dk := scryptKey([]byte(password), salt, scryptN, scryptR, scryptP, scryptK)
	return fmt.Sprintf("scrypt$%d$%d$%d$%s$%s",
		scryptN, scryptR, scryptP,
		hex.EncodeToString(salt),
		hex.EncodeToString(dk),
	), nil
}

func VerifyPassword(password, encoded string) bool {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[0] != "scrypt" {
		return false
	}
	n, err1 := strconv.Atoi(parts[1])
	r, err2 := strconv.Atoi(parts[2])
	p, err3 := strconv.Atoi(parts[3])
	salt, err4 := hex.DecodeString(parts[4])
	expected, err5 := hex.DecodeString(parts[5])
	if err1 != nil || err2 != nil || err3 != nil || err4 != nil || err5 != nil {
		return false
	}
	if n < 1024 || n > 131072 || (n&(n-1)) != 0 || r < 1 || r > 16 || p < 1 || p > 8 || len(expected) == 0 {
		return false
	}
	dk := scryptKey([]byte(password), salt, n, r, p, len(expected))
	return subtle.ConstantTimeCompare(dk, expected) == 1
}

// Pure-Go RFC 7914 Scrypt implementation using Go standard library only.
func scryptKey(password, salt []byte, n, r, p, keyLen int) []byte {
	b := pbkdf2SHA256(password, salt, 1, p*128*r)
	xy := make([]uint32, 64*r)
	v := make([]uint32, 32*n*r)
	for i := 0; i < p; i++ {
		smix(b[i*128*r:], r, n, v, xy)
	}
	return pbkdf2SHA256(password, b, 1, keyLen)
}

func pbkdf2SHA256(password, salt []byte, iter, keyLen int) []byte {
	prf := hmac.New(sha256.New, password)
	hashLen := prf.Size()
	numBlocks := (keyLen + hashLen - 1) / hashLen
	var dk []byte
	u := make([]byte, hashLen)
	buf := make([]byte, 4)

	for block := 1; block <= numBlocks; block++ {
		prf.Reset()
		prf.Write(salt)
		binary.BigEndian.PutUint32(buf, uint32(block))
		prf.Write(buf)
		dk = prf.Sum(dk)
		copy(u, dk[len(dk)-hashLen:])

		for i := 2; i <= iter; i++ {
			prf.Reset()
			prf.Write(u)
			u = u[:0]
			u = prf.Sum(u)
			for j := range u {
				dk[len(dk)-hashLen+j] ^= u[j]
			}
		}
	}
	return dk[:keyLen]
}

func salsaXOR(tmp *[16]uint32, in, out []uint32) {
	w := tmp[:]
	for i := 0; i < 16; i++ {
		w[i] ^= in[i]
	}
	x0, x1, x2, x3 := w[0], w[1], w[2], w[3]
	x4, x5, x6, x7 := w[4], w[5], w[6], w[7]
	x8, x9, x10, x11 := w[8], w[9], w[10], w[11]
	x12, x13, x14, x15 := w[12], w[13], w[14], w[15]

	for i := 0; i < 8; i += 2 {
		x4 ^= bits.RotateLeft32(x0+x12, 7)
		x8 ^= bits.RotateLeft32(x4+x0, 9)
		x12 ^= bits.RotateLeft32(x8+x4, 13)
		x0 ^= bits.RotateLeft32(x12+x8, 18)

		x9 ^= bits.RotateLeft32(x5+x1, 7)
		x13 ^= bits.RotateLeft32(x9+x5, 9)
		x1 ^= bits.RotateLeft32(x13+x9, 13)
		x5 ^= bits.RotateLeft32(x1+x13, 18)

		x14 ^= bits.RotateLeft32(x10+x6, 7)
		x2 ^= bits.RotateLeft32(x14+x10, 9)
		x6 ^= bits.RotateLeft32(x2+x14, 13)
		x10 ^= bits.RotateLeft32(x6+x2, 18)

		x3 ^= bits.RotateLeft32(x15+x11, 7)
		x7 ^= bits.RotateLeft32(x3+x15, 9)
		x11 ^= bits.RotateLeft32(x7+x3, 13)
		x15 ^= bits.RotateLeft32(x11+x7, 18)

		x1 ^= bits.RotateLeft32(x0+x3, 7)
		x2 ^= bits.RotateLeft32(x1+x0, 9)
		x3 ^= bits.RotateLeft32(x2+x1, 13)
		x0 ^= bits.RotateLeft32(x3+x2, 18)

		x6 ^= bits.RotateLeft32(x5+x4, 7)
		x7 ^= bits.RotateLeft32(x6+x5, 9)
		x4 ^= bits.RotateLeft32(x7+x6, 13)
		x5 ^= bits.RotateLeft32(x4+x7, 18)

		x11 ^= bits.RotateLeft32(x10+x9, 7)
		x8 ^= bits.RotateLeft32(x11+x10, 9)
		x9 ^= bits.RotateLeft32(x8+x11, 13)
		x10 ^= bits.RotateLeft32(x9+x8, 18)

		x12 ^= bits.RotateLeft32(x15+x14, 7)
		x13 ^= bits.RotateLeft32(x12+x15, 9)
		x14 ^= bits.RotateLeft32(x13+x12, 13)
		x15 ^= bits.RotateLeft32(x14+x13, 18)
	}

	w[0] += x0
	w[1] += x1
	w[2] += x2
	w[3] += x3
	w[4] += x4
	w[5] += x5
	w[6] += x6
	w[7] += x7
	w[8] += x8
	w[9] += x9
	w[10] += x10
	w[11] += x11
	w[12] += x12
	w[13] += x13
	w[14] += x14
	w[15] += x15

	for i := 0; i < 16; i++ {
		out[i] = w[i]
	}
}

func blockMix(tmp *[16]uint32, in, out []uint32, r int) {
	copy(tmp[:], in[(2*r-1)*16:])
	for i := 0; i < 2*r; i += 2 {
		salsaXOR(tmp, in[i*16:], out[i*8:])
		salsaXOR(tmp, in[(i+1)*16:], out[(i+2*r)*8:])
	}
}

func integerify(x []uint32, r int) uint64 {
	j := (2*r - 1) * 16
	return uint64(x[j]) | uint64(x[j+1])<<32
}

func smix(b []byte, r, n int, v, xy []uint32) {
	var tmp [16]uint32
	x := xy
	y := xy[32*r:]

	for i := 0; i < 32*r; i++ {
		x[i] = binary.LittleEndian.Uint32(b[i*4:])
	}
	for i := 0; i < n; i += 2 {
		copy(v[i*(32*r):], x[:32*r])
		blockMix(&tmp, x, y, r)

		copy(v[(i+1)*(32*r):], y[:32*r])
		blockMix(&tmp, y, x, r)
	}
	for i := 0; i < n; i += 2 {
		j := int(integerify(x, r) & uint64(n-1))
		for k := 0; k < 32*r; k++ {
			x[k] ^= v[j*(32*r)+k]
		}
		blockMix(&tmp, x, y, r)

		j = int(integerify(y, r) & uint64(n-1))
		for k := 0; k < 32*r; k++ {
			y[k] ^= v[j*(32*r)+k]
		}
		blockMix(&tmp, y, x, r)
	}
	for i := 0; i < 32*r; i++ {
		binary.LittleEndian.PutUint32(b[i*4:], x[i])
	}
}
