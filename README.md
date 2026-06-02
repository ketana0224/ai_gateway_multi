# ai_gateway_multi

Azure API Management (APIM) を **AI Gateway** として使い、**マルチベンダー LLM 接続 / マルチクラウド展開 / OpenTelemetry 可視化** を一気通貫で体験するハンズオンキット（Lab 0 〜 Lab 7 / 全 8 Lab）。**Azure Portal 中心**、**AWS アカウント不要**（AWS 環境も Azure 上で mock）、**無料試用版サブスクリプションでも実施可能**。

## このハンズオンで扱う 3 テーマ

| # | テーマ | 担当 Lab | やること |
|---|---|---|---|
| 1 | **マルチベンダー LLM の一元集約** | Lab 2 / Lab 3 / Lab 4 | Microsoft Foundry の OpenAI (`gpt-4o-mini`) と、AWS Bedrock の Anthropic Claude（mock 経由）を **同じ APIM AI Gateway に登録**。サブスクリプション キー / トークン制限 / メトリクスを横断統制 |
| 2 | **マルチクラウドな APIM データプレーン** | Lab 5 | APIM Self-hosted Gateway (SHGW) を **Azure Container Apps（別 RG / 別リージョン）** に展開し、「APIM 本体は Azure、Gateway 実体は AWS / オンプレ」というハイブリッド構成を再現（コンテナイメージは AWS でも完全に同じ） |
| 3 | **OpenTelemetry によるモニタリング / トレーシング** | Lab 6 + [docs/Otel_Info.md](./docs/Otel_Info.md) | APIM ↔ Foundry ↔ SHGW を貫通する **W3C traceparent** ベースの分散トレースを Application Insights で可視化。ベンダー別トークン消費・レイテンシをメトリクス化 |

## 全体アーキテクチャ（最終形）

```
                          [ 利用者 / curl / Notebook ]
                                       │
                                       ▼
        ┌──────────────────────────────────────────────────────┐
        │   Azure APIM (Classic Developer) — japaneast         │
        │   = AI Gateway （Control Plane 兼 Data Plane）       │
        │     • subscription-key 認証                          │
        │     • llm-token-limit / llm-emit-token-metric        │
        │     • W3C Correlation / Application Insights logger  │
        └────────┬────────────────────────┬────────────────────┘
                 │  openai-api            │  bedrock-api
                 ▼                        ▼
   ┌──────────────────────┐   ┌──────────────────────────────┐
   │  Microsoft Foundry   │   │  Bedrock mock               │
   │  gpt-4o-mini         │   │  (= AWS Bedrock Runtime 互換) │
   │  + App Insights 接続 │   │   講師事前デプロイ            │
   └──────────────────────┘   └──────────────────────────────┘

                  ▲                  ▲
                  │ 同じ trace-id    │
                  │                  │
        ┌──────────────────────────────────────────────────────┐
        │   APIM Self-hosted Gateway (Data Plane only)         │
        │   Azure Container Apps `cae-apim-instructor` — eastus │
        │   = 「AWS 相当の外部環境」（AWS Fargate と同イメージ）│
        └──────────────────────────────────────────────────────┘

   ── 全レイヤーが Application Insights `appi-aigw-<initials>` に集約 ──
```

## ハンズオン目次

> :warning: **この手順は受講者用です。** 先に [docs/instructor-setup.md](./docs/instructor-setup.md) — 講師側の事前準備（mock エンドポイントと共有 Container Apps 環境のデプロイ）が完了している必要があります。

事前準備 → 構築 → 連携 → マルチクラウド → 可視化 → 後片付け の順で進めます。

| Lab | タイトル | 概要 | 所要時間 |
|---|---|---|---|
| [Lab 0](./docs/labs/lab0.md) | 環境準備 | Azure CLI / Portal アクセス / 命名規約 (`<initials>`) / リソースグループ整備 | 約 10 分 |
| [Lab 1](./docs/labs/lab1.md) | APIM 基盤と Application Insights 構築 | Log Analytics → App Insights → APIM (Classic Developer) → ロガー紐付け | 約 45 分（うち APIM プロビジョニング待ち 30–45 分は Lab 2 と並行） |
| [Lab 2](./docs/labs/lab2.md) | LLM プロバイダの準備（Foundry + mock） | Microsoft Foundry リソース作成 → `gpt-4o-mini` デプロイ → 講師配布 mock エンドポイント疎通 | 約 25 分（Lab 1 と並行可） |
| [Lab 3](./docs/labs/lab3.md) | Microsoft Foundry と APIM AI Gateway の連携 | Foundry portal ↔ APIM portal 双方向統合（プレビュー）で `openai-api` を登録、AI Gateway ポリシーを適用 | 約 40 分 |
| [Lab 4](./docs/labs/lab4.md) | 他ベンダー LLM（AWS Bedrock の Claude）の登録 | APIM の **Create an AI API → Language Model API** ウィザードで `bedrock-api` を Passthrough 登録、SigV4 ポリシー追加（mock は署名検証しない） | 約 45 分 |
| [Lab 5](./docs/labs/lab5.md) | 外部環境（AWS 相当）で APIM Self-hosted Gateway を展開 | APIM で Gateway リソース定義 → token 生成 → Container Apps (`ca-shgw-<initials>` / eastus) にデプロイ → 同じ API を AWS 相当データプレーン経由で叩く | 約 55 分 |
| [Lab 6](./docs/labs/lab6.md) | OpenTelemetry によるモニタリング / トレーシング | APIM の W3C 設定確認 → Foundry を App Insights に接続 → 外部 SHGW のテレメトリと通信断時の挙動を整理 | 約 45 分 |
| [Lab 7](./docs/labs/lab7.md) | クリーンアップ | Container App 停止／Gateway リソース削除／RG 一括削除で課金停止 | 約 5 分 |

ハンズオン所要時間 **約 4 時間**（Lab 1 の APIM プロビジョニング待ちと Lab 2 を並行実施する前提）。実作業の単純合計は約 4 時間 30 分。

## 補足資料

- [docs/README.md](./docs/README.md) — ハンズオン全体の詳細概要・コスト方針・想定読者
- [docs/Otel_Info.md](./docs/Otel_Info.md) — E2E 分散トレース成立条件のリファレンス（Lab 6 を読み解くための前提理論。`traceparent` 受け渡し原則 / Azure・M365・AWS・GCP・SaaS 別の自動計装可否マトリクス）
- [docs/instructor-setup.md](./docs/instructor-setup.md) — 講師側の事前準備（mock エンドポイントと共有 Container Apps 環境のデプロイ）
- [spec.md](./spec.md) — ハンズオンキット仕様

## 想定読者

- Azure の基礎操作ができる
- REST / JSON / curl の基礎
- コンテナの概念（Docker コマンド操作は不要）

## 前提となる Azure SKU / 構成

| リソース | SKU / 種類 | 注意点 |
|---|---|---|
| APIM | **Classic Developer** | Self-hosted Gateway を使うため必須。`StandardV2` は SHGW 非対応（`MethodNotAllowedInPricingTier`） |
| Microsoft Foundry | Standard | `gpt-4o-mini` を Global Standard でデプロイ |
| Container Apps env | 講師配布の共有 env `cae-apim-instructor` (eastus) に相乗り | 受講者は Container App を 1 つ追加するだけ（env 新規作成不要） |
| Application Insights | Workspace-based | Log Analytics と一体で課金 |

## 重要な注意事項

> :warning: **Lab 7 のクリーンアップを必ず実施してください。** APIM Classic Developer と Container Apps (`minReplicas=1`) は削除しない限り課金が継続します。

> :information_source: 本ハンズオンは **AWS アカウントを使用しません**。「AWS 上で APIM SHGW を動かすパターン」は Azure Container Apps で再現します。コンテナイメージ・設定方法・トークン認可は AWS で動かす場合と完全に同一のため、本番でホスティング先を AWS Fargate / EKS / EC2 に差し替えるだけで動きます。

## ライセンス

このリポジトリは [MIT License](./LICENSE) で公開されています。

---

開始は [Lab 0 — 環境準備](./docs/labs/lab0.md) から。
