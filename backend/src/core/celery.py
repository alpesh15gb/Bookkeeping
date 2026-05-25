"""
Celery configuration for background tasks.
"""
import os
from celery import Celery
from src.core.config import settings

# Broker and backend from environment or default to Redis
broker_url = os.getenv("CELERY_BROKER_URL", settings.REDIS_URL)
result_backend = os.getenv("CELERY_RESULT_BACKEND", settings.REDIS_URL)

celery_app = Celery(
    "bookkeeping",
    broker=broker_url,
    backend=result_backend,
    include=[
        "src.workers.tasks"
    ]
)

# Optional configuration
celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,
    task_track_started=True,
    task_time_limit=30 * 60,  # 30 minutes
    worker_prefetch_multiplier=1,
    task_acks_late=True,
)