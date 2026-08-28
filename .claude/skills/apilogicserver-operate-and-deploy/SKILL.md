---
name: apilogicserver-operate-and-deploy
description: Operations runbook for API Logic Server (Genai-Logic) projects - starting the server (python api_logic_server_run.py, als run, run.sh/run.ps1, VSCode F5 launch configs), the startup banner and what a healthy start looks like, changing port/host (--port, --flask_host, APILOGICPROJECT_PORT precedence), the full URL map (/ redirect, /admin-app/index.html, /api Swagger, /api/auth/login, /ui/admin/admin.yaml, /metadata, /stop), the react-admin Admin App and admin.yaml customization, logs/als.log and config/logging.yml, building/running project Docker images (devops/docker-image/build_image.sh, docker-compose variants, env.list), gunicorn, and Azure/PythonAnywhere deploy outlines. Use when running, verifying, stopping, containerizing, or deploying a project, or on symptoms - "Port 5656 is in use by another program", "Address already in use", connection refused, server won't start, blank admin app, "where is swagger", "how do I change the port", "where do logs go", "docker build for my project", "deploy to Azure".
---

# API Logic Server: Operate and Deploy

## Purpose

This skill is the operations runbook for a created API Logic Server (product name: **Genai-Logic**) project: how to start it, prove it is healthy, find every URL it serves, read what it writes to `logs/`, run and customize the Admin App, package it into a Docker image, and deploy it. Every command, flag, URL, and message marked "verified" was executed against a live Genai-Logic 17.03.19 install with the Northwind-with-customizations sample (`nw+`) running (verified 2026-08-23/24); container builds and cloud deploys were **not** executed here and are labeled accordingly.

## Use this skill when

- Starting or stopping a project server, locally, in an IDE, or in a container
- Verifying a server is healthy (which URLs to probe, what a good startup banner shows)
- The server will not start: "Port 5656 is in use by another program", "Address already in use"
- Changing port, bind host, or the host/scheme advertised to clients (Swagger/Admin App URLs)
- Anything Admin App: touring it, customizing `ui/admin/admin.yaml`, understanding why there is no generated UI code
- Finding or configuring server logs (`logs/als.log`, `config/logging.yml`)
- Building a Docker image of the project, choosing a docker-compose variant, passing env vars into containers
- Deploying: Azure single/multi-container, PythonAnywhere, gunicorn for production

## Do NOT use this skill when

- Installing Python/venv/ALS itself, or `F5` fails on missing modules → **apilogicserver-build-and-env**
- You need the full CLI flag catalog, `--db-url` forms, or `config/config.py` semantics beyond ports/hosts → **apilogicserver-cli-and-config**
- Calling the API (filters, PATCH shapes, custom endpoints' payloads) → **apilogicserver-api-contract**
- Login failures, roles, Grant/GlobalFilter → **apilogicserver-security-model**
- Interpreting the logic log or diagnosing rule misfires → **apilogicserver-debugging-playbook** (and **declarative-rules-reference** for theory)
- Running the Behave suite / Logic Report → **apilogicserver-validation-and-qa**
- Deciding what may be edited vs regenerated before you change anything → **apilogicserver-change-control**

---

## 1. Local run (verified 2026-08-23/24, Genai-Logic 17.03.19)

Terms used below, once: **WSGI** = Python's standard interface between web servers and web apps; **gunicorn** = a production WSGI server (the built-in Flask server is for development); **venv** = per-project Python virtual environment.

### 1.1 Canonical start: `python api_logic_server_run.py`

Run from the **project root**, venv active:

```bash
python api_logic_server_run.py
```

Real startup output, excerpted verbatim from a live `nw+` project start (verified; middle sections elided):

```
API Logic Project Server Setup (nw_sample) Starting with CLI args:
.. api_logic_server_run.py
...
The following rules have been activated
...
Logic Bank 1.32.00 - 34 rules loaded
Exposing /Category
Exposing /Customer
...
Declare   API - api/expose_api_models, endpoint for each table on localhost:5656, customizing...
..discovered services: ['dashboard_services.py', 'system.py', 'mcp_discovery.py', ...]

Authentication loaded -- api calls now require authorization header
..declare security - security/declare_security.py authentication tables loaded
Kafka mode: FALLBACK — KAFKA_SERVER not configured; running debug endpoint only

API Logic Project loaded (not WSGI), version: 17.03.19
.. startup message: normal start
 (running locally at flask_host: 0.0.0.0)

API Logic Project (name: nw_sample) starting:
..Explore data and API at http_scheme://swagger_host:port http://localhost:5656   *
.... with flask_host: 0.0.0.0
.... and  swagger_port: 5656

*************************************************************************
*   Startup Instructions: Open your Browser at: http://localhost:5656   *
*************************************************************************
```

Health markers in a good start: rules loaded ("Logic Bank ... N rules loaded"), one "Exposing /<Type>" per table, "Authentication loaded" if security is on, and the final boxed URL. "Kafka mode: FALLBACK" without a broker is **normal**, not an error (verified).

### 1.2 Alternative: `als run`

```bash
als run                    # from project root
```

Flags, verbatim from `als run --help` (verified):

```
--project-name TEXT  Project to run (default: current directory)
--host TEXT          Server hostname (default is localhost)
--port TEXT          Port (default 5656, or leave empty)
--swagger-host TEXT  Swagger hostname (default is localhost)
```

Note the dash/underscore split: the **als CLI** uses `--swagger-host`; the **run script** (`python api_logic_server_run.py`) uses `--swagger_host` (Section 1.5). Full CLI catalog → **apilogicserver-cli-and-config**.

### 1.3 Shipped shell runners: `run.sh` / `run.ps1` (verified file contents)

Every created project ships both at project root:

- `sh run.sh` — activates the project venv (skipped when `APILOGICSERVER_RUNNING=DOCKER`), sets `PYTHONHASHSEED=0`, `cd`s to the script's directory, then runs `python api_logic_server_run.py`. Args: `sh run.sh help` prints usage; `sh run.sh '$'` reuses the currently active venv; any **second** arg switches to gunicorn:

  ```bash
  # gunicorn arm, verbatim from run.sh (verified):
  PORT=${APILOGICPROJECT_PORT:-5656}
  gunicorn --log-level=info -b 0.0.0.0:${PORT} -w2 --reload api_logic_server_run:flask_app
  ```

- `run.ps1` (PowerShell/Windows) — activates `venv\Scripts\activate`, runs `python api_logic_server_run.py`.

The WSGI entry point is `api_logic_server_run:flask_app` — that exact module:attribute is what gunicorn and PythonAnywhere import (verified in `run.sh` and `devops/python-anywhere/python_anywhere_wsgi.py`).

### 1.4 VSCode F5 (verified from the shipped `.vscode/launch.json`, identical names in both reference projects)

Open the project folder in VSCode, pick a configuration in Run and Debug, press F5. Real configuration names:

| Configuration name | What it does |
|---|---|
| `Run Project (start server)` | Standard start: `api_logic_server_run.py` with args `--flask_host=localhost --port=5656 --swagger_port=5656 --swagger_host=localhost --verbose=False`; env sets `APILOGICPROJECT_LOGGING_CONFIG=config/logging.yml`, `APILOGICPROJECT_STOP_OK=True`; opens integrated browser on ready |
| `Run Project DEBUG` | Same, plus `APILOGICPROJECT_DEBUG=True` |
| `  - API Logic Server - VERBOSE` | Same start with `APILOGICPROJECT_VERBOSE=True` and `--verbose=True` |
| `  - No Security ApiLogicServer (e.g., simpler swagger)` | Sets `SECURITY_ENABLED=False` (and `OPT_LOCKING=optional`) |
| `  - No Security ApiLogicServer VERBOSE` | Both of the above |
| `Behave Run` / `  - Behave Scenario` / `  - Behave Logic Report` | Test suite → **apilogicserver-validation-and-qa** |
| `MCP - Model Context Protocol - Client Executor` | → **apilogicserver-integration-patterns** |
| `db-debug - explore SQLAlchemy` | → **apilogicserver-data-modeling** |

Older docs call the config "ApiLogicServer"; current 17.03.19 projects generate the names above (verified on disk — trust the file). Stop a debug run with the red stop button or Shift+F5. If F5 fails on interpreter/module errors → **apilogicserver-build-and-env**.

### 1.5 Changing port and hosts (names verified in project `config/config.py` and `launch.json`)

Four knobs, defined once:

| Setting | CLI flag (run script) | Env var | Meaning |
|---|---|---|---|
| port | `--port` | `APILOGICPROJECT_PORT` | Port Flask binds (default 5656) |
| bind host | `--flask_host` | `APILOGICPROJECT_FLASK_HOST` | IP Flask binds; `localhost` created default, `0.0.0.0` when running in Docker (auto-switched, verified in `config.py`) |
| advertised host | `--swagger_host` | `APILOGICPROJECT_SWAGGER_HOST` (also honors `APILOGICPROJECT_EXTERNAL_HOST`) | Host clients/Swagger/Admin App are told to use |
| advertised port | `--swagger_port` | `APILOGICPROJECT_SWAGGER_PORT` (also `APILOGICPROJECT_EXTERNAL_PORT`) | e.g. 443 behind Codespaces/proxy |

Also `--http_scheme` / `APILOGICPROJECT_HTTP_SCHEME` (http|https) and `APILOGICPROJECT_CLIENT_URI` (full URI override for reverse proxies — a front server forwarding requests). All flags verified in `config/config.py get_cli_args()`; positional compatibility form `python api_logic_server_run.py <flask_host> <port> <swagger_host>` also exists (verified in the same function).

**Precedence (verified in `api_logic_server_run.py` main sequence):** `config/config.py` created defaults → overridden by CLI args → overridden by `APILOGICPROJECT_*` env vars (`flask_app.config.from_prefixed_env(prefix="APILOGICPROJECT")` runs last). So `export APILOGICPROJECT_PORT=5657` beats `--port`. Full config catalog → **apilogicserver-cli-and-config**.

```bash
python api_logic_server_run.py --port=5657        # run on another port
als run --port=5657                               # same via CLI
```

### 1.6 Port collision (verified 2026-08-23)

Starting a second server on a busy port fails. Message text, verbatim (Python raises `OSError: [Errno 98] Address already in use`; the server prints the friendly form — text read from the installed werkzeug `serving.py`, collision reproduced live):

```
Port 5656 is in use by another program. Either identify and stop that program,
or start the server with a different port.
```

Resolution, in order:

1. Find the owner: `lsof -i :5656` (Mac/Linux) or `netstat -ano | findstr 5656` (Windows).
2. It is usually your own earlier run: stop it (Ctrl+C in its terminal, VSCode stop button, or Section 7's `/stop` if enabled).
3. Or run on a free port: `python api_logic_server_run.py --port=5657` — then use 5657 in every URL below.

---

## 2. URL map (each row live-probed 2026-08-24 against the running `nw+` server unless labeled)

Terms, once: **JSON:API** = the standard JSON REST format ALS serves (`{data:{type,id,attributes}}`); **JWT** = the signed JSON Web Token returned by login and sent as `Authorization: Bearer <token>`; **SPA** = single-page application; **Swagger** = interactive OpenAPI documentation UI.

| URL | What it is | Verification |
|---|---|---|
| `/` | Redirects to the Admin App: `302 → /admin-app/index.html` | verified (curl `-w %{redirect_url}`) |
| `/admin-app/index.html` | Admin App SPA (Section 3) | verified 200 text/html |
| `/admin-app/home.js` | Admin App home-page script (referenced by `admin.yaml settings.HomeJS`; file `ui/admin/home.js`) | file verified; route per admin_loader |
| `/api` | Swagger UI for the JSON:API | verified 200 text/html |
| `/api/swagger.json` | Raw OpenAPI document | verified 200 |
| `/api/<Type>/` e.g. `/api/Customer/?page[limit]=1` | JSON:API endpoint per exposed table → **apilogicserver-api-contract** | verified: 401 `{"msg":"Missing Authorization Header"}` without token; 200 with Bearer |
| `/api/auth/login` | POST `{"username":"admin","password":"p"}` → `{"access_token": ...}` → **apilogicserver-security-model** | verified 200 |
| `/ui/admin/admin.yaml` | The Admin App model, served to the SPA at load | verified 200 |
| `/ui/images/<path>` | Images referenced by admin pages | route read in `ui/admin/admin_loader.py` |
| `/admin/<path>` | Alternate/custom admin app entry (serves the SPA index) | route read in `admin_loader.py` |
| `/hello_world?user=x` | Sample custom endpoint (`api/customize_api.py`) | verified: `{"result":"hello, probe"}` |
| `/metadata?resource=Category&include=attributes` | Programmatic schema discovery (`api/api_discovery/system.py`) | verified 200 |
| `/server_log?msg=text` | Writes `msg` into the server console/log — lets test clients annotate the server log (`api/api_discovery/system.py`) | verified 200 |
| `/.well-known/mcp.json` | MCP discovery document → **apilogicserver-integration-patterns** | verified 200 |
| `/dashboard`, `/sales_by_category` | nw_sample demo services (`api/api_discovery/dashboard_services.py`, `sales_by_category.py`) | verified 200 |
| `/stop?msg=reason` | **Stops the server** (Section 7) — do not probe casually | code read, not probed |

All under `http://localhost:5656` by default. Endpoints in `api/api_discovery/` and `api/customize_api.py` vary per project — `grep -rn "@app.route" api/` lists yours (the routes above were found exactly that way).

---

## 3. The Admin App

### 3.1 Architecture (3 paragraphs)

The Admin App is **not generated code**. It is a prebuilt React SPA — SAFRS-React-Admin (**SRA**), built on the react-admin framework — shipped inside the ALS installation (docs: `.../site-packages/api_logic_server_cli/create_from_model/safrs-react-admin-npm-build`) and served by your project's Flask app. What *is* generated into your project is one declarative model file: `ui/admin/admin.yaml`. Per the Admin-Architecture docs: "The admin 'app' created in your project is *just a yaml file.* It is interpreted by a React Admin app (SAFRS React Admin - SRA)." There is no generated JavaScript to maintain.

Serving is wired by `ui/admin/admin_loader.py` (routes verified by reading the file and probing): `/` redirects to `/admin-app/index.html`; `/admin-app/<path>` serves the SPA's static files; `/ui/admin/<path>` serves `admin.yaml` itself; `/ui/images/<path>` serves images. At load, the browser fetches the SPA, the SPA fetches `/ui/admin/admin.yaml`, renders pages from it, and thereafter talks pure JSON:API to `/api` — so every Admin App write executes your rules exactly like any API client (→ **apilogicserver-architecture-contract**).

Consequence for operations: UI changes are a YAML edit plus **browser refresh** — per the Admin-Customization docs, "it is not necessary to restart the server". The app targets back-office admin and "instant agile collaboration" (working screens for business users on day one), not pixel-perfect end-user UI; for custom front ends, consume the API directly (→ **apilogicserver-api-contract**, and `ui/app_readme.md` in the project).

### 3.2 Tour highlights (per Admin-Tour docs; matching info text verified inside the real `admin.yaml`)

- **Multi-table pages**: list/show pages per table with search, sort, pagination, export; tab sheets of related child rows; click-through page transitions.
- **Automatic joins**: parent rows shown as meaningful text ("Product Name - not just the Id").
- **Lookups**: pick parent rows instead of typing foreign-key values.
- **Cascade add**: adding a child from a parent page pre-fills the parent's key (e.g. new Order gets its Customer filled in).
- **Declarative hide/show** via `show_when` (e.g. hide `Id` while inserting), images, booleans.
- **Info/help**: per-page `(?)` help from `info_list`/`info_show` — the nw sample uses these as a built-in guided tour; login button (admin/p when security is on → **apilogicserver-security-model**).

### 3.3 Customization basics — real keys from the real file

Top-level keys in the verified `nw_sample/ui/admin/admin.yaml`: `about`, `api_root` (`'{http_type}://{swagger_host}:{port}/{api}'`), `info`, `info_toggle_checked`, `authentication` (`'{system-default}'`), `resources`, `settings` (with `HomeJS`, `max_list_columns`, `style_guide`). A real resource stanza, verbatim (excerpt):

```yaml
resources:
  Customer:
    attributes:
      - name: Id
        search: true
        sort: true
      - label: ' Company Name*'
        name: CompanyName
        search: true
        sort: true
      - name: Balance
        type: DECIMAL
        info: derived as sum(Order.AmountTotal where ShippedDate is None)
    tab_groups:
      - direction: tomany
        fks:
          - CustomerId
        name: OrderList
        label: Placed Order List
        resource: Order
    type: Customer
    user_key: CompanyName
```

Levers that cover most needs: attribute **order** (list order = display order), `label`, `search`/`sort`, `user_key` (which attribute represents the row in joins), `tab_groups` (child tabs and their captions), `info`/`info_list`/`info_show` (help HTML), `show_when` (e.g. `show_when: isInserting == false`), and `settings.style_guide` (currency symbol, date format, edit modes — all present in the verified file). Deep customization (multiple yaml files per audience, home page, images, custom apps) → https://apilogicserver.github.io/Docs/Admin-Customization/ (per docs, not live-verified).

**Change control**: `admin.yaml` is customer-owned — created once, never overwritten; schema rebuilds write `admin-created.yaml` / `admin-merge.yaml` next to it for manual merge. Do not edit it without reading **apilogicserver-change-control** (which owns the merge runbook); that skill's gates are the final step of any admin-app change.

---

## 4. Logs: what lands where (verified on disk)

Real `logs/` listing after live runs: `als.log`, `als.log.1`, `readme.md`. Wiring, from the verified `config/logging.yml`:

- Root and every named logger write to **both** handlers: `console` (StreamHandler) and `file` — a `RotatingFileHandler` at `logs/als.log`, `maxBytes: 2097152` (2 MB), `backupCount: 1` (hence `als.log.1`).
- So the **logic log** (logger `logic_logger`, level DEBUG — the per-transaction rule trace) appears in the console *and* in `logs/als.log`. Reading it → **apilogicserver-debugging-playbook**; format/phases → **declarative-rules-reference**.
- Named loggers you can tune in `logging.yml`: `logic_logger`, `safrs`, `sqlalchemy.engine` (uncomment DEBUG to see SQL), `api_logic_server_app`, `security.*`, `integration.kafka/mcp/n8n`, `ui.admin.admin_loader`, more — each a two-line edit (level + restart).
- Select an alternate config via env: `APILOGICPROJECT_LOGGING_CONFIG=config/logging.yml` (the shipped launch configs set exactly this; `config/logging-nofile.yml` and `logging-reduced.yml` also ship, verified on disk).
- `logs/readme.md` (verbatim purpose): "Automatic logging is configured in `config/logging.yml`, so that your AI Ass't can 'see' your debug console." The directory must exist at startup (it ships with the project).
- Access lines (`GET /api/... 200`) are werkzeug console output; behave logs/reports land under `test/api_logic_server_behave/logs|reports/`, not `logs/` → **apilogicserver-validation-and-qa**.
- Known 17.03.19 wart (verified 2026-08-23): when a constraint violation is logged, `config/server_setup.py short_format_exception()` itself raises `TypeError: 'str' object cannot be interpreted as an integer` (bad `splitlines('\n')` call), so the console shows a logging stack trace instead of the pretty trace. The 400 response and rollback are still correct — engine fine, logging cosmetic → **apilogicserver-debugging-playbook**.

---

## 5. Containers (scripts read from the real created project — verified content; container EXECUTION not performed here)

Terms, once: a Docker **image** is a packaged filesystem+command; a **container** is a running instance; **docker compose** runs several containers as one described system; an **env file** is a `KEY=value` list passed into a container.

`devops/` tree in a created 17.03.19 project (verified): `docker-image/`, `docker-compose-dev-local/`, `docker-compose-dev-azure/`, `docker-standard-image/`, `auth-db/`, `keycloak/`, `python-anywhere/`, `readme-devops.md`. The readme's intended flow: build an image (`docker-image`) → verify multi-container locally (`docker-compose-dev-local`) → deploy to Azure (`docker-compose-dev-azure`); `auth-db` prepares database images that include test + security data.

### 5.1 Build a project image — `devops/docker-image/build_image.sh`

```bash
cd <project root>
sh devops/docker-image/build_image.sh .        # "." = use defaults coded in the script
```

What the verified script does: sets `projectname` (lower case only — Docker requires it; nw_sample → `nwsample`), `repositoryname` (default `apilogicserver` — **edit to your Docker Hub account**), `version="1.0.0"`; then runs exactly:

```bash
docker build -f devops/docker-image/build_image.dockerfile -t ${repositoryname}/${projectname} --rm .
```

On success it prints the next steps (verbatim from the script): `docker tag .../... .../...:1.0.0`, `docker push` (after `docker login`), same for `:latest`. Arg form: `sh build_image.sh myrepository myproject 1.0.1` overrides all three. The dockerfile (`build_image.dockerfile`, verified) is 5 load-bearing lines: `FROM --platform=linux/amd64 apilogicserver/api_logic_server` (pins amd64 for cloud even when building on ARM Macs), `WORKDIR /home/api_logic_project`, `COPY ../../ .` (your whole project into the image), `RUN chown -R api_logic_server /home/api_logic_project` (lets the container write SQLite files), `CMD [ "python", "./api_logic_server_run.py" ]`. Add extra Python packages via `requirements.txt` before building (per DevOps-Containers-Build docs).

### 5.2 Run the image — `devops/docker-image/run_image.sh` (verified content)

```bash
sh devops/docker-image/run_image.sh
# which runs (verbatim):
docker run --env-file devops/docker-image/env.list -it --name api_logic_project --rm \
  --net dev-network -p 5656:5656 -p 5002:5002 apilogicserver/nwsample
```

`--rm` deletes the container on exit; `--net dev-network` joins the docker network where database containers live (create once: `docker network create dev-network` — per docs, not live-verified); the shipped scripts publish 5656 (the server) and 5002 (a second port the standard scripts also expose; the app itself serves everything on 5656 — verified URL map above). Append `bash` (commented variant in the script) to get a shell inside the container instead of starting the app.

### 5.3 The docker-compose variants (all files verified on disk)

| Directory | File(s) | What it adds |
|---|---|---|
| `docker-compose-dev-local/` | `docker-compose-dev-local.yml` + `docker-compose.sh` | Runs **your built image** (`apilogicserver/nwsample`) plus a `sqlite3` sidecar; sets `APILOGICPROJECT_VERBOSE=true`, `SECURITY_ENABLED=true`; maps 5656; the `.sh` first checks security is activated (looks for `database/database_discovery/authentication_models.py`, tells you to run `genai-logic add-auth ...` if missing), then `docker compose -f ./devops/docker-compose-dev-local/docker-compose-dev-local.yml up` |
| `docker-standard-image/` | `docker-compose-standard-image.yml` + `env.list` | No project image at all: runs the **standard** `apilogicserver/api_logic_server` image, volume-mounts the project (`./../..:/app`) and starts `command: python3 /app/api_logic_server_run.py` — fastest container path since edits need no rebuild; includes commented Keycloak env vars; `restart: unless-stopped` |
| `docker-compose-dev-azure/` | `azure-deploy.sh` | Azure CLI deploy commands (Section 6.1) |
| `auth-db/` | `authdb_mysql.Dockerfile`, `authdb_mysql.sql`, `authdb_postgres.sql` | Build database images preloaded with the auth schema/data for multi-container tests |
| `keycloak/` | `docker-compose.yml` + realm imports + nginx | Keycloak identity provider stack → **apilogicserver-security-model** |

Header comment in the standard-image yml (verbatim, useful): `docker-compose -f devops/docker-standard-image/docker-compose-standard-image.yml up` / `... down` — and "if you have run docker compose up (above), you must run docker compose down to run directly".

### 5.4 Passing configuration into containers (env.list verified; semantics per DevOps-Container-Configuration docs)

`devops/docker-image/env.list` opens with the contract, verbatim: "these values override the Config values, and the CLI arguments" — the same precedence as Section 1.5, which is exactly why env vars are the container-config mechanism. Every project setting is reachable as `APILOGICPROJECT_<NAME>`; the shipped env.list documents (mostly commented): `APILOGICPROJECT_FLASK_HOST`, `_PORT`, `_SWAGGER_HOST`, `_SWAGGER_PORT`, `_HTTP_SCHEME`, `_CLIENT_URI` (reverse proxy), `_SQLALCHEMY_DATABASE_URI` and `_SQLALCHEMY_DATABASE_URI_AUTHENTICATION` (point the container at real databases, e.g. `mysql+pymysql://root:p@mysql-container:3306/classicmodels`), `_SECURITY_ENABLED`, and ships `APILOGICPROJECT_VERBOSE=True` active. Feed it with `docker run --env-file ...` (5.2), `env_file:`/`environment:` in compose (5.3), or `--environment-variables` on Azure (6.1). Database URI forms → **apilogicserver-cli-and-config**.

### 5.5 Production server: gunicorn

Flask's built-in server is a development server. For production the docs (DevOps-Container-Configuration) give:

```bash
gunicorn api_logic_server_run:flask_app -w 4 -b localhost:5656     # per docs, not live-verified
```

and the shipped `run.sh` gunicorn arm (Section 1.3, verified content) uses `-w2 --reload -b 0.0.0.0:${APILOGICPROJECT_PORT:-5656}`. Under WSGI the banner reads "loaded (WSGI)" instead of "(not WSGI)" and CLI args are ignored — configure via env vars only (verified in `config.py`: non-`__main__` runs skip arg parsing).

---

## 6. Deploy targets (per docs, NOT live-verified — no cloud execution here)

### 6.1 Azure — single container (docs: https://apilogicserver.github.io/Docs/DevOps-Containers-Deploy/)

1. Build and push your image (5.1). 2. Create an Azure account + resource group. 3. If using a managed database, create it and load your SQL. 4. In Azure Cloud Shell (portal CLI), clone your project repo (you only need the script) and run `sh devops/docker-compose-dev-azure/azure-deploy.sh .` — the verified shipped script prompts, then runs:

```bash
az group create --name nwsample_rg --location "westus"
az appservice plan create --name myAppServicePlan --resource-group nwsample_rg --sku S1 --is-linux
az container create --resource-group nwsample_rg --name nwsample \
  --image apilogicserver/nwsample:latest --dns-name-label nwsample --ports 5656 \
  --environment-variables 'VERBOSE'='True' 'APILOGICPROJECT_CLIENT_URI'='//nwsample.westus.azurecontainer.io:5656'
```

(Script content verified on disk; execution not verified.) It also pre-checks that security is activated (`database/authentication_models.py` present) and aborts with the `add-auth` command if not. Browse `http://<dns-name-label>.westus.azurecontainer.io:5656`; logs via `az container logs --resource-group <rg> --name <name>`; teardown via `az container delete ...` (per docs). Pass the database URI env vars (5.4) to reach the managed DB.

### 6.2 Azure — multi-container (docs: https://apilogicserver.github.io/Docs/DevOps-Containers-Deploy-Multi/)

App container + database container from one compose file. Per docs: push project image and DB image (see `devops/auth-db/`) to Docker Hub, push project to GitHub, then in Azure portal CLI: `git clone <your repo>`, `cd <project>`, then either the script or directly:

```bash
az webapp create --resource-group myResourceGroup --plan myAppServicePlan --name <app> \
  --multicontainer-config-type compose \
  --multicontainer-config-file devops/docker-compose-dev-azure/docker-compose-dev-azure.yml
```

Browse `https://<app>.azurewebsites.net` (first load is slow — container startup). Note: the 17.03.19 project ships `azure-deploy.sh` in that directory; the docs' compose-file name above is from the docs example — check your tree before quoting paths to teammates.

### 6.3 PythonAnywhere (WSGI host; outline from the verified shipped file + provider flow — not live-verified)

The project ships `devops/python-anywhere/python_anywhere_wsgi.py`, whose load-bearing lines (verified; path is stamped at project creation) are:

```python
path = '<absolute path to your project on the host>'   # updated in creation process
if path not in sys.path:
    sys.path.append(path)
from api_logic_server_run import flask_app as application
```

Runbook outline: 1. In a PythonAnywhere console: clone your project, create a virtualenv, `pip install -r requirements.txt`. 2. Web tab: add a manual-config web app, set the virtualenv path. 3. Paste/adapt the shipped WSGI file into the PythonAnywhere WSGI config, fixing `path` to the server-side project path. 4. Reload the web app; your API/Admin App serve at `https://<user>.pythonanywhere.com`. The file itself warns: do not call `app.run()` under WSGI. No dedicated current docs page was found for this target (checked 2026-08-24); treat as community-supported, verify on a throwaway account first.

---

## 7. Ops checklist: pre-flight, start, verify, stop

**Pre-flight**

1. Venv active and correct: `als welcome` prints `Welcome to Genai-Logic 17.03.19` (fails → **apilogicserver-build-and-env**).
2. Port free: `lsof -i :5656` returns nothing (else Section 1.6).
3. DB reachable: SQLite projects — `ls database/db.sqlite` exists; external DBs — confirm the URI (`grep SQLALCHEMY config/config.py`, env overrides Section 5.4) and that the DB host answers.
4. You are at the **project root** (`ls api_logic_server_run.py` succeeds).

**Start**: `python api_logic_server_run.py` (or F5 `Run Project (start server)`, or `als run`). Wait for the boxed `Open your Browser at: http://localhost:5656`.

**Verify** (each probe verified live; expected values shown):

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:5656/            # 302 (→ /admin-app/index.html)
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:5656/api         # 200 (Swagger UI)
curl -s -X POST http://localhost:5656/api/auth/login \
  -H "Content-Type: application/json" -d '{"username":"admin","password":"p"}'
#   → {"access_token":"..."}                    (security on; users → apilogicserver-security-model)
curl -s -H "Authorization: Bearer <token>" "http://localhost:5656/api/Customer/?page%5Blimit%5D=1" \
  -o /dev/null -w "%{http_code}\n"                                         # 200; without header: 401
tail -5 logs/als.log                                                       # file logging alive
```

A 401 `{"msg":"Missing Authorization Header"}` on `/api/<Type>/` is security working, not an outage (verified).

**Stop**

- Foreground terminal: Ctrl+C. VSCode: stop button / Shift+F5.
- Browser/scripted: `http://localhost:5656/stop?msg=reason` — sends SIGINT to the server process. In the current template (verified in basic_demo `api/customize_api.py`) it refuses with `{"success": false, "message": "Shutdown not enabled"}` unless env `APILOGICPROJECT_STOP_OK` is set (the shipped launch configs set it True); the nw_sample copy predates the guard and stops unconditionally — check your `api/customize_api.py`. Dev convenience only; remove or keep guarded in production.
- Containers: `docker stop api_logic_project`, or `docker compose -f <variant yml> down` (5.3).

Anything that changes project behavior along the way (yaml edits, config, dockerfiles) goes through **apilogicserver-change-control** before it ships.

---

## Provenance and maintenance

Volatile facts and how to re-verify each (run from any created project's root, server running where a URL is probed):

- Startup banner text and version line: `python api_logic_server_run.py` and read the first/last 40 console lines (expect "API Logic Project loaded (not WSGI), version: <n>").
- `als run` flags: `als run --help`.
- Run-script flags and precedence: `grep -n "add_argument\|from_prefixed_env" config/config.py api_logic_server_run.py`.
- Port-collision message: start a second server on the same port; or `grep -rn "in use by another program" venv/lib/python*/site-packages/werkzeug/serving.py`.
- Launch config names: `grep '"name"' .vscode/launch.json`.
- URL map: `curl -s -o /dev/null -w "%{http_code} %{redirect_url}\n" http://localhost:5656/` plus `grep -rn "@app.route" api/ ui/admin/admin_loader.py`.
- Admin app serving routes: `grep -n "flask_app.route" ui/admin/admin_loader.py`.
- admin.yaml keys: `head -40 ui/admin/admin.yaml` and `grep -n "settings:\|style_guide:" ui/admin/admin.yaml`.
- Log wiring: `cat config/logging.yml | grep -A4 "file:"` and `ls logs/`.
- Container scripts: `cat devops/docker-image/build_image.sh devops/docker-image/build_image.dockerfile devops/docker-image/env.list` and `ls devops/`.
- Azure commands: `cat devops/docker-compose-dev-azure/azure-deploy.sh` and the two Deploy docs pages below.
- PythonAnywhere WSGI stub: `cat devops/python-anywhere/python_anywhere_wsgi.py`.

Grounded in: https://apilogicserver.github.io/Docs/Execute/, https://apilogicserver.github.io/Docs/IDE-Execute/, https://apilogicserver.github.io/Docs/Admin-Tour/, https://apilogicserver.github.io/Docs/Admin-Customization/, https://apilogicserver.github.io/Docs/Admin-Architecture/, https://apilogicserver.github.io/Docs/DevOps-Automation/, https://apilogicserver.github.io/Docs/DevOps-Containers/, https://apilogicserver.github.io/Docs/DevOps-Containers-Build/, https://apilogicserver.github.io/Docs/DevOps-Containers-Run/, https://apilogicserver.github.io/Docs/DevOps-Containers-Deploy/, https://apilogicserver.github.io/Docs/DevOps-Containers-Deploy-Multi/, https://apilogicserver.github.io/Docs/DevOps-Container-Configuration/, https://apilogicserver.github.io/Docs/DevOps-Docker/, https://apilogicserver.github.io/Docs/Tutorial-Deployment/ and a live Genai-Logic 17.03.19 install (2026-08-23) — banner, URL probes, collision, scripts, and configs verified against a live install and two `als`-created reference projects (basic_demo, nw+) on the same machine, 2026-08-23/24.
