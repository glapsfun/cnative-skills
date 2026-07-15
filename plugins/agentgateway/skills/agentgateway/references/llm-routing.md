# agentgateway LLM / AI Gateway Reference

## Two Configuration Modes

1. **`backends[].ai`** — attach an AI backend to a route like any other backend. Works with either config model (`binds` or `gateways`/`routes`), or a Kubernetes `AgentgatewayBackend`.
2. **`llm.models[]` / `llm.providers[]` / `llm.virtualModels[]`** — simplified, model-name-centric config, auto-served under standard OpenAI-shaped paths (`/v1/chat/completions`, `/v1/models`, etc). `llm.port`/`llm.tls` are deprecated in favor of `llm.gateways`.

```yaml
llm:
  port: 4000
  models:
  - name: smart
    provider: openAI
    params: { model: gpt-5.5, apiKey: $OPENAI_API_KEY }
  - name: anthropic/*
    provider: anthropic
    params: { apiKey: $ANTHROPIC_API_KEY }
    transformation:
      model: llmRequest.model.stripPrefix("anthropic/")
```

## Provider Union

Exactly one of `openAI`, `gemini`, `vertex`, `anthropic`, `bedrock`, `azure`, `copilot`, `custom`:

- **`azure`** — `resourceName`, `resourceType: openAI|foundry|aiServices`, `apiVersion`, `projectName` (Foundry only; builds path `/api/projects/{projectName}/openai/v1/...`).
- **`vertex`** — `region` (special values `global`/`us`/`eu` also accepted), `projectId`.
- **`bedrock`** — `region`, `guardrailIdentifier`, `guardrailVersion` (native Bedrock Guardrails hook).
- **`custom`** — `providerOverride` (identity used for cost-catalog lookups/telemetry), `formats[]` with `type: completions|messages|responses|embeddings|anthropicTokenCount|realtime|rerank` and optional per-format `path`. This is how you point at any OpenAI-compatible endpoint — Ollama, vLLM, Groq, DeepSeek, Together AI, OpenRouter, xAI — or a Kubernetes Gateway API Inference Extension `InferencePool`.

Docs list first-class provider pages for OpenAI, Bedrock, Anthropic, Azure, Gemini, Ollama, Vertex AI, Baseten, Cerebras, Cohere, DeepInfra, DeepSeek, Fireworks AI, Groq, Hugging Face, Mistral, OpenRouter, Together AI, xAI, plus generic "Custom" and "OpenAI-compatible providers" pages — check the docs page for the exact provider before hand-writing a `custom` block, since a first-class entry may already exist.

## Virtual Models — the Distinctive Feature

Publish one client-facing model name that dynamically routes to real `llm.models` entries via exactly one strategy per virtual model:

- **`routing.weighted.targets[]: {model, weight}`** — weighted load balancing across models (e.g. cost/quality tradeoffs, canarying a new model).
- **`routing.failover.targets[]: {model, priority}`** — priority tiers; degrades to the next tier if every model in the current tier is unhealthy (health/latency composite score).
- **`routing.conditional.targets[]: {when: <CEL>, model}`** — first matching CEL expression wins, evaluated in declaration order (content-based routing — e.g. route by prompt length, header, or user tier).

```yaml
llm:
  models:
  - { name: cheap-model, provider: openAI, params: { model: gpt-5-mini, apiKey: $OPENAI_API_KEY } }
  - { name: smart-model, provider: openAI, params: { model: gpt-5.5, apiKey: $OPENAI_API_KEY } }
  virtualModels:
  - name: default
    routing:
      weighted:
        targets:
        - { model: cheap-model, weight: 90 }
        - { model: smart-model, weight: 10 }
```

`llm.models[].visibility: public|internal` — set `internal` to hide a model from direct client requests so it's reachable only through a `virtualModel`. `llm.models[].authorization.rules[]` gives per-model CEL RBAC (same rule shape as the generic `authorization` policy).

## Cost Tracking

`config.modelCatalog[]` merges cost catalog sources (a `file`, or inline `providers`) — load with `agctl costs import` or reference directly in config. Once loaded, CEL exposes `llm.cost.{total,input,output,cacheRead,cacheWrite,reasoning,...}` and `llm.costRates.*` (USD per 1M tokens), usable in dashboards, logs, or rate-limit cost expressions (see `references/security.md` for token-cost rate limiting).

## CEL Telemetry Surface

Available wherever policies run on LLM traffic: `llm.{requestModel,responseModel,provider,streaming,inputTokens,outputTokens,totalTokens,cachedInputTokens,reasoningTokens,timeToFirstToken,timePerOutputToken,prompt[],completion[],params.*}`. `llmRequest` (the raw pre-processed request) is additionally visible during the LLM policy phase specifically.

## In-Progress / Evolving

A design doc in the repo (`design/288-inferencepool-ai-policies.md`) proposes a `custom` LLM provider variant with a `backendRef` targeting a Kubernetes `Service` or Gateway API Inference Extension `InferencePool`, so AI policies (token counting, prompt guards, rate limits) can apply to self-hosted-model traffic that also goes through Endpoint Picker (EPP) inference routing. Treat this as evidence the provider/backend model is still actively evolving — check the design doc's `Status:` field and the installed version's release notes before assuming a specific shape is shipped.
