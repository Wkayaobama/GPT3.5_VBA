---
name: apilogicserver-logic-patterns
description: Practice runbook for writing business logic in API Logic Server / Genai-Logic projects. Use when adding, changing, or reviewing rules in logic/declare_logic.py or logic/logic_discovery/ — Rule.constraint, Rule.sum, Rule.count, Rule.formula, Rule.copy, Rule.commit_constraint, Rule.parent_check, event rules (early_row_event, row_event, commit_row_event, after_flush_row_event), RuleExtension.copy_row/allocate. Use when you need the exact signature of a rule, a worked pattern (check-credit chain, qualified aggregates, defaults, state transitions, auditing, request pattern, Kafka integration events, order clone), the logic_discovery file template, or the safe add-a-rule procedure. Symptom triggers: "constraint not firing", "sum not updating", "copied value didn't change", "LBActivateException", "ConstraintException", "error_msg interpolation", "where clause on sum", "how do I validate/derive/default a column".
---

# API Logic Server: Logic Patterns Runbook

## Purpose

This is the practice runbook for declaring business logic in an API Logic Server (Genai-Logic) project: every rule type as a recipe with its exact verified signature, real examples from the shipped samples, the worked 5-rule check-credit composition with its logic log, the `logic_discovery` team mechanics, and the safe procedure for adding a rule. All signatures were read from the installed engine (LogicBank 1.32.0 inside Genai-Logic 17.03.19) and all examples from real created projects — verified 2026-08-23.

## Use this skill when

- Adding or modifying any rule in `logic/declare_logic.py` or `logic/logic_discovery/`
- You need the exact parameters of `Rule.constraint`, `Rule.sum`, `Rule.count`, `Rule.formula`, `Rule.copy`, `Rule.commit_constraint`, `Rule.parent_check`, an event rule, or `RuleExtension.allocate`/`copy_row`
- Implementing a known pattern: validation, derived totals, defaults, date/user stamping, auditing, state-transition checks, the request pattern, integration events, multi-row clone, allocation
- Diagnosing "my rule didn't fire" at the *authoring* level (wrong rule type, wrong where-clause, copy vs formula confusion, event mutation guard)

## Do NOT use this skill when

- You need the *theory* of the engine — why declarative, watch/react/chain, dependency ordering, pruning/adjustment internals, Rete comparison → **declarative-rules-reference**
- You are triaging a runtime failure from symptoms (stack traces, logging bug, port issues) → **apilogicserver-debugging-playbook**
- You are writing Behave tests or the Logic Report → **apilogicserver-validation-and-qa**
- You need JSON:API request shapes to exercise logic → **apilogicserver-api-contract**
- You need Kafka/n8n/MCP wiring beyond the logic-side event → **apilogicserver-integration-patterns**
- You are deciding what may be edited vs regenerated, or merging a rebuild → **apilogicserver-change-control**
- Roles/grants (`Grant`, `GlobalFilter`) → **apilogicserver-security-model**

## Ground rules (60-second orientation)

- **Rules are declared, not called.** `Rule.*` calls in `declare_logic()` register rules once at server start (`LogicBank.activate` in `api_logic_server_run.py`). They *execute* automatically on `session.commit()` — the engine listens to SQLAlchemy (the ORM — object-relational mapper) `before_flush` events. A *flush* is SQLAlchemy writing pending row changes to the database inside the transaction, before commit.
- **Declaration order does not matter.** The engine orders execution by dependencies. Theory in **declarative-rules-reference**.
- **A *derivation* computes a stored column** (sum/count/formula/copy). **A *constraint* is a condition that must hold** or the transaction rolls back with HTTP 400.
- **Rules apply to every write path** — JSON:API (the REST convention this server generates: `data/attributes/relationships` documents) PATCH/POST/DELETE, admin app, custom endpoints, tests. You never re-invoke them per screen.
- **Logic = rules + Python.** Anything the rule types cannot express goes in an event rule with a plain Python function receiving `(row, old_row, logic_row)`.

---

## 1. Rule-type catalog

Verification: "installed engine" = read from the installed LogicBank 1.32.0 source; "sample" = verbatim in basic_demo / nw_sample created by als 17.03.19; "live" = exercised over HTTP against a running project (all 2026-08-23).

| Rule | Derives / checks | Fires | Verification |
|---|---|---|---|
| `Rule.constraint` | Condition must be true for the row | Inline, every time the row is processed or adjusted mid-cascade | installed engine + sample + live 400 |
| `Rule.commit_constraint` | Condition on *settled* derived values | Once per row, after the whole cascade, during after-flush | installed engine + docs; not in samples |
| `Rule.parent_check` | Non-null foreign keys reference an existing parent | On insert / FK change | installed engine + docs |
| `Rule.sum` | Parent column = sum of child column | Iff summed field, where-predicate result, or FK changes | installed engine + sample + live |
| `Rule.count` | Parent column = count of child rows | Iff where-predicate result or FK changes | installed engine + sample |
| `Rule.formula` | Column from own row + parent references | Iff referenced attributes change (parent refs propagate) | installed engine + sample + live |
| `Rule.copy` | Child column copied from parent — **once** | On insert or FK change only; parent changes do NOT propagate | installed engine + sample |
| `Rule.early_row_event` | Python before any rules run on the row | Per row, before logic; may set attributes | installed engine + sample |
| `Rule.early_row_event_all_classes` | Generic pre-logic handler for every class | Per row, every class | installed engine + sample |
| `Rule.row_event` | Python during logic, after the row's rules | Per row, possibly multiple times per transaction | installed engine + sample |
| `Rule.commit_row_event` | Python after ALL rows' rules, before flush | Once per row per transaction | installed engine + sample |
| `Rule.after_flush_row_event` | Python after flush — DB-generated ids available | Once per row; must not update rows | installed engine + sample |
| `RuleExtension.copy_row` | Audit-style copy to another table on condition | When `copy_when` true | installed engine + sample |
| `RuleExtension.allocate` | Allocate a provider amount across recipients | On provider insert | installed engine + docs; not in samples |

`DeclareRule` is an exact alias of `Rule` (installed engine) — some generated code uses it for readability.

---

## 2. Constraint

```python
Rule.constraint(validate: object,            # mapped model class
                calling: Callable = None,     # function(row, old_row, logic_row) -> bool
                as_condition: any = None,     # lambda row: <bool>  (simple form)
                error_msg: str = "(error_msg not provided)",
                error_attributes=None)        # list of attributes for clients
```
(verified 2026-08-23, installed engine)

Semantics: the condition must be true whenever the row is processed — including when the row is only *adjusted* by a child's chain (see the worked composition, section 10). False (or raising `ConstraintException` from `logic_bank.util`) rolls back the transaction; the API returns HTTP 400.

Real example — simple lambda form (basic_demo, verbatim):

```python
Rule.constraint(validate=Customer, as_condition=lambda row: row.balance <= row.credit_limit,
                error_msg="Customer balance ({row.balance}) exceeds credit limit ({row.credit_limit})")
```
Guards the whole check-credit chain: it fires when a distant Item change adjusts this Customer's balance, not just on direct Customer updates.

Real example — function form with state transition (nw_sample, verbatim):

```python
def raise_over_20_percent(row: Employee, old_row: Employee, logic_row: LogicRow):
    if logic_row.ins_upd_dlt == "upd" and row.Salary > old_row.Salary:
        return row.Salary >= Decimal('1.20') * old_row.Salary
    else:
        return True
Rule.constraint(validate=Employee,
                calling=raise_over_20_percent,
                error_msg="{row.LastName} needs a more meaningful raise")
```
`old_row` is the pre-transaction image; `logic_row.ins_upd_dlt` is `"ins" | "upd" | "dlt"`. This is the standard old-vs-new (state transition) pattern.

**error_msg interpolation** (verified live): brace contents are evaluated with `row` in scope at failure time. The 400 payload for the rule above the sample data produced, verbatim:

```json
{"errors": [{"title": "Customer balance (9000.0000000000) exceeds credit limit (5000.0000000000)",
  "detail": {"model": "Customer", "error_attributes": []}, "code": "2001"}]}
```

Expressions work too — nw_sample uses `error_msg="balance ({round(row.Balance, 2)}) exceeds credit ({round(row.CreditLimit, 2)})"`. Write a **plain** string: an f-string prefix (`f"...{row.balance}"`) would evaluate at *declaration* time and fail — `row` does not exist yet.

Gotchas:
- A constraint referencing an aggregate can fire before children exist (Order inserted before its Items). Use `Rule.commit_constraint` (next section) for minimum-cardinality checks.
- Known 17.03.19 cosmetic bug: when a constraint fires, the console may show a `TypeError` from `config/server_setup.py` `short_format_exception` instead of the pretty log. The 400 and rollback are still correct — see **apilogicserver-debugging-playbook** / **apilogicserver-failure-archaeology**.

## 3. Commit constraint

```python
Rule.commit_constraint(validate, calling=None, as_condition=None,
                       error_msg="(error_msg not provided)", error_attributes=None)
```
(verified 2026-08-23, installed engine — signature identical to `Rule.constraint`; not used in the shipped samples, runtime behavior per docs, not live-verified)

Semantics (installed docstring): checked **once per row, after the transaction's logic cascade has fully settled** (during after-flush), instead of inline mid-cascade. Use for minimum-cardinality rules that inline constraints cannot express:

```python
Rule.count(derive=Order.ItemCount, as_count_of=OrderDetail)
Rule.commit_constraint(validate=Order,
              as_condition=lambda row: row.ItemCount > 0,
              error_msg="Order {row.Id} must have at least one item")
```
An inline constraint here fails on Order's own insert — Order is processed before its not-yet-existent Items.

Restrictions (installed docstring): not run for rows deleted in the transaction; runs after flush, so — like `after_flush_row_event` — it must not alter the row.

## 4. Parent check

```python
Rule.parent_check(validate: object, error_msg: str = "(error_msg not provided)", enable: bool = True)
```
(verified 2026-08-23, installed engine; per docs, not live-verified)

Ensures non-null foreign keys reference an existing parent row (referential integrity in logic, useful when the DB lacks FK enforcement). `enable=False` tolerates orphans — installed docstring warns behavior of other rules (sum, count, parent references) is then *undefined*; use only for legacy bad data.

## 5. Sum

```python
Rule.sum(derive: Column, as_sum_of: any, where: any = None,
         child_role_name: str = "", insert_parent: bool = False)
```
(verified 2026-08-23, installed engine)

Semantics: parent column = sum of a child column, optionally qualified by `where=lambda row: ...` evaluated on the **child** row. Executed as a **one-row adjustment update** to the parent, not a `SELECT SUM` — see **declarative-rules-reference** for why that matters at scale. Fires iff the summed field, the where-predicate's result, or the foreign key changes; otherwise pruned.

Real examples (verbatim — first pair basic_demo, second nw_sample):

```python
Rule.sum(derive=Customer.balance, as_sum_of=Order.amount_total, where=lambda row: row.date_shipped is None)
Rule.sum(derive=Order.amount_total, as_sum_of=Item.amount)

Rule.sum(derive=Customer.Balance, as_sum_of=Order.AmountTotal,
         where=lambda row: row.ShippedDate is None and row.Ready == True)
```
The where-clause encodes business meaning: shipped orders no longer count against credit. Multiple conditions AND together in one lambda.

Parameters beyond the basics:
- `child_role_name`: required only when child and parent are connected by 2+ relationships ("Ambiguous Relationship" error otherwise); names the parent-accessor attribute on the child class.
- `insert_parent=True`: auto-create the missing parent row on adjust (group-by-style aggregates; per docs, not live-verified).

Gotcha: the derived column must exist as a real column in `database/models.py` — see **apilogicserver-data-modeling** for adding one and **apilogicserver-change-control** for the rebuild flow.

## 6. Count

```python
Rule.count(derive: Column, as_count_of: object, where: any = None,
           child_role_name: str = "", insert_parent: bool = False)
```
(verified 2026-08-23, installed engine)

Same adjustment semantics as sum; `as_count_of` is the child **class**, not an attribute. Real examples (nw_sample, verbatim):

```python
Rule.count(derive=Customer.UnpaidOrderCount, as_count_of=Order,
           where=lambda row: row.ShippedDate is None)
Rule.count(derive=Customer.OrderCount, as_count_of=Order)
Rule.count(derive=Order.OrderDetailCount, as_count_of=OrderDetail)
```
`OrderDetailCount` powers the empty-order check in section 9 — counts exist to be constrained against.

## 7. Formula

```python
Rule.formula(derive: Column,
             as_exp: str = None,          # string, for very short expressions
             as_expression: Callable = None,  # lambda row: ...  (preferred: syntax-checked)
             calling: Callable = None,    # function(row, old_row, logic_row) for if/else logic
             no_prune: bool = False)
```
(verified 2026-08-23, installed engine)

Semantics: derives a column of the **same row** from its own attributes and **parent** attributes. Unlike `Rule.copy`, referenced *parent changes propagate to all child rows*. Exactly one of `as_exp` / `as_expression` / `calling`.

Real examples (verbatim):

```python
# lambda form (basic_demo)
Rule.formula(derive=Item.amount, as_expression=lambda row: row.quantity * row.unit_price)

# function form for old_row arithmetic (nw_sample order_ship_inventory_reorder)
def units_in_stock(row: Product, old_row: Product, logic_row: LogicRow):
    result = row.UnitsInStock - (row.UnitsShipped - old_row.UnitsShipped)
    return result  # use lambdas for simple expressions, functions for complex logic (if/else etc)
Rule.formula(derive=Product.UnitsInStock, calling=units_in_stock)

# string form with a parent reference that CASCADES to children (nw_sample)
Rule.formula(derive=OrderDetail.ShippedDate,  # unlike copy, referenced parent values cascade to children
    as_exp="row.Order.ShippedDate")
```
The last line is the copy/formula contrast in one rule: ship the Order and every OrderDetail's ShippedDate re-derives.

Gotchas (all from the installed engine's docstring, verified 2026-08-23):
- **`calling` must return a value — else the column is nullified.** A missing `return` silently NULLs your column.
- **Keep expressions side-effect-free.** Dependency discovery (pruning + parent-change propagation) is a *textual scan* for `row.<attr>` / `row.<parent>.<attr>` in the rule's source, including a `calling` function's own body. Side effects and hidden references break the model.
- **Helper-function trap**: if parent access happens inside a helper the formula calls, no literal `row.Parent.attr` appears in `calling`'s source — the formula is wrongly pruned and never re-derives on parent change. Fix by naming the references in a comment (comments ARE scanned):

```python
def _quantity(row, old_row, logic_row):
    # deps: row.order_line.quantity row.order_line.date_served
    return _derive_quantity(row, logic_row)
Rule.formula(derive=Movement.quantity, calling=_quantity)
```
- `no_prune=True` forces re-evaluation every time (rare; costs performance).

## 8. Copy

```python
Rule.copy(derive: Column, from_parent: any, child_role_name: str = "")
```
(verified 2026-08-23, installed engine)

Semantics: child column copied from a parent column **at insert time or when the foreign key changes — and never again**. Parent changes do NOT propagate. This is a business decision, not a limitation: an Item's `unit_price` is the price *at time of order*; Tuesday's price change must not rewrite Monday's orders.

Real example (basic_demo, verbatim):

```python
Rule.copy(derive=Item.unit_price, from_parent=Product.unit_price)
```
Want propagation instead? Use a formula parent reference (`as_exp="row.Product.unit_price"`). Choosing between them IS the requirement decision.

`child_role_name` disambiguates when 2+ relationships link the same child and parent classes (names the relationship attribute on the **child** class).

## 9. Event rules — the Python escape hatch

All event handlers receive `(row, old_row, logic_row)` (the all-classes variant receives only `logic_row`). `LogicRow` bundles the row, its pre-transaction image, and engine state. Verified members (installed engine, 2026-08-23): attributes `row`, `old_row`, `ins_upd_dlt`, `nest_level`, `session`; methods `is_inserted()`, `is_updated()`, `is_deleted()`, `log(msg)`, `are_attributes_changed([Model.attr, ...])`, `new_logic_row(ModelClass)`, `link(to_parent=...)`, `set_same_named_attributes(logic_row)`, `copy_children(copy_from=..., which_children=[...])`, and rule-respecting `insert(reason=...)` / `update(reason=...)` / `delete(reason=...)`.

Lifecycle (verified from installed docstrings; flush = rows written to DB inside the transaction):

| Event | When | Aggregates final? | DB-generated ids? | May set row attrs? | Calls/txn |
|---|---|---|---|---|---|
| `early_row_event` | Before the row's rules | No | No | **Yes** — runs before logic | possibly multiple |
| `early_row_event_all_classes` | Before logic, every class | No | No | Yes | per row |
| `row_event` | During logic, after the row's formulas/constraints | For this row | No | **No** (guarded) | possibly multiple |
| `commit_row_event` | After ALL rows' logic, before flush | Yes | No | **No** (guarded) | once per row |
| `after_flush_row_event` | After flush | Yes | **Yes** | No — updates undefined | once per row |

**Mutation guard (verified installed docstrings):** activation FAILS with `LBActivateException` if a `row_event`/`commit_row_event` handler's source appears to assign `row.<attr> = ...` — the mutation would persist without re-derivation or re-validation. Either move the assignment to an `early_row_event`, insert a NEW row via `logic_row.new_logic_row(...)...insert(...)` (full cascade applies), or pass `allow_row_mutation=True` only if you accept the bypass.

### 9a. early_row_event — defaults

```python
Rule.early_row_event(on_class: object, calling: Callable = None, allow_event_nesting: bool = False)
```
Real example (nw_sample check_credit.py, verbatim, abridged to one class):

```python
def order_defaults(row: Order, old_row: Order, logic_row: LogicRow):
    if row.Freight is None:
        row.Freight = 10
    if row.AmountTotal is None:
        row.AmountTotal = 0
    if row.Ready is None:  # if not set in UI, set to False for do_not_ship_empty_orders()
        row.Ready = False
Rule.early_row_event(on_class=Order, calling=order_defaults)
```
Early events are the sanctioned place to set attribute values in Python — downstream rules then see and react to them.

### 9b. early_row_event_all_classes — stamping and cross-cutting services

```python
Rule.early_row_event_all_classes(early_row_event_all_classes=handle_all)
```
Real example — `logic/logic_discovery/system/all_classes_stamping.py` (both samples ship it; verbatim core):

```python
def handle_all(logic_row: LogicRow):  # #als: DATE / USER STAMPING, OPTIMISTIC LOCKING
    if logic_row.is_updated() and logic_row.old_row is not None and logic_row.nest_level == 0:
        opt_locking.opt_lock_patch(logic_row=logic_row)
    Grant.process_updates(logic_row=logic_row)
    did_stamping = False
    if enable_stamping := False:  # #als: change False to True to enable date/user stamping
        row = logic_row.row
        if logic_row.ins_upd_dlt == "ins" and hasattr(row, "CreatedOn"):
            row.CreatedOn = datetime.datetime.now()
            did_stamping = True
        if logic_row.ins_upd_dlt == "ins" and hasattr(row, "CreatedBy"):
            row.CreatedBy = Security.current_user().id \
                if Config.SECURITY_ENABLED == True else 'public'
            did_stamping = True
        # ... same pattern for "upd" + UpdatedOn / UpdatedBy ...
        if did_stamping:
            logic_row.log("early_row_event_all_classes - handle_all did stamping")
Rule.early_row_event_all_classes(early_row_event_all_classes=handle_all)
```
One handler stamps every table that HAS the columns (`hasattr` guard) — flip `enable_stamping := False` to `True` to activate. It also hosts optimistic-locking (see **apilogicserver-api-contract**) and `Grant` enforcement (see **apilogicserver-security-model**) — do not delete those lines when customizing.

**Single-slot gotcha (verified 2026-08-23, installed engine):** `setup_early_row_event_all_classes` stores ONE callable — the **last registration wins**. basic_demo actually registers twice (the discovery file above with stamping `False`, then `declare_logic.py`'s own `handle_all` with stamping `True`; discovery runs first, so `declare_logic.py`'s wins). Keep exactly one all-classes handler per project, or know which registration is last.

### 9c. row_event — during-logic work, e.g. multi-row clone

```python
Rule.row_event(on_class, calling=None, allow_event_nesting: bool = False, allow_row_mutation: bool = False)
```
Real example (nw_sample order_clone/clone_order.py, verbatim):

```python
def clone_order(row: Order, old_row: Order, logic_row: LogicRow):
    if row.CloneFromOrder is not None and logic_row.nest_level == 0:
        which = ["OrderDetailList"]
        logic_row.copy_children(copy_from=row.Order, which_children=which)
Rule.row_event(on_class=Order, calling=clone_order)
```
Set `CloneFromOrder` on an Order and its source's OrderDetails are copied in — each copied child runs the full rule cascade, so totals and credit check just work. `nest_level == 0` restricts to client-initiated changes (not rows the engine itself inserted).

### 9d. commit_row_event — after all logic, aggregates final

```python
Rule.commit_row_event(on_class, calling=None, allow_event_nesting: bool = False, allow_row_mutation: bool = False)
```
Real example (nw_sample check_credit.py, verbatim) — a commit-time check against a derived count, raising `ConstraintException` directly:

```python
def do_not_ship_empty_orders(row: Order, old_row: Order, logic_row: LogicRow):
    if row.OrderDetailCount == 0:  # an empty order... error if trying to ship...
        if logic_row.is_deleted():
            pass
        else:  # enforce child cardinality
            if row.ShippedDate is not None or row.Ready == True:
                raise ConstraintException("Empty Order - Cannot Ship or Make Ready")
Rule.commit_row_event(on_class=Order, calling=do_not_ship_empty_orders)
```
`from logic_bank.util import ConstraintException` (verified import path). `Rule.commit_constraint` (section 3) is the newer declarative spelling of this pattern. The other shipped commit event, `congratulate_sales_rep`, shows parent navigation (`row.Employee.Manager`) and direct `logic_row.session.query(...)` — logic is system code, NOT subject to row security.

### 9e. after_flush_row_event — integration messages

```python
Rule.after_flush_row_event(on_class: object, calling: Callable = None,
                           if_condition: any = None,      # lambda row: execute iff True
                           when_condition: any = None,    # lambda: execute iff was False, now True
                           with_args: dict = None)        # extra args, e.g. Kafka topic
```
(verified 2026-08-23, installed engine)

Runs after flush: DB-generated autoincrement ids ARE populated (earlier events see None on inserts — the samples call this out explicitly). Updates during after_flush are *undefined*; if you must update, use `commit_row_event`.

Real example — declarative Kafka send (basic_demo, verbatim):

```python
Rule.after_flush_row_event(on_class=Order, calling=kafka_producer.send_row_to_kafka,
    if_condition=lambda row: row.date_shipped is not None, with_args={'topic': 'order_shipping'})
```
`send_row_to_kafka(row, old_row, logic_row, with_args)` is the generic handler shipped in `integration/kafka/kafka_producer.py`; `with_args` arrives as the 4th parameter. With no broker configured the producer logs "Kafka mode: FALLBACK" and does not fail the transaction (verified live). Handler-function form with a `RowDictMapper` payload: see `logic/logic_discovery/order_place/app_integration.py` and **apilogicserver-integration-patterns**.

**Only ONE `after_flush_row_event` per class** — verified as a load-bearing comment in nw_sample `logic/logic_discovery/integration.py` ("important - only one after_flush_row_event per class"); that file defines an Order workflow function but deliberately does NOT register it because `app_integration.py` already owns Order's after-flush. A second registration on the same class silently displaces coverage — consolidate into one handler.

### 9f. RuleExtension.copy_row — auditing in one rule

```python
RuleExtension.copy_row(copy_from: object, copy_to: object,
                       copy_when: Callable, initialize_target: Callable = None)
```
(verified 2026-08-23, installed engine; import `from logic_bank.extensions.rule_extensions import RuleExtension`)

Real example (nw_sample employee_auditing/employee_audit.py, verbatim):

```python
RuleExtension.copy_row(copy_from=Employee,
                copy_to=EmployeeAudit,
                copy_when=lambda logic_row: logic_row.ins_upd_dlt == "upd" and
                        logic_row.are_attributes_changed([Employee.Salary, Employee.Title]))
```
Copies like-named attributes into an audit row whenever Salary or Title changes. The same file shows the equivalent hand-rolled `commit_row_event` using `new_logic_row` / `link` / `set_same_named_attributes` / `insert` — the triggered-insert pattern for when the audit needs extra logic.

### 9g. RuleExtension.allocate

```python
RuleExtension.allocate(provider: object = None, recipients: Callable = None,
                       while_calling_allocator: Callable = None, creating_allocation: object = None)
```
(signature verified 2026-08-23 from installed engine; behavior per docs, not live-verified — no sample project ships one)

Allocates a provider amount (e.g. a `Payment`) across a list of recipients (e.g. unpaid `Orders`), creating one `creating_allocation` junction row (e.g. `PaymentAllocation`) per recipient until the amount is exhausted. Each created row triggers the normal cascade (Order balances, Customer balance). Treat as a documented extension pattern: prototype against the LogicBank Allocation sample before relying on it.

---

## 10. Worked composition: the 5-rule check-credit chain (verified live)

The requirement, as rules (basic_demo, verbatim — declaration order is free):

```python
Rule.constraint(validate=Customer, as_condition=lambda row: row.balance <= row.credit_limit,
                error_msg="Customer balance ({row.balance}) exceeds credit limit ({row.credit_limit})")
Rule.sum(derive=Customer.balance, as_sum_of=Order.amount_total, where=lambda row: row.date_shipped is None)
Rule.sum(derive=Order.amount_total, as_sum_of=Item.amount)
Rule.formula(derive=Item.amount, as_expression=lambda row: row.quantity * row.unit_price)
Rule.copy(derive=Item.unit_price, from_parent=Product.unit_price)
```

Execution for "PATCH Item.quantity 1 → 100" (unshipped order, unit_price 90, customer credit_limit 5000 — verified live 2026-08-23):

1. Formula re-derives `Item.amount`: 90 → 9000.
2. Amount change adjusts parent `Order.amount_total` (one-row adjustment update, chained to the Order).
3. That change adjusts `Customer.balance` (order is unshipped, so the where-clause includes it).
4. The Customer constraint fires on the adjusted row: 9000 > 5000 → `ConstraintException` → rollback → HTTP 400 with the interpolated title shown in section 2.
5. Copy does not fire at all (no insert, no product change) — pruned.

Logic log (verbatim shape from the live server console; `[old-->] new` marks changed values):

```
Logic Phase:		ROW LOGIC		(session=0x...) (sqlalchemy before_flush)
..Item[2] {Formula amount} id: 2, order_id: 2, ..., quantity:  [1-->] 100, amount:  [90.0000000000-->] 9000.0000000000, ...  row: 0x...  session: 0x...  ins_upd_dlt: upd, initial: upd
Logic Phase:		COMMIT LOGIC		(session=0x...)
Logic Phase:		AFTER_FLUSH LOGIC	(session=0x...)
These Rules Fired (see Logic Phases, above, for actual order):
    1. Derive <class 'database.models.Customer'>.balance as Sum(Order.amount_total Where ...)
Logic Phase:		COMPLETE(session=0x...)
```
Indentation depth = chain depth across tables. The "These Rules Fired" trailer is your evidence that the intended rules ran — **apilogicserver-validation-and-qa** turns it into the Behave Logic Report.

**The discriminating experiment** (verified live): the *same* PATCH against an Item of a SHIPPED order **succeeds** — `where=lambda row: row.date_shipped is None` excludes shipped orders from the balance, so the constraint never sees the change. When someone reports "my constraint didn't fire", run their transaction against a row that passes the where-clause before suspecting the engine. Triage tree: **apilogicserver-debugging-playbook**.

---

## 11. logic_discovery mechanics (verified 2026-08-23 from installed project code)

`logic/declare_logic.py` → `from logic.logic_discovery.auto_discovery import discover_logic; discover_logic()`. What `discover_logic()` actually does (read from `logic/logic_discovery/auto_discovery.py`):

1. `os.walk` over `logic/logic_discovery/` — **subdirectories included** (nw_sample groups files per use case: `order_place/`, `employee_auditing/`, ...).
2. Imports every `*.py` except `auto_discovery.py` and `__init__.py` — module top-level code runs at import.
3. Calls the module's **`declare_logic()`** function. No registration list, no naming convention beyond that.
4. Logs `..discovered logic: [<files>]` at startup — your first checkpoint that a new file was picked up. Verified basic_demo list: `simple_constraints.py, email_request.py, use_case.py, all_classes_stamping.py`.
5. Additionally loads `logic/wg_rules/active_rules_export.py` if present (WebGenAI export — see **apilogicserver-genai-development**).

**Contract: every `.py` you drop under `logic/logic_discovery/` MUST define a module-level `declare_logic()`** or startup fails with `AttributeError`. Never edit `auto_discovery.py` itself.

Team pattern: **one file (or one subdirectory) per use case**, named for the use case — `order_place/check_credit.py`, not `misc_rules.py`. Keep `logic/declare_logic.py` for cross-cutting services only (the samples keep `handle_all` stamping there or in `system/all_classes_stamping.py`). Rules merge like code because they ARE code and declaration order is free — parallel use-case files rarely conflict in git.

Discovery-file template — this is the exact shape of the shipped `simple_constraints.py`, trimmed to what is required:

```python
from logic_bank.exec_row_logic.logic_row import LogicRow
from logic_bank.logic_bank import Rule
from database import models
import logging

app_logger = logging.getLogger(__name__)

def declare_logic():
    """<Use case name>: <one-line requirement statement>."""

    Rule.constraint(validate=models.Customer,
        as_condition=lambda row: row.name != 'x',
        error_msg="Customer name cannot be 'x'")
```
Add `from decimal import Decimal`, `import datetime`, or model-star imports (`from database.models import *`, used by nw_sample use-case files) as needed. Subdirectories need an empty `__init__.py` (present in all nw_sample use-case dirs).

## 12. Pattern index (all real, with home file)

| Pattern | Recipe | Real file (project-relative) |
|---|---|---|
| Qualified aggregate | `where=lambda row: ...` on sum/count; predicate on child row; AND conditions in one lambda | `logic/logic_discovery/order_place/check_credit.py` |
| Chained derivation | formula → sum → sum → constraint; order inferred, never declared | same |
| Constraint on derived value | declare the aggregate, then constrain it | same (`Balance` / `OrderDetailCount`) |
| Min-cardinality | count + `commit_row_event` raising `ConstraintException`, or `Rule.commit_constraint` | same, `do_not_ship_empty_orders` |
| State transition | function constraint comparing `row` vs `old_row`, gated on `ins_upd_dlt == "upd"` | `employee_state_transition_logic/raise_over_20_percent.py` |
| Defaults | `early_row_event` setting attrs if None | `order_place/check_credit.py` |
| Date/user stamping | `early_row_event_all_classes` + `hasattr` | `logic_discovery/system/all_classes_stamping.py` |
| Auditing | `RuleExtension.copy_row` on `are_attributes_changed` | `employee_auditing/employee_audit.py` |
| Request pattern | insert a request row (SysEmail); its `after_flush_row_event` does the work, wrapped in logic (e.g. honor `email_opt_out`) | `logic/logic_discovery/email_request.py` (basic_demo) |
| Integration event | `after_flush_row_event` + Kafka/n8n producer, `if_condition`, `with_args` | `order_place/app_integration.py`, `logic_discovery/integration.py` |
| Multi-row clone | `row_event` + `logic_row.copy_children` | `order_clone/clone_order.py` |
| Triggered insert | `new_logic_row` → `link` → `set_same_named_attributes` → `insert(reason=...)` | commented alt in `employee_audit.py` |
| Allocation | `RuleExtension.allocate` provider→recipients→allocation rows | per docs only (section 9g) |

The request pattern deserves emphasis for modernization work (see **apilogicserver-modernization-campaign**): instead of a bespoke "send email" endpoint, clients POST a `SysEmail` row; the event sends the mail, and *rules govern the request* — basic_demo's `send_mail` checks `row.customer.email_opt_out` before sending (verbatim in `email_request.py`). Same shape powers SysMcp request rows (**apilogicserver-integration-patterns**).

## 13. Add-a-rule checklist

1. **State the requirement in cocktail-napkin form first** ("Balance = sum of unshipped order totals; Balance <= credit limit"). Each line maps to one rule. If a line needs if/else or external calls, it is an event.
2. **Pick the rule type** from the catalog. Derive stored columns with sum/count/formula/copy; validate with constraint/commit_constraint; everything else is an event. New derived column needed? → **apilogicserver-data-modeling** first.
3. **Create or open the use-case file** under `logic/logic_discovery/` (template in section 11). Do not append unrelated rules to an existing use case.
4. **Write the rule.** Plain-string `error_msg` (no f-prefix). Side-effect-free lambdas. Functions for old_row/if-else. `# deps:` comment if a `calling` formula hides parent access in helpers.
5. **Restart the server** — rules load only at activation, at startup. Runner mechanics: **apilogicserver-operate-and-deploy**.
6. **Confirm registration in the startup log**: your file in `..discovered logic: [...]` and your attribute in the per-attribute dependency listing (e.g. `..Customer.balance: constraint`). Missing file → no `declare_logic()` or wrong directory.
7. **Exercise it** with a real transaction — admin app or curl (JSON:API shapes and login/JWT (JSON Web Token) header: **apilogicserver-api-contract**; a JWT is the bearer token from `POST /api/auth/login`). Probe pattern, run from a shell:
   `curl -s --noproxy '*' -X PATCH http://localhost:5656/api/Item/2/ -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"data":{"type":"Item","id":"2","attributes":{"quantity":100}}}'`
8. **Read the logic log** for that transaction: expected rules in "These Rules Fired", correct `[old-->] new` values, correct chain depth. A rule you expected but absent = pruned (nothing it watches changed) or where-clause excluded the row — re-run the discriminating experiment from section 10.
9. **Negative-test constraints**: force the violation; expect HTTP 400, `"code": "2001"`, interpolated `title`. (Console TypeError trace alongside it is the known 17.03.19 logging bug — not your rule.)
10. **Write/extend a Behave scenario** capturing the requirement and regenerate the Logic Report — gate and evidence discipline in **apilogicserver-validation-and-qa** (verified suite baseline: 26 scenarios, 0 failed).
11. **Route the change through apilogicserver-change-control** — logic files are safe-to-edit customization files, but the commit/merge/rebuild gates there are non-negotiable.

## 14. Common mistakes

| Symptom | Why | Fix |
|---|---|---|
| "Order must have items" constraint rejects every Order insert | Inline constraint runs before the Items exist; count still 0 | `Rule.commit_constraint`, or count + `commit_row_event` raising `ConstraintException` (sections 3, 9d) |
| Constraint/sum "didn't fire" on a shipped order (verified live) | `where=lambda row: row.date_shipped is None` excludes it — by design | Re-read the where-clause as the requirement; test against a row the predicate includes |
| Child value stale after parent update | `Rule.copy` is copy-once, non-reactive | Use a formula parent reference (`as_exp="row.Parent.attr"`) if propagation is the requirement |
| Formula never recomputes on parent change | Parent access hidden in a helper — textual dependency scan missed it; wrongly pruned | `# deps: row.parent.attr` comment in `calling`'s body (section 7) |
| Derived column silently NULL | `calling` formula lacks a `return` | Return a value on every path (installed docstring: else column is nullified) |
| Server fails at startup: `LBActivateException` | `row_event`/`commit_row_event` handler assigns `row.attr = ...` | Move to `early_row_event`; or insert a new row via `new_logic_row(...).insert(...)`; `allow_row_mutation=True` only knowingly |
| `error_msg` shows wrong/instant values or NameError at startup | Wrote `f"...{row.x}"` — evaluated at declaration | Plain string; engine evaluates braces at failure time with `row` in scope (verified 400 payload) |
| `Ambiguous Relationship` at activation | 2+ relationships between child and parent | Pass `child_role_name=` (sum/count/copy) naming the child's parent accessor |
| Kafka/n8n event stopped firing after adding another | Only one `after_flush_row_event` per class is honored | Consolidate per-class after-flush work into one handler (section 9e) |
| New rules file ignored | Not under `logic/logic_discovery/`, or lacks module-level `declare_logic()` | Section 11 template; check startup `..discovered logic:` list |
| Rule edits have no effect | Rules load only at startup activation | Restart the server (checklist step 5) |
| Autoincrement id is None in event | Pre-flush events run before the DB assigns ids | Use `after_flush_row_event` for anything needing generated ids |
| Python writes bypass logic (audit rows missing rules) | Raw `session.add`/attribute writes outside the engine | Use `logic_row.new_logic_row/link/insert`, `update`, `delete` — they run the cascade |
| Ugly TypeError trace when a constraint fires, but 400 is correct | Known 17.03.19 bug in `config/server_setup.py` `short_format_exception` | Cosmetic; do not "fix" logic — see **apilogicserver-debugging-playbook** |
| Security filtering inside logic queries | Logic is system code — `logic_row.session.query` is NOT subject to Grants | Expected (verified sample comment); enforce client-side access via **apilogicserver-security-model** |

## Provenance and maintenance

- Rule signatures (`Rule.constraint/commit_constraint/parent_check/sum/count/formula/copy`, event family, `RuleExtension.allocate/copy_row`) — read from installed LogicBank 1.32.0. Re-verify: `python -c "from logic_bank.logic_bank import Rule; help(Rule.formula)"` (venv active) or `pip show logicbank`.
- Engine/CLI version pairing (Genai-Logic 17.03.19). Re-verify: `als welcome`.
- 5-rule chain, stamping, request pattern, Kafka event — verbatim from generated samples. Re-verify in any project: `grep -rn "Rule\." logic/ | grep -v logic_discovery/auto` and `cat logic/logic_discovery/system/all_classes_stamping.py`.
- Discovery mechanics (walk subdirs, skip `auto_discovery.py`/`__init__.py`, call `declare_logic()`, wg_rules hook). Re-verify: `cat logic/logic_discovery/auto_discovery.py`; startup line `..discovered logic: [...]`.
- Constraint 400 payload with interpolated `error_msg` and `"code": "2001"`; where-clause discriminating experiment (shipped PATCH succeeds, unshipped 400s). Re-verify: login then PATCH an Item quantity to a violating value (checklist step 7) against unshipped vs shipped orders.
- Logic-log format (`Logic Phase:` sections, `[old-->] new`, "These Rules Fired"). Re-verify: watch server console during any transaction.
- One-after-flush-per-class limit — source comment in `logic/logic_discovery/integration.py` (nw sample). Re-verify: `grep -n "only one after_flush" logic/logic_discovery/integration.py`.
- `short_format_exception` logging bug (17.03.19). Re-verify: `grep -n "splitlines" config/server_setup.py` — fixed when the argument is a bool/absent.
- Allocation runtime behavior and `insert_parent=True` — per docs, not live-verified; re-check against the LogicBank Allocation sample before teaching further.
- Grounded in: https://apilogicserver.github.io/Docs/Logic-Type-Constraint/, Logic-Type-Formula/, Logic-Type-Sum/, Logic-Type-Copy/, Logic-Type-Events/, Logic-Type-Constraint-Commit/, Logic-Use/, Logic-Allocation/, Logic-Tutorial/ and a live Genai-Logic 17.03.19 install (2026-08-23), verified against a live install's basic_demo and nw sample projects.
