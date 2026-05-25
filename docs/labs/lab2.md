# Lab 2 — LLM プロバイダの準備（Microsoft Foundry + mimic）

## ゴール

Lab 3 で APIM の AI Gateway に登録する **LLM プロバイダを 2 系統** 用意する。

| 系統 | 用途 | 実体 |
|---|---|---|
| **メイン LLM** | 本物の OpenAI 推論を体験 | **Microsoft Foundry にデプロイした gpt-4o-mini** |
| **代用 LLM** | Anthropic Claude / Google Gemini API 形式を体験 | **講師配布の mimic エンドポイント** |

> :information_source: なぜ 2 系統か：APIM は「Azure OpenAI Service」「Language Model API」「Passthrough」と複数の登録ウィザードを提供しています。Lab 3 では各ウィザードを 1 つずつ実機で触るために、Azure OpenAI 本物（Foundry）と OpenAI 互換でない LLM（mimic の Claude / Gemini 形式）を併用します。

## 所要時間

約 25 分（Foundry 作成 + モデル deploy 約 20 分 / mimic 疎通 5 分。Lab 1 の APIM プロビジョニング待ちと並行実施可）

## 事前条件

- [Lab 0](./lab0.md) 完了
- 講師から **mimic エンドポイントの Base URL** を受領済み
  - 配布形式例: `https://<INSTRUCTOR_CA_NAME>.<region>.azurecontainerapps.io`
  - 以降本資料では **`<MIMIC_BASE_URL>`** と表記します

---

## 2-1. Microsoft Foundry リソースを作成

`Foundry リソースを作成する` 画面は **基本情報 / ストレージ / ネットワーク / Identity / 暗号化 / タグ / 確認と作成** の 7 タブ構成です。本ハンズオンでは **基本情報** と **Identity** タブだけ触れば OK で、最初のプロジェクトもこの画面でまとめて作られます（別途 ai.azure.com に行く必要なし）。

### Portal 手順

1. Azure Portal の検索バーで **Microsoft Foundry** と入力 → **Microsoft Foundry** を選択 → **作成**
2. **基本情報** タブ:

   **インスタンスの詳細** セクション
   | 項目 | 値 |
   |---|---|
   | サブスクリプション | 任意 |
   | リソース グループ | `rg-aigw-handson-<initials>` |
   | 名前 | `aif-aigw-<initials>`（テナント内で一意） |
   | リージョン | **East US** / **East US 2** / **Sweden Central** など（gpt-4o-mini が利用可能なリージョン） |

   **最初のプロジェクト** セクション
   | 項目 | 値 |
   |---|---|
   | Default project name | `proj-default-<initials>` |

   > :information_source: Portal の既定値は `proj-default` です。参加者間で識別できるようサフィックスを付与してください。ここで指定したプロジェクトが Foundry リソースと同時に作成され、後ほど Foundry portal (`ai.azure.com`) で開けます。

   **コンテンツ レビュー ポリシー** セクションは情報表示のみ。読んだ上で次へ。

3. **ストレージ** タブ: 既定（Microsoft 管理ストレージ）
4. **ネットワーク** タブ: **すべてのネットワークからアクセスできるようにする**（既定）
5. **Identity** タブ:
   - **システム割り当てマネージド ID**: **オフ**（既定、本ハンズオンでは不要）

   > :information_source: Lab 3 では **APIM 側のマネージド ID**（Lab 1 で ON にしたもの）が Foundry リソースを呼び出します。Foundry リソース側の MI は、将来 Foundry から AI Search / Storage 等にアクセスさせるときに使うもので、本ハンズオンではオフのままで問題ありません。
   - ユーザー割り当てマネージド ID: 未指定
6. **暗号化** タブ: 既定（Microsoft 管理キー）
7. **タグ** タブ: 任意
8. **確認と作成** → **作成**

> :information_source: Microsoft Foundry は旧 Azure AI Services / Azure OpenAI Service を統合したリソースです。リソース自体は Azure リソース（`Microsoft.CognitiveServices/accounts`、kind=`AIServices`）、モデルのデプロイは Foundry portal (`ai.azure.com`) から行います。

## 2-2. gpt-4o-mini を Deploy

### Foundry portal に移動

1. デプロイ完了後、`aif-aigw-<initials>` リソースの **概要** 画面を開く
   - 上部 `Foundry ポータルに移動` リンク、または画面中央の **Foundry ポータルに移動** ボタンをクリック
   - ブラウザの新しいタブで [https://ai.azure.com](https://ai.azure.com) が開き、§2-1 で作成した **`aif-aigw-<initials>` / `proj-default-<initials>`** が選択された状態でランディングします
   - 初回サインインを求められた場合は Azure Portal と同じアカウントでサインイン


### 「新しい Foundry」エクスペリエンスを ON にする

Foundry portal トップに「新しい Microsoft Foundry エクスペリエンスをお試しください」バナーと、画面右上に **新しい Foundry** トグルが表示されます。

1. 右上の **新しい Foundry** トグルを **オン** に切り替える
2. 確認ダイアログが出た場合は **続行 / 切り替え** をクリック
3. UI が切り替わり、画面構成が以下のようになることを確認:
   - **画面上部右側のグローバル ナビゲーション**: **ホーム** / **検出** / **ビルド** / **操作** / **ドキュメント**
   - **ホーム画面中央**: `API キー` / `プロジェクト エンドポイント` / `Azure OpenAI エンドポイント` の 3 つのカードが横並び
   - その下に **エージェントの作成** / **プレイグラウンドを探索する** / **モデルの検索** のショートカット カード

> :information_source: 本ラボ以降の Foundry portal 手順はすべて **新しい Foundry** UI を前提に記述します。新 UI では旧 UI にあった左ペイン `My assets > Models + endpoints` や `モデル カタログ` は廃止され、上部ナビゲーションの **検出 / ビルド / 操作** から各機能にアクセスします。

### モデルをデプロイ

1. Foundry portal 画面 **右上のグローバル ナビゲーション → 検出** をクリック → サブメニューから **モデル** を選択
   - もしくはホーム画面中央の **モデルの検索** カードをクリックしても同じモデル一覧に遷移します
2. モデル一覧の検索ボックスに `gpt-4o-mini` → 一覧から **gpt-4o-mini**（モデル プロバイダ = Azure OpenAI）を選択
3. モデル詳細ページが開きます。タブは **詳細 / デプロイ / ベンチマーク / 責任ある AI / ライセンス**、右側パネルに **クイック ファクト / モデル ID** が表示されます
4. 画面右上の紫色の **デプロイ** ボタン（ドロップダウン）をクリック（隣の **微調整** ではなく **デプロイ** の方）
5. ドロップダウンに 2 つの選択肢が出ます:

   | 選択肢 | 説明 | 本ハンズオン |
   |---|---|---|
   | **既定の設定** | グローバル標準および既定のクォータでそのままデプロイ | **こちらを選択** |
   | カスタム設定 | 独自の SKU・クォータ・PTU・スピルオーバー・ガードレールを設定 | 不要 |

   **既定の設定** をクリックすると、追加ダイアログ無しに即座にデプロイが開始されます（Deployment name = `gpt-4o-mini`、Deployment type = Global Standard、TPM = 既定のクォータが自動付与）。
6. ステータスが **Succeeded** になるまで待機（数十秒）

> :information_source: 後から TPM 上限などを調整したい場合は、モデル詳細ページの **デプロイ** タブ、または上部ナビゲーション **操作 → デプロイ** からデプロイ名を選んで変更できます。

### Playground で動作確認

1. デプロイ完了画面で **プレイグラウンドで開く**（Open in playground）→ **Chat playground** が開く
   - もしくは画面上部 **操作 → プレイグラウンド** → **チャット** から開いても OK
2. **モデル** ドロップダウンが `gpt-4o-mini` になっていることを確認
3. 入力欄に `こんにちは` と入れて送信 → 応答が返れば OK

## 2-3. エンドポイント情報を控える

Lab 3 で APIM のウィザードに入力するため、以下を控えてください。

### Foundry portal のホーム画面から取得（最短ルート）

新しい Foundry の **ホーム** 画面（`Microsoft Foundry → ホーム`）には、ようこそメッセージのすぐ下に **3 つのカード** が横並びで配置されています:

| カード | 値の例 | 用途 |
|---|---|---|
| **API キー** | `••••••••••••` + コピー アイコン | Foundry / Azure OpenAI への認証 |
| **プロジェクト エンドポイント** | `https://aif-aigw-<initials>.services.ai.azure.com/api/projects/proj-default-<initials>` | Azure AI Foundry SDK / プロジェクト スコープ |
| **Azure OpenAI エンドポイント** | `https://aif-aigw-<initials>.openai.azure.com/` | Azure OpenAI SDK / `openai` Python SDK (`AzureOpenAI`) / **Lab 3 の APIM ウィザードはこちらの URL を内部で利用** |

各カード右端の **コピー アイコン** で値をクリップボードに取得できます。API キーは伏字表示の右側にある **目アイコン** で一時的に表示できます。

> :information_source: Lab 3 の APIM **Microsoft Foundry** ウィザードでは Foundry リソースを **ドロップダウンで選ぶだけ** で URL もデプロイメントも自動検出されるため、ここで控えるのは **APIM 経由ではなく Foundry に直接叩いて挙動を比較したい場合** の保険です。

## 2-4. 講師配布 mimic エンドポイントの疎通確認

mimic は **AWS Bedrock の Anthropic Claude（Bedrock Runtime API）** の代用として Lab 4 で使用します。実際の Bedrock と同じ URL パスとレスポンス形式（Converse API / InvokeModel API）を返します（後段で AI Gateway がパースするため）。

> :information_source: **なぜ Bedrock 形式の mimic なのか**: 本ハンズオンでは [Microsoft Learn: Amazon Bedrock パススルー言語モデル API](https://learn.microsoft.com/azure/api-management/amazon-bedrock-passthrough-llm-api) の手順を APIM 上で完走させます。APIM 側で **AWS SigV4 署名ポリシー** を適用すると Authorization ヘッダーが生成されますが、mimic 側は署名を**検証しません**（受け取ったヘッダーは無視）。これにより、実 AWS 認証情報なしで「APIM が Bedrock を呼び出す」体験を再現できます。本番では URL とアクセスキーを実 AWS に差し替えるだけで動きます。

### 配布された 2 形式のエンドポイント

| 形式 | ルート（`<MIMIC_BASE_URL>` 配下） | リクエスト形式 | Lab 4 での用途 |
|---|---|---|---|
| Bedrock Converse | `POST /model/{modelId}/converse` | `{ "messages": [{ "role":"user", "content":[{"text":"..."}] }], "inferenceConfig": {...} }` | `bedrock-api` の登録先（推奨） |
| Bedrock InvokeModel | `POST /model/{modelId}/invoke` | `{ "anthropic_version":"bedrock-2023-05-31", "max_tokens":N, "messages":[...] }` | Anthropic ネイティブ body を直接送る場合 |

### 変数セット（PowerShell）

```pwsh
$MIMIC_BASE_URL = "https://ca-mimic-shared.<...>.azurecontainerapps.io"
$MODEL_ID = "us.anthropic.claude-3-5-haiku-20241022-v1:0"
Write-Host "MIMIC_BASE_URL: $MIMIC_BASE_URL"
Write-Host "MODEL_ID: $MODEL_ID"
```

> :warning: **PowerShell 注意**:
> - bash 用の行末 `\` は PowerShell では使えません。1 行にまとめるか PowerShell の継続文字 `` ` `` (バッククォート) を使ってください。
> - `-d '{...}'` のシングルクォート JSON は PowerShell では引用符が消えて壊れます。代わりに **一時ファイル + `--data-binary "@$tmp"`** を使ってください。
> - PowerShell では `curl` が `Invoke-WebRequest` のエイリアスになります。本資料のコマンドは Windows 標準の **`curl.exe`** を明示的に呼び出しています。

### Bedrock Converse 形式（Lab 4 の `bedrock-api` 用 / 推奨）

```pwsh
$tmp = New-TemporaryFile
'{"messages":[{"role":"user","content":[{"text":"hello via Bedrock mimic"}]}],"inferenceConfig":{"maxTokens":256,"temperature":0.5}}' |
  Set-Content -Path $tmp -Encoding utf8 -NoNewline
curl.exe -X POST "$MIMIC_BASE_URL/model/$MODEL_ID/converse" `
  -H "Content-Type: application/json" --data-binary "@$tmp"
Remove-Item $tmp -Force
```

期待レスポンス（抜粋）:
```json
{
  "output": {
    "message": {
      "role": "assistant",
      "content": [{"text": "Echo: hello via Bedrock mimic"}]
    }
  },
  "stopReason": "end_turn",
  "usage": {"inputTokens": 6, "outputTokens": 8, "totalTokens": 14},
  "metrics": {"latencyMs": 200}
}
```

### Bedrock InvokeModel 形式（Anthropic ネイティブ body）

```pwsh
$tmp = New-TemporaryFile
'{"anthropic_version":"bedrock-2023-05-31","max_tokens":256,"messages":[{"role":"user","content":[{"type":"text","text":"hello"}]}]}' |
  Set-Content -Path $tmp -Encoding utf8 -NoNewline
curl.exe -X POST "$MIMIC_BASE_URL/model/$MODEL_ID/invoke" `
  -H "Content-Type: application/json" --data-binary "@$tmp"
Remove-Item $tmp -Force
```

期待レスポンス（抜粋）:
```json
{
  "id": "msg_mock_...",
  "type": "message",
  "role": "assistant",
  "model": "us.anthropic.claude-3-5-haiku-20241022-v1:0",
  "content": [{"type": "text", "text": "Echo: hello"}],
  "stop_reason": "end_turn",
  "usage": {"input_tokens": 5, "output_tokens": 7}
}
```

> :information_source: **mimic 共通仕様**:
> - 入力をエコー or 固定文字列で返す
> - `usage` にダミーのトークン数を返す（Lab 3 / Lab 4 の `llm-emit-token-metric` で集計するため必須）
> - 200 ms 程度の `sleep` を挟んでレイテンシ計測に意味を持たせる
> - **AWS SigV4 署名は検証しない**（APIM が付ける Authorization ヘッダーは受け取って無視）
> - 認証は付与されていない（APIM 側で担う）

## チェックリスト

- [ ] Microsoft Foundry リソース `aif-aigw-<initials>` を作成（マネージド ID 有効）
- [ ] プロジェクト `proj-default-<initials>` を作成
- [ ] gpt-4o-mini を Deploy（Deployment type: Global Standard）
- [ ] Foundry の Chat playground で `gpt-4o-mini` の応答を確認
- [ ] Foundry のエンドポイント / Key を控えた（または Foundry リソース名 `aif-aigw-<initials>` をメモ）
- [ ] 講師から `<MIMIC_BASE_URL>` を受領した
- [ ] Bedrock Converse 形式 mimic で 200 OK と `output.message` 形式の JSON を確認
- [ ] Bedrock InvokeModel 形式 mimic で 200 OK と Anthropic ネイティブ JSON を確認

完了したら（Lab 1 の APIM プロビジョニングも完了している前提で） [Lab 3 — APIM AI Gateway として LLM を登録・管理](./lab3.md) へ。
