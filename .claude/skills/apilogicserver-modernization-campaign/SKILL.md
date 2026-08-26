---
name: apilogicserver-modernization-campaign
description: >-
  Executable, decision-gated campaign modernizing a legacy spreadsheet/VBA + GPT automation
  (this repo's turbo3.5_excel_vba + api_Key.xlsm is the instance) into a governed API Logic
  Server (Genai-Logic) system. Phases P0-P7, each with exact commands, expected verified
  outputs, a measurable gate, failure branches, and a rollback note: legacy inventory and defect
  mapping, environment build, project creation, spreadsheet-formula-to-rule translation, security
  activation, Behave validation, governed AI re-entry via MCP (replacing GPT-in-a-cell), and
  containerization. Ends with a ranked solution menu (full adoption / Excel bridge / genai
  re-create), fenced wrong paths, and a promotion protocol. Use when asked to migrate, modernize,
  or replace Excel workbooks, VBA macros, spreadsheet automation, or client-embedded OpenAI/GPT
  calls; when planning legacy-to-ALS adoption end to end; when a "working" workbook must become
  auditable, secured, and tested; or when sequencing create/logic/auth/behave phases with proof.
---

# API Logic Server Modernization Campaign

## Purpose

This skill is the end-to-end, gated runbook for the owner-ratified hardest problem in this repo: carry a legacy spreadsheet/VBA + GPT automation (the concrete instance: `turbo3.5_excel_vba` and `api_Key.xlsm` at this repo's root) to a governed, production-grade API Logic Server system. It is executable: every phase has copy-pasteable commands, the exact output a healthy run produces (quoted from live-verified transcripts wherever they exist), a measurable pass/fail gate, and a named branch for each known failure. A phase is complete when its gate's observable is captured — never when the result "looks right."

## Use this skill when

- You are asked to migrate, modernize, replace, or "productionize" an Excel/VBA automation, a workbook macro, or any client-embedded LLM/API call like `turbo3.5_excel_vba`.
- You need the full legacy-to-ALS sequence — inventory, environment, project, rules, security, tests, AI re-entry, deploy — with proof at each step.
- You must decide between full ALS adoption, a hybrid Excel bridge, or GenAI re-creation (see Solution Menu).
- Someone asks "the workbook works — why replace it?" and you need the defect-to-mechanism mapping (P0) plus the measurable governance proof (P6 gate).

## Do NOT use this skill when

- You need the line-by-line autopsy of the legacy VBA file itself → **apilogicserver-failure-archaeology** entry A9 owns it (this skill maps defects to campaign phases; A9 owns the full forensics).
- You are executing one narrow step and already know where you are: environment repair → **apilogicserver-build-and-env**; writing a specific rule → **apilogicserver-logic-patterns**; security details → **apilogicserver-security-model**; API call shapes → **apilogicserver-api-contract**; Behave mechanics → **apilogicserver-validation-and-qa**; MCP/Kafka wiring → **apilogicserver-integration-patterns**; containers/deploy → **apilogicserver-operate-and-deploy**.
- A server or rule is misbehaving right now → **apilogicserver-debugging-playbook** (this skill names its symptom rows at each branch).
- You are deciding what may be edited vs regenerated, or merging a change → **apilogicserver-change-control** (every phase here lands through its gates).

---

## Rules of engagement (read once, apply to every phase)

1. **Gates are measurable.** Each phase ends with a GATE: a command whose output either matches the quoted expectation or does not. No gate is passed "by inspection of the admin app" — that is explicitly fenced (see Wrong Paths).
2. **Predict numbers first.** Before any probe transaction, write down the expected values (quantities, sums, HTTP codes, error text). Compare after. This is the standing evidence bar (**apilogicserver-research-methodology** owns the general discipline; **apilogicserver-validation-and-qa** owns the test mechanics).
3. **Verification labels.** Facts below marked "verified 2026-08-23, Genai-Logic 17.03.19" were produced by live execution against a real install; "per docs, not live-verified" means docs-derived; "candidate" means designed but never executed anywhere — treat as a proposal.
4. **Every phase lands via change-control.** The final step of any phase that changes files is: classify the change, pass the gates, and commit per **apilogicserver-change-control** (its §2 classification table and §7.2 PR checklist).
5. **Paths.** Commands run from either the *workspace root* (the directory holding your venv, which will contain the project) or the *project root* (the created project directory containing `api_logic_server_run.py`). Each command block states which.
6. **Jargon.** ALS = API Logic Server, installed since v17 under the package name **Genai-Logic** (CLI: `als`). JSON:API = the REST style SAFRS serves (typed `data/attributes/relationships` envelopes). Rule = a LogicBank declaration in `logic/`. Gate = this skill's measurable pass condition. JWT = the login token from `POST /api/auth/login`.

### Campaign map

| Phase | Name | Gate (one line) |
|---|---|---|
| P0 | Inventory the legacy | Every defect mapped to the ALS mechanism that eliminates it |
| P1 | Environment | `als welcome` prints the version banner |
| P2 | Target schema + project | Server banner up; authenticated GET returns rows |
| P3 | Declarative logic | Logic log shows the chain; violating PATCH → 400 code 2001 with predicted numbers |
| P4 | Security | 401 without token (verified shape); role-filtered read demonstrated |
| P5 | Validation | Behave all green + Behave Logic Report file exists |
| P6 | Governed AI re-entry | A rule-violating write through the new channel is REJECTED 400/2001 |
| P7 | Containerize + operate | Container runs the same Behave suite green (to-execute) |

---

## P0 — Inventory the legacy

**Objective.** Establish exactly what the legacy system does (its capability list), what is wrong with it (risk register), and — the gate — map every defect to the specific ALS mechanism that eliminates it. Scope here is the campaign mapping; the full line-by-line autopsy is **apilogicserver-failure-archaeology** entry A9.

**Exact commands** (from the legacy repo root):

```bash
cat turbo3.5_excel_vba          # the whole legacy "system": one VBA function
wc -l turbo3.5_excel_vba        # expect: 44 (42 content lines + trailing blanks)
ls -la                          # expect: turbo3.5_excel_vba, api_Key.xlsm, .git — plus .claude/ (this skill library); the legacy system itself is just the two files
git log --oneline -- turbo3.5_excel_vba api_Key.xlsm | wc -l   # expect: 2 (the legacy system landed in 2 commits — no CI, no tests, no docs; the repo's TOTAL count grows as this library lands, so scope the check to the legacy files)
```

**EXPECTED observation** (verified 2026-08-23, Genai-Logic-era workspace; file read in full). The file is `Function OpenAI(prompt As String) As String`: it string-concatenates a JSON body for `https://api.openai.com/v1/chat/completions` (model `gpt-3.5-turbo`, temperature 0, both hardcoded), sends it synchronously via `MSXML2.ServerXMLHTTP` with a hardcoded `apiKey`, then "parses" the response with `InStr`. The parse loop, quoted verbatim from the file:

```vba
ContentStart = InStr(json, """content"": """) + Len("""content"": """)
ContentEnd = ContentStart

' Iterate through the string until we find an unescaped double quote
Do While True
    ContentEnd = InStr(ContentEnd, json, """")
    ' Check if the double quote is escaped (preceded by a backslash)
    If Mid(json, ContentEnd - 1, 1) <> "\" Then Exit Do
    ContentEnd = ContentEnd + 1
Loop
```

`api_Key.xlsm` is the binary workbook that carries the key and the function in practice. Do not parse the binary; record its role: the credential and the behavior ship inside an un-diffable file, copied per user.

**Deliverable 1 — capability list.** The legacy system has exactly one capability: `=OpenAI("some prompt")` in a cell returns a chat-completion string into that cell, synchronously (Excel frozen for the duration). No state, no persistence, no multi-step flows, no roles. Write this down — it is the entire behavioral surface P2–P6 must cover, and it is small.

**Deliverable 2 — risk register** (each risk is a defect below): key exfiltration via workbook copies; silent-garbage answers on response-format drift or error bodies; JSON injection via cell content; run-time errors on responses > ~32 KB (16-bit `Integer` indexes) or content ending in `\`; UI freeze; zero audit trail; per-user divergence of the "logic."

**GATE — the defect-to-mechanism table.** The phase passes when each of the five defects has a named ALS mechanism and an owning skill. This table IS the campaign's justification; keep it in the migration record.

| # | Defect (evidence in the file) | Failure it causes | ALS mechanism that eliminates it | Owner skill | Verification |
|---|---|---|---|---|---|
| 1 | String-concatenated JSON request body (lines 10–12: `& prompt &` pasted raw into a JSON literal) | Any quote/backslash/newline in a cell → invalid request or injected JSON keys | Wire format is generated, never hand-built: SAFRS serializes JSON:API server-side; clients use real JSON libraries against a typed contract | apilogicserver-api-contract | file read in full; envelope verified 2026-08-23 |
| 2 | `InStr`/`Do While` response parsing (lines 28–37, quoted above) — plus 16-bit `Integer` indexes and un-decoded escapes | Escaped-quote overrun, format drift → silent garbage; error bodies parsed as success; run-time errors 5/6 | Responses are `jsonapi 1.0` envelopes (`data/attributes/meta`) parsed by JSON parsers; errors are typed (`errors[].code`), never scraped | apilogicserver-api-contract; forensics: failure-archaeology A9 | 4 failure modes enumerated in A9 |
| 3 | Hardcoded API key (line 6) + key living in `api_Key.xlsm` | Secret ships with every workbook copy; no rotation, no review | Secrets live server-side only (LLM key = server env var `APILOGICSERVER_CHATGPT_APIKEY`); clients hold a short-lived JWT from `POST /api/auth/login` | apilogicserver-security-model; apilogicserver-integration-patterns | login/token shape verified 2026-08-23 |
| 4 | No error handling, no `.Status` check, no timeout/retry, no logging | Failures indistinguishable from success; zero evidence trail | HTTP status contract (400/401/422 shapes, all verified); per-transaction logic log; `logs/als.log`; Behave Logic Report as an audit artifact | apilogicserver-debugging-playbook; apilogicserver-validation-and-qa | shapes verified 2026-08-23 |
| 5 | Business behavior client-side, per-workbook, unversioned, untested | Ungoverned logic invisible to IT; every copy can drift | Logic is declared once in `logic/` and enforced on every write path (API, admin app, custom endpoints, MCP); versioned in git; changes gated | declarative-rules-reference (why); apilogicserver-change-control (gates) | enforcement chain verified 2026-08-23 |

**If you see X instead →** the legacy file differs from the exhibit (different macro, more functions): still fill the same table — the five defect *classes* (hand-built wire format both directions, embedded secret, no error/evidence path, client-side logic) recur in every application-embedded glue; add rows rather than skipping. If someone argues "just harden the VBA," read failure-archaeology A9's status line: SETTLED-BY-REPLACEMENT-PLAN — do not reopen.

**Rollback note.** P0 changes nothing; there is nothing to roll back. The legacy file stays untouched for the whole campaign — it is the before-picture and the acceptance foil.

---

## P1 — Environment

**Objective.** A working venv with the ALS CLI installed and proven. Full install/repair detail is **apilogicserver-build-and-env**; this phase is only the happy path plus branch pointers.

**Exact commands** (workspace root):

```bash
python3 -m venv venv
source venv/bin/activate            # Windows: venv\Scripts\activate
python -m pip install ApiLogicServer
als welcome
```

**EXPECTED observation** (verified 2026-08-23, Genai-Logic 17.03.19; `als welcome` re-run and matched during authoring):

```
Welcome to Genai-Logic 17.03.19
```

Notes that prevent an hour of confusion (all verified): `pip install ApiLogicServer` installs the package named **Genai-Logic**; SIX equivalent CLI entry points are installed — `ApiLogicServer`, `als`, `genai-logic`, `gail`, `gal`, `gl` (all verified working 2026-08-26; official docs often write commands as `gail ...` — that works, but script against `als`/`ApiLogicServer` for portability); `ApiLogicServer version` is NOT a command — use `als welcome` (version) or `als about` (system info).

**GATE.** `als welcome` exits 0 and prints `Welcome to Genai-Logic <version>`. Record the version — every later "verified" label is relative to it.

**If you see X instead →**
- `command not found: als` → venv not active or PATH problem → **apilogicserver-build-and-env** trap table (§5).
- `No module named ...` on any als command → wrong interpreter → build-and-env §4 (60-second self-test), and **apilogicserver-debugging-playbook** row 2.
- pip SSL/proxy failures, driver build errors (`psycopg2`, `pyodbc`) → build-and-env §5–§6.

**Rollback note.** `deactivate; rm -rf venv` — the venv is disposable; nothing else was touched.

---

## P2 — Target schema + project

**Objective.** A created, running, queryable ALS project whose schema models the domain the spreadsheet implies. For this campaign's demo instance, the shipped `basic_demo` schema — Customer / Order / Item / Product — stands in for "the domain the workbook feeds." For a real migration, first run the schema-design checklist in **apilogicserver-data-modeling** (keys, foreign keys for every aggregate, naming), produce a database or model, then use the same commands with your `--db-url`.

**Exact commands** (workspace root; verified sequence — this is exactly how the reference project in this workspace was built):

```bash
als create --project-name=basic_demo --db-url=basic_demo
cd basic_demo
als add-cust                    # installs the demo customizations incl. the 5 rules (P3 reads them)
als add-auth --db_url=auth      # activates security with the sample sqlite auth DB
python api_logic_server_run.py  # start the server (venv active, project root)
```

Flag-spelling note (verified from `--help` 2026-08-25): help prints `--db-url` for add-auth; the underscore form `--db_url=auth` is the form verified by execution — both observed against 17.03.19. `--db-url=basic_demo` and `db_url=auth` are shorthands (full decoder: **apilogicserver-cli-and-config**). For a real migration substitute your SQLAlchemy URL and skip `add-cust` (you will write your own logic in P3).

**EXPECTED observation** (verified 2026-08-23, Genai-Logic 17.03.19).

Created top level, quoted from the real created projects:

```
api/ config/ database/ devops/ docs/ integration/ logic/ security/ test/ ui/
api_logic_server_run.py  readme.md  requirements.txt  .vscode/  .claude/  CLAUDE.md  .github/
```

(after `add-cust`, also `customizations/` — staged copies, not runtime; see change-control §3.5).

Startup banner, excerpted verbatim from a live start (middle sections elided):

```
The following rules have been activated
...
Logic Bank 1.32.00 - 13 rules loaded
Exposing /Customer
...
Authentication loaded -- api calls now require authorization header
Kafka mode: FALLBACK — KAFKA_SERVER not configured; running debug endpoint only

API Logic Project (name: basic_demo) starting:
..Explore data and API at http_scheme://swagger_host:port http://localhost:5656   *

*************************************************************************
*   Startup Instructions: Open your Browser at: http://localhost:5656   *
*************************************************************************
```

"Kafka mode: FALLBACK" without a broker is normal, not an error (verified). Rule count differs per project (verified in logs 2026-08-25: basic_demo 13, nw_sample 34); presence of "rules have been activated" is the health marker.

Then, in a second terminal, login and read (shapes verified live):

```bash
curl -s --noproxy '*' -X POST http://localhost:5656/api/auth/login \
  -H 'Content-Type: application/json' -d '{"username":"admin","password":"p"}'
# → {"access_token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9. ..."}

TOKEN=<paste access_token>
curl -s --noproxy '*' -H "Authorization: Bearer $TOKEN" \
  "http://localhost:5656/api/Customer/?page%5Blimit%5D=2"
# → JSON:API envelope: data[...].attributes (incl. S_CheckSum), relationships, links,
#   meta: {"count": ..., "limit": 2, "total": ...}, jsonapi: {"version": "1.0"}
```

**GATE.** Both observables captured: (1) the boxed startup banner with `http://localhost:5656`; (2) an authenticated GET returning at least one row with `meta` and `jsonapi: {"version": "1.0"}`. Save both outputs into the migration record.

**If you see X instead →**
- `Address already in use` / `Port 5656 is in use by another program` → **apilogicserver-debugging-playbook** row 1 (stop the other instance or `python api_logic_server_run.py --port=5657`).
- Immediate exit, `No module named 'safrs'` → venv not active → debugging-playbook row 2 / build-and-env.
- `can't open file '.../api_logic_server_run.py'` → wrong directory → debugging-playbook row 3.
- 401 `{"msg":"Missing Authorization Header"}` on the GET → you skipped the login or the header → debugging-playbook row 4.
- Creation logs `Dynamic model import failed` → unusual DB naming defeated introspection → debugging-playbook row 17, then **apilogicserver-data-modeling**.

**Rollback note.** The project is a plain directory: stop the server (Ctrl-C) and `rm -rf basic_demo` returns you to post-P1 state. Never delete a project that has accumulated custom logic without a git commit to fall back to.

---

## P3 — Declarative logic (the conceptual heart of the migration)

**Objective.** Translate the spreadsheet's implicit business behavior into declarative rules, and prove the chain fires with predicted numbers. The bridge insight (theory: **declarative-rules-reference**): *Excel cell formulas ARE derivations; VBA validation IS a constraint; cell recalculation IS watch/react/chain.* A spreadsheet is already a declarative system — the migration recovers that declarativeness and moves it server-side, governed.

### The translation table (spreadsheet construct → rule)

| Spreadsheet / VBA construct | Typical legacy form | ALS rule type | Verified instance (basic_demo, quoted below) |
|---|---|---|---|
| Cell formula | `=Qty*UnitPrice` | `Rule.formula` | `Item.amount = quantity * unit_price` |
| `SUM()` over a range | `=SUM(Items!D:D)` | `Rule.sum` | `Order.amount_total = sum(Item.amount)` |
| `SUMIF()` (conditional roll-up) | `=SUMIF(Status,"open",Amts)` | `Rule.sum` with `where=` | `Customer.balance = sum(Order.amount_total) where date_shipped is None` |
| `VLOOKUP` from a reference sheet | `=VLOOKUP(pid, Products!A:B, 2)` | `Rule.copy` | `Item.unit_price` copied from `Product.unit_price` |
| Data-validation rule / VBA `If ... MsgBox` | reject bad entry by hand | `Rule.constraint` | `balance <= credit_limit` → HTTP 400 code 2001 |
| Automatic recalculation | the cell dependency graph | watch/react/chain (engine ordering) | declarative-rules-reference owns the mechanism |
| `Worksheet_Change` macro side effect | send mail / export on change | event rules (`Rule.after_flush_row_event`) / request pattern | `Order → Kafka topic 'order_shipping'` (integration-patterns) |

### The template: the canonical 5-rule check-credit pattern

Installed by `add-cust` into `logic/declare_logic.py`; copied verbatim from the created project (verified 2026-08-23, Genai-Logic 17.03.19):

```python
Rule.constraint(validate=Customer, as_condition=lambda row: row.balance <= row.credit_limit,
                error_msg="Customer balance ({row.balance}) exceeds credit limit ({row.credit_limit})")
Rule.sum(derive=Customer.balance, as_sum_of=Order.amount_total, where=lambda row: row.date_shipped is None)
Rule.sum(derive=Order.amount_total, as_sum_of=Item.amount)
Rule.formula(derive=Item.amount, as_expression=lambda row: row.quantity * row.unit_price)
Rule.copy(derive=Item.unit_price, from_parent=Product.unit_price)
```

Read them as the worked example of the translation table: one SUMIF, one SUM, one cell formula, one VLOOKUP, one validation — the whole check-credit spreadsheet in five lines. (The docs' procedural equivalent runs ~200 lines; history: failure-archaeology A5.)

### Adding YOUR migrated rules

Add each migrated use case as its own file under `logic/logic_discovery/` (best practice per the shipped `logic/readme_logic_discovery.md`; discovery mechanism verified — `logic/declare_logic.py` calls `auto_discovery.py`, which loaded `simple_constraints.py`, `email_request.py`, `use_case.py`, `all_classes_stamping.py` in the created project). Template (from the shipped `use_case.py`):

```python
# logic/logic_discovery/check_credit.py  (name the file for the use case)
from logic_bank.logic_bank import Rule
from database import models

def declare_logic():
    # your translated rules here, via the table above
    ...
```

Exact signatures, worked patterns, and the safe add-a-rule procedure: **apilogicserver-logic-patterns**. Restart the server after adding (rules load at startup).

### The probe transaction — predict the numbers FIRST

Seeded facts in the created `basic_demo` (verified): Customer "Alice": `balance 90, credit_limit 5000`. Order 2 is UNSHIPPED and holds Item id=2: `quantity 1, unit_price 90, amount 90`. Order 1 is SHIPPED. Write the prediction before running:

| Step | Rule that fires | Predicted value |
|---|---|---|
| PATCH `Item[2].quantity` 1 → 100 | — | quantity 100 |
| formula | `Item.amount = 100 × 90` | 90 → 9000 |
| sum | `Order[2].amount_total` | 90 → 9000 |
| sum (`where date_shipped is None`) | `Customer[Alice].balance` | 90 → 9000 |
| constraint | `9000 <= 5000` is False | HTTP 400, code 2001 |

Run it (project root environment, server running, `$TOKEN` from P2; PATCH body shape per **apilogicserver-api-contract** §4.1):

```bash
curl -s --noproxy '*' -X PATCH "http://localhost:5656/api/Item/2/" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{ "data": { "attributes": { "quantity": 100 }, "type": "Item", "id": "2" } }'
```

**EXPECTED observation** — captured live, verbatim (verified 2026-08-23, Genai-Logic 17.03.19):

```json
{"errors": [{"title": "Customer balance (9000.0000000000) exceeds credit limit (5000.0000000000)",
  "detail": {"model": "Customer", "error_attributes": []}, "code": "2001"}]}
```

HTTP status 400. And the server console logic log for a chained transaction looks like this (verbatim excerpt; old→new shown as `[old-->] new`):

```
Logic Phase:		ROW LOGIC		(session=0x...) (sqlalchemy before_flush)
..Item[2] {Formula amount} id: 2, order_id: 2, ..., quantity:  [1-->] 100, amount:  [90.0000000000-->] 9000.0000000000, ...
Logic Phase:		COMMIT LOGIC		(session=0x...)
Logic Phase:		AFTER_FLUSH LOGIC	(session=0x...)
These Rules Fired (see Logic Phases, above, for actual order):
    1. Derive <class 'database.models.Customer'>.balance as Sum(Order.amount_total Where ...)
```

**Control experiment** (run it — it is the discriminating half): the same PATCH against the SHIPPED order's item SUCCEEDS (200), because `where=date_shipped is None` excludes shipped orders from the balance (verified). If you skip the control you cannot distinguish "constraint works" from "constraint fires on everything."

**GATE.** Three observables: (1) the 400 body matches the predicted numbers inside the verified shape (`code": "2001"`); (2) the logic log shows the `[1-->] 100` / `[90...-->] 9000...` chain; (3) the control PATCH on the shipped order returns 200. For your own migrated rules, repeat the same pattern per rule: prediction table → violating probe → 400/2001 with your numbers → control probe.

**If you see X instead →**
- Violating PATCH returns 200 ("constraint didn't fire") → almost always aggregate `where=`-clause pruning doing its job or misdeclared → **apilogicserver-debugging-playbook** row 7 and deep-dive D1.
- Your new rule has no effect and never logs → not discovered (wrong folder, missing `declare_logic()`) → debugging-playbook row 8 / deep-dive D2.
- Console shows `--- Logging error ---` ... `TypeError: 'str' object cannot be interpreted as an integer` exactly when the constraint rejects → known 17.03.19 logging bug, engine and 400 are correct → debugging-playbook row 10 / failure-archaeology A8. Do NOT interpret it as a broken engine.
- Sums disagree with DB values → a write bypassed the session → debugging-playbook row 9 (and see Wrong Paths).

**Rollback note.** Rules are plain Python files under git: `git checkout -- logic/` restores. A rejected probe transaction rolls itself back (verified — rejection leaves data unchanged); a *successful* probe you did not want must be reversed with a compensating PATCH before P5's suite runs.

---

## P4 — Security

**Objective.** Prove the API refuses unauthenticated access, demonstrate role-filtered reads, and plan credential replacement. Full model: **apilogicserver-security-model**.

**Exact commands.** If your campaign followed P2's demo sequence, `als add-auth --db_url=auth` already ran there (verified form). If your real migration deferred it, run from the project root now, then restart the server:

```bash
als add-auth --db_url=auth      # activates SECURITY_ENABLED + sample sqlite auth DB
```

Then probe (shapes verified live 2026-08-23, re-probed during authoring):

```bash
# 1. No token → refused
curl -s --noproxy '*' -w '\nHTTP %{http_code}\n' "http://localhost:5656/api/Customer/?page%5Blimit%5D=1"
# → {"msg":"Missing Authorization Header"}
#   HTTP 401

# 2. Login → token
curl -s --noproxy '*' -X POST http://localhost:5656/api/auth/login \
  -H 'Content-Type: application/json' -d '{"username":"admin","password":"p"}'
# → {"access_token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9. ..."}

# 3. Restricted role sees fewer rows than admin (role-filtered read)
#    Login as s1/p, repeat the Customer GET with that token, compare meta.count vs admin's.
```

**EXPECTED observation.** Step 1 returns exactly the 401 body above. Step 3's reference pattern is security-model's verified composition matrix (its §4.5): in the `nw+` sample, user `s1` (role sales, Grants OR'd, GlobalFilters AND'd) sees **exactly 1 Customer row** while `admin` sees the full set — verified 2026-08-23/24. Reproduce the same *kind* of evidence in your project: for at least one restricted role, a numeric row-count difference you predicted from the declared `Grant`/`GlobalFilter` in `security/declare_security.py`.

**Replace-sample-credentials plan** (do not defer past this phase): every sample password is `p` and the sample auth DB ships 11 known users (verified) — production cannot go live on it. Plan per security-model §5 (inspecting/changing users, §5.3 production warning) and, for enterprise identity, its Keycloak section (per docs, not live-verified). Land the change via change-control.

**GATE.** (1) The exact 401 body without a token; (2) a role-filtered read with a predicted, observed row-count difference; (3) a written credential-replacement plan committed to the migration record.

**If you see X instead →**
- Login 401 `"Wrong username or password"` → debugging-playbook row 5. Unknown user gives a 500 HTML page in 17.03.19 (observed) — see security-model §6.1.
- 422 `{"msg":"Not enough segments"}` → malformed/empty token → debugging-playbook row 6.
- Everyone sees everything → security not actually enabled (check `SECURITY_ENABLED` per **apilogicserver-cli-and-config**) or missing Grants → security-model §3.
- s1 sees too few/too many rows → Filters are AND'd, Grants are OR'd — recompute the expected WHERE per security-model §4.5 before touching declarations.

**Rollback note.** Deactivation exists (security-model §2.2) but removing auth is a governance regression — record it as an explicit decision, never a convenience. Config-only changes revert via git.

---

## P5 — Validation

**Objective.** Every migrated behavior has a Behave scenario with predicted numbers, including a rejection test per constraint; the Behave Logic Report exists as requirements-traceability. Procedure ownership: **apilogicserver-validation-and-qa** (its §5 add-a-scenario checklist; §3.4 rejection-test pattern). This phase is the campaign's acceptance instrument — P6's governance proof and P7's container gate both re-run this suite.

**Exact commands** (server running first; then from the project root):

```bash
cd test/api_logic_server_behave
python behave_run.py --outfile=logs/behave.log
python behave_logic_report.py run    # writes reports/'Behave Logic Report.md'
```

**EXPECTED observation** (verified 2026-08-23, Genai-Logic 17.03.19, `nw+` reference suite). Console summary — note the counts go to the **console**, not into `behave.log` (the log gets the per-step listing):

```
7 features passed, 26 scenarios passed, 83 steps passed, 0 failed   (~1.4s)
```

Those golden numbers are the *format* of acceptable evidence, not your target counts: your suite's counts are whatever covers the P0 capability list — at minimum, for the demo instance: one good-path scenario (order within credit), one rejection scenario per constraint (the P3 probe as a scenario, asserting the 400 title text), and one where-clause control (shipped order unaffected). Per-scenario logic logs land in `logs/scenario_logic_logs/` (verified: files like `Alter_Item_Qty_to_exceed_.log`), and the report embeds them — that is the audit trail defect #4 said the legacy lacked.

**GATE.** (1) Behave console summary shows `0 failed` across all features/scenarios/steps; (2) `test/api_logic_server_behave/reports/Behave Logic Report.md` exists and contains your scenarios with embedded logic logs; (3) each migrated behavior from P0's capability list is traceable to a named scenario (make the mapping a table in the migration record).

**If you see X instead →**
- `Assertion Failed` in `behave.log` → validation-and-qa §6 (seed assumptions: the certified suite depends on seeded rows like ALFKI/order 10643/Employee 5 — yours must state its own seeds).
- Step "never matched" / suite errors → validation-and-qa §5.
- Checksum-related failures → keep `PYTHONHASHSEED=0` (launch configs and `run.sh` set it) → validation-and-qa repeatability footnote; debugging-playbook row 15.
- Scenario passed but data now wrong → state-restoration truth in validation-and-qa §6.2 — restore the DB before re-runs.

**Rollback note.** Tests are additive files under `test/`; git revert restores. A failed run can leave mutated seed data — restore the database per validation-and-qa §6.3 before re-running, or your next run fails for the wrong reason.

---

## P6 — Governed AI re-entry (replacing GPT-in-a-cell)

**Objective.** Re-introduce AI — the legacy system's one capability — but through the governed door. The proof is measurable: an AI-driven (or bridge-driven) write that violates a rule is REJECTED with the same verified 400/code-2001 shape as P3.

### OLD vs NEW

| | OLD (legacy) | NEW (governed) |
|---|---|---|
| Path | Excel cell → hand-built HTTP → api.openai.com | AI assistant / MCP client → JSON:API on `:5656` → rules + security enforce every write |
| Secret | OpenAI key hardcoded in VBA / `api_Key.xlsm` | Client holds only a JWT; any LLM key lives server-side (`APILOGICSERVER_CHATGPT_APIKEY`) |
| Logic | none (raw completion into a cell) | every write runs the P3 rule chain; refusals are typed 400/2001 |
| Audit | none | logic log per transaction; Behave Logic Report |
| Blast radius on failure | silent garbage in a spreadsheet cell | rejected transaction, rolled back, logged |

### Path A (primary): MCP — AI assistants operate THROUGH the API

MCP (Model Context Protocol — a discovery-plus-tooling convention letting AI assistants call your API as typed tools) is built in. Discovery is live-verified: on the running reference server,

```bash
curl -s --noproxy '*' "http://localhost:5656/.well-known/mcp.json"
```

returned (verified 2026-08-25 against the live 17.03.19 server; excerpt):

```json
{"base_url": "http://localhost:5656/api", "description": "API Logic Project: nw_sample",
 "learning": "To issue one request per row from a prior step (fan-out), use the syntax: ...", ...}
```

The created project ships `integration/mcp/mcp_client_executor.py` and `integration/mcp/mcp_server_discovery.json` (verified on disk). Per docs (Integration-MCP; not live-verified here — the live-LLM leg needs `APILOGICSERVER_CHATGPT_APIKEY`): `als genai-add-mcp-client` installs the `SysMcp` request-pattern table (insert a row carrying the NL request → logic invokes the client executor; the shipped 17.03.19 executor's own curl examples name the attribute `request`, while the docs page says `prompt` — a real docs-vs-install divergence, so verify the created column at `genai-add-mcp-client` time; details: **apilogicserver-integration-patterns**); `python integration/mcp/mcp_client_executor.py mcp` runs the executor; and — the governance property — "MCP also respects your security settings ... API calls are made with the current request header from your login," so role-based grants bind AI-driven calls too. Wiring detail and the request pattern: **apilogicserver-integration-patterns**; AI-output guardrails: **apilogicserver-genai-development**.

### Path B (optional bridge, **candidate — not live-verified**; no Excel runtime exists in this workspace)

Excel keeps a thin VBA call — but against YOUR server, with a Bearer token, server-side logic enforcing. Corrected sketch:

```vba
' CANDIDATE — reviewed, never executed. No key in the sheet: the JWT comes from a login
' prompt or a per-user config outside the workbook, expires (222 min), and grants only
' what security/declare_security.py allows.
Function ALS_Get(path As String, token As String) As String
    On Error GoTo failed
    Dim http As Object
    Set http = CreateObject("MSXML2.ServerXMLHTTP")
    http.setTimeouts 5000, 5000, 15000, 30000
    http.Open "GET", "http://your-server:5656/api/" & path, False
    http.setRequestHeader "Authorization", "Bearer " & token
    http.Send
    If http.Status <> 200 Then
        ALS_Get = "ERROR " & http.Status & ": " & Left(http.responseText, 200)
        Exit Function
    End If
    ALS_Get = http.responseText   ' parse with a real VBA JSON library, never InStr
    Exit Function
failed:
    ALS_Get = "ERROR: " & Err.Description
End Function
```

State this plainly to the owner: hand-rolled JSON *assembly* remains fragile in VBA (defect #1 does not go away on the write path), and VBA has no first-class JSON parser. Therefore: keep Excel **read-mostly** (GET + a maintained VBA JSON parsing library); put every write behind the API from a real client, or at minimum accept that a bridge-driven bad write is now *safely rejected* (the gate below) rather than silently applied. Business logic stays server-side — the bridge carries data, never rules.

**GATE — the governance proof.** Through the NEW channel (an MCP-driven write, or the bridge issuing the P3 violating PATCH), attempt the transaction that violates a declared constraint. It must be REJECTED with the verified shape:

```
HTTP 400, body errors[0].code == "2001",
title == "Customer balance (9000.0000000000) exceeds credit limit (5000.0000000000)"
```

(same observable as P3 — that identity IS the point: the rule fires regardless of who calls). Capture the refusal into the migration record. If the MCP live-LLM leg is unavailable (no key), the bridge-or-curl variant of the violating write through `:5656` satisfies the gate; label the MCP leg "to-execute."

**If you see X instead →**
- The violating write SUCCEEDS through the new channel → it did not go through the API/session (see Wrong Paths, raw SQL) or the rule regressed → re-run the P3 gate directly, then debugging-playbook rows 7/9.
- MCP discovery 404 → the project predates MCP scaffolding or discovery not wired → integration-patterns (MCP section).
- `genai*` commands fail immediately → missing `APILOGICSERVER_CHATGPT_APIKEY` → debugging-playbook row 16.
- 401/422 from the bridge → token handling → debugging-playbook rows 4–6.

**Rollback note.** Path A adds files/rows (SysMcp) — revert via git + a DB restore. Path B lives entirely in workbooks — keep the corrected function in source control as text (never only inside `.xlsm`), or the campaign recreates defect #5.

---

## P7 — Containerize + operate

**Objective.** The same project, containerized, passing the same suite. Detail owner: **apilogicserver-operate-and-deploy** (§5 containers, §6 deploy targets, §7 ops checklist).

**Exact commands** (project root; script content verified on disk 2026-08-23 — execution of the build was NOT performed in this workspace):

```bash
# Edit devops/docker-image/build_image.sh first: it defaults to
#   projectname="basicdemo"  repositoryname="apilogicserver"  version="1.0.0"
# (verified file content) — change repository/name to yours ("lower case, only").
sh devops/docker-image/build_image.sh .        # "." = use the script's defaults
sh devops/docker-image/run_image.sh            # then re-probe P2's GATE against the container
```

Shipped compose variants (verified on disk under `devops/`): `docker-image/`, `docker-standard-image/`, `docker-compose-dev-local/`, `docker-compose-dev-local-nginx/`, `docker-compose-dev-azure/`, `auth-db/`, `keycloak/`, `python-anywhere/`. Configuration enters containers via `env.list` / `APILOGICPROJECT_*` env vars (**apilogicserver-cli-and-config**); production serving uses gunicorn (`api_logic_server_run:flask_app` — operate-and-deploy §5.5). Cloud targets (Azure, PythonAnywhere): per docs, not live-verified — operate-and-deploy §6.

**Ops checklist** (run per environment; full version operate-and-deploy §7): banner + boxed URL on start; login returns `access_token`; authenticated GET returns rows; logs landing in `logs/als.log`; port/host set explicitly; sample credentials replaced (P4); DB file/volume backed up before each release.

**GATE — labeled to-execute (not live-verified here; no container was built or run in this workspace).** The container serves `:5656` (or your mapped port) such that: (1) P2's banner/GET gate passes against the container; and (2) the P5 Behave suite, pointed at the containerized server, runs green with the same counts as the host run. Do not call the campaign deployed until this gate has actually been executed and captured.

**If you see X instead →** build fails → operate-and-deploy §5.1; container up but port unreachable → port mapping / `APILOGICPROJECT_PORT` → operate-and-deploy §1.5–§1.6; suite fails only in the container → env delta (env.list, DB path, `PYTHONHASHSEED`) → validation-and-qa + cli-and-config.

**Rollback note.** Containers are disposable; the image tag is the rollback unit. Never fix a container by editing files inside it — fix the project, rebuild, re-gate.

---

## Solution menu (ranked)

| Rank | Option | What it is | Effort | Risk | Theory obligations | Status |
|---|---|---|---|---|---|---|
| A | **Full ALS adoption** | P0→P7 as written; Excel retired or demoted to a viewer | Days→weeks (schema + rules + scenarios dominate) | Low–medium: every step above rides the verified path | None new — all mechanisms verified end-to-end in this workspace | Verified path (P0–P6 executed 2026-08-23/25; P7 to-execute) |
| B | **Hybrid Excel bridge** | A is a prerequisite; Excel keeps thin read-mostly calls to the governed API (P6 Path B) | A + small | Medium: VBA JSON assembly stays fragile on any write path; token distribution to workbooks needs a story | Prove bridge writes safe or forbid them; JSON parsing via a maintained VBA library only | Candidate — snippet reviewed, never executed |
| C | **GenAI re-create from natural language** | `als genai`-family creates schema+rules from NL prompts (docs example prompt: "Give a 10% discount for carbon-neutral products for 10 items or more.") | Potentially lowest | Highest variance: LLM-dependent; requires `APILOGICSERVER_CHATGPT_APIKEY`; output quality unguaranteed | ALL generated output still passes P3 and P5 gates unchanged (failure-archaeology A10 guard); guardrails in **apilogicserver-genai-development** | Per docs, not live-verified here |

Decision rule: choose A; add B only for user-facing continuity and only read-mostly; use C as an accelerator for A's P2–P3 drafting, never as a substitute for the gates.

## Fenced wrong paths (each with why and evidence)

1. **Re-hand-rolling JSON parsing anywhere** — in VBA, Python, or a "quick" script. Exhibit: the legacy `Do While` `InStr` loop (quoted in P0), with four enumerated failure modes (escaped-`\\"` overrun, format drift → silent garbage, error bodies parsed as success, un-decoded escapes) — failure-archaeology A9. Use JSON parsers against the typed contract (**apilogicserver-api-contract**).
2. **Client-side business logic** — in the workbook, the bridge, or any consumer. Evidence: defect #5 (per-copy drift, ungoverned) and the architecture invariant that logic must be shared across every access path (**apilogicserver-architecture-contract**). One rule server-side replaces N client copies.
3. **Raw SQL writes around the ORM.** Rules run only in the SQLAlchemy `before_flush`; direct SQL yields stale sums and silent constraint bypass — debugging-playbook row 9; invariant in architecture-contract. All writes go through the API/session.
4. **Skipping the Behave gates** ("it looks right in the admin app"). The admin app shows a state, not a proof; the evidence bar is predicted-numbers scenarios plus the Logic Report — **apilogicserver-validation-and-qa** §1.
5. **Trusting AI output without the P5 gate.** "5 rules become 200 lines ... hard to spot, but fatal to data integrity" (per docs; failure-archaeology A5/A10). AI output is a proposal; the gates decide.
6. **Editing regenerated files** (`database/models.py` and friends) instead of the owned customization points. A rebuild clobbers you — change-control §3 clobber table; failure-archaeology A6.

## Promotion protocol

1. **One phase at a time, in order.** A phase begins only when the previous phase's gate artifact is captured (command output pasted into the migration record, committed).
2. **Every landing goes through apilogicserver-change-control**: classify the change (its §2), respect regenerated-vs-owned (§3), run the rebuild runbook if schema moved (§4), pass the standing gates and PR checklist (§7). No phase of this campaign is exempt, including test-only and docs-only phases.
3. **Success is measured by the gates, never judged by eye.** The campaign's acceptance statement is exactly: P0 table complete; P1 version banner; P2 banner + authenticated rows; P3 predicted 400/2001 + logic-log chain + control; P4 401 shape + role-count delta + credential plan; P5 zero-failed suite + report file; P6 rejected violating write through the new channel; P7 container-green suite (to-execute until run).
4. **Deviations become ledger entries.** Any new failure mode, surprise, or settled argument discovered during the campaign is recorded in **apilogicserver-failure-archaeology** ("How to add an entry") — so the next migration does not re-fight it.
5. **The legacy artifact is retired, not deleted**: keep `turbo3.5_excel_vba` in the repo as the before-picture; the P0 table plus the P6 refusal capture are the after-picture.

## Provenance and maintenance

Volatile facts and a one-line re-verification for each (run in any project unless noted):

- Installed version + welcome banner: `als welcome` → expect `Welcome to Genai-Logic 17.03.19` (version will drift; re-stamp labels when it does).
- CLI command inventory (incl. `genai-add-mcp-client`): `als --help`.
- `add-auth` flag spelling (dash vs underscore): `als add-auth --help` (help prints `--db-url`; `--db_url=auth` verified by execution).
- Created top-level tree: `als create --project-name=scratch --db-url=sqlite:///scratch.sqlite && ls scratch` (then delete `scratch`).
- Startup banner + port-collision message: `python api_logic_server_run.py` from a project root (second concurrent start reproduces "Port 5656 is in use by another program").
- Login/token and 401 shapes: `curl -s -X POST http://localhost:5656/api/auth/login -H 'Content-Type: application/json' -d '{"username":"admin","password":"p"}'`; then any `/api/<Type>/` GET without a header → `{"msg":"Missing Authorization Header"}`.
- The 5-rule template: `sed -n '55,80p' logic/declare_logic.py` in a post-`add-cust` basic_demo.
- Constraint 400 / code 2001 with chained numbers: run the P3 probe PATCH in a scratch project and read the body + console.
- 17.03.19 constraint-logging TypeError (open bug): `grep -n "splitlines" config/server_setup.py` → `result.splitlines('\n')` near line 203 means still present.
- Behave golden counts (7 features / 26 scenarios / 83 steps, ~1.4s) and report: `cd test/api_logic_server_behave && python behave_run.py --outfile=logs/behave.log` (summary on console) then `python behave_logic_report.py run` → `reports/Behave Logic Report.md`.
- MCP discovery endpoint: `curl -s http://localhost:5656/.well-known/mcp.json` → JSON with `base_url`, `description`, `learning`.
- Docker script defaults: `head -15 devops/docker-image/build_image.sh` → `projectname=`, `repositoryname=`, `version=`.
- Legacy exhibit unchanged: `wc -l turbo3.5_excel_vba` → 44; `git log --oneline -- turbo3.5_excel_vba api_Key.xlsm | wc -l` → 2 (scoped to the legacy files, re-verified 2026-08-26 — the repo's total commit count grows with this skill library).

Grounded in: https://apilogicserver.github.io/Docs/Sample-Basic-Demo/, https://apilogicserver.github.io/Docs/Tutorial/, https://apilogicserver.github.io/Docs/Integration-MCP/, https://apilogicserver.github.io/Docs/Tech-DSL/ and a live Genai-Logic 17.03.19 install (2026-08-23; live server re-probed 2026-08-25) — verified against a live install in this workspace's scratchpad reference projects.
