# Lab 5 — 外部環境（AWS 相当）で APIM Self-hosted Gateway を展開

## ゴール

APIM の **コントロールプレーンは Azure**、**データプレーン（SHGW）は別ホスティング** に置くマルチクラウド構成を構築する。本ハンズオンでは **AWS アカウントを使用せず**、講師が事前に用意した共有 **Azure Container Apps 環境 `cae-apim-instructor`（East US）** を「AWS 相当の外部環境」として利用する。

> :information_source: SHGW のコンテナイメージ・環境変数・トークン認可は **AWS Fargate / EKS / EC2 にデプロイする場合と完全に同一** です。本番で AWS に置き換える際に変わるのはホスティング先のみです。本ハンズオンでは APIM 本体は `japaneast`、SHGW を載せる Container App は `eastus` というクロスリージョン配置にすることで、「別クラウド感」を Gateway リソースの `locationData` ラベルとリージョン差の両方で表現します。
>
> :information_source: **なぜ Container Apps か**: (1) 無償サブスクリプションでは Container Apps 環境の新規作成枠が限られるため、講師が用意した **共有 env `cae-apim-instructor`** に相乗りする（既存 env への Container App 追加は無料枠内に収まる）、(2) ACI は Resource Provider レベルで環境変数名にドット (`.`) を許可しないため SHGW が要求する `config.service.endpoint` / `config.service.auth` をそのまま渡せない、という 2 つの理由から **Azure Container Apps（Consumption）** を採用します。Container Apps は env 名にドットを許可し、Ingress に Azure 発行の TLS 証明書が付き、Portal だけでデプロイが完結します。

## 所要時間

約 55 分

## 事前条件

- [Lab 3](./lab3.md) 完了 — `openai-api` が APIM で動作中
- [Lab 4](./lab4.md) 完了 — `bedrock-api`（AWS Bedrock の Anthropic Claude）が APIM に登録済み
- APIM SKU が **Classic Developer** または **Premium**（StandardV2 等は不可）

> :warning: **Self-hosted Gateway は Classic Developer / Premium のみ対応**。
> StandardV2 で実施すると Gateway バインド時に `MethodNotAllowedInPricingTier` エラーになります。

---

## 5-1. APIM 側で Gateway リソースを作成

### Portal 手順

1. Azure Portal で `apim-aigw-handson-<id>` を開く
2. 左メニュー **デプロイとインフラストラクチャ > セルフホステッド ゲートウェイ** を選択
3. **＋ 追加** をクリック
4. 設定:
   - 名前: `gw-ext-tokyo-<id>`　「外部環境(AWS 相当)」を意図した命名
   - 場所: `aws-ap-northeast-1`　本番で AWS Tokyo にデプロイする想定
   - 説明: `External SHGW (AWS-mock on Azure Container Apps)`
   - API: そのまま（後で §5-2 でバインドするため、ここでは何も追加しない）
5. **追加** をクリックし、`gw-ext-tokyo-<id>` が一覧に表示されることを確認

> :information_source: 場所フィールドは Azure の実リージョンではなく **任意ラベル** です。`locationData.name` に該当し、APIM のメトリクススプリットに使われます。

## 5-2. Gateway に LLM API をバインド

### Portal 手順

1. APIM → **デプロイとインフラストラクチャ > セルフホステッド ゲートウェイ > `gw-ext-tokyo-<id>`** を開く
2. 左メニュー 設定 → **API** タブ
3. **＋ 追加** をクリック
4. Lab 4 で作った **`bedrock-api`** を選択して **追加**
5. 一覧に `bedrock-api` が表示されることを確認
6. `bedrock-api` の **URL スキーム** を `HTTP(S)` に変更:
   - APIM 左メニュー **APIs > API** → `Bedrock API` をクリック → 上部タブ **Settings（設定）**
   - **URL scheme** のラジオボタンで **`HTTP(S)`** を選択（HTTP と HTTPS の両方を許可）
   - 下部の **Save（保存）** をクリック

> :information_source: **なぜ HTTP が必要か**: 本ハンズオンでは Container Apps 標準 HTTP Ingress が TLS を終端してコンテナへ **HTTP:8080** で転送するため、`http` を含むスキーム（`HTTP(S)`）が必要です。全区間 TLS（クライアント〜SHGW 間も HTTPS）が要件の場合は、Azure も AWS も NLB／ACA TCP ingress モード等の **TLS パススルー構成** と APIM のカスタム証明書設定を組み合わせることで対応できます。本ハンズオンはその構成を省略した簡略版です。

## 5-3. Gateway トークンを生成（30 日有効）

### Portal 手順

1. APIM → **デプロイとインフラストラクチャ > セルフホステッド ゲートウェイ > `gw-ext-tokyo-<id>`** → 設定 → **デプロイ** タブ
2. **アクセス トークン** セクションで:
   - **有効期限**: 最大 30 日（Portal の日付ピッカーは 30 日先まで選択可。それ以上は設定不可）。本ハンズオンはデフォルト（当日から 30 日後）のままで OK
   - **秘密鍵**: `主キー` を選択
3. 上記を選んだ時点で **トークン** テキストボックスに `GatewayKey <gateway-id>&<expiry>&<signature>` 形式の完成済みトークンが自動表示される
4. 右端の **コピー** アイコンでクリップボードに保存し、安全な場所にメモ
5. トークン欄のすぐ下にある **構成エンドポイント** フィールドに `apim-aigw-handson-<id>.configuration.azure-api.net` が表示される（`config.service.endpoint` に使う値）
6. さらに下の **デプロイ スクリプト** セクション → **Docker** タブ → **環境 (env.conf)** ブロックに:
   ```
   config.service.endpoint=apim-aigw-handson-<id>.configuration.azure-api.net
   config.service.auth=GatewayKey <gateway-id>&<expiry>&<signature>
   runtime.deployment.artifact.source=Azure Portal
   runtime.deployment.mechanism=Docker
   ```
   が表示される。`config.service.endpoint` と `config.service.auth` の 2 行を控えておくと §5-4 での設定がスムーズです（`runtime.*` の 2 行は Container Apps には不要）

> :information_source: トークンは先頭の `GatewayKey ` （半角スペース付き）を含んだ状態で Portal に表示されます。**次の 5-4 で作成する Container App の環境変数 `config.service.auth` の「値」欄に、コピーした文字列をそのまま貼り付けてください**（プレフィックスを手で付け足す必要はありません）。

> :information_source: **本番運用でのトークンローテーション**: 有効期限は最大 30 日のため、期限切れ前に新しいトークンを生成して `config.service.auth` 環境変数を更新する必要があります。Container Apps の場合はシークレット更新 → リビジョン再デプロイの手順になります。Key Vault + マネージド ID でトークンを管理し、期限前に自動更新する仕組みを CI/CD パイプラインに組み込むことを推奨します。

> :information_source: 同じ画面の **デプロイ スクリプト** セクション (Docker / Kubernetes / Helm タブ) では、同じトークンを埋め込んだコンテナー / k8s デプロイテンプレートもダウンロードできますが、本ハンズオンでは 5-4 で Container App の作成ウィザードに手動で入力します。

## 5-4. Container App を作成（既存共有環境 `cae-apim-instructor` を利用）

> SHGW を動かす Container App を、講師が事前に用意した **共有 Container Apps 環境 `cae-apim-instructor`（リージョン: East US、リソースグループ: `rg-apim-instructor`）** にデプロイします。Container App 本体（`ca-shgw-<id>`）は任意のリソースグループに作成できますが、**App と env は同じリージョン（East US）** である必要があります。本番では env を AWS Fargate のクラスター、Container App を Fargate サービス／タスクに読み替えてください。

### Portal 手順

#### (a) 作成ウィザードを開く

1. Azure Portal の検索ボックスに「コンテナー アプリ」と入力し、**コンテナー アプリ** サービスを開く
2. 上部の **＋ 作成** → **コンテナー アプリ** をクリック

#### (b) 「基本」タブ

**プロジェクトの詳細** セクション:

| 項目 | 値 |
|---|---|
| サブスクリプション | `Azure subscription 1`（APIM と同じサブスクリプション） |
| リソース グループ | `rg-aigw-handson-<id>`（APIM 本体と同じ RG。env と異なるリージョンでも OK） |
| コンテナー アプリ名 | `ca-shgw-<id>` |
| Azure Functions 用に最適化 | **オフ**（チェックを入れない） |
| デプロイ元 | **コンテナー イメージ** |

**Container Apps 環境** セクション:

| 項目 | 値 |
|---|---|
| すべてのリージョンの環境を表示する | **オフ**（既定のまま） |
| リージョン | **East US**（共有 env のリージョンに合わせる。`Japan East` 等を選ぶと env がドロップダウンに表示されません） |
| Container Apps 環境 | `cae-apim-instructor (rg-apim-instructor)` を選択 |

> :warning: **リージョンは必ず East US**。env と異なるリージョンを選ぶとドロップダウンに `cae-apim-instructor (rg-apim-instructor)` が表示されません。
>
> :information_source: 「**新しい環境の作成**」リンクは押さないでください。共有 env を再利用するのが本ラボの目的です。

入力後、**次へ: コンテナー >** をクリックします。

#### (c) 「コンテナー」タブ

冒頭の **クイック スタート イメージを使用する** チェックは **オフのまま** にします（既定）。

**コンテナーの詳細** セクション:

| 項目 | 値 |
|---|---|
| 名前 | `ca-shgw-<id>` |
| イメージのソース | **Docker Hub またはその他のレジストリ** |
| イメージの種類 | **パブリック** |
| レジストリ ログイン サーバー | `mcr.microsoft.com` |
| イメージとタグ | `azure-api-management/gateway:2.5.0` |
| コマンドのオーバーライド | （空欄） |
| 引数のオーバーライド | （空欄） |

**開発スタック固有の機能** セクション:

| 項目 | 値 |
|---|---|
| 開発スタック | **未指定**（既定のまま） |

> :information_source: 「開発スタック」はランタイム特化のテレメトリ／自動チューニング機能を有効化するためのヒントです。SHGW のような汎用コンテナーでは **未指定** のままで問題ありません（Java/Node 等を選んでも実害はないが SHGW 向けの最適化は提供されない）。

**コンテナー リソースの割り当て** セクション:

| 項目 | 値 |
|---|---|
| ワークロード プロファイル | **Consumption - 最大 4 個の vCPU、8 Gib のメモリー**（既定のまま） |
| GPU | **オフ**（既定のまま） |
| CPU とメモリ | **0.5 CPU コア、1 Gi メモリ** |

**環境変数** セクションで **追加** を 2 回クリックし、以下を入力（**ソース** は両方とも **手動エントリ**）:

| 名前 | 値 |
|---|---|
| `config.service.endpoint` | `apim-aigw-handson-<id>.configuration.azure-api.net` |
| `config.service.auth` | `GatewayKey <Lab 5-3 でコピーした完成済みトークン>` |

> :information_source: **Container Apps Portal は env 名にドット (`.`) をそのまま受け付けます**（ACI Portal / RP の制限はありません）。`GatewayKey ` の半角スペース込みでトークンを貼り付けます。
>
> :warning: 値欄に貼り付けた後、末尾に改行や余分な空白が混入していないか確認してください（コピー時に末尾改行が付きやすい）。

入力後、**次へ: イングレス >** をクリックします。

#### (d) 「イングレス」タブ

**アプリケーションのイングレス設定** セクション:

| 項目 | 値 |
|---|---|
| イングレス | **オン**（チェックを入れる） |
| イングレス トラフィック | **どこからでもトラフィックを受け入れます** |
| イングレス タイプ | **HTTP** |
| 転送 | **自動**（既定のまま） |
| セキュリティで保護されていない接続 | **オフ**（既定のまま） |
| ターゲット ポート | **8080** |
| セッション アフィニティ | **オフ**（既定のまま） |
| 追加の TCP ポート | （展開しない／変更不要） |

> :information_source: Container Apps の Ingress は **外向きに HTTPS 443 / Azure 発行の信頼済み証明書** を提供し、内部で HTTP `8080` にフォワードします。SHGW がもう一方で公開する自己署名 HTTPS 8081 を直接外部公開する必要はありません（自己署名証明書の検証回避のための `-k` も不要）。

入力後、**次へ: タグ >** をクリックし、タグ タブはそのまま **次へ: 確認と作成 >** で進めます（タグは任意のため空でも可）。

#### (e) 「確認および作成」

1. **確認および作成** → **作成**
2. デプロイ完了後、リソースの **概要** ページで **アプリケーション URL** をコピー
   - 例: `https://ca-shgw-userxx.xxxxxxxx-xxxxxxxx.eastus.azurecontainerapps.io`
   - これが SHGW のパブリック エンドポイントです

## 5-5. 起動ログを確認

Portal → コンテナー アプリ → `ca-shgw-<id>` → 左メニュー **監視 > ログ ストリーム** を開きます。

画面上部のフィルタを以下に設定:

| 項目 | 値 |
|---|---|
| 表示 | **Real-time** |
| カテゴリ | **アプリケーション** |
| 基になるリビジョン | （既定の最新リビジョンのまま） |
| レプリカ | （既定のまま） |
| コンテナー | `shgw-<id>` |

下部のログ ペインに、起動直後から以下のような JSON 構造ログが流れれば成功です（時刻と GUID は環境によって異なります）:

```
Connecting to the container 'shgw-<id>'...
Successfully Connected to container: 'shgw-<id>' [Revision: 'ca-shgw-<id>--xxxxxxx', Replica: 'ca-shgw-<id>--xxxxxxx-xxxxxxxxxx-xxxxx']
[Info] [OperationRouteTableRebuildStarted], message: echo-api:Rev=1, source: ApiRouter
[Info] [OperationRouteTableRebuildCompleted], message: echo-api:Rev=1, source: ApiRouter
[Info] [OperationRouteTableRebuildStarted], message: bedrock-api:Rev=1, source: ApiRouter
[Info] [OperationRouteTableRebuildCompleted], message: bedrock-api:Rev=1, source: ApiRouter
[Info] [MsalAppClientCreated], message: MSAL app client created for client ID ...
[Info] [ManagedIdentityAddedToMap], message: systemAssigned, source: ManagedIdentityResolver
[Info] [EventSnapshotRestored], message: revision: 00000xxx, serviceName: apim-aigw-handson-<id>, gatewayId: ..., source: ConfigurationRepositoryProvider
[Info] [EventsSuccessfullyRestored], source: ConfigurationRepositoryProvider
[Info] [ConfigInitialSyncCompleted], source: ConfigurationRepositoryProvider
[Info] [BootstrapperStarted], source: Bootstrapper
[Info] [TenantStarted], message: Tenant lifecycle id: ... in 00:00:11.xxxxxxx
```

成功の判定ポイント:

- ✅ `Successfully Connected to container: 'shgw-<id>'` — ストリーム接続成功
- ✅ `[ApiRouter]` 行に `bedrock-api:Rev=1` が出現 — APIM 側でバインドした API 定義がダウンロード済み
- ✅ `[ConfigInitialSyncCompleted]` — APIM コントロールプレーンからの初期構成同期完了
- ✅ `[TenantStarted]` — SHGW テナント起動完了

> :information_source: 起動シーケンスの最後に `[TenantRecycled]` が **1 回だけ** 出るのは正常です。SHGW は最初に空構成のブートストラップ テナントで起動し、APIM から構成を取得した後で本番テナント (`[TenantStarted]`) に切り替えるため、その際にブートストラップ テナントが破棄されてこのイベントが記録されます。`TenantStarted` / `TenantRecycled` が **延々と繰り返す** 場合は構成スナップショットが安定していない（同一 gateway-id に複数 SHGW が接続している等の）異常状態です。

> :information_source: 表示が **履歴** のままだと過去ログのみで止まり追従しません。**Real-time** に切り替えてください。
>
> :information_source: ログ ストリームに何も表示されない場合、左メニュー **アプリケーション > リビジョン管理** に移動し、`プロビジョニング状態` が `プロビジョニング済み` で `実行状態` が `実行中` であることを確認してください。`プロビジョニング失敗` の場合はその行をクリックして詳細を確認します（多くは env 値の typo か image pull 失敗）。

## 5-6. APIM Portal でゲートウェイ状態を確認

APIM Portal → **デプロイとインフラストラクチャ > セルフホステッド ゲートウェイ** の一覧から **`gw-ext-tokyo-<id>`** をクリックして概要ページを開きます。

**基本** セクションで以下を確認します:

| 項目 | 期待値 |
|---|---|
| 名前 | `gw-ext-tokyo-<id>` |
| 場所 | `aws-ap-northeast-1` |
| 構成 URL | `apim-aigw-handson-<id>.configuration.azure-api.net` |
| 状態 | ✅ **`1 個のインスタンス、最後のハートビートは X:XX:XX です`** |

> :information_source: 状態欄に緑のチェックアイコンと「**X 個のインスタンス、最後のハートビートは …**」が表示されれば、Container App 上の SHGW が APIM コントロールプレーンと正常に通信しています。ハートビートは数十秒ごとに更新されます。

状態欄がグレーのアイコンで「**接続されているインスタンスはありません**」などと表示されている場合は §5-5 のログを再確認します。

## 5-7. 接続テスト

Container App の **アプリケーション URL** に対し、APIM API を呼び出します。Container Apps Ingress が HTTPS 443 / 信頼済み証明書を提供しているため、ブラウザ／`curl` ともに証明書例外フラグは不要です。

### URL を取得

Portal → コンテナー アプリ → `ca-shgw-<id>` → **概要** ページの **アプリケーション URL** をコピー。
例: `https://ca-shgw-userxx.xxxxxxxx-xxxxxxxx.eastus.azurecontainerapps.io`

### 動作確認 (curl, PowerShell)

```pwsh
$URL = "https://ca-shgw-<id>.xxxxxxxx-xxxxxxxx.eastus.azurecontainerapps.io"
$KEY = "<Lab 3 で取得したサブスクリプションキー>"
$MODEL_ID = "us.anthropic.claude-3-5-haiku-20241022-v1:0"
$tmp = New-TemporaryFile

'{"messages":[{"role":"user","content":[{"text":"hello via external SHGW (Container Apps)"}]}],"inferenceConfig":{"maxTokens":100}}' |
  Set-Content -Path $tmp -Encoding utf8 -NoNewline

curl.exe -i -X POST "$URL/bedrock/model/$MODEL_ID/converse" `
  -H "api-key: $KEY" `
  -H "Content-Type: application/json" `
  --data-binary "@$tmp"

Remove-Item $tmp -Force
```

200 OK が返れば、**「外部ホスティング(East US の Container Apps)上の SHGW → Azure の mock Bedrock エンドポイント(japaneast)」** という経路で動作しています。Lab 4 で Azure 直の APIM 経由でも同じ API が動くため、**同一 API 定義が複数 Gateway で動作する** ことが確認できます。

## 5-8. 本番で AWS に置き換える場合の差分

| 項目 | 本ハンズオン (Azure Container Apps) | 本番 (AWS) |
|---|---|---|
| ホスティング | Azure Container Apps（共有 env `cae-apim-instructor`, Consumption） | ECS Fargate / EKS / EC2 |
| イメージ | `mcr.microsoft.com/azure-api-management/gateway:2.5.0` | **同じ** |
| 環境変数 | `config.service.endpoint` / `config.service.auth` | **同じ** |
| Gateway リソース定義 (APIM 側) | `gw-ext-tokyo-<id>` (locationData=aws-ap-northeast-1) | **同じ** |
| Ingress | Container Apps Ingress（HTTPS 443 / Azure 発行証明書） | ALB（TLS 終端） / NLB（TCP パススルー） |
| ログ | Container Apps Log Stream / Log Analytics | CloudWatch Logs / OTel Collector |
| スケール | KEDA ベースの HTTP / CPU トリガー（min=1） | ECS Service の DesiredCount / EKS HPA |

つまり **APIM 側の構成と SHGW コンテナの実体は変わらず**、ホスティング先と監視先のみ AWS に差し替える形になります。

> :information_source: **AWS でのレイヤー分離**: Fargate / EKS / EC2 はコンピュートレイヤーであり、TLS 終端は行いません。TLS 終端は常に前段のロードバランサー（ALB または NLB）が担います。ALB を使う場合は HTTPS:443 を受けて HTTP:8080 に転送（Container Apps Ingress と同じ構成）するため `bedrock-api` の URL スキームは `HTTP(S)` が必要です。NLB を TCP パススルーで使う場合は HTTPS がコンテナまで到達するため `HTTPS` のみで十分です。

## 5-9. ハンズオン終了後のクリーンアップ

共有 env `cae-apim-instructor` 自体は他の受講者と共有しているため**削除しません**。自分が作った Container App `ca-shgw-<id>` のみを削除します。

Portal → コンテナー アプリ → `ca-shgw-<id>` → **削除** → 確認文字列を入力 → **削除**

これで自分の SHGW 分の課金は完全に停止します（env 側のアイドル課金は元々ゼロ）。APIM 側の Gateway リソース `gw-ext-tokyo-<id>` も Lab 6 以降で使わない場合は同様に削除してください。

## トラブルシューティング

| 症状 | 原因 / 対処 |
|---|---|
| Gateway 作成で `MethodNotAllowedInPricingTier` | APIM SKU が StandardV2 等。Classic Developer or Premium へ変更（Lab 1 から作り直し） |
| コンテナー アプリ環境ドロップダウンに `cae-apim-instructor` が表示されない | 基本タブの **リージョン** が East US 以外。**East US** に切り替える |
| 作成時に `Microsoft.App is not registered` | サブスクリプションで `Microsoft.App` リソース プロバイダーが未登録。Portal → サブスクリプション → リソース プロバイダー → `Microsoft.App` を **登録** |
| ログに `Unauthorized` | `config.service.auth` のフォーマット誤り。`GatewayKey <token>` の半角スペース、トークン末尾の改行混入を確認 |
| ログに `Configuration endpoint not reachable` | `config.service.endpoint` のホスト名スペルミス。末尾の `/` や `https://` プレフィックスを含めていないか確認（ホスト名のみが正解） |
| Portal で「接続中」にならない | 環境変数キーが `config_service_endpoint` 等のアンダースコアになっていないか確認（**ドット必須**）。値貼り付け時に改行・前後空白が混入していないかも要チェック |
| リビジョンが `Provisioning Failed` | **リビジョン管理** → 失敗したリビジョン行をクリック → 「問題を表示」で詳細確認。多くは env typo か image pull 失敗 |
| ログ ストリームに何も出ない | リビジョンが起動失敗している。**リビジョン管理** で実行状態が `Running` か確認。`Provisioning` のまま長時間止まる場合は image タグ誤り |
| 起動から数分後に SHGW が落ちる | min replicas が 0 になっていてアイドルスケールダウンしている可能性。**スケール** タブで **最小レプリカ数: 1** を確認 |

## チェックリスト

- [ ] Gateway リソース `gw-ext-tokyo-<id>` が APIM に作成済み
- [ ] `bedrock-api` が Gateway にバインド済み
- [ ] `bedrock-api` の URL スキームを `HTTP(S)` に変更済み
- [ ] Gateway トークンを生成し、`GatewayKey <token>` の形式で控えた
- [ ] Container App `ca-shgw-<id>` を既存環境 `cae-apim-instructor` (East US) にデプロイし、Ingress ターゲット ポート 8080 を公開
- [ ] リビジョンが 実行中、ログ ストリームに `[ConfigInitialSyncCompleted]` と `[TenantStarted]`、`[ApiRouter]` の `bedrock-api:Rev=1` が出ている
- [ ] APIM Portal の `gw-ext-tokyo-<id>` が「接続中」
- [ ] 外部 SHGW (Container Apps アプリケーション URL) 経由で `/bedrock/model/.../converse` が `api-key` ヘッダー付きで 200 を返す
- [ ] 同じリクエストを Azure 直の APIM URL でも実行し、両方とも成功することを確認

完了したら [Lab 6 — OpenTelemetry によるモニタリング / トレーシング](./lab6.md) へ。
