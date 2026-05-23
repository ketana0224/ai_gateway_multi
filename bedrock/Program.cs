using Amazon;
using Amazon.BedrockRuntime;
using Amazon.BedrockRuntime.Model;
using Amazon.Runtime;
using BedrockClient;

// Leave accessKey and secretKey values as empty strings. Authentication to AWS API is handled through policies in API Management.
var accessKey = "";
var secretKey = "";
var credentials = new BasicAWSCredentials(accessKey, secretKey);

// Create custom configuration to route requests through API Management
// apimUrl は API Management のエンドポイント。例: https://apim-hello-word.azure-api.net/bedrock
var apimUrl = Environment.GetEnvironmentVariable("APIM_BEDROCK_URL") ?? "<api-management-endpoint>";
// Provide name and value for the API Management subscription key header.
var apimSubscriptionHeaderName = "api-key";
var apimSubscriptionKey = Environment.GetEnvironmentVariable("APIM_SUBSCRIPTION_KEY") ?? "<your-apim-subscription-key>";

var config = new AmazonBedrockRuntimeConfig()
{
    HttpClientFactory = new BedrockHttpClientFactory(apimUrl, apimSubscriptionHeaderName, apimSubscriptionKey),
    // Bedrock モデルがホストされている AWS リージョン
    RegionEndpoint = RegionEndpoint.USEast1
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
    InferenceConfig = new InferenceConfiguration()
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
