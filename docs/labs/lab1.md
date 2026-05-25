# Lab 1 — APIM 基盤と Application Insights 構築

## ゴール

AI Gateway のハブとなる **Azure API Management（Developer SKU）** と、OTel / トレースの受け皿となる **Application Insights**（Workspace ベース）を作成し、両者を接続する。

## 所要時間

約 45 分（うち APIM プロビジョニングの待ち時間が 30–45 分。待機中に [Lab 2](./lab2.md) の Foundry リソース作成 + gpt-4o-mini デプロイ + mimic 疎通確認（約 25 分）を並行実施してください。実際の画面操作は約 15 分）

## 事前条件

- [Lab 0](./lab0.md) 完了
- リソースグループ `rg-aigw-handson-<initials>` がある
- 命名規約の `<initials>` を決定済み

---

## 1-1. Log Analytics ワークスペース作成

1. Portal 検索バーで **「Log Analytics ワークスペース」** → **作成**
2. 設定:
   - リソース グループ: `rg-aigw-handson-<initials>`
   - 名前: `log-aigw-<initials>`
   - リージョン: `Japan East`
3. **確認と作成** → **作成**

## 1-2. Application Insights 作成

1. Portal 検索バーで **「Application Insights」** → **作成**
2. 設定:
   - リソース グループ: `rg-aigw-handson-<initials>`
   - 名前: `appi-aigw-<initials>`
   - リージョン: `Japan East`
   - リソースモード: **Workspace ベース**
   - ログ分析ワークスペース: 1-1 で作成した `log-aigw-<initials>`
3. **確認と作成** → **作成**
4. 作成完了後、**プロパティ** から **接続文字列** をコピーし、安全な場所にメモ
   - 形式: `InstrumentationKey=xxx;IngestionEndpoint=https://...`

## 1-3. APIM 作成（Developer SKU）

> :warning: **SKU の選択に注意**
> Lab 4 で Self-hosted Gateway を使うため、**Classic Developer** または Premium が必須です。
> Consumption / StandardV2 / Basic v2 を選ぶと Lab 4 で `MethodNotAllowedInPricingTier` エラーになります。

1. Portal 検索バーで **「API Management サービス」** → **作成**
2. **基本** タブ:
   - リソース グループ: `rg-aigw-handson-<initials>`
   - リージョン: `Japan East`
   - リソース名: `apim-aigw-<initials>`
   - 組織名: 任意（例: `aigw-handson`）
   - 管理者メール: 自分のアドレス
   - 価格レベル: **Developer (no SLA)**
   - 容量: `1`
3. **監視とセキュリティ保護** タブ:
   - **Log Analytics**: **チェックを入れる**
     - サブスクリプション: 既定
     - ログ分析ワークスペース: 1-1 で作成した `log-aigw-<initials> (japaneast)`
   - **Microsoft Defender for Cloud の Defender for API**: **チェックを入れない**（コスト発生のため本ハンズオンでは不要）
   - **Application Insights**: **チェックを入れる**
     - インスタンスの選択: 1-2 で作成した `appi-aigw-<initials>`
4. **ネットワーク** タブ:
   - 接続の種類: **なし**（パブリック IP アドレスで公開。Lab 4 の外部 SHGW から接続するため、仮想ネットワーク/プライベートエンドポイントは選ばない）
5. **マネージド ID** タブ:
   - **システム割り当てマネージド ID**: **オン**（Lab 3 で Microsoft Foundry の gpt-4o-mini に MI 認証で接続するため必須）
   - ユーザー割り当てマネージド ID: 未指定
6. **タグ** タブ: 任意
7. **確認とインストール** → **作成**

> :hourglass: プロビジョニングは 30–45 分かかります。**この間に [Lab 2](./lab2.md) の Foundry リソース作成 + gpt-4o-mini デプロイ + mimic 疎通確認（約 25 分）を済ませておいてください**。

## 1-4. APIM の Application Insights ロガー設定確認

APIM 作成後（プロビジョニング完了後）:

1. APIM リソース → 左メニュー **監視 > Application Insights**
2. 既定で `appi-aigw-<initials>` が登録されていることを確認
3. 既定ロガー（**applicationinsights**）が表示される場合:
   - サンプリング: **100 %**
   - 詳細レベル: **Verbose**
   - 「すべての API でこのロガーを有効にする」: **オン**

## 1-5. APIM の管理者キー / Gateway URL を控える

APIM リソース → 概要 で以下をメモ:

| 項目 | 例 | 用途 |
|---|---|---|
| ゲートウェイ URL | `https://apim-aigw-<initials>.azure-api.net` | Lab 3 で curl 実行先 |
| 管理 URL | `https://apim-aigw-<initials>.management.azure-api.net` | 管理 API |
| 開発者ポータル URL | `https://apim-aigw-<initials>.developer.azure-api.net` | サブスクリプションキー発行 |
| 構成 URL | `apim-aigw-<initials>.configuration.azure-api.net` | Lab 4 SHGW で使用 |

## チェックリスト

- [ ] Log Analytics ワークスペース作成済み
- [ ] Application Insights（Workspace ベース）作成済み、接続文字列を控えた
- [ ] APIM（Developer SKU）作成完了、ゲートウェイ URL を控えた
- [ ] APIM ↔ Application Insights が紐付け済み

完了したら [Lab 2 — Mimic エンドポイントの確認](./lab2.md) へ。
