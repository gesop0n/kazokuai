// Package server は、デバイスに短命トークンを渡し、アプリから見守る方の登録と今すぐ通話を受け、電話の報告からまとめを作るバックエンドの HTTP サーバーである。
// つながっている電話機は、見守る方の ID ごとにメモリーで持つ。
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

// Config は、AI の設定である。電話をかける見守る方は、電話機が接続するときに決まり、フラグでは持たない。
type Config struct {
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
	// SummaryModel は、まとめに使う Gemini のモデルである。空なら DefaultSummaryModel を使う。
	SummaryModel string
	// SummaryRetryWait は、まとめの generateContent が失敗してから、次を試すまでの時間である。
	// 0 なら待たない。
	SummaryRetryWait time.Duration
}

// DefaultSummaryModel は、まとめに使うモデルの既定値である。
const DefaultSummaryModel = "gemini-3.6-flash"

// Tokens は、制約を固定した短命トークンを作る。genai.Client の AuthTokens がこれを満たす。
type Tokens interface {
	Create(ctx context.Context, config *genai.CreateAuthTokenConfig) (*genai.AuthToken, error)
}

// Summarizer は、会話からまとめを 1 回の generateContent で作る。genai.Client の Models がこれを満たす。
type Summarizer interface {
	GenerateContent(ctx context.Context, model string, contents []*genai.Content, config *genai.GenerateContentConfig) (*genai.GenerateContentResponse, error)
}

// Clock は今の時刻を返す。
type Clock interface {
	Now() time.Time
}

// Handler は、バックエンドの HTTP サーバーである。Stop で電話機との接続を閉じる。
type Handler struct {
	http.Handler
	stop   context.CancelFunc
	phones *phoneBook
}

// Stop は、つながっている電話機との WebSocket を閉じる。
func (h *Handler) Stop() { h.stop() }

// Connected は、personID の電話機が今つながっているかを返す。
func (h *Handler) Connected(personID string) bool { return h.phones.connected(personID) }

// New は、protocol.TokenPath でデバイスにトークンを渡し、protocol.PhonePath で電話機の接続を受け、
// watchedPersonsPath でアプリから見守る方の登録を受け、protocol.StartCallPath で今すぐ通話を始め、
// protocol.CallReportPath でデバイスから電話の報告を受ける Handler を返す。
func New(config Config, firebase Firebase, tokens Tokens, summarizer Summarizer, clock Clock) *Handler {
	ctx, stop := context.WithCancel(context.Background())
	s := &server{
		config:     config,
		firebase:   firebase,
		tokens:     tokens,
		summarizer: summarizer,
		clock:      clock,
		phones:     newPhoneBook(),
		base:       ctx,
	}
	router := chi.NewRouter()
	router.Get(protocol.PhonePath, s.phone)
	router.Post(protocol.TokenPath, s.token)
	router.Post(watchedPersonsPath, s.registerWatchedPerson)
	router.Post(protocol.StartCallPath, s.startCall)
	router.Post(protocol.CallReportPath, s.reportCall)
	return &Handler{Handler: router, stop: stop, phones: s.phones}
}

type server struct {
	config     Config
	firebase   Firebase
	tokens     Tokens
	summarizer Summarizer
	clock      Clock
	phones     *phoneBook
	// base は、このサーバーが止まるまで生きている context である。電話機の接続はこれに従う。
	base context.Context
}

// token は、頼まれた電話の見守る方の名前と呼び方を Firestore から読み、それをシステム指示に書いたトークンを作る。
func (s *server) token(w http.ResponseWriter, r *http.Request) {
	var req protocol.TokenRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxRegistration)).Decode(&req); err != nil {
		http.Error(w, "本文を JSON で読めなかった", http.StatusBadRequest)
		return
	}
	if req.CallID == "" || req.WatchedPersonID == "" {
		http.Error(w, "電話の ID と見守る方の ID を入れてください", http.StatusBadRequest)
		return
	}
	if _, err := s.callRef(req.WatchedPersonID, req.CallID).Get(r.Context()); err != nil {
		http.Error(w, "電話が見つからなかった", http.StatusNotFound)
		return
	}
	config := s.config
	person, err := readWatchedPerson(r.Context(), s.firebase.Firestore, req.WatchedPersonID)
	if err != nil {
		log.Printf("見守る方 %s を読めなかった: %v", req.WatchedPersonID, err)
		http.Error(w, "見守る方を読めなかった", http.StatusInternalServerError)
		return
	}
	now := s.clock.Now()
	token, err := s.tokens.Create(r.Context(), tokenConfig(config, person, now))
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
}

// tokenConfig は、1 回の電話のための短命トークンの制約である。
// LockAdditionalFields を指定しないので、モデルと設定のすべてのフィールドがトークンに固定され、
// デバイスはどれも変えられない。
func tokenConfig(config Config, person watchedPerson, now time.Time) *genai.CreateAuthTokenConfig {
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
				SystemInstruction: genai.NewContentFromText(systemInstruction(config, person, now), genai.RoleUser),
				// 言語を自分で判定すると、「うん」のような短い返事が別の言語になる。
				// 見守る方の文字起こしには、言語のヒントとして日本語を渡す。
				InputAudioTranscription: &genai.AudioTranscriptionConfig{
					LanguageCodes: []string{"ja-JP"},
				},
				OutputAudioTranscription: &genai.AudioTranscriptionConfig{},
			},
		},
	}
}
