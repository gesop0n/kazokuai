package phone_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"

	"github.com/gesop0n/kazokuai/device/mac"
	"github.com/gesop0n/kazokuai/device/phone"
	"github.com/gesop0n/kazokuai/device/spoken"
	"github.com/gesop0n/kazokuai/internal/clock"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

// 認証コードのテストは、偽の受話器、フック、キーパッド、バックエンドで電話機を動かす。
// 音声の PCM は、埋め込んである読み上げと比べる。ターミナルの文は仕様の文言そのものである。

const (
	testPhoneID  = "phone-1"
	testPhoneKey = "key-1"
	testCode     = "482751"

	codeSentence      = "認証コードは、4、8、2、7、5、1 です。もう一度お伝えします。4、8、2、7、5、1 です。"
	offlineSentence   = "インターネットにつながっていません。Wi-Fi を確かめてください。"
	failedSentence    = "うまくいきませんでした。しばらくしてから、もう一度シャープを押してください。"
	completedSentence = "同期が完了しました。受話器を置いてください。"

	codeOK      = "ok"
	codeOffline = "offline"
	codeError   = "error"
	codeClosed  = "closed"
	codeBlock   = "block"
)

func TestHashUpPlaysTheCodeAndPlaysItAgain(t *testing.T) {
	r := newCodeRig(t, codeOK)
	code := codePCM(t)
	r.lift()
	r.press("#")
	r.waitAudio(code)
	r.wantText(codeSentence + "\n")

	r.press("#")
	r.waitAudio(twice(code))
	r.wantText(codeSentence + "\n" + codeSentence + "\n")
	if got := r.backend.hits(); got != 2 {
		t.Fatalf("認証コードを頼んだ回数 = %d, want 2", got)
	}
}

func TestUnreachableBackendPlaysTheOfflineSentence(t *testing.T) {
	r := newCodeRig(t, codeOffline)
	r.lift()
	r.press("#")
	r.waitAudio(spoken.Offline())
	r.wantText(offlineSentence + "\n")
}

func TestBackendErrorPlaysTheFailedSentence(t *testing.T) {
	r := newCodeRig(t, codeError)
	r.lift()
	r.press("#")
	r.waitAudio(spoken.Failed())
	r.wantText(failedSentence + "\n")
}

func TestSyncNotReadyPlaysNothing(t *testing.T) {
	r := newCodeRig(t, codeClosed)
	r.lift()
	r.press("#")
	r.waitHits(1)
	r.quiet()
}

func TestOtherKeysAndADownHandsetDoNothing(t *testing.T) {
	r := newCodeRig(t, codeOK)
	r.press("#")
	r.press("1")
	r.press("*")
	r.press("5")
	r.lift()
	r.press("1")
	r.quiet()
	if got := r.backend.hits(); got != 0 {
		t.Fatalf("認証コードを頼んだ回数 = %d, want 0", got)
	}
}

func TestPuttingTheHandsetDownStopsTheAudio(t *testing.T) {
	r := newCodeRig(t, codeOK)
	r.lift()
	r.press("#")
	r.waitAudio(codePCM(t))
	before := r.phone.hushCount()
	r.down()
	if r.phone.hushCount() <= before {
		t.Fatal("受話器を置いても音声が止まらなかった")
	}
}

func TestCodeArrivingAfterPutDownPlaysNothing(t *testing.T) {
	r := newCodeRig(t, codeBlock)
	r.lift()
	r.press("#")
	r.backend.waitEntered(t)
	r.down()
	r.backend.unblock()
	r.quiet()
}

func TestHashDuringACallDoesNothing(t *testing.T) {
	r := newCodeRig(t, codeOK)
	r.send(protocol.PhoneMessage{Type: protocol.PhoneTypeCall, CallID: "call-1"})
	waitUntil(t, "呼び出し音が鳴らなかった", r.phone.isRinging)
	r.press("#")
	r.quiet()
	if got := r.backend.hits(); got != 0 {
		t.Fatalf("電話の最中に認証コードを頼んだ: %d", got)
	}
	if r.phone.micOpen() {
		t.Fatal("置いてある受話器で電話に出た")
	}
}

func TestSyncedSpeaksOnlyWhileTheHandsetIsUp(t *testing.T) {
	r := newCodeRig(t, codeOK)
	r.lift()
	r.send(protocol.PhoneMessage{Type: protocol.PhoneTypeSynced})
	r.waitAudio(spoken.Completed())
	r.wantText(completedSentence + "\n")
}

func TestSyncedWhileDownPlaysNothing(t *testing.T) {
	r := newCodeRig(t, codeOK)
	r.send(protocol.PhoneMessage{Type: protocol.PhoneTypeSynced})
	r.quiet()
	r.lift()
	r.press("#")
	r.waitAudio(codePCM(t))
	r.wantText(codeSentence + "\n")
}

func TestCallWhileSpeakingStopsAndRings(t *testing.T) {
	r := newCodeRig(t, codeOK)
	code := codePCM(t)
	r.lift()
	r.press("#")
	r.waitAudio(code)
	before := r.phone.hushCount()
	r.send(protocol.PhoneMessage{Type: protocol.PhoneTypeCall, CallID: "call-1"})
	waitUntil(t, "呼び出し音が鳴らなかった", r.phone.isRinging)
	if r.phone.hushCount() <= before {
		t.Fatal("電話が来ても音声が止まらなかった")
	}
	if r.phone.micOpen() {
		t.Fatal("上がっていた受話器で電話に出た")
	}
	r.send(protocol.PhoneMessage{Type: protocol.PhoneTypeSynced})
	r.quiet()
	if !bytes.Equal(r.phone.playedAudio(), code) {
		t.Fatal("電話の最中に、完了か別の音声を流した")
	}
	if r.phone.micOpen() || !r.phone.isRinging() {
		t.Fatal("同期の知らせで電話の進み方が変わった")
	}
}

func TestMacHandsetLiftedBeforeACallDoesNotAnswer(t *testing.T) {
	inR, inW := io.Pipe()
	t.Cleanup(func() { inW.Close() })
	out := &lockedBuffer{}
	inner := mac.NewHook(inR, out)
	hook := &readyHook{Hook: inner, ready: make(chan struct{})}
	handset := &fakePhone{}
	backend := newCodeBackend(codeOK)
	srv := httptest.NewServer(backend)
	t.Cleanup(srv.Close)
	runCodeDevice(t, srv, backend, phone.Phone{
		Handset: handset,
		Hook:    hook,
		Keypad:  inner,
		Ringer:  handset,
		Lamp:    handset,
	}, io.Discard, false)

	select {
	case <-hook.ready:
	case <-time.After(waitTimeout):
		t.Fatal("フックの監視が始まらなかった")
	}
	fmt.Fprintln(inW, "")
	waitText(t, out, "受話器を上げました")
	backend.send(t, protocol.PhoneMessage{Type: protocol.PhoneTypeCall, CallID: "call-1"})
	waitUntil(t, "呼び出し音が鳴らなかった", handset.isRinging)
	if handset.micOpen() {
		t.Fatal("上がっていた受話器で電話に出た")
	}
	fmt.Fprintln(inW, "")
	waitText(t, out, "受話器を置きました")
	if handset.micOpen() || !handset.isRinging() {
		t.Fatal("置いたあと、電話に出たか呼び出しが止まった")
	}
	fmt.Fprintln(inW, "")
	waitUntil(t, "上げ直しても出なかった", handset.micOpen)
}

// readyHook は、最初の Prepare が戻ったことをテストに知らせる。
type readyHook struct {
	*mac.Hook
	ready chan struct{}
	once  sync.Once
}

func (h *readyHook) Prepare() {
	h.Hook.Prepare()
	h.once.Do(func() { close(h.ready) })
}

type chanKeys chan string

func (c chanKeys) Keys() <-chan string { return c }

type codeRig struct {
	t       *testing.T
	backend *codeBackend
	phone   *fakePhone
	keys    chan string
	out     *lockedBuffer
}

func newCodeRig(t *testing.T, kind string) *codeRig {
	t.Helper()
	p := &fakePhone{hook: make(chan phone.HookEvent)}
	keys := make(chan string)
	out := &lockedBuffer{}
	backend := newCodeBackend(kind)
	srv := httptest.NewServer(backend)
	t.Cleanup(srv.Close)
	runCodeDevice(t, srv, backend, phone.Phone{
		Handset: p,
		Hook:    p,
		Keypad:  chanKeys(keys),
		Ringer:  p,
		Lamp:    p,
	}, out, true)
	return &codeRig{t: t, backend: backend, phone: p, keys: keys, out: out}
}

func runCodeDevice(t *testing.T, srv *httptest.Server, backend *codeBackend, hw phone.Phone, out io.Writer, echo bool) {
	t.Helper()
	device := &phone.Device{
		Backend: srv.URL,
		Secret:  "secret-test",
		ID:      testPhoneID,
		Key:     testPhoneKey,
		Gemini:  &fakeGemini{},
		Phone:   hw,
		Out:     out,
		Clock:   clock.Real{},
		Echo:    echo,
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- device.Run(ctx) }()
	t.Cleanup(func() {
		backend.unblock()
		cancel()
		select {
		case err := <-done:
			if err != nil && !errors.Is(err, context.Canceled) {
				t.Errorf("電話機が終わった: %v", err)
			}
		case <-time.After(waitTimeout):
			t.Error("電話機が終わらなかった")
		}
	})
	select {
	case <-backend.accepted:
	case <-time.After(waitTimeout):
		t.Fatal("電話機がつながらなかった")
	}
}

func (r *codeRig) lift() {
	r.t.Helper()
	r.sendHook(phone.PickedUp)
	r.sendKey("1")
}

func (r *codeRig) down() {
	r.t.Helper()
	r.sendHook(phone.PutDown)
	r.sendKey("1")
}

func (r *codeRig) press(key string) {
	r.t.Helper()
	r.sendKey(key)
	r.sendKey("1")
}

func (r *codeRig) sendHook(ev phone.HookEvent) {
	r.t.Helper()
	select {
	case r.phone.hook <- ev:
	case <-time.After(waitTimeout):
		r.t.Fatal("フックを受け取らなかった")
	}
}

func (r *codeRig) sendKey(key string) {
	r.t.Helper()
	select {
	case r.keys <- key:
	case <-time.After(waitTimeout):
		r.t.Fatalf("キーを受け取らなかった")
	}
}

func (r *codeRig) send(msg protocol.PhoneMessage) {
	r.t.Helper()
	r.backend.send(r.t, msg)
}

func (r *codeRig) waitAudio(want []byte) {
	r.t.Helper()
	waitUntil(r.t, "音声が流れなかった", func() bool {
		return bytes.Equal(r.phone.playedAudio(), want)
	})
}

func (r *codeRig) wantText(text string) {
	r.t.Helper()
	if got := r.out.String(); got != text {
		r.t.Fatalf("表示 = %q, want %q", got, text)
	}
}

func (r *codeRig) waitHits(n int) {
	r.t.Helper()
	waitUntil(r.t, "認証コードを頼まなかった", func() bool {
		return r.backend.hits() >= n
	})
}

func (r *codeRig) quiet() {
	r.t.Helper()
	before := r.phone.playedAudio()
	text := r.out.String()
	time.Sleep(200 * time.Millisecond)
	after := r.phone.playedAudio()
	if !bytes.Equal(after, before) || r.out.String() != text {
		r.t.Fatalf("音声が %d バイトから %d バイトになり、表示が %q から %q になった", len(before), len(after), text, r.out.String())
	}
}

func codePCM(t *testing.T) []byte {
	t.Helper()
	pcm, err := spoken.Code(testCode)
	if err != nil {
		t.Fatal(err)
	}
	return pcm
}

func twice(pcm []byte) []byte {
	out := make([]byte, 0, len(pcm)*2)
	out = append(out, pcm...)
	return append(out, pcm...)
}

func waitText(t *testing.T, buf *lockedBuffer, text string) {
	t.Helper()
	waitUntil(t, fmt.Sprintf("表示に %q が無い", text), func() bool {
		return strings.Contains(buf.String(), text)
	})
}

type lockedBuffer struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (l *lockedBuffer) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.b.Write(p)
}

func (l *lockedBuffer) String() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.b.String()
}

type codeBackend struct {
	kind        string
	mu          sync.Mutex
	n           int
	conn        *websocket.Conn
	accepted    chan struct{}
	onceAccept  sync.Once
	entered     chan struct{}
	release     chan struct{}
	onceRelease sync.Once
	onceEntered sync.Once
}

func newCodeBackend(kind string) *codeBackend {
	return &codeBackend{
		kind:     kind,
		accepted: make(chan struct{}),
		entered:  make(chan struct{}),
		release:  make(chan struct{}),
	}
}

func (s *codeBackend) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch {
	case r.Method == http.MethodPost && r.URL.Path == protocol.PhoneRegisterPath:
		w.WriteHeader(http.StatusCreated)
	case r.URL.Path == protocol.PhonePath:
		s.acceptPhone(w, r)
	case r.Method == http.MethodPost && r.URL.Path == protocol.PhoneCodePath:
		s.issueCode(w, r)
	case r.Method == http.MethodPost && r.URL.Path == protocol.TokenPath:
		s.issueToken(w)
	case r.Method == http.MethodPost && r.URL.Path == protocol.CallReportPath:
		w.WriteHeader(http.StatusAccepted)
	default:
		http.NotFound(w, r)
	}
}

func (s *codeBackend) acceptPhone(w http.ResponseWriter, r *http.Request) {
	if !phoneHeaders(r) {
		http.Error(w, "認証が違います", http.StatusUnauthorized)
		return
	}
	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{InsecureSkipVerify: true})
	if err != nil {
		return
	}
	s.mu.Lock()
	s.conn = conn
	s.mu.Unlock()
	s.onceAccept.Do(func() { close(s.accepted) })
	for {
		if _, _, err := conn.Read(r.Context()); err != nil {
			return
		}
	}
}

func (s *codeBackend) issueCode(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	s.n++
	s.mu.Unlock()
	if !phoneHeaders(r) {
		http.Error(w, "認証が違います", http.StatusUnauthorized)
		return
	}
	switch s.kind {
	case codeOffline:
		hj, ok := w.(http.Hijacker)
		if !ok {
			http.Error(w, "切れません", http.StatusBadGateway)
			return
		}
		conn, _, err := hj.Hijack()
		if err != nil {
			return
		}
		conn.Close()
	case codeError:
		http.Error(w, "だめ", http.StatusInternalServerError)
	case codeClosed:
		http.Error(w, protocol.PhoneAnswerSyncClosed, http.StatusConflict)
	case codeBlock:
		s.onceEntered.Do(func() { close(s.entered) })
		<-s.release
		writeCode(w)
	default:
		writeCode(w)
	}
}

func writeCode(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"code":"` + testCode + `"}`))
}

func (s *codeBackend) issueToken(w http.ResponseWriter) {
	body, err := json.Marshal(protocol.TokenResponse{
		Token: "token-test",
		Model: "model-test",
		Times: protocol.CallTimes{
			RingTimeout:  time.Minute,
			MaxCall:      time.Hour,
			WrapUpBefore: time.Minute,
		},
	})
	if err != nil {
		http.Error(w, "作れなかった", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Write(body)
}

func phoneHeaders(r *http.Request) bool {
	return r.Header.Get(protocol.PhoneIDHeader) == testPhoneID && r.Header.Get(protocol.PhoneKeyHeader) == testPhoneKey
}

func (s *codeBackend) hits() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.n
}

func (s *codeBackend) waitEntered(t *testing.T) {
	t.Helper()
	select {
	case <-s.entered:
	case <-time.After(waitTimeout):
		t.Fatal("認証コードのリクエストが来なかった")
	}
}

func (s *codeBackend) unblock() {
	s.onceRelease.Do(func() { close(s.release) })
}

func (s *codeBackend) send(t *testing.T, msg protocol.PhoneMessage) {
	t.Helper()
	s.mu.Lock()
	conn := s.conn
	s.mu.Unlock()
	if conn == nil {
		t.Fatal("WebSocket が無い")
	}
	body, err := json.Marshal(msg)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), waitTimeout)
	defer cancel()
	if err := conn.Write(ctx, websocket.MessageText, body); err != nil {
		t.Fatalf("知らせを送れなかった: %v", err)
	}
}
