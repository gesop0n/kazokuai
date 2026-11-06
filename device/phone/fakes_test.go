package phone_test

import (
	"context"
	"errors"
	"fmt"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"google.golang.org/genai"

	"github.com/gesop0n/kazokuai/backend/server"
	"github.com/gesop0n/kazokuai/device/phone"
)

// テストの境目の外側だけを偽物にする。偽物は電話機、時計、Gemini の 3 つで、
// デバイスの電話の処理、その HTTP のクライアント、バックエンドの HTTP のサーバーは本物を動かす。

const waitTimeout = 5 * time.Second

// waitUntil は、cond が true を返すまで待つ。
func waitUntil(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(waitTimeout)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatalf("待っても%s", what)
		}
		time.Sleep(time.Millisecond)
	}
}

// system は、テストの中で動かすバックエンドと、そこからトークンをもらうデバイスである。
type system struct {
	phone    *fakePhone
	gemini   *fakeGemini
	terminal *terminal
	device   *phone.Device
}

func newSystem(t *testing.T, config server.Config, now time.Time) *system {
	t.Helper()
	gemini := &fakeGemini{}
	backend := httptest.NewServer(server.New(config, gemini, fakeClock{now}))
	t.Cleanup(backend.Close)
	p := &fakePhone{hook: make(chan phone.HookEvent, 4)}
	term := &terminal{}
	return &system{
		phone:    p,
		gemini:   gemini,
		terminal: term,
		device: &phone.Device{
			Backend: backend.URL,
			Gemini:  gemini,
			Phone:   phone.Phone{Handset: p, Hook: p, Ringer: p, Lamp: p},
			Out:     term,
		},
	}
}

// call は、動いている 1 回の電話である。
type call struct {
	ended chan struct{}
	err   error
}

func (s *system) startCall(t *testing.T) *call {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	c := &call{ended: make(chan struct{})}
	go func() {
		c.err = s.device.Call(ctx)
		close(c.ended)
	}()
	t.Cleanup(func() {
		cancel()
		select {
		case <-c.ended:
		case <-time.After(waitTimeout):
			t.Error("テストの終わりに電話が終わらなかった")
		}
	})
	return c
}

// result は、電話が終わるのを待ち、Call が返したエラーを返す。
func (c *call) result(t *testing.T) error {
	t.Helper()
	select {
	case <-c.ended:
		return c.err
	case <-time.After(waitTimeout):
		t.Fatal("待っても電話が終わらなかった")
		return nil
	}
}

func (c *call) hasEnded() bool {
	select {
	case <-c.ended:
		return true
	default:
		return false
	}
}

// fakeClock は、決まった時刻を返す偽の時計である。
type fakeClock struct{ now time.Time }

func (c fakeClock) Now() time.Time { return c.now }

// fakePhone は偽の電話機である。受話器の音声、フック、呼び出し音、ランプを持つ。
type fakePhone struct {
	hook chan phone.HookEvent

	mu      sync.Mutex
	ringing bool
	lit     bool
	mic     chan []byte // マイクが開いている間だけある
	played  []byte
	hushes  int
}

func (p *fakePhone) Listen(ctx context.Context) (<-chan []byte, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	mic := make(chan []byte, 16)
	p.mic = mic
	go func() {
		<-ctx.Done()
		p.mu.Lock()
		defer p.mu.Unlock()
		close(mic)
		p.mic = nil
	}()
	return mic, nil
}

func (p *fakePhone) Play(pcm []byte) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.played = append(p.played, pcm...)
}

func (p *fakePhone) Hush() {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.hushes++
}

func (p *fakePhone) Events() <-chan phone.HookEvent { return p.hook }

func (p *fakePhone) Ring() { p.set(&p.ringing, true) }
func (p *fakePhone) Stop() { p.set(&p.ringing, false) }
func (p *fakePhone) On()   { p.set(&p.lit, true) }
func (p *fakePhone) Off()  { p.set(&p.lit, false) }

func (p *fakePhone) set(field *bool, v bool) {
	p.mu.Lock()
	defer p.mu.Unlock()
	*field = v
}

func (p *fakePhone) get(field *bool) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return *field
}

func (p *fakePhone) isRinging() bool { return p.get(&p.ringing) }
func (p *fakePhone) isLit() bool     { return p.get(&p.lit) }

func (p *fakePhone) pickUp()  { p.hook <- phone.PickedUp }
func (p *fakePhone) putDown() { p.hook <- phone.PutDown }

// roomNoise は、電話機のまわりで鳴った音である。マイクが開いているときだけマイクに入る。
func (p *fakePhone) roomNoise(pcm []byte) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.mic != nil {
		p.mic <- pcm
	}
}

// say は、見守る方が受話器に向かって話した音である。マイクが開くのを待ってからマイクに入れる。
func (p *fakePhone) say(t *testing.T, pcm []byte) {
	t.Helper()
	waitUntil(t, "マイクが開かなかった", func() bool {
		p.mu.Lock()
		defer p.mu.Unlock()
		return p.mic != nil
	})
	p.roomNoise(pcm)
}

func (p *fakePhone) playedAudio() []byte {
	p.mu.Lock()
	defer p.mu.Unlock()
	return append([]byte(nil), p.played...)
}

func (p *fakePhone) hushCount() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.hushes
}

// fakeGemini は偽の Gemini である。トークンを作るときの制約を記録し、
// Live のセッションとして fakeSession を開く。
type fakeGemini struct {
	mu       sync.Mutex
	tokens   []*genai.CreateAuthTokenConfig
	sessions []*fakeSession
}

func (g *fakeGemini) Create(ctx context.Context, config *genai.CreateAuthTokenConfig) (*genai.AuthToken, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.tokens = append(g.tokens, config)
	return &genai.AuthToken{Name: fmt.Sprintf("auth_tokens/%d", len(g.tokens))}, nil
}

func (g *fakeGemini) Connect(ctx context.Context, token, model string) (phone.Session, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	s := &fakeSession{
		token:  token,
		model:  model,
		server: make(chan *genai.LiveServerMessage, 32),
		lost:   make(chan error, 1),
		closed: make(chan struct{}),
	}
	g.sessions = append(g.sessions, s)
	return s, nil
}

func (g *fakeGemini) tokenConfigs() []*genai.CreateAuthTokenConfig {
	g.mu.Lock()
	defer g.mu.Unlock()
	return append([]*genai.CreateAuthTokenConfig(nil), g.tokens...)
}

func (g *fakeGemini) sessionCount() int {
	g.mu.Lock()
	defer g.mu.Unlock()
	return len(g.sessions)
}

// waitForSession は、n 番目(1 から数える)の Live のセッションが開くのを待つ。
func (g *fakeGemini) waitForSession(t *testing.T, n int) *fakeSession {
	t.Helper()
	waitUntil(t, "Live のセッションが開かなかった", func() bool { return g.sessionCount() >= n })
	g.mu.Lock()
	defer g.mu.Unlock()
	return g.sessions[n-1]
}

// fakeSession は、受け取ったものを記録し、テストが用意したサーバーのメッセージを返す Live のセッションである。
type fakeSession struct {
	token, model string

	server    chan *genai.LiveServerMessage
	lost      chan error
	closed    chan struct{}
	closeOnce sync.Once

	mu         sync.Mutex
	setupSent  bool
	clientSent []any // genai.LiveClientContentInput か genai.LiveRealtimeInput
}

func (s *fakeSession) SendClientContent(input genai.LiveClientContentInput) error {
	return s.record(input)
}

func (s *fakeSession) SendRealtimeInput(input genai.LiveRealtimeInput) error {
	return s.record(input)
}

func (s *fakeSession) record(input any) error {
	if s.isClosed() {
		return errors.New("閉じたセッションに送った")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.clientSent = append(s.clientSent, input)
	return nil
}

// Receive は、genai.Session と同じく、最初に SetupComplete を返す。
func (s *fakeSession) Receive() (*genai.LiveServerMessage, error) {
	s.mu.Lock()
	first := !s.setupSent
	s.setupSent = true
	s.mu.Unlock()
	if first {
		return &genai.LiveServerMessage{SetupComplete: &genai.LiveServerSetupComplete{}}, nil
	}
	select {
	case msg := <-s.server:
		return msg, nil
	case err := <-s.lost:
		return nil, err
	case <-s.closed:
		return nil, errors.New("use of closed network connection")
	}
}

func (s *fakeSession) Close() error {
	s.closeOnce.Do(func() { close(s.closed) })
	return nil
}

func (s *fakeSession) isClosed() bool {
	select {
	case <-s.closed:
		return true
	default:
		return false
	}
}

// reply は、サーバーのメッセージを順に送る。
func (s *fakeSession) reply(msgs ...*genai.LiveServerMessage) {
	for _, msg := range msgs {
		s.server <- msg
	}
}

// drop は、サーバーとの接続を切る。
func (s *fakeSession) drop(err error) { s.lost <- err }

func (s *fakeSession) sent() []any {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]any(nil), s.clientSent...)
}

// sentAudio は、Live のセッションに送られたマイクの音を、送られた順に返す。
func (s *fakeSession) sentAudio() []*genai.Blob {
	var audio []*genai.Blob
	for _, msg := range s.sent() {
		if in, ok := msg.(genai.LiveRealtimeInput); ok && in.Audio != nil {
			audio = append(audio, in.Audio)
		}
	}
	return audio
}

func aiSays(text string) *genai.LiveServerMessage {
	return &genai.LiveServerMessage{ServerContent: &genai.LiveServerContent{
		OutputTranscription: &genai.Transcription{Text: text},
	}}
}

func elderSays(text string) *genai.LiveServerMessage {
	return &genai.LiveServerMessage{ServerContent: &genai.LiveServerContent{
		InputTranscription: &genai.Transcription{Text: text},
	}}
}

func aiAudio(pcm ...byte) *genai.LiveServerMessage {
	return &genai.LiveServerMessage{ServerContent: &genai.LiveServerContent{
		ModelTurn: &genai.Content{Role: genai.RoleModel, Parts: []*genai.Part{
			{InlineData: &genai.Blob{MIMEType: "audio/pcm;rate=24000", Data: pcm}},
		}},
	}}
}

func turnComplete() *genai.LiveServerMessage {
	return &genai.LiveServerMessage{ServerContent: &genai.LiveServerContent{TurnComplete: true}}
}

func interrupted() *genai.LiveServerMessage {
	return &genai.LiveServerMessage{ServerContent: &genai.LiveServerContent{Interrupted: true}}
}

// terminal は、開発者が見るターミナルである。
type terminal struct {
	mu  sync.Mutex
	buf strings.Builder
}

func (w *terminal) Write(p []byte) (int, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.buf.Write(p)
}

func (w *terminal) lines() []string {
	w.mu.Lock()
	defer w.mu.Unlock()
	return strings.Split(strings.TrimSuffix(w.buf.String(), "\n"), "\n")
}

// waitForLines は、ターミナルにこれらの行がこの順に出るのを待つ。
func (w *terminal) waitForLines(t *testing.T, want ...string) {
	t.Helper()
	waitUntil(t, fmt.Sprintf("ターミナルに %q が出なかった", want), func() bool {
		rest := want
		for _, line := range w.lines() {
			if len(rest) > 0 && line == rest[0] {
				rest = rest[1:]
			}
		}
		return len(rest) == 0
	})
}
