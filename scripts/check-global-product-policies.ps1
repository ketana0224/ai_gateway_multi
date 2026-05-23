$ErrorActionPreference = "Continue"
$APIM_NAME = "apim-aigw-userxx"
$RG = "rg-aigw-handson-userxx"
$SUB = "9353f1a1-94a4-4e4b-ae82-c27ea3d07160"
$token = az account get-access-token --resource https://management.azure.com --query accessToken -o tsv

Write-Host "===== GLOBAL policy ====="
try {
    $g = Invoke-RestMethod -Uri "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM_NAME/policies/policy?api-version=2022-08-01&format=rawxml" -Headers @{ Authorization = "Bearer $token" }
    Write-Host $g.properties.value
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 404) { Write-Host "(no global policy)" } else { Write-Host "ERROR: $_" }
}

Write-Host "`n===== PRODUCTS ====="
$prodResp = Invoke-RestMethod -Uri "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM_NAME/products?api-version=2022-08-01" -Headers @{ Authorization = "Bearer $token" }
$prods = $prodResp.value
$prods | ForEach-Object { "  $($_.name)" }

foreach ($p in $prods) {
    Write-Host "`n===== Product '$($p.name)' policy ====="
    try {
        $pp = Invoke-RestMethod -Uri "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM_NAME/products/$($p.name)/policies/policy?api-version=2022-08-01&format=rawxml" -Headers @{ Authorization = "Bearer $token" }
        Write-Host $pp.properties.value
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 404) { Write-Host "(no product policy)" } else { Write-Host "ERROR: $($_.Exception.Message)" }
    }
}
