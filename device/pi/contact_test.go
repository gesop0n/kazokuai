package pi

import (
	"testing"
	"time"

	"github.com/gesop0n/kazokuai/device/phone"
)

func TestDebounceIgnoresABounceShorterThanFiftyMilliseconds(t *testing.T) {
	// tel-base のデバウンスと同じ時刻で、短い揺れは受話器が上がったことにしない。
	start := time.Unix(1, 0)
	d := newDebouncer(0, start, 50*time.Millisecond)

	if got := d.update(1, start); got != 0 {
		t.Fatalf("変化した瞬間 = %d, want 0", got)
	}
	if got := d.update(0, start.Add(20*time.Millisecond)); got != 0 {
		t.Fatalf("20ms で戻った = %d, want 0", got)
	}
	if got := d.update(1, start.Add(30*time.Millisecond)); got != 0 {
		t.Fatalf("30ms で再び変化 = %d, want 0", got)
	}
	if got := d.update(1, start.Add(80*time.Millisecond)); got != 1 {
		t.Fatalf("50ms 安定した = %d, want 1", got)
	}
}

func TestLiftHeldForFiftyMillisecondsAnswers(t *testing.T) {
	start := time.Unix(0, 0)
	// 1 は開いている接点。上げると閉じる設定では、開いているのが置いた状態。
	c := newContact(1, start, true, 50*time.Millisecond)

	if _, ok := c.level(0, start); ok {
		t.Fatal("閉じた瞬間に電話に出た")
	}
	if _, ok := c.level(0, start.Add(49*time.Millisecond)); ok {
		t.Fatal("49ms で電話に出た")
	}
	got, ok := c.level(0, start.Add(50*time.Millisecond))
	if !ok || got != phone.PickedUp {
		t.Fatalf("50ms = %v, %v, want 受話器を上げた", got, ok)
	}
	if _, ok := c.level(1, start.Add(100*time.Millisecond)); ok {
		t.Fatal("開き始めた瞬間に置いたことにした")
	}
	got, ok = c.level(1, start.Add(150*time.Millisecond))
	if !ok || got != phone.PutDown {
		t.Fatalf("置いた = %v, %v, want 受話器を置いた", got, ok)
	}
}

func TestHookPolarity(t *testing.T) {
	start := time.Unix(0, 0)
	for _, closedMeansUp := range []bool{true, false} {
		// 0 は閉じている。デバウンス 0 なので、そのレベルの意味がすぐ出る。
		c := newContact(1, start, closedMeansUp, 0)
		got, ok := c.level(0, start)
		wantUp := closedMeansUp
		if wantUp {
			if !ok || got != phone.PickedUp {
				t.Fatalf("閉じると上がる設定で、閉じた = %v, %v", got, ok)
			}
		} else if !ok || got != phone.PutDown {
			t.Fatalf("開くと上がる設定で、初めから上がっていた受話器を閉じた = %v, %v", got, ok)
		}
		got, ok = c.level(1, start)
		if wantUp {
			if !ok || got != phone.PutDown {
				t.Fatalf("閉じると上がる設定で、開いた = %v, %v", got, ok)
			}
		} else if !ok || got != phone.PickedUp {
			t.Fatalf("開くと上がる設定で、開いた = %v, %v", got, ok)
		}
	}
}

func TestHandsetAlreadyUpDoesNotAnswerUntilItIsPutDown(t *testing.T) {
	start := time.Unix(0, 0)
	// 始めから閉じている。上げると閉じる設定なので、受話器はすでに上がっている。
	c := newContact(0, start, true, 50*time.Millisecond)

	if _, ok := c.level(0, start.Add(time.Second)); ok {
		t.Fatal("上がったままの受話器が電話に出た")
	}
	down := start.Add(time.Second)
	if _, ok := c.level(1, down); ok {
		t.Fatal("置き始めた瞬間に出来事にした")
	}
	got, ok := c.level(1, down.Add(50*time.Millisecond))
	if !ok || got != phone.PutDown {
		t.Fatalf("初めから上がっていた受話器を置いた = %v, %v, want 受話器を置いた", got, ok)
	}
	up := down.Add(time.Second)
	if _, ok := c.level(0, up); ok {
		t.Fatal("上げ始めた瞬間に電話に出た")
	}
	got, ok = c.level(0, up.Add(50*time.Millisecond))
	if !ok || got != phone.PickedUp {
		t.Fatalf("置いてから上げた = %v, %v, want 受話器を上げた", got, ok)
	}
}
