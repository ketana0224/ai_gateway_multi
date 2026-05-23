# 講師用 事前準備ガイド — Mimic API 共有エンドポイントの構築

このドキュメントは **AI Gateway 複数ベンダー ハンズオン** で参加者全員が共有する **AWS Bedrock Runtime 互換の mimic API**（Anthropic Claude）を、講師が **事前に 1 セットだけ** デプロイするための手順です。

- 参加者向け本編は [docs/labs/lab2.md](./docs/labs/lab2.md)（参加者は `<MIMIC_BASE_URL>` への疎通確認のみ）
- 講師は本ガイドの手順で 1 つの Container App を立てて、その Base URL を参加者に配布する

---

## 1. 全体方針

| 項目 | 方針 |
|---|---|
| **mimic 実体** | 1 つの Python ASGI アプリ（FastAPI）で AWS Bedrock Runtime 互換の 2 エンドポイント（Converse / InvokeModel）を同居実装 |
| **ホスティング** | **Azure Container Apps**（Free Trial 含む全サブスクリプションで動作、0 スケーリング可、リクエスト課金） |
| **参加者共有** | 全員が同じ Base URL を叩く。APIM 側で参加者ごとの認証/メトリクス分離 |
| **コスト** | 0 スケーリング設定でアイドル時は完全無課金。ハンズオン中のみ起動 |
| **再現性** | Bicep / az CLI スクリプトを `infra-instructor/` に配置（任意） |

### アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│  ca-mimic-shared (Container App, 1 replica, 0-scaling)     │
│                                                             │
│  FastAPI (Python 3.13) — AWS Bedrock Runtime mimic         │
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

### 2.1 本ガイドの実デプロイ例（参考値）

| 項目 | 値 |
|---|---|
| Subscription ID | `9353f1a1-94a4-4e4b-ae82-c27ea3d07160` |
| Resource Group | `rg-mcp-instructor` |
| Location | `eastus` |
| Container Registry | `mcpinstructorsvn2j` (Basic, admin enabled) |
| Container Apps Environment | `cae-mcp-instructor` |
| Container App | `ca-mimic-shared` |
| Image | `mcpinstructorsvn2j.azurecr.io/mimic:1.0.0` |
| **MIMIC_BASE_URL** | **`https://ca-mimic-shared.wonderfulpebble-9f4a40b9.eastus.azurecontainerapps.io`** |

---

## 3. mimic 実装コード

リポジトリの `mimic/` 配下に以下を配置します。

### 3.1 ディレクトリ構成

```
mimic/
├── Dockerfile
├── requirements.txt
└── app/
    └── main.py
```

### 3.2 `mimic/requirements.txt`

```text
fastapi==0.115.4
uvicorn[standard]==0.32.0
```

### 3.3 `mimic/app/main.py`

```python
"""AWS Bedrock Runtime mimic for Anthropic Claude models.

Implements two Bedrock Runtime endpoints used by the Microsoft Learn
"Amazon Bedrock passthrough LLM API" flow:

- POST /model/{modelId}/converse    — Bedrock Converse API (unified contract)
- POST /model/{modelId}/invoke      — Bedrock InvokeModel API (Anthropic native body)

The mimic ignores AWS SigV4 (the `Authorization` / `X-Amz-*` headers signed by
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

app = FastAPI(title="AI Gateway Mimic (AWS Bedrock — Anthropic Claude)", version="2.0.0")

MIMIC_SLEEP_SEC = 0.2


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
    await asyncio.sleep(MIMIC_SLEEP_SEC)
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
        "metrics": {"latencyMs": int(MIMIC_SLEEP_SEC * 1000)},
    }


@app.post("/model/{model_id:path}/invoke")
async def bedrock_invoke(model_id: str, request: Request) -> dict[str, Any]:
    await asyncio.sleep(MIMIC_SLEEP_SEC)
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

### 3.4 `mimic/Dockerfile`

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

```powershell
# 講師用変数（本ガイドの実デプロイ例）
$SUBSCRIPTION = "9353f1a1-94a4-4e4b-ae82-c27ea3d07160"
$RG       = "rg-mcp-instructor"
$LOCATION = "eastus"     # japaneast でも可
$ACR_NAME = "mcpinstructorsvn2j"   # グローバル一意。新規作成なら $(Get-Random) を付ける
$ENV_NAME = "cae-mcp-instructor"
$APP_NAME = "ca-mimic-shared"
$LOG_NAME = "log-mimic-shared"
$IMAGE    = "mimic:1.0.0"

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
az acr build --registry $ACR_NAME --image $IMAGE ./mimic
```

> **❌ `TasksOperationsNotAllowed` が返る場合**は方式 B に切り替えてください。Free Trial や Pass-through サブスクリプションでは ACR Tasks が無効化されていることがあります。

#### 4.3.B 方式 B: ローカル Docker でビルド & Push（本ガイドの実デプロイで使用）

```powershell
# Docker Desktop を起動しておくこと
az acr login --name $ACR_NAME

$ACR_SERVER = az acr show -n $ACR_NAME --query loginServer -o tsv
docker build -t "$ACR_SERVER/$IMAGE" ./mimic
docker push "$ACR_SERVER/$IMAGE"
```

### 4.4 Container Apps 環境 & アプリ作成

```powershell
# Container Apps 拡張のインストール（初回のみ）
az extension add --name containerapp --upgrade

# Container Apps 環境（従量課金プロファイル）— 既に存在する場合はスキップ
az containerapp env create `
  --name $ENV_NAME `
  --resource-group $RG `
  --location $LOCATION `
  --logs-workspace-id $LOG_ID `
  --logs-workspace-key $LOG_KEY

# Container App 本体
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

**環境が既に存在する場合**（本ガイドの実デプロイ例）: `--environment $ENV_NAME` の指定だけで既存の Container Apps 環境を再利用できます。`env create` は不要です。

### 4.5 Base URL 取得

```powershell
$MIMIC_BASE_URL = "https://$(az containerapp show -g $RG -n $APP_NAME --query properties.configuration.ingress.fqdn -o tsv)"
Write-Host "===== 参加者へ配布する値 ====="
Write-Host "MIMIC_BASE_URL: $MIMIC_BASE_URL"
```

本ガイドの実デプロイ結果:

```text
MIMIC_BASE_URL: https://ca-mimic-shared.wonderfulpebble-9f4a40b9.eastus.azurecontainerapps.io
```

> **📌 配布する値はこの 1 行だけ**。参加者は `docs/labs/lab2.md` の `<MIMIC_BASE_URL>` にこの値を代入して使用します。

---

## 5. 動作確認

> **PowerShell の JSON エスケープ注意**: PowerShell 5/7 で `curl.exe -d '{"key":"value"}'` を渡すとシングル/ダブルクオートが壊れて `JSON decode error` になります。下記のように一時ファイル経由（`--data-binary "@$tmp"`) で渡すのが確実です。

### 5.1 ヘルスチェック

```powershell
curl.exe "$MIMIC_BASE_URL/healthz"
# 期待値: {"status":"ok"}
```

### 5.2 Bedrock Converse 形式

```powershell
$MODEL_ID = "us.anthropic.claude-3-5-haiku-20241022-v1:0"
$tmp = New-TemporaryFile
'{"messages":[{"role":"user","content":[{"text":"hello"}]}],"inferenceConfig":{"maxTokens":256}}' |
  Set-Content -Path $tmp -Encoding utf8 -NoNewline
curl.exe -X POST "$MIMIC_BASE_URL/model/$MODEL_ID/converse" `
  -H "Content-Type: application/json" --data-binary "@$tmp"
```

期待レスポンス（抜粋）:
```json
{
  "output": {
    "message": {
      "role": "assistant",
      "content": [{"text": "Echo: hello"}]
    }
  },
  "stopReason": "end_turn",
  "usage": {"inputTokens": 1, "outputTokens": 2, "totalTokens": 3},
  "metrics": {"latencyMs": 200}
}
```

### 5.3 Bedrock InvokeModel 形式（Anthropic ネイティブ body）

```powershell
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
  "usage": {"input_tokens": 1, "output_tokens": 2}
}
```

---

## 6. 運用 Tips

### 6.1 0 スケーリングによる無課金停止

`--min-replicas 0` で設定済み。アイドル時間が一定（既定 5 分）続くとレプリカが 0 になり、課金は **ACR のストレージ料のみ**（数十円/月）。

ハンズオン開始前にウォームアップしたい場合:
```powershell
curl "$MIMIC_BASE_URL/healthz"  # 1 回叩けば 5〜10 秒でレプリカが起動
```

### 6.2 イメージ更新

```powershell
# コード変更後
az acr build --registry $ACR_NAME --image "mimic:1.0.1" ./mimic
az containerapp update -n $APP_NAME -g $RG --image "$ACR_SERVER/mimic:1.0.1"
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

MIMIC_BASE_URL = https://ca-mimic-shared.wonderfulpebble-9f4a40b9.eastus.azurecontainerapps.io

確認コマンド (PowerShell):
  curl.exe "$MIMIC_BASE_URL/healthz"
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
