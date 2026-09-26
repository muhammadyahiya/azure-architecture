# Azure GenAI Platform Template

A production-oriented, event-driven reference implementation for shipping GenAI / RAG
applications on Azure, plus a parallel MLOps track for endpoints you host and train
yourself. Treat this as a skeleton to `git clone` into every new project and delete
what you don't need — not a framework to depend on.

Naming note (2026): "Azure AI Foundry" is now **Microsoft Foundry** (Azure AI Studio →
Azure AI Foundry → Microsoft Foundry). Prompt Flow is retired (Apr 2026) in favor of
**Microsoft Agent Framework 1.0** and **Foundry Agent Service**. This template uses the
current names and SDKs (`azure-ai-projects` 2.2.x). Re-check `docs/decision-log.md`
before you build on this in six months — this stack moves fast.

## Architecture

```
                                   ┌───────────────────────────┐
                                   │   Microsoft Foundry        │
                                   │   (model catalog / agent   │
                                   │   service / Foundry IQ)    │
                                   └─────────────▲───────────────┘
                                                 │ inference calls
┌──────────┐   blob created   ┌────────────┐  filtered route  ┌──────────────┐   queue/topic   ┌───────────────────┐
│  Blob     │ ───────────────▶│ Event Grid  │─────────────────▶│  Service Bus  │────────────────▶│ processing-worker  │
│  Storage  │  (system topic) │  (routing)  │                   │ (reliability) │  KEDA-scaled    │  Container App     │
└──────────┘                  └────────────┘                   └──────────────┘                 └─────────┬─────────┘
                                                                                                            │ chunk + embed
                                                                                        ┌───────────────────┼────────────────────┐
                                                                                        ▼                                        ▼
                                                                              ┌──────────────────┐                    ┌──────────────────┐
                                                                              │  Azure AI Search   │                    │  Cosmos DB (NoSQL) │
                                                                              │  (vector + hybrid  │                    │  (doc metadata,    │
                                                                              │  + semantic rank)  │                    │  status, audit)    │
                                                                              └─────────▲──────────┘                    └──────────────────┘
                                                                                        │ retrieve
                                                                              ┌──────────────────┐
                                                                              │   rag-api          │
                                                                              │   Container App     │◀── client / channel
                                                                              │   (FastAPI)         │
                                                                              └──────────────────┘
```

Everything authenticates with **Entra ID managed identity** — no connection strings,
no API keys committed anywhere, no long-lived secrets in Key Vault that a pipeline has
to fetch. GitHub Actions authenticates to Azure via **OIDC workload identity
federation**. This is deliberate, not decorative: read `docs/decision-log.md` §Security.

## When to use which piece (read this before you copy the whole thing)

| Component | Use it when | Skip it when |
|---|---|---|
| Event Grid | ≥2 heterogeneous event sources/sinks need central routing, or you want Blob's native "blob created" push without polling | Single source → single consumer; a Storage Queue or direct Service Bus send is less to operate |
| Service Bus | You need ordering (sessions), dead-lettering with forensics, duplicate detection, or backpressure control independent of ingestion bursts | Throughput is low/steady and at-least-once with no ordering is fine — Event Grid → Function is enough |
| Container Apps + KEDA | You want Docker-native, scale-to-zero, event- or HTTP-driven compute with revision-based blue/green | You need custom schedulers, node pool isolation across many teams, or you already run AKS |
| AKS | Platform team already exists; you need GPU node pool multi-tenancy across many workloads | A single project's inference/RAG workload — this is usually over-engineering |
| Managed Online Endpoint (Azure ML / Foundry Hub) | You trained or fine-tuned the model yourself and need blue/green traffic splitting + built-in drift monitors | You're only calling a hosted foundation model via API — there's no "endpoint" to own |
| Foundry Agent Service (hosted agents) | The "model" is really a multi-step tool-using agent and you want built-in tracing/eval/governance without building it | You need full control of the orchestration loop, on-prem portability, or a framework Foundry doesn't host yet |
| Hand-rolled AI Search RAG (this template) | Custom chunking rules, multi-source fusion (Search + Cosmos + graph), document-level security trimming | Standard content types (SharePoint/OneLake) where Foundry IQ / agentic retrieval gets you there faster with less code |

## Repo layout

```
infra/                  Bicep IaC — one module per resource, composed in main.bicep
src/ingestion_function/ Blob-triggered Azure Function → validates + republishes as an Event Grid custom event
src/processing_worker/  Container App, Service Bus-triggered (KEDA) — chunk, embed, index, write metadata
src/rag_api/             Container App, FastAPI — hybrid+semantic retrieval from AI Search, generation via Foundry
mlops/                   Azure ML SDK v2 pipeline: train → evaluate → register → deploy to a managed online endpoint
.github/workflows/       CI (lint/test/build/push), infra CD (bicep what-if + deploy), app CD, model CD
azure-pipelines/         Azure DevOps equivalent of the GitHub Actions pipelines
docs/decision-log.md     The "why", trade-offs, and things to revisit
```

## Quick start

```bash
# 1. Provision infra (requires an Entra ID app registration federated for GitHub OIDC — see docs/decision-log.md)
az deployment sub create \
  --location eastus2 \
  --template-file infra/main.bicep \
  --parameters infra/main.parameters.json

# 2. Build & push the two container apps (see .github/workflows/app-ci.yml for the CI version)
az acr build --registry <acrName> --image processing-worker:latest src/processing_worker
az acr build --registry <acrName> --image rag-api:latest src/rag_api

# 3. Deploy an Azure Function for ingestion
func azure functionapp publish <functionAppName> --python

# 4. Point Container Apps at the new images (or just push to main and let app-cd.yml do it)
```

## What this template deliberately does NOT include

- A UI. Wire `rag_api`'s `/query` endpoint to Teams/Copilot Studio/your own front end.
- Fine-tuning code. `mlops/train.py` assumes you already have a training script; it wraps it for CI/CD.
- Network isolation (private endpoints/VNET injection). The Bicep is written so you can add it without restructuring — see `docs/decision-log.md` §Networking — but it's off by default so you can stand this up in an afternoon.
