---
name: apilogicserver-cli-and-config
description: Catalog of every ApiLogicServer/Genai-Logic configuration axis - CLI commands and flags (als create, add-auth, add-db, add-cust, genai family, rebuild-from-database, rebuild-from-model, run, login, curl), --db-url shorthands and SQLAlchemy URI forms, config/config.py Config and Args classes, config/default.env, and APILOGICPROJECT_* environment variables (PORT, FLASK_HOST, SECURITY_ENABLED, OPT_LOCKING, DISABLE_RULES, STOP_OK, NO_FLASK). Use when picking or verifying a CLI command or flag, hitting "no such option" or "Invalid OPT_LOCKING", changing port/host/http scheme, pointing a project at a different database, overriding settings via env vars or Docker env.list, checking a flag default, or resolving what a db-url abbreviation (nw, nw+, basic_demo, auth, todo) expands to. Do NOT use for install/venv trouble (apilogicserver-build-and-env), server operation (apilogicserver-operate-and-deploy), or rule authoring (apilogicserver-logic-patterns).
---

# ApiLogicServer CLI and Configuration Reference

## Purpose

This is the single home for the CLI command/flag catalog and every configuration axis of an API Logic Server project: `als` commands, `--db-url` forms, `config/config.py`, `config/default.env`, and the `APILOGICPROJECT_*` environment-variable family. Everything marked "verified" was checked by executing the CLI or reading the installed package and two real generated projects on 2026-08-23 against Genai-Logic 17.03.19 (the pip package that `pip install ApiLogicServer` installs). Where the rendered `--help` text is garbled (it is, in places — see "Help-output caveat"), the installed CLI source is quoted instead.

## Use this skill when

- You need the exact name, default, or meaning of a CLI command or flag before running it.
- A command failed with `no such option`, `Invalid OPT_LOCKING`, `does not appear to be a project`, or prompted interactively when you expected batch behavior.
- You must change port, host, swagger host, HTTP scheme, API prefix, security toggle, or optimistic-locking mode — and need to know whether to use a CLI arg, `config.py`, `default.env`, or an env var (and which wins).
- You need a `--db-url` value: a shorthand (`nw`, `nw+`, `basic_demo`, `auth`, ...) or a full SQLAlchemy URI for sqlite/PostgreSQL/MySQL/SQL Server/Oracle.
- You are wiring Docker/deployment env files and need the exact `APILOGICPROJECT_*` names.
- You want to add a new config option to a project.

## Do NOT use this skill when

- Installing Python/venv/DB drivers, or `als` itself is not found → **apilogicserver-build-and-env**.
- Starting/stopping servers, ports in use, admin-app URLs, containers → **apilogicserver-operate-and-deploy**.
- Writing rules or custom endpoints → **apilogicserver-logic-patterns**, **apilogicserver-api-contract**.
- Deciding what is safe to edit vs regenerate → **apilogicserver-change-control** (any change procedure here ends at its gates).
- Auth providers, roles, Grant/GlobalFilter semantics → **apilogicserver-security-model**.
- The genai command family in depth (prompts, WebGenAI, guardrails) → **apilogicserver-genai-development**.

---

## 1. CLI identity and version (verified 2026-08-23, Genai-Logic 17.03.19)

Five console entry points are installed by the package and are byte-identical dispatchers — each imports `api_logic_server_cli.cli.start` and calls it, which prints the banner and invokes the same click command group:

| Entry point | Status (this install) |
|---|---|
| `ApiLogicServer` | verified, works |
| `als` | verified, works (shortest — used throughout this library) |
| `genai-logic` | verified, works |
| `gail` | verified present and working (`gail welcome` exits 0) |
| `gal` | verified present and working (`gal welcome` exits 0) |

Notes:

- Docs pages use `ApiLogicServer`, `als`, and `genai-logic` interchangeably. All commands below work under any of the five names.
- There is **no** `als version` command in 17.03.19 (it errors). Use:
  - `als welcome` — prints "Welcome to Genai-Logic 17.03.19" and exits ("Just print version and exit").
  - `als about` — version plus install path, PYTHONPATH, recent changes, system info.
- The click group asserts Python >= 3.10 (excluding 3.11.0/3.11.1) when run as a script; interpreter problems belong to **apilogicserver-build-and-env**.

Re-verify entry points at any time: `ls "$(dirname "$(command -v als)")" | grep -iE 'apilogicserver|als|gail|gal|genai'`

---

## 2. Verified command inventory (from `als --help`, run 2026-08-23)

"Mutating" = writes or overwrites project/manager files, or sends writes to a server. Verification: `help` = help text captured here; `src` = installed CLI source read; `exec` = actually executed against this install (by this library's ground-truth runs).

| Command | One line | Mutating | Verified |
|---|---|---|---|
| `about` | Recent changes, install path, system info | no | help+exec |
| `add-auth` | Adds authentication/authorization (auth DB + provider) to current project | YES | help+src+exec |
| `add-cust` | Overlays sample customizations onto a northwind/genai/basic_demo project | YES | help+src+exec |
| `add-db` | Adds a second database (SQLAlchemy "bind key") — model, api, app — to current project | YES | help+src |
| `create` | Creates a new project from `--db-url` (overwrites existing dir of same name) | YES | help+src+exec |
| `create-and-run` | `create`, then starts the server | YES + starts server | help+src |
| `create-ui` | Internal: regenerates admin `models.yaml` from `models.py` | writes yaml | help+src |
| `curl` | Executes a cURL command, injecting saved `Authorization: Bearer` header from `login` | only if your verb mutates | help+src |
| `curl-test` | Canned curl smoke tests — nw project only, includes a data-mutating POST | YES (test data) | help+src |
| `examples` | Prints example commands and SQLAlchemy URIs | no | exec |
| `genai` | Creates a project from a natural-language prompt via an LLM | YES | help+src |
| `genai-add-app` | Generates a customizable React app under `ui/` | YES | src |
| `genai-add-mcp-client` | Adds MCP client (mcp db bind, logic, admin app) to project | YES | src |
| `genai-create` | Writes prompt file then invokes `genai` (new project) | YES | src |
| `genai-graphics` | Adds dashboard graphics to current project via LLM | YES | src |
| `genai-iterate` | Re-submits accumulated prompts + a new one; regenerates project | YES | src |
| `genai-logic` | Adds (or with `--suggest`, only suggests) rules from natural language | YES | src |
| `genai-utils` | GenAI utilities: `--fixup`, `--import-genai`, `--rebuild-test-data`, `--submit` | YES | src |
| `login` | Logs in to a running project server; caches JWT token for `curl` | writes token cache only | help+src |
| `rebuild-from-database` | Regenerates `database/models.py`, api, ui from a changed database schema | YES | help+src |
| `rebuild-from-model` | Regenerates database, api, ui from a hand-changed `database/models.py` | YES | help+src |
| `run` | Runs existing project = `python api_logic_server_run.py` in the project | starts server | help+src |
| `start` | Creates/opens the Manager (a workspace dir with samples) in an IDE | YES (manager dir) | help+src |
| `tutorial` | Creates/updates the Tutorial project tree | YES | help |
| `welcome` | Prints version, exits | no | exec |

Hidden commands (declared `hidden=True` in cli.py — internal, do not build runbooks on them): `genai-cust`, `sample-ai`, `sample-ai-iteration` (verified in source, 2026-08-23).

Jargon: **JWT** (JSON Web Token) — the signed bearer token returned by `POST /api/auth/login`; **MCP** (Model Context Protocol) — see **apilogicserver-integration-patterns**; **Manager** — the `als start` workspace directory holding sample projects.

---

## 3. Flag conventions and the help-output caveat (verified 2026-08-23)

1. **Every major flag has two spellings.** The CLI source declares each option twice: `--db_url` (underscore, legacy) and `--db-url` (hyphen), both bound to the same parameter. Both work. Docs and `als examples` freely mix them. Prefer hyphens; do not "fix" underscores in docs' commands — they are valid.
2. **Some hyphen-form options prompt interactively when omitted.** `als create` with no args prompts for "Project Name" and "SQLAlchemy Database URI" (click `prompt=` on `--project-name`, `--db-url`). In scripts/CI always pass both flags explicitly to avoid a hang waiting for stdin.
3. **Help-output caveat (verified 17.03.19):** rendered `--help` for `create`, `genai`, and the rebuild commands shows some help strings shifted onto the wrong flag (an artifact of hiding the underscore variants). Examples actually observed: `--not-exposed` shows "Creates ui/react app (yaml model)" but the source help is "Tables not written to api/expose_api_models"; `--temperature` shows "Number of test data rows"; `genai --help` omits the `--project-name` row entirely though the option exists. **Trust flag names from `--help`, but meanings/defaults from the tables below (taken from the installed source).**
4. Boolean pairs follow click style: `--admin-app / --no-admin-app`. One irregular spelling exists: `--flask-appbuilder / --noflask-appbuilder` (no hyphen after "no") — copy it exactly.

---

## 4. Flag tables for the big commands

Source of truth: `als <cmd> --help` output captured 2026-08-23 plus the installed `api_logic_server_cli/cli.py`. "SD" in Notes = present in CLI help, sparsely documented.

### 4.1 `als create` (verified 2026-08-23, Genai-Logic 17.03.19)

Canonical form:

```bash
als create --project-name=basic_demo --db-url=basic_demo
```

| Flag | Default | Meaning | Notes |
|---|---|---|---|
| `--project-name` | `ApiLogicProject` | Project directory to create (overwrites) | prompts if omitted |
| `--db-url` | Northwind sample (`nw.sqlite`) | Shorthand or SQLAlchemy URI (section 5) | prompts if omitted; `?` for help |
| `--auth-db-url` | `auth` | URI/shorthand for the authentication DB | pair with `--auth-provider-type` |
| `--auth-provider-type` | `` (blank) | Blank = no authentication; `sql` or `keycloak` to create secured | see apilogicserver-security-model |
| `--from-model` | `` | Create from a SQLAlchemy model file instead of a live DB | SD |
| `--api-name` | `api` | Last URL node (`/api`) | |
| `--opt-locking` | `optional` | Optimistic locking: `ignored`, `optional`, `required` | see section 6.4 |
| `--opt-locking-attr` | `S_CheckSum` | Attribute name for the locking checksum | source says "(unused)" |
| `--id-column-alias` | `Id` | Attribute name used for DB columns literally named `id` | avoids safrs conflict |
| `--from-git` | `` | Clone-from template project or directory | SD |
| `--run` | off (flag) | Run the created project immediately | |
| `--quote` | off (flag) | Quote column names in generated model | for reserved-word columns |
| `--open-with` | `` | Open created project in an editor (e.g. `code`) | |
| `--not-exposed` | `ProductDetails_V` | Tables NOT written to `api/expose_api_models` | rendered help mislabeled; source meaning shown here |
| `--admin-app/--no-admin-app` | on | Generate `ui/admin` (admin.yaml) app | |
| `--multi-api/--no-multi-api` | off | Create multiple APIs | SD |
| `--flask-appbuilder/--noflask-appbuilder` | off | Generate `ui/basic-web-app` | irregular "no" spelling |
| `--react-admin/--no-react-admin` | off | Generate `ui/react-admin` app | SD |
| `--favorites` | `name description` | Column names displayed first in admin app | |
| `--non-favorites` | `id` | Column names displayed last | |
| `--use-model` | `` | Use pre-built model file (troubleshooting path) | SD |
| `--host` | `localhost` | Server hostname baked into the created project | |
| `--port` | `5656` | Port baked into the created project; empty = no port in URLs | |
| `--swagger-host` | `localhost` | Host clients/swagger use to reach the API | |
| `--extended-builder` | `` | Your `your_code.py` for additional build automation | rendered help says "yml for include, exclude" — source meaning shown here |
| `--include-tables` | `` | yml file of tables to include/exclude | SD |
| `--infer-primary-key/--no-infer-primary-key` | off | Infer a primary key for tables with only unique cols | needed for key-less tables |

### 4.2 `als add-auth` (verified 2026-08-23)

Run from the project root (`--project-name=.` is the default).

```bash
als add-auth --db_url=auth          # sqlite auth DB, sql provider (as used to build the reference project)
```

| Flag | Default | Meaning | Notes |
|---|---|---|---|
| `--provider-type` | `sql` | `sql`, `keycloak`, or `none` (none removes auth) | |
| `--db-url` | `auth` | Auth DB: `auth` shorthand, or full SQLAlchemy URI | `auth` + `sql` internally resolves to the installed starter auth sqlite |
| `--project-name` | `.` | Project location | errors "does not appear to be a project" if no `database/models.py` |
| `--api-name` | `api` | API prefix | |
| `--bind_key_url_separator` | `-` | Separator between bind key and class name in URLs | underscore-only spelling; SD |

After add-auth, `config/default.env` carries `SECURITY_ENABLED = True` (verified in the reference project). Semantics of roles/grants → **apilogicserver-security-model**.

### 4.3 `als add-db` (verified from help + source 2026-08-23; not executed here)

```bash
als add-db --db-url=todo --bind-key=Todo
```

| Flag | Default | Meaning | Notes |
|---|---|---|---|
| `--db-url` | Northwind sample | Database to add | |
| `--bind-key` | `Alt` | SQLAlchemy bind key (multi-DB name); becomes class/URL prefix | `auth` db-url forces bind key `authentication` |
| `--bind_key_url_separator` | `-` | bindkey/class URL separator | SD |
| `--quote` | off | Quoted column names | |
| `--project-name` | `.` | Project location | |
| `--api-name` | `api` | API prefix | |

Multi-DB model layout → **apilogicserver-data-modeling**.

### 4.4 `als rebuild-from-database` / `als rebuild-from-model` (verified from help + source 2026-08-23)

Same flag set as `create` minus creation-only options: `--auth-db-url`, `--auth-provider-type`, `--from-model`, `--multi-api`, `--include-tables`, `--opt-locking*` are absent from BOTH rebuilds; `rebuild-from-database` additionally keeps `--id-column-alias` and `--quote`, which `rebuild-from-model` drops (verified from both `--help` outputs). Key facts:

- `rebuild-from-database`: schema changed in the DB → regenerates `database/models.py`, api, ui files. Your `logic/`, `api/customize_api.py`, `ui/admin/admin.yaml` are preserved; rebuilds write `admin-created.yaml`/`admin-merge.yaml` for you to merge manually.
- `rebuild-from-model`: you edited `database/models.py` → regenerates database DDL, api, ui.
- Defaults: `--project-name` `ApiLogicProject`-style default in help, but in practice run from project root with `--project-name=.` and the same `--db-url` used at create.
- Full merge discipline, what gets clobbered, and when to run these at all: **apilogicserver-change-control** (do not run a rebuild without reading it).

### 4.5 `als run` (verified 2026-08-23)

| Flag | Default | Meaning |
|---|---|---|
| `--project-name` | `` = current directory | Project to run |
| `--host` | `localhost` | Server hostname |
| `--port` | `5656` | Port (empty = omit from URLs) |
| `--swagger-host` | `localhost` | Host clients use |

`als run` simply executes `python api_logic_server_run.py` in the project with the current interpreter (verified in source; the host/port args are accepted but NOT forwarded to the run file — a source comment says forwarding them makes it hang, so to override port/host use the run-file args or env vars of section 7). Server lifecycle, admin app URL, port collisions → **apilogicserver-operate-and-deploy**.

### 4.6 `als genai` (flags verified from source 2026-08-23; LLM execution NOT verified here)

Requires env var `APILOGICSERVER_CHATGPT_APIKEY` (exact name verified in installed `api_logic_server_cli/genai/client.py`; unset → exception). Model choice env var: `APILOGICSERVER_CHATGPT_MODEL`.

| Flag | Default | Meaning | Notes |
|---|---|---|---|
| `--using` | `genai_demo` | File or directory of prompt(s) | |
| `--db-url` | `sqlite` | Target DB technology | |
| `--project-name` | `_genai_default` | Project location | missing from rendered help (bug); exists |
| `--genai-version` | `''` | LLM version, e.g. `gpt-3.5-turbo`, `gpt-4o`; blank = env/model default | |
| `--repaired-response` | `''` | Re-run project build from a saved/hand-fixed LLM response file — no LLM call | replay path; per docs, not live-verified |
| `--retries` | `3` | Retry count on failed generation | |
| `--opt-locking` | `optional` | as in create | |
| `--prompt-inserts` | `''` | Inserts file; blank = default from db-url; `*` = none | SD |
| `--quote` | off | Quoted column names | |
| `--use-relns` | on | Internal (create_db with relationships) | rendered help wrong; SD |
| `--tables` | `12` | Number of tables to request | |
| `--test-data-rows` | `4` | Test data rows per table | |
| `--temperature` | `0.7` | LLM sampling temperature | rendered help mislabeled |
| `--active-rules` | off | Use `logic/active_rules` | SD |

Family one-liners (defaults from source): `genai-create`/`genai-iterate` take `--project-name` + `--using` (prompt text; iterate appends numbered `.prompt` files under `system/genai/temp/<project>`); `genai-logic` (`--using=docs/logic`, `--suggest`, `--logic="<one rule in English>"`, `--retries=3`); `genai-graphics` (`--using=docs/graphics`, `--replace-with`); `genai-add-app` (`--app-name=react_app`, `--vibe/--no-vibe`, `--retries=1`, `--schema=admin.yaml`); `genai-utils` (`--fixup`, `--import-genai`, `--import-resume`, `--submit`, `--rebuild-test-data`, `--response=docs/response.json`). All LLM-dependent — depth in **apilogicserver-genai-development**.

### 4.7 `als login` / `als curl` (verified from source 2026-08-23)

- `als login --user=admin --password=p` — POSTs to the running project's `/api/auth/login`, stores the JWT as `last_login_token` in the install's `api_logic_server_cli/api_logic_server_info.yaml` (NOT in the project). Defaults `admin`/`p` match the sample auth DB; prompts if flags omitted.
- `als curl '<curl args>' [--data='<json>'] [--security/--no-security]` — wraps your curl text, appending `-H 'Authorization: Bearer <cached token>'` when `--security` (default on). With `--data` it adds JSON content-type headers.
- Raw equivalent (verified live 2026-08-23 against a secured running project):

```bash
curl -s -X POST http://localhost:5656/api/auth/login -H "Content-Type: application/json" -d '{"username":"admin","password":"p"}'
# → {"access_token":"<JWT>"}; then:
curl -s "http://localhost:5656/api/Category/?page%5Blimit%5D=1" -H "Authorization: Bearer <JWT>"
```

JSON:API (the response format: `data/attributes/relationships`, `page[limit]` params) usage → **apilogicserver-api-contract**.

---

## 5. `--db-url` reference

### 5.1 Shorthand abbreviations (verified 2026-08-23 from installed `create_from_model/api_logic_server_utils.py`)

A shorthand makes `create` copy an installed sample sqlite DB into `<project>/database/db.sqlite`.

| Shorthand | Resolves to (installed sample) | Notes |
|---|---|---|
| (omitted) / `''` / `nw` / `sqlite:///nw.sqlite` | `database/nw-gold.sqlite` | Northwind sample, WITHOUT customizations |
| `nw-` | `database/nw-gold.sqlite` | explicit no-customizations form |
| `nw+` / `sqlite:///nw+.sqlite` | `database/nw-gold.sqlite` + customization overlay | Northwind WITH custom api/logic/security/tests |
| `nw--` | `database/nw.sqlite` | marked "unused - avoid" in source |
| `auth` / `authorization` / `add-auth` | starter authentication sqlite (from prototypes/base) | for `--auth-db-url` / `add-auth` |
| `basic_demo` | `database/basic_demo.sqlite` | Customer/Order/Item/Product tutorial DB |
| `chinook` | `database/Chinook_Sqlite.sqlite` | albums/tracks sample |
| `classicmodels` | `database/classicmodels.sqlite` | |
| `todo` / `todos` | `database/todos.sqlite` | 1-table starter |
| `allocation` | `database/allocation.sqlite` | payment-allocation logic sample |
| `BudgetApp` | `database/BudgetApp.sqlite` | case-sensitive |
| `shipping` / `Shipping` | `database/shipping.sqlite` | Kafka consumer sample |
| `new` | `database/new.sqlite` | empty starter |
| `table_filters_tests` | internal test DB | internal |
| `{install}` prefix | replaced with the install's `database/` dir | SD |

### 5.2 Real SQLAlchemy URIs

A SQLAlchemy URI is `dialect+driver://user:password@host:port/dbname?params`. sqlite forms verified live; the server URIs below are verbatim from `als examples` output (run 2026-08-23) and the Database-Connectivity docs — **connection to those servers: per docs, not live-verified**.

```bash
# sqlite — 3 slashes + relative-ish/windows path, 4 slashes + absolute unix path
--db_url=sqlite:////Users/val/dev/todo_example/todos.db
--db_url=sqlite:///c:\ApiLogicServer\nw.sqlite

# MySQL (driver pymysql)
--db_url=mysql+pymysql://root:p@localhost:3306/classicmodels

# PostgreSQL (psycopg2 default; schema targeting via search_path)
--db_url=postgresql://postgres:p@10.0.0.234/postgres
--db_url=postgresql+psycopg2://postgres:password@localhost:5432/postgres?options=-csearch_path%3Dmy_db_schema

# SQL Server (pyodbc + ODBC Driver 18; quote the whole URI in shells)
--db_url='mssql+pyodbc://sa:Posey3861@localhost:1433/NORTHWND?driver=ODBC+Driver+18+for+SQL+Server&trusted_connection=no&Encrypt=no'

# Oracle (oracledb)
--db_url='oracle+oracledb://hr:tiger@localhost:1521/?service_name=ORCL'
```

Facts to keep straight:

- sqlite sample DBs are copied into `<project>/database/` and renamed `db.sqlite`; the project then runs standalone (verified — both reference projects have `database/db.sqlite`).
- Python 3.13+: generated `config.py` auto-rewrites `postgresql://` to `postgresql+psycopg://` (psycopg3) at load time — verified in the generated file. Driver installs → **apilogicserver-build-and-env**.
- URIs with `?`, `&`, `$`, or backslashes must be single-quoted in shells.

---

## 6. `config/config.py` anatomy (verified 2026-08-23 from generated projects; file identical in both reference projects)

Layout: `config/` contains `config.py`, `server_setup.py`, `activate_logicbank.py`, `default.env`, `logging.yml` (+ `logging-nofile.yml`, `logging-reduced.yml`), `mypy.ini`.

### 6.1 Load and override order (the contract)

`api_logic_server_run.py` applies configuration in this order — **later wins** (verified verbatim in the run file):

```python
args = server_setup.get_args(flask_app)                      # 1. creation defaults (CREATED_*)
flask_app.config.from_object(config.Config)                  # 2. config/config.py Config class
args.get_cli_args(dunder_name=__name__, args=args)           # 3. api_logic_server_run.py CLI args
flask_app.config.from_prefixed_env(prefix="APILOGICPROJECT") # 4. APILOGICPROJECT_* env vars — LAST, WINS
```

Also: `config.py` itself calls `load_dotenv(config/default.env)` at import, so `default.env` entries become process env vars **unless already set in the real environment** (dotenv does not override existing vars). Net precedence, lowest to highest:

`Config` class literals < `config/default.env` < real (unprefixed) env vars read by `config.py` < run-file CLI args < `APILOGICPROJECT_*` env vars.

This matches the two in-repo statements: Config docstring "These values are overridden by api_logic_server_run cli args, and APILOGICPROJECT_ env variables"; `devops/docker-image/env.list` header "these values override the Config values, and the CLI arguments."

### 6.2 The `Config` class — every member (verified)

| Member | Default | Meaning |
|---|---|---|
| `CREATED_API_PREFIX` | `/api` | URI node for the JSON:API |
| `CREATED_FLASK_HOST` | `localhost`, then forced to `0.0.0.0` | IP flask binds. Quirk (verified): the guard reads `if is_docker and ...` — function object, always truthy — so the generated file always flips localhost to `0.0.0.0`; `env.list` documents 0.0.0.0 as the effective default |
| `CREATED_SWAGGER_HOST` | `localhost` | Host clients/swagger use |
| `CREATED_PORT` | `"5656"` | Flask port (string) |
| `CREATED_SWAGGER_PORT` | = port | e.g. 443 for codespaces |
| `CREATED_HTTP_SCHEME` | `http` | http or https |
| `SECRET_KEY`, `FLASK_APP`, `FLASK_ENV`, `DEBUG` | from env | standard Flask settings |
| `SQLALCHEMY_DATABASE_URI` | `sqlite:///<project>/database/db.sqlite` | THE database location; override here or via env var of the same name |
| `SQLALCHEMY_DATABASE_URI_AUTHENTICATION` | `sqlite:///<project>/database/authentication_db.sqlite` | auth DB (multi-DB bind) |
| `SQLALCHEMY_DATABASE_URI_LANDING` | `database/db_spa.sqlite` | SPA landing page DB, if present |
| `SECURITY_ENABLED` | `False`; env `SECURITY_ENABLED` overrides (`false`/`no` = off) | master auth toggle |
| `SECURITY_PROVIDER` | `'sql'` → resolved to provider class when enabled | `keycloak` in value selects the Keycloak class, else SQL |
| `KEYCLOAK_REALM` / `KEYCLOAK_BASE` / `KEYCLOAK_BASE_URL` / `KEYCLOAK_CLIENT_ID` | `kcals` / `https://localhost:8080` / base+realm / `alsclient` | all env-overridable by same names |
| `OPT_LOCKING` | `"optional"` | see 6.4 |
| `KAFKA_SERVER` / `KAFKA_PRODUCER` / `KAFKA_CONSUMER` / `KAFKA_CONSUMER_GROUP` | `None` unless env `KAFKA_SERVER` set | Kafka wiring → apilogicserver-integration-patterns |
| `N8N_PRODUCER` (+ `wh_scheme/wh_server/wh_port/wh_endpoint/wh_path/wh_token`) | `None` (template values commented) | n8n webhook → apilogicserver-integration-patterns |
| `SQLALCHEMY_TRACK_MODIFICATIONS` | `False` | leave as is |
| `PROPAGATE_EXCEPTIONS` | `False` | leave as is |

### 6.3 The `Args` class (typed accessors)

`Args` is a singleton wrapping `flask_app.config`; code should read config ONLY through it: `Args.instance.port`, `.flask_host`, `.swagger_host`, `.swagger_port`, `.http_scheme`, `.api_prefix`, `.security_enabled`, `.opt_locking`, `.client_uri`, `.verbose`, `.kafka_producer`, `.n8n_producer`, `.keycloak_*`. Two accessors read extra env vars directly (verified): `swagger_host` honors `APILOGICPROJECT_EXTERNAL_HOST`, `swagger_port` honors `APILOGICPROJECT_EXTERNAL_PORT` (codespaces-style external addressing).

### 6.4 The two style toggles (exact names, verified)

- `OPT_LOCKING` — optimistic locking (server rejects a PATCH whose row checksum `S_CheckSum` no longer matches, i.e. someone else changed the row). Values `ignored` | `optional` | `required` (enum `OptLocking` in config.py). Set in Config or `export OPT_LOCKING=required`; an invalid value prints `Invalid OPT_LOCKING. ..Valid values are ['ignored', 'optional', 'required']` and exits 1 (verified in file). Wire-level behavior → **apilogicserver-api-contract**.
- `SECURITY_ENABLED` — master auth switch. After `als add-auth`, `config/default.env` contains `SECURITY_ENABLED = True` (verified). Turn security off for an experiment with `export SECURITY_ENABLED=false` (or `APILOGICPROJECT_SECURITY_ENABLED=false`) rather than editing files. Provider/roles → **apilogicserver-security-model**.

### 6.5 `config/default.env` (verified contents, both reference projects)

A dotenv file auto-loaded by config.py. Observed entries: `SECRET_KEY`, `SQLALCHEMY_TRACK_MODIFICATIONS`, `SQLALCHEMY_ECHO`, commented `AGGREGATE_DEFAULTS`/`ALL_DEFAULTS` (LogicBank activation options read by `config/activate_logicbank.py`), commented `APILOGICPROJECT_KAFKA_*` JSON examples, `SECURITY_ENABLED = True` (after add-auth), `API_LOGIC_SERVER_TUNNEL` placeholder (MCP tunneling), and in the nw+ project `APILOGICPROJECT_CONSUME_DEBUG = true`. Quirk (verified): the basic_demo variant ships the echo key miscased as `SQLAlCHEMY_ECHO` — as such it does NOT set `SQLALCHEMY_ECHO`; the nw+ variant is correctly cased.

---

## 7. `APILOGICPROJECT_*` environment variable catalog (verified 2026-08-23)

Mechanism first: `flask_app.config.from_prefixed_env(prefix="APILOGICPROJECT")` means **any** Flask config key can be overridden by exporting `APILOGICPROJECT_<KEY>` — the table lists the names actually used/documented in generated projects. All names below were grepped from the generated projects' files (consumer file shown), not guessed.

| Env var | Consumed in | Effect |
|---|---|---|
| `APILOGICPROJECT_PORT` | flask config | Flask port (default 5656) |
| `APILOGICPROJECT_FLASK_HOST` | flask config | Bind IP (default effective 0.0.0.0) |
| `APILOGICPROJECT_SWAGGER_HOST` | flask config | Host clients use in returned URLs |
| `APILOGICPROJECT_SWAGGER_PORT` | flask config | External port (e.g. 443) |
| `APILOGICPROJECT_EXTERNAL_HOST` | config.py `Args.swagger_host` | Same as swagger_host, read directly |
| `APILOGICPROJECT_EXTERNAL_PORT` | config.py `Args.swagger_port` | Same as swagger_port, read directly |
| `APILOGICPROJECT_HTTP_SCHEME` | flask config | `http` or `https` |
| `APILOGICPROJECT_CLIENT_URI` | flask config / admin app | Full external URI for reverse-proxy cases (overrides host+port composition) |
| `APILOGICPROJECT_API_PREFIX` | flask config | URI node (default `/api`) — via generic prefix mechanism |
| `APILOGICPROJECT_SQLALCHEMY_DATABASE_URI` | flask config | Point project at another DB without editing config.py |
| `APILOGICPROJECT_SQLALCHEMY_DATABASE_URI_AUTHENTICATION` | flask config | Ditto for auth DB |
| `APILOGICPROJECT_SECURITY_ENABLED` | flask config | Auth on/off (`false`/`no` = off) |
| `APILOGICPROJECT_OPT_LOCKING` | flask config | `ignored`/`optional`/`required` |
| `APILOGICPROJECT_VERBOSE` | server_setup logging | `True` = activate key debug loggers |
| `APILOGICPROJECT_DEBUG` | api_logic_server_run.py, config.py | `True` = debugpy attach hook + DEBUG log level |
| `APILOGICPROJECT_LOGGING_CONFIG` | config.py `logging_setup` | Alternate logging yml path, project-relative (e.g. `config/logging-reduced.yml`) |
| `APILOGICPROJECT_DISABLE_RULES` | config/activate_logicbank.py | truthy (`1/t/true/y/yes`) = skip LogicBank activation entirely — diagnostic lever; see apilogicserver-debugging-playbook |
| `APILOGICPROJECT_STOP_OK` | api/customize_api.py | Must be set for the `/stop` endpoint to shut the server down; else it returns "Shutdown not enabled" |
| `APILOGICPROJECT_NO_FLASK` | database/models.py, test-data tooling | `1` = import models without a Flask app (standalone scripts); set before importing models |
| `APILOGICPROJECT_CONSUME_DEBUG` | integration/kafka | Enables `/consume_debug/<topic>` endpoints, no Kafka broker needed (nw+ sets it in default.env) |
| `APILOGICPROJECT_KAFKA_PRODUCER` / `_KAFKA_CONSUMER` | flask config | FULL JSON override, e.g. `"{\"bootstrap.servers\": \"localhost:9092\"}"` — details in apilogicserver-integration-patterns |
| `APILOGICPROJECT_SRA` | ui/admin/admin_loader.py | Directory of the safrs-react-admin build (default `ui/safrs-react-admin`) |
| `APILOGICPROJECT_APILOGICSERVER_HOME` | ui/admin/admin_loader.py | Locate the install when not in venv (admin app assets). Caution (verified): `devops/docker-image/env.list` spells it `APILOGICPROJECT_APILOGICSERVERHOME` (no underscore) — the admin_loader comment uses the underscore form; if it seems ignored, try the other spelling and prefer plain `APILOGICSERVER_HOME` |
| `APILOGICPROJECT_KEYCLOAK_BASE` / `_KEYCLOAK_REALM` / `_KEYCLOAK_BASE_URL` / `_KEYCLOAK_CLIENT_ID` | flask config | Keycloak endpoints → apilogicserver-security-model |

Unprefixed env vars read directly by generated code (verified): `SECURITY_ENABLED`, `SQLALCHEMY_DATABASE_URI`, `SQLALCHEMY_DATABASE_URI_AUTHENTICATION`, `OPT_LOCKING`, `SECRET_KEY`, `FLASK_APP`, `FLASK_ENV`, `DEBUG`, `KAFKA_SERVER`, `KAFKA_PRODUCER`, `KAFKA_CONSUMER`, `KAFKA_CONSUMER_GROUP`, `KEYCLOAK_*`, `AGGREGATE_DEFAULTS`, `ALL_DEFAULTS`, `EXPERIMENT` (`+` = early logging setup), `APILOGICSERVER_RUNNING` (`DOCKER` marker), `CODESPACES`/`CODESPACE_NAME` (codespaces port defaulting — source comments call it experimental), `API_LOGIC_SERVER_TUNNEL`.

Install-level (CLI, not project) env vars — verified names in installed source: `APILOGICSERVER_CHATGPT_APIKEY` (required by all genai LLM calls), `APILOGICSERVER_CHATGPT_MODEL` (LLM selection; code default `gpt-4o-2024-08-06`), `APILOGICSERVER_HOME` (dev installs).

### 7.1 `api_logic_server_run.py` direct args (verified in config.py `get_cli_args`)

argparse, underscore-only: `python api_logic_server_run.py [--port=5657] [--flask_host=0.0.0.0] [--swagger_host=myhost] [--swagger_port=443] [--http_scheme=https] [--verbose=True]`; positional compatibility form `python api_logic_server_run.py <flask_host> <port> <swagger_host>` also accepted. Remember: `APILOGICPROJECT_*` env vars are applied after these and win.

---

## 8. Production vs experimental axes (assessment as of 2026-08-23, Genai-Logic 17.03.19)

| Tier | Items | Basis |
|---|---|---|
| Verified-stable (safe for runbooks) | `create`, `run`, `rebuild-from-database`, `rebuild-from-model`, `add-auth`, `add-cust`, `add-db`, `login`, `curl`, `about`, `welcome`, `examples`; config precedence chain; `APILOGICPROJECT_*` overrides; db-url shorthands | executed here or read from installed source + working generated projects |
| LLM-dependent / preview | entire `genai` family (`genai`, `genai-create`, `genai-iterate`, `genai-logic`, `genai-graphics`, `genai-add-app`, `genai-add-mcp-client`, `genai-utils`) — require `APILOGICSERVER_CHATGPT_APIKEY`, outputs vary, `--repaired-response` replay documented but untested here | per docs, not live-verified; guardrails in apilogicserver-genai-development |
| Internal / avoid in automation | `create-ui`, `curl-test` (hardcoded nw URLs + mutating POST), `tutorial`, `start` (opens an IDE; interactive), hidden `genai-cust`, `sample-ai`, `sample-ai-iteration`; `nw--` shorthand; `EXPERIMENT` env; codespaces auto-defaulting | marked internal/hidden/experimental in source |

---

## 9. Add a config option — checklist

Follow in order; the final gate is **apilogicserver-change-control** (config.py IS a customizable file, but changes still go through its verification gates).

1. Declare the default in the `Config` class in `config/config.py`, UPPER_CASE: `MY_FEATURE_ENABLED = os.getenv('MY_FEATURE_ENABLED', 'False') == 'True'`. Keep a pure-Python default so the server boots with no env at all.
2. (Recommended) Add a typed accessor property (getter+setter over `self.flask_app.config["MY_FEATURE_ENABLED"]`) to `Args`, mirroring `security_enabled` — consumers then read `Args.instance.my_feature_enabled`.
3. Do NOT write a custom env parser for deployment override: `APILOGICPROJECT_MY_FEATURE_ENABLED` already works via `from_prefixed_env` and wins over everything. Only add explicit `os.getenv` reads if the value is needed before the Flask app exists.
4. Document it where operators look: a commented line in `config/default.env` and in `devops/docker-image/env.list`.
5. Re-verify: start the server and confirm the config log line appears (`config.py` logs its decisions at startup); flip the env var and confirm the change; then run the project's test suite per **apilogicserver-validation-and-qa** and record evidence per **apilogicserver-change-control** before merging.

---

## 10. Drift table — re-verify before trusting (flags drift between releases)

| Volatile fact | One-line re-check (run in any project / venv) |
|---|---|
| Installed version is 17.03.19 | `als welcome` |
| Five equivalent entry points incl. `gail`/`gal` | `ls "$(dirname "$(command -v als)")" \| grep -iE 'als\|gail\|gal\|genai\|ApiLogicServer'` |
| Command list (25 visible) | `als --help` |
| `create` flag set / defaults | `als create --help` (names only — meanings garble; see section 3) |
| `--infer-primary-key` still exists | `als create --help \| grep infer-primary-key` |
| `add-auth` defaults (sql, auth, `.`) | `als add-auth --help` |
| genai flags incl. `--repaired-response` | `als genai --help` |
| db-url shorthand + URI examples | `als examples` |
| default port 5656 / hosts | `grep -n "CREATED_PORT\|CREATED_FLASK_HOST\|CREATED_SWAGGER_HOST" config/config.py` |
| `OPT_LOCKING` values and default | `grep -n "OPT_LOCKING\|class OptLocking" -A3 config/config.py` |
| `SECURITY_ENABLED` toggle location | `grep -n SECURITY_ENABLED config/config.py config/default.env` |
| DB URI defaults (db.sqlite, auth db) | `grep -n SQLALCHEMY_DATABASE_URI config/config.py` |
| Env override mechanism still last-wins | `grep -n from_prefixed_env api_logic_server_run.py` |
| Project-level env var inventory | `grep -rho "APILOGICPROJECT_[A-Z_]*" . --include=*.py --include=*.env \| sort -u` |
| Genai key env var name | `grep -rn APILOGICSERVER_CHATGPT_APIKEY "$(python -c 'import api_logic_server_cli,os;print(os.path.dirname(api_logic_server_cli.__file__))')/genai/client.py"` |
| `/stop` gate | `grep -n STOP_OK api/customize_api.py` |
| Optimistic-locking checksum attr | `curl -s <server>/api/<AnyResource>/?page%5Blimit%5D=1 -H "Authorization: Bearer <JWT>" \| grep -o S_CheckSum` |
| default.env echo-key casing quirk | `grep -n "SQLA.CHEMY_ECHO" config/default.env` |

---

## Provenance and maintenance

- CLI name equivalence (ApiLogicServer/als/genai-logic/gail/gal): re-check `ls "$(dirname "$(command -v als)")"` and `gail welcome`. Note: an earlier ground-truth pass recorded gail/gal as absent; direct execution on 2026-08-23 found all five installed and working — always re-run the check on a fresh install.
- Version / command list: `als welcome`; `als --help`.
- Flag meanings vs garbled help: compare `als create --help` against `@click.option` declarations in the installed `api_logic_server_cli/cli.py`.
- db-url shorthands: `als examples`, and the resolver in `api_logic_server_cli/create_from_model/api_logic_server_utils.py`.
- Config precedence: `grep -n from_prefixed_env api_logic_server_run.py` plus the `Config`/`Args` docstrings in `config/config.py`.
- Env var catalog: `grep -rho "APILOGICPROJECT_[A-Z_]*" . --include=*.py --include=*.env --include=*.json | sort -u` in any generated project; `cat devops/docker-image/env.list`.
- GenAI env vars: `grep -rn "APILOGICSERVER_CHATGPT" <site-packages>/api_logic_server_cli/genai/`.
- Live-API syntax (login, Bearer, page[limit], S_CheckSum): re-probe any running secured project with the curl pair in section 4.7.
- Grounded in: https://apilogicserver.github.io/Docs/ApiLogicServer-create/, https://apilogicserver.github.io/Docs/Project-Env/, https://apilogicserver.github.io/Docs/Database-Connectivity/, https://apilogicserver.github.io/Docs/Execute/ and a live Genai-Logic 17.03.19 install (2026-08-23) — CLI help/source, two generated projects (basic_demo, nw+ sample), and a running secured server, verified against a live install in the session scratchpad.
