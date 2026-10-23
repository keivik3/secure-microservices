"""Слой работы с PostgreSQL.

Пул потокобезопасных соединений (gRPC обрабатывает запросы в пуле потоков,
поэтому одно соединение на сервис использовать нельзя).
Все SQL-запросы параметризованы — защита от SQL-инъекций на уровне БД
(санитизация в api-gateway — первая линия, это — вторая).
"""

import os
import time

import psycopg2
import psycopg2.extras
from psycopg2.pool import ThreadedConnectionPool

_pool: ThreadedConnectionPool | None = None

SCHEMA_PATH = os.path.join(os.path.dirname(__file__), "schema.sql")


def init_db() -> None:
    """Создаёт пул соединений и применяет schema.sql (идемпотентно)."""
    global _pool
    _pool = ThreadedConnectionPool(
        minconn=1,
        maxconn=10,
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=int(os.getenv("POSTGRES_PORT", "5432")),
        dbname=os.getenv("POSTGRES_DB", "rail_repair"),
        user=os.getenv("POSTGRES_USER", "app"),
        password=os.getenv("POSTGRES_PASSWORD", "app_secret"),
    )
    with open(SCHEMA_PATH, encoding="utf-8") as f:
        schema = f.read()
    conn = _pool.getconn()
    try:
        with conn.cursor() as cur:
            cur.execute(schema)
        conn.commit()
    finally:
        _pool.putconn(conn)


def _query(sql: str, params: tuple = (), fetch: str = "one"):
    """Выполняет запрос. fetch: 'one' | 'all' | None (для INSERT/UPDATE)."""
    conn = _pool.getconn()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(sql, params)
            if fetch == "one":
                row = cur.fetchone()
            elif fetch == "all":
                row = cur.fetchall()
            else:
                row = None
        conn.commit()
        return row
    finally:
        _pool.putconn(conn)


def _to_dict(row) -> dict | None:
    return dict(row) if row else None


# ---------- CRUD ----------

def create_ticket(track_section: str, defect_type: str, description: str,
                  priority: str, reporter: str) -> dict:
    now = int(time.time())
    row = _query(
        """
        INSERT INTO tickets (track_section, defect_type, description, priority,
                             status, reporter, created_at, updated_at)
        VALUES (%s, %s, %s, %s, 'NEW', %s, %s, %s)
        RETURNING *
        """,
        (track_section, defect_type, description, priority, reporter, now, now),
        fetch="one",
    )
    return dict(row)


def get_ticket(ticket_id: int) -> dict | None:
    return _to_dict(_query("SELECT * FROM tickets WHERE id = %s", (ticket_id,)))


def list_tickets(status: str | None, priority: str | None,
                 track_section: str | None, page: int, page_size: int) -> tuple[list[dict], int]:
    """Фильтры необязательные; возвращает (страница, всего записей по фильтру)."""
    conditions, params = [], []
    if status:
        conditions.append("status = %s")
        params.append(status)
    if priority:
        conditions.append("priority = %s")
        params.append(priority)
    if track_section:
        conditions.append("track_section ILIKE %s")  # подстрока, без учёта регистра
        params.append(f"%{track_section}%")
    where = ("WHERE " + " AND ".join(conditions)) if conditions else ""

    total = _query(f"SELECT COUNT(*) AS c FROM tickets {where}", tuple(params))["c"]
    rows = _query(
        f"SELECT * FROM tickets {where} ORDER BY id DESC LIMIT %s OFFSET %s",
        tuple(params) + (page_size, (page - 1) * page_size),
        fetch="all",
    )
    return [dict(r) for r in rows], total


def update_ticket_status(ticket_id: int, status: str, comment: str) -> dict | None:
    return _to_dict(_query(
        """
        UPDATE tickets
        SET status = %s, comment = %s, updated_at = %s
        WHERE id = %s
        RETURNING *
        """,
        (status, comment, int(time.time()), ticket_id),
    ))


def assign_ticket(ticket_id: int, crew: str, planned_date: str) -> dict | None:
    return _to_dict(_query(
        """
        UPDATE tickets
        SET crew = %s, planned_date = %s, status = 'ASSIGNED', updated_at = %s
        WHERE id = %s
        RETURNING *
        """,
        (crew, planned_date, int(time.time()), ticket_id),
    ))


def delete_ticket(ticket_id: int) -> dict | None:
    """Возвращает удалённую запись (для события) или None, если не найдена."""
    return _to_dict(_query(
        "DELETE FROM tickets WHERE id = %s RETURNING *", (ticket_id,)
    ))
