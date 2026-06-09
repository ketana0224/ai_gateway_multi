# OpenTelemetry E2E トレースの補足情報

[Lab 6](./labs/lab6.md) §6-2 で「App Insights を紐付けるだけで OTel 計装が完了する」「APIM 起点から末端まで連結される」と説明していますが、**APIM はあくまでパイプの中流** であり、その上流（呼び出し元クライアント / エージェント / フロントエンド）まで含めた **真の End-to-End** を実現するには別の条件が必要です。本ドキュメントでその境界条件と実装パターンを整理します。

## 1. E2E トレース連結の必要条件

### 1-1. 最初に押さえる原則（E2E 成立の優先順位）

E2E を成立させたいなら、次の優先順位で対処してください。**これがすべての出発点** で、以降のマトリクスや個別コンポーネントの話はこの原則の派生です。

1. **【最重要】 全コンポーネントが W3C `traceparent` を受信して下流に伝搬する**  
   → これが切れたら何をしても繋がらない。trace-id (= 1 本の "糸") を全コンポーネントで共有することが分散トレースの大前提
2. **【理想】 全コンポーネントが同じ App Insights に span を送る**  
   → 1 画面（Application Insights のエンドツーエンド トランザクション）で完結する
3. **【現実的妥協】 一部が別 APM の場合は、trace-id をログに必ず残す ことを徹底し、複数 APM を trace-id で横串検索する運用にする**  
   → 完全な 1 画面表示は諦めるが、追跡そのものは可能

> :information_source: **APM (Application Performance Monitoring)** = Application Insights / AWS X-Ray / Datadog / New Relic / Dynatrace 等の「span を蓄積・可視化する製品」の総称。OTel は計装側の標準仕様で、APM は OTel が出した span を受け取って可視化するバックエンド側です。

### 1-2. なぜこの 2 条件なのか — 役割の違い

優先順位 1 と 2 は似て見えますが、**全く別の役割** を持ちます。混同すると「片方だけ満たせば E2E できる」と誤解しがちなので明確に区別します。

| 条件 | 何を保証するか | 比喩 |
|---|---|---|
| **条件 1: W3C `traceparent` の受信と伝搬** | **trace-id (= 1 本の "糸") の連続性**。各コンポーネントの span が同じ親子関係に紐づくこと | 配達伝票の **追跡番号** を全配送業者で共有すること |
| **条件 2: 同じ App Insights (APM) への span 送信** | **1 つの可視化画面で見える "宛先" の統一**。trace-id が同じでも別 APM に span が散らばれば 1 画面では見えない | 配達状況を **1 つのダッシュボード** で確認できる状態にすること |

APIM は **incoming `traceparent` ヘッダがあればそれを親 span として継承し、なければ新しい trace-id を発番** します。つまり条件 1 は APIM だけでなく **APIM の上流コンポーネントが伝票を発番・伝搬してくれるか** にかかっています。

### 1-3. 4 ケースで整理した可否マトリクス

| 条件 1 (`traceparent`) | 条件 2 (App Insights 送信) | E2E 分散トランザクション可否 |
|---|---|---|
| ◯ 扱える | ◯ App Insights に送る | **◯ E2E 成立**（1 画面で連続表示） |
| ◯ 扱える | ✗ 別 APM (X-Ray / Datadog 等) | **△ trace-id は連続するが App Insights 単体では断絶**（複数 APM を trace-id で突き合わせる運用なら追跡は可能） |
| ✗ 扱えない | ◯ App Insights に送る | **△ trace-id が切れる** → そのコンポーネント以降は別トレースとして記録（コンポーネント単体の監視は可能、E2E にはならない） |
| ✗ 扱えない | ✗ 別 APM | **✗ 完全に断絶**（コンポーネントごとに独立したトレース、E2E 不可） |

### 1-4. 個別条件の不成立時の挙動

| # | 条件 | 満たさないとどうなる |
|---|---|---|
| 1 | **上流が W3C `traceparent` ヘッダを送信** している | APIM が新しい trace-id を発番し、**トレースの始点が APIM になる**（クライアント側の処理時間は見えない） |
| 2 | **上流が同じ App Insights (または同一 Log Analytics workspace) に span を送信** している | trace-id は連続するが、別の App Insights / 別 APM に分散して **トランザクション検索の 1 画面では繋がって見えない**（cross-resource query / 手動突き合わせが必要） |

両方を満たせば、Application Insights の「エンドツーエンド トランザクション」ビューに **クライアント → APIM → backend** が 1 本のタイムラインで描画されます。

## 2. 上流コンポーネント別の "コードレス度"

> :information_source: **表の凡例**:
> - **◯** = 既定で自動的に行われる（コードレス）
> - **△** = 別形式では送出されるが W3C ではない、または条件付きで動作する
> - **✗** = 既定では行われない（実現には別途設定 / SDK 組み込み / ヘッダ手動付与が必要。**できない訳ではない**）

### 2-1. Azure / 一般 Web クライアント

| 上流の種類 | `traceparent` 自動送信 | App Insights 自動送信 | 必要作業 |
|---|---|---|---|
| **ブラウザ JS / SPA** | ✗ | ✗ | Application Insights JavaScript SDK のスニペット 1 個（`<script>` 1 行） |
| **モバイル ネイティブ** | ✗ | ✗ | OTel SDK 手動組み込み |
| **App Service / Functions / Container Apps の managed image (.NET / Java / Node.js)** | ◯ | ◯ | **App Insights を紐付けるだけ**（ランタイム拡張が agent を auto-attach。**真にコードレス**） |
| **App Service / Functions の Python** | △（stdout / incoming HTTP は自動。細かい span は要 SDK） | ◯ | アプリ設定 + 必要に応じて `azure-monitor-opentelemetry` パッケージ |
| **Container Apps の自前イメージ (Python / Node / Go)** | △（stdout/stderr → traces は自動。**HTTP span は SDK 必須**） | ◯ | `azure-monitor-opentelemetry` 等を 1〜3 行で初期化（**完全コードレスではない**） |
| **Foundry リソース / Foundry Agent (hosted)** | ◯ | ◯ | リソース画面で App Insights を接続するだけ。モデル呼び出し span に GenAI 属性が自動付与（**真にコードレス**） |
| **LangChain / Semantic Kernel / AutoGen (SDK)** | ◯（OTel 対応クラス標準装備） | ✗ | ハンドラ登録の **数行コード追加が必要**（例: `OpenTelemetryCallbackHandler` / `AddOpenTelemetry()`）。**コードレスではない** |
| **MCP クライアント（Claude Desktop など）** | ✗（現状の MCP 仕様では trace 伝播未定義） | ✗ | クライアント側で OTel SDK ラッパが必要 |
| **既存 .NET / Java の業務アプリ** | ◯（auto-instrumentation 対応言語） | App Insights agent 接続のみ | エージェント JAR / NuGet 1 個 |
| **`curl` / `Postman` / APIM Test コンソール** | ✗ | ✗ | **始点は APIM になる**（本ハンズオンの状況） |

### 2-2. Microsoft 365 Copilot / Copilot Studio / M365 Agents

Microsoft 自身が提供する "Copilot / エージェント プラットフォーム" は **3 系統あり、可観測性のレベルが大きく異なる** ので注意。

| プラットフォーム | 上流側 App Insights 接続 | APIM への `traceparent` 自動付与 | E2E 連結のしやすさ |
|---|---|---|---|
| **Copilot Studio** | ◯ 設定画面で App Insights 接続可（`customEvents` に会話 / インテント / アクションが流れる） | ✗ Connector / HTTP アクションは W3C 伝搬未対応（2026/5 時点） | △ trace 連結したい場合は HTTP アクションで `traceparent` ヘッダを **手動セット** が必要 |
| **M365 Agents Toolkit / Custom engine agents** | ◯ スキャフォールド時に `appi-*` リソースと `APPLICATIONINSIGHTS_CONNECTION_STRING` を **自動投入** | ◯ Azure ホスト (App Service / Functions / Container Apps) + .NET / Java なら auto-instrumentation で **自動付与** | ◯ **真にコードレスで E2E** が成立する系統。Node.js は `@azure/monitor-opentelemetry` 初期化のみ |
| **M365 Copilot Declarative Agents** (旧 Copilot プラグイン) | ✗ M365 Copilot 本体は Microsoft 内部テレメトリのみ。お客様の App Insights には流れない | ✗ プラグインからの outgoing HTTP の W3C 伝搬は **公式仕様非公開** | ✗ お客様の可観測領域は **プラグイン バックエンド以降のみ**（APIM が始点） |

#### Copilot Studio の連結ステップ（参考）

1. **設定 > 詳細 > Application Insights** で `appi-aigw-<initials>` を接続 → 会話イベントを App Insights へ
2. APIM を呼ぶカスタム HTTP アクションを作成し、ヘッダに以下を追加:

   | ヘッダ | 値（式） |
   |---|---|
   | `traceparent` | `00-{Topic.ConversationId のハイフン除去 32 hex}-{ランダム 16 hex}-01` |

3. APIM 側 `Correlation protocol = W3C` なので、この trace-id が APIM → Foundry まで継承される
4. App Insights の **トランザクション検索** で同じ trace-id で `customEvents` (Copilot Studio) と `dependencies` (APIM/Foundry) が並ぶ

#### M365 Agents Toolkit の連結（既定で成立）

1. `teamsapp.yml` / `infra/azure.bicep` で **App Insights リソースが自動作成**
2. エージェントを App Service / Functions / Container Apps にデプロイすると `APPLICATIONINSIGHTS_CONNECTION_STRING` が **自動 inject**
3. .NET / Java の場合は HttpClient auto-instrumentation で APIM への呼び出しに `traceparent` が自動付与
4. **何もしなくても** `M365 Agent → APIM → Foundry` の 3 階層が App Insights に出る

#### Declarative Agents の現実

- プラグイン (API バックエンド) 側だけがお客様の可観測対象
- M365 Copilot 本体の処理時間は **見えない / 知りようがない** ことを SLO 設計時に明記
- 将来 Microsoft 側で W3C 伝搬が公開された場合に備え、APIM 側で `traceparent` を受け入れる設定（`Correlation protocol = W3C`）は今のうちから入れておくのが推奨

> :information_source: **判定の最速手段**: Copilot Studio / M365 Agent からテスト呼び出しを 1 回打ち、APIM Trace タブの `Backend → request-forwarder → request.headers` に **既に `traceparent` が来ているか** を見る。来ていれば連結済み、来ていなければ手動付与 or 諦めて APIM 起点。

### 2-3. 非 Azure クラウド (AWS / GCP) の上流コンポーネント

非 Azure クラウドから APIM を呼ぶ場合、**W3C `traceparent` 自体は OTel SDK が言語ランタイム共通で扱える** ため、ヘッダ送出は問題なく実現できます。ただし **App Insights への span 送出はクラウドごとに既定の宛先が異なる** ため明示設定が必要です。

| 上流の種類 | `traceparent` 自動送信 | App Insights 自動送信 | 必要作業 |
|---|---|---|---|
| **AWS Lambda (X-Ray 既定)** | △（既定は `X-Amzn-Trace-Id`。W3C 変換は別途設定） | ✗（既定は X-Ray） | [ADOT (AWS Distro for OpenTelemetry) Lambda Layer](https://aws-otel.github.io/docs/getting-started/lambda) を追加し、OTLP exporter を **Application Insights の OTLP エンドポイント** に向ける |
| **AWS ECS / Fargate / EC2** | OTel SDK 入れれば ◯ | ✗ | アプリ側に `azure-monitor-opentelemetry` (Python/Node) または OTel Java auto-instrumentation agent を組み込み、`APPLICATIONINSIGHTS_CONNECTION_STRING` を env で渡す。AWS 側から Azure へのアウトバウンドが許可されている必要あり |
| **AWS API Gateway / ALB** | ✗（X-Amzn-Trace-Id のみ） | ✗ | API Gateway 自身は W3C 非対応。ALB の前段に Lambda 等を挟んで変換するか、APIM 側で `x-amzn-trace-id` を `traceparent` に変換するポリシーを書く |
| **AWS Bedrock Agents / Step Functions** | ✗（X-Ray のみ） | ✗ | アプリ ロジック側で OTel SDK 計装が必要。サービス自体の組込み計装は X-Ray のみ |
| **GCP Cloud Run / Cloud Functions** | OTel SDK 入れれば ◯ | ✗（既定は Cloud Trace） | OTel SDK + Azure Monitor exporter または OTLP exporter |
| **GCP API Gateway** | ✗ | ✗ | Cloud Trace 連携のみ。W3C 変換は前段 Cloud Function で実装 |

> :information_source: **Azure Monitor OTLP エンドポイント**: Application Insights は OTLP/HTTP 受信を **プレビューでサポート** しています（リージョンにより GA 状況が異なる）。エンドポイントは `https://<region>.in.applicationinsights.azure.com/v2.1/track`（ingestion）または OTLP 専用 endpoint（プレビュー）。実運用では Azure Monitor exporter (`azure-monitor-opentelemetry`) を使う方が安定。

> :warning: **APIM の下流が AWS / GCP の連鎖になる場合**（例: APIM → AWS API Gateway → Lambda → Bedrock）も同じ判定軸が適用されますが、**AWS / GCP 側の各サービスごとに W3C 対応・export 先・ADOT 設定が異なる** ため、本ドキュメントでは網羅できません。**AWS / GCP 側の運用チームに以下 3 点の確認を依頼** してください:
>
> 1. 各サービスが **受信した `traceparent` を継承して下流に転送するか**（多くの AWS サービスは既定で `X-Amzn-Trace-Id` のみ。W3C は無視 / 破棄される）
> 2. 各サービスの span を **App Insights / X-Ray のどちらに送るか**（OTLP exporter を App Insights に向けるか、X-Ray に出して trace-id で別ツール突き合わせ運用にするか）
> 3. AWS / GCP → Azure へのアウトバウンド ネットワーク経路が **許可・閉域要件を満たすか**

### 2-4. SaaS / サードパーティ AI エージェント プラットフォーム

SaaS 系の AI エージェント プラットフォーム（Jinba.ai 等）は **APIM の上流（呼び出し元）にも下流（バックエンド）にもなり得る** ため、両方向で E2E 連結の判定軸が変わります。

#### 上流（APIM を呼ぶ側）として使う場合

E2E トレース連結ができるかは **プラットフォームが以下の 2 機能を提供しているか** で決まります。

| 判定軸 | 確認方法 |
|---|---|
| (1) 外部 HTTP 呼び出し時に **W3C `traceparent` ヘッダを送信** するか | プラットフォームの公式ドキュメントで「W3C Trace Context」「OpenTelemetry」「distributed tracing」のキーワード検索 / もしくは APIM Trace 機能で実リクエストを観察して `traceparent` の有無を確認 |
| (2) 自身の span を **外部 OTel collector / Azure Monitor に exporter で送出** できるか | 「Webhook for traces」「OTLP exporter」「External APM integration」等の機能の有無 |

#### 下流（APIM から呼ばれる側）として使う場合

APIM が backend として SaaS エージェントを呼ぶ場合、APIM 側 §6-1(b) `Correlation protocol = W3C` により `traceparent` は自動で乗りますが、**SaaS 側の挙動次第で見え方が変わります**。

| SaaS 側の挙動 | App Insights での見え方 |
|---|---|
| 受信した `traceparent` を **受理し内部処理の span を継続発番**、かつ **同じ App Insights / OTLP に export** | ◯ 真の E2E（APIM → SaaS 内部 span → さらに下流）が 1 つの trace に並ぶ |
| 受信した `traceparent` を **受理して trace-id 継承するが、span は SaaS 自身の APM にのみ送出** | △ 同一 trace-id で **2 つの APM を突き合わせる** 運用（App Insights 側は APIM の dependency span だけが見える） |
| `traceparent` を **無視 / 上書き** する | ✗ APIM の dependency span 1 つ（ブラックボックス）として処理時間のみ見える |

#### Jinba.ai を使う場合（上流・下流共通）

> :warning: 2026 年 5 月時点で Jinba.ai の OTel 連携仕様は公式公開情報が限定的です。**E2E 連結が必要な場合は、Jinba.ai のサポート窓口 / 公式ドキュメントで以下 3 点の確認が必要** です。
>
> 1. **上流時**: 外部 HTTP 呼び出し時に **W3C `traceparent` ヘッダを送出するか**（送出されない場合、カスタムヘッダ機能等で手動付与できるか）
> 2. **下流時**: 受信した `traceparent` を **継承して内部 span を発番するか**（受理 / 無視 / 上書きのいずれか）
> 3. **共通**: 自身の span を **OTLP / Azure Monitor exporter で外部に送出できるか**

> :information_source: **判定の最速手段**:
>
> - **上流時**: Jinba.ai から実際に APIM を 1 回叩いて、APIM Trace タブの `Inbound → request.headers` に `traceparent` が来ているかを確認
> - **下流時**: APIM から Jinba.ai を 1 回呼び、Jinba.ai 側の管理画面 / ログに APIM 由来の trace-id が現れるかを確認（同 trace-id で span が記録されていれば最低限の継承は成立）

---

# 📎 以下は参考情報

> :warning: **ここから先（§3 以降）は参考情報です**
>
> 本ハンズオン（[Lab 6](./labs/lab6.md)）の実施に **必須の知識ではありません**。
>
> - §3: 本ラボのスコープが「APIM 起点の 2 階層トレース」であることの位置付け説明
> - §4: 真の E2E（クライアント起点）に拡張したい場合のパターン例
> - §5: まとめ
>
> ラボを進める上では §1〜§2 の理解で十分です。E2E トレースを自身の環境で再現・拡張したいときの参考としてご覧ください。

---

## 3. ハンズオン本編の位置付け

本ハンズオン（Lab 6）の動線は **APIM の Test コンソール / curl から直接 APIM へ** リクエストを送るため、`traceparent` は上流から伝搬してきません。したがって [Lab 6](./labs/lab6.md) §6-4 で見える「エンドツーエンド トランザクション」は:

```
[apim-aigw-handson-<initials>]  POST /openai/...    ← トレースの始点 = APIM
  └─ [aif-aigw-handson-<initials>]  openai.chat.completions
```

という **2 階層** のトレースです。これは **「APIM 起点でダウンストリーム側を末端まで連結」** という意味であり、**ブラウザやエージェント等の上流クライアントを含む E2E ではない** ことに注意してください。

## 4. 真の E2E を見せたい場合の拡張パターン

ラボ標準スコープ外ですが、以下のいずれかを追加すると **クライアント起点の E2E** に拡張できます。

### パターン A: ブラウザ起点の E2E（最も短い）

1. Azure Static Web App などに以下の `index.html` をデプロイ:

   ```html
   <!-- App Insights JS SDK のスニペット -->
   <script type="text/javascript" src="https://js.monitor.azure.com/scripts/b/ai.3.min.js"></script>
   <script>
     var appInsights = new Microsoft.ApplicationInsights.Web.ApplicationInsights({
       config: {
         connectionString: "<appi-aigw-<initials> の接続文字列>",
         distributedTracingMode: 2,            // W3C のみ
         enableCorsCorrelation: true,
         enableRequestHeaderTracking: true,
         enableResponseHeaderTracking: true
       }
     });
     appInsights.loadAppInsights();
   </script>
   <button onclick="callApim()">Call APIM</button>
   <script>
     async function callApim() {
       await fetch("https://apim-aigw-handson-<initials>.azure-api.net/openai/openai/responses?api-version=2025-03-01-preview", {
         method: "POST",
         headers: { "Content-Type": "application/json", "api-key": "<sub-key>" },
         body: JSON.stringify({ model: "gpt-4o-mini", input: "hi" })
       });
     }
   </script>
   ```

2. ボタンをクリック → App Insights → トランザクション検索 → 1 件選ぶと:

   ```
   [browser]  fetch /openai/...                ← 始点 = ブラウザ
     └─ [apim-aigw-handson-<initials>]  POST /openai/...
          └─ [aif-aigw-handson-<initials>]  openai.chat.completions
   ```

   3 階層が 1 本のタイムラインで見える。

3. APIM 側の CORS ポリシーで `Access-Control-Allow-Headers` に **`traceparent`** と **`request-id`** を含めること（含めないとブラウザの fetch が `traceparent` を送らない）。

### パターン B: バックエンド エージェントが上流の E2E

Container Apps 等に薄い Python / Node クライアントを置き、`azure-monitor-opentelemetry` パッケージで自動計装する:

```python
# client.py
from azure.monitor.opentelemetry import configure_azure_monitor
import httpx
configure_azure_monitor()  # APPLICATIONINSIGHTS_CONNECTION_STRING を自動で拾う

httpx.post(
    "https://apim-aigw-handson-<initials>.azure-api.net/openai/openai/responses?api-version=2025-03-01-preview",
    headers={"api-key": "<sub-key>"},
    json={"model": "gpt-4o-mini", "input": "hi"},
)
```

`httpx` / `requests` / `urllib3` 等は自動計装対象で、**`traceparent` ヘッダが outgoing リクエストに勝手に乗ります**。App Insights には:

```
[client-app]  POST https://apim-aigw-handson-.../openai/...   ← 始点 = クライアント
  └─ [apim-aigw-handson-<initials>]  POST /openai/...
       └─ [aif-aigw-handson-<initials>]  openai.chat.completions
```

が見える。

## 5. まとめ

- 「App Insights を紐付けるだけ」で完了するのは **ダウンストリーム側**（APIM の後ろ）の話
- **上流側** は別途 `traceparent` 送出が必要（Azure PaaS 上のアプリなら大半が自動、ブラウザ / MCP クライアントは要対応）
- 本ハンズオンは **APIM 起点の 2 階層トレース** までを公式スコープとする
- 真の E2E は **パターン A (ブラウザ) または B (バックエンド クライアント)** で拡張可能、ただし演習時間 +30 分

## 関連リソース

- [Lab 6 §6-2 ダウンストリームの OTel 計装](./labs/lab6.md#6-2-ダウンストリームのotel計装コードレス自動計装)
- [Lab 6 §6-2-b Foundry に Application Insights を接続](./labs/lab6.md#6-2-b-foundry-に-application-insights-を接続するコードレス-otel)
- [Application Insights for ASP.NET Core 自動計装](https://learn.microsoft.com/azure/azure-monitor/app/asp-net-core)
- [Application Insights JavaScript SDK](https://learn.microsoft.com/azure/azure-monitor/app/javascript)
- [OpenTelemetry W3C Trace Context 仕様](https://www.w3.org/TR/trace-context/)
