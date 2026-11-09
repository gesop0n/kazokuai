package server

import (
	"crypto/subtle"
	"net/http"
	"net/url"
	"strings"

	"github.com/gesop0n/kazokuai/internal/protocol"
)

// requirePhone は、電話機の合言葉が無い /token、/calls、WebSocket を断る。
func (s *server) requirePhone(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !phoneSecretOK(r.Header.Get(protocol.PhoneSecretHeader), s.config.PhoneSecret) {
			http.Error(w, "合言葉が違います", http.StatusUnauthorized)
			return
		}
		next(w, r)
	}
}

func phoneSecretOK(got, want string) bool {
	if want == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(got), []byte(want)) == 1
}

// withCORS は、demo- のプロジェクトのときだけ、localhost からのリクエストに CORS を付ける。
// 事前のリクエストにはここで答え、ルートには進まない。本番は Hosting の /api を通るので、CORS は付けない。
func (s *server) withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if demoProject(s.config.ProjectID) && localhostOrigin(origin) {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			if r.Method == http.MethodOptions {
				w.WriteHeader(http.StatusNoContent)
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}

func demoProject(id string) bool {
	return strings.HasPrefix(id, "demo-")
}

func localhostOrigin(origin string) bool {
	u, err := url.Parse(origin)
	if err != nil || u.Host == "" {
		return false
	}
	switch u.Scheme {
	case "http", "https":
	default:
		return false
	}
	switch u.Hostname() {
	case "localhost", "127.0.0.1", "::1":
		return true
	default:
		return false
	}
}
