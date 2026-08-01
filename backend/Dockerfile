# ── Stage 1: Build dependencies ─────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: Runtime image ──────────────────────────────────────────────
FROM python:3.12-slim

WORKDIR /app

# Runtime system deps for PaddleOCR + PDF rendering
RUN apt-get update && apt-get install -y --no-install-recommends \
    poppler-utils \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxrender1 \
    libxext6 \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Copy installed Python packages from builder
COPY --from=builder /install /usr/local

COPY . .

RUN find /app -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true

# Run the API and Celery processes without root privileges in production.
RUN groupadd --system appuser && useradd --system --gid appuser --home-dir /app appuser \
    && chown -R appuser:appuser /app
USER appuser

# Pre-download PaddleOCR models during build (avoids runtime HuggingFace downloads)
RUN python -c "import os; os.environ['FLAGS_enable_pir_in_executor']='0'; os.environ['FLAGS_enable_pir_api']='0'; os.environ['FLAGS_pir_apply_inplace_pass']='0'; from paddleocr import PaddleOCR; ocr = PaddleOCR(lang='en', device='cpu', enable_mkldnn=False, use_doc_orientation_classify=False, use_doc_unwarping=False, use_textline_orientation=False, text_detection_model_name='PP-OCRv5_mobile_det', text_recognition_model_name='en_PP-OCRv5_mobile_rec'); print('Models pre-downloaded')" 2>/dev/null || true

EXPOSE 8000

CMD ["sh", "-c", "FLAGS_enable_pir_in_executor=0 FLAGS_enable_pir_api=0 FLAGS_pir_apply_inplace_pass=0 exec uvicorn src.main:app --host 0.0.0.0 --port 8000"]
