FROM docker.io/library/python:3.12-slim@sha256:4840d514c583a4d3d8cad3940e68dee6f0f6f3635c12fcd0a3d74c21a5b93a54

WORKDIR /app

# Зависимости — отдельным слоем для кэширования
COPY services/repair_service/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN useradd --system --uid 10001 --no-create-home app

# Сгенерированный pb2-код (генерируется scripts/gen_proto.sh до сборки)
COPY gen/ ./gen/

# Код сервиса
COPY services/repair_service/ ./services/repair_service/

WORKDIR /app/services/repair_service
ENV GEN_PATH=/app/gen \
    PYTHONDONTWRITEBYTECODE=1
USER app

CMD ["python", "main.py"]
