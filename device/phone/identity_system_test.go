package phone_test

import (
	"context"
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/gesop0n/kazokuai/backend/server"
	"github.com/gesop0n/kazokuai/device/phone"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

// newIdentitySystem は、ID と鍵のファイルを作り、見守る方を渡さずに電話機を起動する。
// 終わりに phones の文書を消す。残すと、あとのテストの今すぐ通話が、その電話機を探す。
func newIdentitySystem(t *testing.T, now time.Time) (*system, phone.Identity, string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "kazokuai", phone.IdentityFileName)
	old := syscall.Umask(0)
	t.Cleanup(func() { syscall.Umask(old) })

	identity, err := phone.LoadOrCreateIdentity(path)
	if err != nil {
		t.Fatal(err)
	}
	if identity.ID == "" || identity.Key == "" || identity.ID == identity.Key {
		t.Fatal("ID と鍵が作られなかった")
	}
	s := newPreparedSystem(t, hanako, now, func(d *phone.Device) {
		d.Identity = identity
	})
	t.Cleanup(func() {
		_, _ = emulators.Firestore.Collection("phones").Doc(identity.ID).Delete(context.Background())
	})
	return s, identity, path
}

func TestFirstStartMakesTheFileAndRegisters(t *testing.T) {
	s, identity, path := newIdentitySystem(t, time.Date(2026, 11, 10, 9, 0, 0, 0, time.UTC))
	assertPrivateIdentityFile(t, path)

	data := waitPhoneDoc(t, identity.ID)
	if got := stringField(data, "watchedPersonId"); got != "" {
		t.Fatalf("結び付き = %q, want 空", got)
	}
	assertKeyHidden(t, data, identity.Key)
	assertRegistration(t, s, identity)
}

func TestNextStartUsesTheSameIDAndKey(t *testing.T) {
	s, identity, path := newIdentitySystem(t, time.Date(2026, 11, 10, 9, 10, 0, 0, time.UTC))
	first := waitPhoneDoc(t, identity.ID)
	before, _, _, _ := s.swap.registration()
	hash := stringField(first, "keyHash")
	registeredAt := timeField(t, first, "registeredAt")

	s.stopPhone(t)
	again, err := phone.LoadOrCreateIdentity(path)
	if err != nil {
		t.Fatal(err)
	}
	if again.ID != identity.ID || again.Key != identity.Key {
		t.Fatal("次の起動が別の ID か鍵を作った")
	}
	s.runDevice()
	waitUntil(t, "次の起動が登録しなかった", func() bool {
		n, _, _, _ := s.swap.registration()
		return n > before
	})

	assertRegistration(t, s, identity)
	second := waitPhoneDoc(t, identity.ID)
	if stringField(second, "keyHash") != hash {
		t.Fatal("次の起動で鍵のハッシュが変わった")
	}
	if got := timeField(t, second, "registeredAt"); !got.Equal(registeredAt) {
		t.Fatalf("登録した時刻 = %v, want %v", got, registeredAt)
	}
}

func TestUnknownIDRegistersAgain(t *testing.T) {
	s, identity, _ := newIdentitySystem(t, time.Date(2026, 11, 10, 9, 20, 0, 0, time.UTC))
	first := waitPhoneDoc(t, identity.ID)
	hash := stringField(first, "keyHash")
	linkPhone(t, identity.ID, hanakoID)
	waitUntil(t, "電話機がつながらなかった", func() bool { return s.api.Connected(hanakoID) })
	before, _, _, _ := s.swap.registration()

	if _, err := emulators.Firestore.Collection("phones").Doc(identity.ID).Delete(context.Background()); err != nil {
		t.Fatal(err)
	}
	waitUntil(t, "消した電話機が残った", func() bool {
		_, err := emulators.Firestore.Collection("phones").Doc(identity.ID).Get(context.Background())
		return status.Code(err) == codes.NotFound
	})
	// つなぎ直すタイマーは、時計を進めるまで鳴らない。先にサーバーを空にしてから進める。
	s.api.Stop()
	s.api = server.New(s.config, emulators, s.gemini, s.gemini, s.clock)
	s.swap.set(s.api)

	deadline := time.Now().Add(waitTimeout)
	var data map[string]any
	for {
		snap, err := emulators.Firestore.Collection("phones").Doc(identity.ID).Get(context.Background())
		if err == nil && snap.Exists() {
			data = snap.Data()
			break
		}
		if err != nil && status.Code(err) != codes.NotFound {
			t.Fatal(err)
		}
		if time.Now().After(deadline) {
			t.Fatal("待っても知らない ID を登録し直さなかった")
		}
		s.clock.advance(time.Second)
		time.Sleep(time.Millisecond)
	}
	if stringField(data, "keyHash") != hash {
		t.Fatal("登録し直した鍵のハッシュが違う")
	}
	if got := stringField(data, "watchedPersonId"); got != "" {
		t.Fatalf("登録し直した結び付き = %q, want 空", got)
	}
	n, id, key, secret := s.swap.registration()
	if n <= before || id != identity.ID || key != identity.Key || secret != s.config.PhoneSecret {
		t.Fatal("登録し直した ID か鍵か合言葉が違う")
	}
}

func TestLinkedPhoneTakesACallWithItsIDAndKey(t *testing.T) {
	started := time.Date(2026, 11, 10, 9, 30, 0, 0, time.UTC)
	s, identity, _ := newIdentitySystem(t, started)
	waitPhoneDoc(t, identity.ID)
	linkPhone(t, identity.ID, hanakoID)

	c := s.startCall(t)
	session := s.gemini.waitForSession(t, 1)
	waitUntil(t, "呼び出し音が鳴らなかった", s.phone.isRinging)
	ringing := waitState(t, c.id, protocol.StateRinging)
	if ringing.Data()["message"] != testMessage {
		t.Errorf("伝えたいこと = %v, want %s", ringing.Data()["message"], testMessage)
	}

	s.phone.pickUp()
	waitForText(t, session, "[電話がつながりました]")
	waitState(t, c.id, protocol.StateTalking)
	s.clock.advance(time.Second)
	session.reply(finished(outputTranscription("お伝えします。")))
	s.terminal.waitForLines(t, "かぞくAI: お伝えします。")
	s.phone.putDown()
	if err := c.result(t); err != nil {
		t.Fatalf("受話器を置いたのに、電話が %v で終わった", err)
	}

	ended := waitState(t, c.id, protocol.StateEnded)
	if got, ok := ended.Data()["startedAt"].(time.Time); !ok || !got.Equal(started) {
		t.Errorf("始まりの時刻 = %v, want %v", ended.Data()["startedAt"], started)
	}
	got := utterancesOf(t, ended.Ref)
	if len(got) != 1 || got[0].text != "お伝えします。" {
		t.Fatalf("発話 = %+v, want お伝えします。", got)
	}
}

func assertPrivateIdentityFile(t *testing.T, path string) {
	t.Helper()
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("ファイルの権限 = %o, want 600", info.Mode().Perm())
	}
	dir, err := os.Stat(filepath.Dir(path))
	if err != nil {
		t.Fatal(err)
	}
	if dir.Mode().Perm() != 0o700 {
		t.Fatalf("ディレクトリの権限 = %o, want 700", dir.Mode().Perm())
	}
}

func waitPhoneDoc(t *testing.T, id string) map[string]any {
	t.Helper()
	var data map[string]any
	waitUntil(t, "電話機が登録されなかった", func() bool {
		snap, err := emulators.Firestore.Collection("phones").Doc(id).Get(context.Background())
		if status.Code(err) == codes.NotFound {
			return false
		}
		if err != nil {
			t.Fatal(err)
		}
		data = snap.Data()
		return true
	})
	return data
}

func linkPhone(t *testing.T, id, personID string) {
	t.Helper()
	_, err := emulators.Firestore.Collection("phones").Doc(id).Update(context.Background(), []firestore.Update{
		{Path: "watchedPersonId", Value: personID},
	})
	if err != nil {
		t.Fatal(err)
	}
}

func assertKeyHidden(t *testing.T, data map[string]any, key string) {
	t.Helper()
	hash := stringField(data, "keyHash")
	if hash == "" || hash == key {
		t.Fatal("鍵のハッシュが無いか、鍵そのものになっている")
	}
	for name, value := range data {
		if text, ok := value.(string); ok && text == key {
			t.Fatalf("フィールド %s に鍵そのものが入っている", name)
		}
	}
}

func assertRegistration(t *testing.T, s *system, identity phone.Identity) {
	t.Helper()
	n, id, key, secret := s.swap.registration()
	if n < 1 || id != identity.ID || key != identity.Key || secret != s.config.PhoneSecret {
		t.Fatal("登録した ID か鍵か合言葉が違う")
	}
}

func stringField(data map[string]any, name string) string {
	text, _ := data[name].(string)
	return text
}

func timeField(t *testing.T, data map[string]any, name string) time.Time {
	t.Helper()
	got, ok := data[name].(time.Time)
	if !ok {
		t.Fatalf("%s が時刻ではない", name)
	}
	return got
}
