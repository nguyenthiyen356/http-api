# ── Stage 1: dependency builder ───────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build
COPY app/requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: lean runtime ──────────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

# Non-root user
RUN useradd -r -u 1001 -s /usr/sbin/nologin appuser

WORKDIR /app

# Pull in only the installed packages — no build tools
COPY --from=builder /install /usr/local

# Copy application source
COPY app/main.py .

RUN chown -R appuser:appuser /app

USER appuser

ENV PYTHONUNBUFFERED=1 \
    PORT=8080

EXPOSE 8080

CMD ["python", "main.py"]
