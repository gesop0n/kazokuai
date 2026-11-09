package pi

import (
	"context"
	"errors"
	"fmt"
	"io"
	"math/bits"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/gesop0n/kazokuai/internal/clock"
)

const (
	// keypadDebounce は、同じ押下だとみなすまでの時間である。tel-base と同じ 30ms。
	keypadDebounce = 30 * time.Millisecond
	// keypadSettle は、行を低くしてから列を読むまでの時間である。
	keypadSettle = time.Millisecond
	// keypadPoll は、確認コマンドが次の走査まで待つ時間である。
	keypadPoll = 5 * time.Millisecond
)

// KeypadConfig は、キーの配置とピンである。チップは Config.GPIOChip をほかの部品と共有する。
// デバウンスは 30ms で、環境変数では変えない。
type KeypadConfig struct {
	Rows     []int
	Cols     []int
	Keys     [][]string
	Debounce time.Duration
}

// DefaultKeypad は、tel-base の配線である。行は GPIO17・27・22・23、列は GPIO24・25・4。
// 上の行から 1 2 3、4 5 6、7 8 9、* 0 #。実機で確かめてあるのは 5 だけである。
func DefaultKeypad() KeypadConfig {
	return KeypadConfig{
		Rows: []int{17, 27, 22, 23},
		Cols: []int{24, 25, 4},
		Keys: [][]string{
			{"1", "2", "3"},
			{"4", "5", "6"},
			{"7", "8", "9"},
			{"*", "0", "#"},
		},
		Debounce: keypadDebounce,
	}
}

// LoadKeypad は、環境変数で上書きした配置を返す。空の変数は既定のままにする。
//
//	KAZOKUAI_KEYPAD_ROWS=17,27,22,23
//	KAZOKUAI_KEYPAD_COLS=24,25,4
//	KAZOKUAI_KEYPAD_KEYS=1,2,3;4,5,6;7,8,9;*,0,#
func LoadKeypad(getenv func(string) string) (KeypadConfig, error) {
	cfg := DefaultKeypad()
	if v := strings.TrimSpace(getenv("KAZOKUAI_KEYPAD_ROWS")); v != "" {
		rows, err := parseGPIOList(v)
		if err != nil {
			return KeypadConfig{}, fmt.Errorf("KAZOKUAI_KEYPAD_ROWS=%q は 17,27,22,23 のように書いてください", v)
		}
		cfg.Rows = rows
	}
	if v := strings.TrimSpace(getenv("KAZOKUAI_KEYPAD_COLS")); v != "" {
		cols, err := parseGPIOList(v)
		if err != nil {
			return KeypadConfig{}, fmt.Errorf("KAZOKUAI_KEYPAD_COLS=%q は 24,25,4 のように書いてください", v)
		}
		cfg.Cols = cols
	}
	if v := strings.TrimSpace(getenv("KAZOKUAI_KEYPAD_KEYS")); v != "" {
		keys, err := parseKeyMap(v)
		if err != nil {
			return KeypadConfig{}, fmt.Errorf("KAZOKUAI_KEYPAD_KEYS=%q は 1,2,3;4,5,6;7,8,9;*,0,# のように書いてください", v)
		}
		cfg.Keys = keys
	}
	if err := validateKeypad(cfg); err != nil {
		return KeypadConfig{}, err
	}
	return cfg, nil
}

func parseGPIOList(s string) ([]int, error) {
	parts := strings.Split(s, ",")
	out := make([]int, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		n, err := strconv.Atoi(part)
		if err != nil || n < 0 {
			return nil, errors.New("bad gpio")
		}
		out = append(out, n)
	}
	if len(out) == 0 {
		return nil, errors.New("empty gpio")
	}
	return out, nil
}

func parseKeyMap(s string) ([][]string, error) {
	rows := strings.Split(s, ";")
	keys := make([][]string, 0, len(rows))
	for _, row := range rows {
		cols := strings.Split(row, ",")
		line := make([]string, 0, len(cols))
		for _, key := range cols {
			key = strings.TrimSpace(key)
			if key == "" {
				return nil, errors.New("empty key")
			}
			line = append(line, key)
		}
		keys = append(keys, line)
	}
	if len(keys) == 0 {
		return nil, errors.New("empty keys")
	}
	return keys, nil
}

func validateKeypad(cfg KeypadConfig) error {
	if len(cfg.Rows) == 0 || len(cfg.Cols) == 0 {
		return errors.New("キーパッドの行と列が要ります。")
	}
	if len(cfg.Rows) > 64 || len(cfg.Cols) > 64 || len(cfg.Rows)*len(cfg.Cols) > 64 {
		return errors.New("キーは 64 個までです。")
	}
	seen := make(map[int]struct{}, len(cfg.Rows)+len(cfg.Cols))
	for _, n := range cfg.Rows {
		if err := seeGPIO(seen, n); err != nil {
			return err
		}
	}
	for _, n := range cfg.Cols {
		if err := seeGPIO(seen, n); err != nil {
			return err
		}
	}
	if len(cfg.Keys) != len(cfg.Rows) {
		return fmt.Errorf("KAZOKUAI_KEYPAD_KEYS が %d 行 %d 列と合いません", len(cfg.Rows), len(cfg.Cols))
	}
	for _, row := range cfg.Keys {
		if len(row) != len(cfg.Cols) {
			return fmt.Errorf("KAZOKUAI_KEYPAD_KEYS が %d 行 %d 列と合いません", len(cfg.Rows), len(cfg.Cols))
		}
		for _, key := range row {
			if strings.TrimSpace(key) == "" {
				return errors.New("KAZOKUAI_KEYPAD_KEYS に空のキーがあります。")
			}
		}
	}
	return nil
}

func seeGPIO(seen map[int]struct{}, n int) error {
	if n < 0 {
		return fmt.Errorf("GPIO%d は 0 以上にしてください", n)
	}
	if _, ok := seen[n]; ok {
		return fmt.Errorf("GPIO%d が繰り返されています", n)
	}
	seen[n] = struct{}{}
	return nil
}

// pin は、キーパッドの 1 本の線である。
// フックの Line とは違い、行は走査のあいだだけ出力にして低くする。
type pin interface {
	DriveLow() error
	Float() error
	Value() (int, error)
	Close() error
}

// Keypad は、行列を走査して押下を 1 回ずつ知らせる。電話の流れではまだ使わない。
type Keypad struct {
	rows      []pin
	cols      []pin
	keys      [][]string
	debounce  time.Duration
	settle    time.Duration
	pollEvery time.Duration
	clk       clock.Clock
	state     *keyDebounce
	ready     bool
	colsN     int
}

func newKeypad(rows, cols []pin, keys [][]string, debounce time.Duration, clk clock.Clock) (*Keypad, error) {
	if len(rows) == 0 || len(cols) == 0 || len(rows)*len(cols) > 64 || len(keys) != len(rows) {
		return nil, errors.New("キーの配置と行・列の数が一致しません。")
	}
	for _, row := range keys {
		if len(row) != len(cols) {
			return nil, errors.New("キーの配置と行・列の数が一致しません。")
		}
		for _, key := range row {
			if key == "" {
				return nil, errors.New("キーの配置に空のキーがあります。")
			}
		}
	}
	if clk == nil {
		clk = clock.Real{}
	}
	if debounce < 0 {
		debounce = 0
	}
	return &Keypad{
		rows:      append([]pin(nil), rows...),
		cols:      append([]pin(nil), cols...),
		keys:      copyKeys(keys),
		debounce:  debounce,
		settle:    keypadSettle,
		pollEvery: keypadPoll,
		clk:       clk,
		state:     &keyDebounce{changed: clk.Now(), wait: debounce},
		ready:     true,
		colsN:     len(cols),
	}, nil
}

func copyKeys(keys [][]string) [][]string {
	out := make([][]string, len(keys))
	for i, row := range keys {
		out[i] = append([]string(nil), row...)
	}
	return out
}

// ReadKey は、行列を 1 回走査し、安定した押下を 1 つ返す。無ければ空である。
// 押したままは繰り返さない。2 つ以上が押されているあいだは、全部離れるまで空である。
func (k *Keypad) ReadKey() (string, error) {
	pressed, err := k.scan()
	if err != nil {
		return "", fmt.Errorf("キーパッドを読めなかった: %w", err)
	}
	if pressed.count() > 1 {
		k.ready = false
	}
	stable := k.state.update(pressed, k.clk.Now())
	if stable == 0 && pressed == 0 {
		k.ready = true
		return "", nil
	}
	if stable.count() == 1 && k.ready {
		k.ready = false
		return k.label(stable), nil
	}
	return "", nil
}

func (k *Keypad) label(s keySet) string {
	index := bits.TrailingZeros64(uint64(s))
	return k.keys[index/k.colsN][index%k.colsN]
}

func (k *Keypad) scan() (keySet, error) {
	var pressed keySet
	for r, row := range k.rows {
		found, err := k.readRow(r, row)
		if err != nil {
			return 0, err
		}
		pressed |= found
	}
	return pressed, nil
}

// readRow は、この行だけを低くして列を読む。
// 終わったら、失敗しても行をハイインピーダンスに戻す。低くしたまま次の行を低くすると、
// 押されたキーを通して出力同士が短絡する。
func (k *Keypad) readRow(r int, row pin) (pressed keySet, err error) {
	if err = row.DriveLow(); err != nil {
		_ = row.Float()
		return 0, err
	}
	defer func() {
		if floatErr := row.Float(); err == nil {
			err = floatErr
		}
	}()
	if k.settle > 0 {
		time.Sleep(k.settle)
	}
	for c, col := range k.cols {
		var level int
		level, err = col.Value()
		if err != nil {
			return 0, err
		}
		if level == 0 {
			pressed |= keySet(1) << (r*k.colsN + c)
		}
	}
	return pressed, nil
}

// Close は、行と列をハイインピーダンスに戻して放す。
func (k *Keypad) Close() error {
	var err error
	for _, group := range [][]pin{k.rows, k.cols} {
		for _, p := range group {
			if e := p.Close(); e != nil && err == nil {
				err = e
			}
		}
	}
	return err
}

// WatchKeypad は、押したキーを 1 回ずつ書く。確認コマンドが使う。
func WatchKeypad(ctx context.Context, k *Keypad, out io.Writer) error {
	if out == nil {
		out = io.Discard
	}
	fmt.Fprintln(out, "キーを1個ずつ押してください。")
	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		key, err := k.ReadKey()
		if err != nil {
			return err
		}
		if key != "" {
			fmt.Fprintf(out, "キー: %s\n", key)
		}
		timer := k.clk.NewTimer(k.pollEvery)
		select {
		case <-ctx.Done():
			timer.Stop()
			return ctx.Err()
		case <-timer.Chan():
		}
	}
}

func checkKeypad(ctx context.Context, hw hardware) error {
	cfg, err := LoadKeypad(os.Getenv)
	if err != nil {
		return err
	}
	pad, err := OpenKeypad(hw.cfg.GPIOChip, cfg)
	if err != nil {
		return err
	}
	defer pad.Close()
	return WatchKeypad(ctx, pad, hw.out)
}

// keySet は、押されているマスである。ビット r*列数+c が 1 のとき、そのマスが押されている。
type keySet uint64

func (s keySet) count() int { return bits.OnesCount64(uint64(s)) }

// keyDebounce は、同じ押下が debounce のあいだ続いてから、その押下を安定とみなす。
type keyDebounce struct {
	value     keySet
	candidate keySet
	changed   time.Time
	wait      time.Duration
}

func (d *keyDebounce) update(next keySet, now time.Time) keySet {
	if next != d.candidate {
		d.candidate = next
		d.changed = now
	}
	if now.Sub(d.changed) >= d.wait {
		d.value = d.candidate
	}
	return d.value
}
