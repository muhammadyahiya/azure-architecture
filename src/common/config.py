"""
Shared configuration + credential helper for processing_worker and rag_api.
Every Azure SDK client in this template is built with DefaultAzureCredential,
which resolves to the container's user-assigned managed identity in Azure and
to `az login` / VS Code auth locally — same code, no environment-specific
branching, no secrets.
"""
import os
from functools import lru_cache

from azure.identity import DefaultAzureCredential, ManagedIdentityCredential


@lru_cache(maxsize=1)
def get_credential():
    """
    Locally: falls back through the DefaultAzureCredential chain (az cli, VS
    Code, etc). In Azure: AZURE_CLIENT_ID (set by Bicep on the worker app) pins
    this to the correct user-assigned identity when a Container App has more
    than one identity attached.
    """
    client_id = os.environ.get("AZURE_CLIENT_ID")
    if client_id:
        return ManagedIdentityCredential(client_id=client_id)
    return DefaultAzureCredential()


class Settings:
    SERVICEBUS_NAMESPACE_FQDN = os.environ.get("SERVICEBUS_NAMESPACE_FQDN", "")
    SERVICEBUS_TOPIC = os.environ.get("SERVICEBUS_TOPIC", "document-ingested")
    SERVICEBUS_SUBSCRIPTION = os.environ.get("SERVICEBUS_SUBSCRIPTION", "processing-worker")

    COSMOS_ENDPOINT = os.environ.get("COSMOS_ENDPOINT", "")
    COSMOS_DATABASE = os.environ.get("COSMOS_DATABASE", "ragplatform")
    COSMOS_CONTAINER = os.environ.get("COSMOS_CONTAINER", "documents")

    SEARCH_ENDPOINT = os.environ.get("SEARCH_ENDPOINT", "")
    SEARCH_INDEX_NAME = os.environ.get("SEARCH_INDEX_NAME", "documents-index")

    FOUNDRY_ENDPOINT = os.environ.get("FOUNDRY_ENDPOINT", "")
    GENERATION_DEPLOYMENT = os.environ.get("GENERATION_DEPLOYMENT", "gpt-4o")
    EMBEDDING_DEPLOYMENT = os.environ.get("EMBEDDING_DEPLOYMENT", "text-embedding-3-large")
    EMBEDDING_DIMENSIONS = int(os.environ.get("EMBEDDING_DIMENSIONS", "3072"))

    STORAGE_ACCOUNT_URL = os.environ.get("STORAGE_ACCOUNT_URL", "")
    DOCUMENTS_CONTAINER = os.environ.get("DOCUMENTS_CONTAINER", "documents")


settings = Settings()
