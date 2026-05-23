$ErrorActionPreference = "Continue"
$MIMIC = "https://ca-mimic-shared.wonderfulpebble-9f4a40b9.eastus.azurecontainerapps.io"
$MODEL_ID = "us.anthropic.claude-3-5-haiku-20241022-v1:0"
$tmp = New-TemporaryFile
'{"messages":[{"role":"user","content":[{"text":"hello direct to mimic"}]}],"inferenceConfig":{"maxTokens":64}}' | Set-Content -Path $tmp -Encoding utf8 -NoNewline

Write-Host "===== Direct call to mimic (without SigV4) ====="
curl.exe -i -X POST "$MIMIC/bedrock/model/$MODEL_ID/converse" `
  -H "Content-Type: application/json" `
  -H "Authorization: AWS4-HMAC-SHA256 Credential=fake/20260522/us-east-1/bedrock/aws4_request, SignedHeaders=host;x-amz-date, Signature=deadbeef" `
  -H "X-Amz-Date: 20260522T180000Z" `
  --data-binary "@$tmp"

Remove-Item $tmp -Force
