using Amazon;
using Amazon.BedrockRuntime;
using Amazon.BedrockRuntime.Model;
using Amazon.Runtime;

// Use non-empty values so the AWS SDK emits an Authorization header.
// APIM re-signs the request server-side, so these values do not need to be real AWS credentials for this sample.
var accessKey = Environment.GetEnvironmentVariable("AWS_ACCESS_KEY_ID") ?? "dummy-access-key";
var secretKey = Environment.GetEnvironmentVariable("AWS_SECRET_ACCESS_KEY") ?? "dummy-secret-key";
var credentials = new BasicAWSCredentials(accessKey, secretKey);

// apimUrl は API Management のエンドポイント。例: https://apim-hello-word.azure-api.net/bedrock
var apimUrl = Environment.GetEnvironmentVariable("APIM_BEDROCK_URL") ?? "<api-management-endpoint>";
var apimSubscriptionHeaderName = "api-key";
var apimSubscriptionKey = Environment.GetEnvironmentVariable("APIM_SUBSCRIPTION_KEY") ?? "<your-apim-subscription-key>";

var config = new AmazonBedrockRuntimeConfig
{
    AuthenticationRegion = RegionEndpoint.USEast1.SystemName,
    RegionEndpoint = RegionEndpoint.USEast1,
    HttpClientFactory = new ApimHeaderHttpClientFactory(apimSubscriptionHeaderName, apimSubscriptionKey),
    // APIM を直接エンドポイントとして使う。ServiceURL は RegionEndpoint より後に設定しないと上書きされる。
    ServiceURL = apimUrl
};

var client = new AmazonBedrockRuntimeClient(credentials, config);

// モデル ID。例: Claude 3.5 Haiku。サポートモデルは Bedrock ドキュメント参照:
// https://docs.aws.amazon.com/bedrock/latest/userguide/models-supported.html
var modelId = "us.anthropic.claude-3-5-haiku-20241022-v1:0";

// ユーザーメッセージ
var userMessage = "Describe the purpose of a 'hello world' program in one line.";

// Converse リクエスト作成
var request = new ConverseRequest
{
    ModelId = modelId,
    Messages = new List<Message>
    {
        new Message
        {
            Role = ConversationRole.User,
            Content = new List<ContentBlock> { new ContentBlock { Text = userMessage } }
        }
    },
    InferenceConfig = new InferenceConfiguration
    {
        MaxTokens = 512,
        Temperature = 0.5F,
        TopP = 0.9F
    }
};

try
{
    // Bedrock runtime にリクエストを送信して結果を待機
    var response = await client.ConverseAsync(request);

    // レスポンステキストを抽出して出力
    string responseText = response?.Output?.Message?.Content?[0]?.Text ?? "";
    Console.WriteLine(responseText);
}
catch (AmazonBedrockRuntimeException e)
{
    Console.WriteLine($"ERROR: Can't invoke '{modelId}'. Reason: {e.Message}");
    throw;
}

internal sealed class ApimHeaderHttpClientFactory : HttpClientFactory
{
    private readonly string _headerName;
    private readonly string _headerValue;

    public ApimHeaderHttpClientFactory(string headerName, string headerValue)
    {
        _headerName = headerName;
        _headerValue = headerValue;
    }

    public override HttpClient CreateHttpClient(IClientConfig clientConfig)
    {
        var client = new HttpClient();

        if (!string.IsNullOrWhiteSpace(_headerName) && !string.IsNullOrWhiteSpace(_headerValue))
        {
            client.DefaultRequestHeaders.Remove(_headerName);
            client.DefaultRequestHeaders.Add(_headerName, _headerValue);
        }

        return client;
    }
}
