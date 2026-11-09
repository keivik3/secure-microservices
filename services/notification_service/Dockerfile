FROM docker.io/library/python:3.12-slim@sha256:4840d514c583a4d3d8cad3940e68dee6f0f6f3635c12fcd0a3d74c21a5b93a54

WORKDIR /app

COPY services/notification_service/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN useradd --system --uid 10001 --no-create-home app

COPY services/notification_service/ ./services/notification_service/

WORKDIR /app/services/notification_service
ENV PYTHONDONTWRITEBYTECODE=1
USER app

CMD ["python", "main.py"]
