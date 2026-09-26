"""
Hybrid (keyword + vector) retrieval with semantic re-ranking against AI
Search. This is the "build" half of the buy-vs-build call documented in
docs/decision-log.md — swap for AI Search's agentic retrieval / a Foundry IQ
knowledge base if your content fits one of those and you want less code to
own.
"""
from azure.search.documents import SearchClient
from azure.search.documents.models import VectorizedQuery

from common.config import get_credential, settings
from embeddings import embed_texts

_search_client = SearchClient(
    endpoint=settings.SEARCH_ENDPOINT,
    index_name=settings.SEARCH_INDEX_NAME,
    credential=get_credential(),
)


def retrieve(question: str, top_k: int = 5, allowed_group_ids: list[str] | None = None) -> list[dict]:
    query_vector = embed_texts([question])[0]
    vector_query = VectorizedQuery(vector=query_vector, k_nearest_neighbors=50, fields="chunkVector")

    # Document-level security trimming: only chunks with no ACL, or an ACL the
    # caller belongs to, are eligible. Wire allowed_group_ids from your auth
    # layer (Entra ID group claims, etc.) before this goes anywhere near
    # multi-tenant data.
    filter_expr = None
    if allowed_group_ids:
        groups = ", ".join(f"'{g}'" for g in allowed_group_ids)
        filter_expr = f"allowedGroupIds/any(g: search.in(g, '{groups}')) or allowedGroupIds/all(g: false)"

    results = _search_client.search(
        search_text=question,
        vector_queries=[vector_query],
        query_type="semantic",
        semantic_configuration_name="default-semantic-config",
        filter=filter_expr,
        select=["id", "documentId", "chunkText", "chunkPosition", "sourceBlobPath"],
        top=top_k,
    )

    return [
        {
            "chunkId": r["id"],
            "documentId": r["documentId"],
            "text": r["chunkText"],
            "sourceBlobPath": r["sourceBlobPath"],
            "rerankerScore": r.get("@search.reranker_score"),
        }
        for r in results
    ]
