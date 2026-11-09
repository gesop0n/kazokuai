package pi

import (
	"bytes"
	"testing"
)

func TestLampAndRingerOnlyLog(t *testing.T) {
	var out bytes.Buffer
	Lamp{Out: &out}.On()
	Lamp{Out: &out}.Off()
	Ringer{Out: &out}.Ring()
	Ringer{Out: &out}.Stop()
	got := out.String()
	want := "ランプが点きました。\nランプが消えました。\n呼び出し中です。\n呼び出しが止まりました。\n"
	if got != want {
		t.Fatalf("ログ =\n%s", got)
	}
}
