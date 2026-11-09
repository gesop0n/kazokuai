package mac

import (
	"bytes"
	"fmt"
	"io"
	"testing"

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

	// 上がったまま電話が終わっても、次の電話は下ろした状態から始まる。
	h.Rest()
	h.Prepare()
	fmt.Fprintln(inW, "")
	if got := <-h.Events(); got != phone.PickedUp {
		t.Fatalf("次の電話の Enter = %v, want 受話器を上げた", got)
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
