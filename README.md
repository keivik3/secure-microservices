# Rail Repair gRPC — заявки на ремонт железной дороги

Безопасное прикладное приложение в микросервисной архитектуре (Python, gRPC).

## Архитектура

```
Клиент (curl / REST)
   │  HTTP/JSON :8000
   ▼
API Gateway (FastAPI) — санитизация ввода (XSS/SQLi)
   │  gRPC + TLS :50051
   ▼
Central gRPC Server — агрегатор, rate limiter (5 rps), Prometheus :8010
   ├── gRPC + TLS :50053 ─► User Service ──► Auth Service :8081 ──► Keycloak :8080
   └── gRPC + TLS :50054 ─► Repair Service ─┬─► PostgreSQL (заявки)
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

## Роли (Keycloak)

`inspector` — создаёт заявки, `dispatcher` — назначает бригады и меняет статусы,
`crew` — выполняет работы, `admin` — всё + удаление.

## Структура каталогов

```
proto/                  контракты gRPC (gateway, user, auth, repair)
services/api_gateway/   REST → gRPC (FastAPI), санитизация ввода
services/central_server/ агрегатор + rate limiter + метрики
services/user_service/  пользователи
services/auth_service/  Keycloak (python-keycloak)
services/repair_service/ заявки: Postgres + Redis + RabbitMQ
services/notification_service/ консьюмер событий
cert/                   генерация CA и mTLS-сертификатов (gen.sh)
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

После запуска <http://127.0.0.1:8000/> открывает Swagger UI.
Если порт `8000` занят, остановите стенд другого движка: `podman compose down` или
`docker compose down`.

Без сборки:

```sh
SKIP_BUILD=1 sh scripts/demo.sh docker
SKIP_BUILD=1 sh scripts/demo.sh podman
```

# Тестирование работы программы: 

## 1. 
```
docker compose up --build -d repair-service
```
## ДЗ 2 — стенд поднят 
Проверка «hello-world» — сервис жив и отвечает:
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

Ожидаемый результат — 10 passed, 0 failed: пять разрешённых и пять запрещённых соединений.

## ДЗ 5 — важный нюанс с вашей ситуацией
```
# 0. Если таблица пуста — создайте заявку заново (команда из ДЗ 3):
docker run --rm --network secure-microservices_app-net fullstorydev/grpcurl \
  -plaintext -d '{"track_section":"Москва — Тверь, 167 км","defect_type":"RAIL","description":"Трещина в рельсе","priority":"CRITICAL","reporter":"inspector_ivan"}' \
  repair-service:50054 repair.RepairService/CreateTicket

# 1. Бэкап (внутри свежей копии — заявка есть)
sh scripts/backup.sh

# 2. "Катастрофа"
docker compose exec postgres psql -U app rail_repair -c "TRUNCATE tickets RESTART IDENTITY;"
docker compose exec postgres psql -U app rail_repair -c "SELECT * FROM tickets;"
# (0 rows) — данных нет, "всё пропало"

# 3. Восстановление — путь УКАЗЫВАЕМ СО СЛЭШЕМ, как вывел backup.sh:
sh scripts/restore.sh backups/rail_repair_20261105_190338.sql.gz

# 4. Проверка
docker compose exec postgres psql -U app rail_repair -c "SELECT id, track_section, status FROM tickets;"
# заявка на месте
```

Мы все сможем и сдадим на отлично !! <3
