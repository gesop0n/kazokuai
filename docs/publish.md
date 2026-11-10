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
- `PHONE_SECRET` は、`phone-shared-secret` に入れた合言葉と同じにする。電話機は、登録するときだけこれを付ける。
- `JUDGE_EMAIL` と `JUDGE_PASSWORD` は、審査員用アカウントである。パスワードは 6 文字以上にする。

## 7. バックエンドを公開する

```bash
mise run deploy:backend -- --project=PROJECT_ID
```

Mac が Apple Silicon でも、イメージは `linux/amd64` で作る。Cloud Run が動かす形である。タグは、実行の時刻と git のリビジョンから作る。push のあと、`gcloud run deploy` でサービス `kazokuai` の新しいリビジョンにする。環境変数、秘密、インスタンス数は渡さない。今のサービスに残っているものを使う。タグは付けない。Terraform は適用しない。

終わると、イメージの URI と、電話機がつなぐ URL を出す。

サービスがまだ無いときは、イメージを push したあとで止まる。表示された URI を `IMAGE` にして、次の apply で Cloud Run を作る。`--bootstrap` は付けない。`--allow-replace` も付けない。確認を求める。

```bash
mise run infra:apply -- \
  --project=PROJECT_ID \
  --billing-account=XXXXXX-XXXXXX-XXXXXX \
  --image=IMAGE \
  --state-bucket=BUCKET
```

plan が Cloud Run か、どちらかの Hosting のサイトを replace するときは、適用しない。サービスができたあとの apply は、イメージの変更を無視する。ワークフローが載せたイメージを戻さない。

push が、Artifact Registry のリポジトリが無いと言って失敗したときは、手順 5 をやり直してから、もう一度このコマンドを実行する。`allUsers` の IAM で失敗したときは、手順 8 の組織ポリシーを直してから、上の apply をやり直す。Cloud Run が状態に tainted で残ったときは、うしろの「Cloud Run が tainted で残っているとき」で戻す。

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

審査の当日の朝に実行する。見本の 1 週間は、実行した日の朝で終わる。前日に実行すると、審査の日の電話が無く、今日の様子は「話していない」になる。

このシェルに `FIRESTORE_EMULATOR_HOST` や `FIREBASE_AUTH_EMULATOR_HOST` が残っていると、本物のプロジェクトには入れずに止まる。残っていれば unset する。

```bash
mise run demo:seed -- --project=PROJECT_ID
```

`JUDGE_EMAIL` と `JUDGE_PASSWORD` を環境から読む。`.env` に書いてあれば、mise が渡す。

作るものは、審査員のアカウント（名前は「田中 太郎」）、見守る方「田中 ハナ」（ID は `tanaka-hana`）、実行した日の朝で終わるおよそ 7 日分の電話、実行した日の翌日以降の見本の予約 3 件である。時刻は日本時間である。3 日前の朝は、出なかった電話である。いちばん新しい電話は実行した日の朝で、伝言（伝えたいことと通話内容）と、その返答を持つ。見本の予約は、翌日の 12:00 と 19:00、3 日後の 10:00 で、伝えたいことと通話内容が入っている。タスクは作らないので、審査のあいだは鳴らない。もう一度実行すると、パスワードと名前を入れ直し、日付をその日に合わせ、このアカウントの電話と見本の予約を見本に戻す。予約は 3 件のままである。チュートリアルを見た記録も消すので、審査員はもう一度見る。このアカウントだけが家族になっている見守る方は、電話と予約ごと消す。ほかの家族が残る見守る方からは、このアカウントだけを外し、その電話と予約は残す。

審査員には、手順 9 の URL と、メールアドレスとパスワードを伝える。リポジトリには書かない。

ログインしたあとに見えるもの:

- ホームと通話記録は、上の 1 週間である。いちばん新しい電話は、実行した日の朝である。その日にアプリを開くと、今日の様子に今日の電話が出て、ホームのいちばん上に伝言への返答が出る。
- 出なかった電話の行は「電話に出ませんでした」である。
- 電話の詳細は、その日のまとめと会話である。いちばん新しい朝の電話は、朝ごはん、眠り、膝の痛みと、通院の伝言への返答が残っている。
- 予約電話の画面は、アプリに初めから入っている見本である。Firestore には、上の見本の予約 3 件が入っている。タスクは無いので鳴らない。審査員が新しく作った予約や直した予約には、そのときにタスクができる。
- ホームの歯車から設定を開く。アカウント情報の名前は「田中 太郎」で、メールアドレスは審査員のものである。登録日は、このアカウントを作った日である。
- 通話記録のカレンダーは、電話がある日だけ印が付く。モックにある、行の無い日の印は付かない。

## 11. 電話機をつなぐ

この手順は、人が実行する。マイクとスピーカーを使う。

`.env` の `PHONE_SECRET` を、手順 6 の合言葉と同じにしておく。mise が電話機に渡す。未設定のときは開発用の合言葉になるので、本番にはつながない。

```bash
mise run device -- --backend CLOUD_RUN_URI
```

`CLOUD_RUN_URI` は、手順 7 が表示した URL である。`https` は `wss` になる。電話機は自分の ID と鍵でつながる。家族がアプリからこの電話機を同期すると、その見守る方の電話を受ける。

Web 版に審査員としてログインし、電話機を同期してから今すぐ通話を押すと、この電話機が鳴る。

## 12. GitHub Actions から公開する

この手順は、人が 1 回実行する。ワークフローは、GitHub の Actions の画面から動かす。

すでに Cloud Run と、Hosting のサイトが 2 つある。次の apply を 1 回実行する。プールと GitHub のプロバイダーと、デプロイ用のサービスアカウントを足す。Cloud Run と両方の Hosting サイトの `deletion_policy` を `PREVENT` にする。この属性は ForceNew ではない。名前、ロケーション、サイト ID、アプリ ID は変えないので、これらの資源はその場で変わる。plan が Cloud Run か、どちらかのサイトを replace するときは、適用しない。

`IMAGE` は要る。今動いているイメージの URI でよい。Terraform はイメージの変更を無視するので、この値では戻さない。

`--bootstrap` は付けない。このフラグは Workload Identity も、Cloud Run へのデプロイ権限も作らない。`--allow-replace` も付けない。

手順 7 で、サービスが無かったあとに同じ apply を既に実行したときは、ここでの apply は繰り返さなくてよい。変数の設定と、ワークフローの実行はする。

```bash
mise run infra:apply -- \
  --project=PROJECT_ID \
  --billing-account=XXXXXX-XXXXXX-XXXXXX \
  --image=IMAGE \
  --state-bucket=BUCKET
```

apply のあと、output を GitHub のリポジトリ変数に入れる。secret にはしない。どれも秘密の値ではない。`firebase_api_key` は、ブラウザに渡すクライアントの設定である。Gemini の API キーと、電話機の合言葉は、ここへ入れない。

プロジェクトは、環境変数で渡す。gcloud の既定のプロジェクトは使わない。

```bash
export GOOGLE_PROJECT=PROJECT_ID
export GOOGLE_CLOUD_PROJECT=PROJECT_ID
export CLOUDSDK_CORE_PROJECT=PROJECT_ID
export GOOGLE_BILLING_PROJECT=PROJECT_ID

terraform -chdir=infra init \
  -input=false \
  -reconfigure \
  -backend-config="bucket=BUCKET" \
  -backend-config="prefix=kazokuai"

repo=gesop0n/kazokuai
gh variable set GCP_PROJECT --repo "$repo" --body "PROJECT_ID"
gh variable set GCP_REGION --repo "$repo" --body "asia-northeast1"
gh variable set WORKLOAD_IDENTITY_PROVIDER --repo "$repo" \
  --body "$(terraform -chdir=infra output -raw workload_identity_provider)"
gh variable set DEPLOY_SERVICE_ACCOUNT --repo "$repo" \
  --body "$(terraform -chdir=infra output -raw deploy_service_account)"
gh variable set FIREBASE_API_KEY --repo "$repo" \
  --body "$(terraform -chdir=infra output -raw firebase_api_key)"
gh variable set FIREBASE_AUTH_DOMAIN --repo "$repo" \
  --body "$(terraform -chdir=infra output -raw firebase_auth_domain)"
gh variable set FIREBASE_APP_ID --repo "$repo" \
  --body "$(terraform -chdir=infra output -raw firebase_app_id)"
gh variable set FIREBASE_MESSAGING_SENDER_ID --repo "$repo" \
  --body "$(terraform -chdir=infra output -raw firebase_messaging_sender_id)"
gh variable set FIREBASE_PROJECT_ID --repo "$repo" \
  --body "$(terraform -chdir=infra output -raw firebase_project_id)"
gh variable set FIREBASE_STORAGE_BUCKET --repo "$repo" \
  --body "$(terraform -chdir=infra output -raw firebase_storage_bucket)"
```

`workload_identity_provider` は、プロジェクト番号を含むプロバイダーの名前である。`deploy_service_account` は、デプロイ用のサービスアカウントのメールアドレスである。ストレージのバケットが空なら、その変数は空の文字列になる。

GitHub の Actions で、ワークフロー `deploy` を `main` から手で 1 回動かす。`workflow_dispatch` だけがきっかけである。先に `mise run check` が動き、そのあと手元と同じ `mise run deploy:backend` と `mise run deploy:web` が動く。状態のバケットは読まない。デプロイ用のサービスアカウントに、状態を読む権限は付いていない。ランナーには Docker があり、ワークフローが gcloud を入れる。

終わると `https://kazokuai.web.app` に、そのビルドが出る。

## Cloud Run が tainted で残っているとき

イメージが無い状態で Cloud Run を作ろうとして失敗すると、サービスが状態に tainted で残ることがある。そのままだと、次の apply はサービスを消して作り直そうとする。`deletion_protection` と、状態の `deletion_policy` が `PREVENT` のときは、その削除を拒む。

プロジェクトは、ここでも引数で渡す。

1. tainted を外す。次の apply は、サービスを消そうとしない。

```bash
mise run infra:untaint -- --project=PROJECT_ID --state-bucket=BUCKET
```

2. 手順 7 の `mise run deploy:backend` をやり直す。サービスがあるときは、`gcloud run deploy` が新しいリビジョンを載せる。Terraform はこのイメージを無視する。

サービスを消して作り直すときは、状態の `deletion_policy` を先に `DELETE` にする。`PREVENT` のまま `--allow-replace` を付けても、プロバイダーは消さない。プロバイダーは、設定ではなく状態の値を見る。

1. tainted なら、上の untaint で外す。plan が replace のままだと、`deletion_policy` の変更も replace になり、状態が `PREVENT` のまま消そうとして失敗する。
2. `infra/run.tf` の Cloud Run の `deletion_policy` を `DELETE` にし、`--allow-replace` を付けずに apply する。plan は、その場の変更だけであることを確かめる。Cloud Run も、どちらの Hosting のサイトも replace していないこと。
3. `deletion_policy` を `PREVENT` に戻す。サービスを再び tainted にする。前の apply で、状態のバケットへは init 済みである。

```bash
export GOOGLE_PROJECT=PROJECT_ID
export GOOGLE_CLOUD_PROJECT=PROJECT_ID
export CLOUDSDK_CORE_PROJECT=PROJECT_ID
export GOOGLE_BILLING_PROJECT=PROJECT_ID

terraform -chdir=infra taint \
  -var=project_id=PROJECT_ID \
  -var=region=asia-northeast1 \
  -var=billing_account=XXXXXX-XXXXXX-XXXXXX \
  -var=container_image=IMAGE \
  google_cloud_run_v2_service.backend
```

4. `--allow-replace` を付けて apply する。イメージは、push 済みの URI にする。この apply はサービスを消して作り直す。

```bash
mise run infra:apply -- --allow-replace \
  --project=PROJECT_ID \
  --billing-account=XXXXXX-XXXXXX-XXXXXX \
  --image=IMAGE \
  --state-bucket=BUCKET
```

5. `--allow-replace` を付けずに、もう一度 apply する。`deletion_protection` が戻る。`deletion_policy` は `PREVENT` のままである。`deploy:backend` は Terraform を適用しないので、保護は戻さない。

## すでに公開しているプロジェクトで予約の電話を有効にする

Cloud Run が既にあるプロジェクトで、予約の時刻に電話をかける。Terraform が Cloud Tasks のキュー、タスクのサービスアカウント、バックエンドへの 3 つの設定を足す。資源の中身は [infra/README.md](../infra/README.md) の「予約の Cloud Tasks」にある。

次の apply を 1 回実行する。`--bootstrap` は付けない。このフラグはキューを作らない。`--allow-replace` も付けない。plan が Cloud Run か、どちらかの Hosting のサイトを replace するときは、適用しない。

```bash
mise run infra:apply -- \
  --project=PROJECT_ID \
  --billing-account=XXXXXX-XXXXXX-XXXXXX \
  --image=IMAGE \
  --state-bucket=BUCKET
```

`IMAGE` は、今動いているイメージの URI でよい。Terraform はイメージの変更を無視する。

バックエンド自身の URL は `https://kazokuai-PROJECT_NUMBER.asia-northeast1.run.app` である。Terraform がプロジェクト番号から組む。Cloud Run のサービスから読まない。読むと、設定するサービスが自分に頼る。予約のタスクは、この URL の `/tasks/bookings` を、タスクのサービスアカウントの OIDC トークンで呼ぶ。audience も、この URL である。

apply のあと、新しいバックエンドを載せる。環境変数は渡さない。apply が足したものを残す。

```bash
mise run deploy:backend -- --project=PROJECT_ID
```

人が確かめる。アプリで 3 分先に予約し、電話機が鳴るのを聞く。その予約をあとの時刻に直し、前の時刻には鳴らないことも確かめる。
