---
name: apilogicserver-debugging-playbook
description: >-
  Symptom-to-fix triage for API Logic Server (Genai-Logic) projects, with shipped tested diagnostic scripts (probe_health.sh, extract_logic_log.sh, list_discovered_logic.sh), a verified logic-log reading guide, the VS Code debugger workflow, and the discriminating-experiment method. Use when a server or rule misbehaves and the cause is unknown - symptoms: "Port 5656 is in use by another program", server exits immediately, No module named safrs, 401 Missing Authorization Header, "Wrong username or password", 422 Not enough segments, "my constraint did not fire" (where-clause pruning), rule missing from "..discovered logic", stale sums after direct SQL, console TypeError str object cannot be interpreted as an integer on constraint violations (17.03.19 short_format_exception bug), "Kafka mode: FALLBACK", blank admin app, Swagger Try-it-out 401, "Sorry, row altered by another user", reading Logic Phase / These Rules Fired output, [old-->] notation, raising logic-log verbosity.
---

# API Logic Server Debugging Playbook

## Purpose

This skill turns an unknown API Logic Server (ALS / Genai-Logic) failure into a named cause and a fix. It ships a triage table keyed on exact verified symptoms, deep-dives for the failures that cost real hours (where-clause pruning, discovery misses, the 17.03.19 logging bug), a guide to reading the logic log, the debugger workflow, and three tested diagnostic scripts. Facts marked **verified 2026-08-23/24, Genai-Logic 17.03.19** were confirmed by live execution or by reading the installed projects/engine source; everything else is marked **per docs, not live-verified**.

## Use this skill when

- A server will not start, exits immediately, or answers with unexpected 401/422/400 errors.
- A rule "did not fire", a sum "is stale", or logic behaves differently than you predicted.
- You need to read or capture the logic log, raise its verbosity, or step through rules in a debugger.
- You want a scripted health probe, logic-log extractor, or discovery-listing before/after a change.

## Do NOT use this skill when

- You are **writing or changing** rules → `apilogicserver-logic-patterns` (signatures, safe add-a-rule procedure).
- You want the **theory** of watch/react/chain, pruning, adjustment → `declarative-rules-reference`.
- The failure is **install/venv/driver** trouble → `apilogicserver-build-and-env`.
- You are choosing CLI flags, ports, env vars → `apilogicserver-cli-and-config`; running/deploying → `apilogicserver-operate-and-deploy`.
- You need **API payload shapes** or Swagger usage → `apilogicserver-api-contract`; auth/roles → `apilogicserver-security-model`.
- You are proving a change is done (Behave suite, Logic Report, evidence bar) → `apilogicserver-validation-and-qa`.
- Your fix requires editing generated files or rebuilding → finish through `apilogicserver-change-control` gates.

Jargon used below, defined once: **JSON:API** = the REST response convention ALS serves (`{"data": ..., "errors": [...]}`); **JWT** = the signed login token sent as `Authorization: Bearer <token>`; **ORM** = SQLAlchemy, mapping tables to Python classes; **flush** = the ORM step that writes pending changes to SQL (rules run in `before_flush`); **derivation** = a rule-computed column (sum/count/formula/copy); **constraint** = a rule that rejects a transaction with a message; **venv** = the project's private Python environment; **logic log** = LogicBank's per-transaction rule trace; **optimistic locking** = update conflict detection via the `S_CheckSum` attribute.

## Method: the discriminating experiment

Debug by experiments that discriminate between hypotheses, one variable per probe, and **predict the number first**. Write down "if hypothesis A, this curl returns X; if B, it returns Y", then run it. A probe whose outcome you cannot predict for each hypothesis is not a test, it is a fishing trip. The logic log makes this cheap: every write prints old→new values for every touched row, so most predictions are checkable to the digit. Three worked examples are in "Worked discriminating experiments" below; the where-clause story in Deep-dive D1 is the canonical full walkthrough.

## The triage table

All "verified" rows: verified 2026-08-23/24, Genai-Logic 17.03.19. `curl` always with `--noproxy '*'` (bypass any corp proxy for localhost). Run first-check commands from the project root. `scripts/` = this skill's scripts directory (`.claude/skills/apilogicserver-debugging-playbook/scripts/` in the repo hosting this library) — see "Shipped diagnostic scripts".

| # | Symptom (exact where verified) | First check (one command) | Likely cause | Fix | Deep dive / owner | Verification |
|---|---|---|---|---|---|---|
| 1 | Startup prints `Address already in use` then `Port 5656 is in use by another program. Either identify and stop that program, or start the server with a different port.` | `curl -s --noproxy '*' http://localhost:5656/api -o /dev/null -w '%{http_code}\n'` (200 = something already serves 5656) | Another server instance (often a forgotten earlier run) owns the port | Stop the other instance, or start on another port: `python api_logic_server_run.py --port=5657` | `apilogicserver-operate-and-deploy` | verified (message verbatim from captured startup log) |
| 2 | Server exits immediately with `ModuleNotFoundError: No module named 'safrs'` (or 'flask', 'logic_bank') | `which python` (must resolve inside the project/scratch venv, not `/usr/bin`) | venv not activated — system Python lacks ALS dependencies | `source venv/bin/activate` (Windows: `venv\Scripts\activate`), rerun | `apilogicserver-build-and-env` | verified (reproduced with system python3) |
| 3 | `python3: can't open file '.../api_logic_server_run.py': [Errno 2] No such file or directory` | `ls api_logic_server_run.py` | Wrong working directory — you are not at the project root | `cd <project>` then `python api_logic_server_run.py` | `apilogicserver-operate-and-deploy` | verified (reproduced) |
| 4 | API GET returns HTTP 401 `{"msg":"Missing Authorization Header"}` | `curl -s --noproxy '*' -X POST http://localhost:5656/api/auth/login -H 'Content-Type: application/json' -d '{"username":"admin","password":"p"}'` | Security is on and no `Authorization: Bearer <token>` header was sent | Login (returns `{"access_token": "..."}`), resend with `-H "Authorization: Bearer $TOKEN"`; or run `scripts/probe_health.sh` | `apilogicserver-security-model` | verified (401 + body live) |
| 5 | Login itself fails: HTTP 401 `"Wrong username or password"` | Same login curl as row 4, watch the body | Bad credentials (sample auth DB user is `admin`/`p`), or auth DB not the one you think | Use a known user; check `security/declare_security.py` and the auth DB | `apilogicserver-security-model` | verified (reproduced live) |
| 6 | HTTP 422 `{"msg":"Not enough segments"}` | Echo the header you sent — is the token empty/garbled? | Malformed JWT (empty var, missing `Bearer `, truncated paste) | Re-login, resend `Authorization: Bearer <full token>` | `apilogicserver-security-model` | verified (reproduced live) |
| 7 | "My constraint did not fire" — a write you expected rejected returns 200 | `scripts/extract_logic_log.sh logs/als.log` — find the transaction; is the parent adjustment row present? | Aggregate `where=` clause excludes the row's parent chain (pruning), so the watched value never changed | Usually not a bug: the rule's qualification is doing its job. If the qualification is wrong, fix the rule via `apilogicserver-logic-patterns` + change-control | **D1** (full story); theory: `declarative-rules-reference` | verified (full experiment below) |
| 8 | Rule has no effect and never appears in the log | `grep -a "discovered logic" logs/als.log \| tail -1` | File not under `logic/logic_discovery/`, wrong extension, or missing top-level `declare_logic()` | Place file in `logic/logic_discovery/`, define `declare_logic()`, restart; verify with `scripts/list_discovered_logic.sh` | **D2** | verified (discovery list + engine code read) |
| 9 | Sums/counts look stale; DB values disagree with rule math | `scripts/extract_logic_log.sh logs/als.log` — the suspect write has **no** transaction block | Write bypassed the SQLAlchemy session (raw SQL, external tool, another app) — rules only run in `before_flush` | Route all writes through the API / session (architecture invariant); recompute damaged aggregates via a controlled update | `apilogicserver-architecture-contract`; gates: `apilogicserver-change-control` | invariant verified by design + log evidence |
| 10 | Console shows `--- Logging error ---` ... `TypeError: 'str' object cannot be interpreted as an integer` exactly when a constraint rejects | `grep -n "splitlines" config/server_setup.py` (shows `result.splitlines('\n')` ~line 203) | 17.03.19 bug in `short_format_exception` — logging cosmetics only; the 400 and rollback are correct | Confirm harmless per **D3**; leave engine behavior alone; any local patch goes through change-control | **D3** | verified (bug reproduced + source read) |
| 11 | Startup prints `Kafka mode: FALLBACK — KAFKA_SERVER not configured; running debug endpoint only`; logic prints `[Note: **Kafka not enabled** ]` | `grep -a "Kafka mode" logs/als.log \| tail -1` | No Kafka broker configured — graceful degradation, benign unless you expected Kafka | If Kafka is expected, configure `KAFKA_SERVER` per `apilogicserver-integration-patterns`; else ignore | `apilogicserver-integration-patterns` | verified (both messages captured) |
| 12 | `ImportError`/build errors for `psycopg2`, `pyodbc` (`sql.h not found`), Oracle client | `python -c "import psycopg2"` (or the failing driver) | DB driver not installed / OS prerequisites missing | Driver install recipes in `apilogicserver-build-and-env` | `apilogicserver-build-and-env` | per docs, not live-verified (sqlite-only here) |
| 13 | Admin app blank or misbehaving after changes; API itself healthy | `curl -s --noproxy '*' -o /dev/null -w '%{http_code}\n' http://localhost:5656/admin-app/index.html` (200 = served; blame the browser) | Browser cache serving stale app/security state (per Troubleshooting docs); or `ui/admin/admin.yaml` edit broke the model | Hard-reload / clear cache for localhost; re-check recent `admin.yaml` edits | `apilogicserver-operate-and-deploy` | 200 verified live; cache cause per docs, not live-verified |
| 14 | Swagger "Try it out" returns 401 with security on | Same login curl as row 4 | Swagger calls carry no JWT until you authorize the UI | In Swagger: execute the auth login endpoint, copy `access_token`, click **Authorize**, enter `Bearer <access_token>` | `apilogicserver-api-contract` | per docs, not live-verified (UI flow); 401 body verified |
| 15 | PATCH rejected: `Sorry, row altered by another user - please note changes, cancel and retry` | `grep -rn "altered by another user" api/system/opt_locking/opt_locking.py` | Optimistic-lock `S_CheckSum` mismatch: row changed since you read it — or checksums computed under a different `PYTHONHASHSEED` | Re-read the row, reapply, retry with fresh `S_CheckSum`; keep `PYTHONHASHSEED=0` (launch configs set it) | `apilogicserver-api-contract`; hashseed: `apilogicserver-validation-and-qa` | message verified in project source; flow per docs, not live-verified |
| 16 | `genai*` commands fail immediately (missing API key) | `python3 -c "import os; print(bool(os.getenv('APILOGICSERVER_CHATGPT_APIKEY')))"` | LLM key env var unset — required by the whole `genai` family | Export `APILOGICSERVER_CHATGPT_APIKEY` (model override: `APILOGICSERVER_CHATGPT_MODEL`) | `apilogicserver-cli-and-config`, `apilogicserver-genai-development` | env-var name verified in installed CLI source; failure mode per docs, not live-verified |
| 17 | Project creation logs `ERROR - Dynamic model import failed` / `Unable to introspect model classes` | Inspect `database/models.py` for the uncompilable class | Unusual DB naming defeated model generation | Correct `models.py`, run `als rebuild-from-model`, merge created files — all via change-control | `apilogicserver-data-modeling`; gates: `apilogicserver-change-control` | per docs, not live-verified |
| 18 | A 4xx you can't classify: is it auth or logic? | `curl -s --noproxy '*' -w '\n%{http_code}\n' http://localhost:5656/api/Customer/` (no header — establishes the auth baseline shape) | 400 + `errors[0].code == "2001"` is a constraint; 401/422 with top-level `msg` is auth | Run the three probes in **E2**; fix per the branch you land in | **E2** | verified (all three shapes live) |

## Deep-dive D1 — "My constraint did not fire": the where-clause pruning story

The canonical wasted afternoon, reproduced end-to-end (verified 2026-08-23, Genai-Logic 17.03.19) on the `basic_demo` model with its five rules (see `apilogicserver-logic-patterns`), the relevant two being:

```python
Rule.constraint(validate=Customer, as_condition=lambda row: row.balance <= row.credit_limit,
                error_msg="Customer balance ({row.balance}) exceeds credit limit ({row.credit_limit})")
Rule.sum(derive=Customer.balance, as_sum_of=Order.amount_total, where=lambda row: row.date_shipped is None)
```

**Symptom.** Tester PATCHes an Item's quantity to an enormous value. Expectation: balance explodes past the credit limit, constraint rejects with 400. Observed: **HTTP 200**. First (wrong) conclusions people reach: "the constraint is broken", "rules are off", "security swallowed it".

**Hypotheses.** (A) Rules not loaded at all. (B) Constraint loaded but broken. (C) Rules ran, but the balance legitimately did not change — something upstream pruned the chain.

**Discriminating experiment.** One variable: the order's `date_shipped`. Item 1 belongs to Order 1 (**shipped**, `date_shipped: 2023-03-22`); Item 2 belongs to Order 2 (**unshipped**, `date_shipped: None`, customer Alice: balance 90, credit_limit 5000, unit_price 90). Predict first: if (C), the PATCH on the shipped order's item returns **200** and the log shows Order adjusted but **no Customer row**; the same PATCH on the unshipped order's item computes amount 100 × 90 = **9000** > 5000 and returns **400** naming 9000.

Probe 1 — PATCH Item 1 (shipped Order 1). Result 200. Log (captured verbatim, trimmed):

```
Logic Phase:		ROW LOGIC		(session=0x7fd465f678d0) (sqlalchemy before_flush)
..Item[1] {Update - client} ... quantity:  [2-->] 50000, amount: 300.0000000000, ...
..Item[1] {Formula amount} ... amount:  [300.0000000000-->] 7500000.0000000000, ...
....Order[1] {Update - Adjusting order: amount_total} ... date_shipped: 2023-03-22, amount_total:  [300.0000000000-->] 7500000.0000000000 ...
Logic Phase:		COMMIT LOGIC		(session=0x7fd465f678d0)
```

Order.amount_total was adjusted to 7,500,000 — and **no `Customer[...]` line exists**: the sum's `where=lambda row: row.date_shipped is None` excludes shipped orders, so the balance adjustment was pruned and the constraint had nothing to react to. (Trap inside the trap: the transaction's `These Rules Fired` summary still lists the Customer.balance sum rule — see "Reading the logic log".)

Probe 2 — PATCH Item 2 quantity 1→100 (unshipped Order 2). Result **400**, body verbatim:

```json
{"errors": [{"title": "Customer balance (9000.0000000000) exceeds credit limit (5000.0000000000)",
  "detail": {"model": "Customer", "error_attributes": []}, "code": "2001"}]}
```

Log verbatim (note the chain depth in the leading dots):

```
Logic Phase:		ROW LOGIC		(session=0x7fd465e05c90) (sqlalchemy before_flush)
..Item[2] {Update - client} ... quantity:  [1-->] 100, amount: 90.0000000000, ...
..Item[2] {Formula amount} ... amount:  [90.0000000000-->] 9000.0000000000, ...
....Order[2] {Update - Adjusting order: amount_total} ... date_shipped: None, amount_total:  [90.0000000000-->] 9000.0000000000 ...
......Customer[1] {Update - Adjusting customer: balance} ... balance:  [90.0000000000-->] 9000.0000000000, credit_limit: 5000.0000000000 ...
......Customer[1] {Constraint Failure: Customer balance (9000.0000000000) exceeds credit limit (5000.0000000000)} ...
```

The predicted 9000 appears to the digit. Hypotheses A and B are dead: the same rules, same code path, fired and rejected when the where-clause admitted the order.

**Resolution.** The constraint is fine; the *qualified sum* is the gate. Shipped orders are, by declared business intent, not part of `balance`. If the business actually wants shipped orders counted, the fix is the rule's `where=` (edit via `apilogicserver-logic-patterns`, land via `apilogicserver-change-control`); it is not a debugging problem. **Generalize:** whenever "a constraint didn't fire", first ask "did the watched value change at all?" — read the phase lines for the adjustment row, and check every aggregate's `where=` between the changed row and the constrained row. Why pruning exists and why sums adjust instead of re-querying: `declarative-rules-reference`.

## Deep-dive D2 — Rule not discovered

Mechanism (verified by reading both generated projects' code): `logic/declare_logic.py` calls `logic/logic_discovery/auto_discovery.py`, which **recursively walks** `logic/logic_discovery/` (`os.walk`), imports every `*.py` except `auto_discovery.py` and `__init__.py`, and calls the module's top-level **`declare_logic()`**. Similarly `api/api_discovery/auto_discovery.py` walks `api/api_discovery/` and calls each module's **`add_service(app, api, project_dir, swagger_host, PORT, method_decorators)`**.

Failure modes, in order of frequency:

1. **File in the wrong place** — anywhere but under `logic/logic_discovery/` (subdirectories are fine; the walk is recursive: verified, e.g. `order_place/check_credit.py` is discovered).
2. **Wrong shape** — no top-level `def declare_logic():` → discovery raises `AttributeError` at startup (the module loads, then the call fails). For API services, missing `add_service(...)` likewise.
3. **Wrong extension** — the sample itself ships `workflow_integration.pyZZ` (verified on disk): renaming away from `.py` is the supported way to disable a file; conversely a file you meant to enable but left as `.pyZZ`/`.py.bak` is invisible.
4. **Server not restarted** — discovery runs once at startup.

Verify what loaded, two ways (verified — outputs match exactly):

```bash
grep -a "discovered logic" logs/als.log | tail -1
# ..discovered logic: ['integration.py', 'simple_constraints.py', 'use_case.py', 'clone_order.py',
#  'units_in_stock.py', 'employee_audit.py', 'check_credit.py', 'app_integration.py',
#  'all_classes_stamping.py', 'raise_over_20_percent.py']        <- Northwind sample, 10 files
bash scripts/list_discovered_logic.sh          # static prediction of the same list + shape check
```

Also check the startup **rule bank listing** (`The following rules have been loaded` / `Rule Bank[0x...]`, then `Logic Bank 1.32.00 - 34 rules loaded` in the Northwind sample) — your rule must appear under its `Mapped Class[...]`. Caution: do **not** create `api/api_discovery/__init__.py` — the generated API discovery code (verified read) does not skip it and would call `add_service()` on it at startup. File templates and the safe add-a-rule procedure: `apilogicserver-logic-patterns`.

## Deep-dive D3 — The 17.03.19 constraint-logging TypeError (status: open bug)

**Verified 2026-08-23, Genai-Logic 17.03.19.** `config/server_setup.py`, function `short_format_exception` (~line 203 in generated projects), contains:

```python
lines = result.splitlines('\n')     # BUG: splitlines takes a keepends bool, not a separator
```

Passing the string `'\n'` raises `TypeError: 'str' object cannot be interpreted as an integer` — *inside the logging machinery*, exactly when a constraint violation's exception is being pretty-printed. Console shows, in order: the constraint's logic-log lines, `These Rules Fired`, then `--- Logging error ---`, a long stack trace ending in `config.server_setup.ValidationErrorExt: <your constraint message>`, then `During handling of the above exception, another exception occurred:` ending at `config/server_setup.py", line 203, in short_format_exception` with the TypeError.

**What it is not:** a broken engine or a lost transaction. Confirm harmlessness (all verified): the client still receives HTTP **400** with `errors[0].code == "2001"` and the constraint message; the rollback is correct (re-read the row: unchanged); the stack trace itself shows the intended path `logic_row.py _adjust_parent_aggregates() → save_altered_parents() → _constraints() → constraint.py execute() → constraint_handler → raise ValidationErrorExt`. The only casualty is the pretty condensed stack trace for that one failed transaction.

**How to confirm you are seeing this bug and not a real crash:** (a) the HTTP response is a well-formed 400/2001, not a 500; (b) the TypeError's own frame is `short_format_exception` at `config/server_setup.py:~203`; (c) `scripts/extract_logic_log.sh` flags the block as "ended by --- Logging error ---" but shows the full constraint evaluation above it. **Status: open in 17.03.19.** The corrected line would be `result.splitlines()` — but `config/server_setup.py` is generated project infrastructure: patch it only as a classified, reviewed change through `apilogicserver-change-control` (and expect to re-apply after regeneration). Do not report the engine as broken on this evidence.

## Reading the logic log

Where it goes (verified): the console **and** `logs/als.log` (rotating file handler, 2 MB, one backup `als.log.1` — rotation observed live), wired in `config/logging.yml`. The logic log is standard Python logging under the logger name **`logic_logger`** (per docs, confirmed in `logging.yml`).

Annotated skeleton (assembled verbatim from a captured transaction, verified):

```
Logic Phase:		ROW LOGIC		(session=0x7fd465e05c90) (sqlalchemy before_flush)
..Item[2] {Update - client} id: 2, ..., quantity:  [1-->] 100, amount: 90.0000000000, ...
                             row: 0x7fd465e1e510  session: 0x7fd465e05c90  ins_upd_dlt: upd, initial: upd
..Item[2] {Formula amount} ..., amount:  [90.0000000000-->] 9000.0000000000, ...
....Order[2] {Update - Adjusting order: amount_total} ..., amount_total:  [90.0000000000-->] 9000.0000000000 ...
......Customer[1] {Update - Adjusting customer: balance} ..., balance:  [90.0000000000-->] 9000.0000000000 ...
Logic Phase:		COMMIT LOGIC		(session=0x7fd465e05c90)
Logic Phase:		AFTER_FLUSH LOGIC	(session=0x7fd465e05c90)
These Rules Fired (see Logic Phases, above, for actual order):
    1. Derive <class 'database.models.Customer'>.balance as Sum(Order.amount_total Where ...)
Logic Phase:		COMPLETE(session=0x7fd465e05c90))
```

How to read it, line by line:

- **Phase lines.** `ROW LOGIC` = rules executing during the ORM's `before_flush`; `COMMIT LOGIC` = commit-phase rules (after all row logic, before flush to SQL); `AFTER_FLUSH LOGIC` = post-flush events (e.g. Kafka sends); `COMPLETE` closes the transaction. Semantics and ordering theory: `declarative-rules-reference`.
- **One line = one rule execution on one row**: `<Class>[<pk>] {<reason>}` then every attribute. The `{reason}` tells you *why* the row was touched: `Update - client` (your PATCH), `Formula amount`, `Update - Adjusting order: amount_total` (a sum adjustment), `Constraint Failure: <msg>`, `AfterFlush Event`.
- **`[old-->] new`** marks each changed attribute (e.g. `quantity:  [1-->] 100`); unchanged attributes print bare. This is your predicted-number scoreboard.
- **Leading dots = chain depth** ("log indention shows multi-table chaining", per docs; verified `..Item` → `....Order` → `......Customer`). Deeper dots mean "this row was reached *because of* the shallower one".
- **`session=0x...`** groups lines of one transaction — essential when concurrent requests interleave; **`row: 0x...`** identifies the instance. **`ins_upd_dlt: upd, initial: upd`** = current vs initial verb for the row (ins/upd/dlt).
- **`These Rules Fired` is an inventory, not a change record** (verified trap): in the shipped-order transaction of D1 the summary listed the `Customer.balance` sum rule even though *no Customer row was adjusted* (the where-clause pruned it). The phase lines are the authoritative record; trust them, not the summary, when arguing about what changed.
- **Startup sections** (verified): the rule bank listing (`The following rules have been loaded` per `Mapped Class[...]`), the dependency listing (`The following attributes have been referenced` — e.g. `..Customer.Balance: constraint`, `..Order.AmountTotal: sum derived from`, `..Order.ShippedDate: aggregate where clause`), and `Logic Bank 1.32.00 - 34 rules loaded`. Read these to confirm your rule exists *before* debugging why it "didn't fire".

**Verbosity — the real knobs** (all verified in generated projects):

1. `config/logging.yml` → `loggers: logic_logger: level: DEBUG` — **the** logic-log switch; DEBUG is the shipped default (that is why you see the trace at all). Set `WARNING` to silence it. `engine_logger` (engine internals) ships commented-out; uncomment its `level: DEBUG` for engine-level detail. (`config/config.py` holds no logic-log knob — grepped; `logging.yml` is the switch.)
2. `--verbose=True` CLI flag or `export APILOGICPROJECT_VERBOSE=True` → sets `api_logic_server_app`, `safrs`, and the three security loggers to DEBUG (`config/server_setup.py`, `if args.verbose:` block). SQLAlchemy engine logging is present there but commented out.
3. `export APILOGICPROJECT_DEBUG=True` → app logger to DEBUG (INFO when False).
4. `APILOGICPROJECT_LOGGING_CONFIG` → path to an alternate logging YAML (launch configs pass `config/logging.yml`).

To capture a clean trace of one experiment: note the time, run the probe, then `scripts/extract_logic_log.sh logs/als.log` and take the last transaction block.

## Debugger workflow (VS Code)

The generated `.vscode/launch.json` ships ready-made configurations (names verbatim, verified in a generated project): `Run Project (start server)`, `Run Project DEBUG`, `  - API Logic Server - VERBOSE`, `  - No Security ApiLogicServer (e.g., simpler swagger)`, `  - No Security ApiLogicServer VERBOSE`, `Test - test/basic/server_test.py`, `  - Run designated Python file`, `MCP - Model Context Protocol - Client Executor`, `Behave Run`, `  - Behave No Security`, `  - Behave Scenario`, `  - Behave Logic Report`, `REBUILD TEST DATA 1`/`2`, `Rebuild Test Data Z`, `Python: Module`, `Python: Current File`, `db-debug - explore SQLAlchemy`, `Sys Info`. All use `justMyCode: false` (you can step into the engine) and set `PYTHONHASHSEED=0` (stable optimistic-locking checksums — `apilogicserver-validation-and-qa`).

Procedure:

1. Start under the debugger with **`Run Project DEBUG`** (sets `APILOGICPROJECT_DEBUG=True`); use a `No Security` config to take auth out of the experiment (one variable at a time).
2. **Breakpoints in rules:** per the Logic-Debug docs you can "stop in lambda functions" — put the breakpoint on the lambda's line in `logic/declare_logic.py` / `logic/logic_discovery/*.py`; it binds to the lambda body and hits when the rule evaluates. For anything non-trivial, prefer a named function (`as_condition=my_check`) or an event rule and breakpoint inside it — easier stepping, docstrings, watchpoints (`apilogicserver-logic-patterns`).
3. **Trigger the write** with curl/Swagger/admin app — never by poking the DB (row 9).
4. **Inspect at the stop** (attribute names verified in the installed engine, `logic_bank/exec_row_logic/logic_row.py`): in lambdas you get `row` (and `old_row` where the signature provides it); in events you get `logic_row` with `logic_row.row` (current values — an instance of your `database/models.py` class, so IDE completion works), `logic_row.old_row` (pre-change values — compare to spot the delta), `logic_row.ins_upd_dlt` (verb), `logic_row.nest_level` (chain depth, = the log's dots), `logic_row.reason`, `logic_row.session`, `logic_row.name` (class name). Helper methods (verified via `hasattr` on the installed class, 2026-08-26): `logic_row.are_attributes_changed(attr_list)`, `logic_row.log(msg)`, and the underscore-prefixed `logic_row._get_parent_logic_row(role_name)` / `logic_row._get_derived_attributes()`. Caution: the engine's own class docstring advertises the last two WITHOUT the underscore (stale) — `logic_row.get_parent_logic_row('order')` raises `AttributeError`; the real defs are at `logic_row.py` ~248 and ~487.
5. Useful engine-side breakpoints when a rule misbehaves mysteriously (paths verified in stack traces): `logic_bank/exec_row_logic/logic_row.py` — `_adjust_parent_aggregates()` (why/whether a parent adjusts) and `_constraints()` (every constraint evaluation).
6. Exploring data outside a request: **`db-debug - explore SQLAlchemy`** runs `database/db_debug/db_debug.py` under the debugger (`apilogicserver-data-modeling`).

Current docs' IDE-Health-Check page describes an AI-assisted "vital signs"/"health check" review (rule coverage/integrity scoring) rather than an IDE-setup checklist — per docs, not live-verified. IDE/venv wiring problems: `apilogicserver-build-and-env`.

## Worked discriminating experiments

**E1 — Where-clause pruning (the full story: Deep-dive D1).** Variable: parent order shipped vs unshipped. Predictions: 200 + no Customer adjustment row vs 400 + `9000.0000000000` in the message. Both confirmed to the digit.

**E2 — Is this 4xx auth or logic? (all three shapes verified live.)** Variable: the request's credential state, holding URL/payload fixed. Three probes (copy-paste; substitute your failing URL/payload in probe 3) and their discriminating outcomes:

```bash
curl -s --noproxy '*' -w '\n%{http_code}\n' http://localhost:5656/api/Customer/
#   -> 401  {"msg":"Missing Authorization Header"}          = auth layer: no credential sent
curl -s --noproxy '*' -w '\n%{http_code}\n' -H "Authorization: Bearer garbage" http://localhost:5656/api/Customer/
#   -> 422  {"msg":"Not enough segments"}                    = auth layer: token malformed
TOKEN=$(curl -s --noproxy '*' -X POST http://localhost:5656/api/auth/login \
  -H 'Content-Type: application/json' -d '{"username":"admin","password":"p"}' \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
curl -s --noproxy '*' -w '\n%{http_code}\n' -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -X PATCH 'http://localhost:5656/api/Item/2/' \
  -d '{"data":{"type":"Item","id":"2","attributes":{"quantity":100}}}'
#   -> 400  {"errors":[{"title":"...","code":"2001",...}]}   = LOGIC: constraint rejected (rules ran)
```

Decision rule: **`errors[0].code == "2001"` means a business-rule constraint** (raised by `constraint_handler` → `ValidationErrorExt`, whose default `api_code=2001` — verified in `config/server_setup.py`); a JSON body with top-level `msg` means the security layer answered and your rules never ran. Predict before each probe which shape you expect; if the "valid token" probe still returns 401, your token pipeline (not your logic) is the defect → `apilogicserver-security-model`.

**E3 — Server "won't start": port collision vs crash vs wrong port.** Variable: none of your code — probe the port first, then the process. Predictions: (a) if another server owns the port, `curl -s --noproxy '*' http://localhost:5656/api -o /dev/null -w '%{http_code}'` prints `200` *and* your new start attempt logs the verbatim row-1 message; (b) if your process crashed at startup, the curl prints `000` and the console shows a Python traceback (rows 2/3, or a real defect); (c) if it started on a different port (`--port`, `APILOGICPROJECT_PORT` — precedence in `apilogicserver-cli-and-config`), `000` on 5656 but the startup banner names the real port (`http://localhost:<port>`). All three observed states verified; one curl + one banner-read classifies the failure without touching anything.

## Shipped diagnostic scripts

Three executable scripts under this skill's `scripts/` directory. Dependencies: bash, curl, python3 stdlib only; curl runs with `--noproxy '*'`. Each was executed against the live Northwind sample server / captured logs before shipping (verified 2026-08-24, Genai-Logic 17.03.19); the sample outputs below are pasted from those runs.

### scripts/probe_health.sh — liveness, login, authorized read

```bash
HOST=localhost PORT=5656 ALS_USER=admin ALS_PASS=p RESOURCE=Customer bash scripts/probe_health.sh
```

All parameters are env vars with those defaults. Steps: (1) `GET /api` expects 200; (2) login expects `access_token` — if login fails but an unauthenticated GET succeeds it prints `SKIP ... security is OFF` instead of failing; (3) authorized `GET /api/$RESOURCE/?page[limit]=1` expects 200 with `"data"`. Exit 0 = healthy, exit N = step N failed. Captured runs:

```
PASS  1. server up: GET http://localhost:5656/api -> HTTP 200
PASS  2. login: POST /api/auth/login as 'admin' -> access_token (331 chars)
PASS  3. authorized GET /api/Customer/ -> HTTP 200, meta.total=95
OK    all probes passed against http://localhost:5656
```

```
$ ALS_PASS=wrong bash scripts/probe_health.sh          # failure path, exit 2
PASS  1. server up: GET http://localhost:5656/api -> HTTP 200
FAIL  2. login: POST /api/auth/login as 'admin' -> no access_token
      Response was: "Wrong username or password"
      'Wrong username or password' -> check ALS_USER/ALS_PASS (sample DB: admin/p)
```

### scripts/extract_logic_log.sh — logic transactions out of a noisy log

```bash
bash scripts/extract_logic_log.sh logs/als.log        # or any captured console log
```

Strips ANSI color codes, then prints each transaction from `Logic Phase: ROW LOGIC` through `COMPLETE` (phase lines, adjustments, `These Rules Fired`) as a numbered block with its session id. A block ending in `--- Logging error ---` instead of `COMPLETE` is flagged as the constraint-violation path (Deep-dive D3) — evidence preserved, verdict attached. Captured run against the basic_demo experiment log (trimmed):

```
==============================================================================
Transaction 3  (session=0x7fd465e05c90)  [ended by "--- Logging error ---" — constraint-violation
path; 400/rollback still correct (short_format_exception bug, see debugging playbook)]
==============================================================================
Logic Phase:		ROW LOGIC		(session=0x7fd465e05c90) (sqlalchemy before_flush)
..Item[2] {Update - client} id: 2, order_id: 2, product_id: 2, quantity:  [1-->] 100, ...
......Customer[1] {Update - Adjusting customer: balance} ... balance:  [90.0000000000-->] 9000.0000000000 ...
......Customer[1] {Constraint Failure: Customer balance (9000.0000000000) exceeds credit limit (5000.0000000000)} ...
...
3 logic transaction(s) extracted from .../server_basic_demo.log.
```

If it prints `No "Logic Phase: ROW LOGIC" blocks found`, either no writes ran (row 9: the write may have bypassed the engine) or `logic_logger` is silenced in `config/logging.yml`.

### scripts/list_discovered_logic.sh — predict what auto-discovery will load

```bash
cd <project-root> && bash scripts/list_discovered_logic.sh      # read-only; exit 1 if any BAD SHAPE
```

Mirrors the generated discovery code exactly: recursive walk of `logic/logic_discovery/` (excluding `auto_discovery.py`, `__init__.py`; requires `declare_logic()`) and of `api/api_discovery/` (requires `add_service(...)`); flags disabled files (`*.pyZZ` etc.) and **BAD SHAPE** files that discovery would load but crash on. Captured run from the Northwind sample root — the 10 logic files and 7 service files match the live startup log's `..discovered logic:` / `..discovered services:` lists exactly (verified):

```
== Logic discovery — each file needs declare_logic() (logic/logic_discovery/) ==
   WILL LOAD   logic/logic_discovery/integration.py
   WILL LOAD   logic/logic_discovery/simple_constraints.py
   WILL LOAD   logic/logic_discovery/use_case.py
   WILL LOAD   logic/logic_discovery/order_clone/clone_order.py
   WILL LOAD   logic/logic_discovery/order_ship_inventory_reorder/units_in_stock.py
   WILL LOAD   logic/logic_discovery/employee_auditing/employee_audit.py
   WILL LOAD   logic/logic_discovery/order_place/app_integration.py
   WILL LOAD   logic/logic_discovery/order_place/check_credit.py
   WILL LOAD   logic/logic_discovery/system/all_classes_stamping.py
   WILL LOAD   logic/logic_discovery/employee_state_transition_logic/raise_over_20_percent.py
   disabled    logic/logic_discovery/workflow_integration.pyZZ   (not *.py — invisible to discovery)
   -> 10 file(s) will be discovered
== API discovery — ... (api/api_discovery/) ==
   ...
   -> 7 file(s) will be discovered
```

Run it before and after adding a rule file; a rule file listed as `WILL LOAD` that still has no effect moves your search to the rule itself (`apilogicserver-logic-patterns`) or to pruning (Deep-dive D1).

## Provenance and maintenance

Volatile facts and how to re-verify each (run from any generated project root, venv active):

- Port-collision message text — start a second instance while one runs and read stderr, or: `grep -a "Port .* is in use" logs/als.log`
- venv-miss symptom (`No module named 'safrs'`) — `deactivate 2>/dev/null; /usr/bin/python3 -c "import safrs"`
- Auth error shapes (401 Missing Authorization Header / 401 Wrong username or password / 422 Not enough segments / token flow) — `bash scripts/probe_health.sh` plus one curl with `-H "Authorization: Bearer garbage"`
- Constraint error shape (400, `code: "2001"`) and `ValidationErrorExt(api_code=2001)` — `grep -n "api_code=2001" config/server_setup.py`
- `short_format_exception` bug presence (~line 203; re-check each version bump) — `grep -n "splitlines('" config/server_setup.py` (no hit = fixed upstream; update Deep-dive D3)
- Logic-log format, phase names, `[old-->]` notation, These-Rules-Fired inventory behavior — make any PATCH, then `bash scripts/extract_logic_log.sh logs/als.log`
- Discovery mechanics and required function shapes — `grep -n "declare_logic()" logic/logic_discovery/auto_discovery.py; grep -n "add_service(" api/api_discovery/auto_discovery.py`
- Discovered-file lists — `bash scripts/list_discovered_logic.sh` vs `grep -a "discovered logic\|discovered services" logs/als.log`
- Verbosity knobs (`logic_logger` level, `engine_logger`, `APILOGICPROJECT_VERBOSE/DEBUG/LOGGING_CONFIG`) — `grep -n "logic_logger" config/logging.yml; grep -n "args.verbose\|APILOGICPROJECT_DEBUG" config/server_setup.py`
- launch.json configuration names — `python3 -c "import json;txt=''.join(l for l in open('.vscode/launch.json') if not l.lstrip().startswith('//'));print([c['name'] for c in json.loads(txt)['configurations']])"` (the file carries `//` comment lines; strip whole comment lines, not `//.*`, which would maul URLs)
- LogicRow inspectables — `python3 -c "import logic_bank.logic_bank; from logic_bank.exec_row_logic.logic_row import LogicRow; print(LogicRow.__doc__)"` (importing `logic_bank.exec_row_logic.logic_row` directly fails with a circular-import `ImportError` — import `logic_bank.logic_bank` first; verified 2026-08-26). The docstring's helper list is stale: `get_parent_logic_row`/`get_derived_attributes` actually ship underscore-prefixed — confirm with `hasattr(LogicRow, '_get_parent_logic_row')`.
- Opt-locking message — `grep -rn "altered by another user" api/system/opt_locking/opt_locking.py`
- Kafka FALLBACK message — `grep -a "Kafka mode" logs/als.log | tail -1`
- Genai key env var — `grep -rn "APILOGICSERVER_CHATGPT_APIKEY" "$(python -c 'import api_logic_server_cli,os;print(os.path.dirname(api_logic_server_cli.__file__))')/genai/client.py"`

Grounded in: https://apilogicserver.github.io/Docs/Logic-Debug/, https://apilogicserver.github.io/Docs/Troubleshooting/, https://apilogicserver.github.io/Docs/IDE-Health-Check/ and a live Genai-Logic 17.03.19 install (2026-08-23) — scripts and probes verified against a live install and its captured server logs on 2026-08-23/24.
