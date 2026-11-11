"""REST API Gateway for the repair gRPC service."""

import os
import sys
import logging
import time

import grpc
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import RedirectResponse, Response
from google.protobuf.json_format import MessageToDict
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from pydantic import BaseModel, Field

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.getenv("GEN_PATH", os.path.join(BASE_DIR, "..", "..", "gen")))

from proto.repair import repair_pb2 as pb
from proto.repair import repair_pb2_grpc as pbg

REPAIR_SERVICE_URL = os.getenv("REPAIR_SERVICE_URL", "repair-service:50054")
ENABLE_DOCS = os.getenv("ENABLE_DOCS", "false").lower() == "true"

channel = grpc.insecure_channel(REPAIR_SERVICE_URL)
client = pbg.RepairServiceStub(channel)
logger = logging.getLogger("api.gateway")
app = FastAPI(
    title="Rail Repair API Gateway",
    docs_url="/docs" if ENABLE_DOCS else None,
    redoc_url="/redoc" if ENABLE_DOCS else None,
    openapi_url="/openapi.json" if ENABLE_DOCS else None,
)

HTTP_REQUESTS = Counter(
    "api_gateway_http_requests_total",
    "HTTP requests handled by the API Gateway.",
    ("method", "route", "status"),
)
HTTP_DURATION = Histogram(
    "api_gateway_http_request_duration_seconds",
    "HTTP request duration in seconds.",
    ("method", "route"),
)


@app.middleware("http")
async def observe_http(request, call_next):
    if request.url.path == "/metrics":
        return await call_next(request)
    started = time.perf_counter()
    status = 500
    try:
        response = await call_next(request)
        status = response.status_code
        return response
    finally:
        route = request.scope.get("route")
        route_name = getattr(route, "path", request.url.path)
        HTTP_REQUESTS.labels(request.method, route_name, str(status)).inc()
        HTTP_DURATION.labels(request.method, route_name).observe(time.perf_counter() - started)


@app.get("/metrics", include_in_schema=False)
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


class TicketCreate(BaseModel):
    track_section: str = Field(min_length=1, max_length=200)
    defect_type: str
    description: str = Field(min_length=1, max_length=2000)
    priority: str
    reporter: str = Field(min_length=1, max_length=100)


class AssignTicket(BaseModel):
    crew: str = Field(min_length=1, max_length=200)
    planned_date: str = Field(default="", max_length=30)


class UpdateStatus(BaseModel):
    status: str
    comment: str = Field(default="", max_length=2000)


@app.get("/", include_in_schema=False)
def root():
    if ENABLE_DOCS:
        return RedirectResponse("/docs")
    return {"status": "ok"}


def validate_text(value: str, field: str) -> str:
    value = value.strip()
    if not value:
        raise HTTPException(status_code=400, detail=f"invalid {field}")
    return value


def enum_value(enum_type, value: str, field: str) -> int:
    try:
        return enum_type.Value(value.upper())
    except ValueError as error:
        allowed = [name for name in enum_type.keys() if not name.endswith("UNSPECIFIED")]
        raise HTTPException(400, f"invalid {field}; allowed: {allowed}") from error


def grpc_call(method, request):
    try:
        return method(request, timeout=5)
    except grpc.RpcError as error:
        status = {
            grpc.StatusCode.INVALID_ARGUMENT: 400,
            grpc.StatusCode.NOT_FOUND: 404,
            grpc.StatusCode.FAILED_PRECONDITION: 409,
        }.get(error.code())
        if status is not None:
            raise HTTPException(status, error.details() or "request rejected") from error
        logger.warning("repair RPC failed: code=%s details=%s", error.code(), error.details())
        raise HTTPException(503, "repair service unavailable") from error


def ticket_json(ticket) -> dict:
    return MessageToDict(ticket, preserving_proto_field_name=True)


@app.get("/api/health")
def health():
    try:
        grpc.channel_ready_future(channel).result(timeout=2)
    except grpc.FutureTimeoutError as error:
        raise HTTPException(503, "repair service unavailable") from error
    return {"status": "ok"}


@app.post("/api/tickets", status_code=201)
def create_ticket(body: TicketCreate):
    response = grpc_call(client.CreateTicket, pb.CreateTicketRequest(
        track_section=validate_text(body.track_section, "track_section"),
        defect_type=enum_value(pb.DefectType, body.defect_type, "defect_type"),
        description=validate_text(body.description, "description"),
        priority=enum_value(pb.Priority, body.priority, "priority"),
        reporter=validate_text(body.reporter, "reporter"),
    ))
    return ticket_json(response.ticket)


@app.get("/api/tickets")
def list_tickets(
    status: str = Query(""),
    priority: str = Query(""),
    track_section: str = Query("", max_length=200),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
):
    response = grpc_call(client.ListTickets, pb.ListTicketsRequest(
        status=enum_value(pb.Status, status, "status") if status else 0,
        priority=enum_value(pb.Priority, priority, "priority") if priority else 0,
        track_section=validate_text(track_section, "track_section") if track_section else "",
        page=page,
        page_size=page_size,
    ))
    return {
        "tickets": [ticket_json(ticket) for ticket in response.tickets],
        "total": response.total,
    }


@app.get("/api/tickets/{ticket_id}")
def get_ticket(ticket_id: int):
    response = grpc_call(client.GetTicket, pb.GetTicketRequest(id=ticket_id))
    return ticket_json(response.ticket)


@app.post("/api/tickets/{ticket_id}/assign")
def assign_ticket(ticket_id: int, body: AssignTicket):
    response = grpc_call(client.AssignTicket, pb.AssignTicketRequest(
        id=ticket_id,
        crew=validate_text(body.crew, "crew"),
        planned_date=validate_text(body.planned_date, "planned_date") if body.planned_date else "",
    ))
    return ticket_json(response.ticket)


@app.post("/api/tickets/{ticket_id}/status")
def update_status(ticket_id: int, body: UpdateStatus):
    response = grpc_call(client.UpdateTicketStatus, pb.UpdateTicketStatusRequest(
        id=ticket_id,
        status=enum_value(pb.Status, body.status, "status"),
        comment=validate_text(body.comment, "comment") if body.comment else "",
    ))
    return ticket_json(response.ticket)


@app.delete("/api/tickets/{ticket_id}")
def delete_ticket(ticket_id: int):
    response = grpc_call(client.DeleteTicket, pb.DeleteTicketRequest(id=ticket_id))
    return {"success": response.success}
