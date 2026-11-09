package server

import (
	"fmt"
	"os"
	"strings"

	"github.com/gesop0n/kazokuai/internal/protocol"
)

// demoProjectID は、環境変数 GOOGLE_CLOUD_PROJECT が無く、エミュレーターの変数があるときのプロジェクトである。
const demoProjectID = "demo-kazokuai"

// ResolveProject は、環境変数から Firebase のプロジェクトの ID を決める。
// エミュレーターの変数があるときは demo- のプロジェクトだけを許し、無ければ demo-kazokuai にする。
// エミュレーターの変数が無いときは、demo- 以外のプロジェクトの ID が環境に要る。資格情報はサービスアカウントに任せる。
func ResolveProject() (string, error) {
	return ResolveProjectFrom(
		os.Getenv("GOOGLE_CLOUD_PROJECT"),
		os.Getenv("FIRESTORE_EMULATOR_HOST"),
		os.Getenv("FIREBASE_AUTH_EMULATOR_HOST"),
	)
}

// ResolveProjectFrom は、ResolveProject の判定である。環境は引数で渡す。
func ResolveProjectFrom(projectID, firestoreHost, authHost string) (string, error) {
	if firestoreHost != "" || authHost != "" {
		if firestoreHost == "" {
			return "", fmt.Errorf("環境変数 FIRESTORE_EMULATOR_HOST に Firebase のエミュレーターのアドレスを入れてください")
		}
		if authHost == "" {
			return "", fmt.Errorf("環境変数 FIREBASE_AUTH_EMULATOR_HOST に Firebase のエミュレーターのアドレスを入れてください")
		}
		if projectID == "" {
			projectID = demoProjectID
		}
		if !strings.HasPrefix(projectID, "demo-") {
			return "", fmt.Errorf("エミュレーターを使うときは、GOOGLE_CLOUD_PROJECT を demo- で始まる ID にしてください（今は %s）", projectID)
		}
		return projectID, nil
	}
	if projectID == "" {
		return "", fmt.Errorf("環境変数 GOOGLE_CLOUD_PROJECT にプロジェクトの ID を入れてください")
	}
	if strings.HasPrefix(projectID, "demo-") {
		return "", fmt.Errorf("プロジェクト %s はエミュレーター専用です。FIRESTORE_EMULATOR_HOST と FIREBASE_AUTH_EMULATOR_HOST を入れてください", projectID)
	}
	return projectID, nil
}

// SecretFor は、電話機の合言葉を決める。環境変数にあれば、前後の空白を除いてそれを使う。
// 無ければ demo- のプロジェクトだけ開発用の合言葉にする。
func SecretFor(projectID, envSecret string) (string, error) {
	envSecret = strings.TrimSpace(envSecret)
	if envSecret != "" {
		return envSecret, nil
	}
	if strings.HasPrefix(projectID, "demo-") {
		return protocol.DevPhoneSecret, nil
	}
	return "", fmt.Errorf("環境変数 PHONE_SECRET に電話機の合言葉を入れてください")
}
