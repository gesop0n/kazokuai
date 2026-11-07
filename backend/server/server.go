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
		token, err := tokens.Create(r.Context(), tokenConfig(config, clock.Now()))
		if err != nil {
			log.Printf("短命トークンを作れなかった: %v", err)
			http.Error(w, "短命トークンを作れなかった", http.StatusBadGateway)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(protocol.TokenResponse{Token: token.Name, Model: config.Model})
	})
	return router
}

// tokenConfig は、1 回の電話のための短命トークンの制約である。
// LockAdditionalFields を指定しないので、モデルと設定のすべてのフィールドがトークンに固定され、
// デバイスはどれも変えられない。
func tokenConfig(config Config, now time.Time) *genai.CreateAuthTokenConfig {
	return &genai.CreateAuthTokenConfig{
		Uses: genai.Ptr[int32](1),
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
