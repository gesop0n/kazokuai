// Package server は、デバイスに短命トークンを渡し、アプリから見守る方の登録と今すぐ通話と通話内容の案を受け、電話の報告からまとめを作るバックエンドの HTTP サーバーである。
// つながっている電話機は、電話機の ID ごとにメモリーで持つ。
package server

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"
	"google.golang.org/genai"

	"github.com/gesop0n/kazokuai/internal/clock"
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
	// ProjectID は、Firebase のプロジェクトである。demo- で始まるときだけ、localhost からの CORS を許す。
	ProjectID string
	// PhoneSecret は、電話機を登録するときの合言葉である。
	PhoneSecret string
	// Logger は、電話機のつながりと、電話機がいない今すぐ通話を書く。nil なら標準のログである。
	Logger *log.Logger
	// AfterPhoneRegistered は、電話機の接続を登録したあと、結び付きを読む前に呼ぶ。
	// テストが、そのあいだに同期を終えるために使う。本番は nil である。
	AfterPhoneRegistered func()
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

// Handler は、バックエンドの HTTP サーバーである。Stop で電話機との接続を閉じる。
type Handler struct {
	http.Handler
	stop      context.CancelFunc
	connected func(string) bool
}

// Stop は、つながっている電話機との WebSocket を閉じる。
func (h *Handler) Stop() { h.stop() }

// Connected は、personID に結び付いた電話機が今つながっているかを返す。
func (h *Handler) Connected(personID string) bool { return h.connected(personID) }

// New は、protocol.TokenPath でデバイスにトークンを渡し、protocol.PhonePath で電話機の接続を受け、
// protocol.PhoneRegisterPath で電話機の ID と鍵を登録し、protocol.PhoneCodePath で認証コードを出し、
// watchedPersonsPath でアプリから見守る方の登録を受け、protocol.DraftScriptPath で通話内容の案を作り、
// protocol.StartCallPath で今すぐ通話を始め、protocol.CallReportPath でデバイスから電話の報告を受け、
// protocol.SyncPreparePath で同期の準備を始め、protocol.SyncCodePath で認証コードを受け付ける Handler を返す。
// アプリの道は /api の下にも付ける。Hosting は /api/** を、道をそのまま Cloud Run に回す。
// 電話機の道（登録、認証コード、/token、/calls、WebSocket）は、/api の下には置かない。
// clk が nil のとき、タイマーは実時間で進む。
func New(config Config, firebase Firebase, tokens Tokens, summarizer Summarizer, clk clock.Clock) *Handler {
	ctx, stop := context.WithCancel(context.Background())
	s := &server{
		config:               config,
		firebase:             firebase,
		tokens:               tokens,
		summarizer:           summarizer,
		clock:                clk,
		phones:               newPhoneBook(),
		syncs:                newSyncBook(),
		base:                 ctx,
		afterPhoneRegistered: config.AfterPhoneRegistered,
	}
	router := chi.NewRouter()
	router.Post(protocol.PhoneRegisterPath, s.registerPhone)
	router.Post(protocol.PhoneCodePath, s.requirePhone(s.issueSyncCode))
	router.Get(protocol.PhonePath, s.requirePhone(s.phone))
	router.Post(protocol.TokenPath, s.requirePhone(s.token))
	router.Post(protocol.CallReportPath, s.requirePhone(s.reportCall))
	s.mountApp(router)
	router.Route("/api", s.mountApp)
	return &Handler{
		Handler: s.withCORS(router),
		stop:    stop,
		connected: func(personID string) bool {
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cancel()
			return s.personConnected(ctx, personID)
		},
	}
}

// mountApp は、アプリが呼ぶ道を r に付ける。
func (s *server) mountApp(r chi.Router) {
	r.Post(watchedPersonsPath, s.registerWatchedPerson)
	r.Post(protocol.DraftScriptPath, s.draftScript)
	r.Post(protocol.StartCallPath, s.startCall)
	r.Post(protocol.SyncPreparePath, s.startSyncPrep)
	r.Post(protocol.SyncCodePath, s.sendSyncCode)
}

func (s *server) newTimer(d time.Duration) clock.Timer {
	if s.clock == nil {
		return clock.Real{}.NewTimer(d)
	}
	return s.clock.NewTimer(d)
}

type server struct {
	config     Config
	firebase   Firebase
	tokens     Tokens
	summarizer Summarizer
	phones     *phoneBook
	// syncs は、同期の準備と認証コードと、その回数である。プロセスが終わると消える。
	syncs *syncBook
	// linkMu は、結び付きの確認から消費までと、電話を届ける直前の読み直しを重ねない。
	// 同じ準備で二人分を結び付けたり、外した電話機へ電話を届けたりしないためである。
	linkMu sync.Mutex
	// clock は、トークンの期限と、ping と、切れた接続の猶予と、同期の期限を進める。nil なら実時間である。
	clock clock.Clock
	// base は、このサーバーが止まるまで生きている context である。電話機の接続はこれに従う。
	base context.Context
	// afterPhoneRegistered は、接続を登録したあと、結び付きを読む前に呼ぶ。nil なら呼ばない。
	afterPhoneRegistered func()
}

// token は、頼まれた電話の見守る方と、伝言があればその通話内容を Firestore から読み、システム指示に書いたトークンを作る。
func (s *server) token(w http.ResponseWriter, r *http.Request) {
	var req protocol.TokenRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxRegistration)).Decode(&req); err != nil {
		http.Error(w, "本文を JSON で読めなかった", http.StatusBadRequest)
		return
	}
	identity := phoneIdentityFrom(r.Context())
	if refuseOtherPerson(w, identity, req.WatchedPersonID) {
		return
	}
	if identity.personID == "" {
		http.Error(w, "この電話機は同期していません", http.StatusConflict)
		return
	}
	if req.CallID == "" {
		http.Error(w, "電話の ID を入れてください", http.StatusBadRequest)
		return
	}
	personID := identity.personID
	doc, err := s.callRef(personID, req.CallID).Get(r.Context())
	if err != nil {
		http.Error(w, "電話が見つからなかった", http.StatusNotFound)
		return
	}
	var script string
	if data := doc.Data(); data != nil {
		script, _ = data["script"].(string)
	}
	config := s.config
	person, err := readWatchedPerson(r.Context(), s.firebase.Firestore, personID)
	if err != nil {
		log.Printf("見守る方 %s を読めなかった: %v", personID, err)
		http.Error(w, "見守る方を読めなかった", http.StatusInternalServerError)
		return
	}
	now := s.clock.Now()
	token, err := s.tokens.Create(r.Context(), tokenConfig(config, person, now, script))
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
func tokenConfig(config Config, person watchedPerson, now time.Time, script string) *genai.CreateAuthTokenConfig {
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
				SystemInstruction: genai.NewContentFromText(systemInstruction(config, person, now, script), genai.RoleUser),
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
