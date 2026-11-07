package phone_test

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"google.golang.org/genai"

	"github.com/gesop0n/kazokuai/backend/server"
	"github.com/gesop0n/kazokuai/device/phone"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

// テストの境目の外側だけを偽物にする。偽物は電話機、時計、Gemini の 3 つで、
// デバイスの電話の処理、その HTTP のクライアント、バックエンドの HTTP のサーバー、Firebase のエミュレーターは本物を動かす。

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
	clock    *fakeClock
	backend  *httptest.Server
	// reportHold は、電話の報告の応答をテストが返すまで止める。止めていなければ素通りする。
	reportHold reportHold
}

func newSystem(t *testing.T, config server.Config, now time.Time) *system {
	t.Helper()
	gemini := &fakeGemini{}
	clock := &fakeClock{now: now}
	s := &system{}
	handler := server.New(config, emulators, gemini, gemini, clock)
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.reportHold.wait(r.URL.Path)
		handler.ServeHTTP(w, r)
	}))
	t.Cleanup(backend.Close)
	p := &fakePhone{hook: make(chan phone.HookEvent, 4)}
	term := &terminal{}
	s.phone = p
	s.gemini = gemini
	s.terminal = term
	s.clock = clock
	s.backend = backend
	s.device = &phone.Device{
		Backend: backend.URL,
		Gemini:  gemini,
		Phone:   phone.Phone{Handset: p, Hook: p, Ringer: p, Lamp: p},
		Out:     term,
		Clock:   clock,
	}
	return s
}

// holdReport は、このあとの電話の報告に、releaseReport まで応答しないようにする。
func (s *system) holdReport() { s.reportHold.arm() }

// releaseReport は、止めていた電話の報告の応答を返す。
func (s *system) releaseReport() { s.reportHold.release() }

// reportArrived は、電話の報告がバックエンドに届き、応答を待っているかを返す。
func (s *system) reportArrived() bool { return s.reportHold.arrived() }

// reportHold は、電話の報告の HTTP 応答を止める。
type reportHold struct {
	mu      sync.Mutex
	entered chan struct{}
	gate    chan struct{}
	seen    bool
}

func (h *reportHold) arm() {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.entered = make(chan struct{})
	h.gate = make(chan struct{})
	h.seen = false
}

func (h *reportHold) release() {
	h.mu.Lock()
	ch := h.gate
	h.gate = nil
	h.mu.Unlock()
	if ch != nil {
		close(ch)
	}
}

func (h *reportHold) arrived() bool {
	h.mu.Lock()
	entered := h.entered
	h.mu.Unlock()
	if entered == nil {
		return false
	}
	select {
	case <-entered:
		return true
	default:
		return false
	}
}

func (h *reportHold) wait(path string) {
	if path != protocol.CallReportPath {
		return
	}
	h.mu.Lock()
	entered, gate, seen := h.entered, h.gate, h.seen
	if gate != nil && !seen {
		h.seen = true
	} else {
		entered = nil
	}
	h.mu.Unlock()
	if entered != nil {
		close(entered)
	}
	if gate != nil {
		<-gate
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

// advance は時計を d 進める。期限が来ていたら、デバイスがそれを扱うのを少し待つ。
// 期限が来ていなければ待たない。その時刻には、デバイスに知らせるものがない。
func (s *system) advance(t *testing.T, c *call, d time.Duration) {
	t.Helper()
	if s.clock.advance(d) == 0 {
		return
	}
	select {
	case <-c.ended:
	case <-time.After(200 * time.Millisecond):
	}
}

// fakeClock は偽の時計である。advance で、待たずに時刻を進める。
type fakeClock struct {
	mu      sync.Mutex
	now     time.Time
	waiters []*fakeTimer
}

func (c *fakeClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

func (c *fakeClock) NewTimer(d time.Duration) phone.Timer {
	c.mu.Lock()
	defer c.mu.Unlock()
	timer := &fakeTimer{
		clock:    c,
		deadline: c.now.Add(d),
		ch:       make(chan time.Time, 1),
	}
	if d <= 0 {
		timer.ch <- c.now
		return timer
	}
	c.waiters = append(c.waiters, timer)
	return timer
}

// advance は、時計を d 進め、その時刻までに期限が来たタイマーへ知らせる。知らせた数を返す。
func (c *fakeClock) advance(d time.Duration) int {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.now = c.now.Add(d)
	fired := 0
	pending := make([]*fakeTimer, 0, len(c.waiters))
	for _, timer := range c.waiters {
		if timer.stopped {
			continue
		}
		if !timer.deadline.After(c.now) {
			timer.ch <- c.now
			fired++
			continue
		}
		pending = append(pending, timer)
	}
	c.waiters = pending
	return fired
}

type fakeTimer struct {
	clock    *fakeClock
	deadline time.Time
	ch       chan time.Time
	stopped  bool
}

func (t *fakeTimer) Chan() <-chan time.Time { return t.ch }

func (t *fakeTimer) Stop() {
	t.clock.mu.Lock()
	defer t.clock.mu.Unlock()
	t.stopped = true
}

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

func (p *fakePhone) micOpen() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.mic != nil
}

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

// summaryRequest は、まとめのために Gemini に届いた 1 回の generateContent である。
type summaryRequest struct {
	model    string
	contents []*genai.Content
	config   *genai.GenerateContentConfig
}

// fakeGemini は偽の Gemini である。トークンを作るときの制約を記録し、
// Live のセッションとして fakeSession を開き、まとめの generateContent に決めた応答を返す。
type fakeGemini struct {
	mu       sync.Mutex
	tokens   []*genai.CreateAuthTokenConfig
	sessions []*fakeSession

	summaries   []summaryRequest
	summaryGate chan struct{}
	summaryOnce sync.Once
	summaryResp *genai.GenerateContentResponse
	summaryErr  error
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

// holdSummary は、generateContent が releaseSummary まで応答を返さないようにする。
func (g *fakeGemini) holdSummary() {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.summaryGate = make(chan struct{})
	g.summaryOnce = sync.Once{}
}

// releaseSummary は、止めていた generateContent の応答を返す。
func (g *fakeGemini) releaseSummary() {
	g.mu.Lock()
	gate := g.summaryGate
	g.mu.Unlock()
	if gate == nil {
		return
	}
	g.summaryOnce.Do(func() { close(gate) })
}

// setSummary は、generateContent が返すまとめを決める。
func (g *fakeGemini) setSummary(resp *genai.GenerateContentResponse) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.summaryResp = resp
	g.summaryErr = nil
}

// failSummary は、generateContent を毎回失敗させる。
func (g *fakeGemini) failSummary(err error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.summaryErr = err
	g.summaryResp = nil
}

func (g *fakeGemini) GenerateContent(ctx context.Context, model string, contents []*genai.Content, config *genai.GenerateContentConfig) (*genai.GenerateContentResponse, error) {
	g.mu.Lock()
	g.summaries = append(g.summaries, summaryRequest{model: model, contents: contents, config: config})
	gate := g.summaryGate
	resp := g.summaryResp
	err := g.summaryErr
	g.mu.Unlock()
	if gate != nil {
		select {
		case <-gate:
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}
	if err != nil {
		return nil, err
	}
	if resp == nil {
		resp = summaryResponse(`{"headline":"","quote":{"text":"","offsetMs":0},"meal":{"status":"話していない","said":"","quote":"","concerning":false},"sleep":{"status":"話していない","said":"","quote":"","concerning":false},"health":{"status":"話していない","said":"","quote":"","concerning":false},"topic":"話し相手","points":[]}`)
	}
	return resp, nil
}

func (g *fakeGemini) summaryRequests() []summaryRequest {
	g.mu.Lock()
	defer g.mu.Unlock()
	return append([]summaryRequest(nil), g.summaries...)
}

func summaryResponse(text string) *genai.GenerateContentResponse {
	return &genai.GenerateContentResponse{
		Candidates: []*genai.Candidate{{
			Content: &genai.Content{
				Role:  genai.RoleModel,
				Parts: []*genai.Part{{Text: text}},
			},
		}},
	}
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
	stalled    bool  // true なら、送ったものは接続が閉じるまで届かない
	clientSent []any // genai.LiveClientContentInput か genai.LiveRealtimeInput
}

func (s *fakeSession) SendClientContent(input genai.LiveClientContentInput) error {
	return s.record(input)
}

func (s *fakeSession) SendRealtimeInput(input genai.LiveRealtimeInput) error {
	return s.record(input)
}

func (s *fakeSession) record(input any) error {
	s.mu.Lock()
	stalled := s.stalled
	s.mu.Unlock()
	if stalled {
		// 上りの回線が止まり、書き込みが接続を閉じるまで戻らない
		<-s.closed
	}
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

// stall は、上りの回線を止める。そのあとに送ったものは、接続が閉じるまで書き込みから戻らない。
func (s *fakeSession) stall() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.stalled = true
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

func outputTranscription(text string) *genai.LiveServerMessage {
	return &genai.LiveServerMessage{ServerContent: &genai.LiveServerContent{
		OutputTranscription: &genai.Transcription{Text: text},
	}}
}

func inputTranscription(text string) *genai.LiveServerMessage {
	return &genai.LiveServerMessage{ServerContent: &genai.LiveServerContent{
		InputTranscription: &genai.Transcription{Text: text},
	}}
}

// finished は、文字起こしに、その発話の終わりの印を付ける。
func finished(msg *genai.LiveServerMessage) *genai.LiveServerMessage {
	for _, transcription := range []*genai.Transcription{
		msg.ServerContent.InputTranscription,
		msg.ServerContent.OutputTranscription,
	} {
		if transcription != nil {
			transcription.Finished = true
		}
	}
	return msg
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

func (w *terminal) text() string {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.buf.String()
}

func (w *terminal) lines() []string {
	return strings.Split(strings.TrimSuffix(w.text(), "\n"), "\n")
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
