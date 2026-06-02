# ============================================================
#  set-env-instructor.ps1  — 講師用 環境変数セットアップ
#  使い方:
#    1. このファイルを set-env-instructor.ps1 にコピー
#    2. [1] の値を自分の環境に合わせて編集
#    3. . .\scripts\set-env-instructor.ps1 で読み込む
# ============================================================

# ============================================================
# [0] 講師 Entra アカウント（テナント管理者が Section 2.2 で作成する）
# ============================================================
$INSTRUCTOR_UPN     = "apim-instructor@<yourdomain>.onmicrosoft.com"  # 作成する UPN
$INSTRUCTOR_DISPLAY = "APIM Instructor"
$INSTRUCTOR_PASS    = "P@ssw0rdXXXX!"  # 初回サインイン時に変更必須

# ============================================================
# [1] 講師が書き換える値
# ============================================================
$SUBSCRIPTION = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # az account show --query id -o tsv
$RG           = "rg-apim-instructor"
$LOCATION     = "eastus"              # japaneast でも可
$ACR_NAME     = "apiminstructorXXXXX"  # グローバル一意。例: "apiminstructor$(Get-Random -Max 99999)"
$ENV_NAME     = "cae-apim-instructor"
$APP_NAME     = "ca-mock-shared"
$LOG_NAME     = "log-mock-shared"
$IMAGE        = "mock:1.0.0"

# ============================================================
# [2] プロセス環境変数に書き出し
# ============================================================
$env:INSTRUCTOR_UPN     = $INSTRUCTOR_UPN
$env:INSTRUCTOR_DISPLAY = $INSTRUCTOR_DISPLAY
$env:SUBSCRIPTION = $SUBSCRIPTION
$env:RG           = $RG
$env:LOCATION     = $LOCATION
$env:ACR_NAME     = $ACR_NAME
$env:ENV_NAME     = $ENV_NAME
$env:APP_NAME     = $APP_NAME
$env:LOG_NAME     = $LOG_NAME
$env:IMAGE        = $IMAGE

Write-Host "=== 講師用環境変数を設定しました ===" -ForegroundColor Cyan
Write-Host "SUBSCRIPTION : $SUBSCRIPTION"
Write-Host "RG           : $RG"
Write-Host "LOCATION     : $LOCATION"
Write-Host "ACR_NAME     : $ACR_NAME"
Write-Host "ENV_NAME     : $ENV_NAME"
Write-Host "APP_NAME     : $APP_NAME"
Write-Host "LOG_NAME     : $LOG_NAME"
Write-Host "IMAGE        : $IMAGE"
