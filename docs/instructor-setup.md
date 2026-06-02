# 講師用 事前準備ガイド — mock API 共有エンドポイントの構築

このドキュメントは **AI Gateway 複数ベンダー ハンズオン** で参加者全員が共有する **AWS Bedrock Runtime 互換の mock API**（Anthropic Claude）を、講師が **事前に 1 セットだけ** デプロイするための手順です。

- 参加者向け本編は [docs/labs/lab2.md](./docs/labs/lab2.md)（参加者は `<mock_BASE_URL>` への疎通確認のみ）
- 講師は本ガイドの手順で 1 つの Container App を立てて、その Base URL を参加者に配布する

---

## 1. 全体方針

| 項目 | 方針 |
|---|---|
| **mock 実体** | 1 つの Python ASGI アプリ（FastAPI）で AWS Bedrock Runtime 互換の 2 エンドポイント（Converse / InvokeModel）を同居実装 |
| **ホスティング** | **Azure Container Apps**（Free Trial 含む全サブスクリプションで動作、0 スケーリング可、リクエスト課金） |
| **参加者共有** | 全員が同じ Base URL を叩く。APIM 側で参加者ごとの認証/メトリクス分離 |
| **コスト** | 0 スケーリング設定でアイドル時は完全無課金。ハンズオン中のみ起動 |
| **再現性** | Bicep / az CLI スクリプトを `infra-instructor/` に配置（任意） |

### アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│  ca-mock-shared (Container App, 1 replica, 0-scaling)     │
│                                                             │
│  FastAPI (Python 3.13) — AWS Bedrock Runtime mock         │
│   ├─ POST /model/{modelId}/converse  (Bedrock Converse)     │
│   └─ POST /model/{modelId}/invoke    (Bedrock InvokeModel,  │
│                                       Anthropic native body)│
│                                                             │
│   - 入力をエコーして固定文字列+入力で返す                    │
│   - usage にダミートークン数                              │
│   - 200ms sleep でレイテンシ計測に意味を持たせる            │
│   - AWS SigV4 署名は検証しない（APIM が付けるだけ）          │
│   - 認証なし（APIM 側で担う）                                │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 事前要件

| 項目 | 内容 |
|---|---|
| サブスクリプション | 有償 or Free Trial（どちらでも可） |
| ロール | サブスクリプション **共同作成者** 以上 |
| ローカル環境 | Azure CLI（2.60+）, **Docker Desktop（ACR Tasks が禁止されているサブスクリプション向け）** |
| リージョン | `Japan East` 推奨（参加者から近い方が低レイテンシ。Free Trial で在庫不足なら `East US`） |

> **⚠️ ACR Tasks 制限について**: 一部の Free Trial / Pass-through サブスクリプションでは `az acr build`（ACR Tasks）が `TasksOperationsNotAllowed` で拒否されます。その場合は **手順 4.3 でローカル Docker ビルド → `docker push`** に切り替えてください（本ガイドの 4.3 でも記載）。

### 2.1 変数一覧

> 以下の変数は `scripts/set-env-instructor.ps1` で設定します。`[1] 講師が書き換える値` の欄を各自の環境に合わせて編集してから `. .\scripts\set-env-instructor.ps1` を実行してください。

| 変数名 | 既定値 | 説明 |
|---|---|---|
| `$SUBSCRIPTION` | *(要設定)* | `az account show --query id -o tsv` で取得 |
| `$RG` | `rg-apim-instructor` | リソースグループ名 |
| `$LOCATION` | `eastus` | デプロイリージョン（`japaneast` でも可） |
| `$ACR_NAME` | *(要設定)* | Container Registry 名（グローバル一意） |
| `$ENV_NAME` | `cae-apim-instructor` | Container Apps 環境名 |
| `$APP_NAME` | `ca-mock-shared` | Container App 名 |
| `$LOG_NAME` | `log-mock-shared` | Log Analytics ワークスペース名 |
| `$IMAGE` | `mock:1.0.0` | イメージタグ |
| `$mock_BASE_URL` | *(手順 4.5 で取得)* | 参加者へ配布する Base URL |
| `$INSTRUCTOR_UPN` | *(要設定)* | 講師アカウントの UPN（例: `apim-instructor@contoso.onmicrosoft.com`） |
| `$INSTRUCTOR_DISPLAY` | `APIM Instructor` | 表示名 |
| `$INSTRUCTOR_PASS` | *(要設定)* | 初期パスワード（初回サインイン時に変更必須） |

---

### 2.2 リソースプロバイダーの事前登録（必須）

**リソースプロバイダー**とは、Azure サービスを提供する名前空間です。`Microsoft.KeyVault` なら Key Vault、`Microsoft.CognitiveServices` なら Azure AI サービス（Foundry 含む）が対応します。リソースを作成する前にそのプロバイダーがサブスクリプションで「登録済み」になっている必要があり、未登録のままリソースを作成しようとすると `AuthorizationFailed` が返ります。

> **実行アカウント**: テナント管理者アカウント（グローバル管理者 / サブスクリプション Owner）で実行してください。`apim-instructor` アカウントには Contributor のみのため拒否されます。

```powershell
# テナント管理者アカウントでサインイン
az login --allow-no-subscriptions

$providers = @(
    "Microsoft.ApiManagement",
    "Microsoft.CognitiveServices",
    "Microsoft.Insights",
    "Microsoft.KeyVault",
    "Microsoft.MachineLearningServices",
    "Microsoft.OperationalInsights",
    "Microsoft.OperationsManagement",
    "Microsoft.Search",
    "Microsoft.Storage",
    "Microsoft.ContainerRegistry",
    "Microsoft.App"
)

foreach ($p in $providers) {
    az provider register --namespace $p --wait
    Write-Host "Registered: $p"
}
```

登録状態の確認:

```powershell
foreach ($p in $providers) {
    $state = az provider show --namespace $p --query registrationState -o tsv
    Write-Host "$p : $state"
}
```

> :information_source: 登録は**サブスクリプション全体に対して一度だけ**行えば OK です。参加者全員分を個別に実行する必要はありません。登録完了まで数分かかる場合があります。

---

### 2.3 講師アカウントの作成と RBAC 付与

> **テナント管理者が実行します。** ハンズオン専用の講師アカウントを作成し、必要な権限を付与します。既存アカウントを流用する場合はスキップしてください。

```powershell
# ---- 0. テナント管理者でサインイン ----
az login --allow-no-subscriptions   # テナント管理者アカウントでブラウザ認証

# 変数を読み込む（set-env-instructor.ps1 の [0] を編集済みであること）
. .\scripts\set-env-instructor.ps1

# ---- 1. 講師ユーザーを作成 ----
az ad user create `
  --display-name $INSTRUCTOR_DISPLAY `
  --user-principal-name $INSTRUCTOR_UPN `
  --password $INSTRUCTOR_PASS `
  --force-change-password-next-sign-in true

# ---- 2. Object ID を取得 ----
$INSTRUCTOR_OID = az ad user show --id $INSTRUCTOR_UPN --query id -o tsv
Write-Host "Instructor OID: $INSTRUCTOR_OID"

# ---- 3. Contributor ロールをサブスクリプションスコープで付与 ----
az role assignment create `
  --assignee-object-id $INSTRUCTOR_OID `
  --assignee-principal-type User `
  --role "Contributor" `
  --scope "/subscriptions/$SUBSCRIPTION"

# ---- 4. User Access Administrator をサブスクリプションスコープで付与 ----
# 参加者が自分の APIM で Foundry API を設定できるよう、セクション 2.4 で
# 参加者 ID に User Access Administrator（roleAssignments/write）を付与するために必要
az role assignment create `
  --assignee-object-id $INSTRUCTOR_OID `
  --assignee-principal-type User `
  --role "User Access Administrator" `
  --scope "/subscriptions/$SUBSCRIPTION"

Write-Host "=== 完了 ===" -ForegroundColor Green
Write-Host "UPN      : $INSTRUCTOR_UPN"
Write-Host "Password : $INSTRUCTOR_PASS  ← メモしておくこと"
Write-Host "初回サインイン: https://portal.azure.com"
```

> **📝 MFA について**: テナントの条件付きアクセスポリシーで MFA が必須になっている場合、初回サインイン後に Microsoft Authenticator などの追加認証方法のセットアップが求められます。環境に合わせて事前にセットアップ方法を案内するか、[https://aka.ms/mfasetup](https://aka.ms/mfasetup) への誘導を追加してください。

**付与するロール:**

| ロール | スコープ | 目的 |
|---|---|---|
| `Contributor` | サブスクリプション | RG / ACR / Log Analytics / Container Apps の作成・管理 |
| `User Access Administrator` | サブスクリプション | 参加者アカウントへのロール割り当て（セクション 2.4）を講師アカウントで実行するために必要 |

> **⚠️ セキュリティ注意**: `$INSTRUCTOR_PASS` は `set-env-instructor.ps1`（`.gitignore` 対象）にのみ記載し、リポジトリにコミットしないでください。ハンズオン終了後は `az ad user delete --id $INSTRUCTOR_UPN` でアカウントを削除してください。

---

### 2.4 参加者アカウントの作成と RG 付与

> **テナント管理者が実行します。** セクション 2.3 に続いてテナント管理者のまま実行してください。講師アカウント（`apim-instructor`）に切り替えた後で実行すると「Insufficient privileges」エラーになります。現在のサインイン状態は `az ad signed-in-user show --query userPrincipalName -o tsv` で確認できます。

参加者 ID は `user01`、`user02`、… の形式で統一します。

```powershell
# ---- 参加者 ID を設定（1 人ずつ変えて繰り返す）----
$PID_       = "user01"   # user02, user03 ... と繰り返す
$P_UPN      = "$PID_@M365CPI65139919.onmicrosoft.com"
$P_PASS     = "Password01!"   # MFA 必須環境のため固定パスワードで可
$P_RG       = "rg-aigw-handson-$PID_"

# ---- 1. Entra ユーザー作成 ----
az ad user create `
  --display-name $PID_ `
  --user-principal-name $P_UPN `
  --password $P_PASS

# ---- 2. Object ID 取得 ----
$P_OID = az ad user show --id $P_UPN --query id -o tsv
Write-Host "OID: $P_OID"

# ---- 3. 参加者 RG 作成 ----
az group create --name $P_RG --location $LOCATION

# ---- 4. 参加者 RG への Contributor 付与 ----
az role assignment create `
  --assignee-object-id $P_OID `
  --assignee-principal-type User `
  --role "Contributor" `
  --scope "/subscriptions/$SUBSCRIPTION/resourceGroups/$P_RG"

# ---- 5. 講師 RG（mock API）への Contributor 付与 ----
# Lab 5 で参加者が共有 env `cae-apim-instructor` を使って Container App を作成する際、
# Portal の ARM デプロイが rg-apim-instructor スコープで
# Microsoft.Resources/deployments/validate/action と
# Microsoft.App/managedEnvironments/join/action を要求するため Contributor が必要。
# ※ 参加者が講師リソース（APIM 本体・mock API）を誤って削除しないよう、
#   ハンズオン前に口頭で注意すること。
az role assignment create `
  --assignee-object-id $P_OID `
  --assignee-principal-type User `
  --role "Contributor" `
  --scope "/subscriptions/$SUBSCRIPTION/resourceGroups/$RG"

# ---- 6. Foundry データプレーンアクセス（Playground / Agent Service 利用に必要）----
# Portal UI では「Azure AI User」と表示されるが、実際の RBAC ロール名は「Cognitive Services User」
az role assignment create `
  --assignee-object-id $P_OID `
  --assignee-principal-type User `
  --role "Cognitive Services User" `
  --scope "/subscriptions/$SUBSCRIPTION/resourceGroups/$P_RG"

# ---- 7. APIM から Foundry API を作成するときに必要なロール割り当て権限 ----
# APIM の「Microsoft Foundry」API 追加ウィザードが内部で APIM マネージド ID への
# ロール割り当てを実行するため、参加者に roleAssignments/write が必要
az role assignment create `
  --assignee-object-id $P_OID `
  --assignee-principal-type User `
  --role "User Access Administrator" `
  --scope "/subscriptions/$SUBSCRIPTION/resourceGroups/$P_RG"

Write-Host "=== 完了: $PID_ ===" -ForegroundColor Green
Write-Host "UPN      : $P_UPN"
Write-Host "Password : $P_PASS  ← 参加者に伝える"
Write-Host "RG       : $P_RG"
```

**付与するロール（参加者）:**

| ロール | スコープ | 目的 |
|---|---|---|
| `Contributor` | `rg-aigw-handson-<id>` | APIM・App Insights 等の作成・管理 |
| `Contributor` | `rg-apim-instructor`（講師 RG） | mock API エンドポイントの参照 + Lab 5: Portal が ARM デプロイ検証（`deployments/validate/action`）と env への `join/action` を RG スコープで要求するため |
| `Cognitive Services User` | `rg-aigw-handson-<id>` | Foundry Playground・Agent Service のデータプレーンアクセス（Portal UI 表示名「Azure AI User」） |
| `User Access Administrator` | `rg-aigw-handson-<id>` | APIM の「Microsoft Foundry」API 作成時に APIM マネージド ID へのロール割り当て（`roleAssignments/write`）が必要 |

> **📋 初回ログイン時の MFA 登録について（環境によっては必須）**  
> テナントで条件付きアクセスが有効になっている場合、参加者は初回サインイン時に MFA 登録フロー（Microsoft Authenticator 等）が求められます。  
> ハンズオン当日に時間を取られないよう、**事前に参加者へ初回ログインと MFA 登録を済ませるよう案内してください。**  
> MFA 登録 URL: `https://aka.ms/mfasetup`

#### MFA 登録を省略したい場合：一時アクセスパス (TAP) の利用

MFA デバイスを持参できない参加者がいる場合や、当日の時間を節約したい場合は **一時アクセスパス (Temporary Access Pass / TAP)** を使うと、パスワード + MFA の代わりに時限付きパスコード 1 つでサインインできます。

**TAP を発行できる Entra ロール:**

| ロール | 備考 |
|---|---|
| グローバル管理者 | すべてのユーザーに発行可 |
| 特権認証管理者 | すべてのユーザーに発行可 |
| 認証管理者 | 管理者以外のユーザーに発行可 |

> テナント管理者（グローバル管理者）であれば追加作業なしに発行できます。

**前提：TAP ポリシーを有効化（テナント全体・初回のみ）**

Entra ID ポータルで有効化するか、以下の CLI で実行します。

```
Entra ID → 保護 → 認証方法 → 一時アクセスパス → 有効にする → すべてのユーザー → 保存
```

または CLI:

```powershell
az rest --method PUT `
  --uri "https://graph.microsoft.com/v1.0/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/temporaryAccessPass" `
  --body '{
    "@odata.type": "#microsoft.graph.temporaryAccessPassAuthenticationMethodConfiguration",
    "state": "enabled",
    "defaultLifetimeInMinutes": 480,
    "defaultLength": 8,
    "minimumLifetimeInMinutes": 60,
    "maximumLifetimeInMinutes": 480,
    "isUsableOnce": false,
    "includeTargets": [{"targetType": "group", "id": "all_users", "isRegistrationRequired": false}]
  }'
```

**参加者ごとに TAP を発行:**

```powershell
$P_UPN = "user01@M365CPI65139919.onmicrosoft.com"
$P_OID = az ad user show --id $P_UPN --query id -o tsv

$tap = az rest --method POST `
  --uri "https://graph.microsoft.com/v1.0/users/$P_OID/authentication/temporaryAccessPassMethods" `
  --body '{"lifetimeInMinutes": 480, "isUsableOnce": false}' | ConvertFrom-Json

Write-Host "TAP : $($tap.temporaryAccessPass)  (有効期限: 8時間)"
```

**受講者のサインイン手順（TAP 利用時）:**
1. `https://portal.azure.com` を開く
2. UPN（`user01@...`）を入力
3. パスワードの代わりに TAP コードを入力 → MFA 登録なしでサインイン完了

> **⚠️ セキュリティ注意**: 参加者パスワードはチャット等で平文送信しないでください。ハンズオン終了後は `az ad user delete --id $P_UPN` と `az group delete --name $P_RG --yes` で参加者リソースを削除してください。

---

## 3. mock 実装コード

リポジトリの `mock/` 配下に以下を配置します。

### 3.1 ディレクトリ構成

```
mock/
├── Dockerfile
├── requirements.txt
└── app/
    └── main.py
```

### 3.2 `mock/requirements.txt`

```text
fastapi==0.115.4
uvicorn[standard]==0.32.0
```

### 3.3 `mock/app/main.py`

```python
"""AWS Bedrock Runtime mock for Anthropic Claude models.

Implements two Bedrock Runtime endpoints used by the Microsoft Learn
"Amazon Bedrock passthrough LLM API" flow:

- POST /model/{modelId}/converse    — Bedrock Converse API (unified contract)
- POST /model/{modelId}/invoke      — Bedrock InvokeModel API (Anthropic native body)

The mock ignores AWS SigV4 (the `Authorization` / `X-Amz-*` headers signed by
APIM are accepted but **not verified**), so the Microsoft Learn flow works end
to end without real AWS credentials. APIM signs the request, this service just
responds with a Bedrock-shaped echo response.

References:
- https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html
- https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_InvokeModel.html
- https://learn.microsoft.com/azure/api-management/amazon-bedrock-passthrough-llm-api
"""

from __future__ import annotations

import asyncio
import uuid
from typing import Any
from urllib.parse import unquote

from fastapi import FastAPI, Request

app = FastAPI(title="AI Gateway mock (AWS Bedrock — Anthropic Claude)", version="2.0.0")

mock_SLEEP_SEC = 0.2


def _echo_text(user_text: str) -> str:
    return f"Echo: {user_text}"


def _approx_tokens(text: str) -> int:
    return max(1, len(text) // 4)


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}


def _extract_text_from_converse_messages(messages: list[dict[str, Any]]) -> str:
    for m in reversed(messages or []):
        if (m or {}).get("role") != "user":
            continue
        for part in (m.get("content") or []):
            text = (part or {}).get("text")
            if isinstance(text, str) and text:
                return text
    return ""


def _extract_text_from_anthropic_messages(messages: list[dict[str, Any]]) -> str:
    for m in reversed(messages or []):
        if (m or {}).get("role") != "user":
            continue
        content = m.get("content")
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            for part in content:
                if (part or {}).get("type") == "text":
                    text = part.get("text")
                    if isinstance(text, str) and text:
                        return text
    return ""


@app.post("/model/{model_id:path}/converse")
async def bedrock_converse(model_id: str, request: Request) -> dict[str, Any]:
    await asyncio.sleep(mock_SLEEP_SEC)
    raw = await request.body()
    body: dict[str, Any] = await request.json() if raw else {}
    messages = body.get("messages", []) if isinstance(body, dict) else []
    user_text = _extract_text_from_converse_messages(messages)
    reply = _echo_text(user_text)
    input_tokens = _approx_tokens(user_text)
    output_tokens = _approx_tokens(reply)
    return {
        "output": {"message": {"role": "assistant", "content": [{"text": reply}]}},
        "stopReason": "end_turn",
        "usage": {
            "inputTokens": input_tokens,
            "outputTokens": output_tokens,
            "totalTokens": input_tokens + output_tokens,
        },
        "metrics": {"latencyMs": int(mock_SLEEP_SEC * 1000)},
    }


@app.post("/model/{model_id:path}/invoke")
async def bedrock_invoke(model_id: str, request: Request) -> dict[str, Any]:
    await asyncio.sleep(mock_SLEEP_SEC)
    raw = await request.body()
    body: dict[str, Any] = await request.json() if raw else {}
    messages = body.get("messages", []) if isinstance(body, dict) else []
    user_text = _extract_text_from_anthropic_messages(messages)
    reply = _echo_text(user_text)
    input_tokens = _approx_tokens(user_text)
    output_tokens = _approx_tokens(reply)
    return {
        "id": f"msg_mock_{uuid.uuid4().hex[:12]}",
        "type": "message",
        "role": "assistant",
        "model": unquote(model_id),
        "content": [{"type": "text", "text": reply}],
        "stop_reason": "end_turn",
        "stop_sequence": None,
        "usage": {"input_tokens": input_tokens, "output_tokens": output_tokens},
    }
```

### 3.4 `mock/Dockerfile`

```dockerfile
FROM python:3.13-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

---

## 4. デプロイ手順

### 4.1 リソース変数の設定（PowerShell）

`scripts/set-env-instructor.ps1` の `[1] 講師が書き換える値` を編集してから、以下を実行します。

```powershell
# ---- 0. 講師アカウントに切り替え ----
# セクション 2.2 でテナント管理者としてサインインしている場合は必ず切り替える
az logout
az login   # ブラウザで $INSTRUCTOR_UPN（講師アカウント）としてサインイン

# 講師用変数を読み込む（事前に set-env-instructor.ps1 の値を書き換えること）
. .\scripts\set-env-instructor.ps1

# サブスクリプション設定 & 確認
az account set --subscription $SUBSCRIPTION
az account show --query "{name:name, id:id, state:state}" -o table
```

### 4.2 リソースグループと Log Analytics 作成

> 既に Container Apps 環境を別の方法で作成済みの場合（手順 4.4 の「環境が既に存在する場合」を参照）はこの手順はスキップ可能。

```powershell
az group create --name $RG --location $LOCATION

az monitor log-analytics workspace create `
  --resource-group $RG `
  --workspace-name $LOG_NAME `
  --location $LOCATION

$LOG_ID  = az monitor log-analytics workspace show -g $RG -n $LOG_NAME --query customerId -o tsv
$LOG_KEY = az monitor log-analytics workspace get-shared-keys -g $RG -n $LOG_NAME --query primarySharedKey -o tsv
```

### 4.3 Azure Container Registry 作成 & イメージビルド

```powershell
# 既存 ACR を使う場合はスキップ
az acr create --resource-group $RG --name $ACR_NAME --sku Basic --admin-enabled true
```

#### 4.3.A 方式 A: ACR Tasks でサーバーサイドビルド（推奨。Docker 不要）

```powershell
az acr build --registry $ACR_NAME --image $IMAGE ./mock
```

> **❌ `TasksOperationsNotAllowed` が返る場合**は方式 B に切り替えてください。Free Trial や Pass-through サブスクリプションでは ACR Tasks が無効化されていることがあります。

#### 4.3.B 方式 B: ローカル Docker でビルド & Push（本ガイドの実デプロイで使用）

```powershell
# Docker Desktop を起動しておくこと
az acr login --name $ACR_NAME

$ACR_SERVER = az acr show -n $ACR_NAME --query loginServer -o tsv
docker build -t "$ACR_SERVER/$IMAGE" ./mock
docker push "$ACR_SERVER/$IMAGE"
```

### 4.4 Container Apps 環境 & アプリ作成

```powershell
# Container Apps 拡張のインストール（初回のみ）
az extension add --name containerapp --upgrade
```

**Step A — Container Apps 環境の作成（既に存在する場合はスキップ）**

```powershell
az containerapp env create `
  --name $ENV_NAME `
  --resource-group $RG `
  --location $LOCATION `
  --logs-workspace-id $LOG_ID `
  --logs-workspace-key $LOG_KEY
```

**Step B — Container App 本体の作成（アプリが存在しない場合のみ。更新は `az containerapp update` を使用）**

```powershell
$ACR_SERVER   = az acr show -n $ACR_NAME --query loginServer -o tsv
$ACR_USERNAME = az acr credential show -n $ACR_NAME --query username -o tsv
$ACR_PASSWORD = az acr credential show -n $ACR_NAME --query "passwords[0].value" -o tsv

az containerapp create `
  --name $APP_NAME `
  --resource-group $RG `
  --environment $ENV_NAME `
  --image "$ACR_SERVER/$IMAGE" `
  --target-port 8000 `
  --ingress external `
  --min-replicas 0 `
  --max-replicas 3 `
  --cpu 0.5 --memory 1Gi `
  --registry-server $ACR_SERVER `
  --registry-username $ACR_USERNAME `
  --registry-password $ACR_PASSWORD
```

### 4.5 Base URL 取得

```powershell
$mock_BASE_URL = "https://$(az containerapp show -g $RG -n $APP_NAME --query properties.configuration.ingress.fqdn -o tsv)"
Write-Host "===== 参加者へ配布する値 ====="
Write-Host "mock_BASE_URL: $mock_BASE_URL"
```

実行例:

```text
mock_BASE_URL: https://<app-name>.<unique-id>.<location>.azurecontainerapps.io
```

> **📌 配布する値はこの 1 行だけ**。参加者は `docs/labs/lab2.md` の `<mock_BASE_URL>` にこの値を代入して使用します。

---

## 5. 動作確認

> **PowerShell の JSON エスケープ注意**: PowerShell 5/7 で `curl.exe -d '{"key":"value"}'` を渡すとシングル/ダブルクオートが壊れて `JSON decode error` になります。下記のように一時ファイル経由（`--data-binary "@$tmp"`) で渡すのが確実です。

### 5.1 ヘルスチェック

```powershell
curl.exe "$mock_BASE_URL/healthz"; Write-Host ""
# 期待値: {"status":"ok"}
```

### 5.2 Bedrock Converse 形式

```powershell
$MODEL_ID = "us.anthropic.claude-3-5-haiku-20241022-v1:0"
$tmp = New-TemporaryFile
'{"messages":[{"role":"user","content":[{"text":"hello"}]}],"inferenceConfig":{"maxTokens":256}}' |
  Set-Content -Path $tmp -Encoding utf8 -NoNewline
curl.exe -s -X POST "$mock_BASE_URL/model/$MODEL_ID/converse" `
  -H "Content-Type: application/json" --data-binary "@$tmp" |
  ConvertFrom-Json | ConvertTo-Json -Depth 10
```

期待レスポンス（抜粋）:
```json
{
  "output": {
    "message": {
      "role": "assistant",
      "content": [
        {
          "text": "[AWS Bedrock mock API] Echo response: hello"
        }
      ]
    }
  },
  "stopReason": "end_turn",
  "usage": {
    "inputTokens": 1,
    "outputTokens": 10,
    "totalTokens": 11
  },
  "metrics": {
    "latencyMs": 200
  }
}
```

### 5.3 Bedrock InvokeModel 形式（Anthropic ネイティブ body）

```powershell
'{"anthropic_version":"bedrock-2023-05-31","max_tokens":256,"messages":[{"role":"user","content":[{"type":"text","text":"hello"}]}]}' |
  Set-Content -Path $tmp -Encoding utf8 -NoNewline
curl.exe -s -X POST "$mock_BASE_URL/model/$MODEL_ID/invoke" `
  -H "Content-Type: application/json" --data-binary "@$tmp" |
  ConvertFrom-Json | ConvertTo-Json -Depth 10
Remove-Item $tmp -Force
```

期待レスポンス（抜粋）:
```json
{
  "id": "msg_mock_6173adb4f62c",
  "type": "message",
  "role": "assistant",
  "model": "us.anthropic.claude-3-5-haiku-20241022-v1:0",
  "content": [
    {
      "type": "text",
      "text": "[AWS Bedrock mock API] Echo response: hello"
    }
  ],
  "stop_reason": "end_turn",
  "stop_sequence": null,
  "usage": {
    "input_tokens": 1,
    "output_tokens": 10
  }
}
```

---

## 6. 運用 Tips

### 6.1 0 スケーリングによる無課金停止

`--min-replicas 0` で設定済み。アイドル時間が一定（既定 5 分）続くとレプリカが 0 になり、課金は **ACR のストレージ料のみ**（数十円/月）。

ハンズオン開始前にウォームアップしたい場合:
```powershell
curl "$mock_BASE_URL/healthz"  # 1 回叩けば 5〜10 秒でレプリカが起動
```

### 6.2 イメージ更新

```powershell
# コード変更後
az acr build --registry $ACR_NAME --image "mock:1.0.1" ./mock
az containerapp update -n $APP_NAME -g $RG --image "$ACR_SERVER/mock:1.0.1"
```

### 6.3 ログ確認

```powershell
az containerapp logs show -n $APP_NAME -g $RG --tail 100 --follow
```

### 6.4 ハンズオン終了後のクリーンアップ

```powershell
az group delete --name $RG --yes --no-wait
```

---

## 7. 参加者への配布テンプレート

ハンズオン開始時、以下を参加者にチャット等で送付します。

```text
===== AI Gateway ハンズオン 共通配布値 =====

mock_BASE_URL = <手順 4.5 で取得した $mock_BASE_URL の値>

確認コマンド (PowerShell):
  curl.exe "$mock_BASE_URL/healthz"
  → {"status":"ok"} が返れば疎通 OK

詳細は docs/labs/lab2.md を参照してください。
```

---

## 8. トラブルシューティング

| 症状 | 原因 | 対処 |
|---|---|---|
| `az acr build` が `TasksOperationsNotAllowed` で失敗 | サブスクリプションで ACR Tasks が無効化（Free Trial 等） | 手順 4.3.B のローカル Docker ビルド + `docker push` に切り替え |
| `az acr build` が遅い | 初回はベースイメージ pull で 2〜3 分かかる | 2 回目以降はキャッシュで早くなる |
| `curl -d '{...}'` で `JSON decode error` | PowerShell のクオート展開で JSON が壊れる | 5 章の `--data-binary "@$tmp"` パターンを使う |
| Gemini エンドポイントが `Internal Server Error` | リクエスト body が空 (JSON エスケープ失敗) | 同上。一時ファイル経由で投げる |
| Container App が起動しない | イメージタグ不一致 / ACR 認証情報未登録 | `az containerapp show` で `properties.template.containers[].image` と registry 認証を確認 |
| 一部参加者から 502 が返る | min-replicas=0 でスケールアップ中 | 30 秒待って再試行。または `--min-replicas 1` に変更 |
| Free Trial で在庫不足エラー | リージョン在庫枯渇 | `--location eastus` 等に切り替え |
| レスポンスが遅い（>1s） | コールドスタート | min-replicas=1 で常時 1 レプリカ稼働。月数百円 |
| `az group create` が `AADSTS130507` (access pass) で失敗 | Conditional Access / トークン期限切れ | `az login --tenant <tid> --scope https://management.core.windows.net//.default` で再ログイン |
