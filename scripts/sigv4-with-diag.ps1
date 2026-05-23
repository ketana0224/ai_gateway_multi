$ErrorActionPreference = "Stop"
$APIM_NAME = "apim-aigw-userxx"
$RG = "rg-aigw-handson-userxx"
$SUB = "9353f1a1-94a4-4e4b-ae82-c27ea3d07160"

$token = az account get-access-token --resource https://management.azure.com --query accessToken -o tsv
$polUri = "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM_NAME/apis/bedrock-api/policies/policy?api-version=2022-08-01&format=rawxml"

# SigV4 改良版 + on-error diagnostics 入り
$full = @'
<policies>
    <inbound>
        <base />
        <set-backend-service backend-id="bedrock-api-backend" />
        <set-variable name="now" value="@(DateTime.UtcNow)" />
        <set-variable name="requestBody" value="@(context.Request.Body.As<string>(preserveContent: true) ?? "")" />
        <set-header name="X-Amz-Date" exists-action="override">
            <value>@(((DateTime)context.Variables["now"]).ToString("yyyyMMddTHHmmssZ"))</value>
        </set-header>
        <set-header name="X-Amz-Content-Sha256" exists-action="override">
            <value>@{
                var body = (string)context.Variables["requestBody"];
                using (var sha256 = System.Security.Cryptography.SHA256.Create())
                {
                    var hash = sha256.ComputeHash(System.Text.Encoding.UTF8.GetBytes(body));
                    return BitConverter.ToString(hash).Replace("-", "").ToLowerInvariant();
                }
            }</value>
        </set-header>
        <set-header name="Authorization" exists-action="override">
            <value>@{
                var accessKey = "{{accesskey}}";
                var secretKey = "{{secretkey}}";
                var region = "us-east-1";
                var service = "bedrock";

                var method = context.Request.Method;
                var uri = context.Request.Url;
                var host = uri.Host;

                var path = uri.Path;
                var modelSplit = path.Split(new[] { "model/" }, 2, StringSplitOptions.None);
                var afterModel = modelSplit.Length > 1 ? modelSplit[1] : "";
                var parts = afterModel.Split(new[] { '/' }, 2);
                var model = System.Uri.EscapeDataString(parts[0]);
                var remainder = parts.Length > 1 ? parts[1] : "";
                var canonicalPath = $"/model/{model}/{remainder}";

                var amzDate = ((DateTime)context.Variables["now"]).ToString("yyyyMMddTHHmmssZ");
                var dateStamp = ((DateTime)context.Variables["now"]).ToString("yyyyMMdd");

                var body = (string)context.Variables["requestBody"];
                string hashedPayload;
                using (var sha256 = System.Security.Cryptography.SHA256.Create())
                {
                    var hash = sha256.ComputeHash(System.Text.Encoding.UTF8.GetBytes(body));
                    hashedPayload = BitConverter.ToString(hash).Replace("-", "").ToLowerInvariant();
                }

                var canonicalQueryString = "";

                var headers = context.Request.Headers;
                var canonicalHeaderList = new List<string[]>();

                if (headers.ContainsKey("Content-Type"))
                {
                    var ct = headers["Content-Type"].FirstOrDefault() ?? "";
                    canonicalHeaderList.Add(new[] { "content-type", ct.ToLowerInvariant() });
                }
                canonicalHeaderList.Add(new[] { "host", host });
                canonicalHeaderList.Add(new[] { "x-amz-content-sha256", hashedPayload });
                canonicalHeaderList.Add(new[] { "x-amz-date", amzDate });

                var canonicalHeadersOrdered = canonicalHeaderList.OrderBy(h => h[0]).ToList();
                var canonicalHeaders = string.Join("\n", canonicalHeadersOrdered.Select(h => h[0] + ":" + (h[1] ?? "").Trim())) + "\n";
                var signedHeaders = string.Join(";", canonicalHeadersOrdered.Select(h => h[0]));

                var canonicalRequest = $"{method}\n{canonicalPath}\n{canonicalQueryString}\n{canonicalHeaders}\n{signedHeaders}\n{hashedPayload}";
                string hashedCanonicalRequest;
                using (var sha256 = System.Security.Cryptography.SHA256.Create())
                {
                    var hash = sha256.ComputeHash(System.Text.Encoding.UTF8.GetBytes(canonicalRequest));
                    hashedCanonicalRequest = BitConverter.ToString(hash).Replace("-", "").ToLowerInvariant();
                }

                var credentialScope = $"{dateStamp}/{region}/{service}/aws4_request";
                var stringToSign = $"AWS4-HMAC-SHA256\n{amzDate}\n{credentialScope}\n{hashedCanonicalRequest}";

                byte[] kSecret = System.Text.Encoding.UTF8.GetBytes("AWS4" + secretKey);
                byte[] kDate, kRegion, kService, kSigning;
                using (var h1 = new System.Security.Cryptography.HMACSHA256(kSecret)) { kDate = h1.ComputeHash(System.Text.Encoding.UTF8.GetBytes(dateStamp)); }
                using (var h2 = new System.Security.Cryptography.HMACSHA256(kDate)) { kRegion = h2.ComputeHash(System.Text.Encoding.UTF8.GetBytes(region)); }
                using (var h3 = new System.Security.Cryptography.HMACSHA256(kRegion)) { kService = h3.ComputeHash(System.Text.Encoding.UTF8.GetBytes(service)); }
                using (var h4 = new System.Security.Cryptography.HMACSHA256(kService)) { kSigning = h4.ComputeHash(System.Text.Encoding.UTF8.GetBytes("aws4_request")); }

                string signature;
                using (var hmac = new System.Security.Cryptography.HMACSHA256(kSigning))
                {
                    var sigBytes = hmac.ComputeHash(System.Text.Encoding.UTF8.GetBytes(stringToSign));
                    signature = BitConverter.ToString(sigBytes).Replace("-", "").ToLowerInvariant();
                }

                return $"AWS4-HMAC-SHA256 Credential={accessKey}/{credentialScope}, SignedHeaders={signedHeaders}, Signature={signature}";
            }</value>
        </set-header>
        <set-header name="Host" exists-action="override">
            <value>@(context.Request.Url.Host)</value>
        </set-header>
    </inbound>
    <backend><base /></backend>
    <outbound><base /></outbound>
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
</policies>
'@

$body = @{ properties = @{ format = "rawxml"; value = $full } } | ConvertTo-Json -Depth 5
Invoke-RestMethod -Uri $polUri -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } -Method Put -Body $body | Out-Null
Write-Host "SigV4 + diagnostics policy applied. Sleeping 8s for propagation..."
Start-Sleep -Seconds 8

$KEY = az rest --method post --uri "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM_NAME/subscriptions/sub-aigw-handson/listSecrets?api-version=2022-08-01" --query "primaryKey" -o tsv
$APIM = "https://$APIM_NAME.azure-api.net"
$MODEL_ID = "us.anthropic.claude-3-5-haiku-20241022-v1:0"
$tmp = New-TemporaryFile
'{"messages":[{"role":"user","content":[{"text":"hello SigV4"}]}],"inferenceConfig":{"maxTokens":64}}' | Set-Content -Path $tmp -Encoding utf8 -NoNewline

Write-Host "`n===== Calling bedrock-api with SigV4 + on-error diag ====="
curl.exe -i -X POST "$APIM/bedrock/model/$MODEL_ID/converse" `
  -H "api-key: $KEY" `
  -H "Content-Type: application/json" `
  --data-binary "@$tmp"

Remove-Item $tmp -Force
