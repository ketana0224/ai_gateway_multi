$ErrorActionPreference = "Stop"
$APIM_NAME = "apim-aigw-userxx"
$RG = "rg-aigw-handson-userxx"
$SUB = "9353f1a1-94a4-4e4b-ae82-c27ea3d07160"

Write-Host "===== APIM loggers ====="
az rest --method get --uri "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM_NAME/loggers?api-version=2022-08-01" --query "value[].{name:name, type:properties.loggerType, resId:properties.resourceId}" -o jsonc

Write-Host "`n===== App Insights resources in RG ====="
az resource list -g $RG --resource-type "Microsoft.Insights/components" --query "[].{name:name, id:id}" -o table
