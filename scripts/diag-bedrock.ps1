$ErrorActionPreference = "Stop"
$APIM_NAME = "apim-aigw-userxx"
$RG = "rg-aigw-handson-userxx"
$SUB = "9353f1a1-94a4-4e4b-ae82-c27ea3d07160"

$token = az account get-access-token --resource https://management.azure.com --query accessToken -o tsv
$polUri = "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM_NAME/apis/bedrock-api/policies/policy?api-version=2022-08-01&format=rawxml"

# 1) 現在のポリシーを取得
$cur = (Invoke-RestMethod -Uri $polUri -Headers @{ Authorization = "Bearer $token" }).properties.value
Write-Host "Current policy length: $($cur.Length)"

# 2) <on-error><base /></on-error> を return-response 入りに置換
$onErrorReplacement = @'
<on-error>
    <base />
    <return-response>
        <set-status code="599" reason="Policy Error" />
        <set-header name="Content-Type" exists-action="override">
            <value>application/json</value>
        </set-header>
        <set-body>@{
            return new JObject(
                new JProperty("source",  context.LastError?.Source ?? ""),
                new JProperty("reason",  context.LastError?.Reason ?? ""),
                new JProperty("message", context.LastError?.Message ?? ""),
                new JProperty("section", context.LastError?.Section ?? ""),
                new JProperty("scope",   context.LastError?.Scope ?? ""),
                new JProperty("policyId",context.LastError?.PolicyId ?? "")
            ).ToString();
        }</set-body>
    </return-response>
</on-error>
'@

# 既存の on-error ブロックを単純な regex で置換
$newPolicy = [System.Text.RegularExpressions.Regex]::Replace(
    $cur,
    '(?s)<on-error>.*?</on-error>',
    $onErrorReplacement
)
Write-Host "New policy length: $($newPolicy.Length)"

# 3) PUT
$body = @{ properties = @{ format = "rawxml"; value = $newPolicy } } | ConvertTo-Json -Depth 5
Invoke-RestMethod -Uri $polUri -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } -Method Put -Body $body | Out-Null
Write-Host "Policy with on-error diagnostics applied."

# 4) 再テスト
$KEY = az rest --method post --uri "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM_NAME/subscriptions/sub-aigw-handson/listSecrets?api-version=2022-08-01" --query "primaryKey" -o tsv
$APIM = "https://$APIM_NAME.azure-api.net"
$MODEL_ID = "us.anthropic.claude-3-5-haiku-20241022-v1:0"
$tmp = New-TemporaryFile
'{"messages":[{"role":"user","content":[{"text":"hello"}]}],"inferenceConfig":{"maxTokens":64}}' | Set-Content -Path $tmp -Encoding utf8 -NoNewline

Write-Host "`n===== Calling bedrock-api ====="
curl.exe -i -X POST "$APIM/bedrock/model/$MODEL_ID/converse" `
  -H "api-key: $KEY" `
  -H "Content-Type: application/json" `
  --data-binary "@$tmp"

Remove-Item $tmp -Force
