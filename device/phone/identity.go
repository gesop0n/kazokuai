package phone

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

const (
	// IdentityFileName は、電話機の ID と鍵を置くファイルの名前である。
	IdentityFileName = "phone.json"
	// LinuxStateDir は、Pi で ID と鍵を置くディレクトリである。systemd の状態ディレクトリと同じである。
	LinuxStateDir = "/var/lib/kazokuai"
	// PhoneFileEnv は、ID と鍵のファイルの場所を変える設定である。
	PhoneFileEnv = "KAZOKUAI_PHONE_FILE"
)

// Identity は、電話機が自分で作った ID と鍵である。鍵は、このファイルを読めるユーザーだけが知る。
type Identity struct {
	ID  string `json:"id"`
	Key string `json:"key"`
}

// IdentityPath は、ID と鍵のファイルの場所を決める。
// PhoneFileEnv があればそれを使う。無ければ、systemd の STATE_DIRECTORY、
// Linux では LinuxStateDir、それ以外はユーザーの設定ディレクトリの kazokuai である。
func IdentityPath(goos string, getenv func(string) string, userConfigDir string) (string, error) {
	if getenv == nil {
		getenv = func(string) string { return "" }
	}
	if path := strings.TrimSpace(getenv(PhoneFileEnv)); path != "" {
		return path, nil
	}
	if dir := strings.TrimSpace(getenv("STATE_DIRECTORY")); dir != "" {
		// systemd は、状態ディレクトリが複数あるとき、コロンで区切って渡す。最初の 1 つを使う。
		first, _, _ := strings.Cut(dir, ":")
		return filepath.Join(first, IdentityFileName), nil
	}
	if goos == "linux" {
		return filepath.Join(LinuxStateDir, IdentityFileName), nil
	}
	if userConfigDir == "" {
		return "", errors.New("ユーザーの設定ディレクトリが分かりません")
	}
	return filepath.Join(userConfigDir, "kazokuai", IdentityFileName), nil
}

// DefaultIdentityPath は、この機械での ID と鍵のファイルの場所である。
func DefaultIdentityPath() (string, error) {
	configDir, err := os.UserConfigDir()
	if err != nil {
		configDir = ""
	}
	return IdentityPath(runtime.GOOS, os.Getenv, configDir)
}

// LoadOrCreateIdentity は、path の ID と鍵を読む。ファイルが無ければ、乱数で作って残す。
// ファイルは、電話機を動かすユーザーだけが読める。壊れたファイルは書き換えない。
func LoadOrCreateIdentity(path string) (Identity, error) {
	id, err := readIdentity(path)
	if err == nil {
		if err := os.Chmod(path, 0o600); err != nil {
			return Identity{}, err
		}
		return id, nil
	}
	if !os.IsNotExist(err) {
		return Identity{}, err
	}
	dir := filepath.Dir(path)
	if err := makePrivateDir(dir); err != nil {
		return Identity{}, err
	}
	created, err := newIdentity()
	if err != nil {
		return Identity{}, err
	}
	if err := writeNewIdentity(path, created); err != nil {
		if os.IsExist(err) {
			return readIdentity(path)
		}
		return Identity{}, err
	}
	log.Printf("電話機の ID を作りました: %s", created.ID)
	return created, nil
}

// makePrivateDir は、dir が無ければ、このユーザーだけが入れるディレクトリとして作る。
// すでにあるディレクトリの権限は変えない。
func makePrivateDir(dir string) error {
	if dir == "" || dir == "." {
		return nil
	}
	if _, err := os.Stat(dir); err == nil {
		return nil
	} else if !os.IsNotExist(err) {
		return err
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	return os.Chmod(dir, 0o700)
}

func newIdentity() (Identity, error) {
	id, err := randomHex(16)
	if err != nil {
		return Identity{}, err
	}
	key, err := randomHex(32)
	if err != nil {
		return Identity{}, err
	}
	return Identity{ID: id, Key: key}, nil
}

func randomHex(n int) (string, error) {
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		return "", fmt.Errorf("ID と鍵の乱数を作れません: %w", err)
	}
	return hex.EncodeToString(buf), nil
}

func readIdentity(path string) (Identity, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Identity{}, err
	}
	var id Identity
	if err := json.Unmarshal(data, &id); err != nil {
		return Identity{}, fmt.Errorf("電話機の ID と鍵のファイルを読めません: %w", err)
	}
	if err := validateIdentity(id); err != nil {
		return Identity{}, err
	}
	return id, nil
}

func writeNewIdentity(path string, id Identity) error {
	payload, err := json.Marshal(id)
	if err != nil {
		return err
	}
	payload = append(payload, '\n')
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return err
	}
	if _, err := f.Write(payload); err != nil {
		f.Close()
		os.Remove(path)
		return err
	}
	if err := f.Chmod(0o600); err != nil {
		f.Close()
		os.Remove(path)
		return err
	}
	if err := f.Close(); err != nil {
		os.Remove(path)
		return err
	}
	return nil
}

// validateIdentity は、バックエンドが受け付ける ID と鍵かを見る。
// ID は英数字と - と _ で、1 文字以上 128 文字まで。鍵は 1 文字以上 256 文字まで。
func validateIdentity(id Identity) error {
	if !validPhoneID(id.ID) || id.Key == "" || len(id.Key) > 256 {
		return errors.New("電話機の ID と鍵のファイルが壊れています")
	}
	return nil
}

func validPhoneID(id string) bool {
	if len(id) < 1 || len(id) > 128 {
		return false
	}
	for _, r := range id {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '-', r == '_':
		default:
			return false
		}
	}
	return true
}
