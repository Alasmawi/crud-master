# Audit guide

Every audit question, with the answer and the command or file that proves it.
Gateway address: `http://localhost:3000` (or `http://192.168.56.13:3000`).

## Documentation

| Question | Answer |
|---|---|
| Does the README include enough context to understand and run the project? | Yes. [README.md](../README.md) has the overview, quick start, API, schema and stack. The guides in `docs/` cover the rest. |
| Does the OpenAPI documentation reflect the API Gateway's behavior? | Yes. [openapi.yaml](../openapi.yaml) documents all 7 endpoints with their status codes. Paste it into https://editor.swagger.io to view it. |

## Virtual machines

| Question | Answer |
|---|---|
| Are the three VMs up and running? | `vagrant up`, then `vagrant status` shows `gateway-vm`, `inventory-vm` and `billing-vm` as running. |
| Does `.env` contain all the credentials the services need? | Yes. `cat .env` shows the PostgreSQL users and passwords for both databases, the RabbitMQ user and password, and all hosts and ports. |
| Is the source code free of credentials? | Yes. `grep -rn "pass\|user" srcs/` shows only `os.environ[...]` reads. |
| Are environment variables injected into the VMs and used by the services? | Yes. See [How variables reach the services](#how-variables-reach-the-services). |
| Can the learner explain the scripts? | See [Scripts](#scripts). |

### How variables reach the services

1. The `Vagrantfile` parses `.env`.
2. It passes each VM only the variables that VM needs, through the provisioner's `env:` option.
3. The script starts the app with PM2, which captures those variables.
4. `pm2 save` stores them, so they survive a reboot.

To see them inside a VM:

```bash
sudo pm2 env 0
```

### Scripts

| Script | Commands and why |
|---|---|
| `common.sh` | `apt-get install python3 python3-venv ...` installs Python. The NodeSource script and `npm install -g pm2` install Node.js and PM2. Runs on every VM. |
| `inventory-vm.sh` | Installs PostgreSQL. `CREATE ROLE` and `CREATE DATABASE movies_db` run only if they don't exist yet, so the script can be re-run. Then it deploys the app. |
| `billing-vm.sh` | Installs PostgreSQL and RabbitMQ and creates the `billing_db` role and database. `rabbitmq-plugins enable rabbitmq_management` turns on the web UI. `rabbitmqctl add_user` creates the RabbitMQ user (`guest` only works from localhost). `rabbitmqadmin declare queue` creates `billing_queue`. Then it deploys the app. |
| `gateway-vm.sh` | Only deploys the app: the gateway has no database. |
| `deploy-app.sh` | `python3 -m venv` creates the app's own virtual environment and `pip install -r requirements.txt` installs its packages. `pm2 start` runs `server.py`. `pm2 save` and `pm2 startup` bring it back after a reboot. |

## API Gateway

| Question | Answer |
|---|---|
| Does it route to the Inventory API using HTTP? | Yes. `_proxy_to_inventory` in `srcs/api-gateway-app/app/routes.py` forwards the request with `requests` to `INVENTORY_API_URL`. |
| Does it route to the Billing API using RabbitMQ? | Yes. `publish_billing_message` in `app/rabbitmq.py` publishes the body to `billing_queue` with `pika`. |
| Does it return Inventory's exact response? | Yes. It returns Inventory's body, status code and content type unchanged. Compare `curl localhost:3000/api/movies` with `curl localhost:8080/api/movies`. |
| Can it enqueue messages while the Billing API is stopped? | Yes. The gateway only talks to RabbitMQ, never to the Billing API. See the billing steps below. |

## Inventory API

| Step | Expected |
|---|---|
| `POST /api/movies/` with `{"title": "A new movie", "description": "Very short description"}` | `201` and the created movie |
| Is the movie persisted in PostgreSQL? | Yes: see the `psql` steps below |
| `GET /api/movies/` | `200`, JSON list containing the movie |
| Filter by title | `GET /api/movies?title=new` returns only matching movies |
| Postman configuration | Import `postman/crud-master.postman_collection.json`. It covers every method of both APIs, and all 24 tests pass. |

On inventory-vm:

```bash
vagrant ssh inventory-vm
sudo -i -u postgres
psql
```

Then in `psql`:

```
\l
\c movies_db
TABLE movies;
```

`\l` lists `movies_db`, and `TABLE movies;` shows the movies created through the API.

## Billing API

| Step | Expected |
|---|---|
| `POST /api/billing/` with `user_id` 20 | `200 {"message": "Message posted"}` |
| `sudo pm2 stop billing_app`, then `sudo pm2 list` (on billing-vm) | `billing_app` is `stopped` |
| `POST /api/billing/` with `user_id` 22 | Still `200` |
| Does the gateway enqueue instead of writing to the database? | Yes. The gateway has no database access; the message waits in `billing_queue`. |

On billing-vm:

```bash
vagrant ssh billing-vm
sudo -i -u postgres
psql
```

Then in `psql`:

```
\l
\c billing_db
TABLE orders;
```

The subject names the database `billing_db`, so use `\c billing_db` where the audit text says
`orders_db`.

| Question | Expected |
|---|---|
| Is the database listed? | `\l` shows `billing_db` |
| Is the order with `user_id = 20` listed? | Yes |
| Is the order with `user_id = 22` NOT listed (while stopped)? | Correct, it is not listed |
| Does the schema match the README? | Yes: `\d orders` matches the [schema in the README](../README.md#database-schema) |

## Resilience of the queue

On billing-vm:

```bash
systemctl is-active rabbitmq-server
sudo rabbitmqctl list_queues name durable messages_ready consumers
```

| Question | Expected |
|---|---|
| Is RabbitMQ running, with `billing_queue` created and the Billing API subscribed? | `active`; `billing_queue` is durable with `consumers` = 1 while billing_app runs |
| Are messages persisted while the Billing API is unavailable? | Yes: `messages_ready` = 1 and `consumers` = 0 while it is stopped. The queue is durable and messages are persistent, so they also survive a RabbitMQ restart. |
| After `sudo pm2 start billing_app`, is the order with `user_id = 22` listed? | Yes, `TABLE orders;` now shows it |
| Does the Billing API acknowledge messages after processing? | Yes. `basic_ack` is called only after the database commit (`srcs/billing-app/app/consumer.py`). After processing, `messages_ready` and unacknowledged are both 0. |

The queue can also be seen at http://localhost:15672 (log in with `RABBITMQ_USER` /
`RABBITMQ_PASSWORD` from `.env`).

## Bonus

| Question | Answer |
|---|---|
| Additional validation or error handling? | Yes. The gateway rejects invalid orders with `400`. Inventory rejects empty titles. The gateway answers `502` when Inventory or RabbitMQ is down. Billing discards malformed messages instead of blocking the queue, and retries on database errors. |
| Monitoring, logging or security improvements? | Yes. Billing logs every stored or discarded message (`sudo pm2 logs billing_app`). PM2 restarts crashed apps and restores them on boot. The RabbitMQ UI shows the queue. RabbitMQ uses a dedicated user instead of `guest`, and each database has its own user. |
| Are the design choices justified? | See [architecture.md](architecture.md#design-choices). |
