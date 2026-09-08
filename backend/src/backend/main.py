from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

from backend.api.router import api_router
from backend.database import init_db


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifecycle event handler initializing database schemas on startup."""
    init_db()
    yield


app = FastAPI(
    title="Chapter2 Migration Protocol API",
    description="Backend service providing automated participant snapshotting, Merkle proof distribution, and gasless claim relaying.",
    version="0.1.0",
    lifespan=lifespan,
)

# Enable CORS for frontend applications
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router)


def main():
    """CLI entrypoint for running the backend service via uvicorn."""
    uvicorn.run("backend.main:app", host="0.0.0.0", port=8000, reload=True)


if __name__ == "__main__":
    main()
