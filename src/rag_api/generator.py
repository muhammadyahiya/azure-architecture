"""
Generation over retrieved context, via the Foundry chat-completion deployment.
Kept deliberately simple (single call, no agent loop) — if the task grows
tool-calling / multi-step needs, that's the signal to move this into Foundry
Agent Service or Microsoft Agent Framework rather than hand-rolling a loop
here (see docs/decision-log.md).
"""
from openai import AzureOpenAI
from azure.identity import get_bearer_token_provider

from common.config import get_credential, settings

_token_provider = get_bearer_token_provider(get_credential(), "https://cognitiveservices.azure.com/.default")

_client = AzureOpenAI(
    azure_endpoint=settings.FOUNDRY_ENDPOINT,
    azure_ad_token_provider=_token_provider,
    api_version="2024-10-21",
)

SYSTEM_PROMPT = (
    "Answer only from the provided context. If the context doesn't contain "
    "the answer, say so explicitly instead of guessing. Cite chunk ids you "
    "used in square brackets, e.g. [chunk-3]."
)


def generate_answer(question: str, chunks: list[dict]) -> str:
    context = "\n\n".join(f"[{c['chunkId']}] {c['text']}" for c in chunks)
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": f"Context:\n{context}\n\nQuestion: {question}"},
    ]
    response = _client.chat.completions.create(
        model=settings.GENERATION_DEPLOYMENT,
        messages=messages,
        temperature=0.1,
    )
    return response.choices[0].message.content
