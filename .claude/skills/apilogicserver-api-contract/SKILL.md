---
name: apilogicserver-api-contract
description: JSON:API usage contract for API Logic Server (Genai-Logic) projects - reading data with page[limit]/page[offset], sort, filter[attr] and the extended filter=[{name,op,val}] grammar, fields[Type] projection, include= compound documents; writing with PATCH/POST/DELETE {data:{type,id,attributes}} payloads that always run business logic; error shapes (400 code 2001 constraint, 401 Missing Authorization Header, 404 NotFoundError); optimistic locking via S_CheckSum; custom endpoints (api/api_discovery add_service template, api/customize_api.py ServicesEndPoint with @jsonapi_rpc, expose_object); Swagger UI at /api, als login and als curl helpers. Use when calling or testing the API, building or debugging a client, writing curl/requests calls, adding a custom endpoint, or on symptoms "how do I filter/sort/paginate", "include related data", "PATCH returns 400", "code 2001", "Missing Authorization Header", "Sorry, row altered by another user", "S_CheckSum", "endpoint not in swagger", "jsonapi_rpc", "add_order".
---

# API Logic Server — API Contract

## Purpose

This skill is the wire-level contract of an API Logic Server (ALS / Genai-Logic) project's API: every read feature with a URL that was actually executed against a live 17.03.19 server, the exact write payload shapes, the error responses byte-for-byte, the optimistic-locking flow, the two custom-endpoint patterns, and the tooling (Swagger, `als login`/`als curl`). Facts labeled **verified 2026-08-23, Genai-Logic 17.03.19** were confirmed by live HTTP probes, by reading the installed sample projects, or by the passing Behave suite executed in the same install; everything else is labeled **per docs, not live-verified**.

## Use this skill when

- Writing or debugging any HTTP call to an ALS server — curl, Python `requests`, Postman, a frontend, another service.
- You need exact syntax for pagination, sorting, filtering, field projection, or related-data retrieval.
- A write returned 400/401/404/422 and you need to interpret the body.
- Handling or testing optimistic locking (`S_CheckSum`).
- Adding a custom endpoint (Flask route, `api_discovery` service, or Swagger-visible `jsonapi_rpc`).
- Deciding between self-serve JSON:API, a custom endpoint, or an integration mechanism.

## Do NOT use this skill when

- Declaring or fixing the business rules a write triggers → **apilogicserver-logic-patterns** (practice) / **declarative-rules-reference** (theory).
- Activating security, roles, `Grant`/`GlobalFilter`, token providers → **apilogicserver-security-model** (this skill only shows the login handshake needed to call the API).
- Kafka, MCP, B2B/EAI, n8n, the request pattern → **apilogicserver-integration-patterns**.
- Starting/stopping servers, ports, containers, admin app operation → **apilogicserver-operate-and-deploy**.
- CLI flags, `config/config.py`, env vars (e.g. `OPT_LOCKING` values) → **apilogicserver-cli-and-config**.
- Which files a rebuild overwrites, merge discipline → **apilogicserver-change-control**.
- Model/relationship names (`OrderList`, accessors, keys) → **apilogicserver-data-modeling**.

---

## 1. What the API is (JSON:API in three sentences)

**JSON:API** is a specification (jsonapi.org, `"jsonapi": {"version": "1.0"}` in every response) for REST payloads: every row is a *resource object* with `type` (class name, e.g. `"Customer"`), `id` (always serialized as a string in responses), `attributes` (the column values), and `relationships` (links/refs to parent and child resources). Related rows requested via `include=` arrive in a top-level `included[]` array alongside `data` — one response carrying several resource types is a *compound document*, which is how ALS serves a multi-table tree in one round trip. ALS generates one JSON:API endpoint per table (`/api/<Type>/`) with GET/POST/PATCH/DELETE, self-serve query parameters, and Swagger — and **every write runs the full rule chain** (see §8).

Verified 2026-08-23, Genai-Logic 17.03.19 against the running Northwind sample (`als create --db-url=nw+`, security enabled). All URLs below are relative to `http://localhost:5656`; substitute your host/port. If your shell forces localhost through an HTTP proxy, add `--noproxy '*'` to curl.

## 2. Base URLs and the authentication handshake (verified)

| URL | What it is | Verification |
|---|---|---|
| `GET /` | 302 redirect → `/admin-app/index.html` (admin web app) | verified |
| `GET /api` | Swagger UI (HTML page, title "Swagger UI") | verified |
| `GET /api/swagger.json` | OpenAPI 2.0 spec: `{"swagger": "2.0", "info": {"title": "API Logic Server", ...}, "basePath": "/api", ...}` | verified |
| `GET /api/<Type>/` | JSON:API collection per table/class | verified |
| `POST /api/auth/login` | Token endpoint when security is on. Bare `/auth/login` (no `/api`) is 404 — the prefix is `Config.CREATED_API_PREFIX` = `/api` | verified |

With security enabled, obtain a **JWT** (JSON Web Token — a signed bearer credential) and send it on every call:

```bash
curl -s -X POST http://localhost:5656/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"p"}'
# → {"access_token": "eyJhbGciOiJIUzI1..."}     (verified)

TOKEN=<paste access_token>
curl -s -H "Authorization: Bearer $TOKEN" "http://localhost:5656/api/Customer/?page%5Blimit%5D=1"
```

Sample users: `admin`/`p` (full access, verified live); the shipped Behave tests default to `aneu`/`p` (code-verified in `test/api_logic_server_behave/features/steps/test_utils.py`). Roles, row filtering, and providers: **apilogicserver-security-model**.

## 3. Read cookbook — every feature with a URL that ran (verified 2026-08-23, Genai-Logic 17.03.19)

`[` and `]` must be percent-encoded (`%5B`, `%5D`) for curl (unencoded brackets trigger curl URL globbing); Swagger and `requests` encode them for you. Every URL in this section was executed against the live server; response excerpts are real, trimmed with `...`.

### 3.1 Collection GET + pagination — `page[limit]`, `page[offset]`

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:5656/api/Customer/?page%5Blimit%5D=2&page%5Boffset%5D=2"
```

Trimmed real response — note `meta` counts and ready-made `links` for paging:

```json
{ "data": [
    { "type": "Customer", "id": "ANTO",
      "attributes": { "Id": "ANTO", "CompanyName": "Antonio Moreno Taquería",
                      "Balance": 0.0, "CreditLimit": 100.0,
                      "S_CheckSum": "2338e0dddc197cb4...", "...": "..." },
      "relationships": { "OrderList": { "data": [],
          "links": { "self": "/api/Customer/ANTO/OrderList" } } },
      "links": { "self": "/api/Customer/ANTO/" } },
    { "type": "Customer", "id": "AROUT", "attributes": { "...": "..." } } ],
  "links": {
    "first": "/api/Customer/?page[offset]=0&page[limit]=2",
    "next":  "/api/Customer/?page[offset]=4&page[limit]=2",
    "last":  "/api/Customer/?page[offset]=94&page[limit]=2",
    "self":  "/api/Customer/?page[offset]=2&page[limit]=2" },
  "meta": { "count": 95, "limit": 2, "total": 95 },
  "jsonapi": { "version": "1.0" } }
```

- `meta.limit` echoes the page size; `meta.count` and `meta.total` both reported the full match count in every probe (95 above; 5 and 1 in the §3.5 filters). Walk `links.next` until it disappears.
- With no `page[limit]`, this install returned `meta.limit: 250` — the default page size observed live. Do not assume "no limit means all rows".

### 3.2 Single resource — `GET /api/<Type>/<id>/`

```bash
curl -s -H "Authorization: Bearer $TOKEN" "http://localhost:5656/api/Category/1/"
```

```json
{ "data": {
    "type": "Category", "id": "1",
    "attributes": { "Id": 1, "CategoryName": "Beverages",
      "Description": "Soft drinks, coffees, teas, beers, and ales", "Client_id": 1,
      "S_CheckSum": "23f61c29c63e2796904113eba3237f9f7a42459cd9662cac4abc3b15f1d5c9e1" },
    "relationships": { "ProductList": { "data": [],
        "links": { "self": "/api/Category/1/ProductList" } } },
    "links": { "self": "/api/Category/1/" } },
  "included": [], "jsonapi": { "version": "1.0" },
  "links": { "self": "/api/Category/1/" },
  "meta": { "count": 1, "instance_meta": {}, "limit": 250, "total": 1 } }
```

- `id` is a **string** in the wire format even for integer keys (`"1"`), while `attributes.Id` keeps the column's native type (`1`). Match on `attributes` when types matter.
- Trailing slash is optional: `/api/Customer/ALFKI` returned 200 with no redirect (verified). The generated code and tests consistently use the trailing slash; prefer it.

### 3.3 Sparse fields (projection) — `fields[<Type>]=`

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:5656/api/Customer/?fields%5BCustomer%5D=Id,CompanyName,Balance&sort=-Balance&page%5Blimit%5D=3"
# data[0].attributes → {"Balance": 10121.5, "CompanyName": "Ernst Handel", "Id": "ERNSH"}
```

- Only the named attributes are serialized — **including `S_CheckSum`, which is omitted unless you ask for it**. A client that projects fields and later PATCHes with optimistic locking must include `S_CheckSum` in the `fields` list (the shipped Behave test does exactly this — §5).
- The type key is the class name exactly as in `database/models.py` (`fields[Customer]`, `fields[Order]`).

### 3.4 Sort — `sort=` (asc), `sort=-` (desc), comma for multi-column

```bash
# ascending (probed): sort=Balance      → first rows: ANATR 0.0, ANTO 0.0
# descending (probed): sort=-Balance    → first row:  ERNSH 10121.5
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:5656/api/Customer/?fields%5BCustomer%5D=Id,Balance&sort=-Balance&page%5Blimit%5D=2"
```

Multi-column: comma-separated, e.g. `sort=Id,CustomerId` — code-verified from the shipped Behave URL (`.../api/Order/?...&sort=Id%2CCustomerId%2C...`), not separately probed.

### 3.5 Filter, simple form — `filter[<attr>]=<value>`

```bash
# one attribute (probed): 5 of 95 customers
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:5656/api/Customer/?filter%5BCountry%5D=Mexico&fields%5BCustomer%5D=Id,Country"
# → meta {"count": 5, "limit": 250, "total": 5}; ids ANATR, ANTO, CENTC, PERIC, TORTU

# multiple attributes AND together (probed): exactly Order 10643
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:5656/api/Order/?filter%5BCustomerId%5D=ALFKI&filter%5BFreight%5D=29.46&fields%5BOrder%5D=Id,CustomerId,Freight"
# → data: [{"id": "10643", "attributes": {"CustomerId": "ALFKI", "Freight": 29.46, "Id": 10643}}]
```

Equality only in this form. Repeat `filter[attr]` params for AND. This is the form the generated admin app and Behave tests use.

### 3.6 Filter, extended grammar — `filter=[{"name","op","val"}]`

SAFRS (the library that generates the JSON:API — see **apilogicserver-architecture-contract**) also accepts a JSON list of predicates in a single `filter=` parameter. Both probes below ran live (verified):

```bash
# numeric comparison: op "gt"
curl -s -G -H "Authorization: Bearer $TOKEN" "http://localhost:5656/api/Customer/" \
  --data-urlencode 'filter=[{"name":"Balance","op":"gt","val":2000}]' \
  --data-urlencode 'fields[Customer]=Id,Balance'
# → ALFKI 2102.0, ERNSH 10121.5, LINOD 3090.0   (meta.total 3)

# SQL LIKE with wildcard: op "like"
curl -s -G -H "Authorization: Bearer $TOKEN" "http://localhost:5656/api/Customer/" \
  --data-urlencode 'filter=[{"name":"CompanyName","op":"like","val":"Alfred%"}]' \
  --data-urlencode 'fields[Customer]=Id,CompanyName'
# → [("ALFKI", "Alfreds Futterkiste")]
```

`op` names map to SQLAlchemy column operators. Only `gt` and `like` were probed here; other operator names (`eq`, `lt`, `le`, `ge`, `ne`, `in`, ...) are **per SAFRS docs, not live-verified** — probe before teaching a client to rely on one. (`curl -G --data-urlencode` moves the JSON into the query string with correct encoding.)

### 3.7 Related data — `include=` (compound documents)

Parent → children, probed on the single-resource GET:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:5656/api/Customer/ALFKI/?include=OrderList&fields%5BCustomer%5D=Id,CompanyName,Balance"
```

```json
{ "data": { "type": "Customer", "id": "ALFKI",
    "attributes": { "Balance": 2102.0, "CompanyName": "Alfreds Futterkiste", "Id": "ALFKI" },
    "relationships": { "OrderList": { "data": [
        { "id": "10643", "type": "Order" }, { "id": "10692", "type": "Order" }, "..." ] } } },
  "included": [
    { "type": "Order", "id": "10692",
      "attributes": { "Id": 10692, "CustomerId": "ALFKI", "AmountTotal": 878.0,
                      "ShippedDate": "2013-10-13", "...": "..." } },
    "... 6 Order resources total ..." ],
  "meta": { "...": "..." } }
```

- Relationship names are the accessors generated in `database/models.py` — children as `<Child>List` (`OrderList`), parent by class name (`Customer`). Resolving a name: **apilogicserver-data-modeling**.
- `relationships.<name>.data` holds only `{type,id}` references; the full rows are in `included[]`. Join them by `(type, id)`.
- **Nested include** with dots, probed: `include=OrderList.OrderDetailList` on `/api/Customer/ALFKI/` returned `included[]` with 6 `Order` + 12 `OrderDetail` resources (verified). The docs' three-level example — `include=OrderList,OrderList.OrderDetailList,OrderList.OrderDetailList.Product` — is per docs (API-Multi-Table); two levels verified here.
- **Child → parent**, probed: `GET /api/Order/?include=Customer&filter%5BId%5D=10643` → `data[0].relationships.Customer.data = {"id": "ALFKI", "type": "Customer"}` and `included[0]` is that Customer (verified).
- Combine with `fields[<Type>]` per type to trim each resource type independently.

### 3.8 Relationship sub-collection endpoints

Each `relationships.<name>.links.self` is directly fetchable (probed):

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:5656/api/Customer/ALFKI/OrderList?fields%5BOrder%5D=Id,AmountTotal&page%5Blimit%5D=2"
# → data: [("Order","10643"), ("Order","10692")], meta {"count": 2, "limit": 2, "total": 2}
```

Caution (observed live): here `meta.total` reflected the returned page (2), not ALFKI's full order count (6). For reliable counts use a filtered collection GET (`/api/Order/?filter[CustomerId]=ALFKI`) or `include=` from the parent.

### Self-serve workflow (per docs API-Self-Serve)

Consumers compose exactly the URL they need — no server change per screen: build the query in Swagger ("Try it out"), verify the response, then "Copy the URL to your client app". Provider-defined endpoints (§6) are for when the caller cannot adapt (external B2B formats).

## 4. Write cookbook — logic-enforced writes

Send `Content-Type: application/json` (Python `requests` `json=` does this). The server accepts it; `application/vnd.api+json` also appears in docs examples.

### 4.1 PATCH (update) — verified 2026-08-23, Genai-Logic 17.03.19

URL carries the id; body repeats `type` and `id` inside `data`. Shape verbatim from the shipped, passing Behave suite (`features/steps/place_order.py`):

```bash
curl -s -X PATCH "http://localhost:5656/api/Order/11011/" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{ "data": { "attributes": { "Ready": false },
                  "type": "Order", "id": "11011" } }'
```

- Only the attributes you send are updated. Body `id` as string `"11011"` or number `10643` both appear in the passing suite (code-verified).
- Success: the transaction commits after the whole rule chain runs (live-verified: PATCH of an Item quantity recomputed formula → sums → constraint chain).
- **Constraint rejection is HTTP 400** with a JSON:API `errors` array — captured live, verbatim:

```json
{ "errors": [ { "title": "Customer balance (9000.0000000000) exceeds credit limit (5000.0000000000)",
                "detail": { "model": "Customer", "error_attributes": [] },
                "code": "2001" } ] }
```

`code` `"2001"` = LogicBank constraint failure; `title` is the rule's `error_msg` with `{row.attr}` interpolated; the transaction is rolled back — nothing is persisted. Known 17.03.19 wart: when a constraint fires, the server *console* may print a `TypeError ... splitlines` logging stack trace (`config/server_setup.py` bug, verified 2026-08-23) — the 400 body and rollback are still correct; do not read it as an engine failure. Triage: **apilogicserver-debugging-playbook**; catalog: **apilogicserver-failure-archaeology**.

### 4.2 POST (create)

Plain JSON:API create — verbatim from the shipped `test/basic/server_test.py` (code-verified; expects **201**):

```bash
curl -s -X POST "http://localhost:5656/api/Customer/" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{ "data": { "attributes": { "Id": "ALFKJ", "CreditLimit": 10, "Balance": 0 },
                  "type": "Customer", "id": "ALFKJ" } }'
```

- Client-supplied `id` works here because Customer has a natural string key. For autoincrement integer keys, omit `id` and read the generated one from the response `data.id` (per docs/JSON:API convention, not live-probed; `allow_client_generated_ids`: **apilogicserver-data-modeling**).
- Per docs (API-Opt-Lock), the POST response includes a populated `S_CheckSum` so a follow-up PATCH needs no extra GET.
- Multi-row business transactions (an order with items) should not be N separate POSTs — use a custom service (§6.3) or an integration mapping (**apilogicserver-integration-patterns**). Real payload for the shipped `add_order` RPC, verbatim from the passing Behave suite (code-verified):

```json
POST /api/ServicesEndPoint/add_order
{ "meta": { "method": "add_order",
            "args": { "CustomerId": "ALFKI", "EmployeeId": 1, "Freight": 11,
                      "OrderDetailList": [ { "ProductId": 1, "Quantity": 1, "Discount": 0 },
                                           { "ProductId": 2, "Quantity": 2, "Discount": 0 } ] } } }
```

### 4.3 DELETE

```bash
curl -s -X DELETE "http://localhost:5656/api/Customer/ALFKJ/" -H "Authorization: Bearer $TOKEN"
```

- Send **no body**: the shipped test that passed a JSON body records the failure comment `Generic Error: Entity body in unsupported format` (code-verified from `test/basic/server_test.py`).
- Deletes run logic like any write — the passing Behave scenario "Logic adjusts aggregates down on delete order" deletes an Order and asserts the customer balance re-derives (code-verified).
- Success status 204 per JSON:API — per docs/spec, not live-provoked here.

### 4.4 Error shapes table

| HTTP | When | Body (real) | Verification |
|---|---|---|---|
| 400 | Rule/constraint rejects the write | `{"errors":[{"title":"<error_msg>","detail":{"model":"Customer","error_attributes":[]},"code":"2001"}]}` | verified 2026-08-23, live |
| 401 | Missing `Authorization` header | `{"msg":"Missing Authorization Header"}` — flask-jwt-extended shape, **not** a JSON:API `errors` array | verified, live |
| 422 | Malformed/garbage bearer token | `{"msg":"Not enough segments"}` | verified, live |
| 401 | Expired token | `{"msg": "Token has expired"}` | per flask-jwt-extended behavior, not live-provoked |
| 404 | Known type, no such id | `{"errors":[{"title":"NotFoundError Invalid \"Category\" ID \"9999\"","detail":"NotFoundError ...","code":"404"}]}` | verified, live |
| 404 | Unknown collection/path (`/api/NoSuchTable/`) | Flask **HTML** "404 Not Found" page — not JSON; a JSON parse error in your client here means a typo'd type name | verified, live |
| 4xx | Stale `S_CheckSum` on PATCH | body contains `"Sorry, row altered by another user..."` | message verified via passing Behave suite 2026-08-23 + docs; exact status code not captured — treat any non-2xx containing that text as an optimistic-lock conflict |

Client rule of thumb: branch on status; then look for `errors[]` (JSON:API/logic errors) else `msg` (auth layer) else HTML (routing typo).

## 5. Optimistic locking — `S_CheckSum`

Optimistic locking = detect concurrent edits without holding database locks: read a row version marker, send it back on update, fail if the row changed in between.

**Mechanism (verified 2026-08-23, Genai-Logic 17.03.19).** `api/expose_api_models.py` wraps every exposed model with an `add_check_sum` decorator that injects a virtual (non-stored) `S_CheckSum` attribute via `@safrs.jsonapi_attr` — read the file: `cls.S_CheckSum = _check_sum_`. Every GET returns it (live values are SHA-256-style hex, e.g. `"23f61c29c63e27..."`; per docs the digest is deterministic across processes/restarts — older releases used Python `hash()` with `PYTHONHASHSEED=0`, which is why a shipped Behave comment mentions a numeric checksum).

**Flow** (steps 1–3 executed by the shipped, passing Behave suite — code-verified; also per docs API-Opt-Lock):

1. GET the row, requesting the checksum if you project fields:
   `GET /api/Category/1/?fields%5BCategory%5D=Id,CategoryName,Description,S_CheckSum`
2. PATCH, echoing the as-read value **inside `attributes`**:

```json
{ "data": { "attributes": { "Description": "x",
                            "S_CheckSum": "<value from step 1>" },
            "type": "Category", "id": "1" } }
```

3. Server recomputes the current row's checksum and compares. Mismatch → rejection whose body contains `"Sorry, row altered by another user..."` (Behave scenario "Invalid Checksum", passed 2026-08-23). Match → the write proceeds into normal rule processing.
4. On POST, the response already carries `S_CheckSum` (per docs), so create-then-update needs no interleaved GET.

**Configuration.** `config/config.py` ships `OPT_LOCKING = "optional"` (verified read, 17.03.19). Modes per docs: `ignored` (never checked), `optional` (checked only when the client sends `S_CheckSum`; default), `required` (PATCH without it is an error). Attribute name is settable at create time via `--opt_locking_attr` (per docs). Overrides via `OPT_LOCKING` env var / CLI: **apilogicserver-cli-and-config**. The checksum lives in the API layer, not the schema — nothing to migrate (**apilogicserver-data-modeling**).

Client guidance: under `optional`, a client that never sends `S_CheckSum` gets last-writer-wins silently — send it for any human-edited screen.

## 6. Custom endpoints

### 6.1 Decide first

| Need | Use | Why |
|---|---|---|
| CRUD, lists, lookups, trees of related rows | Self-serve JSON:API (§3–§4) | Zero code; already logic-enforced, secured, in Swagger |
| Non-database or bespoke-shape response (health, hello, HTML, computed report) | Flask route in `api/customize_api.py` or an `api_discovery` file (§6.2) | Full control; **not** in Swagger |
| Swagger-visible service verb (RPC = remote procedure call), e.g. "post an order with items" | `safrs.JABase` class + `@jsonapi_rpc` (§6.3) | Appears in Swagger with a sample payload; one transaction |
| External partner document formats, messaging, MCP | **apilogicserver-integration-patterns** (`RowDictMapper`, Kafka, B2B) | Mapping/alias/lookup automation belongs there |

Whatever you choose, business rules stay in `logic/` — never re-implement validations in an endpoint (§8).

### 6.2 `api_discovery` auto-discovery (verified 2026-08-23, Genai-Logic 17.03.19)

Mirror of `logic/logic_discovery` (see **apilogicserver-logic-patterns**): at startup, `api/customize_api.py` calls `discover_services`, which walks `api/api_discovery/*.py`, imports each file (skipping `auto_discovery.py` itself), and calls its `add_service(app, api, project_dir, swagger_host, PORT, method_decorators)`. No registration list to edit — drop in a file, restart, done. Shipped template, verbatim (`api/api_discovery/new_service.py`; its endpoint answered live: `GET /hello_service?user=probe` → `{"result": "hello from new_service! from probe"}`):

```python
from flask import request, jsonify
import logging

app_logger = logging.getLogger("api_logic_server_app")

def add_service(app, api, project_dir, swagger_host: str, PORT: str, method_decorators = []):
    pass

    @app.route('/hello_service')
    def hello_service():
        user = request.args.get('user')
        app_logger.info(f'{user}')
        return jsonify({"result": f'hello from new_service! from {user}'})
```

Add-a-service checklist:

1. Copy the template to `api/api_discovery/<my_service>.py`; keep the exact `add_service` signature; rename the route and function (route names are global — collisions break startup).
2. For database access inside the route: `db = safrs.DB; session = db.session`, then SQLAlchemy (ORM = object-relational mapper) queries — see `api/api_discovery/sales_by_category.py` in the nw sample for a multi-join example (code-verified).
3. Restart the server; confirm the startup log line `..discovered services: [...]` lists your file, then GET the route.
4. These are your files — rebuilds do not touch `api_discovery` service files you add; still land the change through **apilogicserver-change-control** gates.

The directory also ships `system.py` (`/server_log`, `/metadata` — programmatic API metadata for tools) and `mcp_discovery.py` (MCP integration — **apilogicserver-integration-patterns**).

### 6.3 `api/customize_api.py` — Flask routes and Swagger-visible `jsonapi_rpc` (verified from installed nw sample)

The file's hook, verbatim (called at startup; header: "Customize this file to add endpoints/services, using SQLAlchemy as required — Separate from expose_api_models.py, to simplify merge if project rebuilt"):

```python
def expose_services(app, api, project_dir, swagger_host: str, PORT: str):
    from api.api_discovery.auto_discovery import discover_services
    discover_services(app, api, project_dir, swagger_host, PORT)

    api.expose_object(ServicesEndPoint)   # registers the RPC class in Swagger
    api.expose_object(CategoriesEndPoint)

    @app.route('/hello_world')
    def hello_world():
        user = request.args.get('user')
        return jsonify({"result": f'hello, {user}'})
```

Live proof: `GET /hello_world?user=probe` → `{"result": "hello, probe"}` (verified).

Swagger-visible service — the shipped pattern, verbatim (trimmed):

```python
class ServicesEndPoint(safrs.JABase):

    @classmethod
    @jsonapi_rpc(http_methods=["POST"])
    def add_order(self, *args, **kwargs):  # yaml comment => swagger description
        """ # yaml creates Swagger description
            args :
                CustomerId: ALFKI
                EmployeeId: 1
                Freight: 10
                OrderDetailList :
                  - ProductId: 1
                    Quantity: 1
                    Discount: 0
            ---
        """
        db = safrs.DB         # Use the safrs.DB, not db!
        session = db.session  # sqlalchemy.orm.scoping.scoped_session
        new_order = models.Order()
        session.add(new_order)
        row_dict_mapper.json_to_entities(kwargs, new_order)  # generic function - any db object
        return {"Thankyou For Your Order"}  # automatic commit, which executes transaction logic
```

Mechanics (all code-verified in the installed sample; endpoints visible live in `/api/swagger.json` paths: `/ServicesEndPoint/add_order`, `/ServicesEndPoint/OrderB2B`, `/CategoriesEndPoint/get_cats`):

- The class extends `safrs.JABase`; each `@classmethod` decorated `@jsonapi_rpc(http_methods=["POST"])` becomes `POST /api/<ClassName>/<method>`. The YAML block in the docstring **above the `---`** becomes the Swagger "Try it out" sample; callers wrap it as `{"meta": {"args": {...}}}` (§4.2 shows the real wire payload).
- `api.expose_object(TheClass)` inside `expose_services` registers it — without this line the RPC does not exist.
- Auth per endpoint: stack `@jwt_required()` (see `CategoriesEndPoint.get_cats`, which also uses `@jsonapi_rpc(http_methods=['POST'], valid_jsonapi=False)` to return a plain dict). The sample also defines `bypass_security()` / `admin_required()` decorator helpers and `Security.set_user_sa()` for endpoints that run without a caller token — details in **apilogicserver-security-model**.
- The service writes via `session.add(...)` and returns; **commit fires automatically at request end, executing all rules** — the comment in the shipped code says exactly that. Never call `session.commit()` yourself mid-service and never write around the session.
- The better-practice variant `OrderB2B` maps an external attribute vocabulary (alias, joins, lookups) through a `RowDictMapper` — that pattern belongs to **apilogicserver-integration-patterns**.

### 6.4 Ownership — what a rebuild touches

`api/expose_api_models.py` header (verified): "Declare API - on existing SAFRSAPI to expose each model ... **You typically do not customize this file**". It is regenerated territory; rebuilds write `api/expose_api_models_created.py` for you to diff/merge. Your code goes in `api/customize_api.py` and `api/api_discovery/` — both preserved. Full matrix and merge runbook: **apilogicserver-change-control** (its gates are the final step of any endpoint change).

## 7. Tooling

**Swagger UI** (interactive OpenAPI docs): browse to `http://localhost:5656` — `/` 302-redirects to the admin app, whose Home links Swagger; or open `http://localhost:5656/api` directly (verified). Machine-readable spec: `GET /api/swagger.json` (OpenAPI 2.0, `basePath: /api`, verified). With security on (per docs Security-Swagger): execute the `auth` POST endpoint in Swagger → copy `access_token` → click **Authorize** at the top → enter `Bearer <access_token>` → Close; subsequent "Try it out" calls carry the header.

**`als login` / `als curl`** — CLI helpers so you do not hand-manage tokens (help output verified 2026-08-23; per docs, `login` stores the token in `api_logic_server_cli/api_logic_server_info.yaml` inside the install, and `curl` appends the auth header):

```bash
als login --user=admin --password=p          # server must be running
als curl "http://localhost:5656/api/Category/?page%5Blimit%5D=1"
als curl "'POST' 'http://localhost:5656/api/ServicesEndPoint/OrderB2B'" --data '{"meta": {"args": {"order": {...}}}}'
```

`als curl --help` options: `--data TEXT` (payload for Post/Patch), `--security / --no_security` (include the Bearer header). Cosmetic wart, verified 17.03.19: the help prints click `UserWarning: The parameter --security is used more than once` — harmless. The quoted-verb form for POST is verbatim from the shipped `customize_api.py` docstrings (code-verified). Full CLI catalog: **apilogicserver-cli-and-config**.

**Postman / other clients:** import the live spec from `http://localhost:5656/api/swagger.json` (spec endpoint live-verified), then add header `Authorization: Bearer <token>` from §2. The import workflow itself is standard OpenAPI tooling — not covered in the docs pages this skill is grounded in.

**Automated tests** against the API (Behave suite, logic report evidence): **apilogicserver-validation-and-qa**.

## 8. The architectural point: there is no logic-free write path

Every write in this section — admin app saves, JSON:API POST/PATCH/DELETE, custom `jsonapi_rpc` services, `api_discovery` routes that `session.add(...)` — funnels through the same SQLAlchemy session, whose flush (the moment the ORM emits SQL) triggers the full rule chain: ROW LOGIC → COMMIT LOGIC → AFTER_FLUSH (**apilogicserver-architecture-contract**, invariant; **declarative-rules-reference** for the engine model). Live proof, verified 2026-08-23: a one-attribute PATCH (`Item.quantity` 1→100) recomputed the formula, adjusted two levels of sums, and was rejected by the credit constraint with the exact 400 in §4.1 — no endpoint code mentioned any of those rules.

Consequences for API work:

- Never duplicate a validation or computation in an endpoint or client "for safety" — it will drift from `logic/declare_logic.py`, which already fires everywhere. Add rules via **apilogicserver-logic-patterns**.
- A "simple" PATCH can legitimately return a 400 naming a *different* table (the constraint above is on `Customer`, the PATCH was on `Item`/`OrderDetail`) — that is the chain working, not a routing bug.
- The only way around the rules is raw SQL outside the session — forbidden except by the narrow waiver in **apilogicserver-change-control**; symptoms of doing it anyway ("stale sums") are cataloged there and in **apilogicserver-debugging-playbook**.

## Provenance and maintenance

Volatile facts and a one-line re-check for each (run from a running project's environment; token per §2):

- Port / root redirect: `curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' http://localhost:5656/` → expect `302 .../admin-app/index.html`.
- Login endpoint and shape: `curl -s -X POST http://localhost:5656/api/auth/login -H 'Content-Type: application/json' -d '{"username":"admin","password":"p"}'` → expect `access_token`.
- Pagination meta/links: `curl -s -H "Authorization: Bearer $TOKEN" 'http://localhost:5656/api/<Type>/?page%5Blimit%5D=2' | python3 -m json.tool` → expect `meta.count/limit/total`, `links.next`.
- Default page limit (250 observed): same call without `page[limit]`, read `meta.limit`.
- Extended filter grammar: `curl -s -G -H "Authorization: Bearer $TOKEN" http://localhost:5656/api/<Type>/ --data-urlencode 'filter=[{"name":"<attr>","op":"gt","val":0}]'`.
- Constraint 400 shape / code 2001: run the Behave suite (see **apilogicserver-validation-and-qa**) and read `test/api_logic_server_behave/logs/`; or PATCH a row to violate a known constraint in a scratch database.
- Opt-lock default and messages: `grep -n 'OPT_LOCKING =' config/config.py` (expect `"optional"`); flow and "Sorry, row altered by another" assertion in `test/api_logic_server_behave/features/steps/opt_locking.py`.
- `S_CheckSum` injection point: `grep -n 'S_CheckSum' api/expose_api_models.py`.
- Discovery mechanism and services: `grep -n 'discover_services' api/customize_api.py api/api_discovery/auto_discovery.py` and the startup log line `..discovered services:`.
- RPC registration: `grep -n 'expose_object\|jsonapi_rpc' api/customize_api.py`; live check `curl -s http://localhost:5656/api/swagger.json | python3 -c "import sys,json;print([p for p in json.load(sys.stdin)['paths'] if 'ServicesEndPoint' in p])"`.
- CLI helper syntax: `als login --help` and `als curl --help`.
- POST/PATCH/DELETE payload shapes in shipped code: `grep -rn '"data"' test/api_logic_server_behave/features/steps/*.py test/basic/server_test.py`.

Grounded in: https://apilogicserver.github.io/Docs/API/, https://apilogicserver.github.io/Docs/API-Self-Serve/, https://apilogicserver.github.io/Docs/API-Multi-Table/, https://apilogicserver.github.io/Docs/API-Customize/, https://apilogicserver.github.io/Docs/API-Opt-Lock/, https://apilogicserver.github.io/Docs/Security-Swagger/ and a live Genai-Logic 17.03.19 install (2026-08-23).
