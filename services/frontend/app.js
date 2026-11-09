const labels = {
  defect: {
    RAIL: "Рельс", SLEEPER: "Шпалы", SWITCH: "Стрелочный перевод",
    CATENARY: "Контактная сеть", SIGNALING: "СЦБ", CROSSING: "Переезд", OTHER: "Другое",
  },
  priority: { LOW: "Низкий", MEDIUM: "Средний", HIGH: "Высокий", CRITICAL: "Критический" },
  status: {
    NEW: "Новая", ASSIGNED: "Назначена", IN_PROGRESS: "В работе",
    DONE: "Выполнена", REJECTED: "Отклонена", CANCELLED: "Отменена",
  },
};

const transitions = {
  NEW: ["REJECTED", "CANCELLED"],
  ASSIGNED: ["IN_PROGRESS", "CANCELLED"],
  IN_PROGRESS: ["DONE"],
  DONE: [], REJECTED: [], CANCELLED: [],
};

const state = { tickets: [], selectedId: null };
const elements = {
  health: document.querySelector("#health"),
  total: document.querySelector("#total"),
  tickets: document.querySelector("#tickets"),
  empty: document.querySelector("#empty"),
  actions: document.querySelector("#actions"),
  selectedTitle: document.querySelector("#selected-title"),
  nextStatus: document.querySelector("#next-status"),
  assignForm: document.querySelector("#assign-form"),
  statusForm: document.querySelector("#status-form"),
  notice: document.querySelector("#notice"),
};

async function request(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: options.body ? { "Content-Type": "application/json", ...options.headers } : options.headers,
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.detail || `HTTP ${response.status}`);
  return body;
}

function showNotice(message, error = false) {
  elements.notice.textContent = message;
  elements.notice.classList.toggle("error", error);
  elements.notice.hidden = false;
  window.clearTimeout(showNotice.timer);
  showNotice.timer = window.setTimeout(() => { elements.notice.hidden = true; }, 3500);
}

function ticketById(id) {
  return state.tickets.find((ticket) => Number(ticket.id) === Number(id));
}

function badge(text, className = "") {
  const node = document.createElement("span");
  node.className = `badge ${className}`.trim();
  node.textContent = text;
  return node;
}

function renderTickets() {
  elements.tickets.replaceChildren();
  elements.total.textContent = state.tickets.length;
  elements.empty.hidden = state.tickets.length !== 0;

  for (const ticket of state.tickets) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `ticket${Number(ticket.id) === Number(state.selectedId) ? " selected" : ""}`;
    button.addEventListener("click", () => selectTicket(ticket.id));

    const id = document.createElement("span");
    id.className = "ticket-id";
    id.textContent = `#${ticket.id}`;

    const main = document.createElement("span");
    main.className = "ticket-main";
    const title = document.createElement("strong");
    title.textContent = ticket.track_section;
    const description = document.createElement("span");
    description.textContent = `${labels.defect[ticket.defect_type] || ticket.defect_type} · ${ticket.description}`;
    main.append(title, description);

    button.append(
      id,
      main,
      badge(labels.priority[ticket.priority] || ticket.priority, `priority-${String(ticket.priority).toLowerCase()}`),
      badge(labels.status[ticket.status] || ticket.status, `status-${String(ticket.status).toLowerCase()}`),
    );
    elements.tickets.append(button);
  }

  if (state.selectedId && !ticketById(state.selectedId)) state.selectedId = null;
  renderActions();
}

function selectTicket(id) {
  state.selectedId = Number(id);
  renderTickets();
  elements.actions.scrollIntoView({ behavior: "smooth", block: "nearest" });
}

function renderActions() {
  const ticket = ticketById(state.selectedId);
  elements.actions.hidden = !ticket;
  if (!ticket) return;

  elements.selectedTitle.textContent = `Заявка #${ticket.id} · ${labels.status[ticket.status] || ticket.status}`;
  elements.assignForm.hidden = ticket.status !== "NEW";
  elements.nextStatus.replaceChildren();
  for (const status of transitions[ticket.status] || []) {
    const option = document.createElement("option");
    option.value = status;
    option.textContent = labels.status[status];
    elements.nextStatus.append(option);
  }
  elements.statusForm.hidden = elements.nextStatus.options.length === 0;
}

async function loadTickets() {
  const form = new FormData(document.querySelector("#filters"));
  const query = new URLSearchParams();
  for (const [key, value] of form.entries()) if (value) query.set(key, value);
  const data = await request(`/api/tickets?${query}`);
  state.tickets = data.tickets || [];
  renderTickets();
}

document.querySelector("#create-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  try {
    const ticket = await request("/api/tickets", {
      method: "POST",
      body: JSON.stringify(Object.fromEntries(new FormData(form))),
    });
    form.reset();
    form.elements.reporter.value = "inspector_demo";
    state.selectedId = Number(ticket.id);
    await loadTickets();
    showNotice(`Заявка #${ticket.id} создана`);
  } catch (error) { showNotice(error.message, true); }
});

document.querySelector("#filters").addEventListener("submit", async (event) => {
  event.preventDefault();
  try { await loadTickets(); } catch (error) { showNotice(error.message, true); }
});

elements.assignForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  try {
    await request(`/api/tickets/${state.selectedId}/assign`, {
      method: "POST",
      body: JSON.stringify(Object.fromEntries(new FormData(event.currentTarget))),
    });
    await loadTickets();
    showNotice("Бригада назначена");
  } catch (error) { showNotice(error.message, true); }
});

elements.statusForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  try {
    await request(`/api/tickets/${state.selectedId}/status`, {
      method: "POST",
      body: JSON.stringify(Object.fromEntries(new FormData(event.currentTarget))),
    });
    await loadTickets();
    showNotice("Статус обновлён");
  } catch (error) { showNotice(error.message, true); }
});

document.querySelector("#delete-button").addEventListener("click", async () => {
  if (!window.confirm(`Удалить заявку #${state.selectedId}?`)) return;
  try {
    await request(`/api/tickets/${state.selectedId}`, { method: "DELETE" });
    state.selectedId = null;
    await loadTickets();
    showNotice("Заявка удалена");
  } catch (error) { showNotice(error.message, true); }
});

async function start() {
  try {
    await request("/api/health");
    elements.health.textContent = "Система доступна";
    elements.health.classList.add("ok");
    await loadTickets();
  } catch (error) {
    elements.health.textContent = "Система недоступна";
    elements.health.classList.add("error");
    showNotice(error.message, true);
  }
}

start();

