# 目的
AI Gatewayのハンズオンキットを作成する
ハンズオンはAzure Portalで行う
ハンズオンテーマは、
・APIM（AI Gateway）経由で他ベンダーLLMへ接続する構成（実際に他ベンダーのLLMは用意できないため、Azureにmimicを作成する）
・AWS環境上でAPIMを展開・利用するパターン（実 AWS は使用せず、Azure Container Apps を「AWS 相当の外部環境」として模擬する）
・OpenTelemetryを用いたモニタリング／トレーシング関連


# 環境制約
最も安価なAzure構成とする。**AWS アカウントは使用しない**（AWS 環境も Azure 上で mimic）。

# 実行計画

## 全体像

3 テーマ（他ベンダー LLM mimic 接続 / 外部環境(AWS 相当)での APIM SHGW / OpenTelemetry）を **8 つの Lab（Lab 0　7）** に分割し、Azure Portal 操作を中心にハンズオン化する。SKU は「最安かつ要件を満たす最小構成」を選定。

> **AWS パターンの扱い**: AWS アカウントを用意しないため、APIM Self-hosted Gateway（SHGW）を **Azure Container Apps（別リソースグループ）** にデプロイし、「APIM コントロールプレーンとは別環境で動くデータプレーン」というマルチクラウド構成を体験的に再現する。コンテナイメージ・設定方法・トークン認可は AWS 上で動かす場合と同一なので、本番で AWS / GCP / オンプレに置き換える際の差分はホスティング先のみ。

### アーキテクチャ（最終形）

```
[利用者 / curl / Notebook]
        │
        ▼
┌──────────────────────────────┐
│  Azure APIM (Developer SKU)  │  ← AI Gateway ポリシー適用
│   - Token Limit / Metric     │  ← Control Plane
│   - Content Safety           │
│   - OTel / App Insights      │
└──────────────────────────────┘
        │                          │
        │ (Azure 直結)             │ (外部=AWS 相当ホスティング 経由)
        ▼                          ▼
┌──────────────────┐   ┌─────────────────────────────────────┐
│ Azure Container Apps │   │ Azure Container Apps                │
│ (講師事前デプロイ)   │   │  (rg-aigw-handson-<initials>)        │
│  AWS Bedrock Runtime│   │  Image: mcr.../api-management/gateway│
│  互換 mimic         │   │  Replicas: 1 (always-on)            │
│  (Anthropic Claude) │   │  = APIM Self-hosted Gateway (SHGW)  │
└──────────────────┘   │  （AWS EC2/EKS/Fargate と同じ image）│
        │              └─────────────────────────────────────┘
        │                          │
        ▼                          ▼
   Application Insights（トレース・トークン数）
```

### SKU / コスト方針（最安構成）

| リソース | SKU | 理由 |
|---|---|---|
| APIM | **Developer (Classic)** | Self-hosted Gateway は Classic Developer / Premium のみ対応（StandardV2 不可）。Developer が最安。 |
| Azure Container Apps (mimic) | Consumption / 0.5 vCPU / 1 GiB / minReplicas=0 | 講師が事前に 1 セットだけデプロイ。アイドル時は 0 スケーリングで課金せず、設定は残す。 |
| Application Insights | Pay-as-you-go (Workspace based) | 1GB/月 無料枠で収まる想定。 |
| Container Apps (SHGW "AWS 相当") | Consumption / 0.25 vCPU / 0.5 GiB / minReplicas=1 | OS 管理不要、Portal で完結。停止すれば 0 円。VM の代替で最安かつ AWS Fargate 相当のサーバレスコンテナ体験。 |
| Azure OpenAI | **不使用**（mimic で代替） | 課金回避。実 LLM が必要な場合のみ最小 SKU。 |
| ネットワーク | Public Endpoint | VNet / Private Endpoint は使わずコスト最小化。 |

> 本ハンズオンでは簡素化のため SHGW Container App もコアリソースと同じ `rg-aigw-handson-<initials>` にデプロイし、「別クラウド感」は Gateway リソースの `locationData` ラベルで表現する。

---

## Lab 0: 環境準備（所要 15 分）

**目的**: ハンズオンに必要な CLI / リソースグループ / 命名規約を揃える。

- [ ] Azure サブスクリプション（共同作成者ロール）
- [ ] Azure CLI (`az --version` >= 2.60)、`curl`、VS Code（Docker / AWS CLI は不要）
- [ ] リソースグループを 2 つ作成
  - `rg-aigw-handson-<initials>` (japaneast) — APIM / Container Apps (mimic, SHGW) / App Insights / Foundry を一元管理
- [ ] 命名規約決定（`apim-aigw-<initials>`, `aca-shgw-<initials>` 等。mimic は講師配布の `<MIMIC_BASE_URL>` を使用）

**成果物**: 空のリソースグループ 2 つ、`az login` 済み環境。

---

## Lab 1: APIM 基盤と Application Insights 構築（所要 45 分）

**目的**: AI Gateway のハブとなる APIM を最安 SKU で立ち上げ、OTel の受け皿を用意する。

1. **Application Insights（Workspace ベース）作成**
   - Portal: Monitor → Application Insights → 作成
   - Log Analytics Workspace を同時作成（既定）
2. **APIM 作成（Developer SKU）**
   - Portal: API Management サービス → 作成
   - 価格レベル: **Developer (no SLA)** を選択
   - デプロイに約 30–45 分かかるため、待機中に Lab 2 の mimic 疎通確認を済ませる
3. **App Insights を APIM に紐付け**
   - APIM → Application Insights → 接続文字列ベースで追加
   - すべての API でデフォルト有効化、サンプリング 100%

**ハンズオン確認ポイント**:
- Self-hosted Gateway を使う Lab 4 のために **Classic Developer SKU** を選んでいるか
- Consumption / StandardV2 を選ぶと Lab 4 で `MethodNotAllowedInPricingTier` になる

---

## Lab 2: Mimic エンドポイントの確認（講師事前準備済み、参加者所要約 5 分）

**目的**: 講師が事前にデプロイした **AWS Bedrock Runtime 互換 mimic エンドポイント**（`<MIMIC_BASE_URL>`）に対して疎通確認を行う。

> 参加者は Container App を作る必要はない。講師は Anthropic Claude を AWS Bedrock にホストしている体を模した mimic（FastAPI 1 つに Bedrock Converse / InvokeModel の 2 ルートを同居）を事前に作成し、参加者に Base URL を配布する。

### 2-1. 配布される AWS Bedrock Runtime 互換エンドポイント
- `POST <MIMIC_BASE_URL>/model/{modelId}/converse`（Bedrock Converse API）
- `POST <MIMIC_BASE_URL>/model/{modelId}/invoke`（Bedrock InvokeModel API、Anthropic ネイティブ body）

### 2-2. mimic のエンドポイント仕様

| API | パス | リクエスト形式 | レスポンス形式 |
|---|---|---|---|
| Bedrock Converse | `POST /model/{modelId}/converse` | `{"messages":[{"role":"user","content":[{"text":"..."}]}],"inferenceConfig":{...}}` | `{"output":{"message":{"role":"assistant","content":[{"text":"..."}]}},"stopReason":"end_turn","usage":{"inputTokens","outputTokens","totalTokens"}}` |
| Bedrock InvokeModel | `POST /model/{modelId}/invoke` | `{"anthropic_version":"bedrock-2023-05-31","max_tokens":N,"messages":[{"role":"user","content":[{"type":"text","text":"..."}]}]}` | Anthropic ネイティブ `{"id","type":"message","role":"assistant","content":[{"type":"text","text":"..."}],"stop_reason":"end_turn","usage":{"input_tokens","output_tokens"}}` |

### 2-3. mimic ロジック（講師実装側の要件）
- 入力プロンプトをエコー or 固定文字列で返す
- `usage` にダミーのトークン数を返す（後段の token-metric ポリシー検証用）
- 200 ms 程度の `sleep` を入れて、レイテンシ計測に意味を持たせる
- **AWS SigV4 署名は検証しない**（APIM が MS Learn 手順に従って署名を付与した Authorization ヘッダーは受け取るが無視）
- 関数キーは付けず匿名（APIM 側で認証を担う）

**成果物**: 講師から配布された `<MIMIC_BASE_URL>` と、Bedrock Converse / InvokeModel 形式での 200 OK レスポンス確認。

---

## Lab 3: Microsoft Foundry と APIM AI Gateway の連携（所要 50 分）

**目的**: 実 Azure OpenAI モデル（Foundry の gpt-4o-mini）を APIM 起点のウィザードで `openai-api` として取り込み、Backend / Managed Identity 認証 / トークン制限ポリシーをコード無しで自動構成する。

### 3-1. `openai-api` — Microsoft Foundry ウィザードで登録
- `APIM → APIs → + API の追加 → Create from Azure resource → Microsoft Foundry`
- Select AI Service: `aif-aigw-<initials>` を選択（`gpt-4o-mini` デプロイ済みであること）
- Configure API: 表示名 `OpenAI API` / 名前 `openai-api` / Base path `openai` / Client compatibility = **Azure OpenAI**
- Manage token consumption: **オン**（TPM=1000、`Estimate prompt tokens` ON、その他ヘッダー出力はオフ）
- Apply semantic caching / AI content safety: オフ

ウィザード完了で以下が自動生成される。
- API `openai-api` と Azure OpenAI オペレーション群（`chat/completions` / `embeddings` / `responses` 等）
- Backend `openai-api-ai-endpoint`（URL = Foundry endpoint、認証 = **Managed identity**）
- APIM の System-assigned MI に Foundry の `Cognitive Services OpenAI User` ロールが自動付与
- Inbound に `set-backend-service` + `llm-token-limit` が自動挿入

### 3-2. 自動生成ポリシーの確認
`openai-api → Design → All operations → Inbound processing` をコードエディタで開き、以下が挿入されていることを確認。

```xml
<inbound>
    <base />
    <set-backend-service id="apim-generated-policy" backend-id="openai-api-ai-endpoint" />
    <llm-token-limit tokens-per-minute="1000" counter-key="@(context.Subscription.Id)" estimate-prompt-tokens="true" />
</inbound>
```

> Managed Identity による Foundry 認証は **Backend リソース側** で構成されるので、API ポリシーには `authentication-managed-identity` は現れない。

### 3-3. サブスクリプション キーの発行
`APIM → サブスクリプション → + 追加`（名前 `sub-aigw-handson` / スコープ All APIs）。**主キー**をメモ（Lab 4 以降でも流用）。

### 3-4. 動作確認
- Portal Test タブ から `POST /openai/responses?api-version=2025-03-01-preview` で 200 + 実 gpt-4o-mini 応答を確認
- PowerShell `curl.exe` で `api-key: <sub key>` ヘッダー付きで同上を確認

### 3-5. （任意）セマンティック キャッシュ / Content Safety
本ラボでは扱わない。`Apply semantic caching` タブ で Azure Managed Redis + Embeddings デプロイメントを指定すれば有効化可能。Content Safety も同様にウィザードから設定可能。

**成果物**: APIM 起点で実 gpt-4o-mini が呼び出せる `openai-api`。

---

## Lab 4: 他ベンダー LLM（AWS Bedrock の Anthropic Claude）の APIM への登録（所要 60 分）

**目的**: 講師配布の mimic を **AWS Bedrock Runtime 互換 API** として APIM に取り込み、Foundry 上の OpenAI と AWS Bedrock 上の Anthropic Claude を **1 つの AI Gateway に一元登録**する。手順は [MS Learn: Amazon Bedrock passthrough LLM API](https://learn.microsoft.com/azure/api-management/amazon-bedrock-passthrough-llm-api) をそのまま踏襲し、Backend URL に `<MIMIC_BASE_URL>` を使う。

### 4-1. `bedrock-api` — Language Model API（Passthrough）で登録
- `APIM → APIs → + API → Define a new API → Language Model API`
- Configure API: 表示名 `Bedrock API` / 名前 `bedrock-api` / URL = `<MIMIC_BASE_URL>` / Path = `bedrock` / 種類 = **Create a passthrough API**
- Manage token consumption: オン（TPM=1000）。他 2 タブはオフ

> Passthrough を選ぶと全 HTTP verb のワイルドカード オペレーションが生成され、`POST /model/{modelId}/converse` 等を透過送信できる。

### 4-2. AWS SigV4 署名 Inbound ポリシー
1. **Named Values** に `accesskey` / `secretkey` を **シークレット** で作成（mimic はダミー値で OK、本番では IAM ユーザーのキーを格納）
2. `bedrock-api → All operations → ポリシー → Inbound` に MS Learn ページ「インバウンドリクエストに AWS SigV4 認証を追加する」の XML 全文を貼り付け
3. APIM が `Authorization: AWS4-HMAC-SHA256 ...` / `X-Amz-Date` / `X-Amz-Content-Sha256` / `Host` を自動生成する（region=`us-east-1`、service=`bedrock`）

### 4-3. 構成サマリ
| API | 自動生成 Backend | プロトコル / 認証 |
|---|---|---|
| `openai-api` | `openai-api-ai-endpoint` | Foundry endpoint / **Managed identity** |
| `bedrock-api` | `bedrock-api-backend` | `<MIMIC_BASE_URL>` / なし（SigV4 は Inbound で付与） |

### 4-4. 動作確認
- Portal Test → `bedrock-api → Wildcard (POST)` で URL template = `/model/us.anthropic.claude-3-5-haiku-20241022-v1:0/converse`、body = Bedrock Converse 形式。`Echo: ...` がレスポンスに見えれば成功。**Trace に `Authorization: AWS4-HMAC-SHA256 ...` ヘッダー** が APIM 側で生成されていることを確認
- PowerShell から `api-key: <sub key>` で 2 API（`openai-api` / `bedrock-api`）に 200
- App Insights メトリクス: namespace に `openai-api` / `bedrock-api` が並び、`Total Tokens` を `api-id` で分割すると API 別の消費量が見える

**成果物**: 1 つの APIM 配下で Foundry の OpenAI と AWS Bedrock の Anthropic Claude を横並びでガバナンス可能な構成。

---

## Lab 5: 外部環境(AWS 相当)で APIM Self-hosted Gateway を展開（所要 75 分）

**目的**: APIM のデータプレーン（SHGW）を **別ホスティング** にデプロイし、マルチクラウド構成をシミュレートする。**実 AWS は使用せず、Azure Container Apps** を「AWS 相当の外部環境」として利用。コンテナイメージ・環境変数・トークン認可は AWS Fargate / EKS / EC2 で動かす場合と完全に同一。

### 5-1. APIM 側で Gateway リソースを作成
- APIM → **デプロイとインフラストラクチャ > ゲートウェイ → ＋ 追加**
- 名前 `gw-ext-tokyo-<initials>` / リージョン（任意ラベル）`aws-ap-northeast-1` / 説明 `External SHGW (AWS-mimic on Container Apps)`
- リージョンは Azure 実リージョンではなく **`locationData.name` の任意ラベル**

### 5-2. Gateway に LLM API をバインド
- `gw-ext-tokyo-<initials> → API タブ → ＋ 追加` で **`openai-api`** / **`bedrock-api`** を順に追加

### 5-3. Gateway トークンを生成（30 日有効）
Portal で Gateway 概要から `Generate token` を選ぶか、ARM REST `gateways/{id}/generateToken?api-version=2022-08-01` を叩いて `value` を取得。

### 5-4. Container Apps 環境と SHGW Container App を起動
- 同一 RG `rg-aigw-handson-<initials>` で簡素化（「別クラウド感」は `locationData` ラベルで表現）
- Container Apps 環境: Consumption / 既存 Log Analytics に紐付け
- Container App `aca-shgw-<initials>`:
  - イメージ: `mcr.microsoft.com/azure-api-management/gateway:2.5.0`
  - 0.25 vCPU / 0.5 GiB / Min=Max=1
  - Ingress: 外部 / HTTP / Target port **8080**
  - 環境変数:
    - `config.service.endpoint` = `apim-aigw-<initials>.configuration.azure-api.net`
    - `config.service.auth` = `GatewayKey <5-3 で生成したトークン>`

### 5-5. 接続テスト
```pwsh
$FQDN = az containerapp show -g rg-aigw-handson-<initials> -n aca-shgw-<initials> --query properties.configuration.ingress.fqdn -o tsv
curl.exe -i -X POST "https://$FQDN/bedrock/model/us.anthropic.claude-3-5-haiku-20241022-v1:0/converse" `
  -H "api-key: <Lab 3 の sub key>" -H "Content-Type: application/json" `
  --data '{"messages":[{"role":"user","content":[{"text":"hello via external SHGW"}]}],"inferenceConfig":{"maxTokens":256}}'
```

- Azure 直 APIM エンドポイントと SHGW 経由で同じ API 定義が動くこと、APIM Portal の **ゲートウェイ → gw-ext-tokyo-<initials>** が「接続中」になることを確認

**注意点**:
- SKU が StandardV2 等だと Gateway バインドで `MethodNotAllowedInPricingTier`（Classic Developer / Premium 必須）
- Container Apps 環境は **Consumption** を選ぶ（Premium は時間課金）
- 環境変数のキー名は **`config.service.endpoint` / `config.service.auth`** のドット区切り（`_` ではない）

---

## Lab 6: OpenTelemetry によるモニタリング / トレーシング（所要 75 分）

**目的**: APIM / 外部 SHGW (Container Apps) / mimic を貫通する分散トレースとトークンメトリクスを可視化。

### 6-1. APIM の OTel / App Insights 連携
- Lab 1 で接続済み。`Application Insights Tracing: Verbose`、サンプリング 100% に設定
- リクエストヘッダ `traceparent` を伝播するポリシーを必要に応じて追加

### 6-2. mimic 側の OTel 計装（参考）
- `azure-monitor-opentelemetry` パッケージ導入を想定。`APPLICATIONINSIGHTS_CONNECTION_STRING` を Container App のシークレットに投入
- W3C `traceparent` を受け取り子 span を生成

### 6-3. Container Apps (SHGW) 側のテレメトリ
- Container Apps 環境作成時に **Log Analytics 統合** が自動有効（Lab 5）
- SHGW コンテナの標準出力は `ContainerAppConsoleLogs_CL` に集約
- Container Apps の OTLP エンドポイント (Preview) は使わず、APIM 側のトレース送信が主軸

### 6-4. 可視化
- App Insights → トランザクション検索で `traceparent` を辿り、APIM → mimic を 1 本のトレースで確認
- メトリクス エクスプローラで `openai-api` / `bedrock-api` 名前空間のトークン量を `api-id` 次元で集計
- **Workbook** を 1 つ作成し、以下のタイルを配置
  - API 別リクエスト数 / 失敗率
  - API 別トークン消費（入出力）
  - p95 レイテンシ（APIM 直 vs 外部 SHGW 経路）

**成果物**: 1 つの Workbook で AI Gateway の利用状況・コスト関連メトリクスを俯瞰できる。

---

## Lab 7: クリーンアップ（所要 10 分）

- [ ] Container Apps `aca-shgw-<initials>` を停止（minReplicas=0）または削除
- [ ] APIM 削除（Developer SKU は時間課金）
- [ ] App Insights / Log Analytics 削除
- [ ] Foundry リソース・Container Apps 環境を削除
- [ ] リソースグループを一括削除
  - `az group delete -n rg-aigw-handson-<initials> --yes --no-wait`

---

## ハンズオン用配布物（このリポジトリで整備するもの）

- `mimic/` — AWS Bedrock Runtime 互換 mimic（FastAPI、Converse / InvokeModel）の Dockerfile / requirements / app コード
- `docs/instructor-setup.md` — 講師向け mimic 構築ガイド
- `docs/labs/lab0.md` … `lab7.md` — Portal 画面手順
- `docs/README.md` — ハンズオン全体ガイド

## 受講者前提

- Azure の基礎操作（リソース作成、Portal ナビゲーション）
- REST / JSON / curl
- コンテナの概念（Docker コマンド操作は不要）

## 想定総所要時間

約 **4.5 時間**（Lab 2 は講師事前デプロイ済みで参加者所要約 5 分。Lab 1 の APIM プロビジョニング待ち時間に Lab 2 を実施して吸収。AWS 排除により Lab 5 が 15 分短縮）
