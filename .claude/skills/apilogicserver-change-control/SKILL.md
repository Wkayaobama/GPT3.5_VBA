---
name: apilogicserver-change-control
description: Change-control gate for API Logic Server (Genai-Logic) projects. Classifies every change (schema, logic, API, admin UI, security, config, dependency), names the exact file where it is made, the gate it must pass, and what must never be done. Owns the rebuild runbook — als rebuild-from-database vs rebuild-from-model, Alembic migrations (alembic revision --autogenerate, alembic upgrade head), merging ui/admin/admin-merge.yaml / admin-created.yaml / api/expose_api_models_created.py — plus the non-negotiables, PR/review checklist, and docs-of-record conventions (CLAUDE.md, .github/copilot-instructions.md, docs/requirements, Behave Logic Report). Use when planning, gating, or reviewing ANY change; when adding a column/table or changing the schema; when deciding whether the database or models.py is the source of truth; or on symptoms "rebuild overwrote my customizations", "can I hand-edit models.py", "admin.yaml out of date after schema change", "migration", "schema drift", "stale sums after direct SQL".
---

# API Logic Server Change Control

## Purpose

This skill is the gate every change to an API Logic Server (ALS) project passes through: how a change is classified, where it is legally made, what must pass before it lands, and the rebuild/migration runbook that keeps generated files and hand-written files from destroying each other. It also fixes the project's non-negotiables (with mechanism and detection) and the docs-of-record conventions — both the ones a created project ships and this skill library's own house style. Facts below marked **verified 2026-08-23, Genai-Logic 17.03.19** were confirmed by execution or by reading two live-created projects (`basic_demo`, `nw+` Northwind sample); everything else is marked **per docs, not live-verified**.

## Use this skill when

- You are about to change the database schema (add/drop/rename column, table, FK) and need the safe sequence.
- You are choosing between `als rebuild-from-database` and `als rebuild-from-model`, or deciding the "source of truth".
- A rebuild produced `admin-created.yaml`, `admin-merge.yaml`, or `expose_api_models_created.py` and you must merge them.
- You need to know whether a file may be hand-edited at all (regenerated vs. owned).
- You are running or reviewing an Alembic migration (`alembic revision --autogenerate`, `alembic upgrade head`).
- You are reviewing a PR / a working-tree diff in an ALS project (solo or small team).
- Symptoms: "my edits to models.py disappeared", "rebuild clobbered X", "admin app doesn't show the new column", "sums are stale after I updated rows with a SQL tool", "autogenerate produced a weird migration".
- You are writing a new skill for this library and need the house style (layout, labeling, provenance).

## Do NOT use this skill when

- You need models.py syntax, keys, aliases, test-data seeding, `db.dbml` → **apilogicserver-data-modeling**.
- You need the full CLI flag catalog, `--db-url` shorthands, config.py, env vars → **apilogicserver-cli-and-config**.
- You are writing/altering rules themselves → **apilogicserver-logic-patterns** (engine theory: **declarative-rules-reference**).
- You need the Behave procedure, Logic Report mechanics, evidence format → **apilogicserver-validation-and-qa**.
- You need auth activation, grants, credential rotation → **apilogicserver-security-model**.
- You need the full file-ownership map of the whole project → **apilogicserver-architecture-contract** §4 (this skill covers only the change-relevant subset, with verbatim headers).
- Something already broke and you are triaging → **apilogicserver-debugging-playbook**; for the history of why these rules exist → **apilogicserver-failure-archaeology**.

## 1. Terms (defined once)

| Term | Meaning here |
|---|---|
| ORM | Object-Relational Mapper — SQLAlchemy. Maps tables to the Python classes in `database/models.py`. ALS business rules fire **only** on writes that go through the ORM session. |
| Introspection | Reading the live database catalog to generate `database/models.py` (`als create`, `als rebuild-from-database`). |
| Rebuild | `als rebuild-from-database` / `als rebuild-from-model` — regenerate the *derived* project files from the current schema/model while preserving customization files. |
| Migration | A generated Python script under `database/alembic/versions/` that alters the database schema in place so existing data survives the change. |
| Alembic | SQLAlchemy's migration tool, pre-wired in every project at `database/alembic/` (`env.py` present, `versions/` present — verified 2026-08-23). |
| Merge artifact | A file the rebuild writes *beside* a file it refuses to overwrite (`admin-created.yaml`, `admin-merge.yaml`, `expose_api_models_created.py`) for you to merge consciously, then delete. |
| Gate | A checkable condition that must pass before a change is considered landed. |
| Behave | The Python BDD test runner shipped in every project at `test/api_logic_server_behave/` — executes Gherkin (`.feature`) scenarios against the running server. Mechanics: **apilogicserver-validation-and-qa**. |
| JWT | Signed JSON Web Token returned by `POST /api/auth/login`; sent as `Authorization: Bearer <token>` when security is enabled. |
| Source of truth | Your recorded policy decision: either the database schema drives `models.py` (DB-first) or `models.py` drives the database via Alembic (model-first). Pick one per project; §4.1. |

## 2. Change classification table

Classify every change before touching anything. "Gate" = must pass before the change lands (gates defined in §7.1). Verified 2026-08-23 against the on-disk projects unless noted.

| Change type | Where it is made (exact path) | Gate | NEVER |
|---|---|---|---|
| Schema — DB-first policy | The database itself (DDL via your DB tool), then `als rebuild-from-database` regenerates `database/models.py` | G0 clean git → rebuild → merge artifacts resolved (G4) → server starts (G1) → behave green (G2) → report (G3) | Never hand-sync models.py to match ad-hoc DDL; never leave direct models.py edits in place under this policy (rebuild clobbers them — put them in `database/customize_models.py`) |
| Schema — model-first policy | `database/models.py` (you edit), then Alembic pushes to DB (§4.4), then `als rebuild-from-model` for API/admin | Same chain, plus migration file reviewed, plus drift probe empty (§6 NN-3) | Never `ALTER TABLE` by hand around Alembic; never skip reviewing the autogenerated migration |
| Logic (derivations, constraints, events) | `logic/declare_logic.py` or a new module in `logic/logic_discovery/` (auto-discovered) | G2 + G3: new/changed behave scenario proving the behavior, Logic Report regenerated | Never put logic in API handlers or the admin app; never UPDATE the DB directly to "fix" a derived value |
| Custom API endpoint | `api/customize_api.py` ("Your Code Goes Here") or a new module in `api/api_discovery/` | G1 + a curl smoke of the endpoint + G2 if it writes data | Never edit `api/expose_api_models.py` (regenerated; header says "You typically do not customize this file") |
| Admin UI | `ui/admin/admin.yaml` (also `home.js`) | Admin app loads, changed resource renders; after any rebuild, G4 | Never expect a rebuild to update `admin.yaml` in place — it only writes merge artifacts beside it |
| Security (roles, grants) | `security/declare_security.py`; activation via `als add-auth` | Login smoke + role-scoped GET behaves as declared → procedure in **apilogicserver-security-model** | Never ship sample credentials (`admin`/`p`) to production (§6 NN-5) |
| Config | `config/config.py`, `config/default.env`, or `APILOGICPROJECT_*` env vars (precedence: **apilogicserver-cli-and-config**) | G1 with the new value proven in the startup banner/log | Never fork `config/server_setup.py` beyond its documented override points; never commit real secrets in `default.env` |
| Dependency | `requirements.txt` (verified content: one comment line + `ApiLogicServer`) | Fresh venv install + G1 + G2 (env repair: **apilogicserver-build-and-env**) | Never pin/upgrade the ALS package casually mid-project — the CLI that created the project is version-coupled to its scaffolding |
| Test data | `database/test_data/`, `database/db.sqlite` | G2 (suite depends on seed state) → **apilogicserver-data-modeling** | Never edit seed rows with raw SQL if derived columns are involved (rules do not fire — stale aggregates baked into the seed) |

## 3. Regenerated vs. owned — what a rebuild will and will not touch

The full ownership map lives in **apilogicserver-architecture-contract** §4. Below is the change-control core, with the real in-file evidence (all quotes read from the live projects, verified 2026-08-23, Genai-Logic 17.03.19).

### 3.1 `database/models.py` — REGENERATED (by `rebuild-from-database`)

Header, quoted verbatim from both projects:

```
# Classes describing database for SqlAlchemy ORM, initially created by schema introspection.
#
# Alter this file per your database maintenance policy
#    See https://apilogicserver.github.io/Docs/Project-Rebuild/#rebuilding
```

"Per your database maintenance policy" is the whole game: under a **DB-first** policy this file is disposable output and direct edits are lost on the next `rebuild-from-database`; under a **model-first** policy this file is the source of truth and `rebuild-from-model` does not regenerate it. Decide the policy once, record it (§8), and route edits accordingly.

### 3.2 `database/customize_models.py` — YOURS, survives regeneration

Docstring quoted verbatim (verified in both projects):

```
If you wish to drive models from the database schema,
you can use this file to customize your schema (add relationships, derived attributes),
and preserve customizations over iterations (regenerations of models.py).
```

Wiring (verified by reading `config/server_setup.py`): at startup the server does `import database.models` → `from database import customize_models` → `activate_logicbank(...)` → `expose_api_models.expose_models(...)`. So classes/attributes added here are in place before the API is exposed. It also runs `database/database_discovery/` auto-discovery. Under DB-first policy, **all** model customizations (extra relationships, virtual attributes, aliases you cannot lose) go here, not in `models.py`. Details: **apilogicserver-data-modeling**.

### 3.3 `api/expose_api_models.py` — REGENERATED, and largely self-updating

Docstring quoted verbatim: "You typically do not customize this file — See https://apilogicserver.github.io/Docs/Sample-Basic-Demo/#api-customization-standard".

Verified nuance that shrinks your merge burden: `expose_models()` enumerates model classes dynamically (`inspect.getmembers(database.models)` over `SAFRSBaseX` subclasses), so a new table that reaches `models.py` gets a JSON:API endpoint at next startup with **no edit to this file**. Per docs (Database-Changes), a rebuild still writes `api/expose_api_models_created.py` "created with new `database/models.py` classes" as a merge artifact — review, merge if you had customized (you typically have not), then delete. Your endpoint code lives in `api/customize_api.py`, whose own comment explains the design (quoted verbatim): "separate from expose_api_models.py, to simplify merge if project recreated".

### 3.4 `ui/admin/admin.yaml` — NEVER overwritten; merge artifacts instead

Verified: `admin.yaml` carries **no warning header** (it starts directly with `about:` / `version:` keys) — the protection is behavioral, not in-file, so nothing in the file itself warns you. Per docs (Database-Changes, exact names): `ui/admin/admin.yaml` is "never overwritten"; a rebuild writes

- `ui/admin/admin-created.yaml` — a fresh admin model built only from the new `models.py`, and
- `ui/admin/admin-merge.yaml` — per docs, "the merge of `ui/admin/admin.yaml` and new `database/models.py` classes".

Docs instruction: "Review the altered files, edit (if required), and merge, or copy them over the original files." Verified: neither artifact exists in a freshly created project — if you see them, a rebuild ran and G4 (§7.1) is open until they are merged into `admin.yaml` and deleted.

### 3.5 `customizations/` and `iteration/` — CLI staging, not runtime

Present in `basic_demo` after `als add-cust` (flags verified from `--help`: `--project-name`, `--api-name`). What add-cust actually does (verified by byte-comparison, 2026-08-23):

- `customizations/` holds the sample's prepared customization set (`logic/declare_logic.py`, `logic/logic_discovery/*`, `security/declare_security.py`, `ui/admin/admin.yaml`, `database/models.py`, `config/default.env`, …). After `add-cust`, each staged file is **identical** to its live counterpart — the command copies the staged tree over the project, and the directory remains as a record.
- `iteration/` is a second staged set for the demo's schema-change iteration (new `database/db.sqlite`, `ui/admin/admin.yaml`, `api/api_discovery/order_b2b.py`, `integration/row_dict_maps/*`, `logic/declare_logic.py`) and is **not applied** by the first `add-cust` (verified: live `declare_logic.py` differs; `order_b2b.py` absent from live `api/api_discovery/`).

Change-control stance: these directories are demo tooling. Never edit project behavior inside them (nothing reads them at runtime), and expect `add-cust`-style application to **overwrite** live files wholesale — run it only on a clean git tree.

### 3.6 Quick clobber table

| File | On `rebuild-from-database` | On `rebuild-from-model` | Verification |
|---|---|---|---|
| `database/models.py` | regenerated from schema | preserved (it is the source) | per docs; header verified |
| `database/customize_models.py` | preserved | preserved | per docs; import wiring verified |
| `api/expose_api_models.py` | merge artifact `expose_api_models_created.py` written beside it | same | per docs, not live-verified |
| `api/customize_api.py`, `api/api_discovery/` your modules | preserved | preserved | per docs ("preserving customizations") |
| `ui/admin/admin.yaml` | never overwritten; `admin-created.yaml` + `admin-merge.yaml` written | same | per docs; pre-rebuild absence verified |
| `logic/`, `security/`, `test/`, `devops/`, `docs/` | preserved | preserved | per docs |
| The database itself | already changed by you (it is the source) | changed by you via Alembic (§4.4) | verified project runbook |

## 4. The rebuild runbook

### 4.1 Choose the source of truth (once, recorded)

| Policy | Pick when | Change flow | Command |
|---|---|---|---|
| DB-first ("the schema is the source of truth" — docs) | DBAs own the schema; DB tools/DDL scripts drive change | Change DB → rebuild project | `als rebuild-from-database` |
| Model-first ("model is the source of truth" — docs) | The repo owns the schema; you want migrations under review | Edit `models.py` → Alembic migrates DB → rebuild API/admin | `als rebuild-from-model` |

Per docs (Database-Changes): `rebuild-from-database` "rebuilds the files shown in blue and purple"; `rebuild-from-model` "rebuilds the files shown in blue" — i.e., the model-first rebuild regenerates the API/admin derivatives but not `models.py` itself; the DB-first rebuild regenerates `models.py` too. §3.6 is that diagram as a table.

### 4.2 `als rebuild-from-database` (flags verified from `--help`, 2026-08-23, Genai-Logic 17.03.19)

```bash
als rebuild-from-database --project-name=<project-dir> --db-url=<sqlalchemy-url>
```

Options verified present in `--help`: `--project-name`, `--db-url`, `--api-name`, `--id-column-alias`, `--from-git`, `--run`, `--open-with`, `--not-exposed`, `--admin-app/--no-admin-app`, `--flask-appbuilder/--noflask-appbuilder`, `--react-admin/--no-react-admin`, `--quote`, `--favorites`, `--non-favorites`, `--use-model`, `--host`, `--port`, `--swagger-host`, `--extended-builder`, `--infer-primary-key/--no-infer-primary-key`. Note `--quote` and `--id-column-alias` exist here but not on `rebuild-from-model`. Some help strings are garbled copy-paste (e.g. `--not-exposed` shows "Creates ui/react app") — flag semantics and the help-text caveat are owned by **apilogicserver-cli-and-config** §4.4. Both `--db-url` (help spelling) and `--db_url` (docs spelling) are accepted — the underscore form was used successfully in the verified create pass. Docs example (Project-Rebuild): `ApiLogicServer rebuild-from-database --db_url=sqlite:///basic_demo/database/db.sqlite`. Rebuild *execution* was not run in this verification pass — treat runtime behavior as per docs, not live-verified.

### 4.3 `als rebuild-from-model` (flags verified from `--help`, 2026-08-23)

```bash
als rebuild-from-model --project-name=<project-dir> --db-url=<sqlalchemy-url>
```

Help description, verbatim: "Updates database, api, and ui from changed models." Same option list as 4.2 minus `--quote` and `--id-column-alias`. The project's own Alembic runbook (§4.4) states the division of labor: Alembic pushes `models.py` to the database; then "To update your admin app, run `rebuild-from-model`" (quoted from `database/alembic/readme_alembic.md`, verified on disk).

### 4.4 The Alembic flow (model-first) — exact commands

Every project ships `database/alembic/` with `env.py`, `versions/`, `alembic.ini` (one level up at `database/alembic.ini`), a runbook `readme_alembic.md`, and an automation script `alembic_run.py` — all verified on disk 2026-08-23. `env.py` sets `target_metadata = Base.metadata` imported from `database.models` (verified), so **autogenerate diffs your edited `models.py` against the live DB** — which is why drift (NN-3) poisons it. `APILOGICPROJECT_NO_FLASK=True` is required so importing models outside the running server works (verified: `models.py` switches its base class on that env var; `alembic_run.py` sets it programmatically).

**Automatic** (verified from the shipped script's source; not executed in this pass):

```bash
python database/alembic/alembic_run.py [--non-interactive]
```

What it does, in order (read from `alembic_run.py`): cd to `database/`; set `APILOGICPROJECT_NO_FLASK=True`; `alembic upgrade head` (bring DB to current baseline); `alembic revision --autogenerate -m "<your message>"`; patch the new migration's `downgrade()` to a bare `return`; prompt you to review the migration file; `alembic upgrade head` again; then print "Consider updating ui/admin/admin.yaml to reflect schema changes." **Implication of the downgrade patch: there is no automated rollback — rollback is restore-from-backup or roll-forward.** Review the migration before the final upgrade; that prompt is your gate.

**Manual** (quoted from `database/alembic/readme_alembic.md`, verified on disk; matches docs Database-Changes "Autogenerate"):

```bash
cd database
export APILOGICPROJECT_NO_FLASK=True
alembic revision --autogenerate -m "Added Tables and Columns"
# Edit the revision file to signify your understanding
alembic upgrade head
unset APILOGICPROJECT_NO_FLASK
```

The `cd database` matters: `alembic.ini` lives there. Docs also document a fully manual variant (`alembic revision -m "my revision"`, hand-edit `database/alembic/versions/xxx_my_revision.py`, `alembic upgrade head`) for changes autogenerate cannot infer (renames, data backfills) — per docs, not live-verified.

### 4.5 AI-assisted variant

Per docs (Database-Changes, "Use AI Assistant", quoted): "You can also use your AI assistant to add columns, tables, and relationships. It will choreograph changes to database models, and use alembic to for the database" (sic). The gates in this skill still apply unchanged to AI-made edits — see **apilogicserver-genai-development** for guardrails.

## 5. Worked end-to-end: one schema change (model-first)

Scenario: add a column `Product.carbon_neutral` (Boolean). Numbered gates in parentheses refer to §7.1. Commands are project-root-relative; venv active (**apilogicserver-build-and-env**).

1. **Baseline (G0).** Project under git, working tree clean, on a branch. Verified fact: `als create` does **not** `git init` (no `.git/` in either created project) but ships a ready `.gitignore` (excludes `venv/`, `logs/`, `__pycache__`, `test/api_logic_server_behave/scenario_logic_logs/`, …). If this is the first change: initialize git now, commit the pristine project as the baseline commit.
2. **Drift probe (NN-3 detection).** `cd database && APILOGICPROJECT_NO_FLASK=True alembic revision --autogenerate -m "probe"` — the generated migration must be empty (no ops). Empty: delete the probe file and proceed. Non-empty: someone changed schema or models out of band; stop and reconcile first.
3. **Edit `database/models.py`.** Add `carbon_neutral = Column(Boolean)` to `Product`. Model syntax and key rules: **apilogicserver-data-modeling**.
4. **Migrate.** `python database/alembic/alembic_run.py` — enter a real message; **read the generated file under `database/alembic/versions/` at the review prompt** and confirm `upgrade()` contains exactly your intended op (one `add_column`) before letting it apply.
5. **Rebuild the derivatives.** `als rebuild-from-model --project-name=<project-dir> --db-url=<url>` (per docs, not live-verified as an execution). Expect merge artifacts to appear (§3.4).
6. **Merge the admin app (G4).** `diff ui/admin/admin.yaml ui/admin/admin-merge.yaml` — adopt the new attribute stanza into `admin.yaml` (or copy `admin-merge.yaml` over it if you accept the whole merge), then **delete** `admin-created.yaml` and `admin-merge.yaml`. Review `api/expose_api_models_created.py` the same way (usually: delete unchanged — §3.3), and confirm no stray `*_created.*`/`*-created.*`/`*-merge.*` remain in the tree.
7. **Test data.** If the column needs seed values, update `database/test_data/` / reseed — **apilogicserver-data-modeling**.
8. **Logic.** If the column carries meaning (derived, validated, or feeding a rollup), declare the rule now — **apilogicserver-logic-patterns**. House scan (from the project's shipped AI instructions): every `total_*/*_count`-shaped column must have a matching `Rule.sum`/`Rule.count`, or it sits silently at its default.
9. **Start and smoke (G1).** `python api_logic_server_run.py` — expect the banner "API Logic Project (name: …) starting" and "Explore data and API at … http://localhost:5656" (verified). Then confirm the attribute is live (login first if security is enabled — credentials flow in **apilogicserver-cli-and-config** §4.7):
   `curl -s "http://localhost:5656/api/Product/?page%5Blimit%5D=1" -H "Authorization: Bearer <JWT>"` → response attributes include `carbon_neutral`.
10. **Behave evidence (G2).** Add/extend a scenario covering the new behavior, then with the server still running:
    `cd test/api_logic_server_behave && python behave_run.py --outfile=logs/behave.log` — expect all features/scenarios passed, 0 failed (verified working suite: 7 features / 26 scenarios / 83 steps in the Northwind sample). Procedure details: **apilogicserver-validation-and-qa**.
11. **Logic Report (G3).** `python behave_logic_report.py run` (same directory) → regenerates `reports/Behave Logic Report.md` (verified artifact) — commit it; it is the behavior doc-of-record.
12. **Commit discipline (G5).** Two commits: first the mechanical output (`regen: rebuild-from-model + migration for Product.carbon_neutral` — migration file, regenerated files, merged `admin.yaml`, `db.sqlite`), then the hand work (`feat: carbon_neutral logic + scenario` — logic module, feature file, report). Push; PR checklist §7.2.

**DB-first variant** (same gates, steps 2–5 replaced): change the schema with your DB tool → `als rebuild-from-database --project-name=<project-dir> --db-url=<url>` → `models.py` is regenerated (any direct edits to it are gone — customizations must already live in `database/customize_models.py`, §3.2) → continue at step 6. No Alembic migration exists in this flow; the DDL you ran is the record — keep it as a script under `devops/` or `docs/`.

## 6. Non-negotiables (owner-ratified, docs-grounded)

Each: the rule; WHY (mechanism); DETECT (checkable); history pointer. NN-1 additionally carries its narrow, written-down WAIVER — the only sanctioned exceptions in this library.

**NN-1 — Never write to the database around the ORM.**
WHY: rules attach to the SQLAlchemy session's flush events (`before_flush`); a `sqlite3`/psql/DBeaver UPDATE, raw `engine.execute`, or bulk SQL bypasses the session, so derivations, constraints, and events **silently do not fire** — stored aggregates go stale, invalid rows persist, no error is raised anywhere. Mechanism detail: **declarative-rules-reference**; invariant statement: **apilogicserver-architecture-contract** §5.
DETECT: recompute one aggregate against its children and compare to the stored value — e.g. for the verified basic_demo rules, `Customer.balance` must equal the sum of its unshipped orders' `amount_total`; a mismatch is the fingerprint of an around-the-ORM write. Symptom keyword: "stale sums".
HISTORY: **apilogicserver-failure-archaeology** (silent-corruption incidents); triage: **apilogicserver-debugging-playbook**.
WAIVER (narrow — the only two sanctioned around-the-ORM writes; both still pass these gates and land in the change record):
(a) **rule-free databases** — the auth DB (`authentication_db.sqlite`) has no rules attached, so there is nothing to bypass; sqlite3 INSERTs into `User`/`UserRole` are the documented user-admin procedure (**apilogicserver-security-model** §5.2) and remain a gated security change.
(b) **one-time initialization of a NEWLY added aggregate column, before its rule owns live traffic** — the engine maintains aggregates by adjustment from a correct starting value, and the docs prescribe a backfill UPDATE for retrofits (**apilogicserver-data-modeling** §4 item 5). Run the backfill before cutover, prove it with the DETECT recompute above, and keep the SQL in the change record.
Everything else stays forbidden — including seed-row edits where derived columns are involved (§2) and any "quick fix" UPDATE on rule-governed tables.

**NN-2 — Never hand-edit regenerated files outside the recorded policy.**
WHY: `rebuild-from-database` rewrites `database/models.py` wholesale; edits made there under a DB-first policy are destroyed without warning (the file's own header, §3.1, delegates this to "your database maintenance policy" — so the policy must exist and be written down, §8). `api/expose_api_models.py` says "You typically do not customize this file"; endpoint code belongs in `api/customize_api.py`, kept "separate … to simplify merge if project recreated" (its own comment).
DETECT: in review, any diff hunk touching `database/models.py` (under DB-first) or `api/expose_api_models.py` inside a hand-work commit is a violation; sanctioned homes are `database/customize_models.py` and `api/customize_api.py`/`api/api_discovery/`.
HISTORY: **apilogicserver-failure-archaeology**; ownership map: **apilogicserver-architecture-contract** §4.

**NN-3 — Schema changes go only through the rebuild flow.**
WHY: Alembic autogenerate diffs `models.py` metadata against the live DB (verified `env.py`: `target_metadata = Base.metadata` from `database.models`). An ad-hoc `ALTER TABLE` plus hand-synced models leaves the two representations agreeing with each other but not with migration history — the next autogenerate emits wrong ops (re-adds, drops), and teammates' databases diverge irreparably.
DETECT: the drift probe (§5 step 2): an autogenerate on a supposedly clean tree must produce an empty migration. Run it before every schema change and in review when a schema PR looks suspicious. Delete the probe file afterward.
HISTORY: **apilogicserver-failure-archaeology**.

**NN-4 — Every behavior change lands with its Behave evidence.**
WHY: rules are the system's requirements; the Behave suite plus the regenerated `reports/Behave Logic Report.md` (which embeds per-scenario logic logs) is the only artifact proving the rule chain still does what the requirements say. A logic diff without a scenario diff is an unverified behavior claim.
DETECT: PR shows `logic/` changes but no change under `test/api_logic_server_behave/features/` or to the report → reject unless the description credibly argues "no externally observable behavior change". Run: G2 + G3 commands (§5 steps 10–11).
PROCEDURE: **apilogicserver-validation-and-qa** owns suite mechanics and evidence format.

**NN-5 — Sample credentials never reach production.**
WHY: `als add-auth` wires a demo auth DB whose users include `admin`/`p` (login verified live 2026-08-23: `POST /api/auth/login {"username":"admin","password":"p"}` returns a JWT). Anyone who has read the docs owns any deployment that still accepts it.
DETECT: production smoke test — that same login POST must **fail** against any non-dev deployment. Put it in the deploy checklist (**apilogicserver-operate-and-deploy**).
ROTATION/PROCEDURE: **apilogicserver-security-model**.

## 7. Review discipline (solo or small team)

### 7.1 The standing gates

| Gate | Check | Command (project root) |
|---|---|---|
| G0 baseline | Under git, tree clean before starting (create does not git-init — verified) | `git status` |
| G1 boots clean | Startup banner, no tracebacks | `python api_logic_server_run.py` → "API Logic Project (name: …) starting" (verified banner) |
| G2 behave green | All scenarios pass against the running server | `cd test/api_logic_server_behave && python behave_run.py --outfile=logs/behave.log` (verified) |
| G3 report current | Logic Report regenerated and committed | `python behave_logic_report.py run` → `reports/Behave Logic Report.md` (verified) |
| G4 merges resolved | No merge artifacts left in tree | `ls ui/admin/ api/` — no `admin-created.yaml`, `admin-merge.yaml`, `expose_api_models_created.py` |
| G5 diffs isolated | Regenerated output and hand work in separate commits | `git log --stat` on the branch |

### 7.2 PR checklist (paste into the PR description)

1. [ ] Change classified per §2; source-of-truth policy respected (NN-2, NN-3).
2. [ ] Regenerated-file diffs isolated in a `regen:` commit and explained in one line (what command produced them).
3. [ ] Migration file (if any) reviewed by a human: `upgrade()` ops match intent; noting the shipped `alembic_run.py` no-ops `downgrade()` (verified) — rollback story stated (backup or roll-forward).
4. [ ] Drift probe run and empty (NN-3) for schema PRs.
5. [ ] Logic diffs ship with new/changed scenarios; `Behave Logic Report.md` regenerated (NN-4, G2, G3).
6. [ ] `admin-merge.yaml` resolved consciously — the `admin.yaml` diff is intentional, artifacts deleted (G4).
7. [ ] `database/db.sqlite` note: it is **not** gitignored (verified) and diffs as opaque binary — the reviewable record is the migration file + `docs/db.dbml` (+ updated test data); confirm they moved together in this PR.
8. [ ] No secrets in `config/default.env` / `devops/` diffs; no sample credentials headed for a production target (NN-5).
9. [ ] `customizations/` and `iteration/` untouched by hand (§3.5).
10. [ ] Docs-of-record touched if behavior or schema changed (§8): report committed, `db.dbml` refreshed (regeneration: **apilogicserver-data-modeling**), project decision log updated.

Solo mode: the checklist still runs — review your own branch diff against it before merging to main. The gates are commands, not opinions; they work with zero reviewers.

## 8. Docs-of-record

### 8.1 What a created project ships (verified on disk 2026-08-23, Genai-Logic 17.03.19)

| Artifact | Role | Notes (verified) |
|---|---|---|
| `readme.md` | Human entry point | Ships with a versioned HTML-comment header (observed "Version: 3.15"); demo-named projects get a demo readme, generic projects get this file as-is (per its own header) |
| `CLAUDE.md` | AI entry point | Exactly two import lines in both projects: `@.github/copilot-instructions.md` and `@docs/training/logic_bank_api.md` |
| `.github/copilot-instructions.md` | The AI context doc-of-record ("Context Engineering for GenAI-Logic Projects") | Versioned changelog frontmatter (entries observed through v3.39); maintained with dated, incident-grounded entries |
| `.github/instructions/*.instructions.md` | Task-scoped mandatory pre-reads | Frontmatter convention observed: `description: "Use when: <trigger keywords…>"`, `applyTo: <glob>`, `version`, `lastUpdated` |
| `.github/agents/`, `.github/welcome.md` | Agent definitions, onboarding | Present in both projects |
| `docs/requirements/project_creation_report.md` (+ `project_creation_prompt.md`) | **Creation provenance**: project name, `--db-url`, timestamp, scaffold used | Verified generated at `create` time |
| `docs/db.dbml` | Schema diagram source | Regeneration owned by **apilogicserver-data-modeling** |
| `docs/training/` | AI training corpus (`logic_bank_api.md`, patterns, governance) | Referenced by `CLAUDE.md` |
| `test/api_logic_server_behave/reports/Behave Logic Report.md` | **Behavior evidence-of-record** | Verified generated by `behave_logic_report.py run` |
| `.claude/settings.json` | Tool-permission settings shipped for IDE AI assistants | Verified content: allow `Bash(*)`, `Read`, `Write`, `Edit` |
| `.gitignore` | Ready for your `git init` | Verified: no `.git/` is created by `als create` |

House rule that falls out of this: a change is not done when the code works — it is done when the record moved with it. Schema change → migration + `db.dbml` + creation-report lineage intact; behavior change → scenarios + regenerated Logic Report; policy decision (source of truth, credential rotation) → written into the project (a short `docs/decisions.md` you create, or the readme) so the next engineer — or the next AI session — inherits it. The project's own `copilot-instructions.md` changelog (§ above) is the model: dated entries, each grounded in a real incident.

### 8.2 This library's house style (for every `apilogicserver-*` skill)

- One directory per skill: `.claude/skills/<skill-name>/SKILL.md`. Frontmatter: `name` (exact directory name) + `description` — third person, trigger-rich, "Use when …" phrasing with symptom keywords, ≤1024 chars.
- Body opens: H1 title → `## Purpose` (2–4 sentences) → `## Use this skill when` → `## Do NOT use this skill when` (naming the sibling to use instead). Then numbered `##` sections; tables and numbered checklists over prose; 300–600 dense lines.
- Ground-truth labeling, non-negotiable: facts confirmed by execution or by reading a live install are labeled "verified <date>, Genai-Logic <version>" (once per section, or a Verification column); docs-derived facts are labeled "per docs, not live-verified"; unproven ideas stay labeled open/candidate. Never an invented flag, path, port, or number — verify or omit.
- One home per fact: deep treatment lives in exactly one skill; every other skill cross-references it by skill name in one line.
- Every command copy-pasteable and project-root-relative; no absolute machine paths as load-bearing content; no marketing voice; jargon defined once at first use.
- Last section of every skill, exactly titled `## Provenance and maintenance`: bullet list of volatile facts each with a one-line re-verification command runnable in any project, ending with a "Grounded in:" line naming the doc URLs actually used and the verified install.

## Provenance and maintenance

- Rebuild command names and flag sets: `als rebuild-from-database --help` and `als rebuild-from-model --help` (also cross-check **apilogicserver-cli-and-config** §4.4 for help-text garbling).
- `models.py` regeneration warning header: `head -20 database/models.py`.
- `expose_api_models.py` "typically do not customize" + dynamic exposure: `grep -n "typically do not customize\|getmembers" api/expose_api_models.py`.
- `customize_api.py` merge-isolation comment: `grep -n "simplify merge" api/customize_api.py`.
- `customize_models.py` survival contract and wiring: `sed -n 1,20p database/customize_models.py` and `grep -n customize_models config/server_setup.py`.
- Merge artifact names (`admin-created.yaml`, `admin-merge.yaml`, `expose_api_models_created.py`) and blue/purple split: re-read https://apilogicserver.github.io/Docs/Database-Changes/ ("API and Admin App merge updates"), or run a rebuild in a scratch copy of a project and `ls ui/admin/ api/`.
- Alembic flow and NO_FLASK requirement: `cat database/alembic/readme_alembic.md` and `sed -n 40,60p database/alembic/alembic_run.py`; autogenerate basis: `grep -n target_metadata database/alembic/env.py`.
- Downgrade-is-no-op behavior: `grep -n -A3 "def downgrade" database/alembic/alembic_run.py` and any file under `database/alembic/versions/`.
- `add-cust` staging semantics: after running it in a scratch project, `diff -r customizations/logic logic` (expect identical) and `diff customizations/logic/declare_logic.py iteration/logic/declare_logic.py` (expect different).
- No git init at create / `db.sqlite` tracked: `ls -d .git` (absent in a fresh project) and `grep -c "db.sqlite" .gitignore` (expect 0).
- Behave gate and Logic Report: `cd test/api_logic_server_behave && python behave_run.py --outfile=logs/behave.log && python behave_logic_report.py run` (server running first).
- Sample-credential login (must fail in production): `curl -s -X POST http://<host>:5656/api/auth/login -H "Content-Type: application/json" -d '{"username":"admin","password":"p"}'`.
- Project docs-of-record inventory: `cat CLAUDE.md`, `ls .github/instructions/ docs/requirements/`, `head -5 docs/requirements/project_creation_report.md`.
- Grounded in: https://apilogicserver.github.io/Docs/Project-Rebuild/, https://apilogicserver.github.io/Docs/Database-Changes/, https://apilogicserver.github.io/Docs/IDE-Customize/, https://apilogicserver.github.io/Docs/Project-Builders/, https://apilogicserver.github.io/Docs/Doc-Home/ and a live Genai-Logic 17.03.19 install (2026-08-23) — CLI `--help` output, two live-created projects (basic_demo with add-cust/add-auth, and the Northwind `nw+` sample with its verified Behave run), verified against a live install in the session scratchpad.
