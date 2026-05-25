# Lab 3 — Microsoft Foundry と APIM AI Gateway の連携

## ゴール

APIM の **AI Gateway** は、既存の API Gateway を生成 AI 向けに拡張した機能群で、Microsoft Foundry にデプロイしたモデル・エージェント・ツール (MCP) を一元的に **保護・スケール・監視・統制** できます。最近のアップデートで、**Foundry 側から直接 AI Gateway を構成できる双方向統合（プレビュー）** が追加されたので、本ラボではその統合ポイントを Foundry portal と APIM の両方の UI から確認します。



## 所要時間

約 40 分

## 事前条件

- [Lab 1](./lab1.md) 完了 — APIM プロビジョニング完了
- [Lab 2](./lab2.md) 完了 — Foundry の gpt-4o-mini をデプロイ済み
- APIM の **システム割り当てマネージド ID** が有効（Lab 1 既定で ON。未設定の場合は `APIM → ID → システム割り当て → オン → 保存`）

---

## 3-1. Microsoft Foundry Models の登録

実 Azure OpenAI モデル（Foundry の gpt-4o-mini）を **APIM 起点** で取り込みます。本ハンズオンは **マルチプロバイダ統合 AI Gateway**（OpenAI + Claude + Gemini + Semantic Cache + Content Safety + Self-hosted Gateway + OTel）が主題のため、APIM Portal のウィザード（3-1B）で `openai-api` を構築します。

| ステップ | 入口 | 本ラボでの扱い |
|---|---|---|
| **3-1A**（参考） | Foundry portal の **操作 → 管理者 → AI Gateway** タブ | **省略**（理由は 3-1A 内で解説。興味のある方は公式ドキュメントを参照） |
| **3-1B**（本流） | APIM Portal の **APIs → + API の追加 → Create from Azure resource → Microsoft Foundry** ウィザード | Foundry のデプロイを `openai-api` として APIM 上に公開。Backend / MI 認証 / トークン制限 / メトリクスをコード無しで自動構成 |

### 3-1A. Foundry portal で AI Gateway を紐付ける（参考・本ハンズオンでは省略）

Foundry portal の **操作 → 管理者 → AI Gateway** タブから、Foundry リソースに APIM (Basic v2) を双方向統合プレビューとして紐付けることができます（公式: [Foundry リソースで AI ゲートウェイを構成する](https://learn.microsoft.com/azure/foundry/configuration/enable-ai-api-management-gateway-portal)）。**本ハンズオンでは以下の理由でこのステップを省略** し、3-1B の APIM 起点ルートのみを実施します。

> :warning: **3-1A を本ハンズオンで省略する理由**
>
> **他社 LLM を統合できない** — Foundry portal の AI Gateway タブは **Foundry リソース内のモデル・Hosted Agent・MCP ツールに UI が閉じている** ため、AWS Bedrock や Google Gemini を Foundry portal から AI Gateway に追加することはできません。本ハンズオンの主目的である **マルチプロバイダ統合 AI Gateway** は、APIM Portal を起点に `openai-api`（Foundry の gpt-4o-mini）と `bedrock-api`（AWS Bedrock の Anthropic Claude）を横並びに構成し、ポリシーを APIM 主導で全 API 横断適用する必要があります。
>
> :information_source: **試したい場合の進め方**: 公式ドキュメント手順に沿って Foundry portal `操作 → 管理者 → AI Gateway` タブで AI Gateway を新規作成（Basic v2 / Free レベル枠内）し、`proj-default-<initials>` を **プロジェクトをゲートウェイに追加** で有効化してください。本ラボの 3-1B 以降には影響しません。

### 3-1B. APIM Portal で Foundry のモデルを API リソース として公開

専用ウィザードを使うことで:

- Foundry リソース内のデプロイメント一覧が自動取得される
- Backend と `set-backend-service` ポリシーが自動生成される
- **APIM のマネージド ID** に `Cognitive Services OpenAI User` ロールが Foundry リソースで自動付与される
- 認証は MI で完結（API キーを APIM 側で保持しない）

#### Portal 手順

1. `APIM (apim-aigw-<initials>) → 左メニュー APIs → + API の追加`
2. **「Create from Azure resource」** カテゴリ内の **Microsoft Foundry** カードを選択

#### Select AI Service タブ

- **サブスクリプション**: Foundry リソースがあるサブスクリプション
- **Microsoft Foundry**: `aif-aigw-<initials>` を選択
  - 行の右側の **deployments** リンクで `gpt-4o-mini` がデプロイされていることを確認
- **次へ**

#### Configure API タブ

| 設定 | 値 |
|---|---|
| 表示名 | `OpenAI API` |
| 名前 | `openai-api` |
| ベース パス (Base path) | `openai` |
| 説明 | `Azure OpenAI gpt-4o-mini via Foundry` |
| クライアント互換性 (Client compatibility) | **Azure OpenAI** |

> :information_source: クライアント互換性 = **Azure OpenAI** を選ぶと、操作 URL は `/openai/deployments/{deployment-id}/chat/completions?api-version=...` 形式で公開されます（Azure OpenAI SDK / `openai` Python SDK の `AzureOpenAI` クラスがそのまま使える）。`Azure AI` を選ぶと Azure AI Model Inference API 形式 (`/models/chat/completions`) になります。本ラボは **Azure OpenAI** を採用。

#### Manage token consumption タブ

UI には 2 つのチェックボックス（`Manage token consumption` / `Track token usage`）があります。ハンズオンでは **`Manage token consumption` のみオン** にし、`Track token usage` は **オフのまま** にします（後者は Application Insights 連携が必要なため、本ラボでは Lab 6 (OpenTelemetry) で別途扱います）。

- **Manage token consumption**: チェック ✔（`llm-token-limit` ポリシーが API スコープに挿入される）
  - **Tokens per minute (TPM)**: `1000`
  - **Token quota** / **Token quota period**: 空欄のまま（TPM のみで制限）
  - **Limit by**: `Subscription`（既定。`counter-key=@(context.Subscription.Id)` に展開される）
  - **Estimate prompt tokens**: チェック ✔（プロンプト送信前に概算してバックエンド送信を抑制）
  - **Add consumed tokens header**: チェック外す（オフ）
  - **Add remaining tokens header**: チェック外す（オフ）
- **Track token usage**: **オフ**（チェック外す）

> :information_source: 実運用では `Tokens per minute` と `Token quota` の **少なくとも一方** を指定してください（両方未指定だと保存時にポリシー検証エラーになります）。

<details>
<summary>各項目の意味（クリックで展開）</summary>

- **Manage token consumption（トークン消費の管理）** ✅ — ポリシー全体の有効化スイッチ。これをオンにすることで、以下のトークン制限が適用されます。
- **Tokens per minute (TPM) / 1 分あたりのトークン数**: `1000` — 1 分間に消費できるトークンの上限。バースト的な過剰利用を防ぐためのレート制限。
- **Token quota（トークンクォータ）** — 指定した期間内に許可される合計トークン数の上限。長期的な総量を制御（未入力）。
- **Token quota period（クォータ期間）** — クォータがリセットされる時間枠（時間／日／週など）。未選択。
- **Limit by（制限の単位）**: `Subscription` — レート制限とクォータを「どのキー単位で適用するか」。`Subscription` は APIM のサブスクリプションキー単位で制限。他に IP やユーザー等も選択可能。
- **Estimate prompt tokens（プロンプトトークンの推定）** ☐ — リクエスト送信前にプロンプトのトークン数を推定し、レート制限の判定に含めるか。オフだとレスポンス後のカウントのみ。
- **Add consumed tokens header（消費トークンヘッダーの追加）** ☐ — レスポンスヘッダーに、そのリクエストで消費されたトークン数を含めるか。
- **Add remaining tokens header（残トークンヘッダーの追加）** ☐ — レスポンスヘッダーに、現在の制限内で残っているトークン数を含めるか。クライアント側で残量を把握したい場合に有用。

</details>

#### Apply semantic caching タブ / AI content safety タブ

- 両方とも **オフ**

#### Review → Create

作成完了で以下が自動構成されます:

- API `openai-api` と、Azure OpenAI のオペレーション群（`chat/completions` / `embeddings` / `images/generations` など）
- Backend `openai-api-ai-endpoint`（URL = `https://<aif-aigw-<initials>>.<region>.cognitiveservices.azure.com/openai`、認証 = `Azure resource (Managed identity)`）
- API スコープ inbound policy に `set-backend-service`（`backend-id="openai-api-ai-endpoint"`）と `llm-token-limit` が挿入される（実ポリシーは 3-2 で確認）
- Foundry リソースに `Cognitive Services OpenAI User` ロールが APIM の MI へ付与される

> :warning: Foundry リソースへのロール付与権限（**所有者** or **ユーザー アクセス管理者**）が必要です。権限不足のときは Wizard が警告するので、講師に依頼するか手動で `APIM の System-assigned MI` に `Cognitive Services OpenAI User` を `aif-aigw-<initials>` リソースで割り当ててください。

## 3-2. 自動生成された成果物の確認

APIs 一覧に **`openai-api`**、Backends → **バックエンド** タブに **`openai-api-ai-endpoint`** が並びます。

| 項目 | 値 |
|---|---|
| API | `openai-api` |
| Backend | `openai-api-ai-endpoint`（Foundry エンドポイント / **Managed identity**） |

`openai-api` の **Design > All operations > Inbound processing** をコードエディター (`</>`) で開くと、以下のポリシーが自動挿入されています:

```xml
<policies>
    <inbound>
        <base />
        <set-backend-service id="apim-generated-policy" backend-id="openai-api-ai-endpoint" />
        <llm-token-limit tokens-per-minute="1000" counter-key="@(context.Subscription.Id)" estimate-prompt-tokens="true" />
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

→ **ウィザードを通すだけで、Backend 接続・MI 認証（Backend 側に紐付け）・トークン制限ポリシーがコード無しで適用されている** ことが確認できます。

> :information_source: Managed Identity による Foundry への認証は **API ポリシーではなく Backend リソース側** で構成されています（Backend の `Credentials` → `Managed identity` で `https://cognitiveservices.azure.com` リソースに対するトークンを APIM が自動取得し `Authorization: Bearer ...` を付与）。そのため API ポリシー内には `authentication-managed-identity` が現れません。
>
> なお `Track token usage` をオフにしたため `llm-emit-token-metric` は含まれていません。

## 3-3. サブスクリプション キーの発行

`APIM → 左メニュー サブスクリプション → + 追加`

- 名前: `sub-aigw-handson`
- 表示名: 任意
- スコープ: **すべての API**（あるいは API 個別に絞っても可）
- **作成** 後、**主キー** を表示してメモ

> :information_source: このキーは Lab 4 以降でもそのまま使います。

## 3-4. 動作確認

### Portal Test タブから（openai-api）

`APIs → openai-api → Test タブ → Creates a model response.`（POST `/responses`）

- **Template parameters**:
  - `api-version`: `2025-03-01-preview`
- **Request body**: 既定のまま（`{"model":"gpt-4o-mini","input":"How are you?","stream":false}`）

**送信**。200 が返り、`output[0].content[0].text` に本物の gpt-4o-mini の応答が含まれていれば成功です。

### PowerShell (curl.exe) から

```pwsh
$APIM = "https://apim-aigw-<initials>.azure-api.net"   # APIM ホスト + openai-api の Base path
$KEY  = "<3-3 で取得した主キー>"
$tmp  = New-TemporaryFile

# openai-api (Foundry の gpt-4o-mini) — Responses API
'{"model":"gpt-4o-mini","input":"hello via APIM","stream":false}' |
  Set-Content -Path $tmp -Encoding utf8 -NoNewline
curl.exe -i -X POST "$APIM/openai/openai/responses?api-version=2025-03-01-preview" `
  -H "api-key: $KEY" `
  -H "Content-Type: application/json" `
  --data-binary "@$tmp"

Remove-Item $tmp -Force
```

## 3-5. （任意）セマンティック キャッシュを有効化

LLM の **完全一致** ではなく **意味（セマンティック）が近いプロンプト** に対して過去のレスポンスを再利用する仕組みです。プロンプトを Embeddings ベクトルに変換し、外部キャッシュ (Redis + RediSearch) 上のベクトル類似度検索でヒットしたら **バックエンド LLM を呼ばずに** キャッシュ済みレスポンスを返します。トークン消費と応答レイテンシの両方を大きく削減でき、FAQ 系・テンプレ問い合わせ系のワークロードに有効です。

ウィザードの **Apply semantic caching** タブで有効化できます。前提:

- **Azure Managed Redis (RediSearch モジュール有効)** インスタンスが必要
- APIM の外部キャッシュとして当該 Redis を登録
- Azure OpenAI の Embeddings デプロイメント（例: `text-embedding-3-small`）が必要

**チューニングと注意点:**

- **類似度しきい値（`score-threshold` = 0.0–1.0）** で精度を調整。**低いほど厳格**（マッチに必要な意味的近さが高くなる）。ワークロードに応じて段階的に上げ下げして最適値を探します。
- 類似度ベースのキャッシュは **現在のリクエストに対して不正確・古いレスポンスを返す可能性** があります。本番投入前にワークロードに対する評価（応答品質・鮮度のテスト）が必要です。

詳細手順: [Enable semantic caching for LLM APIs in Azure API Management](https://learn.microsoft.com/azure/api-management/azure-openai-enable-semantic-caching)

> :warning: 本ハンズオンの主旨（マルチプロバイダ統合 AI Gateway）とは異なるため、ハンズオン本編では任意です。

## 3-6. （任意）AI Content Safety を有効化

ウィザードの **AI content safety** タブで有効化できます。

- **Azure AI Content Safety** リソースが必要
- APIM の Backend として Content Safety を登録（ウィザードが自動で実施）
- カテゴリごとに `allowed-level`（0=Safe〜6=Highest）を指定

詳細手順 / ポリシー仕様: [llm-content-safety policy](https://learn.microsoft.com/azure/api-management/llm-content-safety-policy)

> :warning: こちらも本ハンズオンの主旨とは異なるため、ハンズオン本編では任意です。

## チェックリスト

- [ ] APIM の **システム割り当てマネージド ID** が有効
- [ ] （任意・3-1A 参考実施時のみ）Foundry portal の **管理者 → AI Gateway** タブで Basic v2 APIM を新規作成し、`proj-default-<initials>` をゲートウェイに追加した
- [ ] **Microsoft Foundry** ウィザードで `openai-api` を作成し、Foundry の gpt-4o-mini と接続した
- [ ] APIM の MI に Foundry リソースの `Cognitive Services OpenAI User` ロールが付与されている
- [ ] `openai-api` の Inbound ポリシーに `set-backend-service` と `llm-token-limit` が自動生成されている
- [ ] サブスクリプション キーで `openai-api` が 200 を返す

完了したら [Lab 4 — 他ベンダー LLM（Claude / Gemini）の APIM への登録](./lab4.md) へ。
