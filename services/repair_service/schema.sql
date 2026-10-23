-- Таблица заявок на ремонт железной дороги.
-- Применяется автоматически при старте repair-service (db.py).

CREATE TABLE IF NOT EXISTS tickets (
    id            BIGSERIAL PRIMARY KEY,
    track_section TEXT        NOT NULL,            -- "Москва — Тверь, 167 км, путь 2"
    defect_type   TEXT        NOT NULL,            -- RAIL | SLEEPER | SWITCH | CATENARY | SIGNALING | CROSSING | OTHER
    description   TEXT        NOT NULL,
    priority      TEXT        NOT NULL,            -- LOW | MEDIUM | HIGH | CRITICAL
    status        TEXT        NOT NULL DEFAULT 'NEW', -- NEW | ASSIGNED | IN_PROGRESS | DONE | REJECTED | CANCELLED
    reporter      TEXT        NOT NULL,            -- username создателя (из Keycloak)
    crew          TEXT        NOT NULL DEFAULT '', -- назначенная бригада
    planned_date  TEXT        NOT NULL DEFAULT '', -- плановая дата ремонта, ISO 8601
    comment       TEXT        NOT NULL DEFAULT '', -- последний комментарий
    created_at    BIGINT      NOT NULL,            -- unix timestamp
    updated_at    BIGINT      NOT NULL
);

-- Индексы под типовые фильтры ListTickets
CREATE INDEX IF NOT EXISTS idx_tickets_status   ON tickets (status);
CREATE INDEX IF NOT EXISTS idx_tickets_priority ON tickets (priority);
