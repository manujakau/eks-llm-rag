from fastapi import FastAPI

app = FastAPI(title="RAG API")

@app.get("/")
async def root():
    return {"message": "RAG API is running"}

@app.get("/health")
async def health():
    return {"status": "healthy"}
