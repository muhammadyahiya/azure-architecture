# Build context is `src/` (the parent of this folder):
#   docker build -f src/rag_api/Dockerfile -t rag-api:latest src/
FROM python:3.12-slim

WORKDIR /app
COPY rag_api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY common ./common
COPY rag_api .

ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
