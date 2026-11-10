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
	waitPending(t, h)

	h.Prepare()
	select {
	case ev := <-h.Events():
		t.Fatalf("待っていた Enter で %v を送った", ev)
	default:
	}

	fmt.Fprintln(inW, "")
	if got := <-h.Events(); got != phone.PickedUp {
		t.Fatalf("次の Enter = %v, want 受話器を上げた", got)
	}

	// 上がったまま次の監視が始まっても、空の行は置く方になる。上がった受話器では電話に出ない。
	h.Rest()
	h.Prepare()
	fmt.Fprintln(inW, "")
	if got := <-h.Events(); got != phone.PutDown {
		t.Fatalf("上がったままの次の Enter = %v, want 受話器を置いた", got)
	}
}

func TestHashLineIsAKeyAndNotTheHook(t *testing.T) {
	inR, inW := io.Pipe()
	defer inW.Close()
	h := NewHook(inR, &bytes.Buffer{})

	fmt.Fprintln(inW, "#")
	if got := readKey(t, h); got != "#" {
		t.Fatalf("キー = %q, want #", got)
	}
	fmt.Fprintln(inW, "*")
	if got := readKey(t, h); got != "*" {
		t.Fatalf("キー = %q, want *", got)
	}
	fmt.Fprintln(inW, "5")
	if got := readKey(t, h); got != "5" {
		t.Fatalf("キー = %q, want 5", got)
	}

	h.Prepare()
	select {
	case ev := <-h.Events():
		t.Fatalf("キーで %v を送った", ev)
	default:
	}
}

func readKey(t *testing.T, h *Hook) string {
	t.Helper()
	select {
	case got := <-h.Keys():
		return got
	case <-time.After(time.Second):
		t.Fatal("キーが届かなかった")
		return ""
	}
}

// waitPending は、Enter がフックに届くまで待つ。時計では待たない。
func waitPending(t *testing.T, h *Hook) {
	t.Helper()
	h.mu.Lock()
	defer h.mu.Unlock()
	for !h.pending {
		h.cond.Wait()
	}
}
