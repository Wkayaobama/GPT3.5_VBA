---
name: apilogicserver-build-and-env
description: >-
  Environment setup and repair for API Logic Server / Genai-Logic development. Use when installing ApiLogicServer, creating or activating a Python venv, choosing a Python version, wiring VS Code to the right interpreter, setting up DB drivers (psycopg2/PostgreSQL, pyodbc/SQL Server/unixODBC, Oracle thick client), using the Docker image, or upgrading the install. Load on symptoms: "command not found: als", "als: command not found", "No module named", pip installed to the wrong Python, "which python" shows system Python, "Port 5656 is in use by another program", "Address already in use", pg_config/psycopg2 build errors, "sql.h not found"/ODBC driver errors, PowerShell "running scripts is disabled on this system", pip SSL/proxy certificate failures, "ApiLogicServer version" printing usage instead of a version, venv_setup/py.py claiming ApiLogicServer is not installed, M1/ARM install questions, or a cloned project that will not run F5.
---

# API Logic Server: Build the Environment, Escape Environment Hell

## Purpose

This skill recreates a working API Logic Server (product name: **Genai-Logic**) development environment from nothing, and repairs broken ones. Environment problems — wrong Python found, venv not activated, port collisions, DB driver builds — are the single largest time-sink in ALS work; every trap here has a detection command and a fix. The canonical install path below was executed end-to-end on a live machine (verified 2026-08-23, Genai-Logic 17.03.19); driver-specific and Windows/Mac/Docker material that could not be executed here is labeled "per docs, not live-verified".

## Use this skill when

- Installing ApiLogicServer for the first time, or on a new machine/container/CI runner.
- Any `command not found`, `ModuleNotFoundError`, wrong-Python, wrong-pip, or venv-activation symptom.
- Choosing/verifying a Python version; multiple Pythons on PATH.
- Port 5656 conflicts at server start.
- Installing DB drivers: PostgreSQL (psycopg2), SQL Server (pyodbc + unixODBC), Oracle (thick client), MySQL.
- Pointing VS Code (or a cloned project) at the correct interpreter; `venv_setup/` scripts.
- Upgrading the ApiLogicServer package; deciding local install vs Docker.

## Do NOT use this skill when

- You need CLI command/flag syntax, `--db-url` forms, or `config/config.py` / `APILOGICPROJECT_*` env-var details → **apilogicserver-cli-and-config**.
- The environment works and a server misbehaves at runtime → **apilogicserver-debugging-playbook**.
- You are starting/operating servers, containers, or deploy targets (beyond "does it start at all") → **apilogicserver-operate-and-deploy**.
- You are changing generated files or upgrading a *project* (not the package) → **apilogicserver-change-control**.
- You want system anatomy or why the stack is shaped this way → **apilogicserver-architecture-contract**.
- Historical "why did env hell happen" context → **apilogicserver-failure-archaeology**.

---

## 1. Name decoder (read once, saves an hour)

Verified 2026-08-23, Genai-Logic 17.03.19:

| Name | What it is |
|---|---|
| **ApiLogicServer** | The PyPI package name. `pip install ApiLogicServer` is correct and current. |
| **Genai-Logic** | The product/brand name printed by the CLI banner: `Welcome to Genai-Logic 17.03.19`. Same software. |
| **`als`** | The canonical short CLI command. Use this in all runbooks. |
| **`ApiLogicServer`, `genai-logic`, `gail`, `gal`, `gl`** | Synonym entry points installed alongside `als` (all six verified working in this install). Do not script against `gail`/`gal`/`gl` — presence has varied across captures; `als` and `ApiLogicServer` are always safe. |
| **17.03.19 vs 17.3.19** | The banner prints `17.03.19`; `pip show ApiLogicServer` prints the PEP-440-normalized `17.3.19`. Same release — do not "fix" one to match the other, and grep for both when checking versions. |

An **entry point** is a small launcher script pip drops into the venv's `bin/` (Windows: `Scripts\`) directory so you can type `als` instead of `python -m ...`.

---

## 2. Supported Python versions

| Source | Claim | Verification |
|---|---|---|
| Installed package metadata (`Requires-Python`) | `>=3.10` — pip refuses to install below this | verified 2026-08-23 in dist-info METADATA |
| Docs Install-Express | "3.10 – 3.13 supported; 3.13 supported as of release 15.0.52" | per docs, not live-verified |
| Docs Install | "requires Python 3.11 or higher" (their recommended floor) | per docs, not live-verified |
| Docs Install-Express, Windows caveat | "Python 3.13 appears to cause install failures due to Pandas" on Windows | per docs, not live-verified |
| This library's reference environment | Python **3.11.15** — everything in these skills ran on it | verified 2026-08-23 |

**Recommendation: use 3.11 or 3.12.** 3.10 is the hard floor; 3.13 is documented-supported but has the Windows/Pandas caveat and different driver wheels (see Section 6).

Check what you have:

```bash
python3 --version        # Mac/Linux (Macs often have no bare `python`)
python --version         # Windows / some Linux
py --list                # Windows py launcher: shows ALL installed Pythons
```

What breaks outside the range: below 3.10, `pip install ApiLogicServer` fails to resolve (pip reports the release "requires a different Python" / finds no compatible version — standard pip behavior for a `Requires-Python` mismatch). Above the tested range, expect wheel gaps in pinned dependencies before ALS itself complains.

Installing Python itself (per docs Tech-Install-Python, not live-verified): Windows — run the python.org installer and **check "Add python.exe to PATH"**; Mac — python.org installer ("install certificates and update your shell") or Homebrew; Linux — distro packages. Mac installs are called out in the docs as "dramatic" — after installing, close and reopen the terminal before trusting `python3 --version`.

---

## 3. Canonical install (verified end-to-end 2026-08-23, Genai-Logic 17.03.19)

A **venv** (virtual environment) is a private, disposable Python installation in a folder; activating it puts that folder's `python`/`pip` first on **PATH** (the shell's program-search list) so installs land there instead of in the system Python. ALS is always installed in a venv — never `sudo pip install`, never `--user`, never the system Python.

### 3.1 Create the venv

```bash
mkdir genai-logic          # any folder name; docs use ~/dev/genai-logic
cd genai-logic
python3 -m venv venv       # Windows: python -m venv venv
```

This creates `venv/` containing `bin/python` (Windows: `Scripts\python.exe`) plus activation scripts. Verified: the created `venv/bin/` ships `activate` (bash/zsh), `activate.csh`, `activate.fish`, and `Activate.ps1`.

### 3.2 Activate — exact command per OS/shell

| OS / shell | Command | Verification |
|---|---|---|
| Linux/Mac — bash or zsh | `source venv/bin/activate` | verified 2026-08-23 |
| Linux/Mac — fish | `source venv/bin/activate.fish` | script present, verified on disk |
| Linux/Mac — csh/tcsh | `source venv/bin/activate.csh` | script present, verified on disk |
| Windows — cmd.exe | `venv\Scripts\activate` | per docs, not live-verified |
| Windows — PowerShell | `venv\Scripts\Activate.ps1` | per docs, not live-verified |

**PowerShell execution-policy trap** (per docs Install-Express, not live-verified): a stock PowerShell refuses `Activate.ps1` with *"running scripts is disabled on this system"*. Fix once, then re-run activation:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

Docs add: "Windows users will need to run the terminal in Admin mode, with scripts enabled."

Success signal on every OS: the prompt gains a `(venv)` prefix. No prefix = not activated = every pip install goes to the wrong Python.

### 3.3 Install

```bash
python -m pip install ApiLogicServer
```

Use `python -m pip` (not bare `pip`) — it guarantees pip runs under the activated interpreter. Verified 2026-08-23: this installs the package **ApiLogicServer 17.3.19**, banner **Genai-Logic 17.03.19**, plus the full runtime (Flask, SQLAlchemy >=2.0.48, SAFRS >=3.1.7, LogicBank >=1.32.00, Flask-JWT-Extended, behave, gunicorn) and the entry points from Section 1.

### 3.4 Verify

```bash
als welcome     # prints:  Welcome to Genai-Logic 17.03.19   (and exits)
als about       # version + install path + PYTHONPATH + system info
```

Both verified 2026-08-23. **`ApiLogicServer version` is NOT a command in 17.03.19** — it prints the usage/help banner ("Try 'ApiLogicServer --help' for help.") instead of erroring loudly, which reads like success in scripts. Use `als welcome` for a version probe.

From here: `als create --project-name=basic_demo --db-url=basic_demo` creates a project (see **apilogicserver-cli-and-config** for the command catalog and `--db-url` forms; **apilogicserver-data-modeling** for what gets generated). `als start` opens the **Manager** — a workspace folder the CLI builds with sample projects and IDE config (options verified via `als start --help`: `--clean/--no-clean`, `--samples/--no-samples`, `--open-with`, `--open-manager`).

### 3.5 What the install bundles (drivers)

Verified 2026-08-23 by reading the installed package's dependency markers and `site-packages`:

| Database | Driver | Bundled? |
|---|---|---|
| SQLite | stdlib `sqlite3` | yes — zero setup; all samples use it |
| PostgreSQL | `psycopg2-binary` (>=2.9.5; installed 2.9.12) | yes, for Python < 3.13; Python >= 3.13 gets `psycopg[binary]` >= 3.1.0 instead |
| MySQL | `PyMySQL` (pure Python; installed 1.2.0) | yes — no C build ever |
| Oracle | `oracledb` 2.1.2 thin driver | yes on x86_64, **skipped on aarch64/ARM64** (dependency marker `platform_machine != "aarch64" and != "ARM64"`) |
| SQL Server | `pyodbc` | **no — manual install required** (Section 6.2) |

---

## 4. The 60-second environment self-test

Run these five lines whenever anything smells wrong; they discriminate 90% of environment hell (all verified 2026-08-23):

```bash
which python && which pip      # Windows: where python / where pip
python -c "import sys; print(sys.prefix)"
python --version
als welcome
python -m pip show ApiLogicServer | head -2
```

Healthy answers: `which python` and `which pip` both point inside **your** `venv/bin` (Windows: `venv\Scripts`); `sys.prefix` is the venv folder; version in range; `Welcome to Genai-Logic <version>`; `Name: ApiLogicServer / Version: ...`.

Verified failure signature of a **non-activated shell** on the reference machine: `which python` → `/usr/local/bin/python`, `which pip` → `/usr/bin/pip` — python and pip from *different* installations, neither the venv. Any pip install in that state lands in system site-packages and `als` stays "command not found".

Inside a created project you can also run the shipped diagnostic `python venv_setup/py.py` — but see the trap table first: in 17.03.19 its ALS-version line is a false negative.

---

## 5. Trap table: symptom → cause → fix

Verification column: **V** = verified 2026-08-23 on the live 17.03.19 install; **D** = per docs, not live-verified; **G** = generic platform behavior, not ALS-specific.

| # | Symptom | Cause | Fix | Ver |
|---|---|---|---|---|
| 1 | `als: command not found` right after a "successful" install | venv not activated when pip ran — package went to system Python; or activated now but installed earlier elsewhere | Run the Section 4 self-test. Activate (Section 3.2), reinstall with `python -m pip install ApiLogicServer`. Detect the bad state: `which pip` outside the venv | V |
| 2 | `pip install` succeeds but `python -c "import ..."` fails / server gets `ModuleNotFoundError` | `pip` on PATH belongs to a different Python than `python` (verified real on the reference machine: `/usr/bin/pip` vs `/usr/local/bin/python`) | Always `python -m pip install ...` — never bare `pip` when diagnosing | V |
| 3 | Wrong Python version found; `python` is 2.x or an old 3.x | Multiple installs; PATH order; Mac ships no bare `python`; Windows py launcher picks its own default | Mac/Linux: call `python3.11 -m venv venv` (exact-versioned binary) — the venv then pins it, and `python` *inside* the venv is correct. Windows: `py -3.11 -m venv venv`. List candidates: `py --list` (Win), `ls /usr/local/bin/python*` (Mac/Linux) | V (Linux) / G |
| 4 | `pip install ApiLogicServer` reports no matching distribution / requires a different Python | Python < 3.10 (package `Requires-Python: >=3.10`) | Install 3.11/3.12 (Section 2), rebuild the venv from scratch | V (metadata) / G (pip msg) |
| 5 | PowerShell: "running scripts is disabled on this system" at activation | Default execution policy blocks `Activate.ps1` | `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`, reopen shell, re-activate | D |
| 6 | Windows install fails building Pandas on Python 3.13 | Docs: "Python 3.13 appears to cause install failures due to Pandas" on Windows | Use Python 3.11/3.12 on Windows | D |
| 7 | Server start fails: **"Address already in use — Port 5656 is in use by another program."** | Another server (often your own previous run) owns 5656 | Find it: `lsof -i :5656` (Mac/Linux), `netstat -ano \| findstr 5656` (Win); stop it, or run on another port: `python api_logic_server_run.py --port=5657` (flag verified in shipped `.vscode/launch.json` args) or `als run --port=5657` (verified in `als run --help`). Precedence config < CLI args < `APILOGICPROJECT_*` env vars → **apilogicserver-cli-and-config** | V (message + flags) / G (lsof) |
| 8 | `ApiLogicServer version` prints the usage banner, no version | `version` is not a command in 17.03.19 (older docs/scripts reference it) | `als welcome` (version only) or `als about` (full info) | V |
| 9 | `python venv_setup/py.py` prints `*** ApiLogicServer not installed in this environment ***` although `als welcome` works | 17.03.19 quirk: py.py imports `api_logic_server_cli.api_logic_server`, which fails with `ModuleNotFoundError: No module named 'clone_and_overlay_prototypes'` — a false negative | Trust `als welcome` / `pip show ApiLogicServer`, not py.py's ALS line. py.py's interpreter/sys.path output (`py.py sys-info`) is still accurate | V |
| 10 | psycopg2 build fails: `pg_config executable not found`, missing headers, compiler errors | pip fell back to the **source** distribution (needs PostgreSQL dev headers + C compiler) instead of the prebuilt **binary wheel** | Usually unnecessary: `psycopg2-binary` is bundled with ALS on Python < 3.13 (verified). If building anyway: `pip install psycopg2-binary` (docs' historical pin: `psycopg2-binary==2.9.3` for releases 5.03.33–6.1; included in the build "as of release 6.2"). True source builds need `libpq-dev`+`gcc` (Debian) / `brew install postgresql` (Mac) | V (bundled) / D (rest) |
| 11 | SQL Server: `pyodbc` import/install fails; `sql.h not found`; "Can't open lib 'ODBC Driver 1x for SQL Server'" | pyodbc is NOT bundled; needs unixODBC + Microsoft ODBC driver + pip package | Section 6.2 | V (not bundled) / D (fix) |
| 12 | Oracle connects fail in locked-down networks: `OSError: [WinError 10038] An operation was attempted on something that is not a socket`, or `Service "xxx" is not registered with the listener` | oracledb **thin** mode blocked; **thick** mode (Oracle Instant Client libraries) required | Section 6.3 | D |
| 13 | Oracle driver simply absent on ARM (Apple Silicon container, Graviton) | Dependency marker excludes `oracledb` on `aarch64`/`ARM64` | Expect to solve Oracle-on-ARM separately (thick client / emulation); not preinstalled | V (marker) |
| 14 | pip fails with SSL: CERTIFICATE_VERIFY_FAILED / ProxyError / 407 behind a corporate proxy | TLS-intercepting proxy; pip doesn't trust the corporate CA | Point pip at the corporate CA bundle: `pip install --cert /path/to/corp-ca.pem ApiLogicServer` or `export PIP_CERT=/path/to/corp-ca.pem`; proxy: `export HTTPS_PROXY=http://proxy:port` or `pip --proxy`. Get the CA file from IT. Never disable verification | G |
| 15 | Mac SSL errors from Python itself right after a python.org install | Certificates step skipped | Run `Install Certificates.command` in `/Applications/Python 3.x/` (docs: "install certificates and update your shell") | D |
| 16 | `gail`/`gal`/`gl` not found in a script | Synonym entry points present in this verified install, but presence has varied across captures | Script against `als` (or `ApiLogicServer`) only | V |
| 17 | `python api_logic_server_run.py` uses the wrong interpreter even though a venv exists | Bare `python` resolved via PATH, not the venv (shell not activated; or IDE terminal opened before interpreter selection) | Activate first, or invoke explicitly: `venv/bin/python api_logic_server_run.py`. Docs note multiple-Python machines "may require explicit `python3 api_logic_server_run.py`" | V / D |
| 18 | F5 in VS Code fails on a git-cloned project; interpreter is system Python | `.vscode/settings.json` (which stores the interpreter path) is **gitignored** — verified in the shipped `.gitignore` (`venv/` and `.vscode/settings.json`) — so clones arrive without it | Section 7.2 | V |
| 19 | Running the venv's python by absolute path, but subprocess/CLI lookups still miss | Absolute-path invocation does not put `venv/bin` on PATH; anything the process shells out to resolves against the old PATH (verified: this is exactly why trap 9's diagnostic misleads) | Activate the venv for interactive work; absolute paths only for single self-contained commands | V |

Deeper runtime triage (logic log reading, constraint mysteries) → **apilogicserver-debugging-playbook**.

---

## 6. Database driver specifics

`--db-url` syntax for each database lives in **apilogicserver-cli-and-config**; this section is only about making the driver importable. SQLAlchemy is the **ORM** (object-relational mapper — Python classes ↔ tables) underneath ALS; a "driver" is the C/Python package SQLAlchemy uses to speak each database's wire protocol.

### 6.1 PostgreSQL — psycopg2 (mostly a non-problem now)

- Verified 2026-08-23: `psycopg2-binary` 2.9.12 is installed automatically with ApiLogicServer on Python < 3.13; on Python >= 3.13 the dependency switches to `psycopg[binary]>=3.1.0` (dist-info markers). **Expect PostgreSQL to work with zero driver setup.**
- The binary-vs-source story (why the docs page exists): `psycopg2-binary` ships a prebuilt wheel; plain `psycopg2` compiles from source and needs `pg_config`, libpq headers, and a compiler — that is where `pg_config executable not found` comes from. Per docs (not live-verified): the driver "is restored into the build of ApiLogicServer" as of release 6.2; only ancient releases (5.03.33–6.1) needed manual `pip install psycopg2-binary==2.9.3`.

### 6.2 SQL Server — pyodbc + unixODBC + MS driver (per docs, not live-verified)

pyodbc is **not** bundled (verified absent from site-packages). **ODBC** is a generic C database API; **unixODBC** is its Linux/Mac driver manager; Microsoft's `msodbcsql17`/`msodbcsql18` is the actual SQL Server driver pyodbc loads.

Linux:

```bash
apt install unixodbc-dev   # headers, fixes "sql.h not found"
pip install pyodbc
```

Mac (install the Microsoft ODBC driver first, per Microsoft's instructions):

```bash
brew install unixodbc      # may be required
pip install pyodbc==5.2.0
```

Docker image needing ODBC Driver **17** (docs give this verbatim for a Debian 11 base — add after the COPY step):

```dockerfile
RUN apt-get update && \
    apt-get install -y curl gnupg apt-transport-https && \
    curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - && \
    curl https://packages.microsoft.com/config/debian/11/prod.list > /etc/apt/sources.list.d/mssql-release.list && \
    apt-get update && \
    ACCEPT_EULA=Y apt-get install -y msodbcsql17 unixodbc-dev gcc g++ python3-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
RUN pip install --upgrade pip && pip install pyodbc==5.2.0
```

Check which ODBC drivers are registered: `odbcinst -d -q`. Docs state Windows pyodbc setup "remains unresolved" — on Windows, prefer the Docker route for SQL Server work. The `--db-url` must name the installed driver version (e.g. ODBC Driver 17 vs 18) → **apilogicserver-cli-and-config**.

### 6.3 Oracle — thin vs thick (per docs, not live-verified)

`oracledb` runs **thin** (pure network protocol, bundled — but not on ARM, trap 13) by default. Some corporate networks require **thick** mode, which loads Oracle's Instant Client C libraries. Symptoms that thick is needed: trap 12's errors.

1. Install Oracle Instant Client per Oracle/python-oracledb instructions for your OS; note the folder (docs example: `/Users/val/Downloads/instantclient_19_16`).
2. Set the ALS switch **before both creating and running** projects:

```bash
export APILOGICSERVER_ORACLE_THICK=/path/to/instantclient_19_16   # Windows: set APILOGICSERVER_ORACLE_THICK=...
```

### 6.4 MySQL

`PyMySQL` (pure Python) is bundled — verified installed. No C build, no system packages, ever.

---

## 7. Project-side environment: how a created project finds its venv

`als create` does **not** create a per-project venv. The project *uses* the venv that ran the create (docs call the standard one the "Manager venv"); a thin `requirements.txt` containing just `ApiLogicServer` (verified in both reference projects) can rebuild an equivalent venv anywhere.

### 7.1 What ships in the project (verified 2026-08-23 on disk)

- `.vscode/settings.json` — contains `python.defaultInterpreterPath` as an **absolute path** to the creating venv's `python`, plus `python.terminal.activateEnvironment: true` (VS Code auto-activates the venv in new terminals). Absolute ⇒ machine-specific ⇒ gitignored (verified: `.gitignore` lists `venv/` and `.vscode/settings.json`).
- `.vscode/launch.json` — "Run Project (start server)" config: `"python": "${command:python.interpreterPath}"` (resolves to whatever interpreter the VS Code picker has selected), runs `api_logic_server_run.py` with `--port=5656`.
- `venv_setup/` — `venv.sh`, `venv-linux.sh`, `venv.ps1`, `py.py` (env diagnostic; remember trap 9), `readme_venv.md`, `requirements-no-cli.txt` (pinned libs without the CLI).

### 7.2 VS Code interpreter selection (the one ritual to memorize)

1. Open the project folder in VS Code.
2. Command palette (`Ctrl/⌘+Shift+P`) → **Python: Select Interpreter** → choose the install venv's `venv/bin/python` (Windows: `venv\Scripts\python.exe`).
3. If a stale selection persists (per docs Project-Env): **Python: Clear Workspace Interpreter Setting**, then select again.
4. Open a **new** terminal (activation is applied when a terminal is created, not retroactively) and F5.

Per docs: the picker is the single source of truth; setting `VIRTUAL_ENV`/`PYTHONPATH`/`PATH` by hand does not change VS Code's interpreter.

### 7.3 Cloned/imported projects (no settings.json arrives — trap 18)

Three options, verbatim from the shipped `venv_setup/readme_venv.md` (verified on disk; run from the project root):

```bash
# Option A — project sits inside the Manager folder (../venv exists): just run it
als run --project-name=.          # docs also show: genai-logic run  (output → logs/als.log per docs)

# Option B — symlink the Manager venv (Mac/Linux; reload VS Code window after)
sh venv_setup/venv.sh symlink

# Option C — real local venv, all platforms (creates venv/ + pip install -r requirements.txt)
sh venv_setup/venv.sh go          # Mac/Linux
sh venv_setup/venv-linux.sh go    # Linux variant
.\venv_setup\venv.ps1 go          # Windows PowerShell
```

Then verify with `python venv_setup/py.py` (interpreter and sys.path lines are trustworthy; its ALS-installed line is not — trap 9).

---

## 8. Docker alternative (per docs, not live-verified)

All commands in this section are from the install docs and were not executed here.

```bash
docker run -it --name api_logic_server --rm -p 5656:5656 -p 5002:5002 -v ${PWD}:/localhost apilogicserver/api_logic_server
# ARM (M1/M2/M3) Macs — dedicated image:
#   apilogicserver/api_logic_server_arm
# Upgrade the image:
docker pull apilogicserver/api_logic_server
```

Notes per docs: on Windows use PowerShell (`${PWD}` is not supported in cmd); inside the container, create projects under `/localhost` so they land in your mounted host folder; `als tutorial` or `als create-and-run --project_name=/localhost/ApiLogicProject --db_url=` to smoke-test.

Prefer Docker over a local install when: (a) Windows + SQL Server (pyodbc "unresolved" on Windows per docs — Section 6.2's Dockerfile solves it), (b) you cannot control the machine's Python (locked-down corp laptop, wrong system Python), (c) CI or throwaway evaluation, (d) you want the DB drivers pre-baked. Prefer local venv when: day-to-day development with IDE debugging (F5 + breakpoints in rules is the core ALS workflow), or when Docker's port/volume mapping just adds failure modes. Created projects also ship `devops/docker-image/` and docker-compose variants for containerizing your *project* (verified present on disk) → **apilogicserver-operate-and-deploy**.

---

## 9. Upgrading the install (per docs Install-Upgrade, not live-verified)

Upgrading the **package** is safe and does not touch your projects:

```bash
cd ~/dev/genai-logic          # your install location
. venv/bin/activate           # windows: venv\Scripts\activate
pip install --upgrade ApiLogicServer
als start --clean             # docs: "this does not delete your projects"
```

- Same venv — docs do not require a fresh one. (If a broken upgrade leaves the venv wedged, deleting `venv/` and redoing Section 3 is cheap; docs elsewhere note "It is simpler to re-create a venv than to move/copy one.")
- `--clean` re-overlays the Manager's samples/context files with the new release's content; your project folders are retained (flag verified to exist via `als start --help`).
- Verify after: `als welcome` shows the new version.
- Docs warn: "Recent updates to included libs have broken previous versions of API Logic Server" — i.e., staying old is not the safe option; pins rot.
- **Existing projects** created under an older release keep their generated code until you rebuild them. Any project-level rebuild/upgrade changes behavior — before running `als rebuild-from-database` / `rebuild-from-model` or adopting a new release into a governed project, go through the gates in **apilogicserver-change-control**. Validate afterward per **apilogicserver-validation-and-qa**.

---

## Provenance and maintenance

Volatile facts and how to re-verify each (run inside an activated install venv, from a created project's root where a project is implied):

- Package version / banner pair (`17.3.19` / `17.03.19`): `als welcome` and `python -m pip show ApiLogicServer | head -2`
- `ApiLogicServer version` still not a command: `ApiLogicServer version` (expect usage banner, no version line)
- Entry points actually installed (`als`, `ApiLogicServer`, `genai-logic`, `gail`, `gal`, `gl`): `ls $(python -c "import sys;print(sys.prefix)")/bin | grep -ixE "apilogicserver|als|gail|gal|gl|genai-logic"` (anchored `-x` on purpose — an unanchored pattern with no `gl` alternative cannot match the two-character `gl`)
- Python floor: `python -c "import importlib.metadata as m; print(m.metadata('ApiLogicServer')['Requires-Python'])"` (expect `>=3.10`)
- Bundled drivers and platform markers (psycopg2-binary/psycopg, PyMySQL, oracledb-not-on-ARM, no pyodbc): `python -m pip show psycopg2-binary pymysql oracledb pyodbc`
- Port-collision message text: start a second server on 5656 (expect "Port 5656 is in use by another program."); port flags: `als run --help`
- py.py false negative (trap 9): `python venv_setup/py.py` vs `als welcome`; root cause: `python -c "import api_logic_server_cli.api_logic_server"` (expect `ModuleNotFoundError: clone_and_overlay_prototypes` while broken)
- Gitignored interpreter config (trap 18): `grep -n "settings.json" .gitignore` and `grep -n defaultInterpreterPath .vscode/settings.json`
- `venv_setup/` script inventory and options: `ls venv_setup/` and `cat venv_setup/readme_venv.md`
- Project requirements are just the meta-package: `cat requirements.txt` (expect `ApiLogicServer`)
- Upgrade flow / `--clean` semantics: `als start --help` and https://apilogicserver.github.io/Docs/Install-Upgrade/
- Docker image names/tags: https://apilogicserver.github.io/Docs/Install-Express/ (and Docker Hub for `apilogicserver/api_logic_server`, `..._arm`)

Grounded in: https://apilogicserver.github.io/Docs/Install-Express/, https://apilogicserver.github.io/Docs/Install/, https://apilogicserver.github.io/Docs/Install-Upgrade/, https://apilogicserver.github.io/Docs/Tech-Install-Python/, https://apilogicserver.github.io/Docs/Install-psycopg2/, https://apilogicserver.github.io/Docs/Install-pyodbc/, https://apilogicserver.github.io/Docs/Install-oracle-thick/, https://apilogicserver.github.io/Docs/Project-Env/, https://apilogicserver.github.io/Docs/Architecture-venv/, https://apilogicserver.github.io/Docs/Architecture-venv-defaulting/ and a live Genai-Logic 17.03.19 install (2026-08-23) — verified against a live install and two `als`-created reference projects on the same machine.
