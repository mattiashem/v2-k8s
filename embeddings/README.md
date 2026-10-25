# embeddings

In-cluster embedding service for the openclaw agents' memory search (dobby + zoe).

openclaw's memory (`memory-core`: MEMORY.md, memory files, dreaming) needs an embedding
model to build and query its vector index. Both agents used Gemini embeddings, which
share the Google project's monthly spend cap: when the cap is hit, chat falls back to
Claude but memory indexing simply stops. This runs the embeddings locally instead — free,
no external dependency, and memory content never leaves the house.

- Image `ollama/ollama` (pinned), model `embeddinggemma:300m` (multilingual, 768 dims).
- Model is pulled by an init container into an `emptyDir`, so the pod can come back on
  any node. Kept off `node1` (pod cap); prefers `node2`/`node3`.
- `OLLAMA_KEEP_ALIVE=-1` keeps the model loaded, so lookups don't pay a cold load.
- ClusterIP only: `http://ollama-embed.embeddings.svc.cluster.local:11434`.

## openclaw wiring

The agent config lives on each instance's PVC (`openclaw.json`), not in git:

```json
"memory": { "search": {
  "provider": "ollama",
  "model": "embeddinggemma:300m",
  "remote": { "baseUrl": "http://ollama-embed.embeddings.svc.cluster.local:11434" },
  "fallback": "none"
} }
```

Changing the embedding model changes the vector dimensions, so after switching run a
full reindex on each instance: `openclaw memory status --index --agent main`.

## Deploy

ArgoCD app `core/embeddings.yaml` (manual sync, like every app here).

```bash
curl -s http://ollama-embed.embeddings.svc.cluster.local:11434/api/embed \
  -d '{"model":"embeddinggemma:300m","input":"hej"}'   # from inside the cluster
```
