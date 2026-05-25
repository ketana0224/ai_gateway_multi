# Lab 4 — 他ベンダー LLM（AWS Bedrock の Anthropic Claude）の APIM への登録

## ゴール

Lab 3 で構築した **Foundry の gpt-4o-mini (`openai-api`)** に加え、講師配布の **mimic エンドポイント** を **AWS Bedrock Runtime 互換 API** として APIM に取り込み、Foundry 上の OpenAI と AWS Bedrock 上の Anthropic Claude を **一つの AI Gateway に一元登録** してガバナンス（サブスクリプション キー、トークン上限、メトリック収集）を横断適用する構成を完成させる。

手順は [Microsoft Learn: Amazon Bedrock パススルー言語モデル API を Azure API Management にインポートする](https://learn.microsoft.com/azure/api-management/amazon-bedrock-passthrough-llm-api) をそのまま踏襲します。**本ラボでは実 AWS Bedrock の代わりに `<MIMIC_BASE_URL>` を Backend URL に使い**、APIM が付与する AWS SigV4 署名は mimic が**検証しません**（受け取って無視）。本番では Backend URL と Named Value のキーを実 AWS に差し替えるだけで動きます。

| API | 登録ウィザード | URL ソース | Wizard の主要設定 |
|---|---|---|---|
| `bedrock-api` | **Create an AI API → Language Model API** | `<MIMIC_BASE_URL>` | 種類: Passthrough |

ウィザードの主要タブ:

| タブ | ポリシー | 本ラボでの扱い |
|---|---|---|
| Configure API | `set-backend-service` + Backend 自動生成 | 必須 |
| Manage token consumption | `llm-token-limit` / `llm-emit-token-metric` | オン |
| Apply semantic caching | `azure-openai-semantic-cache-*` | オフ |
| AI content safety | `llm-content-safety` | オフ |

ウィザード完了後、追加で **AWS SigV4 署名 Inbound ポリシー** を貼り付けます（MS Learn の手順）。

## 所要時間

約 45 分

## 事前条件

- [Lab 3](./lab3.md) 完了 — `openai-api`（Foundry の gpt-4o-mini）が APIM に登録済み
- Lab 2 で確認した `<MIMIC_BASE_URL>` を環境変数 / メモに保持

---

## 4-1. `bedrock-api` — mimic を Language Model API（Passthrough）で登録

AWS Bedrock は **OpenAI 互換ではない独自スキーマ**（Converse / InvokeModel）なので、**Passthrough** で登録します。

### Portal 手順

1. `APIM (apim-aigw-<initials>) → 左メニュー APIs → + API の追加`
2. **「Create an AI API」** セクション内の **Language Model API** カード（New バッジ）を選択


**Configure API** タブ:

| 設定 | 値 |
|---|---|
| 表示名 | `Bedrock API` |
| 名前 | `bedrock-api` |
| URL | `<MIMIC_BASE_URL>` |
| パス | `bedrock` |
| 種類 | **Create a passthrough API** |
| アクセス キー（ヘッダー名 / 値） | 空欄のまま（SigV4 は次節のポリシーで付与） |

**Manage token consumption** タブ: オン（`tokens-per-minute=1000`）。他 2 タブはオフ。

> Passthrough を選ぶと全 HTTP verb のワイルドカード オペレーションが作られ、`POST /model/{modelId}/converse` などを APIM 経由でそのまま透過送信できます。

> :information_source: **実プロバイダで登録する場合の URL 例**:
>
> | プロバイダ | URL | 種類 |
> |---|---|---|
> | OpenAI | `https://api.openai.com/v1` | Create OpenAI API |
> | Google Gemini (OpenAI 互換) | `https://generativelanguage.googleapis.com/v1beta/openai` | Create OpenAI API |
> | Anthropic（API 直） | `https://api.anthropic.com/v1` | Passthrough |
> | **Amazon Bedrock** | `https://bedrock-runtime.us-east-1.amazonaws.com` | **Passthrough**（次節の SigV4 ポリシーを併用）|
> | Hugging Face TGI | （自前ホスト URL） | Create OpenAI API |

## 4-1A. Backend の命名をきれいにする（重要）

ウィザード完了直後、`Backends → バックエンド` を開くと **`bedrock-api-openai-endpoint`** という Backend が自動生成されています（ランタイム URL は手順 4-1 で入力した `<MIMIC_BASE_URL>`）。

> :information_source: **これは Language Model API ウィザードが現在のプレビュー段階で Passthrough/OpenAI を問わず同じ命名ロジック（`<api-name>-openai-endpoint`）を使っている一時的な挙動で、将来のリリースで Bedrock を含む Passthrough API 向けの命名（例: `<api-name>-endpoint`）に修正される予定です**。機能上は今のままでも動きますが、Bedrock 用なのに `openai` が含まれて紛らわしいので、本ラボでは **`bedrock-api-backend` にリネーム**（= 新規作成 + 旧削除）してから次節へ進みます。今後ウィザード側の命名が修正された後にこのラボを実施する場合は、自動生成された Backend 名をそのまま使い、本節の手動作成 + 旧削除は読み替えて省略しても構いません。

### 手順

1. `APIM → Backends → + 新しいバックエンドの作成`

   | 設定 | 値 |
   |---|---|
   | 名前 | `bedrock-api-backend` |
   | 種類 | **カスタム URL** |
   | ランタイム URL | `<MIMIC_BASE_URL>` |

   → 作成。これで Backend 一覧に `bedrock-api-backend` と `bedrock-api-openai-endpoint` が並びます。

2. 古い `bedrock-api-openai-endpoint` を選択 → `削除`（次節 §4-2(2) で貼り付ける Inbound ポリシーは `bedrock-api-backend` を参照する形になっているので、この時点で削除して構いません）。

> :information_source: APIM の Backend は ID（= 名前）を後から変更できないため、「リネーム」は実体としては **新規作成 + 旧削除** で行います。

## 4-2. AWS SigV4 署名 Inbound ポリシーを適用

[MS Learn の手順](https://learn.microsoft.com/azure/api-management/amazon-bedrock-passthrough-llm-api) どおり、`bedrock-api` の Inbound にポリシーを追加します。APIM が `Authorization: AWS4-HMAC-SHA256 ...` / `X-Amz-Date` / `X-Amz-Content-Sha256` / `Host` ヘッダーを自動生成します。

### (1) Named Values にダミーの AWS 認証情報を作成

`APIM → 名前付きの値 → ＋ 追加`:

| 設定 | 値 |
|---|---|
| 名前 | `accesskey` |
| 表示名 | `accesskey` |
| 種類 | **シークレット** |
| 値 | `AKIA_DUMMY_HANDSON_KEY` （mimic は検証しないので任意の値で OK）|

同じ手順で `secretkey` を作成（値: `secret_dummy_handson_xxxxxxxxxxxxxxxxxxxxxx`）。

> :information_source: 本番で実 AWS Bedrock に向ける場合は、AWS IAM ユーザーのアクセスキー / シークレットキーをここに格納します。本ラボでは mimic 側で署名を検証しないため**ダミー値で構いません**。

### (2) Inbound ポリシーを貼り付け

`APIs → bedrock-api → All operations → ポリシー (`</>` アイコン) → Inbound`:

MS Learn の「[Configure policies to authenticate requests to the Amazon Bedrock API](https://learn.microsoft.com/azure/api-management/amazon-bedrock-passthrough-llm-api#configure-policies-to-authenticate-requests-to-the-amazon-bedrock-api)」セクションの XML を**ベース**に、次節の **改良版 XML**（下記 `<details>` 内）を貼り付けます。`<policies>` 全体を改良版で置き換えてください。

<details>
<summary>クリックして開く — 改良版が MS Learn 原文と異なる 3 点（差分の理由）</summary>

- **改良版は MS Learn 原文に対して 3 点差分**があります（理由は下記）:
  1. `<base />` の直後に **`<set-backend-service backend-id="bedrock-api-backend" />`** を追加（転送先を §4-1A で作った Backend に固定）。MS Learn 原文には無いが、ウィザード生成時に埋め込まれていた等価の転送設定が `<policies>` 全置換で消えるため明示的に書き直す。
  2. **body の読み取りを `<set-variable name="requestBody">` で 1 回だけ実行**し、`X-Amz-Content-Sha256` と `Authorization` の両 set-header からは `(string)context.Variables["requestBody"]` で参照（MS Learn 原文は両 set-header の式内で `context.Request.Body.As<string>(preserveContent: true)` を 2 回呼ぶ書き方だが、APIM のビルドによっては 2 回目の呼び出しが `null` を返して `set-header[3]` の C# 式が NullReferenceException で落ちる事象を実機で再現確認したため、`<set-variable>` 経由に統一して堅牢化）。
  3. **`<set-header name="Host">` を削除し、署名計算側では `context.Request.OriginalUrl` を使用**。MS Learn 原文は `<set-header name="Host"><value>@(context.Request.Url.Host)</value></set-header>` を付けているが、現行 APIM ビルドでは `<set-backend-service>` を先に呼んだあとの inbound コンテキストで `context.Request.Url.Host` が空文字列を返し、`set-header[4]` にて `Header can't have empty value.` で 500 になる事象を実機で再現確認した。そもそも `<set-backend-service>` を使う場合 backend へ転送される Host ヘッダーは APIM が自動で付与するため、`<set-header name="Host">` は不要。さらに、SigV4 署名計算内で `host` を取り出すための URL も `context.Request.Url`（途中で書き換えが起きる可能性がある）ではなく **`context.Request.OriginalUrl`**（incoming の不変コピー）を使うように変更。
- `region` / `service` / `accesskey` / `secretkey` は **`<set-header name="Authorization">` の C# 式の内側でローカル変数として定義**されています（MS Learn 原文どおり）。
- 実 Bedrock に向ける場合は C# 式内の `var region = "us-east-1";` を Bedrock のリージョンに合わせて書き換えるだけ。本ラボの mimic は署名を検証しないため `us-east-1` のままで OK。
- `{{accesskey}}` / `{{secretkey}}` は (1) で作成した Named Value をそのまま参照します。

</details>

<details>
<summary>クリックして開く — SigV4 署名ポリシー改良版全文（`<policies>` 全体をこれで置換）</summary>

```xml
<policies>
  <inbound>
    <base />
    <!-- §4-1A で作った Backend に転送先を固定（ウィザード生成時の転送設定が全置換で消えたため、ここで明示する）-->
    <set-backend-service backend-id="bedrock-api-backend" />
    <set-variable name="now" value="@(DateTime.UtcNow)" />
    <!-- body は 1 回だけ読んで以降は context.Variables["requestBody"] で使い回す（MS Learn 原文では両 set-header 内で Body.As<string>(preserveContent: true) を 2 回呼ぶが、一部 APIM ビルドで 2 回目が null を返して NRE となるため）-->
    <set-variable name="requestBody" value="@(context.Request.Body.As<string>(preserveContent: true) ?? "")" />
    <set-header name="X-Amz-Date" exists-action="override">
      <value>@(((DateTime)context.Variables["now"]).ToString("yyyyMMddTHHmmssZ"))</value>
    </set-header>
    <set-header name="X-Amz-Content-Sha256" exists-action="override">
      <value>@{
        var body = (string)context.Variables["requestBody"];
        using (var sha256 = System.Security.Cryptography.SHA256.Create())
        {
          var hash = sha256.ComputeHash(System.Text.Encoding.UTF8.GetBytes(body));
          return BitConverter.ToString(hash).Replace("-", "").ToLowerInvariant();
        }
      }</value>
    </set-header>
    <set-header name="Authorization" exists-action="override">
      <value>@{
        var accessKey = "{{accesskey}}";
        var secretKey = "{{secretkey}}";
        var region = "us-east-1";
        var service = "bedrock";

        var method = context.Request.Method;
        // OriginalUrl を使う（上記ポイント 3 参照。Url だと set-backend-service 後のコンテキストで Host が空になるビルドがあるため）
        var uri = context.Request.OriginalUrl;
        var host = uri.Host;

        // Create canonical path
        var path = uri.Path;
        var modelSplit = path.Split(new[] { "model/" }, 2, StringSplitOptions.None);
        var afterModel = modelSplit.Length > 1 ? modelSplit[1] : "";
        var parts = afterModel.Split(new[] { '/' }, 2);
        var model = System.Uri.EscapeDataString(parts[0]);
        var remainder = parts.Length > 1 ? parts[1] : "";
        var canonicalPath = $"/model/{model}/{remainder}";

        var amzDate = ((DateTime)context.Variables["now"]).ToString("yyyyMMddTHHmmssZ");
        var dateStamp = ((DateTime)context.Variables["now"]).ToString("yyyyMMdd");

        // Hash the payload（1 回だけ読んだ body を使い回す）
        var body = (string)context.Variables["requestBody"];
        string hashedPayload;
        using (var sha256 = System.Security.Cryptography.SHA256.Create())
        {
          var hash = sha256.ComputeHash(System.Text.Encoding.UTF8.GetBytes(body));
          hashedPayload = BitConverter.ToString(hash).Replace("-", "").ToLowerInvariant();
        }

        // Canonical query string（本ラボの mimic は query を使わないため空で固定）
        var canonicalQueryString = "";

        // Create signed headers and canonical headers
        var headers = context.Request.Headers;
        var canonicalHeaderList = new List<string[]>();

        if (headers.ContainsKey("Content-Type"))
        {
          var ct = headers["Content-Type"].FirstOrDefault() ?? "";
          canonicalHeaderList.Add(new[] { "content-type", ct.ToLowerInvariant() });
        }
        canonicalHeaderList.Add(new[] { "host", host });
        canonicalHeaderList.Add(new[] { "x-amz-content-sha256", hashedPayload });
        canonicalHeaderList.Add(new[] { "x-amz-date", amzDate });

        var canonicalHeadersOrdered = canonicalHeaderList.OrderBy(h => h[0]).ToList();
        var canonicalHeaders = string.Join("\n", canonicalHeadersOrdered.Select(h => h[0] + ":" + (h[1] ?? "").Trim())) + "\n";
        var signedHeaders = string.Join(";", canonicalHeadersOrdered.Select(h => h[0]));

        // Create and hash the canonical request
        var canonicalRequest = $"{method}\n{canonicalPath}\n{canonicalQueryString}\n{canonicalHeaders}\n{signedHeaders}\n{hashedPayload}";
        string hashedCanonicalRequest;
        using (var sha256 = System.Security.Cryptography.SHA256.Create())
        {
          var hash = sha256.ComputeHash(System.Text.Encoding.UTF8.GetBytes(canonicalRequest));
          hashedCanonicalRequest = BitConverter.ToString(hash).Replace("-", "").ToLowerInvariant();
        }

        // Build string to sign
        var credentialScope = $"{dateStamp}/{region}/{service}/aws4_request";
        var stringToSign = $"AWS4-HMAC-SHA256\n{amzDate}\n{credentialScope}\n{hashedCanonicalRequest}";

        // Sign it using secret key
        byte[] kSecret = System.Text.Encoding.UTF8.GetBytes("AWS4" + secretKey);
        byte[] kDate, kRegion, kService, kSigning;
        using (var h1 = new System.Security.Cryptography.HMACSHA256(kSecret)) { kDate = h1.ComputeHash(System.Text.Encoding.UTF8.GetBytes(dateStamp)); }
        using (var h2 = new System.Security.Cryptography.HMACSHA256(kDate)) { kRegion = h2.ComputeHash(System.Text.Encoding.UTF8.GetBytes(region)); }
        using (var h3 = new System.Security.Cryptography.HMACSHA256(kRegion)) { kService = h3.ComputeHash(System.Text.Encoding.UTF8.GetBytes(service)); }
        using (var h4 = new System.Security.Cryptography.HMACSHA256(kService)) { kSigning = h4.ComputeHash(System.Text.Encoding.UTF8.GetBytes("aws4_request")); }

        // Auth header
        string signature;
        using (var hmac = new System.Security.Cryptography.HMACSHA256(kSigning))
        {
          var sigBytes = hmac.ComputeHash(System.Text.Encoding.UTF8.GetBytes(stringToSign));
          signature = BitConverter.ToString(sigBytes).Replace("-", "").ToLowerInvariant();
        }

        return $"AWS4-HMAC-SHA256 Credential={accessKey}/{credentialScope}, SignedHeaders={signedHeaders}, Signature={signature}";
      }</value>
    </set-header>
    <!-- ※ MS Learn 原文にある <set-header name="Host"> は意図的に削除している（上記ポイント 3 参照）。セクション 4-2 のポイントの上で詳細説明。 -->
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
```

</details>

> :information_source: 上記 XML は `apim-aigw-userxx`（Developer SKU / japaneast）で「200 OK + `Echo: hello via Bedrock through APIM with SigV4 no Host header`」を返すことを実機検証済みです。APIM のポリシー仕様が今後変わった場合は MS Learn の最新版を優先してください（出典 URL は同じ）。

## 4-3. Backend 一覧を確認

APIs 一覧に Lab 3 の `openai-api` と合わせて **2 API**、Backends → **バックエンド** タブに **2 Backend** が並びます。

| API | Backend | 作成方法 | プロトコル / 認証 |
|---|---|---|---|
| `openai-api` | `openai-api-ai-endpoint` | ウィザード自動生成 | Foundry エンドポイント / **Managed identity** |
| `bedrock-api` | `bedrock-api-backend` | **§4-1A で手動作成**（ウィザード生成の `bedrock-api-openai-endpoint` は削除済み）| `<MIMIC_BASE_URL>` / なし（SigV4 は Inbound ポリシーで付与）|

## 4-4. 動作確認

動作確認は次の 3 通りで実施できます。どれでも 200 と同じ echo レスポンスが返ります。

| # | 経路 | 主用途 |
|---|---|---|
| (1) | APIM Test コンソール | Portal 上で Trace を眺めて SigV4 ヘッダーが組み上がる様子を観察 |
| (2) | PowerShell の `curl.exe` | コマンドラインから素の HTTP で確認（ハンズオン本流） |
| (3) | AWS ネイティブ SDK（.NET）| 実プロジェクトのコード経路に最も近い形での動作確認 |

### (1) APIM Test コンソール（任意・Trace 観察用）

`APIs → bedrock-api → Test タブ → POST *`

| 設定 | 値 |
|---|---|
| Template parameters → `*` | `model/us.anthropic.claude-3-5-haiku-20241022-v1:0/converse` |
| Headers → `Content-Type` | `application/json` |
| Request body | `{"messages":[{"role":"user","content":[{"text":"hello via Bedrock"}]}],"inferenceConfig":{"maxTokens":256}}` |

`Send` 実行 → **HTTP 200** と Bedrock Converse 形式の echo レスポンスが返ります。

> :information_source: Test コンソールは `*` ワイルドカードの値を 1 URL セグメントとして扱うため、内部的に `/` を `%2F` に、`:` を `%3A` にエンコードして Backend へ送ります（Request URL に `model%2F...%2Fconverse` と表示される）。mimic 側の FastAPI ルート `/model/{model_id:path}/converse` は `%2F` を `/` としてデコードして受け付け、APIM の SigV4 ポリシー側も canonical path 生成時に modelId を `EscapeDataString` で同形にエンコードして署名するため、**エンコードあり/なし両方の経路で署名整合性が保たれ 200 が返ります**（実機検証済み）。
>
> Trace タブを開けば、`set-header (Authorization)` ステップで `AWS4-HMAC-SHA256 Credential=...` ヘッダーが生成されている様子が一行ずつ確認できます。

### (2) PowerShell (curl.exe) から

Lab 3 で作成したサブスクリプション キーをそのまま流用します。

```pwsh
$APIM = "https://apim-aigw-<initials>.azure-api.net"
$KEY  = "<Lab 3 のサブスクリプション主キー>"
$MODEL_ID = "us.anthropic.claude-3-5-haiku-20241022-v1:0"
$tmp  = New-TemporaryFile

# bedrock-api (mimic / Bedrock Converse passthrough with SigV4)
'{"messages":[{"role":"user","content":[{"text":"hello via Bedrock"}]}],"inferenceConfig":{"maxTokens":256}}' |
  Set-Content -Path $tmp -Encoding utf8 -NoNewline
curl.exe -i -X POST "$APIM/bedrock/model/$MODEL_ID/converse" `
  -H "api-key: $KEY" `
  -H "Content-Type: application/json" `
  --data-binary "@$tmp"

Remove-Item $tmp -Force
```

### (3) AWS ネイティブ SDK（.NET）から

リポジトリの [`bedrock-APIM-direct/`](../../bedrock-APIM-direct) フォルダに、AWS 公式 .NET SDK（`AWSSDK.BedrockRuntime`）の `AmazonBedrockRuntimeClient.ConverseAsync` をそのまま使い、**`ServiceURL` に APIM のエンドポイントを直接指定**するサンプル一式が同梱されています。Bedrock 用 URL を APIM の URL に差し替えるだけで、既存の Bedrock SDK 資産がそのまま APIM 経由で動くことが確認できます。

> :warning: 本サンプルは机上検証と SDK 仕様に基づいて構成した擬似環境での確認結果です。**実環境および実環境での実装方式での検証は別途必須**です。

| ファイル | 役割 |
|---|---|
| `bedrock-APIM-direct/Program.cs` | Bedrock SDK で `ConverseAsync` を呼ぶエントリポイント。`AmazonBedrockRuntimeConfig.ServiceURL` に APIM の URL を直接設定 |
| `bedrock-APIM-direct/BedrockClient.csproj` | .NET 8 / `AWSSDK.BedrockRuntime` への参照 |

> :information_source: **AWS の認証情報はダミーで OK**: `Program.cs` の `accessKey` / `secretKey` は非空のダミー値です（SDK が `Authorization` ヘッダーを生成するために非空が必須）。SDK が生成する SigV4 署名ヘッダーは APIM の Inbound ポリシーが §4-2 の Named Value (`{{accesskey}}` / `{{secretkey}}`) を使って **上書き再生成** するため、クライアント側で実 AWS の鍵を持つ必要はありません。本番で実 AWS Bedrock に向ける場合も、認証情報は APIM の Named Value 側にだけ置けば十分です。
>
> :information_source: **`ServiceURL` と `RegionEndpoint` は相互排他**: AWS SDK の仕様上、後から設定した方が有効になります。`Program.cs` ではこのため `ServiceURL` をイニシャライザの最後に置いています。

#### 事前要件

- .NET 8 SDK（`dotnet --version` で `8.0.x` 以上）

#### 実行手順

```pwsh
cd .\bedrock-APIM-direct
$env:APIM_BEDROCK_URL      = "https://apim-aigw-<initials>.azure-api.net/bedrock"
$env:APIM_SUBSCRIPTION_KEY = "<Lab 3 のサブスクリプション主キー>"
dotnet run
```

期待される標準出力（mimic は入力プロンプトをエコーする実装のため、`Program.cs` 中の `userMessage` がそのまま返ってきます）:

```text
[AWS Bedrock mimic API] Echo response: Describe the purpose of a 'hello world' program in one line.
```

#### 確認ポイント

- AWS Bedrock SDK の `ServiceURL` を APIM の URL に向けるだけで、`ConverseAsync` が APIM 経由で成功する（**URL を Bedrock から APIM に差し替えるだけで既存資産がそのまま動く**ことの実証）
- ハンズオン本番ではここの `userMessage` を任意のテキストに差し替えるだけで、Bedrock SDK の `ConverseRequest` / `InferenceConfiguration` 等の高レベル API がそのまま APIM 経由で利用できることが確認できる

## チェックリスト

- [ ] **Language Model API** ウィザード（Passthrough）で `bedrock-api` を mimic 向けに作成した
- [ ] §4-1A で **`bedrock-api-backend`（カスタム URL = `<MIMIC_BASE_URL>`）** を手動作成し、ウィザード自動生成の `bedrock-api-openai-endpoint` を削除した
- [ ] Named Values に `accesskey` / `secretkey` をシークレットとして登録した（mimic 向けはダミー値で可）
- [ ] §4-2(2) の **改良版 SigV4 ポリシー XML**（`<set-backend-service backend-id="bedrock-api-backend" />` + body 1 回読み + Host set-header なし + `OriginalUrl` 使用）を `bedrock-api` の Inbound に貼り付けた
- [ ] サブスクリプション キーで `openai-api` / `bedrock-api` の 2 API が 200 を返す
- [ ] APIM Test コンソール（または curl）で **HTTP 200** と Bedrock Converse 形式の echo レスポンスを確認した
- [ ] APIM Test コンソールの Trace で `Authorization: AWS4-HMAC-SHA256 ...` ヘッダーが生成されていることを確認した
- [ ] `bedrock-APIM-direct/` の AWS ネイティブ SDK サンプル（`dotnet run`）が APIM 経由で `[AWS Bedrock mimic API] Echo response: ...` を返した

完了したら [Lab 5 — 外部環境（AWS 相当）で APIM Self-hosted Gateway を展開](./lab5.md) へ。
