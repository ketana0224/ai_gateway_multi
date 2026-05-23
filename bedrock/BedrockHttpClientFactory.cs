using Amazon.Runtime;

namespace BedrockClient;

/// <summary>
/// AWS Bedrock のリクエストを Azure API Management 経由でルーティングするための HttpClientFactory。
/// - Bedrock SDK が生成する URI のホスト/スキームを APIM のエンドポイントに置き換え
/// - APIM のサブスクリプションキーをヘッダーで付与
/// </summary>
public class BedrockHttpClientFactory : HttpClientFactory
{
    private readonly Uri _apimBase;
    private readonly string _apimSubscriptionHeaderName;
    private readonly string _apimSubscriptionKey;

    public BedrockHttpClientFactory(string apimUrl, string apimSubscriptionHeaderName, string apimSubscriptionKey)
    {
        if (string.IsNullOrWhiteSpace(apimUrl))
            throw new ArgumentException("apimUrl is required", nameof(apimUrl));

        _apimBase = new Uri(apimUrl);
        _apimSubscriptionHeaderName = apimSubscriptionHeaderName;
        _apimSubscriptionKey = apimSubscriptionKey;
    }

    public override HttpClient CreateHttpClient(IClientConfig clientConfig)
    {
        var handler = new ApimRoutingHandler(_apimBase)
        {
            InnerHandler = new HttpClientHandler()
        };

        var client = new HttpClient(handler);

        if (!string.IsNullOrEmpty(_apimSubscriptionHeaderName) && !string.IsNullOrEmpty(_apimSubscriptionKey))
        {
            client.DefaultRequestHeaders.Remove(_apimSubscriptionHeaderName);
            client.DefaultRequestHeaders.Add(_apimSubscriptionHeaderName, _apimSubscriptionKey);
        }

        return client;
    }

    private sealed class ApimRoutingHandler : DelegatingHandler
    {
        private readonly Uri _apimBase;

        public ApimRoutingHandler(Uri apimBase)
        {
            _apimBase = apimBase;
        }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var originalUri = request.RequestUri!;

            // APIM のベースパス + 元のパス (例: /model/{modelId}/converse) を結合
            var basePath = _apimBase.AbsolutePath.TrimEnd('/');
            var combinedPath = basePath + originalUri.AbsolutePath;

            var builder = new UriBuilder
            {
                Scheme = _apimBase.Scheme,
                Host = _apimBase.Host,
                Port = _apimBase.Port,
                Path = combinedPath,
                Query = originalUri.Query.TrimStart('?')
            };

            request.RequestUri = builder.Uri;

            // ホストヘッダーも APIM 側に合わせて再設定
            request.Headers.Host = _apimBase.Authority;

            return base.SendAsync(request, cancellationToken);
        }
    }
}
