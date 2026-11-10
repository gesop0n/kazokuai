package pi

import (
	"bytes"
	"context"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gesop0n/kazokuai/device/phone"
	"github.com/gesop0n/kazokuai/internal/clock"
)

func TestLiftingTheHandsetAnswersAndPuttingItDownEnds(t *testing.T) {
	line := newFakeLine(1)
	var out bytes.Buffer
	h := newHook(line, Config{LiftedWhenClosed: true}, clock.Real{}, &out)
	h.Prepare()
	defer h.Rest()
	<-h.started
	h.Events()

	line.Set(0)
	if got := recv(t, h); got != phone.PickedUp {
		t.Fatalf("上げた = %v", got)
	}
	line.Set(1)
	if got := recv(t, h); got != phone.PutDown {
		t.Fatalf("置いた = %v", got)
	}
	if text := out.String(); !strings.Contains(text, "受話器を上げました。") || !strings.Contains(text, "受話器を置きました。") {
		t.Fatalf("表示 =\n%s", text)
	}
}

func TestHandsetAlreadyUpDoesNotAnswerTheCall(t *testing.T) {
	line := newFakeLine(0)
	h := newHook(line, Config{LiftedWhenClosed: true}, clock.Real{}, &bytes.Buffer{})
	h.Prepare()
	defer h.Rest()
	<-h.started

	select {
	case ev := <-h.Events():
		t.Fatalf("上がったままの受話器で %v を送った", ev)
	default:
	}

	line.Set(1)
	if got := recv(t, h); got != phone.PutDown {
		t.Fatalf("初めから上がっていた受話器を置いた = %v", got)
	}
	line.Set(0)
	if got := recv(t, h); got != phone.PickedUp {
		t.Fatalf("置いてから上げた = %v, want 受話器を上げた", got)
	}
}

func TestOpenMeansLiftedWhenConfigured(t *testing.T) {
	line := newFakeLine(0)
	h := newHook(line, Config{LiftedWhenClosed: false}, clock.Real{}, &bytes.Buffer{})
	h.Prepare()
	defer h.Rest()
	<-h.started
	h.Events()

	line.Set(1)
	if got := recv(t, h); got != phone.PickedUp {
		t.Fatalf("開いた = %v, want 受話器を上げた", got)
	}
}

func TestLiftBeforeThePhoneListensDoesNotAnswer(t *testing.T) {
	line := newFakeLine(1)
	var out bytes.Buffer
	h := newHook(line, Config{LiftedWhenClosed: true}, clock.Real{}, &out)
	h.Prepare()
	defer h.Rest()
	<-h.started

	line.Set(0)
	events := h.Events()
	select {
	case ev := <-events:
		t.Fatalf("呼び出しの前に上げた受話器で %v を送った", ev)
	default:
	}
	if strings.Contains(out.String(), "受話器を上げました。") {
		t.Fatalf("表示 =\n%s", out.String())
	}

	line.Set(1)
	if got := recv(t, h); got != phone.PutDown {
		t.Fatalf("呼び出しの前から上がっていた受話器を置いた = %v", got)
	}
	line.Set(0)
	if got := recv(t, h); got != phone.PickedUp {
		t.Fatalf("呼び出しのあとに置いて上げた = %v", got)
	}
}

func recv(t *testing.T, h *Hook) phone.HookEvent {
	t.Helper()
	select {
	case ev := <-h.Events():
		return ev
	case <-time.After(time.Second):
		t.Fatal("フックの知らせが来なかった")
		return 0
	}
}

func TestCheckHookShowsTheHandsetEvenWhenItStartsUp(t *testing.T) {
	line := newFakeLine(0)
	ctx, cancel := context.WithCancel(context.Background())
	var out safeBuffer
	done := make(chan error, 1)
	go func() {
		done <- Watch(ctx, line, true, 0, clock.Real{}, &out)
	}()
	waitFor(t, &out, "受話器: 上がっている")
	line.Set(1)
	waitFor(t, &out, "受話器: 置かれている")
	cancel()
	if err := <-done; err != context.Canceled {
		t.Fatalf("終わり = %v", err)
	}
}

func waitFor(t *testing.T, buf *safeBuffer, text string) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for !strings.Contains(buf.String(), text) {
		if time.Now().After(deadline) {
			t.Fatalf("表示に %q が無い:\n%s", text, buf.String())
		}
		time.Sleep(time.Millisecond)
	}
}

// safeBuffer は、確認のゴルーチンとテストが同時に読むためのバッファである。
type safeBuffer struct {
	mu sync.Mutex
	bytes.Buffer
}

func (s *safeBuffer) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.Buffer.Write(p)
}

func (s *safeBuffer) String() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.Buffer.String()
}

type fakeLine struct {
	mu      sync.Mutex
	value   int
	changes chan int
}

func newFakeLine(value int) *fakeLine {
	return &fakeLine{value: value, changes: make(chan int, 8)}
}

func (f *fakeLine) Set(value int) {
	f.mu.Lock()
	f.value = value
	f.mu.Unlock()
	f.changes <- value
}

func (f *fakeLine) Value() (int, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.value, nil
}

func (f *fakeLine) Changes() <-chan int { return f.changes }

func (f *fakeLine) Close() error { return nil }
