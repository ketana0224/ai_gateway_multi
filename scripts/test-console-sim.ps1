$ErrorActionPreference = "Stop"
$SUB = "9353f1a1-94a4-4e4b-ae82-c27ea3d07160"
$APIM_NAME = "apim-aigw-userxx"
$RG_APIM = "rg-aigw-handson-userxx"

$KEY = az rest --method post --uri "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG_APIM/providers/Microsoft.ApiManagement/service/$APIM_NAME/subscriptions/sub-aigw-handson/listSecrets?api-version=2022-08-01" --query "primaryKey" -o tsv

$tmp = New-TemporaryFile
'{"messages":[{"role":"user","content":[{"text":"test console sim"}]}],"inferenceConfig":{"maxTokens":64}}' | Set-Content -Path $tmp -Encoding utf8 -NoNewline

$base = "https://$APIM_NAME.azure-api.net"

$paths = @(
    @{ Label = "A: normal"; Path = "/bedrock/model/us.anthropic.claude-3-5-haiku-20241022-v1:0/converse" },
    @{ Label = "B: %2F + %3A encoded (Test console default)"; Path = "/bedrock/model%2Fus.anthropic.claude-3-5-haiku-20241022-v1%3A0%2Fconverse" },
    @{ Label = "C: only %3A encoded"; Path = "/bedrock/model/us.anthropic.claude-3-5-haiku-20241022-v1%3A0/converse" }
)

foreach ($p in $paths) {
    Write-Host ""
    Write-Host "===== $($p.Label) ====="
    Write-Host "URL: $base$($p.Path)"
    $resp = curl.exe -s -w "`n---HTTP %{http_code}---`n" -X POST "$base$($p.Path)" `
        -H "api-key: $KEY" `
        -H "Content-Type: application/json" `
        --data-binary "@$tmp"
    Write-Host $resp
}

Remove-Item $tmp -Force
