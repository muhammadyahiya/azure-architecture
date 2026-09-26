# Build context is `src/` (the parent of this folder), NOT this directory —
# it needs to see the sibling `common/` package too:
#   docker build -f src/processing_worker/Dockerfile -t processing-worker:latest src/
FROM python:3.12-slim

WORKDIR /app
COPY processing_worker/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY common ./common
COPY processing_worker .

ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app
CMD ["python", "main.py"]
