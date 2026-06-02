# ============================================================
#  set-env.ps1  — ハンズオン共通 環境変数セットアップ
#  使い方: . .\scripts\set-env.ps1
# ============================================================

# ============================================================
# [1] 各自で書き換える値
# ============================================================
$INITIALS       = "user01"       # 割り当てられた番号に変更 (例: "user01", "user02" ...)
$SUBSCRIPTION   = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # az account show --query id -o tsv
$LOCATION       = "japaneast"   # 受講者リソースのリージョン

# mock エンドポイント (講師から配布された値を貼り付ける)
$mock_BASE_URL = "https://xxxxxxxx.xxxxxxxxxxxxxxxx.eastus.azurecontainerapps.io"

# Lab 5: SHGW トークン (APIM Portal → ゲートウェイ → デプロイ → アクセストークンをコピー後ここに貼付)
$SHGW_TOKEN     = ""

# ============================================================
# [2] 命名規約に従って自動導出 (通常変更不要)
# ============================================================
$RG             = "rg-aigw-handson-$INITIALS"
$APIM_NAME      = "apim-aigw-$INITIALS"
$APPINSIGHTS    = "appi-aigw-$INITIALS"
$LOG_ANALYTICS  = "log-aigw-$INITIALS"
$FOUNDRY_NAME   = "aif-aigw-$INITIALS"
$FOUNDRY_PROJECT= "proj-default-$INITIALS"
$CAE_SHGW       = "cae-aigw-ext-$INITIALS"
$ACA_SHGW       = "aca-shgw-$INITIALS"
$SHGW_NAME      = "gw-ext-tokyo-$INITIALS"
$MODEL_ID       = "us.anthropic.claude-3-5-haiku-20241022-v1:0"
$GPT_DEPLOYMENT = "gpt-4o-mini"
$APIM_SUB_NAME  = "sub-aigw-handson"  # APIM サブスクリプション名 (Lab 3 で作成)

# APIM エンドポイント
$APIM_HOST      = "https://$APIM_NAME.azure-api.net"
$APIM_BEDROCK_URL  = "$APIM_HOST/bedrock"
$APIM_OPENAI_URL   = "$APIM_HOST/openai"

# ============================================================
# [3] プロセス環境変数に書き出し
# ============================================================
$env:INITIALS          = $INITIALS
$env:SUBSCRIPTION      = $SUBSCRIPTION
$env:LOCATION          = $LOCATION
$env:RG                = $RG
$env:APIM_NAME         = $APIM_NAME
$env:APPINSIGHTS       = $APPINSIGHTS
$env:LOG_ANALYTICS     = $LOG_ANALYTICS
$env:FOUNDRY_NAME      = $FOUNDRY_NAME
$env:FOUNDRY_PROJECT   = $FOUNDRY_PROJECT
$env:CAE_SHGW          = $CAE_SHGW
$env:ACA_SHGW          = $ACA_SHGW
$env:SHGW_NAME         = $SHGW_NAME
$env:SHGW_TOKEN        = $SHGW_TOKEN
$env:mock_BASE_URL    = $mock_BASE_URL
$env:MODEL_ID          = $MODEL_ID
$env:GPT_DEPLOYMENT    = $GPT_DEPLOYMENT
$env:APIM_HOST         = $APIM_HOST
$env:APIM_BEDROCK_URL  = $APIM_BEDROCK_URL
$env:APIM_OPENAI_URL   = $APIM_OPENAI_URL

# ============================================================
# [4] APIM サブスクリプション キーを Azure から取得 (オプション)
#     APIM がプロビジョニング済みで az login 済みの場合のみ実行
# ============================================================
if ($INITIALS -ne "xx" -and $SUBSCRIPTION -notmatch "^xxx") {
    try {
        $key = az rest --method post `
            --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM_NAME/subscriptions/$APIM_SUB_NAME/listSecrets?api-version=2022-08-01" `
            --query "primaryKey" -o tsv 2>$null
        if ($key) {
            $env:APIM_SUBSCRIPTION_KEY = $key
            Write-Host "[OK] APIM_SUBSCRIPTION_KEY を取得しました"
        }
    } catch {
        Write-Host "[INFO] APIM_SUBSCRIPTION_KEY の取得をスキップ (APIM 未作成 or 未ログイン)"
    }
}

# ============================================================
# [5] 設定内容を確認表示
# ============================================================
Write-Host ""
Write-Host "===== 環境変数の設定状況 =====" -ForegroundColor Cyan
Write-Host "INITIALS          : $env:INITIALS"
Write-Host "SUBSCRIPTION      : $env:SUBSCRIPTION"
Write-Host "LOCATION          : $env:LOCATION"
Write-Host "RG                : $env:RG"
Write-Host "APIM_NAME         : $env:APIM_NAME"
Write-Host "APPINSIGHTS       : $env:APPINSIGHTS"
Write-Host "LOG_ANALYTICS     : $env:LOG_ANALYTICS"
Write-Host "FOUNDRY_NAME      : $env:FOUNDRY_NAME"
Write-Host "FOUNDRY_PROJECT   : $env:FOUNDRY_PROJECT"
Write-Host "CAE_SHGW          : $env:CAE_SHGW"
Write-Host "ACA_SHGW          : $env:ACA_SHGW"
Write-Host "SHGW_NAME         : $env:SHGW_NAME"
Write-Host "SHGW_TOKEN        : $(if ($env:SHGW_TOKEN) { '(set)' } else { '(未設定 — Lab 5 前に再実行)' })"
Write-Host "mock_BASE_URL    : $env:mock_BASE_URL"
Write-Host "MODEL_ID          : $env:MODEL_ID"
Write-Host "GPT_DEPLOYMENT    : $env:GPT_DEPLOYMENT"
Write-Host "APIM_HOST         : $env:APIM_HOST"
Write-Host "APIM_BEDROCK_URL  : $env:APIM_BEDROCK_URL"
Write-Host "APIM_OPENAI_URL   : $env:APIM_OPENAI_URL"
Write-Host "APIM_SUBSCRIPTION_KEY : $(if ($env:APIM_SUBSCRIPTION_KEY) { '(set)' } else { '(未設定 — Lab 3 以降で必要)' })"

if ($INITIALS -match "^user\d+$" -eq $false) {
    Write-Host ""
    Write-Host "[WARNING] INITIALS が想定外の値です。'user01' 形式で指定してください。" -ForegroundColor Yellow
}
