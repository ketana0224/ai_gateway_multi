"""AWS Bedrock Runtime mimic for Anthropic Claude models.

Implements two Bedrock Runtime endpoints used by the Microsoft Learn
"Amazon Bedrock passthrough LLM API" flow:

- POST /model/{modelId}/converse    — Bedrock Converse API (unified contract)
- POST /model/{modelId}/invoke      — Bedrock InvokeModel API (Anthropic native body)

The mimic ignores AWS SigV4 (the `Authorization` / `X-Amz-*` headers signed by
APIM are accepted but **not verified**), so the Microsoft Learn flow works end
to end without real AWS credentials. APIM signs the request, this service just
responds with a Bedrock-shaped echo response.

References:
- https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html
- https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_InvokeModel.html
- https://learn.microsoft.com/azure/api-management/amazon-bedrock-passthrough-llm-api
"""

from __future__ import annotations

import asyncio
import uuid
from typing import Any
from urllib.parse import unquote

from fastapi import FastAPI, Request

app = FastAPI(title="AI Gateway Mimic (AWS Bedrock — Anthropic Claude)", version="2.0.0")

MIMIC_SLEEP_SEC = 0.2


def _echo_text(user_text: str) -> str:
    """Build the echo response text."""
    return f"[AWS Bedrock mimic API] Echo response: {user_text}"


def _approx_tokens(text: str) -> int:
    """Very rough token estimate: ~4 chars per token, min 1."""
    return max(1, len(text) // 4)


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _extract_text_from_converse_messages(messages: list[dict[str, Any]]) -> str:
    """Pick the latest user message text from a Bedrock Converse messages list."""
    for m in reversed(messages or []):
        if (m or {}).get("role") != "user":
            continue
        for part in (m.get("content") or []):
            text = (part or {}).get("text")
            if isinstance(text, str) and text:
                return text
    return ""


def _extract_text_from_anthropic_messages(messages: list[dict[str, Any]]) -> str:
    """Pick the latest user message text from an Anthropic-native messages list."""
    for m in reversed(messages or []):
        if (m or {}).get("role") != "user":
            continue
        content = m.get("content")
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            for part in content:
                if (part or {}).get("type") == "text":
                    text = part.get("text")
                    if isinstance(text, str) and text:
                        return text
    return ""


# ---------------------------------------------------------------------------
# Bedrock Runtime — Converse API
# POST /model/{modelId}/converse
# ---------------------------------------------------------------------------

@app.post("/model/{model_id:path}/converse")
async def bedrock_converse(model_id: str, request: Request) -> dict[str, Any]:
    await asyncio.sleep(MIMIC_SLEEP_SEC)
    raw = await request.body()
    body: dict[str, Any] = await request.json() if raw else {}

    messages = body.get("messages", []) if isinstance(body, dict) else []
    user_text = _extract_text_from_converse_messages(messages)
    reply = _echo_text(user_text)

    input_tokens = _approx_tokens(user_text)
    output_tokens = _approx_tokens(reply)

    return {
        "output": {
            "message": {
                "role": "assistant",
                "content": [{"text": reply}],
            }
        },
        "stopReason": "end_turn",
        "usage": {
            "inputTokens": input_tokens,
            "outputTokens": output_tokens,
            "totalTokens": input_tokens + output_tokens,
        },
        "metrics": {"latencyMs": int(MIMIC_SLEEP_SEC * 1000)},
    }


# ---------------------------------------------------------------------------
# Bedrock Runtime — InvokeModel API (Anthropic-native body)
# POST /model/{modelId}/invoke
# ---------------------------------------------------------------------------

@app.post("/model/{model_id:path}/invoke")
async def bedrock_invoke(model_id: str, request: Request) -> dict[str, Any]:
    await asyncio.sleep(MIMIC_SLEEP_SEC)
    raw = await request.body()
    body: dict[str, Any] = await request.json() if raw else {}

    messages = body.get("messages", []) if isinstance(body, dict) else []
    user_text = _extract_text_from_anthropic_messages(messages)
    reply = _echo_text(user_text)

    input_tokens = _approx_tokens(user_text)
    output_tokens = _approx_tokens(reply)

    return {
        "id": f"msg_mock_{uuid.uuid4().hex[:12]}",
        "type": "message",
        "role": "assistant",
        "model": unquote(model_id),
        "content": [{"type": "text", "text": reply}],
        "stop_reason": "end_turn",
        "stop_sequence": None,
        "usage": {
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
        },
    }
