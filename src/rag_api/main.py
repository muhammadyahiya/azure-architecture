"""
rag_api — the synchronous, latency-sensitive front door. FastAPI, always at
least 1 warm replica (see infra/modules/containerapps-env.bicep), scales on
concurrent HTTP requests rather than a queue because a human is waiting on
the other end of this call.
"""
import logging

from fastapi import FastAPI
from pydantic import BaseModel

from common.telemetry import init_telemetry
from retriever import retrieve
from generator import generate_answer

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("rag_api")

init_telemetry("rag-api")
app = FastAPI(title="RAG API")


class QueryRequest(BaseModel):
    question: str
    top_k: int = 5
    allowed_group_ids: list[str] | None = None


class QueryResponse(BaseModel):
    answer: str
    citations: list[dict]


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.post("/query", response_model=QueryResponse)
def query(request: QueryRequest) -> QueryResponse:
    chunks = retrieve(request.question, top_k=request.top_k, allowed_group_ids=request.allowed_group_ids)
    if not chunks:
        return QueryResponse(answer="I couldn't find anything relevant to that question.", citations=[])

    answer = generate_answer(request.question, chunks)
    return QueryResponse(
        answer=answer,
        citations=[{"chunkId": c["chunkId"], "documentId": c["documentId"], "sourceBlobPath": c["sourceBlobPath"]} for c in chunks],
    )
