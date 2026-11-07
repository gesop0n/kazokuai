// Package server は、デバイスに短命トークンを渡すバックエンドの HTTP サーバーである。
package server

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"google.golang.org/genai"

	"github.com/gesop0n/kazokuai/internal/protocol"
)

// Config は、電話をかける相手と、AI の設定である。
type Config struct {
	// Name は見守る方の名前である。
	Name string
	// CallName は、AI が見守る方を呼ぶときの呼び方である。
	CallName string
	// Model は Live API のモデルである。
	Model string
	// Voice は AI の声の名前である。
	Voice string
	// RingTimeout は呼び出しの上限である。
	RingTimeout time.Duration
	// MaxCall は電話の長さの上限である。受話器が上がってから測る。
	MaxCall time.Duration
	// WrapUpBefore は、締めの合図を電話の長さの上限のどれだけ前に送るかである。
	WrapUpBefore time.Duration
	// TokenMargin は、トークンの有効期限を、呼び出しの上限と電話の長さの上限よりどれだけ先にするかである。
	// 有効期限が切れると、開いている接続も使えなくなる。
	TokenMargin time.Duration
}

// Tokens は、制約を固定した短命トークンを作る。genai.Client の AuthTokens がこれを満たす。
type Tokens interface {
	Create(ctx context.Context, config *genai.CreateAuthTokenConfig) (*genai.AuthToken, error)
}

// Clock は今の時刻を返す。
type Clock interface {
	Now() time.Time
}

// New は、protocol.TokenPath でトークンを渡す http.Handler を返す。
func New(config Config, tokens Tokens, clock Clock) http.Handler {
	router := chi.NewRouter()
	router.Post(protocol.TokenPath, func(w http.ResponseWriter, r *http.Request) {
		now := clock.Now()
		token, err := tokens.Create(r.Context(), tokenConfig(config, now))
		if err != nil {
			log.Printf("短命トークンを作れなかった: %v", err)
			http.Error(w, "短命トークンを作れなかった", http.StatusBadGateway)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(protocol.TokenResponse{
			Token: token.Name,
			Model: config.Model,
			Times: protocol.CallTimes{
				RingTimeout:  config.RingTimeout,
				MaxCall:      config.MaxCall,
				WrapUpBefore: config.WrapUpBefore,
			},
		})
	})
	return router
}

// tokenConfig は、1 回の電話のための短命トークンの制約である。
// LockAdditionalFields を指定しないので、モデルと設定のすべてのフィールドがトークンに固定され、
// デバイスはどれも変えられない。
func tokenConfig(config Config, now time.Time) *genai.CreateAuthTokenConfig {
	return &genai.CreateAuthTokenConfig{
		// 有効期限が切れると開いている接続も切れるので、呼び出しと電話の全体を覆う。
		// 新しいセッションを始められる期限は、SDK の既定の 60 秒のままにする。
		ExpireTime: now.Add(config.RingTimeout + config.MaxCall + config.TokenMargin),
		Uses:       genai.Ptr[int32](1),
		LiveConnectConstraints: &genai.LiveConnectConstraints{
			Model: config.Model,
			Config: &genai.LiveConnectConfig{
				ResponseModalities: []genai.Modality{genai.ModalityAudio},
				SpeechConfig: &genai.SpeechConfig{
					VoiceConfig: &genai.VoiceConfig{
						PrebuiltVoiceConfig: &genai.PrebuiltVoiceConfig{VoiceName: config.Voice},
					},
				},
				SystemInstruction:        genai.NewContentFromText(systemInstruction(config, now), genai.RoleUser),
				InputAudioTranscription:  &genai.AudioTranscriptionConfig{},
				OutputAudioTranscription: &genai.AudioTranscriptionConfig{},
			},
		},
	}
}
