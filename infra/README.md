# 本番のインフラ

`infra/` の Terraform が、本番の Firebase と Google Cloud のプロジェクトに資源を作る。プロジェクトは、毎回引数で渡す。gcloud の既定のプロジェクトは使わない。

公開の一連の手順は [docs/publish.md](../docs/publish.md) にある。ここにあるのは、Terraform を動かすために人がやることと、Terraform ではできないことである。

## 状態のバケット

人が 1 回だけ作る。オブジェクトのバージョニングを付ける。`PROJECT_ID` は、作る先のプロジェクトである。

```bash
gcloud storage buckets create gs://BUCKET --project=PROJECT_ID --location=asia-northeast1 --uniform-bucket-level-access
gcloud storage buckets update gs://BUCKET --project=PROJECT_ID --versioning
```

状態のプレフィックスは `kazokuai` である。`infra/run.sh` が `terraform init` の `-backend-config` で、バケット名とこのプレフィックスを渡す。`terraform init` を、この設定なしで実行しない。

## plan と apply

```bash
mise run infra:plan -- --project=PROJECT_ID --billing-account=XXXXXX-XXXXXX-XXXXXX --image=IMAGE --state-bucket=BUCKET
mise run infra:apply -- --project=PROJECT_ID --billing-account=XXXXXX-XXXXXX-XXXXXX --image=IMAGE --state-bucket=BUCKET
```

`--region` を省くと `asia-northeast1` になる。`--billing-account` は `billingAccounts/` が付いていてもよい。予算の資源には ID だけを渡す。provider が接頭辞を付ける。

`--project` が無いと、環境変数に別のプロジェクトがあっても、terraform は起動しない。apply は確認を求める。`-auto-approve` は付けない。

`IMAGE` は、Artifact Registry に push したバックエンドのイメージの URI である。リポジトリは output の `artifact_registry` である。

## 作る順

1. 上のバケットを作る。
2. イメージと、秘密のバージョンがまだ無いときは、最初の apply が Cloud Run で失敗することがある。失敗したら、次を済ませてから同じ apply をやり直す。
3. 秘密の値を入れる。値はコマンドの引数にも、リポジトリのファイルにも書かない。標準入力で渡す。

```bash
gcloud secrets versions add gemini-api-key --project=PROJECT_ID --data-file=-
gcloud secrets versions add phone-shared-secret --project=PROJECT_ID --data-file=-
```

各コマンドのあと、値を貼って Ctrl-D で終える。名前は `gemini-api-key` と `phone-shared-secret` である。Cloud Run は、これらを環境変数 `GEMINI_API_KEY` と `PHONE_SECRET` として読む。電話機も、同じ合言葉を環境変数 `PHONE_SECRET` から読む。

4. イメージを push する。手順は [docs/publish.md](../docs/publish.md) にある。
5. apply をやり直す。

API の有効化が行き渡る前に失敗したときも、同じ apply をやり直す。

## メールアドレスとパスワードのログイン

コンソールで有効にする。Terraform の `google_identity_platform_config` は、署名の鍵を状態に書く。秘密の値を状態に置かないため、資源にはしない。

1. Firebase コンソールで、この `PROJECT_ID` の Authentication を開く。
2. ログイン方法の「メール / パスワード」を有効にする。
3. メールリンクは無効のままにする。
4. 承認済みドメインに、`localhost`、`PROJECT_ID.firebaseapp.com`、`PROJECT_ID.web.app` があることを確かめる。

審査員が登録する前に済ませる。

## すでに資源があるとき

Firestore の `(default)` や、プロジェクト ID と同じ Hosting のサイトが既にあるときは、作るのではなく取り込む。先に上の plan を 1 回実行し、状態のバケットへ init してから、同じ変数で import する。

```bash
export GOOGLE_PROJECT=PROJECT_ID
export GOOGLE_CLOUD_PROJECT=PROJECT_ID
export CLOUDSDK_CORE_PROJECT=PROJECT_ID
export GOOGLE_BILLING_PROJECT=PROJECT_ID

terraform -chdir=infra import \
  -var=project_id=PROJECT_ID \
  -var=region=asia-northeast1 \
  -var=billing_account=XXXXXX-XXXXXX-XXXXXX \
  -var=container_image=IMAGE \
  'google_firestore_database.default' 'projects/PROJECT_ID/databases/(default)'

terraform -chdir=infra import \
  -var=project_id=PROJECT_ID \
  -var=region=asia-northeast1 \
  -var=billing_account=XXXXXX-XXXXXX-XXXXXX \
  -var=container_image=IMAGE \
  google_firebase_hosting_site.web projects/PROJECT_ID/sites/PROJECT_ID
```

## 予算

月 3,000 円である。実績が 100% に達したときと、月末までの予測が 100% に達したときに通知する。通知先は、請求先アカウントの管理者である。請求先の通貨は日本円である。

## 公開の呼び出し

Cloud Run は `allUsers` に `roles/run.invoker` を付ける。Hosting の `/api/**` と、電話機からの直接の接続は、Google の IAM では公開する。家族の API は Firebase の ID トークンで、電話機の API は合言葉で、バックエンドが断る。

組織のポリシー `iam.allowedPolicyMemberDomains` が `allUsers` を拒むと、この IAM は失敗する。そのときは、このプロジェクトで `allUsers` を許す。

## 状態に入るもの

Firebase の Web アプリの設定は output に出す。`firebase_api_key` を含む。これはブラウザに渡すクライアントの設定であり、Gemini の API キーではない。

Gemini の API キーと、電話機の合言葉は、Secret Manager の名前だけを扱う。値のバージョンは Terraform で作らないので、状態に入らない。

## Hosting の `/api/**`

サイトは Terraform が作る。中身と、`/api/**` を Cloud Run に回す設定は、公開のときに `firebase.json` へ書く。空のリリースは作らない。今ある中身を消してしまう。

```json
{
  "hosting": {
    "rewrites": [
      {
        "source": "/api/**",
        "run": {
          "serviceId": "kazokuai",
          "region": "asia-northeast1"
        }
      }
    ]
  }
}
```

リージョンを変えたときは、`region` も変える。サービス名は output の `cloud_run_service` である。

電話機は output の `cloud_run_uri` に直接つなぐ。Hosting を通さない。

## output

| 名前 | 中身 |
| --- | --- |
| `firebase_api_key` | Web アプリのクライアント API キー |
| `firebase_auth_domain` | Firebase Auth のドメイン |
| `firebase_project_id` | プロジェクト ID |
| `firebase_app_id` | Web アプリの ID |
| `firebase_messaging_sender_id` | FCM の送信者 ID |
| `firebase_storage_bucket` | ストレージのバケット。未設定なら空 |
| `hosting_url` | `https://PROJECT_ID.web.app` |
| `cloud_run_service` | Cloud Run のサービス名 `kazokuai` |
| `cloud_run_region` | Cloud Run のリージョン |
| `cloud_run_uri` | 電話機がつなぐ URL |
| `artifact_registry` | イメージを push するリポジトリ |
| `gemini_api_key_secret` | 秘密の名前 `gemini-api-key`。値は出ない |
| `phone_shared_secret` | 秘密の名前 `phone-shared-secret`。値は出ない |
