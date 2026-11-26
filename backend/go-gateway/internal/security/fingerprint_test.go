package security

import (
	"net"
	"net/http/httptest"
	"testing"
)

func mustCIDR(t *testing.T, cidr string) *net.IPNet {
	t.Helper()
	_, network, err := net.ParseCIDR(cidr)
	if err != nil {
		t.Fatalf("ParseCIDR(%q): %v", cidr, err)
	}
	return network
}

func TestExtractClientIPTrustedIgnoresForwardedHeaderFromUntrustedPeer(t *testing.T) {
	req := httptest.NewRequest("GET", "http://example.test/", nil)
	req.RemoteAddr = "198.51.100.20:1234"
	req.Header.Set("X-Forwarded-For", "203.0.113.7")

	got := ExtractClientIPTrusted(req, []*net.IPNet{mustCIDR(t, "10.0.0.0/8")})
	if want := "198.51.100.20"; got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestExtractClientIPTrustedWalksForwardedChainFromTrustedProxy(t *testing.T) {
	req := httptest.NewRequest("GET", "http://example.test/", nil)
	req.RemoteAddr = "10.0.0.2:1234"
	req.Header.Set("X-Forwarded-For", "203.0.113.7, 10.0.0.1")

	got := ExtractClientIPTrusted(req, []*net.IPNet{mustCIDR(t, "10.0.0.0/8")})
	if want := "203.0.113.7"; got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}
