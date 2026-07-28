# crud-master

A microservices movie-streaming backend: an **Inventory API** (CRUD over PostgreSQL), a **Billing API**
(async order processing over RabbitMQ), and an **API Gateway** that fronts both. Each service runs in
its own Vagrant VM.

## Architecture

```
                        ┌─────────────────┐
   client ── HTTP ──►   │  api-gateway-app │  (gateway-vm, port 3000)
                        └───────┬─────┬────┘
                     HTTP       │     │ publish
                (proxy) │       │     │ (billing_queue)
                        ▼       │     ▼
              ┌──────────────┐ │  ┌─────────────┐      ┌───────────────┐
              │ inventory-app│ │  │  RabbitMQ   │◄─────┤  billing-app   │
              │  port 8080   │ │  │ (billing-vm)│      │  (consumer,    │
              └──────┬───────┘ │  └─────────────┘      │  billing-vm)   │
                     ▼         │                        └───────┬───────┘
              ┌──────────────┐ │                                ▼
              │  movies_db   │ │                        ┌───────────────┐
              │ (inventory-  │ │                        │  billing_db   │
              │     vm)      │ │                        │ (billing-vm)  │
              └──────────────┘ │                        └───────────────┘
```

- **inventory-vm**: `inventory-app` (Flask + SQLAlchemy) + PostgreSQL `movies_db`.
- **billing-vm**: `billing-app` (pika consumer, no HTTP surface) + PostgreSQL `billing_db` + RabbitMQ.
- **gateway-vm**: `api-gateway-app` (Flask) — proxies `/api/movies*` to the Inventory API over HTTP,
  and publishes `/api/billing` request bodies straight onto `billing_queue`. It never talks to
  billing-app directly, so billing requests succeed even while billing-app is stopped — RabbitMQ holds
  the message until a consumer is available again.

## Services

### Inventory API (`srcs/inventory-app`)

Flask + SQLAlchemy CRUD API backed by PostgreSQL (`movies_db`, table `movies`: `id`, `title`, `description`).

| Method | Path                 | Description                          |
|--------|----------------------|---------------------------------------|
| GET    | `/api/movies`        | list all movies                      |
| GET    | `/api/movies?title=` | filter movies by title substring     |
| POST   | `/api/movies`        | create a movie (`title` required)    |
| DELETE | `/api/movies`        | delete all movies                    |
| GET    | `/api/movies/<id>`   | get one movie                        |
| PUT    | `/api/movies/<id>`   | update one movie                     |
| DELETE | `/api/movies/<id>`   | delete one movie                     |

### Billing API (`srcs/billing-app`)

No HTTP endpoints. Consumes JSON messages from `billing_queue` (durable), inserts a row into
`billing_db.orders` (`id`, `user_id`, `number_of_items`, `total_amount`), and acks only after the DB
write succeeds — a failed insert `nack`s and requeues. On startup it drains any messages that piled up
in the queue while it was stopped.

### API Gateway (`srcs/api-gateway-app`)

- `GET|POST|DELETE /api/movies`, `GET|PUT|DELETE /api/movies/<id>` → proxied verbatim to the Inventory
  API; the gateway returns exactly what Inventory returned.
- `POST /api/billing` → publishes the JSON body to `billing_queue` and responds
  `{"message": "Message posted"}` (202), regardless of whether billing-app is currently running.

## Environment variables (`.env`, committed per project spec)

See [`.env`](.env) for the full list: PostgreSQL credentials for both databases, RabbitMQ credentials,
and each service's bind host/port. Vagrant reads this file directly and forwards the relevant subset
to each VM's provisioning script — nothing is hardcoded in the application code.

## Running locally (no Vagrant, fast iteration loop)

Each service has its own venv. With PostgreSQL and RabbitMQ reachable at the hosts/ports in `.env`:

```bash
cd srcs/inventory-app && python3 -m venv venv && ./venv/bin/pip install -r requirements.txt
./venv/bin/python server.py          # http://localhost:8080

cd srcs/billing-app && python3 -m venv venv && ./venv/bin/pip install -r requirements.txt
./venv/bin/python server.py          # consumer, no port

cd srcs/api-gateway-app && python3 -m venv venv && ./venv/bin/pip install -r requirements.txt
./venv/bin/python server.py          # http://localhost:3000
```

## Running with Vagrant (3 VMs)

```bash
vagrant up          # provisions inventory-vm (.11), billing-vm (.12), gateway-vm (.13)
vagrant status
vagrant ssh gateway-vm
```

Each VM installs Python, PostgreSQL/RabbitMQ as needed, and runs its app under **PM2**
(`pm2 list`, `pm2 stop <name>`, `pm2 start <name>`, `pm2 logs <name>`) so services survive
reboots and crashes.

Try it end to end from the host (once VMs are up):

```bash
curl -X POST http://192.168.56.13:3000/api/movies \
  -H "Content-Type: application/json" \
  -d '{"title":"Inception","description":"A dream heist"}'

curl -X POST http://192.168.56.13:3000/api/billing \
  -H "Content-Type: application/json" \
  -d '{"user_id":"3","number_of_items":"5","total_amount":"180"}'
```

## Testing

`postman/crud-master.postman_collection.json` — a Postman/Newman collection with at least one test per
Inventory endpoint (CRUD + filter + 404 case). Verified with `newman run postman/crud-master.postman_collection.json`
(18/18 assertions passing against a local run of inventory-app).

To exercise the billing resilience behavior manually: publish a message with billing-app running, stop
it (`pm2 stop billing-app`), publish another message (gateway still returns 202, `orders` table
unchanged), then `pm2 start billing-app` and confirm the pending message is processed. This exact
sequence was verified during development.

## Design notes

- Each service is its own Python virtual environment (`venv/`, gitignored) with a scoped
  `requirements.txt` — no shared dependency tree between services.
- `billing-app` has no Flask app at all: the spec is explicit that it "receives messages exclusively
  through RabbitMQ," so there's no HTTP surface to build or secure.
- The gateway never calls billing-app directly (HTTP or otherwise) — it only publishes to RabbitMQ.
  That's what makes "accept billing requests even when billing-app is down" trivial: it's not a
  gateway-side retry/queue, it's RabbitMQ's normal durable-queue behavior.
