package mac

import (
	"bytes"
	"fmt"
	"io"
	"testing"
	"time"

	"github.com/gesop0n/kazokuai/device/phone"
)

func TestIdleEnterDoesNotAnswerTheNextCall(t *testing.T) {
	inR, inW := io.Pipe()
	defer inW.Close()
	h := NewHook(inR, &bytes.Buffer{})

	fmt.Fprintln(inW, "")
	waitUntil(t, "Enter が残らなかった", func() bool { return len(h.presses) == 1 })

	h.Prepare()
	if len(h.presses) != 0 {
		t.Fatal("待っていた Enter が残っている")
	}
	select {
	case ev := <-h.Events():
		t.Fatalf("待っていた Enter で %v を送った", ev)
	case <-time.After(100 * time.Millisecond):
	}

	fmt.Fprintln(inW, "")
	if got := readHook(t, h); got != phone.PickedUp {
		t.Fatalf("次の Enter = %v, want 受話器を上げた", got)
	}

	// 上がったまま電話が終わっても、次の電話は下ろした状態から始まる。
	h.Rest()
	h.Prepare()
	fmt.Fprintln(inW, "")
	if got := readHook(t, h); got != phone.PickedUp {
		t.Fatalf("次の電話の Enter = %v, want 受話器を上げた", got)
	}
}

func readHook(t *testing.T, h *Hook) phone.HookEvent {
	t.Helper()
	select {
	case ev := <-h.Events():
		return ev
	case <-time.After(time.Second):
		t.Fatal("待っても受話器の上げ下げが来なかった")
		return 0
	}
}

func waitUntil(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatal("待っても" + what)
		}
		time.Sleep(time.Millisecond)
	}
}
