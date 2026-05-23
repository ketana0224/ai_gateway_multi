"""
AWS ネイティブ SDK (boto3) で Bedrock Runtime の Converse API を直接呼び出すサンプル。

認証は boto3 の標準解決順序に従います:
  1. 環境変数 (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN / AWS_REGION)
  2. ~/.aws/credentials, ~/.aws/config の named profile (AWS_PROFILE)
  3. IAM ロール / SSO など

事前に AWS CLI で `aws configure` するか、環境変数をセットしてから実行してください。
モデルへのアクセス権は Bedrock のコンソールで有効化が必要です:
  https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html
"""

import os
import sys

import boto3
from botocore.exceptions import BotoCoreError, ClientError

# AWS リージョン (環境変数 AWS_REGION があればそちら優先)
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

# モデル ID (例: Claude 3.5 Haiku)
# https://docs.aws.amazon.com/bedrock/latest/userguide/models-supported.html
MODEL_ID = "us.anthropic.claude-3-5-haiku-20241022-v1:0"

USER_MESSAGE = "Describe the purpose of a 'hello world' program in one line."


def main() -> int:
    # AWS_PROFILE があれば named profile を使用、無ければ標準解決 (env vars 等)
    profile = os.environ.get("AWS_PROFILE")
    session = boto3.Session(profile_name=profile) if profile else boto3.Session()

    client = session.client("bedrock-runtime", region_name=AWS_REGION)

    try:
        response = client.converse(
            modelId=MODEL_ID,
            messages=[
                {
                    "role": "user",
                    "content": [{"text": USER_MESSAGE}],
                }
            ],
            inferenceConfig={
                "maxTokens": 512,
                "temperature": 0.5,
                "topP": 0.9,
            },
        )
    except (ClientError, BotoCoreError) as e:
        print(f"ERROR: Can't invoke '{MODEL_ID}'. Reason: {e}", file=sys.stderr)
        return 1

    text = (
        response.get("output", {})
        .get("message", {})
        .get("content", [{}])[0]
        .get("text", "")
    )
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
