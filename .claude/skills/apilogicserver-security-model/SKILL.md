---
name: apilogicserver-security-model
description: Security model for API Logic Server (Genai-Logic) projects - activating authentication/authorization (als add-auth, SECURITY_ENABLED, --provider-type sql/keycloak/None), the JWT login flow (POST /api/auth/login, Bearer token, 222-minute expiry), declarative row security in security/declare_security.py (Grant, GlobalFilter, DefaultRolePermission, Roles, filters AND'd / grants OR'd, sa superuser), the sample auth DB (admin/p, s1/p, 11 users), Keycloak and custom providers, and how to TEST security with curl instead of assuming it. Use when activating or disabling security, adding users or roles, writing or debugging Grant/GlobalFilter declarations, protecting custom endpoints with @jwt_required, or on symptoms - 401 Missing Authorization Header, 422 Not enough segments, Wrong username or password, login returns 500, GrantSecurityException, "does not have delete access", users see too many/too few rows, admin sees rows but s1 sees one, Swagger Authorize. CLI flags -> apilogicserver-cli-and-config.
---

# ApiLogicServer Security Model

## Purpose

This skill is the single home for security in an API Logic Server project: how authentication (login, JWT) and authorization (role-based row/verb access) are activated, where they are declared, how the engine enforces them, and — critically — how to prove they work with curl probes rather than assume it. Everything marked "verified" was executed against, or read from, two real generated projects and a live Northwind-with-customizations (`nw+`) server on a Genai-Logic 17.03.19 install (2026-08-23/24).

## Use this skill when

- Activating, deactivating, or verifying security on a project (`als add-auth`, `SECURITY_ENABLED`).
- Writing or debugging `Grant`, `GlobalFilter`, `DefaultRolePermission` in `security/declare_security.py`.
- Adding users or roles, finding the auth database, or wondering what the sample passwords are.
- A request fails with `401 Missing Authorization Header`, `422 Not enough segments`, `"Wrong username or password"`, a `500` from login, or `"does not have <verb> access"`.
- A user sees too many rows (filter not applied) or too few rows / `404` on a row that exists (filter applied).
- Wiring Keycloak or a custom authentication provider, or protecting a custom endpoint.
- Using Swagger against a secured server.

## Do NOT use this skill when

- You need the full CLI flag catalog, `--db-url` shorthands, or env-var precedence → **apilogicserver-cli-and-config**.
- Rules (`Rule.constraint` etc.) misbehave with security off → **apilogicserver-logic-patterns** / **apilogicserver-debugging-playbook**.
- JSON:API request syntax (filters, PATCH shapes, optimistic locking) → **apilogicserver-api-contract**.
- Starting servers, ports, the admin app UI itself → **apilogicserver-operate-and-deploy**.
- Running the Behave suite / reading its reports → **apilogicserver-validation-and-qa**.
- Deciding whether an edit is allowed and how it is gated → **apilogicserver-change-control** (every change procedure below ends at its gates).

---

## 1. The model on one page

Jargon, defined once:

- **Authentication** — proving who you are. Client POSTs credentials to `/api/auth/login` and receives a **JWT** (JSON Web Token: a signed, base64-encoded token; here HS256-signed). The client sends it on every later request as a **bearer token**: header `Authorization: Bearer <token>`.
- **Authorization** — deciding what that identity may do: which CRUD verbs per role, and which **rows** per role. Declared, not coded: `Grant` / `GlobalFilter` declarations compile to SQLAlchemy filters.
- **ORM** — Object-Relational Mapper (SQLAlchemy here); **flush** — the moment the ORM writes pending changes to SQL, where the rules engine runs; **JSON:API** — the REST convention SAFRS serves (`data/attributes/meta`); **multi-tenant** — one database serving many client organizations, each seeing only its rows; **RBAC** — role-based access control.

Both halves are enforced **server-side, inside the same SQLAlchemy session the rules engine uses**, so logic and security compose:

| Access | Enforcement point | Mechanism (verified in source) |
|---|---|---|
| Read (SELECT) | SQLAlchemy `do_orm_execute` session event | `with_loader_criteria` appends the role's WHERE clause before SQL executes — `security/system/authorization.py` |
| Insert/Update/Delete | Inside logic, per row, before flush | `Grant.process_updates(logic_row=...)` called from the generic event in `logic/declare_logic.py` (line ~92) |
| Every API endpoint | Flask route decoration | `configure_auth()` appends `jwt_required()` to SAFRS `method_decorators` — `security/system/authentication.py` |

Consequence: the admin app, Swagger, curl, and custom API clients all pass through identical checks — there is no per-UI security to keep in sync (see **apilogicserver-architecture-contract** for the invariant).

---

## 2. Activation runbook (`als add-auth`)

Verified 2026-08-23, Genai-Logic 17.03.19. Run from the project root, venv active.

```bash
als add-auth --db_url=auth      # sqlite auth DB + sql provider — the live-verified form
```

`--db_url=auth` resolves to a starter sqlite authentication database copied into the project. General forms from the current docs (per docs, not live-verified beyond the first form):

```bash
als add-auth --provider-type=sql --db-url=                                        # default sqlite auth db
als add-auth --provider-type=sql --db_url=postgresql://postgres:p@localhost/authdb # your own auth db
als add-auth --provider-type=keycloak --db-url=localhost                           # Keycloak at localhost:8080
als add-auth --provider-type=keycloak --db-url=hardened                            # docs' hardened variant
als add-auth --provider-type=None                                                  # disable security
```

Spelling notes (verified):
- Docs write these commands as `gail add-auth ...` / `genai-logic ...` — the rebranded names for the same CLI. On this install all six entry points are equivalent and verified working (`als`, `ApiLogicServer`, `genai-logic`, `gail`, `gal`, `gl` — so the docs' `gail add-auth` runs as-is); script against `als`/`ApiLogicServer` for portability. Full catalog: **apilogicserver-cli-and-config**.
- `als add-auth --help` prints `--provider-type` ("sql, keycloak, or none"), `--project-name`, `--db-url` ("auth db loc (local | hardened | SQLAlchemy uri)"), `--api-name` (verified). The live-verified invocation used the underscore spelling `--db_url=auth`; both spellings appear in official docs. If one errors with "no such option", try the other.

### 2.1 What activation changes on disk (verified in the post-add-auth basic_demo project)

| Artifact | Content after add-auth | Verification |
|---|---|---|
| `config/default.env` | `SECURITY_ENABLED = True` — **this is the master switch** | verified on disk |
| `config/config.py` | Unchanged logic, already present in every project: line ~49 `load_dotenv(...default.env)`; line ~169 `SECURITY_ENABLED = os.getenv("SECURITY_ENABLED", False)`; line ~170 `SECURITY_PROVIDER = 'sql'`; when enabled, a ternary swaps in the sql or keycloak provider class | verified in source |
| `database/authentication_db.sqlite` | The auth database (11 sample users; section 5) | verified on disk |
| `config/config.py` line ~201 | `SQLALCHEMY_DATABASE_URI_AUTHENTICATION = f'sqlite:///{...}database/authentication_db.sqlite'` — auth DB is a second bound database (bind key `authentication`; see **apilogicserver-data-modeling**) | verified in source |
| `database/database_discovery/authentication_models.py` | SQLAlchemy models for `User`, `Role`, `UserRole`, `Apis` | verified on disk |
| `security/` tree | `declare_security.py` (yours to edit), `system/` (authentication.py, authorization.py — engine, do not edit), `authentication_provider/` (sql/, keycloak/, memory/, abstract) | verified on disk |
| Startup wiring | `config/server_setup.py` lines ~428-436: `if args.security_enabled: configure_auth(...)` then `from security import declare_security` | verified in source |

The docs say add-auth "updates conf/config.py"; on disk (17.03.19) the observable switch is `SECURITY_ENABLED = True` in `config/default.env`, which `config.py` reads via `os.getenv` (its own default is `False`). Selecting `--provider-type=keycloak` also rewrites the provider import lines in `config.py` via the CLI's `set_provider()` (documented in a comment block inside `config.py` itself, verified in source).

### 2.2 Deactivation

- Permanent (per docs, not live-verified): `als add-auth --provider-type=None`.
- Temporary, no file edits (mechanism verified in `config.py` source): `export SECURITY_ENABLED=false` before starting the server — any value in `{false, no}` (case-insensitive) disables; anything else enables. Env-var family and precedence → **apilogicserver-cli-and-config**.

### 2.3 Post-activation verification checklist

1. Start the server (**apilogicserver-operate-and-deploy**). Expect startup log line: `config.py - security enabled: True using SECURITY_PROVIDER: <class ...sql.auth_provider...>` and `..declare security - security/declare_security.py`.
2. Run probe 6.2-A (no token → 401). If you get 200, security is NOT on — check `config/default.env` and any `SECURITY_ENABLED` env override.
3. Run probe 6.1-A (login admin/p → token) and a role-filtered read (6.3).
4. Any edit beyond this runbook (new grants, new users, provider swap) passes the gates in **apilogicserver-change-control** before merge.

---

## 3. Enforcement engine: what actually happens

Source of truth: `security/system/authorization.py` (`Grant.exec_grants`, `receive_do_orm_execute`) and `security/system/authentication.py` (`configure_auth`). Verified 2026-08-23/24 by reading the generated files and probing the live server. You normally never edit these two files.

### 3.1 Authentication path (per request)

1. `POST /api/auth/login` (the only auth route the sql provider generates — there is **no refresh endpoint**; re-login when the token expires). Body `{"username": ..., "password": ...}`; an `Authorization: Basic base64(user:pass)` header also works (verified in source).
2. The provider's `get_user(id, password)` loads the user row + `UserRoleList` from the auth DB; `check_password` compares — **plaintext** in the sample provider (`return password == user.password_hash`, logged with warning "Checking plaintext password"; verified in `security/authentication_provider/sql/auth_provider.py`).
3. `create_access_token(identity=user)` issues the JWT. The token's `sub` claim is the user id only — **roles are not embedded in the token** (verified by decoding a live token, section 6.5).
4. On every subsequent request, flask-jwt-extended validates the signature/expiry, then `user_lookup_callback` calls `get_user` again — roles and user attributes are **re-read from the auth DB per request**, so role changes take effect without re-login (verified in `authentication.py` source).

### 3.2 Authorization path (per query / per row)

For SELECTs, the `do_orm_execute` listener fires `Grant.exec_grants(class_name, "is_select", orm_execute_state)`, which builds:

```
WHERE (AND of all applicable GlobalFilters) AND (OR of all matching Grant filters)
```

and injects it with `with_loader_criteria` — the filter rides along on relationship loads too, not just top-level queries. For insert/update/delete, `Grant.process_updates` (called from the generic row event in `logic/declare_logic.py`) re-runs `exec_grants` with the verb — inside the same transaction as your rules, before flush.

### 3.3 Deny-by-default or allow-by-default? The precise statement

From `security/system/authorization.py`, `Grant.exec_grants` (verified in source; the comment at the accumulation loop reads `# start out full restricted - any True will turn on access`):

- **CRUD verbs are deny-by-default.** `can_read/can_insert/can_update/can_delete` start `False`. They are OR-accumulated from (a) every `DefaultRolePermission` declared for any of the user's roles and (b) every `Grant` on the entity matching one of the user's roles. A role mentioned in neither place gets nothing → `GrantSecurityException`, message `Grant Security Error on User: <id> with roles: [...] does not have <verb> access on entity: <Entity>` (HTTP 400 per its `status_code=HTTPStatus.BAD_REQUEST`).
- **Row filters are allow-by-default.** If the verb is permitted and no Grant filter / GlobalFilter matches the entity, the user sees ALL rows.
- **Superuser bypass:** users with id in `['sa']`, or holding role `sa`, or flagged `g.isSA`, skip everything — no verb checks, no filters. The sample `admin` user has role `sa` (section 5), which is why admin sees unfiltered data.
- **Roleless users become `public`.** A user with zero roles is treated as holding role `"public"` (sample user `p1` demonstrates).
- **Trap (verified in `Grant.__init__` defaults):** `can_read/can_insert/can_update/can_delete` default `True` on `Grant`. A filter-only `Grant(on_entity=..., to_role=..., filter=...)` therefore also turns ON all four verbs for that role+entity. Pass explicit `can_*=False` when you mean filter-but-not-permit.

### 3.4 What security does NOT cover — verified blind spots

| Blind spot | Evidence | What to do |
|---|---|---|
| **Custom endpoints are NOT auto-protected.** `GET /hello_world?user=test` returned 200 with **no token** on the secured live server (verified 2026-08-24). | `method_decorators` only wraps SAFRS model endpoints | Add `@jwt_required()` above `@jsonapi_rpc(...)` in `api/customize_api.py` — the sample `CategoriesEndPoint.get_cats` shows the pattern |
| Reads made BY rules during flush are unfiltered — log line `No grants during logic processing`. Deliberate: aggregates must stay correct no matter who triggers them. | `receive_do_orm_execute` source | Never rely on row filters inside rule code; see **declarative-rules-reference** |
| The auth `User` table is exempt from grants (`No grants - avoid recursion on User table`). | same source | — |
| Views / mapper-less selects: `No mapper - authorization not supported for views`. | same source | Don't expose sensitive views expecting row security |
| Raw SQL bypasses everything (as it bypasses rules). | architecture invariant | **apilogicserver-architecture-contract** |
| Filters apply to SELECT only; writes are verb-gated, not row-filtered — but a PATCH/DELETE must first read the row through a filtered SELECT, and an out-of-grant row reads as 404 (verified, section 6.2-E). | `exec_grants` source + live probe | — |

---

## 4. `security/declare_security.py` anatomy — verbatim from the nw+ sample

This file is **yours to edit** (gates: **apilogicserver-change-control**). It runs once at server start (`server_setup.py` imports it when security is enabled). Import line, verbatim:

```python
from security.system.authorization import Grant, Security, DefaultRolePermission, GlobalFilter
from database import models
```

### 4.1 Roles — code-completion constants, not the source of truth

```python
class Roles():
    """ Define Roles here, so can use code completion (Roles.tenant) """
    tenant = "tenant"           # aneu, u1, u2
    renter = "renter"           # r1
    manager = "manager"         # u2, sam
    sales="sales"               # s1
    customer="customer"         # ALFKI, ANATR
    public="public"             # p1 (no roles, so gets public)
```

Role **assignment** lives in the authentication provider (auth DB `Role`/`UserRole` tables, or Keycloak). The class is just string constants; the auth DB also contains roles (`dev`, `sa`) not mirrored here.

### 4.2 DefaultRolePermission — per-role verb defaults

```python
DefaultRolePermission(to_role = Roles.tenant,  can_read=True, can_delete=True)
DefaultRolePermission(to_role = Roles.renter,  can_read=True, can_delete=False)
DefaultRolePermission(to_role = Roles.manager, can_read=True, can_delete=False)
DefaultRolePermission(to_role = Roles.sales,   can_read=True, can_delete=False)
DefaultRolePermission(to_role = Roles.public,  can_read=True, can_delete=False)
```

Unpassed args default `True` (`can_insert`/`can_update` here). `renter.can_delete=False` is what makes the Behave scenario "r1 deletes a Shipper → Operation is Refused" pass.

### 4.3 GlobalFilter — one declaration, every entity that has the column

```python
GlobalFilter(   global_filter_attribute_name = "Client_id",  # try customers & categories for u1 vs u2
                roles_not_filtered = ["sa"],
                filter = '{entity_class}.Client_id == Security.current_user().client_id')

GlobalFilter(   global_filter_attribute_name = "Region",  # sales see only Customers in British Isles (9 rows)
                roles_not_filtered = ["sa", "manager", "tenant", "renter", "public"],  # ie, just sales
                filter = '{entity_class}.Region == Security.current_user().region')

GlobalFilter(   global_filter_attribute_name = "Discontinued",  # hide discontinued products
                roles_not_filtered = ["sa", "manager"],         # except for admin and managers
                filter = '{entity_class}.Discontinued == 0')
```

Semantics (verified in `GlobalFilter.__init__` source): at declaration time it scans every class in `database.models`; for each class possessing the named column it `eval`s the filter string (`{entity_class}` → `lambda : models.<Class>`) and registers an internal `Grant(to_role="*", global_filter=self, ...)`. At query time the filter applies **unless** the requesting user holds a role in `roles_not_filtered`. Multiple GlobalFilters on one entity are **AND'd**. `Security.current_user().<attr>` reads any column of the auth `User` row (e.g. `client_id`, `region`) — the multi-tenant pattern. This also demonstrates the fourth use: soft-delete (`Is_deleted == 0`) works the same way.

### 4.4 Grant — role + entity + filter

```python
Grant(  on_entity = models.Customer,
        to_role = Roles.customer,
        filter = lambda : models.Customer.Id == Security.current_user().id,
        filter_debug = "Id == Security.current_user().id")     # customers can only see their own account

Grant(  on_entity = models.Customer,
        to_role = Roles.sales,
        filter = lambda : models.Customer.CreditLimit > 300,
        filter_debug = "CreditLimit > 300")     # this eliminates all British Isle rows, but...

Grant(  on_entity = models.Customer,
        to_role = Roles.sales,
        filter = lambda : models.Customer.ContactName == "Mike",  # Mike sees his contacts
        filter_debug = "ContactName == Mike (see security/declare_security.py)")

Grant(  on_entity = models.Customer,
        to_role = Roles.public,
        filter = lambda : models.Customer.Id != 'ANATR',
        filter_debug = "Customer.Id != 'ANATR'")     # illustrates public role (user p1)
```

- `filter` is a zero-argument lambda returning a SQLAlchemy expression, evaluated **per request** (so `Security.current_user()` is the requester).
- `filter_debug` is a string echoed in the security log — always supply it.
- Optional `can_read/can_insert/can_update/can_delete` args set verb permissions (default `True` — see the 3.3 trap).
- The minimal basic_demo variant is the same shape with lowercase columns: `filter = lambda : models.Customer.credit_limit >= 3000`.

### 4.5 Composition worked example — user s1 (sales)

The sample file's own comment, verbatim:

```python
# so user s1 sees the CTWSR customer row, per the resulting where from 2 global filters and 2 Grants:
# where (Client_id=2 and region="British Isles") and (CreditLimit>300 or ContactName="Mike")
#       <---- Filters AND'd ------------------->     <--- Grants OR'd --------------------->
```

Live result (verified 2026-08-24): s1 sees exactly 1 Customer, id **`CTWTR`** — the comment's "CTWSR" is a typo in the shipped sample; trust the probe, not the comment.

---

## 5. Users, roles, and the auth database

### 5.1 Verified roster — `database/authentication_db.sqlite`

Tables: `User (id, name, username, password_hash, client_id, region)`, `Role (name)`, `UserRole (user_id, role_name, notes)`, `Apis`. Enumerated read-only from both generated projects (identical contents; verified 2026-08-24). **Every sample password is `p`** (login verified for admin, s1, u1, u2, ALFKI).

| user id | roles | client_id | region | Demonstrates |
|---|---|---|---|---|
| `admin` | sa | – | – | superuser bypass (the login used everywhere) |
| `sa` | sa | – | – | superuser |
| `aneu` | tenant | 1 | British Isles | tenant filtering (default Behave login) |
| `u1` | tenant | 1 | North America | tenant 1: 1 category |
| `u2` | tenant, manager | 2 | British Isles | multi-role OR; manager skips Discontinued filter |
| `sam` | dev, manager | 2 | North America | manager |
| `s1` | sales | 2 | British Isles | Grants OR'd + Filters AND'd → 1 customer |
| `r1` | renter | 1 | Central America | `can_delete=False` refusal |
| `ALFKI` | customer, tenant | 1 | – | sees only own Customer row |
| `ANATR` | customer, tenant | 2 | – | ditto |
| `p1` | *(none)* | 2 | – | roleless → treated as `public` |

Role table contents: `customer, dev, manager, renter, sa, sales, tenant`.

### 5.2 Inspecting and changing users

Read-only enumeration from a project root (copy-paste; python3 stdlib only):

```bash
python3 - <<'EOF'
import sqlite3
con = sqlite3.connect("file:database/authentication_db.sqlite?mode=ro", uri=True)
for uid, pw in con.execute("SELECT id, password_hash FROM User ORDER BY id"):
    roles = [r[0] for r in con.execute("SELECT role_name FROM UserRole WHERE user_id=?", (uid,))]
    print(f"{uid:8} pw={pw!r:6} roles={roles}")
EOF
```

To add/change users: the auth tables are a normal SQLAlchemy-bound database — edit with sqlite3 (INSERT into `User`, `UserRole`), or point add-auth at your own DB (`--db_url=postgresql://...`, schema per `devops/auth-db/authdb_postgres.sql` / `authdb_mysql.sql`, shipped in the project — verified on disk). Note: in the verified projects the auth tables are **not** exposed at `/api/User` (probe returned 404), so user admin is DB-side; docs mention an auth admin interface (per docs, not live-verified). Any user/role change is a security change → **apilogicserver-change-control** gates (raw SQL here is sanctioned by its NN-1 waiver (a): the auth DB has no rules to bypass).

### 5.3 Production warning — non-negotiable

The shipped credentials (`admin`/`p` and the 10 others) and the plaintext `check_password` are demo scaffolding. Before any non-demo deployment: replace all sample users, hash passwords (docs show a `flask_bcrypt` `check_password_hash` override in the provider), and change `JWT_SECRET_KEY` (section 6.5). Treat these as blocking items in the **apilogicserver-change-control** release checklist.

---

## 6. Test-security cookbook — probe, don't assume

All shapes below verified live 2026-08-24 against the running secured nw+ sample (Genai-Logic 17.03.19), except where labeled. Base URL `http://localhost:5656`.

### 6.1 Login shapes

```bash
# A. Success → 200
curl -s -X POST http://localhost:5656/api/auth/login \
  -H "Content-Type: application/json" -d '{"username":"admin","password":"p"}'
# → {"access_token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9. ..."}

# B. Wrong password → 401, body is a bare JSON string
curl -s -w '\n%{http_code}\n' -X POST http://localhost:5656/api/auth/login \
  -H "Content-Type: application/json" -d '{"username":"admin","password":"wrong"}'
# → "Wrong username or password"   / 401

# C. UNKNOWN user → 500 with an HTML error page (observed 17.03.19)
curl -s -w '\n%{http_code}\n' -X POST http://localhost:5656/api/auth/login \
  -H "Content-Type: application/json" -d '{"username":"nobody","password":"p"}'
# → "<!doctype html>...500 Internal Server Error..." / 500
```

Triage rule from C: a **500 from login means "user id not in the auth DB"** before it means "server broken" — the sql provider raises `ALSError("User <id> is not authorized for this system")` inside the login view and Flask surfaces it as 500 (source-verified; wrong-password for an existing user is the clean 401).

Capture a token for reuse:

```bash
TOKEN=$(curl -s -X POST http://localhost:5656/api/auth/login \
  -H "Content-Type: application/json" -d '{"username":"admin","password":"p"}' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')
```

(Alternative: `als login --user=admin --password=p` then `als curl ...` auto-injects the header → **apilogicserver-cli-and-config**.)

### 6.2 Request shapes

```bash
# A. No header → 401
curl -s -w '\n%{http_code}\n' "http://localhost:5656/api/Customer/?page%5Blimit%5D=1"
# → {"msg":"Missing Authorization Header"} / 401

# B. Malformed token → 422
curl -s -w '\n%{http_code}\n' -H "Authorization: Bearer garbage" \
  "http://localhost:5656/api/Customer/?page%5Blimit%5D=1"
# → {"msg":"Not enough segments"} / 422

# C. Valid token → 200 JSON:API document with meta counts
curl -s -H "Authorization: Bearer $TOKEN" "http://localhost:5656/api/Customer/?page%5Blimit%5D=1" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["meta"])'
# → {'count': 95, 'limit': 1, 'total': 95}      (admin = sa = unfiltered)
```

```bash
# D. Expired token → 401 {"msg":"Token has expired"}   (per flask-jwt-extended docs, not live-verified — expiry is 222 min)
# E. Row outside your grant → 404, NOT 403 (verified: ALFKI fetching BOLID)
#    {"errors": [{"title": "NotFoundError Invalid \"Customer\" ID \"BOLID\"", ... "code": "404"}]}
```

E is the designed behavior: out-of-grant rows are indistinguishable from nonexistent rows — do not "fix" a 404 into a 403.

### 6.3 Row-filtering matrix — the discriminating experiment

Login as each user (password `p`), GET with `page[limit]=1`, read `meta.total`. Verified totals:

| entity | admin (sa) | s1 (sales) | u1 (tenant c1) | u2 (tenant+manager c2) | Explains |
|---|---|---|---|---|---|
| Customer | 95 | **1** (`CTWTR`) | – | – | Filters AND'd, Grants OR'd (4.5) |
| Category | 8 | 3 | **1** | 3 | `Client_id` GlobalFilter (u1=client 1, s1/u2=client 2) |
| Product | 77 | 69 | 69 | **77** | `Discontinued==0` filter skips `sa` and `manager` — u2 is a manager |
| Customer (as ALFKI) | – | – | – | – | 1 row, own id only (customer Grant) |

Read this table as the triage template: *same GET, different token, different `meta.total`* proves row security is live; identical totals for admin and a restricted user proves it is not.

### 6.4 Verb denial

Renter r1 deleting `/api/Shipper/1/` is refused with body containing `does not have delete access` — encoded as the Behave scenario "CRUD Permissions" in `test/api_logic_server_behave/features/authorization.feature` (step asserts that exact text), part of the suite that passed 26/26 scenarios on 2026-08-23. Status is 400 per `GrantSecurityException` source (`HTTPStatus.BAD_REQUEST`). To retest verb permissions, prefer running that suite (**apilogicserver-validation-and-qa**) over ad-hoc destructive curls.

### 6.5 Token anatomy and lifetime

Decode any token (no secret needed for the payload):

```bash
python3 - "$TOKEN" <<'EOF'
import sys, base64, json
h, p, s = sys.argv[1].split(".")
pad = lambda x: x + "=" * (-len(x) % 4)
print(json.loads(base64.urlsafe_b64decode(pad(p))))
EOF
# → {'fresh': False, 'iat': ..., 'jti': '...', 'type': 'access', 'sub': 'admin',
#    'nbf': ..., 'csrf': '...', 'exp': ...}     # exp - iat = 13320 s = exactly 222 min (verified)
```

Settings live in `security/system/authentication.py` `configure_auth` (verified in source — note they are **not** in `config/config.py`):

| Setting | Value shipped | Note |
|---|---|---|
| `JWT_SECRET_KEY` | `"ApiLogicServerSecret"` with comment `# Change this!` | **must change before production** |
| `JWT_ACCESS_TOKEN_EXPIRES` | `timedelta(minutes=222)` | matches decoded exp−iat |
| `JWT_REFRESH_TOKEN_EXPIRES` | `timedelta(days=30)` | declared, but **no refresh endpoint is generated** for the sql provider — clients re-login on expiry |
| Roles in token? | No — only `sub` (user id) | roles re-read from provider per request (3.1); no re-login needed after role changes |

### 6.6 Regression baseline

`features/authorization.feature` scenarios (verified passing): u1 GETs Categories → 1; sam GETs Customers → 3; sam GETs Departments → 8; s1 GETs Customers → 1; r1 delete refused. Keep these green after every security edit — evidence discipline in **apilogicserver-validation-and-qa**.

---

## 7. Keycloak provider — per docs, not live-verified

Keycloak is an external identity server (OAuth/OIDC). What IS verified on disk: the provider at `security/authentication_provider/keycloak/auth_provider.py`, the compose stack under `devops/keycloak/` (`docker-compose.yml`, `import/`, nginx variants), and the config defaults in `config/config.py`: `KEYCLOAK_REALM='kcals'`, `KEYCLOAK_BASE='https://localhost:8080'`, `KEYCLOAK_BASE_URL=<base>/realms/<realm>`, `KEYCLOAK_CLIENT_ID='alsclient'` (all overridable by same-named env vars).

Docs flow (quote-accurate, unexecuted here):

```bash
cd devops/keycloak; docker compose up          # local Keycloak with pre-imported realm kcals
als add-auth --provider-type=keycloak --db-url=localhost
als add-auth --provider-type=keycloak --db-url=http://10.0.0.77:8080   # non-default location
```

Users, roles, and user attributes (client_id, region — the same attributes your GlobalFilters read) are administered in the Keycloak admin console: define realm roles, assign to users, define attribute types, link attributes to scopes. Docs caveat: "Do not specify None or Null for attribute values; these lead to unpredictable results." Realm export/import: `docker exec -it keycloak bash; cd /opt/keycloak; bin/kc.sh export --dir export`, then `docker cp keycloak:/opt/keycloak/export devops/keycloak/import`. Your `declare_security.py` grants are unchanged by the provider swap — authorization is provider-independent.

## 8. Custom authentication providers — the plug-point (verified structure)

Directory: `security/authentication_provider/` containing `abstract_authentication_provider.py`, `sql/`, `keycloak/`, `memory/`. Contract (verbatim from the abstract class): implement two static methods —

- `get_user(id, password) -> object` — returns a row-like object (DotMap or SQLAlchemy row) with the user's attributes plus `UserRoleList`, a list of objects each having `role_name`. This shape is what `Security.current_user()` and grant filters consume.
- `check_password(user, password) -> bool`.

To integrate LDAP/AD/etc., copy the `sql/` provider directory, reimplement those two methods, and wire it as the provider (17.03.19 selects the class in `config.py`'s ternary — a custom class requires editing those import lines; the config comment block notes an env-var-supplied custom class is NOT implemented). Password hashing: override `check_password` with `flask_bcrypt.check_password_hash(self.password_hash, plaintext)` (per docs). Note a docs discrepancy: Security-Authentication says to modify `database/authentication.py` — that path does not exist in generated 17.03.19 projects; the real locations are `security/system/authentication.py` (engine) and `security/authentication_provider/*` (providers), verified on disk. Provider changes are security changes → **apilogicserver-change-control**.

## 9. Swagger with security on — per docs (Security-Swagger)

Swagger (the interactive API console at the server root) "accesses the API in the same manner as any other client", so it needs the same bearer token:

1. In Swagger, open the `auth` POST endpoint (at the end of the page), Try it out → Execute with `{"username":"admin","password":"p"}`; copy `access_token`.
2. Scroll to the top, click **Authorize**, enter `Bearer`, a space, then the pasted token; Authorize → Close. The `Bearer ` prefix with the space is required.
3. Retest a model endpoint (e.g. Category) — results now depend on the logged-in user, exactly like section 6.3. The admin app similarly presents a login screen when security is on (admin/p; s1/p shows 1 customer — per docs Getting-Started, matching the verified curl matrix).

## 10. Production hardening checklist

1. Change `JWT_SECRET_KEY` in `security/system/authentication.py` (shipped value `"ApiLogicServerSecret"`).
2. Replace all 11 sample users; every one has password `p` (verified).
3. Replace the plaintext `check_password` in the sql provider with a hash check (bcrypt per docs), or move to Keycloak/corporate SSO.
4. Ensure every custom endpoint in `api/customize_api.py` carries `@jwt_required()` — verified that unprotected ones stay open even with security on (3.4).
5. Serve HTTPS at the front (deploy topology → **apilogicserver-operate-and-deploy**).
6. Re-run the authorization Behave suite and archive the Logic Report as evidence (**apilogicserver-validation-and-qa**).
7. Land it all through **apilogicserver-change-control** gates.

---

## Provenance and maintenance

Volatile facts and how to re-verify each (run from any secured project root, server running):

- Master switch + provider selection: `grep -n "SECURITY_ENABLED\|SECURITY_PROVIDER" config/config.py config/default.env`
- add-auth flags/spellings: `als add-auth --help`
- Login endpoint + JWT settings (secret, 222-min expiry, no refresh route): `grep -n "JWT_\|route" security/system/authentication.py`
- Deny-by-default verb semantics, `sa` bypass, flush/User/view exemptions: `grep -n "start out full restricted\|super_users\|No grants\|No mapper" security/system/authorization.py`
- Grant/GlobalFilter/DefaultRolePermission signatures: `grep -n "def __init__" security/system/authorization.py`
- Sample users/passwords/roles: the python3 sqlite snippet in 5.2 against `database/authentication_db.sqlite`
- Plaintext password check in sql provider: `grep -n "password_hash" security/authentication_provider/sql/auth_provider.py`
- Live shapes (401/422/404/row counts): probes in sections 6.1–6.3 against `http://localhost:5656`
- Verb-denial regression: `cd test/api_logic_server_behave && python behave_run.py --outfile=logs/behave.log` (server up first)
- Keycloak defaults: `grep -n "KEYCLOAK" config/config.py`; stack: `ls devops/keycloak/`
- Custom-endpoint exposure: with security on, curl a `customize_api.py` endpoint without a token — expect 401 only if you added `@jwt_required()`

Grounded in: https://apilogicserver.github.io/Docs/Security-Overview/, https://apilogicserver.github.io/Docs/Security-Getting-Started/, https://apilogicserver.github.io/Docs/Security-Activation/, https://apilogicserver.github.io/Docs/Security-Authentication/, https://apilogicserver.github.io/Docs/Security-Authorization/, https://apilogicserver.github.io/Docs/Security-sql/, https://apilogicserver.github.io/Docs/Security-Swagger/, https://apilogicserver.github.io/Docs/Security-Keycloak/, https://apilogicserver.github.io/Docs/Architecture-Security-Auth/ and a live Genai-Logic 17.03.19 install (2026-08-23).
