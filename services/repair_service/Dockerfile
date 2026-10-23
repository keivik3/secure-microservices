FROM python:3.12-slim

WORKDIR /app

# Зависимости — отдельным слоем для кэширования
COPY services/repair_service/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Сгенерированный pb2-код (генерируется scripts/gen_proto.sh до сборки)
COPY gen/ ./gen/

# Код сервиса и сертификаты
COPY services/repair_service/ ./services/repair_service/
COPY cert/ ./cert/

WORKDIR /app/services/repair_service
ENV GEN_PATH=/app/gen

CMD ["python", "main.py"]
