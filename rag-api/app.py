import os, uuid
import httpx
import openai
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from openai import OpenAI
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel, Field
from qdrant_client import QdrantClient
from qdrant_client.models import (Distance, FieldCondition, Filter, FilterSelector, MatchValue,
                                  PointStruct, VectorParams)

QDRANT_URL = os.getenv("QDRANT_URL", "http://qdrant.rag:6333")
TEI_URL = os.getenv("TEI_URL", "http://tei.llm:8080")
VLLM_URL = os.getenv("VLLM_URL", "http://vllm.llm:8000/v1")
MODEL = os.getenv("MODEL", "qwen3-4b")              # vLLM --served-model-name
COLLECTION = os.getenv("COLLECTION", "docs")        # vector size comes from TEI's output, not a constant

app = FastAPI(title="rag-api")
# serves /metrics; per-handler latency buckets reach 60 s (default stops at 1 s, which caps /ask's p95)
Instrumentator().instrument(
    app, latency_lowr_buckets=(0.1, 0.25, 0.5, 1, 2, 5, 10, 20, 30, 60)).expose(app)
qdrant = QdrantClient(url=QDRANT_URL)
# no retries: one 25 s attempt stays under API Gateway's 29 s; the SDK's default 2 retries would not
llm = OpenAI(base_url=VLLM_URL, api_key="not-needed", timeout=25, max_retries=0)
http = httpx.Client(timeout=30)


class Doc(BaseModel):
    source: str = Field(min_length=1)
    text: str = Field(min_length=1)


class Question(BaseModel):
    question: str = Field(min_length=1)
    top_k: int = Field(4, ge=1, le=20)


def chunk(text: str, size: int = 800, overlap: int = 100) -> list[str]:
    return [text[i:i + size] for i in range(0, len(text), size - overlap)]


def embed(texts: list[str]) -> list[list[float]]:
    out = []
    for i in range(0, len(texts), 32):              # TEI's default --max-client-batch-size
        r = http.post(f"{TEI_URL}/embed", json={"inputs": texts[i:i + 32], "truncate": True})
        r.raise_for_status()
        out.extend(r.json())
    return out


def ensure_collection(dim: int) -> None:
    if qdrant.collection_exists(COLLECTION):
        return
    try:
        qdrant.create_collection(COLLECTION, vectors_config=VectorParams(size=dim, distance=Distance.COSINE))
    except Exception:
        if not qdrant.collection_exists(COLLECTION):  # another worker or replica created it first
            raise


# vLLM is paused overnight (scaled to 0) and TEI can be restarting; report that instead of a bare 500
@app.exception_handler(openai.APITimeoutError)
def llm_timeout(_: Request, e: Exception):
    return JSONResponse(status_code=504, content={"detail": "LLM timed out"})


@app.exception_handler(openai.APIConnectionError)
def llm_unavailable(_: Request, e: Exception):
    return JSONResponse(status_code=503, content={"detail": "LLM unavailable (vLLM may be paused or starting)"})


@app.exception_handler(httpx.HTTPError)
def embedder_error(_: Request, e: Exception):
    return JSONResponse(status_code=502, content={"detail": f"embedding service error ({type(e).__name__})"})


@app.get("/health")
def health():
    return {"status": "healthy"}


@app.post("/ingest")
def ingest(docs: list[Doc]):
    total = 0
    for d in docs:
        pieces = chunk(d.text)
        vectors = embed(pieces)
        ensure_collection(len(vectors[0]))
        # re-ingesting a source replaces its chunks instead of duplicating them
        qdrant.delete(COLLECTION, points_selector=FilterSelector(filter=Filter(
            must=[FieldCondition(key="source", match=MatchValue(value=d.source))])))
        qdrant.upsert(COLLECTION, points=[
            PointStruct(id=str(uuid.uuid4()), vector=vec, payload={"source": d.source, "text": piece})
            for piece, vec in zip(pieces, vectors, strict=True)])
        total += len(pieces)
    return {"chunks": total}


@app.post("/ask")
def ask(q: Question):
    if not qdrant.collection_exists(COLLECTION):
        raise HTTPException(404, "no documents ingested yet; POST /ingest first")
    hits = qdrant.query_points(COLLECTION, query=embed([q.question])[0], limit=q.top_k).points
    context = "\n\n".join(f"[{i + 1}] {h.payload['text']}" for i, h in enumerate(hits))
    resp = llm.chat.completions.create(
        model=MODEL, max_tokens=300, temperature=0.2,
        messages=[
            {"role": "system", "content": "Answer only from the context. Cite like [1]. "
                                          "If the context lacks the answer, say so."},
            {"role": "user", "content": f"Context:\n{context}\n\nQuestion: {q.question}"},
        ],
    )
    return {"answer": resp.choices[0].message.content,
            "sources": [h.payload["source"] for h in hits],     # sources[n-1] is citation [n]
            "usage": resp.usage.model_dump() if resp.usage else None}  # log this per caller for chargeback
