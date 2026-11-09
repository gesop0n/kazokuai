# 公開する

本物のプロジェクトに、バックエンドと Web 版を公開し、審査員用アカウントを作る手順である。Terraform が作る資源は [infra/README.md](../infra/README.md) にある。

gcloud の既定のプロジェクトは使わない。この Mac の既定は、別の本番プロジェクトであることがある。どのコマンドも、プロジェクト ID を引数で渡す。`gcloud config set` は実行しない。

Gemini の API キー、電話機の合言葉、審査員のパスワードは、人が入れる。リポジトリには置かない。`.env` は git に入らない。mise はタスクを実行するとき、`.env` を読む。

docker と gcloud は、このリポジトリの mise では入らない。人が用意する。

以下の `PROJECT_ID` は、Firebase のプロジェクト ID である。手順 2 で確かめる。請求先アカウントは `XXXXXX-XXXXXX-XXXXXX`、リージョンは `asia-northeast1`、状態のバケットは名前だけである。`gs://` は付けない。`--region` は付けない。Hosting の `/api/**` は `firebase.json` で `asia-northeast1` のサービス `kazokuai` に回している。

Web 版の URL は `https://kazokuai.web.app` である。プロジェクト ID のサイト（`https://PROJECT_ID.web.app`）には出さない。

## 1. ログインする

```bash
gcloud auth login
gcloud auth application-default login
gcloud auth application-default set-quota-project PROJECT_ID
```

見本のデータを入れるタスクは、Cloud Run のサービスアカウントではなく、この人の認証情報で Firestore と Auth を書く。課金のプロジェクトは、上の `set-quota-project` でこのプロジェクトにする。

## 2. Firebase を追加する

公開する Google Cloud のプロジェクトが、まだ Firebase のプロジェクトでないときは、Firebase コンソールで、既存の Google Cloud プロジェクトに Firebase を追加する。

Firebase のプロジェクト ID は、名前が似た Google Cloud のプロジェクトと違うことがある。末尾が `-574b3` のようになる。ここから先の `PROJECT_ID` は、Firebase コンソールに出ている ID にする。

## 3. 状態のバケットを作る

まだ無いときだけ作る。オブジェクトのバージョニングを付ける。コマンドは [infra/README.md](../infra/README.md) の「状態のバケット」にある。どちらにも `--project=PROJECT_ID` を付ける。

## 4. すでにある Hosting のサイトを取り込む

Firebase がプロジェクト ID と同じ名前の Hosting のサイトを既に作っているときは、手順 5 の bootstrap の apply の前に、状態へ取り込む。

状態のバケットへまだ init していないときは、先に plan を 1 回実行する。

```bash
mise run infra:plan -- --project=PROJECT_ID \
  --billing-account=XXXXXX-XXXXXX-XXXXXX \
  --image=asia-northeast1-docker.pkg.dev/PROJECT_ID/kazokuai/backend:bootstrap \
  --state-bucket=BUCKET
```

import は `infra/run.sh` を通らない。プロジェクトは、次の環境変数で渡す。

```bash
export GOOGLE_PROJECT=PROJECT_ID
export GOOGLE_CLOUD_PROJECT=PROJECT_ID
export CLOUDSDK_CORE_PROJECT=PROJECT_ID
export GOOGLE_BILLING_PROJECT=PROJECT_ID

terraform -chdir=infra import \
  -var=project_id=PROJECT_ID \
  -var=region=asia-northeast1 \
  -var=billing_account=XXXXXX-XXXXXX-XXXXXX \
  -var=container_image=asia-northeast1-docker.pkg.dev/PROJECT_ID/kazokuai/backend:bootstrap \
  google_firebase_hosting_site.web projects/PROJECT_ID/sites/PROJECT_ID
```

`container_image` は変数として要る。この URI は push しなくてよい。

取り込むのは、プロジェクト ID と同じ既定のサイトだけである。資源のアドレスは `google_firebase_hosting_site.web` のままにする。Web 版のサイトは別に作る。サイト ID の既定は `kazokuai`（変数 `hosting_site_id`）である。これはまだ状態に無いので、import しない。手順 5 の apply が作る。

Firestore の `(default)` が既にあるときも、作る前に取り込む。コマンドは [infra/README.md](../infra/README.md) の「すでに資源があるとき」にある。

## 5. Cloud Run を作らずに apply する

`--bootstrap` は、API、Artifact Registry、秘密の入れ物、IAM、Firestore とルール、Firebase の Web アプリ、Hosting（既定のサイトと、サイト ID `kazokuai`）、予算を作る。Cloud Run と、その公開の IAM は作らない。

`IMAGE` は Terraform の変数なので要る。この URI は push しなくてよい。Cloud Run はここから先の手順で作る。

```bash
mise run infra:apply -- --bootstrap \
  --project=PROJECT_ID \
  --billing-account=XXXXXX-XXXXXX-XXXXXX \
  --image=asia-northeast1-docker.pkg.dev/PROJECT_ID/kazokuai/backend:bootstrap \
  --state-bucket=BUCKET
```

apply は確認を求める。API の有効化が行き渡る前に失敗したときは、同じコマンドをやり直す。

## 6. 秘密の値を入れる

値はコマンドの引数にも、リポジトリのファイルにも書かない。標準入力で渡す。

```bash
gcloud secrets versions add gemini-api-key --project=PROJECT_ID --data-file=-
gcloud secrets versions add phone-shared-secret --project=PROJECT_ID --data-file=-
```

各コマンドのあと、値を貼って Ctrl-D で終える。

リポジトリのルートの `.env` に、値を書く。名前は [.env.example](../.env.example) にある。

- `GEMINI_API_KEY` は、手元でバックエンドを動かすときのもの。本番の Cloud Run が読むのは、上で入れた `gemini-api-key` である。
- `PHONE_SECRET` は、`phone-shared-secret` に入れた合言葉と同じにする。電話機がこれを付ける。
- `JUDGE_EMAIL` と `JUDGE_PASSWORD` は、審査員用アカウントである。パスワードは 6 文字以上にする。

## 7. バックエンドを公開する

```bash
mise run deploy:backend -- \
  --project=PROJECT_ID \
  --billing-account=XXXXXX-XXXXXX-XXXXXX \
  --state-bucket=BUCKET
```

Mac が Apple Silicon でも、イメージは `linux/amd64` で作る。Cloud Run が動かす形である。タグは、実行の時刻と git のリビジョンから作る。push のあと、そのイメージで Terraform を適用し、Cloud Run を作る。確認を求める。

終わると、イメージの URI と、電話機がつなぐ URL を出す。

push が、Artifact Registry のリポジトリが無いと言って失敗したときは、手順 5 をやり直してから、もう一度このコマンドを実行する。`allUsers` の IAM で失敗したときは、手順 8 の組織ポリシーを直してからやり直す。Cloud Run が状態に tainted で残ったときは、うしろの「Cloud Run が tainted で残っているとき」で戻す。

## 8. コンソールでログインを有効にする

審査員用アカウントを作る前に済ませる。

1. Firebase コンソールで、この `PROJECT_ID` の Authentication を開く。
2. ログイン方法の「メール / パスワード」を有効にする。
3. メールリンクは無効のままにする。
4. 承認済みドメインに、`localhost`、`PROJECT_ID.firebaseapp.com`、`PROJECT_ID.web.app` があることを確かめる。
5. 承認済みドメインに `kazokuai.web.app` と `kazokuai.firebaseapp.com` を足す。Firebase が自動で足すのは、既定のサイトのドメイン（`PROJECT_ID.web.app` と `PROJECT_ID.firebaseapp.com`）だけである。`kazokuai` のサイトのドメインは、コンソールで足す。サイト ID を変えたときは、その ID の `web.app` と `firebaseapp.com` を足す。

組織のポリシー `iam.allowedPolicyMemberDomains` が `allUsers` を拒むと、Cloud Run を公開する IAM が失敗する。そのときは、このプロジェクトで `allUsers` を許す。説明は [infra/README.md](../infra/README.md) の「公開の呼び出し」にある。

## 9. Web 版を公開する

```bash
mise run deploy:web -- --project=PROJECT_ID --state-bucket=BUCKET
```

Terraform の output をビルドの引数にして、ビルド結果を `firebase/hosting` に写し、`firebase.json` の `site`（`kazokuai`）へ公開する。Firebase CLI は、`firebase.json` の外のディレクトリを受け取らない。クライアントの API キーは、リポジトリにも、このコマンドの表示にも出さない。output のプロジェクトが `--project` と違うとき、Cloud Run のリージョンとサービス名が `firebase.json` と違うとき、または `hosting_url` が `https://kazokuai.web.app` と違うときは、公開しない。

終わると `https://kazokuai.web.app` を出す。スマホとパソコンのブラウザで開く。`/api/**` は、このサイトから Cloud Run に届く。審査員には、この URL を渡す。

## 10. 審査員用アカウントを作る

このシェルに `FIRESTORE_EMULATOR_HOST` や `FIREBASE_AUTH_EMULATOR_HOST` が残っていると、本物のプロジェクトには入れずに止まる。残っていれば unset する。

```bash
mise run demo:seed -- --project=PROJECT_ID
```

`JUDGE_EMAIL` と `JUDGE_PASSWORD` を環境から読む。`.env` に書いてあれば、mise が渡す。

作るものは、審査員のアカウント、見守る方「田中 ハナ」（ID は `tanaka-hana`）、2026-10-31 から 2026-11-05 までの電話である。11 月 2 日の朝は、出なかった電話である。もう一度実行すると、パスワードを入れ直し、このアカウントの電話を見本に戻す。このアカウントだけが家族になっている見守る方は消す。ほかの家族が残る見守る方からは、このアカウントだけを外し、その電話は残す。

審査員には、手順 9 の URL と、メールアドレスとパスワードを伝える。リポジトリには書かない。

ログインしたあとに見えるもの:

- ホームと通話記録は、上の 1 週間である。いちばん新しい電話は 2026-11-05 の朝である。今日の電話が無い日は、今日の様子が「話していない」になる。
- 出なかった電話の行は「電話に出ませんでした」である。
- 電話の詳細は、その日のまとめと会話である。11 月 5 日の朝は、朝ごはん、眠り、膝の痛みが残っている。
- 予約電話は、アプリに初めから入っている見本である。Firestore には入っていない。
- 通話記録のカレンダーは、電話がある日だけ印が付く。モックにある、行の無い日の印は付かない。

## 11. 電話機をつなぐ

この手順は、人が実行する。マイクとスピーカーを使う。

`.env` の `PHONE_SECRET` を、手順 6 の合言葉と同じにしておく。mise が電話機に渡す。未設定のときは開発用の合言葉になるので、本番にはつながない。

```bash
mise run device -- --backend CLOUD_RUN_URI --watched-person tanaka-hana
```

`CLOUD_RUN_URI` は、手順 7 が表示した URL である。`https` は `wss` になる。

Web 版に審査員としてログインし、今すぐ通話を押すと、この電話機が鳴る。

## Cloud Run が tainted で残っているとき

イメージが無い状態で Cloud Run を作ろうとして失敗すると、サービスが状態に tainted で残ることがある。そのままだと、次の apply はサービスを消して作り直そうとし、削除の保護がそれを拒む。

プロジェクトは、ここでも引数で渡す。

1. tainted を外す。次の apply は、サービスを消さずにイメージを載せる。

```bash
mise run infra:untaint -- --project=PROJECT_ID --state-bucket=BUCKET
```

2. 手順 7 の `mise run deploy:backend` をやり直す。

サービスを消して作り直すときは、上の untaint のあと、削除の保護を 1 回だけ外して apply する。イメージは、push 済みの URI にする。

```bash
mise run infra:apply -- --allow-replace \
  --project=PROJECT_ID \
  --billing-account=XXXXXX-XXXXXX-XXXXXX \
  --image=IMAGE \
  --state-bucket=BUCKET
```

続いて、`--allow-replace` を付けずに、もう一度 apply する。削除の保護が戻る。`deploy:backend` の apply でも戻る。
