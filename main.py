# pyrefly: ignore [missing-import]
import os
from fastapi import FastAPI
import uvicorn

app = FastAPI()

@app.get('/')
def read_root():
    return {"Hello": "World"}

if __name__ == "__main__":
    # Look for Cloud Run's default port, fallback to 8080
    port = int(os.environ.get("PORT", 8080))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)

# procfile: web: uvicorn main:app --host 0.0.0.0 --port 8080
