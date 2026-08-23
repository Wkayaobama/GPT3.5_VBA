---
name: apilogicserver-architecture-contract
description: System anatomy and design contract for API Logic Server (Genai-Logic) projects. Use when an engineer or model needs to know what ALS is, the runtime stack (Flask, SQLAlchemy, SAFRS JSON:API, LogicBank rules engine, safrs-react-admin), which project files are generated-and-regenerated vs yours to edit (database/models.py, logic/declare_logic.py, api/customize_api.py, ui/admin/admin.yaml, config/), the invariants that must hold (all writes through the SQLAlchemy session, rules declared not called, plain files under source control, one config path, logic shared across every access path), the startup sequence, the execution flow of a write request (before_flush, ROW LOGIC / COMMIT LOGIC / AFTER_FLUSH), and the known weak points. Load for symptoms and questions like "what is this file", "where does my code go", "can I edit models.py", "rules did not fire after direct SQL", "what happens when I PATCH", "why declarative", or before any architectural decision in an ALS project.
---

# API Logic Server — Architecture Contract

## Purpose

This skill is the system map and design contract for an API Logic Server (ALS / Genai-Logic) project. It states what the runtime stack is and why each part was chosen, which files in a created project belong to the generator vs to you, the invariants every change must preserve, exactly what executes at startup and on a write request, and the known weak points — stated plainly, with each claim labeled verified or docs-derived. Read it before making any structural decision; it is the "why" behind every other skill's "how".

## Use this skill when

- You are new to an ALS project and need to orient: what each top-level directory/file is and whether you may edit it.
- You must decide WHERE code goes (logic vs API vs model vs config) or whether a proposed change violates a system invariant.
- You need to explain or trace what happens between an HTTP PATCH and the database commit (phases, ordering, rollback).
- Symptoms: "my rule didn't fire", "who calls my code", "is this file generated", "why is there no controller layer", "what does before_flush mean here".
- You are reviewing AI-generated or teammate changes for architectural violations (raw SQL, hand-sequenced logic, config forks, edits to engine files).

## Do NOT use this skill when

- You need rule signatures or worked logic patterns → **apilogicserver-logic-patterns**; theory of watch/react/chain ordering → **declarative-rules-reference**.
- You need to install anything or fix a venv → **apilogicserver-build-and-env**; CLI flags and db-url forms → **apilogicserver-cli-and-config**.
- You need JSON:API request syntax (filters, PATCH bodies, pagination) → **apilogicserver-api-contract**; auth/roles/Grants → **apilogicserver-security-model**.
- You need to actually edit/rebuild files safely → **apilogicserver-change-control** (its gates govern every mutation this skill motivates).
- You need symptom→fix triage → **apilogicserver-debugging-playbook**; history of why alternatives were rejected → **apilogicserver-failure-archaeology**.
- You need to run/deploy the server → **apilogicserver-operate-and-deploy**; model/keys/test-data details → **apilogicserver-data-modeling**.

---

## 1. What API Logic Server / Genai-Logic is

API Logic Server (the pip package is named `ApiLogicServer`; since v17 it installs as **Genai-Logic** — same product, `als` is the CLI) is a Python system that creates a complete, executable, customizable web-app-plus-API project from a database schema in one command (`als create --project-name=x --db-url=y`). The created project is standard Python source: a Flask server exposing a JSON:API (a standard REST dialect with typed resources, relationships, and pagination) generated from SQLAlchemy ORM models (ORM = Object-Relational Mapper: Python classes mapped to tables), a React admin UI driven by a YAML model, and — the differentiating part — a declarative rules engine (LogicBank) that enforces multi-table derivations and constraints on every transaction. The design bet, per docs: models "executed" by runtime engines beat generated low-level code, because rules are ~40X more concise than procedural logic and are automatically reused across every access path. (Definition per docs; creation flow and project contents verified 2026-08-23, Genai-Logic 17.03.19.)

## 2. Runtime stack

Each component is a mainstream open-source library; the project's `requirements.txt` contains only `ApiLogicServer`, which pins them all (verified in created projects).

| Component | Role in a running project | Why chosen (per docs) | Verification |
|---|---|---|---|
| **Flask** | HTTP server and routing; `api_logic_server_run.py` builds `Flask("API Logic Server", template_folder='ui/templates')`, adds CORS on `/api/*`, runs threaded on port 5656 | Ubiquitous Python web framework; permits arbitrary custom endpoints beside the generated ones | verified 2026-08-23 in `api_logic_server_run.py` |
| **SQLAlchemy** | ORM; `database/models.py` classes map tables; ALL data access flows through its session | Standard Python ORM; its session/flush events are the single interception point that makes shared logic possible | verified (`models.py`, `server_setup.py`) |
| **SAFRS** | Turns each SQLAlchemy model class into a JSON:API endpoint plus Swagger (OpenAPI) docs; adds an `S_CheckSum` attribute per row for optimistic locking (reject writes based on stale reads) | API-from-models automation — "the JSON:API is driven by the model classes, so is very short"; no controller code to write or maintain | verified: live GET returned `jsonapi: {version: "1.0"}`, `S_CheckSum`, `meta {count, limit, total}` |
| **LogicBank** | Declarative rules engine. `LogicBank.activate(session=…, activator=declare_logic, constraint_event=…)` binds it to the SQLAlchemy session's `before_flush` event (flush = the moment the session converts pending object changes into SQL). From then on every transaction runs derivations (computed/aggregated values), constraints (must-hold conditions), and events | Rules "listen for SQLAlchemy updates"; declare WHAT, engine derives HOW and in what order; transaction-optimized via delta adjustment rather than a RETE-style inference engine (see **apilogicserver-failure-archaeology**) | verified: `config/activate_logicbank.py`, live constraint 400, logic log |
| **safrs-react-admin (SRA)** | The admin UI: a prebuilt, minified React single-page app (SPA) served by the project; it reads `ui/admin/admin.yaml` at load and then calls the same `/api` JSON:API for all data | Instant multi-table UI with zero frontend code; behavior customized by editing `admin.yaml` (a YAML model), not React source. The minified SPA is served from the venv (or `ui/safrs-react-admin`, or `APILOGICPROJECT_SRA`) to keep projects small ("32MB -> 2.5 MB" per in-file comment) | verified: `ui/admin/admin_loader.py` `get_sra_directory()`; live `GET /` → `302` to `/admin-app/index.html` |

Key consequence, stated once: **the admin app has no privileged path to the database.** It calls the same JSON:API as curl does, so logic and security apply to it identically (verified: admin app and API share host:port 5656).

### How the access paths converge (the picture behind invariants 1 and 5)

```
 admin app (SPA)   curl / any client    custom endpoints         MCP / integrations
       |                  |          (customize_api, api_discovery)       |
       +------- JSON:API (SAFRS) --------+---- Flask routes ----+---------+
                          |
                SQLAlchemy session   <-- ALL reads and writes converge here
                          |
              before_flush --> LogicBank: ROW LOGIC -> COMMIT LOGIC -> flush -> AFTER_FLUSH
                          |
                       database
```

Anything that writes the database WITHOUT passing through the session skips the LogicBank box entirely — that is invariant 1 and weak point 1 below.

### Deliberately absent from the architecture

Knowing what is NOT there prevents hunting for it (all verified 2026-08-23 unless marked):

- **No per-endpoint controller/service layer** — `api/expose_api_models.py` is one generic loop over model classes; there is no file-per-endpoint to edit.
- **No database triggers or stored procedures carrying logic** — rules live in Python at the session binding; the database stays plain (portable across DBs).
- **No metadata repository or registry** — behavior is 100% files in the repo (invariant 3).
- **No required message bus** — Kafka is optional; with `KAFKA_SERVER` unset the server starts anyway and logs `Kafka mode: FALLBACK — KAFKA_SERVER not configured; running debug endpoint only` (verified startup log).
- **No hot reload of rules** — activation is once per process (invariant 6).
- **No frontend build step for the admin app** — the SPA ships prebuilt/minified; only `admin.yaml` is interpreted at load.

## 3. Load-bearing design decisions and why

These decisions explain the shape of everything else. Rationale is per docs unless marked verified.

| Decision | Instead of | Why (per docs) | Consequence for you |
|---|---|---|---|
| Execute declarative models with runtime engines | Generating low-level code you then maintain | Generated code is a maintenance liability; models are "specifications of what you want to happen, not how" — "orders of magnitude shorter" | You edit models (rules, `admin.yaml`) and small Python extension points, not controller stacks |
| Rules engine bound to the ORM session (`before_flush`) | Database triggers or per-endpoint validation code | One binding enforces logic for every writer automatically; rules stay portable across databases and platforms ("Derive Customer.Balance as sum(...)" is technology-agnostic) | Invariant 1 below — and weak point 1: out-of-session writes bypass logic |
| Transaction logic via delta adjustment | RETE-style inference engine re-deriving aggregates | Transactional integrity and performance — adjustment is a one-row update, not an aggregate re-query (docs claim large gains from O(1) vs O(n) recomputation; ratio not re-measured here) | Aggregates are STORED columns kept correct by the engine; never recompute them in app code. Internals verified in stack traces: `logic_row.py` `_adjust_parent_aggregates()` → `save_altered_parents()` → `_constraints()` |
| JSON:API via SAFRS | Bespoke REST controllers | Self-describing resources, relationships, pagination, and Swagger for free, driven entirely by the model classes | API surface changes when models change (rebuild), not by editing endpoint code |
| Admin UI = prebuilt SPA + YAML model | Generated React source per project | Declarative YAML replaces "hundreds of lines of very complex HTML and JavaScript"; SPA reuse keeps repos small (verified venv-serving) | UI customization surface is `admin.yaml`; deeper UI needs a separate custom app |
| Project = plain files, standard Python, git-managed | Hosted platform / repository-based metadata | "Fully open source, built on standard Python, Flask, and SQLAlchemy"; "no vendor lock-in: source lives in Git"; the direct lesson of the Versata / Live API Creator lineage (**apilogicserver-failure-archaeology**) | Everything reviewable and diffable — invariant 3 |
| Discovery directories + paired customize files | One big regenerated file you edit in place | Separate regenerated files from your code "to simplify merge if project recreated" (verified: header comment in `api/customize_api.py`); `logic/logic_discovery/`, `api/api_discovery/`, `database/database_discovery/` are auto-imported | New work goes in discovery dirs / customize files; rebuilds stay conflict-free — ownership table below |
| Config layering ends at env vars | Scattered per-file settings | Same image runs dev/container/cloud by changing only environment (verified precedence, invariant 4) | One place to look; `APILOGICPROJECT_*` wins |

## 4. Project anatomy and ownership

Verified 2026-08-23 by reading two live-created projects (`als create … --db-url=basic_demo` and `--db-url=nw+`, Genai-Logic 17.03.19), including in-file header comments. Ownership legend:

- **REGEN** — generated and regenerated by `als rebuild-from-database` / `rebuild-from-model`; hand-edits are at risk. Procedure and merge discipline: **apilogicserver-change-control**.
- **ONCE-YOURS** — generated once at `create` as a scaffold containing "Your Code Goes Here"; never overwritten afterward; this is where your work lives.
- **ALWAYS-YOURS** — files you add (new discovery modules, docs, tests); the tool never touches them.
- **ENGINE** — generated once, but framework plumbing. Headers literally say "You typically do not customize this file". Edit only the documented override points; anything more forks the framework.

| Path | Purpose | Ownership |
|---|---|---|
| `api_logic_server_run.py` | Startup: config layering, `server_setup.api_logic_server_setup()`, admin loader, `flask_app.run()`. Rotates `logs/als.log` → `als.log.1` on each start | ENGINE |
| `config/config.py` | All settings as class `Config` / typed `Args`; DB URIs, `SECURITY_ENABLED`, `OPT_LOCKING`, `KAFKA_SERVER`; reads `config/default.env` | ONCE-YOURS (override values here) |
| `config/default.env` | dotenv defaults loaded by `config.py` | ONCE-YOURS |
| `config/server_setup.py` | `api_logic_server_setup()` (the real boot), logging patchers, `get_args` — "do not customize … except to override Creation Defaults and Logging" (its own header) | ENGINE |
| `config/activate_logicbank.py` | Calls `LogicBank.activate(...)`; honors `APILOGICPROJECT_DISABLE_RULES` | ENGINE |
| `config/logging*.yml` | Log levels per logger (`logic_logger`, `safrs`, sqlalchemy…) | ONCE-YOURS (tune levels) |
| `database/models.py` | SQLAlchemy classes from schema introspection. Header: "initially created by schema introspection… Alter this file per your database maintenance policy" — i.e., rewritten by rebuild | REGEN |
| `database/customize_models.py` | Derived attributes/relationships that SURVIVE model regeneration; imported after `models.py` | ONCE-YOURS |
| `database/database_discovery/` | Auto-discovered extra model modules (multi-db) | ALWAYS-YOURS additions (`auto_discovery.py`: ENGINE) |
| `database/db.sqlite`, `authentication_db.sqlite` | Demo/data DB and auth DB (present when `add-auth` used) | your data |
| `database/system/`, `database/bind_dbs.py` | `SAFRSBaseX` base classes, multi-db binding | ENGINE |
| `database/alembic/`, `alembic.ini` | Schema migration scaffolding (Alembic) — see **apilogicserver-data-modeling** | ONCE-YOURS |
| `database/test_data/` | Generated seed-data scripts | ONCE-YOURS |
| `api/expose_api_models.py` | One JSON:API endpoint per model class; adds `S_CheckSum` to every model. Kept separate from customizations "to simplify merge if project recreated" (its header) | REGEN |
| `api/customize_api.py` | `expose_services()` — your custom endpoints. Header: "Your Code Goes Here" | ONCE-YOURS |
| `api/api_discovery/` | Auto-discovered custom endpoint modules (verified live: `GET /hello_world?user=test` served from here in nw_sample) | ALWAYS-YOURS additions (`auto_discovery.py`, `system.py`: ENGINE) |
| `api/system/`, `api/json_encoder.py` | Utilities, optimistic-locking implementation, JSON encoding | ENGINE |
| `logic/declare_logic.py` | Rule declarations plus call into discovery. THE center of the system | ONCE-YOURS |
| `logic/logic_discovery/` | Auto-discovered rule modules — preferred home for new use-case logic (verified discovered: `simple_constraints.py`, `use_case.py`, `email_request.py`, `system/all_classes_stamping.py`) | ALWAYS-YOURS additions (`auto_discovery.py`, `system/`: ENGINE) |
| `logic/load_verify_rules.py` | Loads/verifies exported rules (WebGenAI flow) | ENGINE |
| `security/declare_security.py` | Roles, `Grant`/`GlobalFilter` declarations — see **apilogicserver-security-model** | ONCE-YOURS |
| `security/authentication_provider/` | Pluggable auth providers (sql, keycloak, …) | ONCE-YOURS |
| `security/system/` | JWT authentication machinery (JWT = signed JSON Web Token carrying identity/roles), `custom_swagger.json` | ENGINE |
| `ui/admin/admin.yaml` | Admin app model: resources, attributes, joins. Never overwritten after create; rebuilds write `admin-created.yaml` / `admin-merge.yaml` BESIDE it for you to merge (per docs Database-Changes; merge files absent until a rebuild) | ONCE-YOURS |
| `ui/admin/admin_loader.py` | Serves the minified SPA + yaml | ENGINE |
| `ui/templates/`, `ui/images/`, `ui/*react*` | Flask templates; optional generated React app source (`genai-add-app`) | ONCE-YOURS |
| `test/api_logic_server_behave/` | Behave (Gherkin) suite + Logic Report tooling — see **apilogicserver-validation-and-qa** | ONCE-YOURS |
| `test/basic/server_test.py` | Smoke test | ONCE-YOURS |
| `integration/` | `kafka/`, `mcp/`, `n8n/`, `row_dict_maps/` producers and mappers — see **apilogicserver-integration-patterns** (MCP = Model Context Protocol, an AI tool-calling standard) | ONCE-YOURS (`system/`: ENGINE) |
| `devops/` | Dockerfiles, docker-compose variants, auth-db, keycloak, python-anywhere | ONCE-YOURS (edit names/registries) |
| `docs/` | `db.dbml` (generated schema doc), `training/` (AI context), `mcp_learning/`, requirements | mixed: generated reference + ALWAYS-YOURS additions |
| `logs/als.log` | Per-run server log (auto-rotated, keeps one prior run) | runtime output |
| `readme.md`, `start_here.md`, `tutor.md`, `run.sh`/`run.ps1`, `requirements.txt` | Onboarding + launchers; `requirements.txt` = just `ApiLogicServer` | ONCE-YOURS |
| `.vscode/`, `.idea/`, `.devcontainer-option/`, `venv_setup/` | IDE launch configs, container option, venv helpers | ONCE-YOURS / ENGINE (venv scripts) |
| `CLAUDE.md`, `.github/` (`copilot-instructions.md`, `agents/`, `instructions/`) | AI-assistant context shipped with every project (`CLAUDE.md` @-includes the copilot instructions and `docs/training/logic_bank_api.md`) | ONCE-YOURS |
| `customizations/`, `iteration/` (present only after `als add-cust`) | Staged copies the `add-cust` demo flow applies; not used at runtime | tool staging |

Rule of thumb (verified against headers): "Your Code Goes Here" → yours; "You typically do not customize this file" → ENGINE; header points at Project-Rebuild → REGEN. Any edit to REGEN/ENGINE files must go through the gates in **apilogicserver-change-control**.

## 5. Invariants — the contract every change must preserve

Summary table; detail blocks follow. All verified 2026-08-23 on Genai-Logic 17.03.19 unless marked.

| # | Invariant |
|---|---|
| 1 | Every write flows through the SQLAlchemy session — that is the only place logic fires |
| 2 | Rules are declared, not called; execution order is derived from dependencies at startup |
| 3 | A project is plain files under source control — no black-box metadata |
| 4 | One config path: `config/config.py` (+`default.env`) → CLI args → `APILOGICPROJECT_*` env, env wins |
| 5 | One logic definition is shared by every access path, by construction |
| 6 | Logic activates once, at startup, before any endpoint is exposed |
| 7 | A constraint failure aborts the whole transaction: HTTP 400, code 2001, rollback |

### Invariant 1 — all writes through the session

- **Statement**: LogicBank's ONLY hook is the SQLAlchemy session's `before_flush` event. There are no database triggers backing the rules.
- **Why**: one interception point buys automatic logic enforcement for every writer with zero per-endpoint code, and keeps rules portable across databases.
- **Breaks if violated**: raw SQL (`engine.execute`, a DB browser, another application, batch scripts, Alembic data migrations) silently bypasses ALL derivations and constraints → stale stored aggregates (e.g. `Customer.balance` wrong), invalid rows admitted.
- **Detect**: no `Logic Phase:` lines in the log for the change; stored aggregate ≠ recomputed aggregate. Triage: **apilogicserver-debugging-playbook**.

### Invariant 2 — declared, not called

- **Statement**: you state `Rule.sum/formula/constraint(...)` in `logic/declare_logic.py`; at `LogicBank.activate` the engine derives execution order from data dependencies, prunes rules whose referenced data did not change, and chains automatically. Never hand-sequence rules.
- **Why**: hand-sequenced logic is the classic corruption source in procedural systems; derived ordering lets the rule count grow without re-analysis (theory: **declarative-rules-reference**).
- **Breaks if violated**: code that assumes an order between rules, or calls rule functions directly, breaks silently when rules are added or changed.
- **Detect**: startup prints the dependency listing per attribute (`..Customer.balance: constraint`, `..Order.amount_total: sum derived from …`); per-transaction actual order is in the `Logic Phase:` log.

### Invariant 3 — plain files, no black box

- **Statement**: models, rules, API, UI model, config are all diffable text — "All project elements are files - no database or binary objects" (docs).
- **Why**: survives git diff/merge, code review, IDE tooling, and vendor death — the direct lesson of the Versata / Live API Creator lineage (**apilogicserver-failure-archaeology**).
- **Breaks if violated**: treating `admin.yaml` or rules as opaque generated output forfeits review and merge; storing logic outside the repo recreates the black box.
- **Detect**: `git status` / `git diff` must account for every behavior change. A behavior change with no diff means invariant 1 or 4 was likely violated instead.

### Invariant 4 — one config path

- **Statement**: precedence, verified in `api_logic_server_run.py` main code order: creation defaults (`server_setup.get_args`) → `config/config.py` class `Config` (+ `config/default.env`) → CLI args → env via `flask_app.config.from_prefixed_env(prefix="APILOGICPROJECT")` — env wins. Verified names include `APILOGICPROJECT_DEBUG`, `APILOGICPROJECT_LOGGING_CONFIG`, `APILOGICPROJECT_DISABLE_RULES`, plus un-prefixed `SECURITY_ENABLED`, `OPT_LOCKING`, `KAFKA_SERVER`, `SQLALCHEMY_DATABASE_URI` read inside `config.py`.
- **Why**: the same image runs dev/container/cloud by changing environment only. Full catalog: **apilogicserver-cli-and-config**.
- **Breaks if violated**: hardcoding URIs or flags in ENGINE files → dev works, container breaks, or points at the wrong database.
- **Detect**: startup debug lines echo effective values (`config.py - SQLALCHEMY_DATABASE_URI: …`, `config.py - security enabled: …`); `grep -rn "sqlite:///" --include="*.py" .` should hit nothing you wrote outside `config/`.

### Invariant 5 — logic shared across all access paths

- **Statement**: admin app, generated JSON:API, custom endpoints (`api/customize_api.py`, `api/api_discovery/`), and MCP integrations all read/write via the same session, so rules fire identically for each — by construction, not by convention.
- **Why**: the point of the architecture — business integrity lives in the domain layer, not per-controller. N paths, one logic definition.
- **Breaks if violated**: re-implementing validation inside a custom endpoint or the UI creates per-path divergence — exactly the corruption ALS exists to prevent.
- **Detect**: the same invalid PATCH via curl and via the admin app must both return the constraint 400 (verified for curl; the admin app uses the same `/api`).

### Invariant 6 — logic activates once, before endpoints

- **Statement**: verified order in `server_setup.api_logic_server_setup()` — logic is bound before any endpoint exists (full sequence in section 6).
- **Why**: no request can ever be served by a rule-less API; the rule set is immutable during traffic, so transactions are deterministic.
- **Breaks if violated / corollary**: editing rules requires a server restart; there is no hot reload. A server started with rules disabled stays that way until restart.
- **Detect**: startup log `LogicBank Activation - declare_logic.py`. If you instead see `LogicBank rules disabled`, the `APILOGICPROJECT_DISABLE_RULES` env var is set and NO logic is running (see weak point 3).

### Invariant 7 — constraint failure aborts the transaction

- **Statement**: the engine raises through `constraint_handler` (defined in `server_setup.py`) → `ValidationErrorExt` → SAFRS returns HTTP 400 `{"errors": [{"title": "<your error_msg>", "detail": {"model": …, "error_attributes": []}, "code": "2001"}]}` and the session rolls back. No partial multi-row commits.
- **Why**: all-or-nothing integrity across all rows chained by one transaction's logic.
- **Breaks if violated**: swallowing `ValidationError` in custom code, or committing inside an event, destroys atomicity.
- **Detect**: verified 400 body above; after a failed PATCH, a re-GET shows unchanged values and unchanged `S_CheckSum`.

## 6. What executes at startup

Numbered, verified 2026-08-23 from `api_logic_server_run.py` main code and `config/server_setup.py::api_logic_server_setup` (line 337 in 17.03.19):

1. `Flask("API Logic Server", template_folder='ui/templates')` is created; CORS is enabled for `/api/*`.
2. Config layering (invariant 4): creation defaults → `config.Config` → CLI args → `APILOGICPROJECT_*` env; then `validate_db_uri`.
3. `api_logic_server_setup(flask_app, args)`:
   1. `bind_dbs` — opens the database(s), including multi-db binds.
   2. `constraint_handler` is defined — rebadges LogicBank constraint failures as `ValidationErrorExt` so SAFRS can return JSON:API 400s (invariant 7).
   3. SQLAlchemy is initialized; `SAFRSAPI` is created (Swagger seeded from `security/system/custom_swagger.json`).
   4. `import database.models`, then `database.customize_models` — log: `Data Model Loaded, customizing...`.
   5. `activate_logicbank(session, constraint_handler)` → `LogicBank.activate(session=…, activator=declare_logic.declare_logic, constraint_event=constraint_handler)`. Rules are validated and dependency-ordered HERE (invariants 2 and 6). `logic/declare_logic.py` in turn triggers auto-discovery of `logic/logic_discovery/` modules.
   6. `expose_api_models.expose_models(...)` — one JSON:API endpoint per model class; log: `Declare   API - api/expose_api_models, endpoint for each table ...`.
   7. `customize_api.expose_services(...)` — your custom endpoints (which auto-discover `api/api_discovery/`).
   8. If `args.security_enabled`: `configure_auth(...)` — JWT authentication (**apilogicserver-security-model**).
4. `AdminLoader.admin_events(...)` — serves the SPA and `ui/admin/admin.yaml`; `GET /` returns `302` → `/admin-app/index.html` (verified live).
5. `flask_app.run(host=args.flask_host, threaded=True, port=args.port)` — default port 5656. Run/ports/containers: **apilogicserver-operate-and-deploy**.

## 7. What executes on one write request

Verified 2026-08-23 by a live experiment: PATCH `Item.quantity` 1→100 on an UNSHIPPED order (unit_price 90, customer credit_limit 5000).

1. Client sends `PATCH /api/Item/2/` with a JSON:API body (`{"data": {"type": "Item", "id": "2", "attributes": {"quantity": 100}}}`) and, when security is on, header `Authorization: Bearer <JWT>` (login: `POST /api/auth/login` with `{"username": "admin", "password": "p"}` → `access_token`; verified live). Full request grammar: **apilogicserver-api-contract**.
2. Flask routes to the SAFRS endpoint generated by `api/expose_api_models.py`. Authorization filters apply (**apilogicserver-security-model**). Optimistic locking compares `S_CheckSum` per `OPT_LOCKING` config (default `optional`).
3. SAFRS applies attributes to the SQLAlchemy ORM row in the session and commits; SQLAlchemy raises `before_flush`; LogicBank receives the changed rows (docs: "SAFRS invokes SQLAlchemy… before_flush assembles update rows and passes them to Logic Bank").
4. **ROW LOGIC phase**: per changed row, LogicBank prunes rules whose referenced attributes did not change, runs formulas/copies (`Item.amount = quantity * unit_price` → 9000), then adjusts parent aggregates by delta — a one-row adjustment update, NOT a `SUM()` re-query. Adjustment chains upward: `Item.amount` → `Order.amount_total` → `Customer.balance` (`where date_shipped is None`), and constraints run on each adjusted row.
5. **COMMIT LOGIC phase**: commit-time rules and events run after all row logic, so parent logic sees all child adjustments (docs: "two distinct logic loops").
6. Flush: SQL is emitted to the database.
7. **AFTER_FLUSH phase**: `after_flush_row_event`s run (e.g. Kafka publish); they can no longer alter this transaction's SQL.
8. Commit — or, on constraint failure anywhere in 4–5, rollback + HTTP 400 code 2001 (invariant 7). The experiment returned exactly: `Customer balance (9000.0000000000) exceeds credit limit (5000.0000000000)`. The same PATCH against a SHIPPED order succeeds, because the sum's `where` excludes shipped orders from balance — the classic "why didn't my constraint fire" discriminating experiment (**apilogicserver-debugging-playbook**).
9. Response: JSON:API document with final attribute values and a fresh `S_CheckSum`.

Verified console log for steps 4–8 (verbatim format, values elided):

```
Logic Phase:		ROW LOGIC		(session=0x...) (sqlalchemy before_flush)
..Item[2] {Formula amount} id: 2, order_id: 2, ..., quantity:  [1-->] 100, amount:  [90.0000000000-->] 9000.0000000000, ...  row: 0x...  session: 0x...  ins_upd_dlt: upd, initial: upd
Logic Phase:		COMMIT LOGIC		(session=0x...)
Logic Phase:		AFTER_FLUSH LOGIC	(session=0x...)
These Rules Fired (see Logic Phases, above, for actual order):
    1. Derive <class 'database.models.Customer'>.balance as Sum(Order.amount_total Where ...)
Logic Phase:		COMPLETE(session=0x...)
```

Read `[old-->] new` as old-to-new value transitions. Reading this log in anger: **apilogicserver-debugging-playbook**; producing it as evidence: **apilogicserver-validation-and-qa**.

Reads (`GET`) skip phases 4–8 entirely — logic fires on writes. Row-level read filtering is security's job (`Grant`/`GlobalFilter`), not logic's.

## 8. Known weak points — the honest list

No invented items; each is evidenced or explicitly docs-only.

1. **Logic does not fire for writes outside the SQLAlchemy session** (flip side of invariant 1). Batch SQL, other applications writing the same database, DBA tools, and Alembic data scripts bypass all rules. Inherent to the `before_flush` design — no DB triggers back the rules. Mitigation policy (route all writers through the API, or verify/recompute aggregates after out-of-band loads): **apilogicserver-change-control** and **apilogicserver-debugging-playbook**. (Design fact verified; the docs do not claim otherwise.)
2. **17.03.19 logging bug on constraint violations** (verified 2026-08-23): `config/server_setup.py` ~line 203, function `short_format_exception`, calls `result.splitlines('\n')` — invalid argument (`splitlines` takes a keepends bool) → `TypeError: 'str' object cannot be interpreted as an integer` raised inside the logging machinery when a constraint violation is logged. Consequence: the console shows a logging stack trace instead of the pretty logic log for that failed transaction. **Transaction integrity is unaffected** — the 400 is still returned and rollback is correct. Do not diagnose this noise as a broken rules engine.
3. **`APILOGICPROJECT_DISABLE_RULES` silently disables ALL rules** (verified in `config/activate_logicbank.py`: truthy values `1/t/true/y/yes` skip `LogicBank.activate`). Legitimate for bulk loads; a deploy-time footgun otherwise. Detection: startup prints `LogicBank rules disabled` and no dependency listing appears. Check this env var before trusting any running server.
4. **GenAI features are LLM-dependent and non-deterministic** (per docs, not live-verified): `genai-create`, `genai-iterate`, and related commands require `APILOGICSERVER_CHATGPT_APIKEY` and can produce differing or invalid output between runs; a `--repaired-response` replay path exists per docs. The deterministic core (create-from-schema, rules engine, API) needs no key. Guardrails: **apilogicserver-genai-development**.
5. **Header metadata inside generated files is prototype residue, not provenance** (verified): a project created 2026-08-21 on 17.03.19 carries an `api_logic_server_run.py` header saying "(v 15.00.38, July 06, 2025…)" and a `database/models.py` header "Created: May 25, 2025" with the upstream author's Mac path. Trust `als welcome` and the `api_logic_server__version = '17.03.19'` variable, never header comment dates.
6. **The admin SPA is a served, minified artifact** (verified in `ui/admin/admin_loader.py`): the customization surface is `ui/admin/admin.yaml` only; the React internals live in the venv package, not your repo. Needing more UI than the yaml allows means a custom app (`ui/` react apps, `genai-add-app`), not patching SRA.
7. **Whole-runtime version pinning rides on one package** (verified): project `requirements.txt` is just `ApiLogicServer`, so Flask/SQLAlchemy/SAFRS/LogicBank versions float with it. Reproducibility therefore depends on venv discipline — **apilogicserver-build-and-env**.
8. **Rule edits require a restart** (invariant 6 corollary, verified: activation happens once in `api_logic_server_setup`). No hot reload of logic; plan restarts into every change procedure (**apilogicserver-change-control**).
9. **CLI help drift** (verified): 17.03.19 help text claims `gail | gal` synonyms that are not installed, and `ApiLogicServer version` is not a command (use `als welcome` / `als about`). Full catalog: **apilogicserver-cli-and-config**.

Anything that changes files to address these goes through the gates in **apilogicserver-change-control** — no exceptions.

## 9. First 15 minutes in an unknown ALS project — orientation checklist

1. Run `als welcome` (venv active). Expect a version line (17.03.19 here). If the command is missing → **apilogicserver-build-and-env**.
2. `ls` the project root. Expect `api/ config/ database/ devops/ docs/ integration/ logic/ security/ test/ ui/` plus `api_logic_server_run.py` (verified anatomy, section 4). Anything missing means a nonstandard or pre-17 project — proceed carefully.
3. Read `logic/declare_logic.py` and `ls logic/logic_discovery/` — this is the business behavior. Then `security/declare_security.py` for who-sees-what.
4. Open `database/models.py` header only — confirm which database it was introspected from. Do NOT edit it (REGEN).
5. Check `config/config.py` for `SQLALCHEMY_DATABASE_URI` and `SECURITY_ENABLED`; check the environment for `APILOGICPROJECT_*` overrides (invariant 4) and especially `APILOGICPROJECT_DISABLE_RULES` (weak point 3).
6. Start the server (**apilogicserver-operate-and-deploy**: `python api_logic_server_run.py`, port 5656) and read the startup log against section 6: dependency listing present? `LogicBank Activation` line present?
7. Fire one discriminating write (section 7) and read the `Logic Phase:` log. If phases are absent on a write, stop and open **apilogicserver-debugging-playbook**.
8. Before changing anything: **apilogicserver-change-control**.

## Provenance and maintenance

Volatile facts, each with a one-line re-verification command (run from a project root unless noted):

- Installed version and product name (17.03.19 / Genai-Logic): `als welcome`
- Command list / help drift (`gail|gal` absent, no `version` command): `ApiLogicServer --help`
- Startup order (models → customize_models → activate_logicbank → expose_models → expose_services → configure_auth): `grep -n "activate_logicbank\|expose_models\|expose_services\|configure_auth" config/server_setup.py`
- Config precedence (defaults → Config → CLI → APILOGICPROJECT_* env): `grep -n "from_object\|get_cli_args\|from_prefixed_env" api_logic_server_run.py`
- Env names in config: `grep -n "SECURITY_ENABLED\|OPT_LOCKING\|KAFKA_SERVER\|APILOGICPROJECT_" config/config.py`
- Rules kill-switch: `grep -n "DISABLE_RULES" config/activate_logicbank.py`
- LogicBank binding + constraint rebadging: `grep -n "LogicBank.activate\|constraint_handler\|ValidationErrorExt" config/activate_logicbank.py config/server_setup.py`
- Logging bug still present?: `grep -n "splitlines" config/server_setup.py` (bug = argument `('\n')` inside `short_format_exception`)
- Optimistic-locking checksum in API: `grep -n "add_check_sum\|_check_sum_" api/expose_api_models.py` — or a live probe: `curl -s http://localhost:5656/api/<Entity>/?page%5Blimit%5D=1 | grep S_CheckSum` (add `Authorization: Bearer <token>` if security is on)
- Landing redirect to admin app: `curl -s -o /dev/null -w "%{http_code} %{redirect_url}\n" http://localhost:5656/`
- Ownership headers ("Your Code Goes Here" vs "do not customize"): `head -30 database/models.py api/customize_api.py config/server_setup.py`
- Admin SPA served from venv: `grep -n "get_sra_directory\|APILOGICPROJECT_SRA" ui/admin/admin_loader.py`
- Logic discovery contents: `ls logic/logic_discovery/`
- Log format / phases: run any failing PATCH and read `logs/als.log` for `Logic Phase:` lines
- Rebuild-writes-merge-files behavior for `admin.yaml` (`admin-created.yaml` / `admin-merge.yaml`): per docs Database-Changes, not live-verified — re-check after your first rebuild with `ls ui/admin/`

Grounded in: https://apilogicserver.github.io/Docs/Architecture-What-Is/, https://apilogicserver.github.io/Docs/Architecture-Project-Operation/, https://apilogicserver.github.io/Docs/Architecture-Internals/, https://apilogicserver.github.io/Docs/Project-Structure/, https://apilogicserver.github.io/Docs/Architecture-Declarative-Automation/, https://apilogicserver.github.io/Docs/Tech-Summary/ and a live Genai-Logic 17.03.19 install (2026-08-23) — two created projects (basic_demo, Northwind-with-customizations) and a running server, verified against a live install.
