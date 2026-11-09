#!/usr/bin/env bash
# テスト用の Firebase のエミュレーターを空いているポートで起動し、その中で 1 つのコマンドを動かす。
# firebase-tools は Auth と Firestore のポートが埋まっていると起動しないので、firebase/firebase.json のポートは使わない。
# ハブ、ログ、Firestore の websocket のポートは firebase-tools が空きを探すが、同時に起動すると取り合うので、それも決めて渡す。
# こうすると、開発用のエミュレーターや、ほかのチェックが同時に動いていても重ならない。
# エミュレーターの場所は、環境変数 FIRESTORE_EMULATOR_HOST と FIREBASE_AUTH_EMULATOR_HOST でコマンドに渡る。
#
#   scripts/emulators_exec.sh 'go test ./...'
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# ポートを全部同時に取ってから放すので、同じ番号にはならない
read -r auth_port firestore_port websocket_port hub_port logging_port < <(python3 -I -c '
import socket
sockets = [socket.socket() for _ in range(5)]
for s in sockets:
    s.bind(("127.0.0.1", 0))
print(*(s.getsockname()[1] for s in sockets))
')

cat >"$work/firebase.json" <<EOF
{
  "firestore": { "rules": "$root/firebase/firestore.rules" },
  "emulators": {
    "singleProjectMode": true,
    "auth": { "port": $auth_port },
    "firestore": { "port": $firestore_port, "websocketPort": $websocket_port },
    "hub": { "port": $hub_port },
    "logging": { "port": $logging_port },
    "ui": { "enabled": false }
  }
}
EOF

# テストのバックエンドはプロジェクトを環境変数から読む。エミュレーターのプロジェクトに固定し、
# 外から GOOGLE_CLOUD_PROJECT が渡っていても本物のプロジェクトにはつながない。
export GOOGLE_CLOUD_PROJECT=demo-kazokuai
firebase emulators:exec --config "$work/firebase.json" --project demo-kazokuai --only auth,firestore "$1"
