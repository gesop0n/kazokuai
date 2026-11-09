# リポジトリ内の決定事項をまとめる (Architecture Decision Records)

## ADR の内容

### ファイル名
`YYYYMMDD_<title>.md`

### Status
この判断が今どの段階かを表す。
- `Proposed`: まだ決めていない、またはレビュー中
- `Accepted`: 採用して実装に入った、または入る前提
- `Rejected`: 検討したが不採用
- `Deprecated`: 以前は正しかったが、もう推奨しない状態
- `Superseded by ADR-<ADR_NUMBER>`: 別の判断に置き換わった状態

### Context
決定が必要になった背景

### Decision 
何を決めたか

### Consequences
影響とトレードオフ


## ADR 一覧

| No. | タイトル | Status |
| --- | --- | --- |
| [00000000_template](00000000_template.md) | アーキテクチャ判断を記録する | Accepted |
| [20261105_mobile_development_policy](20261105_mobile_development_policy.md) | モバイルアプリの開発方針 | Accepted |
| [20261106_mobile_demo_behavior](20261106_mobile_demo_behavior.md) | モバイルアプリのデモの動き | Accepted |
| [20261106_device_backend_architecture](20261106_device_backend_architecture.md) | デバイスおよびバックエンドのアーキテクチャ | Accepted |
| [20261107_development_process](20261107_development_process.md) | 開発プロセス | Accepted |
| [20261107_issue_pr_writing](20261107_issue_pr_writing.md) | issue とプルリクエストの書き方 | Accepted |
| [20261107_single_reviewer](20261107_single_reviewer.md) | レビュー役を Codex だけにする | Accepted |
| [20261107_grok_implementer](20261107_grok_implementer.md) | 実装役を Grok だけにする | Accepted |
| [20261107_biz_udp_gothic](20261107_biz_udp_gothic.md) | アプリのフォントを BIZ UDPゴシックだけにする | Accepted |
| [20261108_mock_narrowed_navigation](20261108_mock_narrowed_navigation.md) | モックで機能を絞ったあとの画面の移り方とデモの動き | Accepted |
| [20261109_bluetooth_sync](20261109_bluetooth_sync.md) | 電話機との同期と Wi-Fi の設定を Bluetooth LE で行う | Accepted |
| [20261109_cloud_run_one_instance](20261109_cloud_run_one_instance.md) | Cloud Run を 1 インスタンスにし、つながっている電話機をメモリーで持つ | Accepted |
| [20261109_four_tickets](20261109_four_tickets.md) | 同時に最大 4 つのチケットを動かす | Accepted |
