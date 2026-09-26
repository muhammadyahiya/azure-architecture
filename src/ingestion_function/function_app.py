"""
ingestion_function — cheap, independent validation gate.

Listens to the same "blob created" signal that the Event Grid -> Service Bus
path uses, via a native blob trigger with source=EVENT_GRID (push-based, not
polling). Its only job: reject obviously-bad uploads before they cost anything
downstream, and write the initial "received" record to Cosmos DB so there's a
row to update as the document moves through the pipeline. It never touches
Service Bus or AI Search — that's processing_worker's job, triggered
independently. A bug here cannot block that pipeline.
"""
import datetime
import logging
import os

import azure.functions as func
from azure.cosmos import CosmosClient

from common.config import get_credential, settings

app = func.FunctionApp()

ALLOWED_EXTENSIONS = {".pdf", ".docx", ".md", ".txt", ".csv"}
MAX_BYTES = 50 * 1024 * 1024  # 50 MB — tune per project


@app.blob_trigger(
    arg_name="myblob",
    path="documents/{name}",
    connection="AzureWebJobsStorage",
    source=func.BlobSource.EVENT_GRID,
)
def validate_upload(myblob: func.InputStream) -> None:
    name = myblob.name or ""
    size = myblob.length or 0
    ext = os.path.splitext(name)[1].lower()

    document_id = name.split("/")[-1]
    record = {
        "id": document_id,
        "documentId": document_id,
        "blobPath": name,
        "sizeBytes": size,
        "receivedAt": datetime.datetime.utcnow().isoformat() + "Z",
        "status": "received",
    }

    if ext not in ALLOWED_EXTENSIONS:
        record["status"] = "rejected"
        record["rejectReason"] = f"unsupported extension {ext}"
        logging.warning("Rejected %s: unsupported extension", name)
    elif size == 0:
        record["status"] = "rejected"
        record["rejectReason"] = "zero-byte upload"
        logging.warning("Rejected %s: zero bytes", name)
    elif size > MAX_BYTES:
        record["status"] = "rejected"
        record["rejectReason"] = f"exceeds {MAX_BYTES} byte limit"
        logging.warning("Rejected %s: too large (%s bytes)", name, size)

    _write_cosmos_record(record)


def _write_cosmos_record(record: dict) -> None:
    client = CosmosClient(settings.COSMOS_ENDPOINT, credential=get_credential())
    db = client.get_database_client(settings.COSMOS_DATABASE)
    container = db.get_container_client(settings.COSMOS_CONTAINER)
    container.upsert_item(record)
