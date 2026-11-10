"""Entrypoint for serverless hosts such as Vercel (they look for a module-level `app`)."""
from app.main import app  # noqa: F401
