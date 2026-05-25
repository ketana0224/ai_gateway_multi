# Lab 0 — 環境準備

## ゴール

ハンズオン全体で使うアカウント・CLI・リソースグループ・命名規約を揃え、Lab 1 以降をスムーズに進められる状態にする。

## 所要時間

約 10 分

## 事前条件

- Azure サブスクリプション（共同作成者以上）
- 作業端末: Windows / macOS / Linux いずれか

> :information_source: このハンズオンでは、**AWS アカウントは不要**です。「AWS 上の APIM 展開パターン」は 疑似APIを利用します。お持ちの場合は、AWS アカウントのご利用もできます。

> :information_source: **無料試用版（Free Trial）サブスクリプションでも実施可能** です。疑似API（mimic エンドポイント）は講師が事前デプロイします。

---

## 0-1. 必須ツールのインストール確認

ターミナルで以下を実行し、すべてバージョンが表示されることを確認します。

| ツール | 確認コマンド | 推奨バージョン |
|---|---|---|
| Azure CLI | `az --version` | 2.60 以上 |
| curl | `curl --version` | 任意 |
| VS Code | — | 任意 |

## 0-2. リージョン

| 用途 | 推奨リージョン | 備考 |
|---|---|---|
| 受講者リソース（APIM・App Insights・SHGW 等） | `japaneast` | APIM Developer / Container Apps 利用可 |

## 0-3. リソースグループを作成（Azure Portal）

1. Azure Portal にサインイン
2. 上部検索バーで **「リソース グループ」** を検索 → **作成**
3. 設定値:
   - 名前: `rg-aigw-handson-<initials>`
   - リージョン: `(Asia Pacific) Japan East`
4. **確認と作成** → **作成**

## 0-4. 命名規約の決定

`<initials>` には 2–4 文字の英小文字（例: 自分のイニシャル）を入れます。以後の Lab で使うので決めておきます。

| 種別 | 例 | あなたの値 |
|---|---|---|
| APIM | `apim-aigw-<initials>` | `apim-aigw-______` |
| App Insights | `appi-aigw-<initials>` | `appi-aigw-______` |
| Log Analytics | `log-aigw-<initials>` | `log-aigw-______` |
| Container Apps 環境 | `cae-aigw-ext-<initials>` | `cae-aigw-ext-______` |
| Container App (SHGW) | `aca-shgw-<initials>` | `aca-shgw-______` |
| SHGW リソース名 (APIM 側) | `gw-ext-tokyo-<initials>` | `gw-ext-tokyo-______` |

## チェックリスト

- [ ] リソースグループ `rg-aigw-handson-<initials>` が作成済み
- [ ] 命名規約（`<initials>`）を決定し、メモした

完了したら [Lab 1 — APIM 基盤と Application Insights 構築](./lab1.md) へ進みます。
