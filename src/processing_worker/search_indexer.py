"""
AI Search index schema + upsert. Kept out of Bicep on purpose (see
docs/decision-log.md): changing chunk fields or the vector profile is an app
change, not an infra change, so it ships through app-cd.yml, not infra-cd.yml.
"""
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import (
    HnswAlgorithmConfiguration,
    SearchableField,
    SearchField,
    SearchFieldDataType,
    SearchIndex,
    SemanticConfiguration,
    SemanticField,
    SemanticPrioritizedFields,
    SemanticSearch,
    SimpleField,
    VectorSearch,
    VectorSearchProfile,
)

from common.config import get_credential, settings

_VECTOR_PROFILE = "default-hnsw-profile"
_VECTOR_ALGO = "default-hnsw-algo"
_SEMANTIC_CONFIG = "default-semantic-config"


def ensure_index_exists() -> None:
    index_client = SearchIndexClient(endpoint=settings.SEARCH_ENDPOINT, credential=get_credential())
    if settings.SEARCH_INDEX_NAME in [i.name for i in index_client.list_indexes()]:
        return

    fields = [
        SimpleField(name="id", type=SearchFieldDataType.String, key=True),
        SimpleField(name="documentId", type=SearchFieldDataType.String, filterable=True),
        SimpleField(name="chunkPosition", type=SearchFieldDataType.Int32, sortable=True),
        SearchableField(name="chunkText", type=SearchFieldDataType.String),
        SearchField(
            name="chunkVector",
            type=SearchFieldDataType.Collection(SearchFieldDataType.Single),
            searchable=True,
            vector_search_dimensions=settings.EMBEDDING_DIMENSIONS,
            vector_search_profile_name=_VECTOR_PROFILE,
        ),
        SimpleField(name="sourceBlobPath", type=SearchFieldDataType.String, filterable=True),
        # Document-level security trimming placeholder — populate from your ACL system and
        # add a `filter` on query time (see rag_api/retriever.py). Empty = visible to everyone.
        SimpleField(name="allowedGroupIds", type=SearchFieldDataType.Collection(SearchFieldDataType.String), filterable=True),
    ]

    vector_search = VectorSearch(
        algorithms=[HnswAlgorithmConfiguration(name=_VECTOR_ALGO)],
        profiles=[VectorSearchProfile(name=_VECTOR_PROFILE, algorithm_configuration_name=_VECTOR_ALGO)],
    )

    semantic_search = SemanticSearch(
        configurations=[
            SemanticConfiguration(
                name=_SEMANTIC_CONFIG,
                prioritized_fields=SemanticPrioritizedFields(content_fields=[SemanticField(field_name="chunkText")]),
            )
        ],
        default_configuration_name=_SEMANTIC_CONFIG,
    )

    index = SearchIndex(name=settings.SEARCH_INDEX_NAME, fields=fields, vector_search=vector_search, semantic_search=semantic_search)
    index_client.create_index(index)


def upsert_chunks(documents: list[dict]) -> None:
    search_client = SearchClient(endpoint=settings.SEARCH_ENDPOINT, index_name=settings.SEARCH_INDEX_NAME, credential=get_credential())
    search_client.merge_or_upload_documents(documents=documents)
