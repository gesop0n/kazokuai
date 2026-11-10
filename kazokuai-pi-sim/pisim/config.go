package main

import (
	"bufio"
	"encoding/binary"
	"fmt"
	"os"
	"strconv"
	"strings"
)

var le = binary.LittleEndian

const configPath = "/etc/kazokuai-pisim.conf"

type Config struct {
	HookGPIO         int
	LiftedWhenClosed bool
	Rows             []int
	Cols             []int
	Keys             [][]byte
	RingerGPIO       int
	AudioName        string
	PulseServer      string
	Volume           float64
	Wifi             bool
	WifiSSID         string
	WifiPassword     string
}

func DefaultConfig() Config {
	return Config{
		HookGPIO:         5,
		LiftedWhenClosed: true,
		Rows:             []int{17, 27, 22, 23},
		Cols:             []int{24, 25, 4},
		Keys:             [][]byte{[]byte("123"), []byte("456"), []byte("789"), []byte("*0#")},
		RingerGPIO:       18,
		AudioName:        "USB PnP Sound Device",
		PulseServer:      "unix:/mnt/wslg/PulseServer",
		Volume:           0.6,
		Wifi:             true,
		WifiSSID:         "kazokuai-home",
		WifiPassword:     "kazokuai-wifi",
	}
}

func (c Config) keyPos(k byte) (row, col int, ok bool) {
	for r, keys := range c.Keys {
		for col, x := range keys {
			if x == k && r < len(c.Rows) && col < len(c.Cols) {
				return r, col, true
			}
		}
	}
	return 0, 0, false
}

func (c Config) Summary() string {
	rows := make([]string, len(c.Keys))
	for i, r := range c.Keys {
		rows[i] = string(r)
	}
	contact := "開く"
	if c.LiftedWhenClosed {
		contact = "閉じる"
	}
	return fmt.Sprintf("フック GPIO%d(上げると接点が%s)・行 %v・列 %v・本体スピーカー GPIO%d・キー %s",
		c.HookGPIO, contact, c.Rows, c.Cols, c.RingerGPIO, strings.Join(rows, " "))
}

func LoadConfig(path string) (Config, error) {
	c := DefaultConfig()

	f, err := os.Open(path)
	if os.IsNotExist(err) {
		return c, nil
	}
	if err != nil {
		return c, err
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	lineNo := 0
	for sc.Scan() {
		lineNo++
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		k, v, ok := strings.Cut(line, "=")
		if !ok {
			return c, fmt.Errorf("%s:%d: KEY=VALUE の形にしてください", path, lineNo)
		}
		k = strings.TrimSpace(k)
		v = strings.Trim(strings.TrimSpace(v), `"'`)
		bad := func(err error) error { return fmt.Errorf("%s:%d: %s=%q: %v", path, lineNo, k, v, err) }

		switch k {
		case "HOOK_GPIO":
			if c.HookGPIO, err = gpioNum(v); err != nil {
				return c, bad(err)
			}
		case "LIFTED_WHEN_CLOSED":
			if c.LiftedWhenClosed, err = strconv.ParseBool(v); err != nil {
				return c, bad(err)
			}
		case "ROW_GPIO":
			if c.Rows, err = gpioList(v); err != nil {
				return c, bad(err)
			}
		case "COL_GPIO":
			if c.Cols, err = gpioList(v); err != nil {
				return c, bad(err)
			}
		case "KEYS":
			c.Keys = nil
			for _, row := range strings.Fields(strings.ReplaceAll(v, ",", " ")) {
				c.Keys = append(c.Keys, []byte(row))
			}
		case "RINGER_GPIO":
			if c.RingerGPIO, err = gpioNum(v); err != nil {
				return c, bad(err)
			}
		case "AUDIO_NAME":
			c.AudioName = v
		case "PULSE_SERVER":
			c.PulseServer = v
		case "VOLUME":
			if c.Volume, err = strconv.ParseFloat(v, 64); err != nil || c.Volume < 0 || c.Volume > 2 {
				return c, bad(fmt.Errorf("0 から 2 にしてください"))
			}
		case "WIFI", "WLAN":
			if c.Wifi, err = strconv.ParseBool(v); err != nil {
				return c, bad(err)
			}
		case "WIFI_SSID":
			if v == "" || len(v) > 32 {
				return c, bad(fmt.Errorf("1〜32 バイトにしてください"))
			}
			c.WifiSSID = v
		case "WIFI_PASSWORD":
			if len(v) < 8 || len(v) > 63 {
				return c, bad(fmt.Errorf("8〜63 文字にしてください"))
			}
			c.WifiPassword = v
		case "WLAN_IF":
		default:
			return c, fmt.Errorf("%s:%d: 知らない項目 %s", path, lineNo, k)
		}
	}
	if err := sc.Err(); err != nil {
		return c, err
	}

	if len(c.Keys) != len(c.Rows) {
		return c, fmt.Errorf("%s: KEYS の行の数(%d)と ROW_GPIO の数(%d)が合いません", path, len(c.Keys), len(c.Rows))
	}
	for _, row := range c.Keys {
		if len(row) != len(c.Cols) {
			return c, fmt.Errorf("%s: KEYS の列の数と COL_GPIO の数(%d)が合いません", path, len(c.Cols))
		}
	}
	return c, nil
}

func gpioNum(v string) (int, error) {
	n, err := strconv.Atoi(v)
	if err != nil || n < 0 || n >= numLines {
		return 0, fmt.Errorf("0 から %d の BCM 番号にしてください", numLines-1)
	}
	return n, nil
}

func gpioList(v string) ([]int, error) {
	var out []int
	for _, s := range strings.Split(v, ",") {
		n, err := gpioNum(strings.TrimSpace(s))
		if err != nil {
			return nil, err
		}
		out = append(out, n)
	}
	return out, nil
}
