# Rail Repair gRPC — заявки на ремонт железной дороги

Безопасное прикладное приложение в микросервисной архитектуре (Python, gRPC).

## Архитектура

```
Браузер
   │  HTTP :8000
   ▼
Frontend (Nginx) — интерфейс заявок
   │  HTTP/JSON /api
   ▼
API Gateway (FastAPI) — валидация HTTP-ввода
   │  gRPC :50054
   ▼
Repair Service ─┬─► PostgreSQL (заявки)
                ├─► Redis (кэш ticket:{id}, TTL 5 мин)
                └─► RabbitMQ (события repair.*)
                             │
                             ▼
                Notification Service (консьюмер)
```

## Домен: заявка на ремонт (RepairTicket)

Поля: id, track_section (участок пути), defect_type (рельс/шпалы/стрелка/контактная
сеть/СЦБ/переезд), description, priority (LOW..CRITICAL),
status (NEW → ASSIGNED → IN_PROGRESS → DONE / REJECTED / CANCELLED),
reporter, crew (бригада), planned_date, created_at, updated_at, comment.

## События брокера (RabbitMQ, exchange repair.events, topic)

- `repair.created` — создана заявка (CRITICAL — срочное уведомление диспетчеру)
- `repair.assigned` — назначена бригада
- `repair.status_changed` — смена статуса
- `repair.deleted` — удалена заявка

## Структура каталогов

```
proto/                  контракты gRPC и сгенерированные клиенты
services/frontend/      веб-интерфейс и reverse proxy к API Gateway
services/api_gateway/   REST → gRPC (FastAPI), валидация ввода
services/repair_service/ заявки: Postgres + Redis + RabbitMQ
services/notification_service/ консьюмер событий
cert/                   генерация CA и mTLS-сертификатов для отдельного TLS-режима
scripts/                генерация pb2-кода, тестовые запросы
```

# Полная демонстрация

```sh
sh scripts/init_env.sh
sh scripts/demo.sh docker
sh scripts/demo.sh podman
```

Проверяются REST API Gateway, валидация ввода, CRUD, SQL-схема, Redis,
RabbitMQ, сети, backup/restore и failover.

После запуска <http://127.0.0.1:8000/> открывает веб-интерфейс. В нём можно
создать заявку, назначить бригаду, изменить статус, отфильтровать и удалить
заявку. Swagger UI доступен по адресу <http://127.0.0.1:8000/docs>.
Если порт `8000` занят, остановите стенд другого движка: `podman compose down` или
`docker compose down`.

Без сборки:

```sh
SKIP_BUILD=1 sh scripts/demo.sh docker
SKIP_BUILD=1 sh scripts/demo.sh podman
```

# Тестирование работы программы

Ниже приведены команды Docker Compose; для Podman замените `docker` на `podman`.

## Запуск repair-service
```
docker compose up --build -d repair-service
```
## ДЗ 2 — стенд поднят
Проверка доступности микросервиса:
```
docker run --rm --network secure-microservices_app-net fullstorydev/grpcurl \
  -plaintext repair-service:50054 list
# ожидаем: repair.RepairService
```
## ДЗ 3 — БД + кэш + брокер

Создать заявку (запись в БД + событие в брокер):
```
docker run --rm --network secure-microservices_app-net fullstorydev/grpcurl \
  -plaintext -d '{
    "track_section": "Москва — Тверь, 167 км, путь 2",
    "defect_type": "RAIL",
    "description": "Трещина в рельсе 12 мм",
    "priority": "CRITICAL",
    "reporter": "inspector_ivan"
  }' repair-service:50054 repair.RepairService/CreateTicket
```
Проверить БД:
```
docker compose exec postgres psql -U app rail_repair -c "SELECT id, track_section, priority, status FROM tickets;"
```
Проверить, что consumer поймал событие:
```
docker compose logs notification-service
# !!! СРОЧНО !!! Уведомление диспетчеру: событие 'repair.created', заявка №1 ...
```
Проверить кэш (чтение дважды):
```
# первый раз — cache MISS (из БД)
docker run --rm --network secure-microservices_app-net fullstorydev/grpcurl \
  -plaintext -d '{"id": 1}' repair-service:50054 repair.RepairService/GetTicket
docker compose logs repair-service | grep cache

# второй раз — cache HIT (из Redis)
docker run --rm --network secure-microservices_app-net fullstorydev/grpcurl \
  -plaintext -d '{"id": 1}' repair-service:50054 repair.RepairService/GetTicket
docker compose logs repair-service | grep cache

docker compose exec redis redis-cli GET ticket:1
```
Инвалидация кэша при изменении:
```
docker run --rm --network secure-microservices_app-net fullstorydev/grpcurl \
  -plaintext -d '{"id": 1, "crew": "ПЧ-6, бригада №3", "planned_date": "2026-11-02"}' \
  repair-service:50054 repair.RepairService/AssignTicket
docker compose exec redis redis-cli GET ticket:1
# (nil) — кэш инвалидирован
```
## ДЗ 4 — повторная проверка
```
sh scripts/check_network.sh
```

Ожидаемый результат — 12 passed, 0 failed: шесть разрешённых и шесть запрещённых соединений.

## ДЗ 5 — резервное копирование и восстановление
```
# Если таблица пуста, создайте заявку:
docker run --rm --network secure-microservices_app-net fullstorydev/grpcurl \
  -plaintext -d '{"track_section":"Москва — Тверь, 167 км","defect_type":"RAIL","description":"Трещина в рельсе","priority":"CRITICAL","reporter":"inspector_ivan"}' \
  repair-service:50054 repair.RepairService/CreateTicket

# Бэкап
sh scripts/backup.sh

# Удаление данных для проверки восстановления
docker compose exec postgres psql -U app rail_repair -c "TRUNCATE tickets RESTART IDENTITY;"
docker compose exec postgres psql -U app rail_repair -c "SELECT * FROM tickets;"

# Восстановление: укажите путь, который вывел backup.sh
sh scripts/restore.sh backups/rail_repair_20261105_190338.sql.gz

# Проверка
docker compose exec postgres psql -U app rail_repair -c "SELECT id, track_section, status FROM tickets;"
```

Мы все сможем и сдадим на отлично !! <3
