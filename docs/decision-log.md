# Decision Log

Dated entries. Re-validate anything older than ~2 quarters against Microsoft Learn —
this stack (Foundry especially) changes monthly.

## 2026-Q3 — Platform naming
Azure AI Foundry was renamed **Microsoft Foundry** (lineage: Azure AI Studio → Azure AI
Foundry → Microsoft Foundry). Prompt Flow was retired 2026-04-30. The replacement is
**Microsoft Agent Framework 1.0** (GA, .NET + Python) for orchestration, plus **Foundry
Agent Service** for hosted agents with built-in tracing/eval (GA'd out of the Build 2026
announcements) via the **Foundry Control Plane**. `azure-ai-projects` 2.2.x is the
current SDK generation. If you find yourself reaching for a Prompt Flow tutorial,
stop and look for the Agent Framework equivalent instead.

## Why Event Grid *and* Service Bus, not one or the other
They solve different problems and the template uses both on purpose:
- **Event Grid** is push-based pub/sub with native Blob Storage integration (the
  storage account emits a `Microsoft.Storage.BlobCreated` event with no polling) and
  first-class *routing/filtering* to many heterogeneous subscribers. It does not give
  you ordering guarantees, sessions, or rich dead-letter forensics.
- **Service Bus** gives you ordered processing within a session, duplicate detection,
  a real dead-letter queue you can inspect and replay, and — critically — a queue
  depth that KEDA can scale Container Apps against, which decouples ingestion bursts
  from processing capacity.
- The combination: Event Grid decides *what gets processed and where it's routed*,
  Service Bus decides *how reliably it gets processed*. For a single source → single
  consumer pipeline this is two hops more than you need — collapse to Event Grid →
  Storage Queue → Function, or Event Grid → Service Bus directly, and skip the extra
  topic if you don't have multiple event producers.

## Why Container Apps over AKS for this template
Container Apps gives KEDA-based event scaling, scale-to-zero, Dapr, and revision-based
blue/green out of the box with no cluster to patch. AKS is the right call when a
platform team already owns a cluster serving many workloads, or you need node-pool
level GPU multi-tenancy across teams. For one project's RAG/inference workload, AKS is
usually paying operational tax for control you don't need yet.

## Why the RAG pipeline is hand-rolled instead of Foundry IQ / agentic retrieval
Azure AI Search's **agentic retrieval** (query planning + retrieval + L2 semantic
reranking, orchestrated by the search service itself against an LLM) and **Foundry IQ**
(knowledge bases grounding agents over MCP against sources like OneLake/SharePoint) are
real "buy vs. build" alternatives to everything in `processing_worker/` and
`rag_api/retriever.py`. Reach for them when your content already lives in a supported
source and you want less code to own. This template hand-rolls chunking, embedding,
and hybrid+semantic queries because: (a) it's the transferable skill the rest of this
roadmap is teaching, (b) it supports arbitrary sources and custom chunking/business
rules, and (c) it supports multi-source fusion (Search + Cosmos DB metadata + a graph
store) that a single knowledge source can't. Re-evaluate per project — don't build this
by default once your content is fully inside a Foundry-IQ-supported source.

## Security: zero standing secrets
- GitHub Actions → Azure: **OIDC workload identity federation** on the App
  Registration, not a service principal password or publish profile.
- Container Apps → Key Vault / Cosmos DB / AI Search / Service Bus / Storage: **user-
  assigned managed identity** with least-privilege RBAC role assignments (`infra/modules/identity.bicep`), not connection strings.
- KEDA's Service Bus scaler authenticates via managed identity (`identity` trigger auth), not a shared access key.
- The only thing that should ever be a "secret" in this template is a third-party API
  key you don't control (e.g. a non-Azure model provider) — and that goes in Key
  Vault with RBAC, referenced by the Container App's secret ref, never in an env var
  literal or a workflow file.

## Networking (off by default)
No private endpoints / VNET injection in the base template — it's meant to stand up in
an afternoon. Before this touches real data: add a Container Apps environment with
`vnetConfiguration.internal = true`, private endpoints for Storage/Cosmos/AI Search/Key
Vault, and disable public network access on each resource. The Bicep modules already
take a `vnetSubnetId` optional parameter as a placeholder for this.

## MLOps vs. LLMOps — two different pipelines, don't conflate them
- **You own model weights** (fine-tuned/custom-trained): classic MLOps —
  `mlops/train.py` → `evaluate.py` (gate) → `register_model.py` → `deploy_endpoint.py`
  to a managed online endpoint with traffic-split canary. Retraining is a real event
  with a real artifact (a model version).
- **You call a hosted foundation model** (Foundry catalog / Azure OpenAI): this is
  LLMOps, not MLOps — there's no model to retrain. What you version and gate instead
  is the *app around the model*: prompts/agent definitions, retrieval config, and eval
  scores (groundedness, relevance, safety) computed against a fixed test set. That's
  `app-cd.yml`, not `model-cd.yml`. Don't build a training pipeline you don't need.

## Certifications, if you want external checkpoints
AZ-305 (architect) and AZ-400 (DevOps) cover the infra/CI-CD half of this template well
and don't go stale fast. AI-102 and DP-100 are useful for the AI/ML half but their
official curricula lag the Foundry rename/Agent Framework GA by a few months at any
given time — cross-check the exam skills-measured PDF against Microsoft Learn's current
Foundry docs before trusting a study guide older than ~3 months.
