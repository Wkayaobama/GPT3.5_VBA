---
name: apilogicserver-integration-patterns
description: Integration patterns for API Logic Server (Genai-Logic) - talking to external systems with business logic still enforced. Owns the request pattern (insert a SysEmail/SysMcp row; after_flush event performs the side effect), Kafka wiring (KAFKA_SERVER/KAFKA_PRODUCER/KAFKA_CONSUMER in config/config.py, send_kafka_message, FlaskKafka, kafka_subscribe_discovery, "Kafka mode - FALLBACK" degradation), MCP (Model Context Protocol - .well-known/mcp.json discovery, mcp_client_executor, SysMcp, genai-add-mcp-client, APILOGICSERVER_CHATGPT_APIKEY), B2B/EAI endpoints via RowDictMapper (OrderB2B, OrderShipping, dict_to_row/row_to_dict, lookups), and n8n webhooks (N8N_PRODUCER). Use when wiring ALS to Kafka, an AI assistant, a B2B partner, or n8n, or choosing between JSON:API, custom endpoint, Kafka, MCP, and B2B mapping; on symptoms "Kafka not enabled", "FALLBACK", "KAFKA NOT AVAILABLE FOR IMPORT", "mcp.json", "tool context", "RowDictMapper", "consume_debug", "webhook".
---

# API Logic Server Integration Patterns

## Purpose

This skill is the runbook for connecting an API Logic Server (ALS / Genai-Logic) project to the outside world — Kafka topics, AI assistants via MCP, B2B partners, n8n workflows — **without ever bypassing the rules engine**. The organizing principle: every inbound payload becomes SQLAlchemy rows saved through the session (so all rules fire), and every outbound side effect is triggered by a logic event after the transaction's data is validated. Facts labeled **verified 2026-08-23/24, Genai-Logic 17.03.19** were confirmed by reading two live-created projects (`basic_demo`, Northwind `nw+` sample) and by HTTP probes against a running server; external-broker and LLM-in-the-loop behavior is labeled **per docs, not live-verified**.

## Use this skill when

- Sending events to Kafka, n8n, email, or any external service from business logic
- Consuming Kafka messages into an ALS project
- Exposing the project to AI assistants via MCP, or running natural-language multi-step requests (`SysMcp`)
- Building a coarse-grained B2B endpoint that accepts a partner's JSON shape (`OrderB2B`-style)
- Deciding which channel to use: JSON:API, custom endpoint, Kafka, MCP, or B2B mapping
- Symptoms: "Kafka not enabled", "Kafka mode: FALLBACK", "SEVERE WARNING - KAFKA NOT AVAILABLE FOR IMPORT", messages sent but rules didn't run (or vice versa), MCP discovery returns 404, tool context malformed

## Do NOT use this skill when

- You need the event-rule *signatures* (`Rule.after_flush_row_event` parameters, one-per-class caution) or general rule authoring → **apilogicserver-logic-patterns**
- You need JSON:API grammar, `@jsonapi_rpc` custom-endpoint mechanics, `als login`/`als curl` → **apilogicserver-api-contract**
- You need JWT details, protecting endpoints, Grant/GlobalFilter → **apilogicserver-security-model**
- You need `config.py`/`default.env`/`APILOGICPROJECT_*` machinery in general → **apilogicserver-cli-and-config**
- You need to run servers, ports, containers → **apilogicserver-operate-and-deploy**
- You are landing the change → final gate is **apilogicserver-change-control**

Definitions used throughout: **JSON:API** = the standardized REST format ALS serves (`{data: {type, id, attributes}}`); **flush** = SQLAlchemy writing pending rows to the database inside the transaction, before commit; **after-flush event** = logic that runs after flush (rows validated, IDs assigned) but before the transaction ends; **JWT** = the signed login token sent as `Authorization: Bearer <token>`; **pub/sub** = publish a message to a named **topic**, any number of subscribers receive it; **webhook** = an HTTP POST to a URL that a workflow tool listens on.

---

## 0. The integration surface (60-second map)

Every created project ships an `integration/` tree (verified 2026-08-23, Genai-Logic 17.03.19, both projects):

| Path (project-relative) | What it is |
|---|---|
| `integration/kafka/kafka_producer.py` | Kafka send: `send_kafka_message()`, `send_row_to_kafka()`; connects at server start if configured |
| `integration/kafka/kafka_consumer.py` | Kafka listen: starts `FlaskKafka` thread if `KAFKA_CONSUMER` configured, else logs FALLBACK |
| `integration/kafka/kafka_subscribe_discovery/` | Drop-in topic handlers, auto-discovered; each file exposes `register(bus)` |
| `integration/kafka/kafka_publish_discovery/` | Drop-in publish mappers (EAI publish pattern) |
| `integration/kafka/message_formats/` | Sample inbound message JSON fixtures |
| `integration/kafka/dockercompose_start_kafka.yml` | Local Kafka broker for testing (per docs, not live-verified) |
| `integration/mcp/mcp_client_executor.py` | MCP client: NL query → LLM → tool context → JSON:API calls |
| `integration/mcp/mcp_server_discovery.json` | List of MCP servers the executor will discover |
| `integration/mcp/examples/` | Canned tool-context/discovery responses (run without an LLM key) |
| `integration/n8n/n8n_producer.py` | n8n webhook send: `send_n8n_message()` |
| `integration/row_dict_maps/` | `RowDictMapper` subclasses declaring message/API shapes (`OrderB2B.py`, `OrderShipping.py`, `OrderById.py`, `Customer_Orders.py` in nw sample) |
| `integration/system/RowDictMapper.py` | The mapper base class (row ⇄ dict with aliases, joins, lookups) |
| `integration/system/FlaskKafka.py` | Threaded Kafka consumer harness with `@bus.handle('topic')` decorator |
| `integration/system/EaiPublishMapper.py`, `EaiSubscribeMapper.py` | EAI mapper base classes |

The one invariant (see **apilogicserver-architecture-contract**): integrations never write to the database except through the SQLAlchemy session, and never call rules directly — they insert/update rows, and the rules react.

---

## 1. The request pattern — the house idiom for side effects

**The pattern**: to perform a side effect (send an email, run an MCP request, alert shipping), the client does not call a bespoke "do it" service. It **inserts a row into a request table** (`SysEmail`, `SysMcp`, ...). A declared `after_flush_row_event` on that table performs the side effect. The inserted row remains as the audit trail.

### 1a. Worked example, verbatim (verified 2026-08-23, Genai-Logic 17.03.19)

The request table — `basic_demo/database/models.py`:

```python
class SysEmail(Base):  # type: ignore
    __tablename__ = 'sys_email'
    _s_collection_name = 'SysEmail'  # type: ignore

    id = Column(Integer, primary_key=True)
    message = Column(String)
    subject = Column(String)
    customer_id = Column(ForeignKey('customer.id'), nullable=False)
    CreatedOn = Column(Date)

    # parent relationships (access parent)
    customer : Mapped["Customer"] = relationship(back_populates=("SysEmailList"))
```

The governing logic — `basic_demo/logic/logic_discovery/email_request.py` (verbatim, docstring elided):

```python
    def send_mail(row: models.SysEmail, old_row: models.SysEmail, logic_row: LogicRow):
        if logic_row.is_inserted():
            customer = row.customer  # parent accessor
            if customer.email_opt_out:
                logic_row.log("customer opted out of email")
                return
            logic_row.log(f"send email {row.message} to {customer.email} (stub, eg use N8N")  # see in log

    Rule.after_flush_row_event(on_class=models.SysEmail, calling=send_mail)  # see above
```

To request an email, any client — admin app, curl, MCP executor — POSTs a `SysEmail` row through the ordinary JSON:API (payload shape: **apilogicserver-api-contract**). Nothing else to build.

### 1b. Why this beats calling services from controllers

| Property | Request pattern (insert a row) | Service call inside a controller |
|---|---|---|
| Logic-governed | Rules wrap the request — here, `email_opt_out` is enforced no matter which client asks | Each controller must re-implement the check; new entry points forget it |
| One implementation, every access path | UI, JSON:API, MCP, Kafka consumer all insert the same row | One path per controller; drift guaranteed |
| Audit trail | The row *is* the record: who, what, when (`CreatedOn`, stamping — see **apilogicserver-logic-patterns**) | Logging is ad hoc or absent |
| Testable | Behave test inserts a row, asserts the logic log (see **apilogicserver-validation-and-qa**) | Requires mocking the controller layer |
| Replayable | Rows persist; a failed side effect can be found and reprocessed | Lost unless you built retry infrastructure |
| Transaction-consistent | `after_flush` runs only after the transaction's data passed all constraints and was flushed | Side effect may fire on data that later fails validation |

Honest limits (do not oversell): ALS gives you the hook and the durable request row, not delivery guarantees. The send happens in the after-flush phase, which is *inside* the request but *not atomic with* the commit — a crash between flush and commit could send without persisting, and reprocessing failed rows is machinery you add yourself. For at-least-once delivery to another *system*, put Kafka behind the event (section 2).

The same shape powers MCP: `genai-add-mcp-client` adds a `SysMcp` request table whose insert event runs the whole natural-language flow (section 3e).

---

## 2. Kafka — async messaging with logic still enforced

Kafka is a message broker: producers publish messages to topics; consumers subscribe. Use it when the receiving system may be down (guaranteed async delivery) or when several systems must react to one event (multi-cast pub/sub) — per docs (Sample-Integration), not live-verified against a broker.

### 2a. Where configuration lives — exact names (verified 2026-08-23, Genai-Logic 17.03.19)

All Kafka settings live in `config/config.py`, class `Config`, keyed off one environment variable. Verbatim from a created project:

```python
    KAFKA_PRODUCER = None
    KAFKA_CONSUMER = None
    KAFKA_CONSUMER_GROUP = None
    KAFKA_SERVER = None
    KAFKA_SERVER = os.getenv('KAFKA_SERVER', None) # 'localhost:9092' # if running locally default
    if KAFKA_SERVER is not None and KAFKA_SERVER != "None" and KAFKA_SERVER != "":
        app_logger.info(f'config.py - KAFKA_SERVER: {KAFKA_SERVER}')
        KAFKA_PRODUCER = os.getenv('KAFKA_PRODUCER',{"bootstrap.servers": f"{KAFKA_SERVER}"})
        KAFKA_CONSUMER_GROUP = os.getenv('KAFKA_CONSUMER_GROUP') #'als-default-group1'
        if KAFKA_CONSUMER_GROUP is not None:
            KAFKA_CONSUMER =  os.getenv('KAFKA_CONSUMER', {"bootstrap.servers": f"{KAFKA_SERVER}",
                "group.id": f"{KAFKA_CONSUMER_GROUP}", "enable.auto.commit": "false", "auto.offset.reset": "earliest"})
```

So the minimal enable is two lines in `config/default.env` (the nw sample ships them commented; verified):

```text
KAFKA_SERVER = localhost:9092
KAFKA_CONSUMER_GROUP = <project>-group1   # consumer only; keep unique per project clone
```

Full-dict overrides also exist (verified as commented examples in `config/default.env` and `Args` properties): `APILOGICPROJECT_KAFKA_PRODUCER = "{\"bootstrap.servers\": \"localhost:9092\"}"` and `APILOGICPROJECT_KAFKA_CONSUMER = "{...full consumer dict...}"` — if you set the full consumer dict, keep `group.id` aligned with `KAFKA_CONSUMER_GROUP`. Runtime access is via `Args.instance.kafka_producer` / `.kafka_consumer` / `.kafka_consumer_group` (general config machinery: **apilogicserver-cli-and-config**).

### 2b. Graceful degradation — the verified messages

Kafka being absent never breaks the server or the transaction. Three layers (all verified 2026-08-23, Genai-Logic 17.03.19):

1. **Library missing** — `kafka_producer.py`/`kafka_consumer.py` guard the import; if `confluent_kafka` cannot import, they log `SEVERE WARNING - KAFKA NOT AVAILABLE FOR IMPORT - DISABLED` and disable themselves.
2. **Broker unconfigured** — at server start, `integration/kafka/kafka_consumer.py` logs (verified live at startup): `Kafka mode: FALLBACK — KAFKA_SERVER not configured; running debug endpoint only`. When configured it logs `Kafka mode: ACTIVE (broker=..., group=...)` instead (from the same file; ACTIVE path not live-verified).
3. **Send while unconfigured** — `send_kafka_message` appends `[Note: **Kafka not enabled** ]` to the logic log and returns; the transaction commits normally.

Expect these lines; do not treat them as errors. If you *expected* Kafka to be live, they are your first diagnostic (then check `KAFKA_SERVER` in the environment).

### 2c. The producer rule — verbatim

Declarative form (`basic_demo/logic/declare_logic.py`, verified 2026-08-23, Genai-Logic 17.03.19):

```python
import integration.kafka.kafka_producer as kafka_producer
...
    # Send order details to Kafka if order is shipped.
    Rule.after_flush_row_event(on_class=Order, calling=kafka_producer.send_row_to_kafka,
        if_condition=lambda row: row.date_shipped is not None, with_args={'topic': 'order_shipping'})
```

`send_row_to_kafka(row, old_row, logic_row, with_args)` is the generic shipped handler; `with_args["topic"]` names the topic. Handler form with a declared message shape (`nw_sample/logic/logic_discovery/order_place/app_integration.py`, verbatim core):

```python
    def send_order_to_shipping(row: Order, old_row: Order, logic_row: LogicRow):
        if (logic_row.is_inserted() and row.Ready == True) or \
            (logic_row.is_updated() and row.Ready == True and old_row.Ready == False):
            kafka_producer.send_kafka_message(logic_row=logic_row,
                                              row_dict_mapper=OrderShipping,  # omit to just send order header
                                              kafka_topic="order_shipping",
                                              kafka_key=str(row.Id),
                                              msg="Sending Order to Shipping")

    Rule.after_flush_row_event(on_class=Order, calling=send_order_to_shipping)
```

Why after-flush: the Order's autoincrement `Id` exists only after flush, and all constraints have already passed — you never publish an invalid or half-derived row. Event signature details and the one-after-flush-event-per-class caution: **apilogicserver-logic-patterns**.

### 2d. `send_kafka_message` — three payload forms (verified from `integration/kafka/kafka_producer.py`)

```python
def send_kafka_message(kafka_topic: str, kafka_key: str = None, msg: str = "", json_root_name: str = "",
                       logic_row: LogicRow = None, row_dict_mapper: RowDictMapper = None, payload: dict = None)
```

| You pass | What is sent |
|---|---|
| `payload={...}` | your dict, verbatim |
| `logic_row=` + `row_dict_mapper=SomeMapper` | the row shaped by the mapper (aliases, nested children — section 4) |
| `logic_row=` only | all columns of the row (generic `RowDictMapper(model_class=...)`) |

`kafka_key` defaults to the row's primary key dict. The producer calls `producer.flush(timeout=10)` after each send, so delivery failures surface in the log rather than dying silently in a buffer. `nw_sample/logic/logic_discovery/integration.py` demonstrates all three forms on Customer events (verified on disk).

### 2e. Consumer side (shipped code verified on disk; behavior with a live broker per docs, not live-verified)

Do **not** edit `integration/kafka/kafka_consumer.py` to add handlers. Drop a file into `integration/kafka/kafka_subscribe_discovery/` exposing `register(bus)` — auto-discovered and registered before the bus runs (verified from `auto_discovery.py`):

```python
def register(bus):
    @bus.handle('order_shipping')          # topic name
    def order_shipping(msg, safrs_api):    # msg is a confluent_kafka Message
        ...  # parse msg.value(), create rows, session.add(...) -> all rules fire
```

Key consumer facts (verified from `integration/system/FlaskKafka.py` and `kafka_readme.md`):

- **Offsets are not committed by default.** `enable.auto.commit=false` and the `consumer.commit(asynchronous=False)` line in `FlaskKafka._run_handlers()` ships commented out — every server restart replays all messages from `earliest`. Intentional for dev/demo. For production at-least-once delivery, uncomment that line.
- **Two-message (blob) pattern** for robust inbound EAI: Tx 1 saves the raw JSON payload to a blob/message table (always commits — no data loss if parsing fails); Tx 2 parses it into real rows (Order + Items), resolves foreign keys, and saves through the session so LogicBank rules run. An `is_processed` guard makes replays a safe no-op. Per docs (Integration-EAI) and `kafka_readme.md`; not live-verified.
- **Debug endpoint without Kafka**: set `APILOGICPROJECT_CONSUME_DEBUG = true` in `config/default.env` (the nw sample ships it set — verified), then:

```bash
curl 'http://localhost:5656/consume_debug/<topic>?file=integration/kafka/message_formats/<topic>.json'
# expect: {"success": true, "topic": "<topic>", "blob_id": 1}   (per readme; endpoint generated per-topic)
```

- Reset helpers between reruns (per `kafka_readme.md`): `bash integration/kafka/<topic>_reset_db.sh` (clear domain/blob tables), `bash integration/kafka/<topic>_reset.sh` (recreate topics, live-Kafka runs only). Run from the project root. Run exactly one server process during consume testing; keep the consumer group unique per project clone.

### 2f. Local broker bring-up (per docs, not live-verified)

```bash
# 1. hosts entry (docs: /etc/hosts):  127.0.0.1       broker1
docker compose -f integration/kafka/dockercompose_start_kafka.yml up -d
# 2. create the topic (inside the container):
docker exec -it broker1 bash
/opt/kafka/bin/kafka-topics.sh --create --bootstrap-server localhost:9092 --replication-factor 1 --partitions 3 --topic order_shipping
```

Then set `KAFKA_SERVER` (2a) and start the server. The docs' Sample-Integration runs two ALS projects — an order producer and a `shipping` consumer created with `genai-logic create --project_name=shipping --db_url=shipping`, on a different port (ports/operation: **apilogicserver-operate-and-deploy**).

### 2g. Kafka vs a direct API call

Choose Kafka when: the receiver may be down (broker stores and forwards); more than one system must react (pub/sub); you must not couple your transaction's latency/success to the receiver. Choose a synchronous API call (JSON:API or custom endpoint) when: the caller needs the answer now (a computed result, a validation verdict); there is exactly one receiver you own; or you have no broker to operate. Full comparison: section 7.

---

## 3. MCP — the project as a tool for AI assistants

**MCP (Model Context Protocol)** is a standard by which AI assistants discover and call tools — here, the project's rule-enforced JSON:API. Two halves, with different maturity (labels per docs, Integration-MCP):

| Half | What it is | Status per docs |
|---|---|---|
| MCP **server** executor | The project publishes discovery at `/.well-known/mcp.json`; any MCP client can find and call its endpoints | GA (production) |
| MCP **client** executor | `integration/mcp/mcp_client_executor.py` — takes a natural-language request, plans with an LLM, executes the plan against MCP servers | **Tech Preview** — do not oversell |

The governance story is the point: whatever the LLM plans, execution is plain JSON:API POST/PATCH/GET against the server, so **all declared rules fire on every write**. An AI cannot route around the credit-limit check.

### 3a. Server side — discovery, live-probed

Live probe (verified 2026-08-24 against the running `nw+` sample server, Genai-Logic 17.03.19, security enabled):

```bash
curl -X GET "http://localhost:5656/.well-known/mcp.json"
```

Result: **HTTP 200 — with or without an `Authorization: Bearer` token, identical body** (both probed). Shape (trimmed; full body ~6 KB):

```json
{"base_url": "http://localhost:5656/api",
 "description": "API Logic Project: nw_sample",
 "learning": "To issue one request per row from a prior step (fan-out), use the syntax:\n\n\"$<stepIndex>[*].<fieldName>\"\n ... <mcp_responseFormat> ... ",
 "resources": [
   {"name": "Customer", "path": "/Customer",
    "fields": ["Id", "CompanyName", "...", "Balance", "CreditLimit"],
    "filterable": ["Id", "CompanyName", "..."],
    "methods": ["GET", "PATCH", "POST", "DELETE"]},
   ... 17 resources total ...],
 "schema_version": "1.0",
 "tool_type": "json-api"}
```

**Security caution (verified)**: the discovery route is a plain Flask `@app.route` in `api/api_discovery/mcp_discovery.py` with no JWT guard — schema metadata (table and column names) is readable without login even when security is on. The *data* endpoints it points at remain JWT-protected. If schema disclosure matters in your deployment, guard this route (**apilogicserver-security-model**) and gate the change via **apilogicserver-change-control**.

What discovery serves (verified from `mcp_discovery.py`): it reads `docs/mcp_learning/mcp_schema.json` (the resources) and `docs/mcp_learning/mcp.prompt` (the "learning" — LLM training text covering fan-out syntax and the required response format), merges them, returns JSON. Missing files → 404 with an error body naming the missing file. Edit `mcp.prompt` to tune LLM behavior for your project.

### 3b. Client executor flow (Tech Preview per docs; code verified on disk, LLM leg not live-verified)

`integration/mcp/mcp_client_executor.py` implements, in order (function names verified):

1. **Discover** — `discover_mcp_servers()` reads `integration/mcp/mcp_server_discovery.json` (verbatim, basic_demo):

```json
{"servers": [{"name": "API Logic Server: basic_demo",
              "base_url": "http://localhost:5656",
              "schema_url": "http://localhost:5656/.well-known/mcp.json"}]}
```

   then GETs each `schema_url`. Add external MCP servers by adding entries here.
2. **Plan** — `query_llm_with_nl()` sends NL query + learnings + schema to the LLM (`openai.api_key = os.getenv("APILOGICSERVER_CHATGPT_APIKEY")` — that env var is required for a real LLM call), which returns a **Tool Context Block**: a JSON plan `{schema_version, resources: [steps]}`, each step giving `tool_type: "json-api"`, `base_url`, `path`, `method`, and `query_params` (GET filter) or `body` (POST/PATCH).
3. **Execute** — `process_tool_context()` iterates the steps, translating `query_params` into the JSON:API `filter=[{name,op,val}]` grammar (**apilogicserver-api-contract**) and issuing real HTTP requests. **Fan-out**: a body value like `"$0[*].customer_id"` means "repeat this step once per row returned by step 0, substituting that row's attribute". Inside a Flask request context the executor forwards the caller's request headers, so its JSON:API calls carry the caller's JWT (verified in `execute_api_step`).
4. **Results** — step results are collected and printed as tables.

Canned example of a Tool Context Block (verbatim, `integration/mcp/examples/mcp_tool_context_response.json` — GET unshipped old orders, then fan-out a `SysEmail` POST per order; note step 2 is the section-1 request pattern):

```json
{"schema_version": "1.0",
 "resources": [
  {"tool_type": "json-api", "base_url": "http://localhost:5656/api", "path": "/Order", "method": "GET",
   "query_params": [{"name": "date_shipped", "op": "eq", "val": "null"},
                     {"name": "CreatedOn", "op": "lt", "val": "2023-07-14"}]},
  {"tool_type": "json-api", "base_url": "http://localhost:5656/api", "path": "/SysEmail", "method": "POST",
   "body": {"subject": "Discount Offer",
            "message": "Dear customer, we are offering a discount on your next purchase. Please check your account for more details.",
            "customer_id": "$0[*].customer_id"}}]}
```

### 3c. `SysMcp` — MCP requests via the request pattern

With the client installed, users trigger the whole flow by inserting one row (verbatim curl from the executor's docstring; POST not executed here — writes to the live server were out of scope):

```bash
curl -X 'POST' 'http://localhost:5656/api/SysMcp/' -H 'accept: application/vnd.api+json' -H 'Content-Type: application/json' -d '{ "data": { "attributes": {"request": "List the orders date_shipped is null and CreatedOn before 2023-07-14, and send a discount email (subject: '\''Discount Offer'\'') to the customer for each one."}, "type": "SysMcp"}}'
```

Or type the same sentence into the Admin App's SysMcp screen. The insert's after-flush event runs `mcp_client_executor(request)` — NL in, governed API calls out, and the SysMcp row is the audit trail.

### 3d. Installing the client — `genai-add-mcp-client`

Verified 2026-08-23, Genai-Logic 17.03.19 (`als genai-add-mcp-client --help`, verbatim):

```text
Usage: als genai-add-mcp-client [OPTIONS]

  Adds mcp-client to project: db, logic, admin app

Options:
  --admin-app  Update Admin App
  --help       Show this message and exit.
```

Per docs it (1) creates the `SysMcp` table, (2) adds the after-flush logic, (3) customizes the Admin App — effects not executed here (mutating CLI was out of scope). **NL-column name — a real docs-vs-install divergence (noted 2026-08-25):** the docs' Integration-MCP page says the table "requires a column called `prompt`", but the shipped 17.03.19 executor's own curl examples (its docstring; quoted in §3c above) POST attribute `request`. Neither project here has run the command, so the created column is unverifiable in this workspace — go with `request` per the shipped source, and verify right after running `genai-add-mcp-client` (`grep -n -A 8 "class SysMcp" database/models.py`). Verified negative: a fresh `basic_demo` has `SysEmail` but **no** `SysMcp` in `database/models.py` until this command runs. It is a schema + logic change: run it through **apilogicserver-change-control** gates like any other.

### 3e. Trying MCP without an LLM key (verified on disk)

`mcp_client_executor.py` ships with `create_tool_context_from_llm = False` — the LLM call is bypassed and a canned tool context is read from `integration/mcp/examples/` (`..._response_get.json`, or `..._response.json` when the query contains "email"). So the full discover → plan → execute loop runs with no `APILOGICSERVER_CHATGPT_APIKEY`. Set the flag to `True` for real planning. Standalone run: `python integration/mcp/mcp_client_executor.py` (server must be running).

Related but distinct (per docs, Integration-OpenAI-Function): exposing ALS as a ChatGPT "Action" via an ngrok tunnel and a reduced OpenAPI 3 spec. The docs label it "an initial experiment, without automation" with known PATCH-payload failures — status "Initial Test Running". Treat as exploratory only; not live-verified.

---

## 4. EAI / B2B — coarse-grained endpoints where all rules fire

**EAI** (Enterprise Application Integration) / **B2B** (business-to-business) here means: accept a partner's agreed JSON document (an order with items, partner field names), map it onto model rows, and save through the session — so the *entire* rule chain (pricing, totals, credit check) governs the partner's transaction exactly as it governs the admin app's. The mapping is declared once, in a **RowDictMapper**.

### 4a. `RowDictMapper` — the mapping class (verified from `integration/system/RowDictMapper.py`)

Constructor (verbatim signature, docstring elided):

```python
class RowDictMapper():
    def __init__(self
            , model_class: type[DefaultMeta] | None   # models.EntityName (required)
            , logic_row: LogicRow = None
            , alias: str = ""                         # name of this level in the dict
            , role_name: str = ""                     # disambiguate multiple relationships
            , fields: list[tuple[Column, str] | Column] = []   # tuple = (column, "Alias")
            , parent_lookups = None                   # find parent row by fields, set FK
            , lookup: list[tuple[Column, str] | Column] = None # FK lookup ("*" = use fields)
            , related: list[Self] | Self = []         # nested child mappers
            , isParent: bool = False                  # many-to-one (defaults True if lookup)
            , isCombined: bool = True                 # merge parent fields into this level
            ):
```

Two methods do the work: `row_to_dict(row)` — outbound, SQLAlchemy row → partner-shaped dict; `dict_to_row(row_dict, session)` — inbound, partner dict → SQLAlchemy row graph ready to `session.add()`. **Lookups** are the key trick: partners send `ProductName`, your model needs `ProductId` — a lookup finds the parent row by the named fields and sets the foreign key automatically (per docs Integration-Map; class verified on disk).

### 4b. A real inbound mapping — `OrderB2B` (verbatim, `nw_sample/integration/row_dict_maps/OrderB2B.py`)

```python
class OrderB2B(RowDictMapper):

    def __init__(self, logic_row: LogicRow = None):
        order = super(OrderB2B, self).__init__(
            model_class=models.Order
            , alias = "order"
            , fields = [(models.Order.CustomerId, "AccountId")]
            , parent_lookups = [( models.Employee,
                                  [(models.Employee.LastName, 'Surname'), (models.Employee.FirstName, 'Given')] )]
            , related = [
                (RowDictMapper(model_class=models.OrderDetail
                    , alias="Items"
                    , fields = [(models.OrderDetail.Quantity, "QuantityOrdered")]
                    , parent_lookups = [( models.Product, [models.Product.ProductName] )]
                    )
                )
            ]
        )
        return order
```

Read it as: the partner's `AccountId` is our `Order.CustomerId`; `Surname`/`Given` look up the Employee (sales rep) to set the FK; each `Items` entry maps `QuantityOrdered` to `OrderDetail.Quantity` and looks up the Product by `ProductName`.

### 4c. The endpoint — 5 lines, and every rule fires (verbatim core, `nw_sample/api/customize_api.py`)

```python
class ServicesEndPoint(safrs.JABase):

    @classmethod
    @jsonapi_rpc(http_methods=["POST"])
    def OrderB2B(self, *args, **kwargs):
        db = safrs.DB         # Use the safrs.DB, not db!
        session = db.session  # sqlalchemy.orm.scoping.scoped_session

        order_b2b_def = OrderB2B()  # a RowDictMapper
        request_dict_data = request.json["meta"]["args"]["order"]
        sql_alchemy_row = order_b2b_def.dict_to_row(row_dict = request_dict_data, session = session)
        sql_alchemy_row.Ready = True

        session.add(sql_alchemy_row)
        return {"Thankyou For Your OrderB2B"}  # automatic commit, which executes transaction logic
```

That final `session.add` is the whole governance story: copy/formula/sum/constraint chain, credit check, and the Kafka `send_order_to_shipping` event (2c) all fire — zero logic in the endpoint. Verified live: `/ServicesEndPoint/OrderB2B` (plus `add_order`, `add_order_by_id` — hand-mapped contrast examples) is present in the running server's `/api/swagger.json` (verified 2026-08-24). Endpoint registration (`api.expose_object(ServicesEndPoint)`, `@jsonapi_rpc` mechanics): **apilogicserver-api-contract**.

Test command (verbatim from the endpoint docstring; uses the `als` curl helper — POST not executed here):

```bash
ApiLogicServer login --user=admin --password=p
ApiLogicServer curl "'POST' 'http://localhost:5656/api/ServicesEndPoint/OrderB2B'" --data '
{"meta": {"args": {"order": {
    "AccountId": "ALFKI", "Surname": "Buchanan", "Given": "Steven",
    "Items": [{"ProductName": "Chai", "QuantityOrdered": 1},
              {"ProductName": "Chang", "QuantityOrdered": 2}]}}}}'
```

### 4d. A real outbound mapping — `OrderShipping` (verbatim, `nw_sample/integration/row_dict_maps/OrderShipping.py`)

```python
class OrderShipping(RowDictMapper):

    def __init__(self, logic_row: LogicRow = None):
        order = super(OrderShipping, self).__init__(
            model_class=models.Order
            , alias = "order"
            , fields = [models.Order.Id, (models.Order.AmountTotal, "Total"),
                        (models.Order.OrderDate, "Order Date"), models.Order.CustomerId]
            , related = RowDictMapper(model_class=models.OrderDetail, alias="Items"
                , fields = [models.OrderDetail.OrderId, models.OrderDetail.Quantity, models.OrderDetail.Amount]
                , related = RowDictMapper(model_class=models.Product, alias="product"
                    , fields=[models.Product.ProductName, models.Product.UnitPrice, models.Product.UnitsInStock]
                    , isParent=True
                )
            )
        )
        return order
```

Used as `row_dict_mapper=OrderShipping` in the Kafka send (2c): one declaration, and shipping receives orders with aliased fields, nested Items, and joined-in parent Product data. New mappers go in `integration/row_dict_maps/`, one class per file.

---

## 5. n8n — webhook workflow integration

n8n is a workflow-automation tool (400+ prebuilt integrations — email, Slack, CRMs); ALS posts to an n8n **webhook** node, and the workflow takes it from there. One shipped producer, `integration/n8n/n8n_producer.py` (import in `declare_logic.py` verified: `from integration.n8n.n8n_producer import send_n8n_message`); a ready-to-import workflow ships at `integration/n8n/N8N_WebHook_from_ApiLogicServer.json`. Live n8n behavior: per docs, not live-verified.

Configuration lives in `config/config.py`, class `Config` (verbatim, verified — ships disabled):

```python
    wh_scheme = "http"
    wh_server = "localhost" # or cloud.n8n.io...
    wh_port = 5678
    wh_endpoint = "webhook-test" # This comes from the WebHook node in n8n
    wh_path = "002fa0e8-f7aa-4e04-b4e3-e81aa29c6e69" # This comes from the WebHook node in n8n
    wh_token = "YWRtaW46cA==" # base64 of username:password
    N8N_PRODUCER = {"authorization": f"Basic {wh_token}", "n8n_url": f'"{wh_scheme}://{wh_server}:{wh_port}/{wh_endpoint}/{wh_path}"'}
    N8N_PRODUCER = None # comment out to enable N8N producer
```

Environment overrides (verified in `n8n_producer.py`): `N8N_TOKEN`, `N8N_SCHEME`, `N8N_SERVER`, `N8N_PORT`, `N8N_ENDPOINT`, `N8N_PATH`, `N8N_PRODUCER`. Usage is the same event idiom — from `order_place/app_integration.py` (verbatim fragment): `send_n8n_message(payload={...}, ins_upd_dlt="upd", wh_entity="Order", msg="...")` inside an after-flush event. The producer POSTs the payload with headers `wh_state` (ins/upd/dlt), `wh_entity`, `wh_source: api_logic_server`, and Basic auth. Setup walkthrough: `integration/n8n/n8n_readme.md`.

---

## 6. Choosing a channel — decision table

| Channel | Direction | Coupling | Delivery / latency | Logic governance | Choose when |
|---|---|---|---|---|---|
| Standard JSON:API | Inbound | Low — self-serve, any client | Synchronous | All rules fire on every write (engine-enforced) | Ad-hoc integration, UIs, scripts; partner can adapt to your schema |
| Custom endpoint + RowDictMapper (B2B) | Inbound | Medium — a negotiated document contract | Synchronous | All rules fire (`dict_to_row` → `session.add`) | Partner dictates the payload shape; coarse-grained one-call transactions |
| Request pattern (SysEmail / SysMcp) | Inbound trigger, outbound effect | Low — it's just a row insert | Synchronous insert, effect at after-flush | Rules wrap the request itself (e.g. opt-out) | Any side-effect service you want governed, audited, and callable from every client |
| Kafka publish | Outbound | Lowest — receivers unknown to sender | Async, broker-guaranteed (per docs); survives receiver downtime | Fires only after the transaction's rules passed (after-flush) | Notify other systems; receiver may be down; multiple receivers |
| Kafka consume | Inbound | Low — topic contract | Async; replay semantics per offset config (2e) | Handler saves via session → all rules fire | Accept events from systems you don't control synchronously |
| MCP | Inbound (AI-planned) | Low — discovery-driven | Synchronous per step | Every step is a JSON:API call → rules fire; client executor is Tech Preview | AI assistants / NL multi-step flows over governed data |
| n8n webhook | Outbound | Medium — URL + workflow contract | Synchronous POST to the webhook | Fires at after-flush | Fan out to SaaS actions (email, chat, CRM) without writing connectors |

Any inbound channel that does NOT end in `session.add()` on model rows is a bug: it bypasses the engine (see the direct-SQL weak point in **apilogicserver-architecture-contract**).

## 7. Cautions

- **After-flush send is not atomic with commit.** The message can be sent even if the commit subsequently fails (rare, but real). For strict consistency, insert an outbox/request row instead and relay it separately.
- **One after-flush event per class is honored** — consolidate Kafka + n8n + email work for a class into one handler (**apilogicserver-logic-patterns**, Common mistakes).
- **Dev consumer replays everything** on restart (offsets uncommitted, 2e). Fine in dev because of the `is_processed` guard; a production deploy must enable the commit line.
- **MCP discovery is unauthenticated** (verified, 3a). Decide deliberately whether that is acceptable.
- **The MCP client executor is Tech Preview** (per docs). Ship the server side; pilot the client side.
- **`get`/`filter` names must match model attributes** — the LLM learning file (`docs/mcp_learning/mcp.prompt`) is where you correct systematic naming mistakes, not the executor code.
- Adding any integration (new mapper, topic handler, endpoint, config flag) is a customization-layer change: name the file, test it (Behave: **apilogicserver-validation-and-qa**), and land it through **apilogicserver-change-control**.

## Provenance and maintenance

Volatile facts and how to re-verify each (run from any created project's root, venv active):

- Kafka config names/defaults — `grep -n "KAFKA_" config/config.py config/default.env`
- FALLBACK message text and consumer discovery — `grep -rn "FALLBACK\|register(bus)" integration/kafka/`
- Producer rule and imports — `grep -rn "after_flush_row_event\|send_kafka_message" logic/`
- MCP discovery live shape — `curl -X GET "http://localhost:5656/.well-known/mcp.json"` (server running)
- MCP discovery source files — `ls docs/mcp_learning/ integration/mcp/`
- `genai-add-mcp-client` options — `als genai-add-mcp-client --help`
- SysMcp presence (before/after add) — `grep -n "SysMcp\|SysEmail" database/models.py`
- SysMcp NL-column name (docs say `prompt`, shipped 17.03.19 executor examples say `request` — divergence noted 2026-08-25) — after running `genai-add-mcp-client`: `grep -n -A 8 "class SysMcp" database/models.py`; executor side: `grep -n '"request"\|"prompt"' integration/mcp/mcp_client_executor.py`
- RowDictMapper signature and mappers — `ls integration/row_dict_maps/ && grep -n "def __init__" integration/system/RowDictMapper.py`
- B2B endpoint registration — `grep -n "OrderB2B\|expose_object" api/customize_api.py` and check `/api/swagger.json`
- n8n config block and env overrides — `grep -n "N8N\|wh_" config/config.py integration/n8n/n8n_producer.py`
- Consumer offset policy — `grep -n "commit" integration/system/FlaskKafka.py`
- Debug-consume flag — `grep -n "CONSUME_DEBUG" config/default.env`

Grounded in: https://apilogicserver.github.io/Docs/Integration-MCP/, https://apilogicserver.github.io/Docs/Integration-Kafka/, https://apilogicserver.github.io/Docs/Integration-Map/, https://apilogicserver.github.io/Docs/Integration-EAI/, https://apilogicserver.github.io/Docs/Sample-Integration/, https://apilogicserver.github.io/Docs/Integration-OpenAI-Function/ and a live Genai-Logic 17.03.19 install (2026-08-23) — sample projects and the running Northwind server were probed in place (read-only; no broker, LLM, or n8n instance was exercised).
