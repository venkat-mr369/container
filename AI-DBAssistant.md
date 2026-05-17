## AI DB Assistant — Hands-On Learning Guide (Podman on Windows)

> Short answer to your question: **YES** — every component in the architecture diagram can run on your Windows laptop with Podman 5.8.1. You do not need cloud, GPU, or paid APIs to learn the whole stack end-to-end. API keys are only needed later if you want to swap the local TinyLlama for GPT-4o or Gemini.

---

## 1. What you will build (mapped to your diagram)

| # | Diagram block | What you'll actually run |
|---|---|---|
| 1 | Streamlit Web UI | `streamlit` Python app |
| 2 | FastAPI Backend + Tool endpoints | `uvicorn` Python app |
| 3 | MCP Server / Agent Pool | LangGraph agents (Python) |
| 4 | LLM Services (TinyLlama, GPT-4o, Gemini) | Ollama container locally; APIs optional |
| 5 | Vector DB (Qdrant) | `qdrant/qdrant` container |
| 6 | Databases / Data Sources | PostgreSQL **or** CockroachDB **or** YugabyteDB **or** ScyllaDB container |
| 7 | Other Systems (ITSM / DevOps / Chat) | Mock locally first; integrate Jira / Slack later |
| 8 | Embedding Model (Nomic) | `nomic-embed-text` via Ollama |
| 9 | Knowledge Store (Runbooks, SOPs, Cases) | Markdown / PDF files indexed into Qdrant |

---

## 2. Prerequisites

You already have:
- Podman 5.8.1 ✅
- A clean container list ✅

Also install on Windows:
- Python 3.11+ — https://python.org
- VS Code (recommended)
- Git
- (Optional) DBeaver or pgAdmin to browse the DB visually
- (Optional) `pip install podman-compose` once Python is installed — Compose files beat long CLI flags

---

## 3. Phase 0 — One-time network setup

Containers can only talk to each other by name if they share a Podman network.

```bat
podman network create aidb-net
podman network ls
```

That's it. Every container below joins `aidb-net`.

> **Windows cmd note:** Multi-line commands below use `^` for line continuation (cmd syntax). In PowerShell use a backtick `` ` ``; in WSL bash use `\`.

---

## 4. Phase 1 — Pick a database

You do not need all four. Suggested order:

1. **PostgreSQL** — easiest, most docs, biggest ecosystem.
2. **CockroachDB** — speaks the Postgres wire protocol, so your code barely changes. Teaches distributed SQL.
3. **YugabyteDB** — Postgres-compat YSQL **and** a Cassandra-compat YCQL API on the same engine.
4. **ScyllaDB** — pure NoSQL wide-column, very different mental model.

### 4A. PostgreSQL

```bat
podman volume create pgdata

podman run -d --name postgres-db --network aidb-net ^
  -e POSTGRES_PASSWORD=mypassword ^
  -e POSTGRES_USER=admin ^
  -e POSTGRES_DB=testdb ^
  -p 5432:5432 ^
  -v pgdata:/var/lib/postgresql/data ^
  docker.io/postgres:16

podman logs -f postgres-db
```

Connect:
```bat
podman exec -it postgres-db psql -U admin -d testdb
```

Inside `psql`, enable the stats extension your "Top SQL Activity" tool will read from:
```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```
(You'll also need to add `shared_preload_libraries = 'pg_stat_statements'` in `postgresql.conf` and restart — covered in the troubleshooting section.)

**What to learn here:** `pg_stat_statements`, `EXPLAIN (ANALYZE, BUFFERS)`, `pg_stat_activity`, `pg_indexes`, `pg_stat_user_tables`. These are exactly what the **Top SQL / Explain Plan / Index Advisor / Capacity Forecast** tools in your diagram wrap.

Load sample data (DVD Rental schema is excellent):
- https://www.postgresqltutorial.com/postgresql-getting-started/postgresql-sample-database/

### 4B. CockroachDB (single-node, insecure — DEV ONLY)

```bat
podman volume create cockroach-data

podman run -d --name cockroach --network aidb-net ^
  -p 26257:26257 -p 8081:8080 ^
  -v cockroach-data:/cockroach/cockroach-data ^
  docker.io/cockroachdb/cockroach:latest ^
  start-single-node --insecure
```

- SQL shell: `podman exec -it cockroach ./cockroach sql --insecure`
- Admin UI: http://localhost:8081

**What to learn:** ranges, replication factor, `AS OF SYSTEM TIME`, distributed `EXPLAIN`, `SHOW RANGES`. Almost every Postgres query you wrote in 4A works unchanged.

### 4C. YugabyteDB

```bat
podman volume create yb-data

podman run -d --name yugabyte --network aidb-net ^
  -p 7000:7000 -p 9000:9000 -p 5433:5433 -p 9042:9042 ^
  -v yb-data:/home/yugabyte/yb_data ^
  docker.io/yugabytedb/yugabyte:latest ^
  bin/yugabyted start --daemon=false
```

- YSQL (Postgres-compatible) port: **5433**
- YCQL (Cassandra-compatible) port: **9042**
- Admin UI: http://localhost:7000

> If you also run ScyllaDB (next section), port **9042 will clash** — remap one of them.

YSQL shell:
```bat
podman exec -it yugabyte ysqlsh -h yugabyte
```

### 4D. ScyllaDB

```bat
podman run -d --name scylla --network aidb-net ^
  -p 9043:9042 ^
  docker.io/scylladb/scylla:latest ^
  --smp 1 --memory 750M --overprovisioned 1
```

Note: host port remapped to **9043** to avoid clashing with YugabyteDB's YCQL on 9042.

CQL shell:
```bat
podman exec -it scylla cqlsh
```

**What to learn:** keyspaces, partition keys, clustering keys, no JOINs, denormalized modeling, `nodetool`.

---

## 5. Phase 2 — Vector Database (Qdrant)

This is your RAG store for runbooks, SOPs, historical incidents, and SQL-script snippets.

```bat
podman volume create qdrant_storage

podman run -d --name qdrant --network aidb-net ^
  -p 6333:6333 -p 6334:6334 ^
  -v qdrant_storage:/qdrant/storage ^
  docker.io/qdrant/qdrant
```

- Dashboard: http://localhost:6333/dashboard
- Python client: `pip install qdrant-client`

---

## 6. Phase 3 — Local LLM + Embedding Model (Ollama)

One container gives you both the chat model **and** the embedding model.

```bat
podman volume create ollama

podman run -d --name ollama --network aidb-net ^
  -p 11434:11434 ^
  -v ollama:/root/.ollama ^
  docker.io/ollama/ollama
```

Pull the models (one-time download, ~1–3 GB each):
```bat
podman exec -it ollama ollama pull tinyllama
podman exec -it ollama ollama pull llama3.2:1b
podman exec -it ollama ollama pull nomic-embed-text
```

> `llama3.2:1b` is noticeably smarter than TinyLlama and still small enough for a laptop. Use TinyLlama only if your machine is very memory-constrained.

Test it:
```bat
curl http://localhost:11434/api/generate -d "{\"model\":\"llama3.2:1b\",\"prompt\":\"hello\",\"stream\":false}"
```

---

## 7. Phase 4 — FastAPI Backend (the tool endpoints)

Now write Python on your **host** (faster iteration). Containerize it later.

```bat
mkdir aidb-assistant
cd aidb-assistant
python -m venv .venv
.venv\Scripts\activate
pip install fastapi uvicorn "psycopg[binary]" qdrant-client langgraph langchain langchain-ollama requests python-dotenv
```

Minimal `main.py`:
```python
from fastapi import FastAPI
import psycopg

app = FastAPI()
CONN = "host=localhost port=5432 dbname=testdb user=admin password=mypassword"

@app.get("/tools/top-sql")
def top_sql():
    with psycopg.connect(CONN) as c, c.cursor() as cur:
        cur.execute("""
            SELECT query, calls, mean_exec_time
            FROM pg_stat_statements
            ORDER BY mean_exec_time DESC
            LIMIT 10
        """)
        return [
            {"query": q, "calls": n, "ms": float(t)}
            for q, n, t in cur.fetchall()
        ]

@app.get("/tools/explain")
def explain(sql: str):
    with psycopg.connect(CONN) as c, c.cursor() as cur:
        cur.execute("EXPLAIN (ANALYZE, FORMAT JSON) " + sql)
        return cur.fetchone()[0]

@app.get("/tools/active-sessions")
def active_sessions():
    with psycopg.connect(CONN) as c, c.cursor() as cur:
        cur.execute("""
            SELECT pid, usename, state, query, now()-query_start AS runtime
            FROM pg_stat_activity
            WHERE state != 'idle'
        """)
        cols = [d[0] for d in cur.description]
        return [dict(zip(cols, row)) for row in cur.fetchall()]
```

Run:
```bat
uvicorn main:app --reload --port 8000
```

Test in your browser: http://localhost:8000/tools/top-sql

Add one tool per study session: index-advisor, capacity-forecast, deployment-runner, lock-monitor, etc. Each tool is just one FastAPI route hitting the DB or a metrics source.

---

## 8. Phase 5 — Agent / MCP layer with LangGraph

A "planner" agent receives a natural-language question, decides which tool to call, and aggregates results.

```python
from langchain_ollama import ChatOllama
from langgraph.prebuilt import create_react_agent
import requests

llm = ChatOllama(model="llama3.2:1b", base_url="http://localhost:11434")

def get_top_sql() -> str:
    """Return the 10 slowest SQL statements in the database."""
    return str(requests.get("http://localhost:8000/tools/top-sql").json())

def explain_sql(sql: str) -> str:
    """Return the EXPLAIN ANALYZE plan for a given SQL statement."""
    r = requests.get("http://localhost:8000/tools/explain", params={"sql": sql})
    return str(r.json())

agent = create_react_agent(llm, [get_top_sql, explain_sql])

result = agent.invoke({
    "messages": [("user", "Show me the slowest queries and explain the top one")]
})
print(result["messages"][-1].content)
```

This is the equivalent of the **MCP Server / Agent Pool** in your diagram — Planner + tool loop. As you add more agents (SQL Review Agent, Plan Analysis Agent, Knowledge Agent, Capacity Agent, Deployment Agent — exactly what your diagram shows), give each one a small focused tool list and a system prompt describing its role.

---

## 9. Phase 6 — RAG over Runbooks / SOPs / Historical Cases

```python
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct
from langchain_ollama import OllamaEmbeddings
import uuid, glob

embed = OllamaEmbeddings(model="nomic-embed-text", base_url="http://localhost:11434")
qdrant = QdrantClient(host="localhost", port=6333)

# One-time: create collection (nomic-embed-text outputs 768-dim vectors)
qdrant.recreate_collection(
    collection_name="runbooks",
    vectors_config=VectorParams(size=768, distance=Distance.COSINE),
)

# Index every .md file in ./runbooks/
for path in glob.glob("runbooks/*.md"):
    text = open(path, encoding="utf-8").read()
    vec = embed.embed_query(text)
    qdrant.upsert(
        collection_name="runbooks",
        points=[PointStruct(
            id=str(uuid.uuid4()),
            vector=vec,
            payload={"source": path, "text": text},
        )],
    )

# Query
hits = qdrant.search(
    collection_name="runbooks",
    query_vector=embed.embed_query("query is slow, what do I do?"),
    limit=3,
)
for h in hits:
    print(h.score, h.payload["source"])
```

Feed the retrieved `hits` text into the agent's prompt as context — that's RAG, exactly like block 9 in your diagram.

---

## 10. Phase 7 — Streamlit Frontend

```bat
pip install streamlit
```

`app.py`:
```python
import streamlit as st
import requests

st.set_page_config(page_title="AI DB Assistant", layout="wide")
st.title("🤖 AI DB Assistant")

if "history" not in st.session_state:
    st.session_state.history = []

q = st.chat_input("Ask a question about your database…")
if q:
    st.session_state.history.append(("user", q))
    r = requests.post("http://localhost:8000/agent", json={"question": q})
    st.session_state.history.append(("assistant", r.json().get("answer", "(no answer)")))

for role, msg in st.session_state.history:
    with st.chat_message(role):
        st.write(msg)
```

Run:
```bat
streamlit run app.py
```

You'll need a `POST /agent` route on the FastAPI side that invokes the LangGraph agent from Phase 5.

---

## 11. Suggested learning order (8 weekends)

| Week | Goal |
|------|------|
| 1 | Podman basics; Postgres container; load DVD Rental sample DB; learn `EXPLAIN ANALYZE` and `pg_stat_statements`. |
| 2 | Build 3 FastAPI tool endpoints: `top-sql`, `explain`, `active-sessions`. |
| 3 | Add Qdrant; index 5 markdown runbooks; write a similarity-search test. |
| 4 | Add Ollama; build a single-tool LangGraph agent. |
| 5 | Multi-tool agent + planner + result aggregation; add a Knowledge Agent that uses RAG. |
| 6 | Streamlit UI + chat history + file upload (drag in a runbook → auto-index). |
| 7 | Swap Postgres for CockroachDB; fix whatever breaks (usually nothing). |
| 8 | Add YugabyteDB or ScyllaDB as a second backend; route tools per-database. |

---

## 12. Useful Podman commands (Windows)

```bat
podman ps -a                       :: list all containers
podman logs <name>                 :: see container output
podman logs -f <name>              :: follow logs (Ctrl+C to exit)
podman exec -it <name> bash        :: shell into container
podman stop <name>                 :: stop
podman rm <name>                   :: remove
podman volume ls                   :: list volumes
podman network inspect aidb-net    :: see who's on the network
podman stats                       :: live CPU / memory usage
podman system prune                :: clean up stopped containers, dangling images
```

---

## 13. Troubleshooting (Windows + Podman gotchas)

- **Port already in use** → change the host side of the mapping, e.g. `-p 15432:5432`.
- **Container exits immediately** → `podman logs <name>` always reveals the reason.
- **Containers can't reach each other** → confirm both joined `aidb-net`. Inside a container, use the **container name** as the hostname (e.g. `host=postgres-db` not `localhost`).
- **`pg_stat_statements` returns "relation does not exist"** → it needs to be in `shared_preload_libraries`. Easiest fix: pass it on startup:
  ```bat
  podman run -d --name postgres-db --network aidb-net ^
    -e POSTGRES_PASSWORD=mypassword -e POSTGRES_USER=admin -e POSTGRES_DB=testdb ^
    -p 5432:5432 -v pgdata:/var/lib/postgresql/data ^
    docker.io/postgres:16 ^
    -c shared_preload_libraries=pg_stat_statements
  ```
  Then `CREATE EXTENSION pg_stat_statements;` inside `testdb`.
- **Windows volume bind-mounts behave oddly** → prefer **named volumes** (`-v pgdata:/var/lib/postgresql/data`) over bind-mounts (`-v C:\foo:/var/lib/postgresql/data`).
- **Out of memory** (Scylla / Yugabyte are hungry) → give your WSL VM more RAM by creating `%UserProfile%\.wslconfig`:
  ```
  [wsl2]
  memory=8GB
  processors=4
  ```
  Then `wsl --shutdown` and reopen Podman.
- **Pulling images is slow / blocked** → behind a corporate proxy, set `HTTPS_PROXY` for the podman machine: `podman machine ssh` then edit `/etc/environment`.

---

## 14. Resources

- PostgreSQL — https://www.postgresql.org/docs/
- CockroachDB — https://www.cockroachlabs.com/docs/
- YugabyteDB — https://docs.yugabyte.com/
- ScyllaDB — https://docs.scylladb.com/
- Qdrant — https://qdrant.tech/documentation/
- Ollama — https://ollama.com/
- LangGraph — https://langchain-ai.github.io/langgraph/
- FastAPI — https://fastapi.tiangolo.com/
- Streamlit — https://docs.streamlit.io/
- Podman on Windows — https://podman.io/docs/installation#windows

---

## 15. After the MVP — where to go next

- **Containerize FastAPI + Streamlit** with a `Containerfile` and run the whole stack from a `podman-compose.yml`.
- **Add observability**: Prometheus + Grafana containers scraping Postgres exporter.
- **Add a second LLM** via OpenAI / Gemini API and route easy questions to TinyLlama, hard ones to GPT-4o (cost optimization, just like the diagram shows).
- **Connect a real ticketing system**: ServiceNow or Jira API, so the agent can open / update tickets.
- **Production hardening**: TLS, secrets, RBAC on the Streamlit UI, audit log everything (your diagram already calls this out: "All actions are controlled, logged and auditable").
