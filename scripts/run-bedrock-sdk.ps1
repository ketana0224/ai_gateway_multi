$ErrorActionPreference = "Stop"
$env:APIM_BEDROCK_URL = "https://apim-aigw-userxx.azure-api.net/bedrock"
$env:APIM_SUBSCRIPTION_KEY = az rest --method post --uri "https://management.azure.com/subscriptions/9353f1a1-94a4-4e4b-ae82-c27ea3d07160/resourceGroups/rg-aigw-handson-userxx/providers/Microsoft.ApiManagement/service/apim-aigw-userxx/subscriptions/sub-aigw-handson/listSecrets?api-version=2022-08-01" --query "primaryKey" -o tsv
Push-Location .\bedrock
dotnet run --nologo
Pop-Location
