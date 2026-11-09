package pi

import (
	"bytes"
	"context"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gesop0n/kazokuai/internal/clock/clocktest"
)

func TestKeypadReportsOnePressAndDoesNotRepeatWhileHeld(t *testing.T) {
	clk := clocktest.New(time.Unix(0, 0))
	cfg := loadedKeypad(t, func(string) string { return "" })
	m := newMatrix(len(cfg.Rows), len(cfg.Cols))
	k := mustKeypad(t, m, cfg.Keys, cfg.Debounce, clk)

	// 1 は左上。行を戻さないと次の行でもその列が低く見え、この押下は出ない。
	m.Hold(0, 0)
	if got := readStable(t, k, clk); got != "1" {
		t.Fatalf("1 回の押下 = %q, want 1", got)
	}
	if m.anyDriven() {
		t.Fatal("走査のあと行が低いまま")
	}
	clk.Advance(time.Second)
	if got, err := k.ReadKey(); err != nil || got != "" {
		t.Fatalf("押したまま = %q, %v", got, err)
	}

	releaseStable(t, k, clk, m)
	// 5 は上から 2 行目、左から 2 列目。実機で確かめてあるのはこのキーだけ。
	m.Hold(1, 1)
	if got := readStable(t, k, clk); got != "5" {
		t.Fatalf("次の押下 = %q, want 5", got)
	}
}

func TestKeypadSaysNothingUntilEveryKeyIsReleased(t *testing.T) {
	clk := clocktest.New(time.Unix(0, 0))
	cfg := loadedKeypad(t, func(string) string { return "" })
	m := newMatrix(len(cfg.Rows), len(cfg.Cols))
	k := mustKeypad(t, m, cfg.Keys, cfg.Debounce, clk)

	// 1 が安定する前に 5 も押して、すぐ 5 だけ離す。残った 1 は、全部離すまで出さない。
	m.Hold(0, 0)
	if got, err := k.ReadKey(); err != nil || got != "" {
		t.Fatalf("押した瞬間 = %q, %v", got, err)
	}
	clk.Advance(20 * time.Millisecond)
	m.Hold(1, 1)
	if got, err := k.ReadKey(); err != nil || got != "" {
		t.Fatalf("2 個 = %q, %v", got, err)
	}
	m.Release(1, 1)
	if got, err := k.ReadKey(); err != nil || got != "" {
		t.Fatalf("5 を離した瞬間 = %q, %v", got, err)
	}
	clk.Advance(30 * time.Millisecond)
	if got, err := k.ReadKey(); err != nil || got != "" {
		t.Fatalf("残った 1 = %q, %v", got, err)
	}

	m.Hold(1, 1)
	if got, err := k.ReadKey(); err != nil || got != "" {
		t.Fatalf("再び 2 個 = %q, %v", got, err)
	}
	clk.Advance(30 * time.Millisecond)
	if got, err := k.ReadKey(); err != nil || got != "" {
		t.Fatalf("2 個が安定 = %q, %v", got, err)
	}
	m.Release(1, 1)
	if got, err := k.ReadKey(); err != nil || got != "" {
		t.Fatalf("1 個に戻した瞬間 = %q, %v", got, err)
	}
	clk.Advance(30 * time.Millisecond)
	if got, err := k.ReadKey(); err != nil || got != "" {
		t.Fatalf("残った 1 が安定 = %q, %v", got, err)
	}

	releaseStable(t, k, clk, m)
	m.Hold(1, 1)
	if got := readStable(t, k, clk); got != "5" {
		t.Fatalf("全部離したあとの押下 = %q, want 5", got)
	}
}

func TestKeypadIgnoresABounceShorterThanThirtyMilliseconds(t *testing.T) {
	clk := clocktest.New(time.Unix(0, 0))
	cfg := loadedKeypad(t, func(string) string { return "" })
	m := newMatrix(len(cfg.Rows), len(cfg.Cols))
	k := mustKeypad(t, m, cfg.Keys, cfg.Debounce, clk)

	m.Hold(1, 1)
	if got, err := k.ReadKey(); err != nil || got != "" {
		t.Fatalf("押した瞬間 = %q, %v", got, err)
	}
	clk.Advance(10 * time.Millisecond)
	m.Release(1, 1)
	if got, err := k.ReadKey(); err != nil || got != "" {
		t.Fatalf("揺れで離れた = %q, %v", got, err)
	}
	clk.Advance(10 * time.Millisecond)
	m.Hold(1, 1)
	if got, err := k.ReadKey(); err != nil || got != "" {
		t.Fatalf("再び押した瞬間 = %q, %v", got, err)
	}
	clk.Advance(29 * time.Millisecond)
	if got, err := k.ReadKey(); err != nil || got != "" {
		t.Fatalf("29ms = %q, %v", got, err)
	}
	clk.Advance(time.Millisecond)
	got, err := k.ReadKey()
	if err != nil || got != "5" {
		t.Fatalf("30ms 安定 = %q, %v, want 5", got, err)
	}
}

func TestKeypadCheckPrintsEachPressUntilStopped(t *testing.T) {
	cfg := loadedKeypad(t, func(string) string { return "" })
	m := newMatrix(len(cfg.Rows), len(cfg.Cols))
	k := mustKeypad(t, m, cfg.Keys, 0, clocktest.New(time.Unix(0, 0)))
	m.Hold(1, 1)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var out safeBuffer
	done := make(chan error, 1)
	go func() {
		done <- WatchKeypad(ctx, k, &out)
	}()
	waitFor(t, &out, "キーを1個ずつ押してください。\n")
	waitFor(t, &out, "キー: 5\n")
	cancel()
	if err := <-done; err != context.Canceled {
		t.Fatalf("終わり = %v", err)
	}
	if err := k.Close(); err != nil {
		t.Fatal(err)
	}
	if !m.allClosed() {
		t.Fatal("線を放していない")
	}
}

func TestKeypadCheckRejectsABadMapBeforeOpeningPins(t *testing.T) {
	t.Setenv("KAZOKUAI_KEYPAD_KEYS", "1,2")
	err := runCheck(context.Background(), "keypad", hardware{
		out: &bytes.Buffer{},
		cfg: DefaultConfig(),
	})
	if err == nil || !strings.Contains(err.Error(), "KAZOKUAI_KEYPAD_KEYS") {
		t.Fatalf("配置 = %v", err)
	}
}

func TestKeypadDefaultsMatchTelBase(t *testing.T) {
	cfg := loadedKeypad(t, func(string) string { return "" })
	if !sameInts(cfg.Rows, []int{17, 27, 22, 23}) || !sameInts(cfg.Cols, []int{24, 25, 4}) {
		t.Fatalf("ピン = %v %v", cfg.Rows, cfg.Cols)
	}
	want := [][]string{{"1", "2", "3"}, {"4", "5", "6"}, {"7", "8", "9"}, {"*", "0", "#"}}
	if !sameKeys(cfg.Keys, want) {
		t.Fatalf("配置 = %v", cfg.Keys)
	}
	if cfg.Debounce != 30*time.Millisecond {
		t.Fatalf("デバウンス = %s, want 30ms", cfg.Debounce)
	}
}

func TestKeypadReadsItsMapFromTheEnvironment(t *testing.T) {
	cfg := loadedKeypad(t, func(key string) string {
		switch key {
		case "KAZOKUAI_KEYPAD_ROWS":
			return "8, 9"
		case "KAZOKUAI_KEYPAD_COLS":
			return "10, 11"
		case "KAZOKUAI_KEYPAD_KEYS":
			return "A, B; C, D"
		default:
			return ""
		}
	})
	if !sameInts(cfg.Rows, []int{8, 9}) || !sameInts(cfg.Cols, []int{10, 11}) {
		t.Fatalf("ピン = %v %v", cfg.Rows, cfg.Cols)
	}
	clk := clocktest.New(time.Unix(0, 0))
	m := newMatrix(len(cfg.Rows), len(cfg.Cols))
	k := mustKeypad(t, m, cfg.Keys, cfg.Debounce, clk)
	m.Hold(1, 0)
	if got := readStable(t, k, clk); got != "C" {
		t.Fatalf("配置 = %q, want C", got)
	}
}

func TestKeypadRejectsAMapThatDoesNotMatchThePins(t *testing.T) {
	_, err := LoadKeypad(func(key string) string {
		if key == "KAZOKUAI_KEYPAD_KEYS" {
			return "1,2"
		}
		return ""
	})
	if err == nil || !strings.Contains(err.Error(), "KAZOKUAI_KEYPAD_KEYS") {
		t.Fatalf("配置 = %v", err)
	}

	_, err = LoadKeypad(func(key string) string {
		if key == "KAZOKUAI_KEYPAD_ROWS" {
			return "17,27,x"
		}
		return ""
	})
	if err == nil || !strings.Contains(err.Error(), "KAZOKUAI_KEYPAD_ROWS") {
		t.Fatalf("行 = %v", err)
	}

	_, err = LoadKeypad(func(key string) string {
		if key == "KAZOKUAI_KEYPAD_COLS" {
			return "17,25,4"
		}
		return ""
	})
	if err == nil || !strings.Contains(err.Error(), "GPIO17") {
		t.Fatalf("重なり = %v", err)
	}
}

func TestKeypadFloatsTheRowWhenAReadFails(t *testing.T) {
	row := &keypadPin{}
	col := &keypadPin{err: errors.New("read failed")}
	k, err := newKeypad([]pin{row}, []pin{col}, [][]string{{"1"}}, 30*time.Millisecond, clocktest.New(time.Unix(0, 0)))
	if err != nil {
		t.Fatal(err)
	}
	k.settle = 0
	if _, err := k.ReadKey(); err == nil || !strings.Contains(err.Error(), "キーパッド") {
		t.Fatalf("読み取り = %v", err)
	}
	if row.low {
		t.Fatal("失敗したあとも行が低いまま")
	}
}

func loadedKeypad(t *testing.T, getenv func(string) string) KeypadConfig {
	t.Helper()
	cfg, err := LoadKeypad(getenv)
	if err != nil {
		t.Fatal(err)
	}
	return cfg
}

func mustKeypad(t *testing.T, m *matrix, keys [][]string, debounce time.Duration, clk *clocktest.Clock) *Keypad {
	t.Helper()
	rows, cols := m.pins()
	k, err := newKeypad(rows, cols, keys, debounce, clk)
	if err != nil {
		t.Fatal(err)
	}
	// 行を低くしてから読む 1ms は、偽の線では待たない。
	k.settle = 0
	return k
}

func readStable(t *testing.T, k *Keypad, clk *clocktest.Clock) string {
	t.Helper()
	if got, err := k.ReadKey(); err != nil || got != "" {
		t.Fatalf("押した瞬間 = %q, %v", got, err)
	}
	clk.Advance(29 * time.Millisecond)
	if got, err := k.ReadKey(); err != nil || got != "" {
		t.Fatalf("29ms = %q, %v", got, err)
	}
	clk.Advance(time.Millisecond)
	got, err := k.ReadKey()
	if err != nil {
		t.Fatal(err)
	}
	return got
}

func releaseStable(t *testing.T, k *Keypad, clk *clocktest.Clock, m *matrix) {
	t.Helper()
	m.ReleaseAll()
	if got, err := k.ReadKey(); err != nil || got != "" {
		t.Fatalf("離した瞬間 = %q, %v", got, err)
	}
	clk.Advance(30 * time.Millisecond)
	if got, err := k.ReadKey(); err != nil || got != "" {
		t.Fatalf("離れて安定 = %q, %v", got, err)
	}
}

func sameInts(got, want []int) bool {
	if len(got) != len(want) {
		return false
	}
	for i := range want {
		if got[i] != want[i] {
			return false
		}
	}
	return true
}

func sameKeys(got, want [][]string) bool {
	if len(got) != len(want) {
		return false
	}
	for r := range want {
		if len(got[r]) != len(want[r]) {
			return false
		}
		for c := range want[r] {
			if got[r][c] != want[r][c] {
				return false
			}
		}
	}
	return true
}

// matrix は、押したマスが、低くした行と列をつなぐ偽物のキーパッドである。
type matrix struct {
	mu        sync.Mutex
	down      [][]bool
	driven    []bool
	rowClosed []bool
	colClosed []bool
}

func newMatrix(rows, cols int) *matrix {
	m := &matrix{
		down:      make([][]bool, rows),
		driven:    make([]bool, rows),
		rowClosed: make([]bool, rows),
		colClosed: make([]bool, cols),
	}
	for r := range m.down {
		m.down[r] = make([]bool, cols)
	}
	return m
}

func (m *matrix) Hold(r, c int) {
	m.mu.Lock()
	m.down[r][c] = true
	m.mu.Unlock()
}

func (m *matrix) Release(r, c int) {
	m.mu.Lock()
	m.down[r][c] = false
	m.mu.Unlock()
}

func (m *matrix) ReleaseAll() {
	m.mu.Lock()
	for r := range m.down {
		for c := range m.down[r] {
			m.down[r][c] = false
		}
	}
	m.mu.Unlock()
}

func (m *matrix) anyDriven() bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, driven := range m.driven {
		if driven {
			return true
		}
	}
	return false
}

func (m *matrix) allClosed() bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, closed := range m.rowClosed {
		if !closed {
			return false
		}
	}
	for _, closed := range m.colClosed {
		if !closed {
			return false
		}
	}
	return true
}

func (m *matrix) pins() (rows, cols []pin) {
	for r := range m.driven {
		rows = append(rows, rowPin{m: m, r: r})
	}
	for c := range m.colClosed {
		cols = append(cols, colPin{m: m, c: c})
	}
	return rows, cols
}

type rowPin struct {
	m *matrix
	r int
}

func (p rowPin) DriveLow() error {
	p.m.mu.Lock()
	p.m.driven[p.r] = true
	p.m.mu.Unlock()
	return nil
}

func (p rowPin) Float() error {
	p.m.mu.Lock()
	p.m.driven[p.r] = false
	p.m.mu.Unlock()
	return nil
}

func (p rowPin) Value() (int, error) { return 1, nil }

func (p rowPin) Close() error {
	if err := p.Float(); err != nil {
		return err
	}
	p.m.mu.Lock()
	p.m.rowClosed[p.r] = true
	p.m.mu.Unlock()
	return nil
}

type colPin struct {
	m *matrix
	c int
}

func (colPin) DriveLow() error { return nil }
func (colPin) Float() error    { return nil }

func (p colPin) Value() (int, error) {
	p.m.mu.Lock()
	defer p.m.mu.Unlock()
	for r, driven := range p.m.driven {
		if driven && p.m.down[r][p.c] {
			return 0, nil
		}
	}
	return 1, nil
}

func (p colPin) Close() error {
	p.m.mu.Lock()
	p.m.colClosed[p.c] = true
	p.m.mu.Unlock()
	return nil
}

type keypadPin struct {
	low bool
	err error
}

func (p *keypadPin) DriveLow() error { p.low = true; return nil }
func (p *keypadPin) Float() error    { p.low = false; return nil }
func (p *keypadPin) Value() (int, error) {
	if p.err != nil {
		return 0, p.err
	}
	if p.low {
		return 0, nil
	}
	return 1, nil
}
func (p *keypadPin) Close() error { return p.Float() }
