$ErrorActionPreference = "Stop"
$APIM_NAME = "apim-aigw-userxx"
$RG = "rg-aigw-handson-userxx"
$SUB = "9353f1a1-94a4-4e4b-ae82-c27ea3d07160"

$token = az account get-access-token --resource https://management.azure.com --query accessToken -o tsv

# trace token (Apim-Debug-Authorization) を発行
$traceTokenUri = "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM_NAME/gateways/managed/listDebugCredentials?api-version=2022-08-01"
$traceBody = @{
  credentialsExpireAfter = "PT1H"
  apiId                  = "/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM_NAME/apis/bedrock-api"
  purposes               = @("tracing")
} | ConvertTo-Json
$traceTokenResp = Invoke-RestMethod -Uri $traceTokenUri -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } -Method Post -Body $traceBody
$debugAuth = $traceTokenResp.token
Write-Host "Trace token acquired."

$KEY = az rest --method post --uri "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM_NAME/subscriptions/sub-aigw-handson/listSecrets?api-version=2022-08-01" --query "primaryKey" -o tsv
$APIM = "https://$APIM_NAME.azure-api.net"
$MODEL_ID = "us.anthropic.claude-3-5-haiku-20241022-v1:0"

$tmp = New-TemporaryFile
'{"messages":[{"role":"user","content":[{"text":"hello"}]}],"inferenceConfig":{"maxTokens":64}}' | Set-Content -Path $tmp -Encoding utf8 -NoNewline

# 呼び出し（-D でヘッダー保存、-o で body 保存）
$headersFile = "trace-headers.txt"
$bodyFile = "trace-body.txt"
curl.exe -s -D $headersFile -o $bodyFile -X POST "$APIM/bedrock/model/$MODEL_ID/converse" `
  -H "api-key: $KEY" `
  -H "Content-Type: application/json" `
  -H "Apim-Debug-Authorization: $debugAuth" `
  --data-binary "@$tmp"

Write-Host "`n===== Response headers ====="
Get-Content $headersFile
Write-Host "`n===== Response body ====="
Get-Content $bodyFile

# trace location ヘッダーを取得
$traceLoc = (Get-Content $headersFile | Where-Object { $_ -match '^Apim-Trace-Location:' }) -replace '^Apim-Trace-Location:\s*', ''
$traceLoc = $traceLoc.Trim()
Write-Host "`nTrace location: $traceLoc"

if ($traceLoc) {
  $trace = Invoke-RestMethod -Uri $traceLoc
  $trace | ConvertTo-Json -Depth 20 | Set-Content -Path "trace.json" -Encoding utf8
  Write-Host "Trace saved to trace.json"

  # 例外が起きたポリシーを抽出
  Write-Host "`n===== Inbound trace records ====="
  $trace.traceEntries.inbound | ForEach-Object {
    "$($_.source) | $($_.elapsed) | $($_.data | ConvertTo-Json -Compress -Depth 5)"
  }
  Write-Host "`n===== on-error trace records ====="
  $trace.traceEntries.'on-error' | ForEach-Object {
    "$($_.source) | $($_.data | ConvertTo-Json -Compress -Depth 5)"
  }
}

Remove-Item $tmp -Force
