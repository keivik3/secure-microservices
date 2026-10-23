# Rail Repair gRPC — заявки на ремонт железной дороги

Безопасное прикладное приложение в микросервисной архитектуре (Python, gRPC).
Порт Go-проекта grpc-vtb с добавлением бизнес-домена «заявки на ремонт ЖД»,
базы данных, кэша и брокера сообщений.

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
