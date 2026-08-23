---
name: declarative-rules-reference
description: >-
  Domain theory of API Logic Server's declarative rules engine (LogicBank): why
  declarative beats procedural for multi-table transaction logic, and exactly how
  the engine executes — watch/react/chain, phases (ROW LOGIC, COMMIT LOGIC,
  AFTER_FLUSH, COMPLETE), old_row semantics, delta-based adjustment vs SELECT SUM,
  pruning, dependency-driven ordering, and the Rete comparison. Use when someone
  asks WHY rules work this way, how execution order is decided, what
  "watch/react/chain" or "adjustment" means, why a sum does not query children,
  whether LogicBank is a Rete/inference/BRMS engine, what the logic-log phases
  mean, why "my rule/constraint didn't fire" on a qualified sum (e.g. shipped
  orders excluded), circular/cyclic rule dependency errors, "5 rules vs 200
  lines", the spreadsheet analogy, or the limits of rules (raw SQL bypass,
  cross-service transactions, rules-vs-Python events). For writing specific
  rules use apilogicserver-logic-patterns; for step-by-step debugging use
  apilogicserver-debugging-playbook.
---

# Declarative Rules Reference — how transaction logic actually executes here

## Purpose

This is the theory pack for API Logic Server's rules engine (LogicBank). It explains what declarative transaction logic is, the five failure modes of procedural logic that declaration eliminates, and the exact execution semantics of this engine — phases, chaining, adjustment, pruning, ordering — verified against a live Genai-Logic 17.03.19 install (2026-08-23), not paraphrased from a textbook. Read it before writing or debugging logic, so the engine's behavior is a model in your head instead of a surprise in your log.

**Use this skill when:**

- You need to understand or explain WHY the engine behaves as it does: execution order, chaining across tables, why an aggregate updated (or didn't).
- A rule or constraint "didn't fire" and you suspect qualification (`where=`) or pruning rather than a bug.
- You see `Logic Phase: ROW LOGIC / COMMIT LOGIC / AFTER_FLUSH LOGIC / COMPLETE` in a log and need to know what runs in each.
- Someone asks whether this is a Rete engine, a BRMS, or "just triggers", or asks for the declarative-vs-procedural argument.
- You hit a circular-dependency error at startup, or need to reason about rule ordering.
- You must judge what rules can and cannot do (raw SQL, cross-service transactions, data backfill after a rule change).

**Do NOT use this skill when:**

- You want the signature/catalog of a specific rule type or a worked pattern to copy — use **apilogicserver-logic-patterns**.
- You are triaging a live failure symptom-first — use **apilogicserver-debugging-playbook**.
- You need JSON:API call shapes beyond the one experiment here — use **apilogicserver-api-contract**.
- You are changing files, rebuilding, or merging — use **apilogicserver-change-control**.
- You want the historical battles (Rete rejection lineage, Versata ancestry, perf walls) — use **apilogicserver-failure-archaeology**; this skill covers the technical argument, that one covers the history.
- You want Behave evidence or the Logic Report — use **apilogicserver-validation-and-qa**.

Jargon used throughout, defined once: **ORM** = Object-Relational Mapper (here SQLAlchemy), which maps Python classes to tables and batches changes in a session. **Flush** = the moment SQLAlchemy converts pending session changes into SQL (before commit). **Derivation** = a rule that computes a column value (sum, count, formula, copy). **Constraint** = a rule that must hold true or the transaction is rejected. **JSON:API** = the REST convention this server speaks (`data/attributes/relationships`). **JWT** = the signed bearer token returned by login. **Rete** = the classic forward-chaining inference algorithm behind decision-rule engines (Drools etc.).

---

## 1. The premise: rules are cell formulas over your schema

Per the docs' analysis (Logic-Why — cite it as their analysis, not a measurement you made): *"For transaction systems, backend multi-table constraint and derivation logic is often nearly half the system"*, and rules typically *"automate over 95% of such logic, and are 40X more concise."* The generated project itself carries the arithmetic (verified 2026-08-23, Genai-Logic 17.03.19, in `logic/declare_logic.py` of a basic_demo project): the 5 declarative lines represent the same logic as ~200 lines of Python, and *"Consider a 100 table system: 1,000 rules vs. 40,000 lines of code."*

The canonical five (verbatim from a generated basic_demo project, verified on disk):

```python
Rule.constraint(validate=Customer, as_condition=lambda row: row.balance <= row.credit_limit,
                error_msg="Customer balance ({row.balance}) exceeds credit limit ({row.credit_limit})")
Rule.sum(derive=Customer.balance, as_sum_of=Order.amount_total, where=lambda row: row.date_shipped is None)
Rule.sum(derive=Order.amount_total, as_sum_of=Item.amount)
Rule.formula(derive=Item.amount, as_expression=lambda row: row.quantity * row.unit_price)
Rule.copy(derive=Item.unit_price, from_parent=Product.unit_price)
```

The docs' spreadsheet analogy, made precise: *"You can think of rules as conceptually similar to spreadsheet cell formulas, applied to your database."* The mapping is exact, not poetic:

| Spreadsheet | LogicBank | Consequence |
|---|---|---|
| Cell formula `=B2*C2` | `Rule.formula(derive=Item.amount, ...)` | You declare WHAT the value is, never when to compute it |
| `=SUM(range)` cell | `Rule.sum(derive=..., as_sum_of=...)` | The total is a stored column the engine keeps correct |
| Recalc order derived from cell references | Execution order derived from `row.xxx` references | No hand-ordered call graph; reordering is automatic when rules change |
| Only affected cells recalc | Pruning + delta adjustment | Unchanged inputs fire nothing; sums move by deltas |
| Formulas hold for every edit anywhere on the sheet | Rules bound to ORM flush events | One declaration covers insert, update, delete, and re-parenting via every API/app path — the docs' "design one / solve many" |

Declarative means: rules state an invariant over the schema ("the balance IS the sum of unshipped order totals"). The engine — not you — derives the execution: which transactions are relevant, in what order rules run, what SQL is issued, what can be skipped. Ordering of the 5 rules in the file is irrelevant; dependencies are discovered (Section 6).

---

## 2. The five problems with procedural logic — and the mechanism that removes each

All five are the docs' analysis (Logic-Why, Logic-Why-Declarative-GenAI); the "mechanism" column is verified against the installed engine (verified 2026-08-23, Genai-Logic 17.03.19).

| # | Problem | What goes wrong procedurally | Declarative mechanism that removes it |
|---|---|---|---|
| 1 | **Dependency tracking** | For `Customer.balance = Sum(Order.amount_total where unshipped)` you must hand-code reactions to: `amount_total` changed, `date_shipped` changed, Order inserted, Order deleted, `customer_id` (foreign key) changed. Miss one path, get silent corruption. | At activation the engine parses every rule for `row.xxx` references (`parse_dependencies` in the installed `logic_bank/rule_type/abstractrule.py` splits rule text and keeps `row.`-prefixed tokens). At runtime it compares `old_row` vs `row` attribute-by-attribute, so every change path — including foreign-key reassignment — is handled by the same declaration. |
| 2 | **Ordering** | *"Introducing a change requires archaeology: read the existing code to determine where to insert the new code"* (docs). The "where do I insert this" problem dominates maintenance. | Order is computed from dependencies at server start (Section 6). Add or change a rule anywhere; execution re-orders itself. |
| 3 | **Reuse across access paths** | Logic written in UI controllers/forms does not run for APIs, integrations, batch jobs, or the admin app. Reuse requires "careful manual design" and usually fails. | Rules bind at the architecture level — SQLAlchemy `before_flush` — so every write through the ORM is governed: JSON:API POST/PATCH/DELETE, admin app, custom endpoints, test loaders. There is no path to "forget" for code that uses the session. |
| 4 | **Optimization** | Naive code recomputes aggregates with `SELECT SUM` per transaction (docs call iterator verbs over children "poor practice"); nobody hand-writes pruning. | Delta-based one-row adjustment plus pruning (Section 4). Docs: rules are *"pruned if only a non-referenced column is altered"* and *"optimized into a 1-row adjustment update instead of an expensive SQL aggregate"*, which *"can literally result in sub-second performance instead of multiple minutes."* |
| 5 | **Silent omission** | The "code was there but not called" problem: the check exists but some path never invokes it. Omissions are unprovable in review; they surface in production. | Rules are indexed by mapped class inside the engine and fired by the ORM event, not by developer call sites. Invocation cannot be forgotten because it is never written. |

The AI angle sharpens #1 and #5 (docs' Logic-Why-Declarative-GenAI experiment, per docs): AI-generated *procedural* logic for the same use case produced ~220 lines with 2 bugs — reassigning an Order to a different Customer failed to decrement the old customer's balance, and reassigning an Item to a different Product failed to re-copy the unit price — vs 5 rules, 0 bugs. Their conclusion: *"Even a perfect LLM cannot guarantee completeness of enumerated procedural paths"*; *"AI expresses meaning; the engine guarantees correctness."* Note in Section 4 that the engine's re-parenting logic handles exactly those two bug classes structurally. See **apilogicserver-genai-development** for AI-assisted authoring guardrails.

---

## 3. Execution semantics, precisely (verified)

Everything in this section is verified 2026-08-23 against Genai-Logic 17.03.19 (bundled Logic Bank 1.32.00): by reading the installed engine source (`logic_bank/exec_trans_logic/listeners.py`, `logic_bank/exec_row_logic/logic_row.py` in the venv) and by live transactions against generated projects.

### 3.1 Binding

Rules are declared in `logic/declare_logic.py` (which auto-discovers `logic/logic_discovery/*.py`) and activated at server start. The engine registers SQLAlchemy session listeners; logic executes inside **`before_flush`** on your `session.commit()`. Consequence: logic is transactional — a constraint failure raises before anything is written, and the whole transaction rolls back.

### 3.2 Watch, react, chain

Per docs, the engine runs "much like a spreadsheet" on each inserted, updated, or deleted row:

- **Watch** — change detection at the *attribute* level: the engine keeps `old_row` (pre-change image) and compares it to `row`.
- **React** — run only the rules that reference changed attributes.
- **Chain** — reacted rules change other attributes, possibly in *other tables* (child Item.amount → parent Order.amount_total → grandparent Customer.balance), which triggers their watchers in turn.

### 3.3 The four phases

One `session.commit()` produces this verified log skeleton (see **apilogicserver-debugging-playbook** for full log-reading drills):

```
Logic Phase:   ROW LOGIC        (session=0x...) (sqlalchemy before_flush)
..Item[2] {Formula amount} id: 2, ..., quantity:  [1-->] 100, amount:  [90.0000000000-->] 9000.0000000000, ...  ins_upd_dlt: upd, initial: upd
Logic Phase:   COMMIT LOGIC     (session=0x...)
Logic Phase:   AFTER_FLUSH LOGIC (session=0x...)
These Rules Fired (see Logic Phases, above, for actual order):
    1. Derive <class 'database.models.Customer'>.balance as Sum(Order.amount_total Where ...)
Logic Phase:   COMPLETE(session=0x...)
```

Changed attributes print as `[old-->] new`. The "These Rules Fired" footer is a summary; actual order is the phase log above it.

| Phase | When | What runs (verified from listeners.py) |
|---|---|---|
| **ROW LOGIC** | Inside `before_flush`. Client-changed rows processed: updates first (SQLAlchemy's `session.dirty`), then inserts (`session.new`), then deletes (`session.deleted`). | Each row's full rule cascade (3.5), which recursively processes chained parent/child rows. |
| **COMMIT LOGIC** | Still inside `before_flush`, after ALL row cascades. | `Rule.commit_row_event` per processed row — row values are final here, so sums/counts reflect all adjustments (e.g. nw's "Empty Order - Cannot Ship" check reads `Order.OrderDetailCount`). |
| **AFTER_FLUSH LOGIC** | SQLAlchemy `after_flush` — rows are written to the database, still pre-commit. | `Rule.after_flush_row_event` (with `if_condition`/`with_args`, e.g. the Kafka send) and — in 17.03.19, verified in source — **commit constraints** (`Rule.commit_constraint`, skipped for deleted rows). DB-generated values (autoincrement keys) exist now. Do not change row values here: the flush already happened, so mutations are not persisted in this transaction. Use it for side effects only (messages, external posts — see **apilogicserver-integration-patterns**). |
| **COMPLETE** | End of cycle. | Log marker only. |

A failed transaction that re-enters flush logs `ROW LOGIC IGNORE RE-RAISE` — that is the engine refusing to re-run logic while the error propagates, not a second execution.

### 3.4 `logic_row` and `old_row`

Every processed row is wrapped in a `LogicRow` with: `row` (current values), `old_row` (pre-change image; `None` for inserts), `ins_upd_dlt` (`"ins"`/`"upd"`/`"dlt"`), `nest_level` (0 for client-submitted rows; +1 per chain hop), verbs `insert/update/delete` (for event code that writes other rows WITH logic), state tests `is_inserted()/is_updated()/is_deleted()`, and `log()`. The engine's own docstring states why `old_row` is central (verbatim, listeners.py):

> old_row is critical for: user logic (did the value change? by how much?); performance / pruning (skip rules iff no dependent values change); performance / optimization (1 row adjustments, not expensive select sum/count).

State-transition logic is therefore trivial: nw's ship-check constraint compares `row.ShippedDate is not None and old_row.ShippedDate is None` (verified in a generated nw project).

### 3.5 The per-row cascade — exact verified order

From `LogicRow.update()` in the installed engine, an **updated** row runs, in order:

1. `early_row_event_all_classes` (generic hook — the generated project uses it for optimistic-locking checks, Grant processing, date/user stamping)
2. `early_row_event` (per-class, e.g. defaults — safe place to mutate the row before rules)
3. parent checks (`_check_parents_on_update` — parent existence / FK validity)
4. **copy** rules (`Rule.copy` — set from parent on insert or FK change; deliberately NOT re-run when the parent's value later changes)
5. **formula** rules — in dependency order, pruned (Sections 4, 6)
6. **adjust parent aggregates** — sums/counts chain to parents (Section 4)
7. **constraints** — raise to reject the transaction
8. cascade changed parent references to children (a formula that references `row.parent.attr` re-fires in children when that parent attribute changes — this is the copy-vs-formula distinction: copy freezes, formula-with-parent-reference cascades)
9. parent primary-key change actions
10. `row_event` (per-class, end of this row's cascade)

**Inserted** rows: eager defaults → load/insert parents → early events → copy → formula → adjust parents → constraints → row events. **Deleted** rows: early events → adjust parent aggregates (decrement) → constraints → cascade delete children. Note what this order buys you: by the time a constraint runs on a row, that row's derivations are current; by the time COMMIT LOGIC runs, *every* row's derivations are current.

### 3.6 Where each rule type fires — summary table

| Rule | Phase / cascade position | Notes |
|---|---|---|
| `Rule.early_row_event(_all_classes)` | ROW LOGIC, step 1–2 | Mutating `row` here is the documented purpose |
| `Rule.copy` | ROW LOGIC, step 4 | Insert / FK-change only; parent changes do NOT propagate |
| `Rule.formula` | ROW LOGIC, step 5 | Topologically ordered within the class; pruned |
| `Rule.sum` / `Rule.count` | ROW LOGIC, step 6 — executed while processing the CHILD | Parent updated by delta; parent's own cascade then runs recursively (`nest_level`+1, logged as `Adjusting <role>`) |
| `Rule.constraint` | ROW LOGIC, step 7, per row including chained parents | Failure → `ConstraintException` → rollback → HTTP 400 `{"errors":[{"title": "<your error_msg>", ...}]}` (verified live) |
| `Rule.parent_check` | ROW LOGIC, step 3 | Parent existence enforcement |
| `Rule.row_event` | ROW LOGIC, step 10 | After this row's cascade |
| `Rule.commit_row_event` | COMMIT LOGIC | All rows' derivations final; still pre-flush |
| `Rule.after_flush_row_event`, `Rule.commit_constraint` | AFTER_FLUSH | Side effects / final validation; do not mutate rows |

(Signatures, argument details, and worked patterns: **apilogicserver-logic-patterns**.)

One 17.03.19 caveat (verified, date-stamped 2026-08-23): a bug in `config/server_setup.py`'s `short_format_exception` makes the console print a logging-machinery stack trace instead of the pretty logic log when a constraint violation is logged. The transaction behavior is correct (400 returned, rollback clean) — do not misread it as a broken engine. Details: **apilogicserver-debugging-playbook**.

---

## 4. The optimization theory: adjustment, not aggregation

This is the heart of why declarative scales. **A `Rule.sum`/`Rule.count` is a stored (denormalized) parent column maintained by one-row delta updates — the engine never issues `SELECT SUM` over children during transactions.** Verified in the installed engine: the child's cascade calls `_adjust_parent_aggregates()`, whose docstring states the contract — *"Objective: 1 (one) update per role, for N aggregates along that role"* — then each aggregate's `adjust_parent` computes a delta from `old_row` vs `row`, and `save_altered_parents()` updates the parent **iff** something actually changed, recursively running the parent's own cascade (which is how chains propagate, and why the parent's constraint fires). The engine source annotates the sum rule itself: `# *not* a sql select sum...`.

### 4.1 The delta algebra (verified from `logic_bank/rule_type/aggregate.py`)

For an **updated** child under `Rule.sum(derive=Parent.total, as_sum_of=Child.value, where=<cond>)`, with same parent:

| `where(old_row)` | `where(row)` | Delta applied to parent |
|---|---|---|
| True | True | `new_value − old_value` |
| False | False | `0` — **parent not touched at all** |
| False | True | `+new_value` (child qualified in) |
| True | False | `−new_value` (child qualified out) |

Delta 0 ⇒ no parent update, no parent cascade, no parent constraint. **Insert**: parent `+= value` iff `where(row)` and value ≠ 0. **Delete**: parent `−= value` iff qualified. **Foreign-key change (re-parenting)**: two one-row adjustments — old parent decremented by the old qualified value, new parent incremented by the new — precisely the two bug classes the AI-procedural experiment shipped (Section 2). A transaction that both re-parents a child and changes its summed value defers/merges adjustments so the parent is adjusted exactly once (the engine logs `Adjustment logic chaining deferred...` when it does this).

### 4.2 Pruning (verified from `_is_formula_pruned` and the delta algebra)

- **Formulas**: never pruned on insert; always pruned on delete; on update, pruned unless a referenced local attribute changed or the parent reference changed/cascaded. Pruned rules log `Prune Formula: <col> [<deps>]`. A formula referencing no attributes (e.g. a date stamp) is retained via a no-prune path.
- **Aggregates**: pruning falls out of the algebra — unchanged summed value + unchanged qualification + unchanged FK ⇒ delta 0 ⇒ nothing fires upstream.
- **Net effect** (docs' phrasing): update a non-referenced column (say, a customer's address or an order's notes) and *no* rules fire.

### 4.3 The discriminating experiment: qualified sums prune the chain (verified live, 2026-08-23)

This is the canonical "why didn't my constraint fire" case. In basic_demo: `Customer.balance` sums `Order.amount_total` **where `date_shipped is None`**. Sample data: Order 1 shipped, Order 2 unshipped (customer Alice, balance 90, credit_limit 5000; Item quantity 1, unit_price 90).

Run from the project root with the server running (see **apilogicserver-operate-and-deploy**; if your shell forces localhost through a proxy, add `--noproxy '*'`):

```bash
# 1. Login (security active) — returns a JWT
TOKEN=$(curl -s -X POST http://localhost:5656/api/auth/login \
  -H "Content-Type: application/json" -d '{"username":"admin","password":"p"}' \
  | python -c "import sys,json;print(json.load(sys.stdin)['access_token'])")

# 2. PATCH an Item on the UNSHIPPED order: quantity 1 -> 100
curl -s -X PATCH http://localhost:5656/api/Item/2 \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"data": {"type": "Item", "id": "2", "attributes": {"quantity": 100}}}'
```

Expect **HTTP 400**: formula fires (amount 90→9000) → Order.amount_total sum adjusts (+8910) → Order qualifies (`date_shipped is None`: True→True) so Customer.balance adjusts 90→9000 → Customer cascade runs → constraint fails:

```json
{"errors": [{"title": "Customer balance (9000.0000000000) exceeds credit limit (5000.0000000000)",
             "detail": {"model": "Customer", "error_attributes": []}, "code": "2001"}]}
```

Now the same PATCH against an Item of the **SHIPPED** order. Expect **success**: the Item formula fires and Order.amount_total still adjusts (that sum has no `where`), but the Customer.balance qualification is False→False ⇒ delta 0 ⇒ the Customer row is never processed ⇒ its constraint never runs. The chain was pruned mid-flight, exactly as declared. If you expected the balance to move, the `where` clause — not the engine — is your answer. (Triage recipes: **apilogicserver-debugging-playbook**. PATCH grammar details: **apilogicserver-api-contract**.)

### 4.4 The production case (per docs, not live-verified)

The FAQ-RETE case study: replacing per-transaction aggregate queries with adjustment took a real transaction from *"several minutes to 2 seconds"* with *"no coding changes required"* — the optimization lives in the engine, not the application. Same theme as Logic-Why's *"sub-second performance instead of multiple minutes."* Treat the numbers as the docs' report of their case, not something reproduced here.

### 4.5 The honest costs

Adjustment implies **stored aggregates**: the schema must carry the column (`Customer.balance`, `Order.amount_total`), which is denormalization managed by the engine — and it is only correct while all writes flow through the engine (Section 7). Initial values for pre-existing data are a data-migration problem, not a rules problem (**apilogicserver-data-modeling**).

---

## 5. Why NOT a Rete engine

Common question; the docs (FAQ-RETE) answer it structurally. Rete-based engines (Drools, ODM, etc.) implement **decision logic**: you pass an array of objects plus the *name of a ruleset* to run, get a decision back — appropriate for stateless, single-user "what-if" requests (pricing, eligibility). LogicBank implements **transaction logic**: *"rule execution bound into update processing"*, where invocation is automatic via ORM events, not an explicit call.

| Requirement for transaction logic | Rete / decision engine | LogicBank |
|---|---|---|
| **Invocation** | Explicitly called; developer chooses ruleset per call | Automatic on every ORM flush — nothing to call |
| **Integrity** | Rules partitioned into named rulesets/agendas; *"a rule that isn't loaded into the ruleset actually invoked for a given transaction simply doesn't fire, silently"* | Rules indexed by mapped class at load time; every transaction sees every relevant rule — the silent-non-fire failure mode is structurally absent |
| **Aggregates / cost** | *"Cannot make presumptions about old rows"* ⇒ must *"read all the Orders (and each of their OrderDetails)"* to know a balance ⇒ *"can reduce performance by multiple orders of magnitude"* | `old_row` is native ⇒ pruning + 1-row delta adjustments (Section 4) |
| **Ordering** | Salience/agenda tuning by hand | Derived from declared dependencies (Section 6) |
| **Architecture** | Logic invoked from app code (back in the controllers) | Logic factored out of controllers entirely; enforced for all apps/APIs |

The docs' operating principle: given old vs new values the engine may *"prune the rules that do not apply"* and *"execute the rules in any manner that returns the correct result"* — declaration constrains WHAT, never HOW. If you genuinely need decision logic (a what-if scoring call with no transaction), that is out of this engine's scope — implement it as a service/endpoint (**apilogicserver-api-contract**, **apilogicserver-integration-patterns**). Historical context of the Rete rejection: **apilogicserver-failure-archaeology**.

---

## 6. Ordering: dependency discovery at startup

Verified 2026-08-23 (Genai-Logic 17.03.19, Logic Bank 1.32.00) from engine source and captured server startup logs.

**At activation (server start):**

1. Each rule's text/lambda is parsed; tokens starting with `row.` become that rule's dependencies (`parse_dependencies`). A `row.parent_role.attr` token is a parent reference — this is how the engine knows a formula depends on another table.
2. Formulas **within each class** are topologically sorted by those dependencies into `_exec_order` (iterative algorithm in `rule_bank_setup.compute_formula_execution_order_for_class`). An unresolvable set raises at startup: `LBCircularDependencyException: Mapped Class[<name>] blocked by circular dependencies:<cols>` plus a `Circular dependencies in <class> formula: ...` warning. Cycles are a **design error surfaced at boot**, never a runtime surprise — if you hit one, restate one formula so the dependency is one-directional.
3. **Cross-table order is not a global sort** — it is emergent from chaining: a child's cascade adjusts its parent, which then runs its own cascade (Section 3.5). That, plus phases, is the whole ordering story.

**The startup listing** (read it — it is the engine telling you what it understood; verbatim structure from a live basic_demo start):

```
The following rules have been loaded
Rule Bank[0x...] (loaded 2026-08-23 ...)
Mapped Class[Customer] rules:
  Constraint Function: None
  Derive <class 'database.models.Customer'>.balance as Sum(Order.amount_total Where ...)
Mapped Class[Item] rules:
  Derive <class 'database.models.Item'>.amount as Formula (1): Rule.formula(derive=Item.amount, ...)
  Derive <class 'database.models.Item'>.unit_price as Copy(product.unit_price)

The following attributes have been referenced
..Customer.balance: constraint
..Customer.balance: aggregate derivation
..Order.date_shipped: aggregate where clause
..Order.amount_total: sum derived from
..Order.amount_total: aggregate derivation
..Item.amount: sum derived from
..Item.quantity: - formula
..Item.unit_price: parent copy derivation
..Product.unit_price: parent copy from

The following rules have been activated
...
Logic Bank 1.32.00 - 13 rules loaded
```

The "attributes referenced" section IS the dependency graph, one line per (attribute, role): which attributes are watched (`- formula`, `aggregate where clause`, `sum derived from`) and which are derived (`aggregate derivation`, `parent copy derivation`). `Formula (1)` is the computed execution order; before activation it prints `(-1)` (unordered). If a rule you wrote is missing from this listing, it was never loaded — check `logic/logic_discovery` auto-discovery before debugging anything else.

**Multi-rule interaction and recompute (per docs — Logic-Recompute — not live-verified):** changing or adding a derivation rule re-orders execution automatically, but **does not rewrite already-stored values** in existing rows; derivations apply to transactions from now on. The docs sketch a "Recompute" feature ("update derivations in row on retrieval", "intended for dev teams to introduce new derived attributes") explicitly marked *under consideration* — do not rely on it. Today, backfilling a new/changed derived column is a deliberate data migration (**apilogicserver-data-modeling**), executed under **apilogicserver-change-control** gates.

---

## 7. Limits and non-goals — honestly

1. **Only ORM writes are governed.** The binding is SQLAlchemy `before_flush` (verified). Any write path that bypasses the session — raw SQL via `engine.execute`, a DBA console, another application writing the same database, bulk loaders — fires **no** rules and silently stales every stored aggregate. If multiple writers exist, either route them through this API or treat aggregates as untrusted and audit them (detection scripts: **apilogicserver-validation-and-qa**).
2. **Scope is one database transaction in one session.** No distributed/cross-service transactions. Cross-system consistency is by design asynchronous: after-flush events publishing to Kafka etc. — patterns and their delivery caveats in **apilogicserver-integration-patterns**.
3. **Aggregates are stored columns.** `Rule.sum`/`Rule.count` require a physical parent column in the schema; adding one is a model + migration change (**apilogicserver-data-modeling**), not just a rule line.
4. **Changing a rule does not migrate data** (Section 6). Plan the backfill or the numbers lie.
5. **Rules + Python is the design, not a compromise.** The docs' analysis: rules automate ~95% of transaction logic; the rest is Python — and the docs are explicit that you should *"focus on the rules as the preferred approach, using Python (events, etc) as a fallback."* Procedural events are the *right* tool for (all verified as generated examples in the nw project): integrations/messaging (`after_flush_row_event` → Kafka), auditing rows into other tables (`commit_row_event`), defaults (`early_row_event`), state-transition checks using `old_row`, and min-cardinality checks that plain constraints cannot express ("Order must have Items" via a commit-phase check on a count). Write events to be idempotent where possible; they are Python, so the five problems of Section 2 apply *inside* them.
6. **Not this engine's job:** decision/what-if logic (Section 5), UI behavior, human workflow orchestration, scheduling. Pair it with the right sibling instead of bending rules into these shapes.
7. **Any behavior-changing edit** — new rule, changed `where`, event code — lands only through the gates in **apilogicserver-change-control** (staged edit, rebuild discipline, Behave evidence per **apilogicserver-validation-and-qa**).

---

## Provenance and maintenance

Volatile facts and how to re-verify each (run from any generated project root, venv active):

- Engine + platform versions ("Genai-Logic 17.03.19", "Logic Bank 1.32.00 - N rules loaded"): `als welcome`, then start the server and read the startup banner and rule-bank footer.
- Phase names ROW LOGIC / COMMIT LOGIC / AFTER_FLUSH LOGIC / COMPLETE, and commit-constraint placement in AFTER_FLUSH: `grep -n "Logic Phase" venv/lib/python3.11/site-packages/logic_bank/exec_trans_logic/listeners.py` (adjust venv path).
- Per-row cascade order (copy → formula → adjust → constraints ...): `grep -n "_formula_rules\|_adjust_parent_aggregates\|_constraints" venv/lib/python3.11/site-packages/logic_bank/exec_row_logic/logic_row.py`.
- Delta algebra and re-parenting adjustments: `grep -n "adjust_from_updated_child\|adjust_from_updated_reparented_child" venv/lib/python3.11/site-packages/logic_bank/rule_type/aggregate.py`.
- Formula pruning + cycle exception: `grep -n "_is_formula_pruned" venv/lib/python3.11/site-packages/logic_bank/exec_row_logic/logic_row.py` and `grep -n "LBCircularDependencyException" venv/lib/python3.11/site-packages/logic_bank/rule_bank/rule_bank_setup.py`.
- Dependency scan (`row.xxx`): `grep -n "def parse_dependencies" venv/lib/python3.11/site-packages/logic_bank/rule_type/abstractrule.py`.
- Startup dependency listing format: start the server; look for "The following attributes have been referenced".
- The canonical 5 rules: `grep -n "Rule\." logic/declare_logic.py` in a basic_demo project.
- The shipped/unshipped 400 experiment: the two curl commands in Section 4.3 (login first; server running).
- Docs' numbers (half-the-system, 95%, 40X, minutes→2s, 220-lines/2-bugs): re-read the four "Grounded in" logic pages below; they are claims of the docs, re-quotable but not locally reproducible.
- 17.03.19 constraint-logging bug (`short_format_exception`): `grep -n "splitlines" config/server_setup.py`.

Grounded in: https://apilogicserver.github.io/Docs/Logic-Why/ , https://apilogicserver.github.io/Docs/Logic-Operation/ , https://apilogicserver.github.io/Docs/Logic/ , https://apilogicserver.github.io/Docs/FAQ-RETE/ , https://apilogicserver.github.io/Docs/Logic-Why-Declarative-GenAI/ , https://apilogicserver.github.io/Docs/Logic-Recompute/ and a live Genai-Logic 17.03.19 install (2026-08-23) — engine source read from the installed logic_bank package, startup listings and the shipped/unshipped chain experiment executed against generated basic_demo and nw sample projects.
