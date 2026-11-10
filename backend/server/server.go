// Package server は、デバイスに短命トークンを渡し、アプリから見守る方の登録と今すぐ通話と予約と通話内容の案を受け、電話の報告からまとめを作るバックエンドの HTTP サーバーである。
// 古い道の電話機は見守る方の ID ごとに、ID と鍵で認証した電話機は電話機の ID ごとに、メモリーで持つ。
package server

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"
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
	// PhoneSecret は、電話機の合言葉である。登録するときの合言葉で、古い道の /token、/calls、WebSocket も、これが無いと断る。
	PhoneSecret string
	// Logger は、電話機のつながりと、電話機がいない今すぐ通話を書く。nil なら標準のログである。
	Logger *log.Logger
	// TasksAudience は、予約のタスクの OIDC トークンの audience である。バックエンド自身の URL。
	TasksAudience string
	// TasksAccount は、予約のタスクのサービスアカウントのメールである。トークンの email と一致させる。
	TasksAccount string
	// CheckBookingOIDC は、予約のタスクの OIDC トークンを確かめ、そのメールアドレスを返す。
	// nil なら Google の ID トークンを確かめる。テストが差し替える。
	CheckBookingOIDC func(ctx context.Context, token, audience string) (email string, err error)
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

// Connected は、personID の電話機が今つながっているかを返す。
// 結び付きがあるときはその電話機を、無いときは古い道の接続を見る。
func (h *Handler) Connected(personID string) bool { return h.connected(personID) }

// New は、protocol.TokenPath でデバイスにトークンを渡し、protocol.PhonePath で電話機の接続を受け、
// protocol.PhoneRegisterPath で電話機の ID と鍵を登録し、protocol.PhoneCodePath で認証コードを出し、
// watchedPersonsPath でアプリから見守る方の登録を受け、protocol.DraftScriptPath で通話内容の案を作り、
// protocol.StartCallPath で今すぐ通話を始め、protocol.CallReportPath でデバイスから電話の報告を受け、
// protocol.SyncPreparePath で同期の準備を始め、protocol.SyncCodePath で認証コードを受け付け、
// protocol.BookingPath で予約を保存し直し、protocol.BookingTaskPath で予約の時刻に電話を始める Handler を返す。
// アプリの道は /api の下にも付ける。Hosting は /api/** を、道をそのまま Cloud Run に回す。
// 電話機の道（登録、認証コード、/token、/calls、WebSocket）と、予約のタスクの道は、/api の下には置かない。
// demo- のプロジェクトでは、予約のタスクの道を閉じ、中のタイマーが同じ処理を呼ぶ。起動時に、まだかけていない予約を読み直す。
// clk が nil のとき、タイマーは実時間で進む。
func New(config Config, firebase Firebase, tokens Tokens, summarizer Summarizer, clk clock.Clock) *Handler {
	ctx, stop := context.WithCancel(context.Background())
	s := &server{
		config:     config,
		firebase:   firebase,
		tokens:     tokens,
		summarizer: summarizer,
		clock:      clk,
		phones:     newPhoneBook(),
		syncs:      newSyncBook(),
		delivered:  map[string]struct{}{},
		base:       ctx,
	}
	var bookings *demoSchedule
	if strings.HasPrefix(config.ProjectID, "demo-") {
		bookings = newDemoSchedule(s)
		s.schedule = bookings
		s.loadUncalledBookings()
	} else {
		s.schedule = noopSchedule{}
	}
	router := chi.NewRouter()
	router.Post(protocol.PhoneRegisterPath, s.registerPhone)
	router.Post(protocol.PhoneCodePath, s.requirePhone(s.issueSyncCode))
	router.Get(protocol.PhonePath, s.requirePhone(s.phone))
	router.Post(protocol.TokenPath, s.requirePhone(s.token))
	router.Post(protocol.CallReportPath, s.requirePhone(s.reportCall))
	router.Post(protocol.BookingTaskPath, s.fireBookingTask)
	s.mountApp(router)
	router.Route("/api", s.mountApp)
	return &Handler{
		Handler: s.withCORS(router),
		stop: func() {
			stop()
			s.work.Wait()
			if bookings != nil {
				bookings.wg.Wait()
			}
		},
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
	r.Post(protocol.BookingPath, s.createBooking)
	r.Post(protocol.BookingPath+"/{booking}", s.editBooking)
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
	// deliverMu は、予約の電話を届ける処理を 1 件ずつにする。
	// 届けた印を付ける前に、もう一方が印の無い予約を戻さないためである。
	deliverMu sync.Mutex
	// delivered は、電話機には届いたが、届けた印を書けなかった電話の ID である。
	// プロセスが終わると消える。印を書けたあとは見ない。
	delivered map[string]struct{}
	// work は、保存した予約を予定へ入れ続ける goroutine を待つ。
	work sync.WaitGroup
	// clock は、トークンの期限と、ping と、切れた接続の猶予と、同期の期限と、予約の時刻を進める。nil なら実時間である。
	clock clock.Clock
	// schedule は、予約の ID と番号で、その時刻に電話を予定へ入れる。
	schedule bookingSchedule
	// base は、このサーバーが止まるまで生きている context である。電話機の接続はこれに従う。
	base context.Context
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
	if identity.phoneID != "" && req.WatchedPersonID == "" {
		req.WatchedPersonID = identity.personID
	}
	if req.CallID == "" || req.WatchedPersonID == "" {
		http.Error(w, "電話の ID と見守る方の ID を入れてください", http.StatusBadRequest)
		return
	}
	doc, err := s.callRef(req.WatchedPersonID, req.CallID).Get(r.Context())
	if err != nil {
		http.Error(w, "電話が見つからなかった", http.StatusNotFound)
		return
	}
	var script string
	if data := doc.Data(); data != nil {
		script, _ = data["script"].(string)
	}
	config := s.config
	person, err := readWatchedPerson(r.Context(), s.firebase.Firestore, req.WatchedPersonID)
	if err != nil {
		log.Printf("見守る方 %s を読めなかった: %v", req.WatchedPersonID, err)
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
