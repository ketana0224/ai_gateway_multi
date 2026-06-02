# Lab 1 — APIM 基盤と Application Insights 構築

## ゴール

AI Gateway のハブとなる **Azure API Management（Developer SKU）** と、OTel / トレースの受け皿となる **Application Insights**（Workspace ベース）を作成し、両者を接続する。

## 所要時間

約 45 分（うち APIM プロビジョニングの待ち時間が 30–45 分。待機中に [Lab 2](./lab2.md) の Foundry リソース作成 + gpt-4o-mini デプロイ + mock 疎通確認（約 25 分）を並行実施してください。実際の画面操作は約 15 分）

## 事前条件

- [Lab 0](./lab0.md) 完了
- リソースグループ `rg-aigw-handson-<id>` がある
- 命名規約の `<id>` を決定済み

---

## 1-1. Log Analytics ワークスペース作成

Application Insights（Workspace ベース）はテレメトリデータの保存先として **Log Analytics ワークスペース**を必要とします。先にワークスペースを作成しておき、1-2 の Application Insights 作成時に紐付けます。Lab 6 では KQL クエリをこのワークスペースに対して実行します。

1. Portal 検索バーで **「Log Analytics ワークスペース」** → **作成**
2. 設定:
   - リソース グループ: `rg-aigw-handson-<id>`
   - 名前: `log-aigw-<id>`
   - リージョン: `Japan East`
3. **確認と作成** → **作成**

## 1-2. Application Insights 作成

**Application Insights** は APIM が送信するリクエストログ・依存関係トレース・メトリクスの収集・可視化サービスです。本ハンズオンでは **Workspace ベース**モードを使用します。従来の Classic モードとは異なり、データは 1-1 で作成した Log Analytics ワークスペースに格納されるため、KQL による横断クエリが可能になります。

1. Portal 検索バーで **「Application Insights」** → **作成**
2. 設定:
   - リソース グループ: `rg-aigw-handson-<id>`
   - 名前: `appi-aigw-<id>`
   - リージョン: `Japan East`
   - リソースモード: **Workspace ベース**
   - ログ分析ワークスペース: 1-1 で作成した `log-aigw-<id>`
3. **確認と作成** → **作成**
4. 作成完了後、**プロパティ** から **接続文字列** をコピーし、安全な場所にメモ
   - 形式: `InstrumentationKey=xxx;IngestionEndpoint=https://...`

---

### Log Analytics と Application Insights の役割

```
APIM ──(テレメトリ送信)──► Application Insights ──(データ格納)──► Log Analytics ワークスペース
                                  │
                                  ├─ リクエストログ（AppRequests）
                                  ├─ 依存関係トレース（AppDependencies）
                                  └─ メトリクス（AppMetrics）
```

| リソース | 役割 |
|---|---|
| **Log Analytics ワークスペース** (`log-aigw-<id>`) | テレメトリデータの**永続化・クエリ基盤**。KQL でログを検索・集計できる |
| **Application Insights** (`appi-aigw-<id>`) | APIM からテレメトリを受け取る**収集エンドポイント**。ダッシュボード・アラート・トレース可視化を提供する |

2 つは別リソースですが、Workspace ベースモードでは Application Insights の実データはすべて Log Analytics に格納されます。Application Insights はあくまで**フロントエンド（受け口 + UI）**、Log Analytics が**バックエンド（ストレージ + クエリエンジン）**です。

---

## 1-3. APIM 作成（Developer SKU）

> :warning: **SKU の選択に注意**
> Lab 4 で Self-hosted Gateway を使うため、**Classic Developer** または Premium が必須です。
> Consumption / StandardV2 / Basic v2 を選ぶと Lab 4 で `MethodNotAllowedInPricingTier` エラーになります。

1. Portal 検索バーで **「API Management サービス」** → **作成**
2. **基本** タブ:
   - リソース グループ: `rg-aigw-handson-<id>`
   - リージョン: `Japan East`
   - リソース名: `apim-aigw-<id>`
   - 組織名: 任意（例: `aigw-handson`）
   - 管理者メール: 自分のアドレス
   - 価格レベル: **Developer (no SLA)**
   - 容量: `1`
3. **監視とセキュリティ保護** タブ:
   - **Log Analytics**: **チェックを入れる**
     - サブスクリプション: 既定
     - ログ分析ワークスペース: 1-1 で作成した `log-aigw-<id> (japaneast)`
   - **Microsoft Defender for Cloud の Defender for API**: **チェックを入れない**（コスト発生のため本ハンズオンでは不要）
   - **Application Insights**: **チェックを入れる**
     - インスタンスの選択: 1-2 で作成した `appi-aigw-<id>`
4. **ネットワーク** タブ:
   - 接続の種類: **なし**（パブリック IP アドレスで公開。Lab 4 の外部 SHGW から接続するため、仮想ネットワーク/プライベートエンドポイントは選ばない）
5. **マネージド ID** タブ:
   - **システム割り当てマネージド ID** セクションの **状態** チェックボックス: **オン（チェック）**（Lab 3 で Microsoft Foundry の gpt-4o-mini に MI 認証で接続するため必須）
6. **タグ** タブ: 任意
7. **確認とインストール** → **作成**

> :hourglass: プロビジョニングは 30–45 分かかります。**この間に [Lab 2](./lab2.md) の Foundry リソース作成 + gpt-4o-mini デプロイ + mock 疎通確認（約 25 分）を済ませておいてください**。

## 1-4. APIM の Application Insights ロガー設定確認

APIM は API を通過するすべてのリクエスト・レスポンスのテレメトリ（リクエスト数・レイテンシ・エラー率など）を Application Insights へ送信できます。この送信を担うのが **Application Insights ロガー**です。1-3 の作成ウィザードで Application Insights を選択した場合、ロガーは自動作成されますが、**サンプリング率や詳細レベルが意図通りになっているか** をここで確認します。サンプリングを 100 % にしないとリクエストがログから欠落し、Lab 6 のトレース確認で結果が見えないことがあります。

APIM 作成後（プロビジョニング完了後）:

1. APIM リソース → 左メニュー **監視 > Application Insights**
2. リストに `appi-aigw-<id>` が表示されていることを確認
   - 行をクリックすると Application Insights リソース画面に移動します（接続が確立していることを確認できます）
3. サンプリング率・詳細レベルの設定は **左メニュー APIs → API → All APIs → Settings タブ → Diagnostics Logs** から行います:
   - **Application Insights** タブを選択
   - Sampling (%): **100**
   - Verbosity: **Verbose**（デフォルトは **Information**。`Verbose` にするとリクエスト・レスポンスのヘッダーや本文もログに含まれ、Lab 6 のトレース確認で詳細が見えるようになります）
   - Correlation protocol: **Legacy**（デフォルトのまま。Lab 6 で W3C に変更します）
   - **Save**

> :information_source: サンプリングが 100 % でないとリクエストがログから欠落し、Lab 6 のトレース確認で結果が見えないことがあります。

## 1-5. APIM の管理者キー / Gateway URL を控える

APIM リソース → 概要 で以下をメモ:

| 項目 | 例 | 用途 |
|---|---|---|
| ゲートウェイ URL | `https://apim-aigw-<id>.azure-api.net` | Lab 3 で curl 実行先 |
| 構成 URL | `apim-aigw-<id>.configuration.azure-api.net` | Lab 5 SHGW で使用 |

## チェックリスト

- [ ] Log Analytics ワークスペース作成済み
- [ ] Application Insights（Workspace ベース）作成済み、接続文字列を控えた
- [ ] APIM（Developer SKU）作成完了、ゲートウェイ URL を控えた
- [ ] APIM ↔ Application Insights が紐付け済み

完了したら [Lab 2 — mock エンドポイントの確認](./lab2.md) へ。
