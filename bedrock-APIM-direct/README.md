# Bedrock APIM Direct Sample

`bedrock/` の HttpClient 書き換え版を、`ServiceURL` で APIM に直接向ける最小構成にしたサンプルです。

## 事前準備

- .NET 8 SDK
- API Management の Bedrock passthrough API
- `APIM_BEDROCK_URL` と `APIM_SUBSCRIPTION_KEY` の環境変数
- `AWS_ACCESS_KEY_ID` と `AWS_SECRET_ACCESS_KEY` の環境変数、またはサンプル内のダミー値をそのまま使用

## 実行

```powershell
$env:APIM_BEDROCK_URL = "https://<your-apim>.azure-api.net/bedrock"
$env:APIM_SUBSCRIPTION_KEY = "<your-apim-subscription-key>"
$env:AWS_ACCESS_KEY_ID = "dummy-access-key"
$env:AWS_SECRET_ACCESS_KEY = "dummy-secret-key"
dotnet run
```

## ポイント

- `ServiceURL` で APIM の URL を直接指定します。
- `AuthenticationRegion` は `us-east-1` を使います。
- `BedrockHttpClientFactory.cs` は不要です。
- 署名用に非空の AWS 認証情報を渡す必要があります。
- `ServiceURL` は `RegionEndpoint` より後に設定します。AWS SDK では両者が相互排他のため、後から設定した方が有効になります。
