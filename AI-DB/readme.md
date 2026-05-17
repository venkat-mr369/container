
#### Every block in that diagram (Streamlit, FastAPI, MCP/agents, Qdrant, LLM, embeddings, and the database itself) runs as a Podman container. TinyLlama and `nomic-embed-text` run on CPU, so no GPU needed. You only need API keys if you later want to call GPT-4o or Gemini — for learning, fully local is enough.

I've put the full step-by-step guide into a markdown file you can save, follow, and tick off as you go. Quick preview of what's inside:

**Architecture mapping** — each diagram block → which container/library handles it.

**8-phase build path**, with copy-paste Podman commands (Windows `cmd` syntax, since that's what you're on):
- Phase 0 — Create the shared network `aidb-net`
- Phase 1 — Pick a database: **PostgreSQL** → **CockroachDB** → **YugabyteDB** → **ScyllaDB** (recommended order; each container command included)
- Phase 2 — Qdrant (vector DB)
- Phase 3 — Ollama (TinyLlama + `nomic-embed-text` in one container)
- Phase 4 — FastAPI backend with starter tool endpoints (`/tools/top-sql`, `/tools/explain`)
- Phase 5 — LangGraph agent that calls those tools
- Phase 6 — RAG over runbooks via Qdrant + Ollama embeddings
- Phase 7 — Streamlit UI

**8-weekend learning timeline** so you don't try to do it all at once.

**Troubleshooting section** for the Windows + Podman gotchas (port clashes between YugabyteDB CQL and ScyllaDB on 9042, volume mount quirks, WSL memory).

**Why this order matters:** PostgreSQL first because every "DB tool" in your diagram (Top SQL, Explain Plan Analyzer, Index Advisor, Capacity Forecast) maps directly to Postgres internals (`pg_stat_statements`, `EXPLAIN ANALYZE`, `pg_stat_activity`, `pg_indexes`). Once you've built tools against Postgres, moving to CockroachDB is almost free — it speaks the same wire protocol. YugabyteDB and ScyllaDB then teach you distributed SQL and wide-column NoSQL mental models respectively.**Start tonight with just 4 commands** (the absolute minimum to feel it working):

```bat
podman network create aidb-net

podman run -d --name postgres-db --network aidb-net -e POSTGRES_PASSWORD=mypassword -e POSTGRES_USER=admin -e POSTGRES_DB=testdb -p 5432:5432 docker.io/postgres:16

podman run -d --name qdrant --network aidb-net -p 6333:6333 docker.io/qdrant/qdrant

podman run -d --name ollama --network aidb-net -p 11434:11434 docker.io/ollama/ollama
```

<img width="1372" height="840" alt="image" src="https://github.com/user-attachments/assets/7880bce5-938f-4304-ab01-34c51a92507e" />


1. The browser hits **Streamlit → FastAPI** over HTTPS. That's your only inbound edge.
2. **FastAPI → LLM services**: any direct chat completions (planning prompts, summarisation). Same backend is also the only thing holding the LLM API keys.
3. **FastAPI → MCP server**: the backend hands the question to the agent layer. The MCP server (LangGraph) runs the planner-and-tools loop.
4. From the agent layer, four edges fan out:
   - **→ Qdrant** for vector / similarity search (RAG).
   - **↑ Knowledge store** feeds context up into the agents (runbooks, SOPs, past cases the planner needs as evidence).
   - **↓ Databases** is where actual SQL/CQL runs (Postgres, CockroachDB, YugabyteDB, ScyllaDB).
   - **↘ Other systems** for the optional integrations — open a Jira ticket, post to Slack, trigger CI/CD.
5. **Embedding model → Knowledge store**: nomic-embed-text turns your markdown runbooks into vectors before they're indexed in Qdrant.

**Two-color legend, on purpose** — blue is everything you write code for (UI, backend, agents); teal is everything that's a service, store, or external system you talk to. When you build this in Podman, every teal box is a container you `podman run`; every blue box is a Python process you run on the host (until you containerize them in week 8).

Want me to also draw a second, **runtime sequence** version — the same boxes but with numbered steps showing what happens when a user types "why is my query slow?" all the way through to the answer? That one tends to make the agent loop click faster than the architecture view.

Then `podman ps` should show 3 running containers. That's your entire AI DB Assistant backend infrastructure — DB + vector store + LLM host — in about 5 minutes. Everything in the guide builds on top of these three.

Which database do you want to start with — PostgreSQL, or jump straight to one of the distributed ones (Cockroach / Yugabyte / Scylla)? I can help you go deeper on whichever you pick, including loading sample data and writing your first tool endpoint.
