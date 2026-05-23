$ErrorActionPreference = "Stop"

$SUBSCRIPTION = "9353f1a1-94a4-4e4b-ae82-c27ea3d07160"
$RG_INSTRUCTOR = "rg-mcp-instructor"
$ACR_NAME = "mcpinstructorsvn2j"
$APP_NAME = "ca-mimic-shared"
$IMAGE_TAG = "2.1.0-bedrock"
$IMAGE = "mimic:$IMAGE_TAG"

Write-Host "===== Setting subscription ====="
az account set --subscription $SUBSCRIPTION

$ACR_SERVER = az acr show -n $ACR_NAME --query loginServer -o tsv
Write-Host "ACR: $ACR_SERVER"
Write-Host "Image: $ACR_SERVER/$IMAGE"

Write-Host "`n===== Trying ACR Tasks (az acr build) ====="
$buildOk = $false
try {
    az acr build --registry $ACR_NAME --image $IMAGE ./mimic --only-show-errors
    if ($LASTEXITCODE -eq 0) { $buildOk = $true; Write-Host "ACR build succeeded." }
} catch {
    Write-Host "ACR Tasks failed: $_"
}

if (-not $buildOk) {
    Write-Host "`n===== Falling back to local docker build ====="
    az acr login --name $ACR_NAME
    docker build -t "$ACR_SERVER/$IMAGE" ./mimic
    if ($LASTEXITCODE -ne 0) { throw "docker build failed" }
    docker push "$ACR_SERVER/$IMAGE"
    if ($LASTEXITCODE -ne 0) { throw "docker push failed" }
}

Write-Host "`n===== Looking up Container App resource group ====="
$caJson = az graph query -q "Resources | where type =~ 'microsoft.app/containerapps' and name == '$APP_NAME' and subscriptionId == '$SUBSCRIPTION' | project name, resourceGroup, id" --first 5 -o json | ConvertFrom-Json
if (-not $caJson.data -or $caJson.data.Count -eq 0) {
    Write-Host "Container App '$APP_NAME' not found via Resource Graph. Trying $RG_INSTRUCTOR directly..."
    $caRg = $RG_INSTRUCTOR
} else {
    $caRg = $caJson.data[0].resourceGroup
}
Write-Host "Container App RG: $caRg"

Write-Host "`n===== Updating Container App to new image ====="
az containerapp update -n $APP_NAME -g $caRg --image "$ACR_SERVER/$IMAGE" --output none
if ($LASTEXITCODE -ne 0) { throw "containerapp update failed" }
Write-Host "Container App updated."

Write-Host "`n===== Waiting for revision rollout (15s) ====="
Start-Sleep -Seconds 15

$MIMIC_BASE_URL = "https://$(az containerapp show -g $caRg -n $APP_NAME --query properties.configuration.ingress.fqdn -o tsv)"
Write-Host "MIMIC_BASE_URL: $MIMIC_BASE_URL"

Write-Host "`n===== Direct verify against mimic ====="
$tmp = New-TemporaryFile
'{"messages":[{"role":"user","content":[{"text":"verify new mimic"}]}],"inferenceConfig":{"maxTokens":64}}' | Set-Content -Path $tmp -Encoding utf8 -NoNewline
curl.exe -s -X POST "$MIMIC_BASE_URL/model/us.anthropic.claude-3-5-haiku-20241022-v1:0/converse" -H "Content-Type: application/json" --data-binary "@$tmp"
Write-Host ""
Remove-Item $tmp -Force

Write-Host "`n===== Verify via APIM (SigV4 path) ====="
$APIM_NAME = "apim-aigw-userxx"
$RG_APIM = "rg-aigw-handson-userxx"
$KEY = az rest --method post --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION/resourceGroups/$RG_APIM/providers/Microsoft.ApiManagement/service/$APIM_NAME/subscriptions/sub-aigw-handson/listSecrets?api-version=2022-08-01" --query "primaryKey" -o tsv
$tmp = New-TemporaryFile
'{"messages":[{"role":"user","content":[{"text":"verify via APIM"}]}],"inferenceConfig":{"maxTokens":64}}' | Set-Content -Path $tmp -Encoding utf8 -NoNewline
curl.exe -s -X POST "https://$APIM_NAME.azure-api.net/bedrock/model/us.anthropic.claude-3-5-haiku-20241022-v1:0/converse" -H "api-key: $KEY" -H "Content-Type: application/json" --data-binary "@$tmp"
Write-Host ""
Remove-Item $tmp -Force
