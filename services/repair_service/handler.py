"""gRPC-обработчики RepairService — бизнес-логика заявок на ремонт.

Каждый метод: валидация -> БД -> инвалидация кэша -> событие в брокер.
Enum-значения в БД храним строками ('RAIL', 'CRITICAL', 'NEW') — читаемо
при ручном просмотре таблицы на защите.
"""

import logging

import grpc

import cache
import db
import events
from proto.repair import repair_pb2, repair_pb2_grpc

logger = logging.getLogger("repair.handler")

# Допустимые переходы статусов: NEW -> ASSIGNED/REJECTED/CANCELLED и т.д.
# Терминальные статусы (DONE, REJECTED, CANCELLED) изменить нельзя.
ALLOWED_TRANSITIONS = {
    "NEW": {"ASSIGNED", "REJECTED", "CANCELLED"},
    "ASSIGNED": {"IN_PROGRESS", "CANCELLED"},
    "IN_PROGRESS": {"DONE"},
    "DONE": set(),
    "REJECTED": set(),
    "CANCELLED": set(),
}

MAX_PAGE_SIZE = 100


def _ticket_to_proto(t: dict) -> repair_pb2.RepairTicket:
    """Строка из БД -> proto-сообщение."""
    return repair_pb2.RepairTicket(
        id=t["id"],
        track_section=t["track_section"],
        defect_type=repair_pb2.DefectType.Value(t["defect_type"]),
        description=t["description"],
        priority=repair_pb2.Priority.Value(t["priority"]),
        status=repair_pb2.Status.Value(t["status"]),
        reporter=t["reporter"],
        crew=t["crew"],
        planned_date=t["planned_date"],
        created_at=t["created_at"],
        updated_at=t["updated_at"],
        comment=t["comment"],
    )


def _enum_name(enum_type, value) -> str:
    """Число из proto -> строка для БД; 0 (UNSPECIFIED) -> None."""
    if value == 0:
        return None
    return enum_type.Name(value)


class RepairService(repair_pb2_grpc.RepairServiceServicer):

    def CreateTicket(self, request, context):
        if not request.track_section.strip():
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, "track_section обязателен")
        if not request.description.strip():
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, "description обязателен")
        if request.defect_type == repair_pb2.DEFECT_UNSPECIFIED:
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, "укажите defect_type")
        if request.priority == repair_pb2.PRIORITY_UNSPECIFIED:
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, "укажите priority")
        if not request.reporter.strip():
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, "reporter обязателен")

        ticket = db.create_ticket(
            track_section=request.track_section,
            defect_type=_enum_name(repair_pb2.DefectType, request.defect_type),
            description=request.description,
            priority=_enum_name(repair_pb2.Priority, request.priority),
            reporter=request.reporter,
        )
        logger.info("создана заявка id=%d (%s, %s)", ticket["id"],
                    ticket["track_section"], ticket["priority"])
        events.publish("repair.created", ticket)
        return repair_pb2.TicketResponse(ticket=_ticket_to_proto(ticket))

    def GetTicket(self, request, context):
        # cache-aside: сначала Redis, при промахе — PostgreSQL
        ticket = cache.get_ticket(request.id)
        if ticket is None:
            ticket = db.get_ticket(request.id)
            if ticket is None:
                context.abort(grpc.StatusCode.NOT_FOUND,
                              f"заявка {request.id} не найдена")
            cache.set_ticket(ticket)
        return repair_pb2.TicketResponse(ticket=_ticket_to_proto(ticket))

    def ListTickets(self, request, context):
        page = max(request.page, 1)
        page_size = request.page_size if request.page_size > 0 else 20
        page_size = min(page_size, MAX_PAGE_SIZE)

        tickets, total = db.list_tickets(
            status=_enum_name(repair_pb2.Status, request.status),
            priority=_enum_name(repair_pb2.Priority, request.priority),
            track_section=request.track_section or None,
            page=page,
            page_size=page_size,
        )
        return repair_pb2.ListTicketsResponse(
            tickets=[_ticket_to_proto(t) for t in tickets],
            total=total,
        )

    def UpdateTicketStatus(self, request, context):
        if request.status in (repair_pb2.STATUS_UNSPECIFIED, repair_pb2.NEW):
            context.abort(grpc.StatusCode.INVALID_ARGUMENT,
                          "нельзя перевести заявку в NEW")

        current = db.get_ticket(request.id)
        if current is None:
            context.abort(grpc.StatusCode.NOT_FOUND,
                          f"заявка {request.id} не найдена")

        new_status = _enum_name(repair_pb2.Status, request.status)
        if new_status not in ALLOWED_TRANSITIONS[current["status"]]:
            context.abort(
                grpc.StatusCode.FAILED_PRECONDITION,
                f"переход {current['status']} -> {new_status} недопустим",
            )

        ticket = db.update_ticket_status(request.id, new_status, request.comment)
        cache.invalidate(request.id)
        logger.info("заявка id=%d: %s -> %s", request.id, current["status"], new_status)
        events.publish("repair.status_changed", ticket)
        return repair_pb2.TicketResponse(ticket=_ticket_to_proto(ticket))

    def AssignTicket(self, request, context):
        if not request.crew.strip():
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, "укажите бригаду (crew)")

        current = db.get_ticket(request.id)
        if current is None:
            context.abort(grpc.StatusCode.NOT_FOUND,
                          f"заявка {request.id} не найдена")
        if "ASSIGNED" not in ALLOWED_TRANSITIONS[current["status"]]:
            context.abort(
                grpc.StatusCode.FAILED_PRECONDITION,
                f"назначить бригаду можно только на заявку в статусе NEW "
                f"(сейчас: {current['status']})",
            )

        ticket = db.assign_ticket(request.id, request.crew, request.planned_date)
        cache.invalidate(request.id)
        logger.info("заявка id=%d назначена бригаде '%s'", request.id, request.crew)
        events.publish("repair.assigned", ticket)
        return repair_pb2.TicketResponse(ticket=_ticket_to_proto(ticket))

    def DeleteTicket(self, request, context):
        ticket = db.delete_ticket(request.id)
        if ticket is None:
            context.abort(grpc.StatusCode.NOT_FOUND,
                          f"заявка {request.id} не найдена")
        cache.invalidate(request.id)
        logger.info("заявка id=%d удалена", request.id)
        events.publish("repair.deleted", ticket)
        return repair_pb2.DeleteTicketResponse(success=True)
