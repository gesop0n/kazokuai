package pi

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"
	"google.golang.org/genai"

	"github.com/gesop0n/kazokuai/device/phone"
	"github.com/gesop0n/kazokuai/internal/clock"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

// 呼び出し中に置いても、出なかった電話はそこで終わらない。
// 戻った待機は置いた受話器から始まるので、「＃」も同期の知らせも何もしない。
func TestDownHandsetAfterMissedCallDoesNotRequestCode(t *testing.T) {
	var codes hitCount
	connections := make(chan *websocket.Conn, 1)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case protocol.PhoneRegisterPath:
			w.WriteHeader(http.StatusCreated)
		case protocol.PhonePath:
			conn, err := websocket.Accept(w, r, nil)
			if err != nil {
				return
			}
			defer conn.CloseNow()
			connections <- conn
			for {
				if _, _, err := conn.Read(r.Context()); err != nil {
					return
				}
			}
		case protocol.PhoneCodePath:
			codes.add()
			io.WriteString(w, `{"code":"482751"}`)
		case protocol.TokenPath:
			if err := json.NewEncoder(w).Encode(protocol.TokenResponse{
				Token: "token-test",
				Model: "model-test",
				Times: protocol.CallTimes{RingTimeout: 300 * time.Millisecond, MaxCall: time.Minute},
			}); err != nil {
				http.Error(w, "encode", http.StatusInternalServerError)
			}
		default:
			w.WriteHeader(http.StatusAccepted)
		}
	}))
	defer srv.Close()

	line := newFakeLine(1)
	var hookOut safeBuffer
	hook := newHook(line, Config{LiftedWhenClosed: true}, clock.Real{}, &hookOut)
	keys := make(chan string, 1)
	handset := &recordingHandset{ring: make(chan struct{}, 1)}
	finished := make(chan struct{}, 1)
	d := &phone.Device{
		Backend:  srv.URL,
		Identity: phone.Identity{ID: "phone-1", Key: "key-1"},
		Secret:   "secret-test",
		Gemini:   silentGemini{},
		Phone: phone.Phone{
			Handset: handset,
			Hook:    hook,
			Keypad:  chanKeys(keys),
			Ringer:  handset,
			Lamp:    handset,
		},
		Out:   io.Discard,
		Clock: clock.Real{},
		AfterCall: func(error) {
			finished <- struct{}{}
		},
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- d.Run(ctx) }()
	defer func() {
		cancel()
		select {
		case <-done:
		case <-time.After(2 * time.Second):
			t.Error("電話機が終わらなかった")
		}
	}()

	var conn *websocket.Conn
	select {
	case conn = <-connections:
	case <-time.After(time.Second):
		t.Fatal("電話機がつながらなかった")
	}
	waitUntil(t, "待機のフックが始まらなかった", func() bool { return hookArmed(hook) })
	hook.mu.Lock()
	idleStopped := hook.stopped
	hook.mu.Unlock()

	line.Set(0)
	waitUntil(t, "受話器を上げたことが出なかった", func() bool {
		return strings.Contains(hookOut.String(), "受話器を上げました。")
	})
	requestCode(t, keys, &codes)
	quiesce(t, &codes)
	waitUntil(t, "上げた受話器で認証コードを流さなかった", func() bool { return len(handset.audio()) > 0 })
	baseline := codes.get()

	body, err := json.Marshal(protocol.PhoneMessage{Type: protocol.PhoneTypeCall, CallID: "call-1"})
	if err != nil {
		t.Fatal(err)
	}
	if err := conn.Write(ctx, websocket.MessageText, body); err != nil {
		t.Fatal(err)
	}
	select {
	case <-handset.ring:
	case <-time.After(time.Second):
		t.Fatal("呼び出し音が鳴らなかった")
	}
	waitUntil(t, "呼び出しのフックが始まらなかった", func() bool {
		hook.mu.Lock()
		stopped := hook.stopped
		hook.mu.Unlock()
		return stopped != idleStopped && hookArmed(hook)
	})
	hook.mu.Lock()
	callStopped := hook.stopped
	hook.mu.Unlock()

	line.Set(1)
	select {
	case <-finished:
	case <-time.After(time.Second):
		t.Fatal("出なかった電話が終わらなかった")
	}
	waitUntil(t, "待機のフックが戻らなかった", func() bool {
		hook.mu.Lock()
		stopped := hook.stopped
		hook.mu.Unlock()
		return stopped != callStopped && hookArmed(hook)
	})

	spoken := len(handset.audio())
	select {
	case keys <- "#":
	case <-time.After(time.Second):
		t.Fatal("置いたあとの「＃」を受け取らなかった")
	}
	synced, err := json.Marshal(protocol.PhoneMessage{Type: protocol.PhoneTypeSynced})
	if err != nil {
		t.Fatal(err)
	}
	if err := conn.Write(ctx, websocket.MessageText, synced); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(200 * time.Millisecond)
	codeRequested := false
	spoke := false
	for time.Now().Before(deadline) {
		if codes.get() > baseline {
			codeRequested = true
		}
		if len(handset.audio()) > spoken {
			spoke = true
		}
		time.Sleep(time.Millisecond)
	}
	if codeRequested || spoke {
		t.Fatalf("置いた受話器で認証コードを頼んだ=%v 音声を流した=%v", codeRequested, spoke)
	}
}

// 受話器が上がったまま待ち始めると、認証コードの途中で置いたときに音声が止まり、そのあとの「＃」は何もしない。
func TestPuttingDownAHandsetThatStartedUpStopsTheCode(t *testing.T) {
	var codes hitCount
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case protocol.PhoneRegisterPath:
			w.WriteHeader(http.StatusCreated)
		case protocol.PhonePath:
			conn, err := websocket.Accept(w, r, nil)
			if err != nil {
				return
			}
			defer conn.CloseNow()
			for {
				if _, _, err := conn.Read(r.Context()); err != nil {
					return
				}
			}
		case protocol.PhoneCodePath:
			codes.add()
			io.WriteString(w, `{"code":"482751"}`)
		default:
			w.WriteHeader(http.StatusAccepted)
		}
	}))
	defer srv.Close()

	// 0 は閉じている。閉じると上がる設定なので、受話器はすでに上がっている。
	line := newFakeLine(0)
	hook := newHook(line, Config{LiftedWhenClosed: true}, clock.Real{}, io.Discard)
	keys := make(chan string, 1)
	handset := &recordingHandset{}
	d := &phone.Device{
		Backend:  srv.URL,
		Identity: phone.Identity{ID: "phone-1", Key: "key-1"},
		Secret:   "secret-test",
		Gemini:   silentGemini{},
		Phone: phone.Phone{
			Handset: handset,
			Hook:    hook,
			Keypad:  chanKeys(keys),
			Ringer:  handset,
			Lamp:    handset,
		},
		Out:   io.Discard,
		Clock: clock.Real{},
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- d.Run(ctx) }()
	defer func() {
		cancel()
		select {
		case <-done:
		case <-time.After(2 * time.Second):
			t.Error("電話機が終わらなかった")
		}
	}()

	waitUntil(t, "待機のフックが始まらなかった", func() bool { return hookArmed(hook) })
	requestCode(t, keys, &codes)
	quiesce(t, &codes)
	waitUntil(t, "上げたままの受話器で認証コードを流さなかった", func() bool { return len(handset.audio()) > 0 })
	baseline := codes.get()
	spoken := len(handset.audio())
	before := handset.hushCount()

	line.Set(1)
	waitUntil(t, "置いても音声が止まらなかった", func() bool { return handset.hushCount() > before })

	select {
	case keys <- "#":
	case <-time.After(time.Second):
		t.Fatal("置いたあとの「＃」を受け取らなかった")
	}
	deadline := time.Now().Add(200 * time.Millisecond)
	for time.Now().Before(deadline) {
		if codes.get() > baseline {
			t.Fatal("置いたあとの「＃」が認証コードを頼んだ")
		}
		if got := len(handset.audio()); got != spoken {
			t.Fatalf("置いたあとの音声 = %d バイト, want %d", got, spoken)
		}
		time.Sleep(time.Millisecond)
	}
}

func waitUntil(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatalf("待っても%s", what)
		}
		time.Sleep(time.Millisecond)
	}
}

func hookArmed(h *Hook) bool {
	h.mu.Lock()
	armed := h.armed
	h.mu.Unlock()
	if armed == nil {
		return false
	}
	select {
	case <-armed:
		return true
	default:
		return false
	}
}

func requestCode(t *testing.T, keys chan string, codes *hitCount) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for codes.get() == 0 {
		select {
		case keys <- "#":
		default:
		}
		if time.Now().After(deadline) {
			t.Fatal("上げた受話器の「＃」が認証コードを頼まなかった")
		}
		time.Sleep(time.Millisecond)
	}
}

func quiesce(t *testing.T, codes *hitCount) {
	t.Helper()
	stable := codes.get()
	deadline := time.Now().Add(200 * time.Millisecond)
	for time.Now().Before(deadline) {
		if got := codes.get(); got != stable {
			stable = got
			deadline = time.Now().Add(200 * time.Millisecond)
		}
		time.Sleep(time.Millisecond)
	}
}

type hitCount struct {
	mu sync.Mutex
	n  int
}

func (h *hitCount) add() {
	h.mu.Lock()
	h.n++
	h.mu.Unlock()
}

func (h *hitCount) get() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.n
}

type chanKeys chan string

func (k chanKeys) Keys() <-chan string { return k }

type recordingHandset struct {
	ring chan struct{}

	mu     sync.Mutex
	pcm    []byte
	hushes int
}

func (h *recordingHandset) Listen(context.Context) (<-chan []byte, error) { return nil, nil }
func (h *recordingHandset) Play(pcm []byte) {
	h.mu.Lock()
	h.pcm = append(h.pcm, pcm...)
	h.mu.Unlock()
}
func (h *recordingHandset) Hush() {
	h.mu.Lock()
	h.hushes++
	h.mu.Unlock()
}
func (h *recordingHandset) hushCount() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.hushes
}
func (h *recordingHandset) Ring() { h.ring <- struct{}{} }
func (h *recordingHandset) Stop() {}
func (h *recordingHandset) On()   {}
func (h *recordingHandset) Off()  {}

func (h *recordingHandset) audio() []byte {
	h.mu.Lock()
	defer h.mu.Unlock()
	return append([]byte(nil), h.pcm...)
}

type silentGemini struct{}

func (silentGemini) Connect(context.Context, string, string) (phone.Session, error) {
	return &silentSession{done: make(chan struct{})}, nil
}

type silentSession struct {
	once sync.Once
	done chan struct{}
}

func (*silentSession) SendClientContent(genai.LiveClientContentInput) error { return nil }
func (*silentSession) SendRealtimeInput(genai.LiveRealtimeInput) error      { return nil }
func (s *silentSession) Receive() (*genai.LiveServerMessage, error) {
	<-s.done
	return nil, io.EOF
}
func (s *silentSession) Close() error {
	s.once.Do(func() { close(s.done) })
	return nil
}
