"""
processing_worker — the KEDA-scaled heavy lifter.

Receives from the Service Bus SESSION subscription (sessions are required —
see infra/modules/servicebus.bicep — so all events for one document process in
order even if Event Grid redelivers or the worker scales to several
replicas). For each message: download the blob, extract text, chunk, embed,
index into AI Search, and update the Cosmos DB status record. On failure the
message is abandoned up to maxDeliveryCount times, then dead-lettered — check
the dead-letter subscription before assuming a document silently vanished.

Runs as a plain long-lived process, not an Azure Functions binding, because
this is a Container App: KEDA reads Service Bus queue depth from the *outside*
and adjusts replica count; each replica just needs to keep receiving.
"""
import datetime
import json
import logging
import os
import time

from azure.servicebus import NEXT_AVAILABLE_SESSION, ServiceBusClient
from azure.servicebus.exceptions import OperationTimeoutError
from azure.storage.blob import BlobClient
from azure.cosmos import CosmosClient

from common.config import get_credential, settings
from common.telemetry import init_telemetry
from chunking import chunk_text
from embeddings import embed_texts
from search_indexer import ensure_index_exists, upsert_chunks

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("processing_worker")

SUPPORTED_TEXT_EXTENSIONS = {".txt", ".md"}


def extract_text(blob_url: str, content_type: str) -> str:
    ext = os.path.splitext(blob_url)[1].lower()
    blob = BlobClient.from_blob_url(blob_url, credential=get_credential())
    raw = blob.download_blob().readall()

    if ext in SUPPORTED_TEXT_EXTENSIONS:
        return raw.decode("utf-8", errors="ignore")

    # TODO: route .pdf / .docx through Azure AI Document Intelligence's
    # prebuilt-layout model and use its Markdown output here instead. Kept out
    # of this template to avoid a hard dependency on a service you might not
    # provision — see docs/decision-log.md.
    raise ValueError(f"unsupported extension for extraction: {ext} (content-type {content_type})")


def _parse_events(body: bytes) -> list[dict]:
    payload = json.loads(body)
    return payload if isinstance(payload, list) else [payload]


def _update_status(cosmos_container, document_id: str, status: str, **extra) -> None:
    item = cosmos_container.read_item(item=document_id, partition_key=document_id)
    item["status"] = status
    item["updatedAt"] = datetime.datetime.utcnow().isoformat() + "Z"
    item.update(extra)
    cosmos_container.upsert_item(item)


def process_message(body: bytes, cosmos_container) -> None:
    for event in _parse_events(body):
        if event.get("eventType") != "Microsoft.Storage.BlobCreated":
            continue

        data = event["data"]
        blob_url = data["url"]
        content_type = data.get("contentType", "")
        document_id = blob_url.rsplit("/", 1)[-1]

        logger.info("Processing %s", document_id)
        try:
            ensure_index_exists()
            text = extract_text(blob_url, content_type)
            chunks = chunk_text(document_id, text)
            if not chunks:
                _update_status(cosmos_container, document_id, "processed", chunkCount=0)
                continue

            vectors = embed_texts([c.text for c in chunks])
            search_docs = [
                {
                    "id": c.chunk_id,
                    "documentId": document_id,
                    "chunkPosition": c.position,
                    "chunkText": c.text,
                    "chunkVector": vector,
                    "sourceBlobPath": blob_url,
                    "allowedGroupIds": [],  # wire up to your ACL source before production
                }
                for c, vector in zip(chunks, vectors)
            ]
            upsert_chunks(search_docs)
            _update_status(cosmos_container, document_id, "processed", chunkCount=len(chunks))
            logger.info("Indexed %s chunks for %s", len(chunks), document_id)

        except Exception as exc:  # noqa: BLE001 — deliberately broad: we always want to record the failure
            logger.exception("Failed processing %s", document_id)
            _update_status(cosmos_container, document_id, "failed", error=str(exc))
            raise  # let Service Bus retry / dead-letter per maxDeliveryCount


def run() -> None:
    init_telemetry("processing-worker")
    credential = get_credential()

    cosmos_container = (
        CosmosClient(settings.COSMOS_ENDPOINT, credential=credential)
        .get_database_client(settings.COSMOS_DATABASE)
        .get_container_client(settings.COSMOS_CONTAINER)
    )

    with ServiceBusClient(settings.SERVICEBUS_NAMESPACE_FQDN, credential=credential) as client:
        while True:
            try:
                with client.get_subscription_receiver(
                    topic_name=settings.SERVICEBUS_TOPIC,
                    subscription_name=settings.SERVICEBUS_SUBSCRIPTION,
                    session_id=NEXT_AVAILABLE_SESSION,
                    max_wait_time=30,
                ) as receiver:
                    for msg in receiver:
                        try:
                            process_message(b"".join(msg.body), cosmos_container)
                            receiver.complete_message(msg)
                        except Exception:  # noqa: BLE001
                            receiver.abandon_message(msg)
            except OperationTimeoutError:
                # No session available right now — this is normal and expected;
                # if it persists, KEDA scales this replica back to zero.
                time.sleep(2)


if __name__ == "__main__":
    run()
