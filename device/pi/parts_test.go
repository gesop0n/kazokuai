package pi

import (
	"bytes"
	"testing"
)

func TestLampOnlyLogs(t *testing.T) {
	var out bytes.Buffer
	Lamp{Out: &out}.On()
	Lamp{Out: &out}.Off()
	got := out.String()
	want := "ランプが点きました。\nランプが消えました。\n"
	if got != want {
		t.Fatalf("ログ =\n%s", got)
	}
}
