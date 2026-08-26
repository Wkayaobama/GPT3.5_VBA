---
name: apilogicserver-research-methodology
description: >-
  The discipline that turns a hunch about API Logic Server (Genai-Logic)
  behavior into an accepted result: the strict evidence bar (one mechanism
  explains ALL observations including negatives, and survives assigned
  adversarial refutation), the predict-numbers-first protocol and its
  Hypothesis/Mechanism/Predicted-numbers/Observed/Verdict template, the idea
  lifecycle (hunch, framed hypothesis, sandbox experiment, Behave-green with a
  rejection scenario, adopted via change control or retired to failure
  archaeology), and a five-recipe proof toolkit (transaction-trace proof,
  dependency-graph derivation, black-box contract probe, performance mechanism
  check, golden-suite regression ratchet). Use when deciding if a claim is
  proven vs plausible, designing a discriminating experiment, facing surprises
  ("engine seems broken", "constraint didn't fire but data changed"), judging
  a benchmark or architecture proposal, assigning or performing a refutation
  pass, or deciding whether an experiment may leave the sandbox.
---

# API Logic Server Research Methodology

## Purpose

This skill defines how a claim about an API Logic Server (ALS, installed as Genai-Logic) system earns the word "verified": the evidence bar, the predict-numbers-first protocol, the lifecycle every idea must walk, and five first-principles proof recipes — each demonstrated with a real investigation from this workspace's history. Follow it and a mid-level engineer or an AI model produces results a stranger can check; skip it and you produce plausible stories that later cost days. Wrong runbooks are worse than none, and this is the skill that keeps the other seventeen honest.

## Use this skill when

- You are about to conclude anything from a surprising observation ("the engine is broken", "the rule silently failed", "this is faster/slower").
- You must design an experiment that can *discriminate* between two explanations, not just illustrate one.
- Someone presents a mechanism story and you must decide: accepted, plausible, or rejected.
- You are assigned (or assigning) an adversarial refutation pass on a claim.
- An idea wants to move from "tried it in a scratch project" to "in the product" — this skill hands it to **apilogicserver-change-control** only after the bar is met.
- You need to write down a result so a future zero-context reader can trust it (labels, templates, archaeology entries).

## Do NOT use this skill when

- You need the *mechanics* of running the Behave suite, adding scenarios, or reading the Behave Logic Report → **apilogicserver-validation-and-qa** owns that; this skill only uses the suite as an instrument.
- You have a live failure and need symptom→fix triage → **apilogicserver-debugging-playbook** (its "discriminating experiment" section is an application of this skill).
- You want the history of settled battles or the entry format for recording one → **apilogicserver-failure-archaeology**.
- You want to know *what* is currently open/unproven and how results are positioned externally → **apilogicserver-research-frontier**.
- You want rule semantics (watch/react/chain, pruning, adjustment theory) → **declarative-rules-reference**; rule authoring → **apilogicserver-logic-patterns**.

## 0. Terms used once, defined once

- **Claim** — a falsifiable statement about system behavior ("the credit constraint fires on any Item change that raises balance past the limit").
- **Mechanism** — the causal story behind a claim, stated in terms of engine semantics (rules, pruning, adjustment, phases), not vibes.
- **Negative observation** — a case where something did NOT happen (a rule did not fire, a request did not fail). Mechanisms must explain these too; they are where naive stories die.
- **Discriminating experiment** — one whose predicted outcomes DIFFER under the competing hypotheses, so the result rules at least one out.
- **Logic log** — the per-transaction trace ALS writes via the `logic_logger` (per docs, Logic-Debug: a standard Python logger; `info` traces rule execution, `debug` adds declared-rule detail). Rows appear with old→new values as `[old-->] new`, indentation showing multi-table chaining, then a "These Rules Fired" summary. Format verified 2026-08-23, Genai-Logic 17.03.19.
- **Sandbox** — a scratch project created with `als create`, disposable, never the project of record.
- **Refutation pass** — a second person or agent explicitly tasked to break a mechanism story using the same artifacts.

---

## 1. THE EVIDENCE BAR (strict)

> **A claim is ACCEPTED when exactly one proposed mechanism explains ALL observations — including the negatives — and has survived an assigned adversarial refutation. Anything less is PLAUSIBLE, and is labeled as such.**

Corollaries, non-negotiable:

1. A mechanism that explains only the positive cases is a story, not a result.
2. An expectation written *after* seeing the output is documentation, not evidence (§2).
3. "Verified" in writing always carries a date and version (`verified 2026-08-23, Genai-Logic 17.03.19`); docs-derived facts carry `per docs, not live-verified`. Never blend the two in one unlabeled sentence.
4. This bar governs accepting a *mechanism/claim*. The sibling bar in **apilogicserver-validation-and-qa** governs declaring a *change done* (Behave scenario with predicted numbers + Logic Report section). Meet both when a research result becomes a shipped change.

### 1.1 Worked example — the constraint-didn't-fire investigation (this workspace, 2026-08-23)

Setting: the `basic_demo` project (created via `als create --project-name=basic_demo --db-url=basic_demo`, then `als add-cust`, `als add-auth --db_url=auth`). Its check-credit logic, verbatim from `logic/declare_logic.py` (verified 2026-08-23, Genai-Logic 17.03.19):

```python
Rule.constraint(validate=Customer, as_condition=lambda row: row.balance <= row.credit_limit,
                error_msg="Customer balance ({row.balance}) exceeds credit limit ({row.credit_limit})")
Rule.sum(derive=Customer.balance, as_sum_of=Order.amount_total, where=lambda row: row.date_shipped is None)
Rule.sum(derive=Order.amount_total, as_sum_of=Item.amount)
Rule.formula(derive=Item.amount, as_expression=lambda row: row.quantity * row.unit_price)
Rule.copy(derive=Item.unit_price, from_parent=Product.unit_price)
```

Seed rows involved (re-verified by reading `database/db.sqlite` 2026-08-25):

| Row | Key facts | Verification |
|---|---|---|
| Item 1 | order 1, quantity 1, unit_price 150, amount 150 | verified 2026-08-25 |
| Order 1 | customer 2 (Bob), `date_shipped='2023-03-22'` (SHIPPED), amount_total 150 | verified 2026-08-25 |
| Customer 2 (Bob) | balance **0**, credit_limit 3000 | verified 2026-08-25 |
| Item 2 | order 2, quantity 1, unit_price 90, amount 90 | verified 2026-08-25 |
| Order 2 | customer 1 (Alice), `date_shipped=None` (UNSHIPPED), amount_total 90 | verified 2026-08-25 |
| Customer 1 (Alice) | balance 90, credit_limit 5000 | verified 2026-08-25 |

**Observation (the surprise).** The Phase-1 investigation PATCHed Item 1 with an absurd quantity (50,000). The server returned success; `amount` recomputed to **7,500,000** (= 50,000 × unit_price 150 — arithmetic checks against the seed values above); Bob's balance did not move; no 400. (Investigation record, 2026-08-23; the same-shape PATCH with quantity 100 on Order 1 is recorded verbatim in the workspace ground-truth brief as "SUCCEEDS".)

**Naive hypothesis H1: "the engine is broken — the credit constraint doesn't fire."** H1 explains the surprise. The bar says: does it explain everything, and what would refute it?

**Refutation-oriented design.** If H1 (engine broken) were true, the same PATCH against an *unshipped* order would also pass. If instead the mechanism is **H2 — the sum is qualified: `where=lambda row: row.date_shipped is None`, so shipped orders are simply not part of `balance`** — then the unshipped-order PATCH must fail, with numbers computable in advance:

> PREDICTED (written before the run): PATCH Item 2 `quantity` 1→100 → formula: amount = 100 × 90 = 9000 → Order 2 amount_total 90→9000 → Alice balance 90→9000 → 9000 > credit_limit 5000 → **HTTP 400**, error text containing **9000** and **5000**.

**Execution.** (Login per **apilogicserver-security-model**; `$TOKEN` is the bearer token.)

```bash
curl -s -X PATCH "http://localhost:5656/api/Item/2/" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{ "data": { "attributes": { "quantity": 100 }, "type": "Item", "id": "2" } }'
```

**Observed** (verified 2026-08-23, Genai-Logic 17.03.19 — captured verbatim):

```json
{"errors": [{"title": "Customer balance (9000.0000000000) exceeds credit limit (5000.0000000000)",
  "detail": {"model": "Customer", "error_attributes": []}, "code": "2001"}]}
```

HTTP 400. The prediction matched **to the digit** — `9000.0000000000` in the error title.

**Verdict.** H1 is dead: the constraint demonstrably fires. H2 explains ALL observations, including the negatives:

| # | Observation | H1 "engine broken" | H2 "qualified sum excludes shipped orders" |
|---|---|---|---|
| 1 | Item 1 (shipped order) PATCH succeeds, amount 7,500,000, balance unmoved | explains | explains — shipped order is outside the sum, so no balance change is **correct behavior, not a bug** |
| 2 | Item 2 (unshipped order) PATCH → 400 with 9000 vs 5000 | **cannot explain** | explains, predicted the digits |
| 3 | Bob's stored balance is 0 while he owns shipped Order 1 worth 150 (static fact, verified 2026-08-25) | cannot explain (why 0, not 150?) | explains — shipped orders never counted |

One mechanism, all observations, negatives included. The result and the reusable moral ("a qualified aggregate not changing is the rule working") are recorded where they belong: **apilogicserver-failure-archaeology** entry A4 cites this as the canonical discriminating experiment, and **apilogicserver-debugging-playbook** carries it as the triage for "my constraint did not fire". Case closed.

**State restoration note:** the shipped-order PATCH *committed* (that was the point). The investigation restored the rows afterward; the seed-value table above was re-read from the database on 2026-08-25 and matches the original seed. An experiment that mutates state is not finished until state is restored or the mutation is documented.

---

## 2. PREDICT-NUMBERS-FIRST

**Protocol: before any experiment runs, write down the expected values — balances, counts, HTTP status codes, error-text fragments, and the list of rules you expect to fire (and to be pruned). Then run. An expectation written after the run is documentation, not evidence.**

Why this is unusually powerful in ALS specifically: the engine is arithmetic all the way down. Derivations are sums/counts/formulas over declared columns; the logic log prints every old→new value to ten decimal places; adjustments move parents by exact child deltas (**declarative-rules-reference** owns the theory). So predictions are cheap to compute by hand and matches are exact — "matched to the digit" is a routinely achievable standard, and any mismatch localizes the misunderstanding immediately.

### 2.1 The template (copy this block into your notes for every experiment)

```text
EXPERIMENT: <short name>                                   DATE / VERSION: <date> / <als welcome output>
HYPOTHESIS: <the claim under test, falsifiable>
MECHANISM:  <the engine-semantics story that would make it true>
PREDICTED NUMBERS (written BEFORE running):
  - values:      <e.g. amount 100*90=9000; amount_total 90->9000; balance 90->9000>
  - HTTP:        <e.g. 400, code 2001, title contains "9000" and "5000">
  - rules fired: <e.g. Formula Item.amount; Sum Order.amount_total; Sum Customer.balance; Constraint>
  - rules NOT fired (and why): <e.g. Copy unit_price - product_id unchanged>
COMMAND(S): <copy-pasteable curl / behave / grep>
OBSERVED:   <paste raw output or artifact path>
VERDICT:    MATCHED / MISMATCHED (per line item) -> ACCEPTED | PLAUSIBLE | REFUTED
STATE:      <mutations made and how restored>
ARCHAEOLOGY ENTRY? <yes -> A<n> in apilogicserver-failure-archaeology | no, why not>
```

### 2.2 Predicted-delta arithmetic, demonstrated from a real trace

The certified suite's rejection scenario "Alter Item Qty to exceed credit" (Northwind sample, `nw+`) PATCHes OrderDetail 1040 (Order 10643, customer ALFKI) quantity 15→1110. Hand prediction: new Amount = 1110 × 45.60 = **50,616**; child delta = 50,616 − 684 = **49,932**; AmountTotal 1,086 + 49,932 = **51,018**; Balance 2,102 + 49,932 = **52,034** > CreditLimit 2,300 → constraint failure. The captured scenario logic log (artifact generated 2026-08-23, Genai-Logic 17.03.19) shows exactly: `Quantity:  [15-->] 1110`, `Amount:  [684.0000000000-->] 50616.0000000000`, `AmountTotal:  [1086.00-->] 51018.0000000000`, `Balance:  [2102.0000000000-->] 52034.0000000000`, then `{Constraint Failure: balance (52034.00) exceeds credit (2300.00)}`. Every parent moved by exactly the child delta — which is also the fingerprint of adjustment (T4). Seed values ALFKI Balance 2102.0 / CreditLimit 2300.0 re-confirmed against the live API 2026-08-25.

---

## 3. THE IDEA LIFECYCLE (state machine)

Every idea — a new rule pattern, a performance claim, a proposed engine swap, an AI-suggested rule — walks these states in order. **No idea skips to Adopted.**

| State | Entry requirement | Exit criteria | Owner skill for mechanics |
|---|---|---|---|
| S0 Hunch | none — free text in notes | someone frames it | (this skill) |
| S1 Framed hypothesis | §2.1 template filled through PREDICTED NUMBERS | experiment designed to discriminate, not illustrate | (this skill) |
| S2 Sandbox experiment | a scratch project or clearly-flagged experiment file (§3.1); NEVER the project of record | template's OBSERVED + VERDICT filled; toolkit recipe(s) from §4 applied | **apilogicserver-cli-and-config** for `als create` |
| S3 Behave-certified | rule/behavior expressed as Behave scenarios, **green, including at least one rejection/adversarial scenario** (a scenario asserting the bad transaction is refused with the predicted error) | full suite green; Behave Logic Report section shows the intended rules fired | **apilogicserver-validation-and-qa** |
| S4a Adopted | survived an assigned refutation pass (§5) for significant claims | merged ONLY through **apilogicserver-change-control** gates | **apilogicserver-change-control** |
| S4b Retired | refuted, or abandoned with reasons | strict-format entry written in **apilogicserver-failure-archaeology** so nobody re-fights it | **apilogicserver-failure-archaeology** |

Transitions: S2 failure → back to S1 (reframe) or straight to S4b (record the dead end — a well-documented retirement is a first-class result; archaeology entry **A1, the Rete rejection, is the exemplar**: claim, investigation, mechanism-level reasons, evidence links, SETTLED status with reopening conditions). A refuted claim never lingers as folklore; it gets an entry or it will be re-proposed.

### 3.1 Sandbox rules (where experiments live)

1. **Default sandbox = a scratch project**: `als create --project-name=exp_<topic> --db-url=basic_demo` (or `nw+` when you need the rich sample). Disposable by construction.
2. **Experiment files inside a sandbox**: put candidate rules in `logic/logic_discovery/exp_<topic>.py` (same `declare_logic()` shape as any discovery file — **apilogicserver-logic-patterns** owns the template). The `exp_` prefix is **THIS LIBRARY's convention** for at-a-glance identification and `grep`-ability — it is not an upstream ALS convention.
3. **Critical fact — discovery makes files LIVE**: `logic/logic_discovery/auto_discovery.py` imports **every** `*.py` in that folder except itself and `__init__.py` (code-verified 2026-08-25, Genai-Logic 17.03.19: `if file.endswith(".py") and file not in ["auto_discovery.py", "__init__.py"]`). Therefore an `exp_*.py` file dropped into a real project's `logic_discovery/` is on the main path immediately. **Never place `exp_*.py` in the project of record.**
4. **Disable-by-rename precedent**: the shipped Northwind sample itself parks a discovery file by renaming it off the `.py` suffix — `logic/logic_discovery/workflow_integration.pyZZ` exists on disk (verified 2026-08-25). Renaming `exp_<topic>.py` → `exp_<topic>.pyZZ` deactivates it without deleting evidence.
5. Startup proof of what's active: the server logs `..discovered logic: [...]` at boot — check it before trusting any experiment ran.

---

## 4. PROOF TOOLKIT — five first-principles recipes

### T1 — Transaction-trace proof

**Purpose:** prove a specific transaction did exactly what the declared logic intends — every fired rule matches an intent, every non-fired rule matches pruning semantics — using the logic log as the primary instrument.

**Procedure:**
1. Predict (§2.1): values, rules fired, rules pruned.
2. Drive ONE transaction (curl PATCH/POST per **apilogicserver-api-contract**, or a single Behave scenario).
3. Capture the trace: from a Behave run, per-scenario logs land in `test/api_logic_server_behave/logs/scenario_logic_logs/<Scenario_name>.log` (one file per scenario — the per-claim evidence trail; verified 2026-08-23). From an ad-hoc curl, read the server console / `logs/als.log`.
4. Audit line by line: each `{Formula ...}` / `{Adjusting ...}` / `{Constraint ...}` line against a declared rule; each `{Prune ...}` line against its reason; anything unexplained → the claim is not proven.

**Worked example** (scenario `Alter_Item_Qty_to_exceed_.log`, artifact of the certified run, 2026-08-23, Genai-Logic 17.03.19 — abbreviated, indentation is chaining depth):

```
..OrderDetail[1040] {Update - client} ... Quantity:  [15-->] 1110, Amount: 684.0000000000 ...
..OrderDetail[1040] {Prune Formula: ShippedDate [['Order.ShippedDate']]} ...
..OrderDetail[1040] {Formula Amount} ... Amount:  [684.0000000000-->] 50616.0000000000 ...
....Order[10643] {Update - Adjusting Order: AmountTotal} ... AmountTotal:  [1086.00-->] 51018.0000000000 ...
....Order[10643] {Prune Formula: OrderDate [[]]} ...
......Customer[ALFKI] {Update - Adjusting Customer: Balance} ... Balance:  [2102.0000000000-->] 52034.0000000000, CreditLimit: 2300.0000000000 ...
......Customer[ALFKI] {Constraint Failure: balance (52034.00) exceeds credit (2300.00)} ...
These Rules Fired (see Logic Phases, above, for actual order):
  Customer
    ...
    4. Derive <class 'database.models.Customer'>.Balance as Sum(Order.AmountTotal Where where=lambda row: row.ShippedDate is None and row.Ready == True) ...
```

The audit that makes it a *proof*, not a screenshot:

| Log line | Explained by | Check |
|---|---|---|
| `{Formula Amount}` 684→50616 | `Rule.formula(derive=OrderDetail.Amount, as_expression=lambda row: row.UnitPrice * row.Quantity)` — Quantity changed, so it must fire; 1110×45.60=50,616 | fired, value exact |
| `{Prune Formula: ShippedDate [['Order.ShippedDate']]}` | OrderDetail.ShippedDate is a formula referencing parent `Order.ShippedDate`; that parent attribute did not change → prune is correct | correctly NOT fired |
| `{Adjusting Order: AmountTotal}` +49,932 | unqualified `Rule.sum(derive=Order.AmountTotal, as_sum_of=OrderDetail.Amount)` — child delta applied | one-row adjustment, delta exact |
| `{Prune Formula: OrderDate [[]]}` | OrderDate formula references no changed attributes (empty reference list logged) | correctly NOT fired |
| `{Adjusting Customer: Balance}` +49,932 | qualified sum; Order 10643 has `ShippedDate: None, Ready: True` → inside the qualification, so the delta propagates | fired, delta exact |
| `{Constraint Failure}` 52,034 > 2,300 | constraint watches Balance; Balance changed → must be checked | fired, txn rolled back |
| Copy `UnitPrice` absent from trace | `Rule.copy` fires on insert or parent-key change; ProductId unchanged | correctly NOT fired |

Every line accounted for, positives and negatives. That is the T1 standard. (Phase headers `ROW LOGIC` / `COMMIT LOGIC` / `AFTER_FLUSH` and `[old-->] new` notation: **declarative-rules-reference**; raising `logic_logger` verbosity and breakpoints inside rule lambdas: **apilogicserver-debugging-playbook**, per docs Logic-Debug.)

### T2 — Dependency-graph derivation

**Purpose:** verify the engine's declared-dependency understanding matches yours, *before* running anything — catching wrong-column and missing-FK errors at startup rather than in production.

**Procedure:**
1. From the rule declarations, hand-derive: for each derived attribute, which attributes it watches (arguments of formulas, summed columns, `where`-clause columns, FK columns, constraint operands).
2. Start (or read the log of) the server: at startup the engine prints each rule under "The following rules have been activated" and each watched attribute under "The following attributes have been referenced".
3. Diff your table against the listing. Any watch you predicted that is absent, or vice versa, is a defect in the rules or in your understanding — resolve before trusting any run.

**Worked example** — from `logic/logic_discovery/order_place/check_credit.py` in the Northwind sample (rule source verbatim, verified 2026-08-25):

```python
Rule.sum(derive=Customer.Balance, as_sum_of=Order.AmountTotal,
    where=lambda row: row.ShippedDate is None and row.Ready == True)
```

Hand-derivation: `Customer.Balance` must watch `Order.AmountTotal` (summed column), `Order.ShippedDate` and `Order.Ready` (qualification), plus the FK reassignment; the constraint watches `Customer.Balance` and `Customer.CreditLimit`. The startup listing (verbatim lines from `logs/als.log`, verified 2026-08-25, Genai-Logic 17.03.19):

```
..Customer.Balance: constraint
..Customer.CreditLimit: constraint
..Customer.Balance: aggregate derivation
..Order.ShippedDate: aggregate where clause
..Order.Ready: aggregate where clause
..Order.AmountTotal: sum derived from
..Order.AmountTotal: aggregate derivation
..OrderDetail.Amount: sum derived from
..OrderDetail.UnitPrice: parent copy derivation
..Product.UnitPrice: parent copy from
```

Every hand-derived edge appears, with its role named (`aggregate where clause`, `sum derived from`, `parent copy from`). Re-verify any time: `grep "aggregate where clause" logs/als.log`.

### T3 — Black-box contract probe

**Purpose:** assert wire-level invariants with curl, independent of any code reading — the outside-in check that the system's contract holds. (Full API grammar: **apilogicserver-api-contract**.)

**Procedure:** for each invariant, one copy-pasteable command and one expected shape; run all after any change to auth, API, or config. In this environment always add `--noproxy '*'` if a corporate proxy intercepts localhost.

| Invariant | Command (project running on :5656, security on) | Expected — verbatim | Verification |
|---|---|---|---|
| Unauthenticated GET is refused | `curl -sg "http://localhost:5656/api/Customer/?page[limit]=1"` | `{"msg":"Missing Authorization Header"}` (HTTP 401) | verified 2026-08-25, Genai-Logic 17.03.19 |
| Login yields a bearer token | `curl -s -X POST http://localhost:5656/api/auth/login -H "Content-Type: application/json" -d '{"username":"admin","password":"p"}'` | JSON containing `access_token` | verified 2026-08-25 |
| Every row carries an optimistic-lock checksum | authorized `GET /api/Category/?page[limit]=1` → inspect `data[0].attributes` | `S_CheckSum` present (64-hex string) | verified 2026-08-25 |
| Constraint rejection shape | the §1.1 PATCH | HTTP 400, `errors[0].code == "2001"`, `title` = the rule's `error_msg` with interpolated numbers | verified 2026-08-23 |

**Evidence-discipline caveat (known bug):** in 17.03.19, when a constraint violation is logged the server *console* may show a `TypeError: 'str' object cannot be interpreted as an integer` stack trace from the logging machinery (`config/server_setup.py`, `short_format_exception`, `result.splitlines('\n')` — archaeology entry **A8**, OPEN). The wire response is still a correct 400 and the rollback is correct (verified 2026-08-23). T3 therefore trusts the *wire* and the *scenario logic logs*, never the console's prettiness.

### T4 — Performance mechanism check (adjustment vs re-aggregation)

**Purpose:** demonstrate — not assert — that aggregates are maintained by one-row delta adjustment, not `SELECT SUM` over children. This is the mechanism that settled the aggregate-performance wall (**apilogicserver-failure-archaeology** A4; docs claim "minutes to 2 seconds", per docs FAQ-RETE).

**The real knob (report of exactly what is in a 17.03.19 project, verified 2026-08-25):**
- `config/config.py` line 222 contains `# SQLALCHEMY_ECHO = environ.get("SQLALCHEMY_ECHO")` — present but **commented out**; the only other occurrence (line 22) sits inside a module docstring. There is **no live `SQLALCHEMY_ECHO` switch** in the generated config.
- The project-native knob is `config/logging.yml`: it ships a `sqlalchemy.engine:` logger stanza whose `level: DEBUG` line is commented out (handlers `[console, file]` already wired). Uncommenting `level: DEBUG` under `sqlalchemy.engine:` turns on SQL echo. (`logic_logger` ships at `level: DEBUG`; an `engine_logger` stanza also exists with DEBUG commented.) Requires a server restart — **apilogicserver-operate-and-deploy** owns run mechanics.

**Procedure — CANDIDATE (knobs verified on disk; this exact run not executed in this workspace):**
1. In a sandbox project, uncomment `level: DEBUG` under `sqlalchemy.engine:` in `config/logging.yml`; restart.
2. Predict FIRST (§2): one Item-quantity PATCH should emit `UPDATE` statements for the item, its order, and its customer — each keyed by primary key — and **zero** `SELECT SUM(...)`/`GROUP BY` statements against item or order tables.
3. Run the §1.1 PATCH; grep the SQL echo for `SUM(`.
4. Verdict: absence of aggregate queries + per-PK parent UPDATEs = adjustment confirmed; any `SELECT SUM` on the derivation path refutes it.
(Generic SQLAlchemy alternative — engine `echo=True` — per docs, not live-verified.)

**Already-verified corroboration you can cite today:** (a) the T1 trace shows both parents moving by exactly the child delta 49,932 — re-aggregation would recompute totals, not apply deltas; (b) live stack traces expose the adjustment call path `logic_bank/exec_row_logic/logic_row.py` `_adjust_parent_aggregates()` → `save_altered_parents(do_not_adjust_list=...)` → `_constraints()` (verified 2026-08-23, Genai-Logic 17.03.19); (c) the startup rule listing prints the vendor's own annotation `# adjusts - *not* a sql select sum...` on the Balance rule (verified 2026-08-25).

### T5 — Golden-suite regression ratchet

**Purpose:** use the certified Behave suite as the invariant-preservation instrument: after ANY accepted change, the whole behavioral surface is re-proven in seconds, and the pass-counts act as a ratchet.

**The ratchet (policy):** the certified baseline is **7 features / 26 scenarios / 83 steps, 0 failed, ~1.4s** (nw+ sample; verified 2026-08-23, Genai-Logic 17.03.19). Counts may only move *consciously*: a new behavior adds scenarios (counts go up, recorded in the change's PR); counts going down or any failure without a corresponding conscious decision = regression, full stop. Run from the project root, server already running:

```bash
cd test/api_logic_server_behave && python behave_run.py --outfile=logs/behave.log
python behave_logic_report.py run   # writes reports/"Behave Logic Report.md"
```

The report ("created during test suite execution", per docs Behave-Logic-Report) interleaves each scenario's Gherkin, its "Rules Used", and its captured logic log — a T1 trace per scenario, machine-generated. Suite mechanics, scenario authoring, seeds, and restoration truth: **apilogicserver-validation-and-qa** (which also owns the "change is done" evidence bar). This skill's use of the suite: an idea reaches S3 only when its scenarios — including at least one rejection scenario — are green *inside* this instrument.

---

## 5. ASSIGNED REFUTATION

**Practice:** for any significant claim (a new mechanism story, a performance conclusion, a "this settled question should be reopened"), a second session, agent, or engineer receives the artifacts and the explicit task: **"break this mechanism story."** Surviving that pass is the acceptance signature the §1 bar requires. Self-review does not qualify — the author's blind spots travel with the artifacts.

**What the refuter receives:** the filled §2.1 template, raw command outputs or artifact paths (scenario logic logs, `logs/behave.log`, report sections), and the claimed mechanism in one paragraph. Not the author's interpretation essay.

**Refuter's checklist:**
1. Recompute every predicted number independently; any mismatch the author explained away is your first target.
2. Hunt for an observation the mechanism does NOT explain — especially negatives (rules that didn't fire, requests that didn't fail) and static facts (stored values that should differ if the mechanism were true — Bob's balance-0 check in §1.1 is the model).
3. Construct a rival mechanism that explains the same positives; then design the discriminating experiment and demand it be run.
4. Audit labels: anything marked `verified` must name date + version and be re-runnable; anything docs-derived must say `per docs, not live-verified`. Unlabeled facts are rejected as evidence.
5. Check state hygiene: did mutations get restored/documented? Could a dirty database have produced the observation?
6. Verdict in writing: SURVIVED (→ eligible for S4a via **apilogicserver-change-control**) or BROKEN (→ back to S1, or S4b with an archaeology entry).

**This library holds itself to the same bar:** the 18 skills are subject to the assigned-refutation practice above, under three lenses — (1) **live-install accuracy**: every `verified` label re-checkable against a Genai-Logic 17.03.19 install; (2) **docs fidelity**: no claim may contradict the official docs without saying so, and docs-only material is labeled as such; (3) **cross-skill consistency**: one home per fact, siblings cross-referenced by name. Trust a label only as far as it is checkable — a `verified` fact names its date and version and can be re-run; that re-runnability, not any past review, is the ground for trust. Re-verify volatile facts per each skill's Provenance section, and treat a label that fails its own re-check as BROKEN (checklist item 6).

---

## 6. Where good ideas came from

The methods above are distilled from this lineage, not invented for it. The *adjustment* insight — maintain aggregates by old/new delta instead of re-aggregating — came out of a real performance wall in the Versata-era systems and is the reason a Rete-style decision engine was evaluated and rejected for transaction logic ("decision engines cannot make presumptions about old rows"; "use the old/new delta to compute a 1-row adjustment", per docs FAQ-RETE); both the retirement and the two decades of commercial proof behind declarative transaction rules are recorded as **apilogicserver-failure-archaeology** A1–A4, and A1 is the standing exemplar of a retirement documented well enough that nobody re-fights it. The *discriminating experiment* pattern (§1.1) came from the most common real support confusion — qualified aggregates "not firing" — turned into a reusable proof. The *predict-numbers-first* habit is simply what the engine's ten-decimal logic log makes cheap, so there is no excuse not to. What remains genuinely open — unproven claims, candidate benchmarks, positioning and reproducibility standards for publishing results outside this repo — lives in **apilogicserver-research-frontier**; this skill supplies the bar any of it must clear on the way in.

---

## Provenance and maintenance

Volatile facts and a one-line re-verification command each (run from any ALS project root, venv active, server running where a URL is hit):

- Constraint-didn't-fire experiment (§1.1) end-to-end: re-run the PATCH commands in §1.1 against a fresh `als create --db-url=basic_demo` project — expect 400/`code 2001` on the unshipped-order leg, success on the shipped-order leg.
- basic_demo seed values (Item 1 qty 1/price 150; Bob balance 0/credit 3000; Alice 90/5000): `python3 -c "import sqlite3; [print(r) for r in sqlite3.connect('database/db.sqlite').execute('select id,quantity,unit_price,amount from item limit 2')]"`
- 401 shape: `curl -sg "http://localhost:5656/api/Customer/?page[limit]=1"` → `{"msg":"Missing Authorization Header"}`
- Login shape: `curl -s -X POST http://localhost:5656/api/auth/login -H "Content-Type: application/json" -d '{"username":"admin","password":"p"}'` → contains `access_token`
- `S_CheckSum` presence: authorized `GET /api/Category/?page[limit]=1`, inspect `data[0].attributes`
- Startup dependency listing lines: `grep -n "aggregate where clause\|parent copy from" logs/als.log`
- Auto-discovery loads every `.py`: `grep -n "endswith" logic/logic_discovery/auto_discovery.py`
- Disable-by-rename precedent: `ls logic/logic_discovery/ | grep pyZZ` (nw+ sample)
- Per-scenario evidence trail: `ls test/api_logic_server_behave/logs/scenario_logic_logs/` after a suite run
- Prune-line format: `grep -rn "Prune Formula" test/api_logic_server_behave/logs/scenario_logic_logs/ | head -3`
- Golden counts (7/26/83, ~1.4s): `cd test/api_logic_server_behave && python behave_run.py --outfile=logs/behave.log` and read the console summary
- T4 knobs: `grep -n "SQLALCHEMY_ECHO" config/config.py` (expect only a commented line ~222 and a docstring hit) and `grep -n -A3 "sqlalchemy.engine" config/logging.yml` (expect `# level: DEBUG`)
- Adjustment call path in stack traces: trigger a constraint 400 and read the console trace for `_adjust_parent_aggregates` (also exercises the A8 logging bug: `sed -n '200,206p' config/server_setup.py`)
- Version stamp for labels: `als welcome`

Grounded in: https://apilogicserver.github.io/Docs/FAQ-RETE/, https://apilogicserver.github.io/Docs/Behave-Logic-Report/, https://apilogicserver.github.io/Docs/Logic-Debug/ and a live Genai-Logic 17.03.19 install (2026-08-23; wire probes, config greps, seed reads, and startup-log reads re-run 2026-08-25 against the same install and its generated basic_demo / nw+ sample projects).
