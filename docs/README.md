# AI Gateway マルチクラウド ハンズオン

Azure API Management（APIM）を **AI Gateway** として利用し、以下 3 テーマを Azure Portal 中心に体験する 7 Lab 構成のハンズオンです。

1. **他ベンダー LLM（AWS Bedrock の Anthropic Claude）への接続**
   実 AWS を使わず、Azure Container Apps 上に AWS Bedrock Runtime 互換の mock を配置
2. **外部環境（AWS 相当）での APIM 展開**
   APIM Self-hosted Gateway（SHGW）を **Azure Container Apps**（別リソースグループ）にデプロイし、「APIM とは独立したホスティング上で動くデータプレーン」（AWS Fargate / EKS / EC2 と同じコンテナイメージ）を体験的に再現
3. **OpenTelemetry によるモニタリング / トレーシング**
   APIM・Functions・SHGW を貫通する分散トレースと Workbook 可視化

> :information_source: 本ハンズオンは **AWS アカウントを使用しません**。「AWS 上で APIM SHGW を動かすパターン」は Azure Container Apps で演出します。コンテナイメージ・設定方法・トークン認可は AWS で動かす場合と完全に同一のため、ホスティング先を差し替えるだけで本番適用できます。

## 想定読者

- Azure の基礎操作ができる
- REST / JSON / curl の基礎
- コンテナの概念（Docker コマンド操作は不要）

## 所要時間

合計 **約 6 時間**（mock は講師事前準備済み。Lab 1 の APIM プロビジョニング待ち時間に Lab 2 の Foundry リソース作成 + gpt-4o-mini デプロイ + mock 疎通確認を並行で実施して吸収）

## コスト方針

すべて **最安構成** を選定。Lab 7 のクリーンアップを必ず実施してください。

| リソース | SKU | 理由 |
|---|---|---|
| APIM | Developer (Classic) | SHGW を使うため必須。Developer が最安。 |
| Container Apps (mock) | **参加者不要** | 講師が事前デプロイした共有エンドポイントを利用。 |
| Application Insights | Workspace 連動 (PAYG) | 1GB/月の無料枠で収まる想定。 |
| Container Apps (SHGW) | Consumption / 0.25 vCPU / 0.5 GiB | 0 スケール可能なサーバレスコンテナ。使わない間は 0 円。 |
| Azure OpenAI | **不使用** | mock で代替し課金回避。 |

## Lab 一覧

| Lab | 内容 | 所要 |
|---|---|---|
| [Lab 0](./labs/lab0.md) | 環境準備（CLI・リソースグループ 2 つ・命名規約） | 15 分 |
| [Lab 1](./labs/lab1.md) | APIM (Developer) + Application Insights 構築 | 45 分 |
| [Lab 2](./labs/lab2.md) | Microsoft Foundry リソース作成 + gpt-4o-mini デプロイ + 講師配布 mock の疎通確認 | 30 分 |
| [Lab 3](./labs/lab3.md) | Microsoft Foundry を APIM AI Gateway として登録（openai-api / Token Limit / Metric） | 50 分 |
| [Lab 4](./labs/lab4.md) | 他ベンダー LLM（AWS Bedrock の Anthropic Claude）の APIM への登録 | 60 分 |
| [Lab 5](./labs/lab5.md) | Azure Container Apps 上で APIM Self-hosted Gateway を展開（AWS 環境を模擬） | 75 分 |
| [Lab 6](./labs/lab6.md) | OpenTelemetry で分散トレース + Workbook 可視化 | 75 分 |
| [Lab 7](./labs/lab7.md) | クリーンアップ | 10 分 |

## アーキテクチャ最終形

```
[利用者 / curl / Notebook]
        │
        ▼
┌──────────────────────────────┐
│  Azure APIM (Developer SKU)  │ ← AI Gateway ポリシー
│   - Token Limit / Metric     │   (Control Plane)
│   - Content Safety           │
│   - OTel / App Insights      │
└──────────────────────────────┘
        │                          │
        │ (Azure 直結)             │ (外部 SHGW = AWS 相当 経由)
        ▼                          ▼
┌──────────────────────────┐   ┌──────────────────────────────┐
│ mock (講師事前デプロイ)    │   │ Azure Container Apps         │
│  rg: rg-apim-instructor   │   │  rg: rg-aigw-handson-<init>  │
│ Container App            │   │  image: apim-gateway:2.5.0   │
│  AWS Bedrock Runtime     │   │  = APIM Self-hosted Gateway │
│  互換 mock (Anthropic)   │   │  （AWS Fargate と同じ image）│
└──────────────────────────┘   └──────────────────────────────┘
        │                          │
        ▼                          ▼
   Application Insights
```

## 命名規約（推奨）

`<イニシャル>` を 2–4 文字の英小文字で置換してください。

| 種別 | 例 |
|---|---|
| リソースグループ | `rg-aigw-handson-<initials>` |
| APIM | `apim-aigw-handson-<initials>` |
| App Insights | `appi-aigw-<initials>` |
| Log Analytics | `log-aigw-<initials>` |
| Container Apps 環境 | `cae-aigw-ext-<initials>` |
| Container App (SHGW) | `aca-shgw-<initials>` |
| SHGW リソース名 (APIM 側) | `gw-ext-tokyo-<initials>` |
| mock Base URL（講師配布） | `<mock_BASE_URL>` |

## 進め方

各 Lab の冒頭にある「ゴール」と「事前条件」を確認してから着手してください。Portal 画面のスクリーンショットを差し替えたい場合は `docs/labs/images/` 配下に追加し、Markdown から参照してください。
