# Lab 0 — 環境準備

## ゴール

ハンズオン全体で使うアカウント・CLI・リソースグループ・命名規約を揃え、Lab 1 以降をスムーズに進められる状態にする。

## 所要時間

約 10 分

## 事前条件

- 講師から配布された Azure アカウント（UPN / 初期パスワード）
- 作業端末: Windows / macOS / Linux いずれか

> :information_source: このハンズオンでは、**AWS アカウントは不要**です。「AWS 上の APIM 展開パターン」は 疑似APIを利用します。お持ちの場合は、AWS アカウントのご利用もできます。

> :information_source: **無料試用版（Free Trial）サブスクリプションでも実施可能** です。疑似API（mock エンドポイント）は講師が事前デプロイします。

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

## 0-3. リソースグループの確認（Azure Portal）

リソースグループは講師が事前作成済みです。

1. Azure Portal（[https://portal.azure.com](https://portal.azure.com)）に配布されたアカウントでサインイン
   - 初回サインイン時にパスワード変更と MFA 設定を求められる場合があります
2. 上部検索バーで **「リソース グループ」** を検索
3. 以下の 2 つが表示されることを確認

| リソースグループ | 用途 | 自分の権限 |
|---|---|---|
| `rg-aigw-handson-<id>` | 自分のリソース（APIM 等）| Contributor |
| `rg-apim-instructor` | 講師の mock API | Reader |

## 0-4. 命名規約の決定

`<id>` には講師から配布された参加者 ID（例: `user01`）を使います。以後の Lab で使うので確認しておきます。

| 種別 | 例 | あなたの値 |
|---|---|---|
| APIM | `apim-aigw-<id>` | `apim-aigw-______` |
| App Insights | `appi-aigw-<id>` | `appi-aigw-______` |
| Log Analytics | `log-aigw-<id>` | `log-aigw-______` |
| Container Apps 環境 | `cae-aigw-ext-<id>` | `cae-aigw-ext-______` |
| Container App (SHGW) | `aca-shgw-<id>` | `aca-shgw-______` |
| SHGW リソース名 (APIM 側) | `gw-ext-tokyo-<id>` | `gw-ext-tokyo-______` |

## チェックリスト

- [ ] 配布アカウントで Azure Portal にサインイン済み
- [ ] リソースグループ `rg-aigw-handson-<id>` が表示されることを確認
- [ ] 講師 RG `rg-apim-instructor` が Reader で見えることを確認
- [ ] 参加者 ID（`<id>`）を確認し、メモした

完了したら [Lab 1 — APIM 基盤と Application Insights 構築](./lab1.md) へ進みます。
