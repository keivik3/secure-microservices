FROM python:3.12-slim

WORKDIR /app

COPY services/notification_service/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY services/notification_service/ ./services/notification_service/

WORKDIR /app/services/notification_service

CMD ["python", "main.py"]
