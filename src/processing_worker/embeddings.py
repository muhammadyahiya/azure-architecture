"""
Embeddings via the Foundry embedding deployment, using Entra ID token auth
(azure_ad_token_provider) — no API key, same managed identity as everything
else in this container.
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


def embed_texts(texts: list[str]) -> list[list[float]]:
    """Batch-embeds; Azure OpenAI/Foundry embedding endpoints accept up to ~2048 inputs per call — batch upstream for very large documents."""
    response = _client.embeddings.create(model=settings.EMBEDDING_DEPLOYMENT, input=texts)
    return [item.embedding for item in response.data]
