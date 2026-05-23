$ErrorActionPreference = "Continue"
$APIM_NAME = "apim-aigw-userxx"
$RG = "rg-aigw-handson-userxx"
$SUB = "9353f1a1-94a4-4e4b-ae82-c27ea3d07160"
$token = az account get-access-token --resource https://management.azure.com --query accessToken -o tsv

Write-Host "===== bedrock-api operations ====="
$opsResp = Invoke-RestMethod -Uri "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM_NAME/apis/bedrock-api/operations?api-version=2022-08-01" -Headers @{ Authorization = "Bearer $token" }
$ops = $opsResp.value
$ops | ForEach-Object { "{0,-30} {1,-6} {2}" -f $_.name, $_.properties.method, $_.properties.urlTemplate }

foreach ($op in $ops) {
    Write-Host "`n===== Operation: $($op.name) policy ====="
    try {
        $pUri = "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM_NAME/apis/bedrock-api/operations/$($op.name)/policies/policy?api-version=2022-08-01&format=rawxml"
        $p = Invoke-RestMethod -Uri $pUri -Headers @{ Authorization = "Bearer $token" }
        Write-Host $p.properties.value
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 404) {
            Write-Host "(no operation-scope policy)"
        } else {
            Write-Host "ERROR: $($_.Exception.Message)"
        }
    }
}
