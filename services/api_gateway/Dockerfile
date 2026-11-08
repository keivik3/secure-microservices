FROM docker.io/library/python:3.12-slim

WORKDIR /app

COPY services/api_gateway/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN useradd --system --uid 10001 --no-create-home app

COPY gen/ ./gen/
COPY services/api_gateway/ ./services/api_gateway/

WORKDIR /app/services/api_gateway
ENV GEN_PATH=/app/gen \
    PYTHONDONTWRITEBYTECODE=1
USER app

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
