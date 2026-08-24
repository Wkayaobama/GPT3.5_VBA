---
name: apilogicserver-validation-and-qa
description: Validation and QA discipline for API Logic Server (Genai-Logic) projects - what counts as evidence that logic works, the certified Behave golden suite (7 features / 26 scenarios / 83 steps, ~1.4s), and how to add tests. Owns test/api_logic_server_behave/ (behave_run.py, behave_logic_report.py, features/, steps/ with test_utils.login and prt, logs/scenario_logic_logs/), the Behave Logic Report as requirements-traceability, rejection tests (asserting a constraint fires), predicted-numbers assertions, seeded rows (ALFKI, order 10643, Employee 5), state restoration truth, and als curl-test. Use when asked "how do I test this", "is this change done", "prove the rule fired", or on symptoms: behave fails, Assertion Failed in behave.log, scenario passed but data now wrong, "looks right in the admin app", stale test data after failed run, Behave Logic Report missing or empty, PYTHONHASHSEED checksum mismatch, step never matched, adding a scenario, regenerating requirements documentation.
---

# API Logic Server: Validation and QA

## Purpose

This skill defines what counts as proof that an API Logic Server (ALS) behavior change works, catalogs the certified Behave test inventory shipped with the Northwind sample, and gives the exact procedure to run the suite, read its artifacts, and add new scenarios. The core discipline: a change is done when a Behave scenario proves it AND the Behave Logic Report shows which rules fired — never when it "looks right" in the admin app.

## Use this skill when

- Deciding whether a logic/API/security change is "done" and what evidence to demand.
- Running or reading the Behave suite (`test/api_logic_server_behave/`), `behave.log`, or the Behave Logic Report.
- Writing a new `.feature` scenario or its step implementation (including rejection tests).
- Tests fail, data is left dirty after a failed run, or scenario logic logs are missing.
- Producing requirements-as-documentation for stakeholders or a PR.

## Do NOT use this skill when

- You need rule syntax or worked logic patterns → **apilogicserver-logic-patterns**.
- You are debugging WHY a rule fired or did not fire → **apilogicserver-debugging-playbook** (this skill proves; that one diagnoses).
- You need JSON:API call shapes (filters, PATCH payloads, custom endpoints) → **apilogicserver-api-contract**.
- You need to start/stop the server or fix ports → **apilogicserver-operate-and-deploy**.
- You are landing the change (what to edit, rebuild flow, PR gates) → **apilogicserver-change-control**.
- You want AI to generate tests from rules → **apilogicserver-genai-development** (this skill covers only the acceptance bar those tests must meet).

---

## 1. The evidence bar (policy)

**Policy: "Looks right in the admin app" is NEVER evidence. A behavior change is done when (a) a Behave scenario asserts the outcome with predicted numbers and passes, and (b) its Behave Logic Report section shows the rules that fired.**

Rationale — why UI eyeballing fails here specifically:

1. **Chained effects land on rows you are not looking at.** One `add_order` POST in the sample adjusts `Order.AmountTotal`, `Customer.Balance`, `Product.UnitsShipped`, and recomputed `Product.UnitsInStock` — four tables from one transaction (verified 2026-08-23, Genai-Logic 17.03.19, scenario "Good Order Custom Service"). An admin-app screen shows one row; the bug is on the row you did not open.
2. **The logic log is the ground truth of what fired.** ALS writes a per-transaction logic log showing each touched row with old→new values (`[old-->] new`) and a "These Rules Fired" list. A green screen cannot tell you a formula was pruned, a sum adjusted, or a constraint checked; the log can. (A *derivation* is a rule-computed value such as a sum or formula; a *constraint* is a rule that rejects a transaction; see **declarative-rules-reference** for phases.)
3. **Rejections need proof too.** Half of business logic is refusing bad transactions. Only a test that submits a bad transaction and asserts the exact error text (e.g. `"exceeds credit"`) proves the constraint exists, fires, and rolls back. You cannot eyeball a rollback.
4. **Regression cost.** The certified suite replays 26 scenarios in ~1.4 seconds (verified 2026-08-23). Manual re-checking after every rule edit does not scale and silently decays.

Evidence table — what to accept:

| Claim | Acceptable evidence | Not acceptable |
|---|---|---|
| Derivation computes correctly | Behave `Then` asserting before/after values with a **predicted number** (e.g. Balance +56) | Screenshot, "the number changed" |
| Constraint rejects bad data | Behave `Then` asserting HTTP error body contains the constraint's `error_msg` text | "I couldn't save it in the UI" |
| Rule chain fired (and only it) | "Rules Used" + Logic Log section in the Behave Logic Report for that scenario | Server "started OK" |
| No unintended side effects | Assertions on OTHER rows (parent balance, product stock) in the same scenario | Checking only the row you changed |
| Security filters rows | Behave scenario logging in as the restricted user and asserting the row COUNT (see authorization.feature) | Browsing as admin |
| Whole system still healthy | Full suite green: features/scenarios/steps all passed, exit code 0 | One scenario green |

The Behave *Logic Report* additionally serves as **requirements-as-documentation**: Gherkin text (Given/When/Then business phrasing) plus the rules that implement it plus the execution trace, in one reviewable file. Attach or reference it in PRs — see **apilogicserver-change-control** for docs-of-record conventions.

---

## 2. Certified golden inventory (verified 2026-08-23, Genai-Logic 17.03.19)

The Northwind-with-customizations sample (`als create --db-url=nw+`) ships a complete Behave suite. Certified all-green run: **7 features passed, 26 scenarios passed, 83 steps passed, 0 failed, ~1.4s**, against a running server with security enabled.

*Behave* is a Python BDD (Behavior-Driven Development) framework: business-readable `.feature` files in *Gherkin* syntax (Given/When/Then lines, grouped into *scenarios*, grouped into *features*) bind to Python *step* functions via decorators.

| Feature file | Feature name | Scenarios | Purpose (from reading the files) | Verification |
|---|---|---|---|---|
| `about.feature` | About Sample | 1 | Smoke test: PATCH Category description to invalid value `x`; constraint rejects; also emits the Rules Report into the logic log | verified on disk + in report |
| `api.feature` | Application Integration | 2 | JSON:API reads (JSON:API = the REST response/payload convention ALS APIs speak; details in **apilogicserver-api-contract**): filtered GET Order 10248 returns VINET; GET Department 2 with self-relationship `include` returns sub-departments | verified on disk |
| `authorization.feature` | Authorization | 5 | Row security by login: u1 sees 1 Category (Grant), sam sees 3 Customers (multi-tenant), sam sees 8 Departments (GlobalFilter), s1 sees 1 Customer, r1 delete Shipper refused (`does not have delete access`) | verified on disk |
| `opt_locking.feature` | Optimistic Locking | 4 | `S_CheckSum` handling: read checksum; PATCH with valid checksum (passes lock, then fails description constraint); missing checksum; invalid checksum → `Sorry, row altered by another` | verified on disk |
| `place_order.feature` | Place Order | 10 | The logic showcase: ready-flag adjustments, good order (chain up, email + Kafka events, delete re-adjusts), empty-order rejection, two credit-limit rejections, pruning (RequiredDate no-op), ship/unship adjustments ±1086, clone via `copy_children` | verified on disk + live |
| `salary_change.feature` | Salary Change | 3 | Audit row on salary change (`copy_row`), virtual attribute `ProperSalary` present in GET, and rejection: raise under 20% refused | verified on disk + live |
| `tests_successful.feature` | Tests Successful | 1 | Sentinel: writes "Behave Run Successfully Completed" marker through the server into the logic logs | verified on disk |

Suite directory map (project-relative; verified on disk):

```
test/api_logic_server_behave/
├── behave_run.py                  # runner wrapper (see §4)
├── behave_logic_report.py         # report generator (see §4)
├── check_step_order.py            # step-pattern ordering linter (see §6)
├── AI-Generated-Tests-from-Rules.md   # background doc on AI test generation
├── features/                      # one .feature per use case
│   └── steps/                     # one steps .py per feature
│       ├── test_utils.py          # login() + prt() helpers (see §3)
│       └── test_data_helpers.py   # create-fresh-test-data scaffolds (see §6)
├── logs/
│   ├── behave.log                 # per-step pass listing (from --outfile)
│   └── scenario_logic_logs/       # one <Scenario_name_trunc>.log per scenario
└── reports/
    ├── Behave Logic Report.md     # generated requirements doc
    └── Behave Logic Report Intro.md   # prepended header content
```

A `basic_demo` project created with `als create --db-url=basic_demo` plus `als add-cust` gets the same skeleton but only `about.feature` plus a `test/basic/server_test.py` smoke test — the golden inventory above is the nw+ sample's (verified 2026-08-23 by comparing both trees).

---

## 3. Anatomy of a test (verbatim from the certified suite)

### 3.1 The feature file — business-readable contract

From `features/place_order.feature` (verbatim):

```gherkin
Feature: Place Order

  Scenario: Good Order Custom Service
     Given Customer Account: ALFKI
      When Good Order Placed
      Then Logic adjusts Balance (demo: chain up)
      Then Logic adjusts Products Reordered
      Then Logic sends email to salesrep
      Then Logic sends kafka message
      Then Logic adjusts aggregates down on delete order

  Scenario: Alter Item Qty to exceed credit
     Given Customer Account: ALFKI
      When Order Detail Quantity altered very high
      Then Rejected per Check Credit
```

Annotation: `Given` = establish/capture data state. `When` = submit ONE transaction through the live API. `Then` = assert derivations and constraint outcomes — note the rejection scenario is a first-class citizen.

### 3.2 Step implementations — how they authenticate and call the API

From `features/steps/place_order.py` (verbatim, including the real imports and the suite's own comments):

```python
from behave import *
import requests, pdb
import test_utils
import sys
import json
from dotmap import DotMap          # dict -> attribute access (result.data.attributes)

logic_logs_dir = "logs/scenario_logic_logs"

def get_ALFLI():                   # (sic - typo is in the shipped suite)
    get_uri = 'http://localhost:5656/api/Customer/ALFKI/?include=OrderList&fields%5BCustomer%5D=Id%2CCompanyName%2CBalance%2CCreditLimit%2COrderCount%2CUnpaidOrderCount'
    header = test_utils.login()    # JWT Bearer header (see below)
    r = requests.get(url=get_uri, headers= header)
    ...
    result_map = DotMap(json.loads(r.text))
    return result_map.data.attributes

@given('Customer Account: ALFKI')
def step_impl(context):
    alfki_before = get_ALFLI()
    context.alfki_before = alfki_before    # context carries state across steps
```

The `@when` announces the scenario to the server (so the server routes this transaction's logic log to a per-scenario file), then calls the API — here a custom endpoint (see **apilogicserver-api-contract** for `ServicesEndPoint`):

```python
@when('Good Order Placed')
def step_impl(context):
    """ (docstring: becomes the 'Logic Doc' section of the Behave Logic Report) """
    scenario_name = 'Good Order Custom Service'
    add_order_uri = f'http://localhost:5656/api/ServicesEndPoint/add_order'
    add_order_args = {
        "meta": { "method": "add_order", "args": {
                "CustomerId": "ALFKI", "EmployeeId": 1, "Freight": 11,
                "OrderDetailList": [
                    {"ProductId": 1, "Quantity": 1, "Discount": 0},
                    {"ProductId": 2, "Quantity": 2, "Discount": 0}]}}}
    test_utils.prt(f'\n\n\n{scenario_name} - verify adjustments...\n', scenario_name)
    r = requests.post(url=add_order_uri, json=add_order_args, headers=test_utils.login())
    context.response_text = r.text
```

The `@then` asserts a **predicted number**, and guards against a dirty database (verbatim):

```python
@then('Logic adjusts Balance (demo: chain up)')
def step_impl(context):
    before = context.alfki_before
    assert before.Balance == 2102.0, "Looks like database does not have starting values"
    expected_adjustment = 56  # find this from inspecting data on test run
    after = get_ALFLI()
    context.alfki_after = after
    assert before.Balance + expected_adjustment == after.Balance, \
        f'On add, before balance {before.Balance} + {expected_adjustment} != new Balance {after.Balance}'
```

Non-database effects are proven by asserting on the captured logic log file (verbatim):

```python
@then('Logic sends kafka message')
def step_impl(context):
        scenario_trunc = get_truncated_scenario_name(context.scenario.name)
        logic_file_name = f'{logic_logs_dir}/{scenario_trunc}.log'
        assert test_utils.does_file_contain(search_for="Sending Order to Shipping", in_file=logic_file_name), \
            "Logic Log does not contain 'Sending Order to Shipping'"
```

### 3.3 The two helpers every step uses (`features/steps/test_utils.py`, verbatim excerpts)

**`login(user='aneu')`** — reads the project's `config.config.Config` directly (behave is a standalone process; Flask env overrides do NOT apply here — the file says so). With the `sql` security provider it does the standard JWT (JSON Web Token) login and returns the header dict every request passes:

```python
post_uri = f'{server}/auth/login'
post_data = {"username": user, "password": "p"}
r = requests.post(url=post_uri, json = post_data)
token = DotMap(json.loads(r.text)).access_token
header = {'Authorization': 'Bearer {}'.format(f'{token}')}
```

Default user is `aneu`; authorization steps pass others: `test_utils.login(user='u1')`, `'sam'`, `'s1'`, `'r1'` (all password `p` — see **apilogicserver-security-model** for the sample auth DB). If `Config.SECURITY_ENABLED == False`, `login()` returns `{}` (empty headers). A keycloak branch exists (per docs, not live-verified).

**`prt(msg, scenario_name)`** — the logic-log capture trick. It calls the running server:

```python
msg_url = f'http://localhost:5656/server_log?msg={msg}&test={test}&dir=test/api_logic_server_behave/logs/scenario_logic_logs'
r = requests.get(msg_url)
```

The server then writes the message AND all subsequent logic logging into `logs/scenario_logic_logs/<Scenario_name>.log`. Scenario names are truncated to 25 characters and spaces become underscores (e.g. `Good_Order_Custom_Service.log`, `Alter_Item_Qty_to_exceed_.log` — verified on disk). **If a `@when` forgets to call `prt(...)` with the scenario name, that scenario gets no logic log and an empty section in the report.**

### 3.4 The rejection test pattern (`salary_change.feature` — "Reject - Raise too small")

Asserting a constraint FIRES is as important as asserting success. Verbatim from `features/steps/salary_change.py`:

```python
@when('Patch Salary to 96k')
def step_impl(context):
    scenario_name = 'Raise Must be Meaningful'
    test_utils.prt(f'\n\n\n{scenario_name}... alter salary, ensure audit row created (also available in shell script\n\n', scenario_name)
    patch_emp_uri = f'http://localhost:5656/api/Employee/5/'
    patch_args = \
        {
            "data": {
                "attributes": {
                    "Salary": 96000,
                    "Id": 5},
                "type": "Employee",
                "id": 5
            }}
    r = requests.patch(url=patch_emp_uri, json=patch_args, headers= test_utils.login())
    context.response_text = r.text

@then("Reject - Raise too small")
def step_impl(context):
    response_text = context.response_text
    assert 'meaningful raise' in response_text, f'Error - "meaningful raise" not in response:\n{response_text}'
```

The rule under test (verbatim from `logic/logic_discovery/employee_state_transition_logic/raise_over_20_percent.py` — a state-transition constraint using `old_row`, the pre-update image):

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

Anatomy of a rejection test: (1) `@when` submits the bad transaction (95000 → 96000 is under a 20% raise); (2) `@then` asserts the interpolated `error_msg` text appears in the HTTP response; (3) the transaction is rolled back so no cleanup is needed. Constraint violations return HTTP 400 with error code `"2001"` (verified live; shapes in **apilogicserver-api-contract**). Every constraint you add deserves one passing (just-legal) and one rejecting (just-illegal) scenario.

Also note the **restore-inside-test** pattern: the sibling scenario "Audit Salary Change" patches Salary to 200000, verifies an `EmployeeAudit` row exists, then PATCHes Salary back to 95000 inside its own `@then` — that is how this suite keeps the database re-runnable (see §6).

---

## 4. Run procedure (verified 2026-08-23, Genai-Logic 17.03.19)

**Precondition: the server must be running.** Behave drives the LIVE HTTP API at `http://localhost:5656` — it does not import the app. Start it first (`python api_logic_server_run.py` from the project root; details in **apilogicserver-operate-and-deploy**). Run with security enabled for the full suite — `authorization.feature` logs in as five different users. Do not run the suite against a database you care about: the tests write data.

1. Run the suite:
   ```bash
   cd test/api_logic_server_behave
   python behave_run.py --outfile=logs/behave.log
   ```
   Expect on the console: per-feature progress, then a summary — the certified run printed `7 features passed`, `26 scenarios passed`, `83 steps passed`, 0 failed, in ~1.4s — and exit code 0. Note: the summary counts go to the **console**, not into `behave.log`; the log gets the per-step listing.
2. `behave_run.py` is a thin wrapper over `behave.__main__` (read it — 64 lines). Two behaviors matter:
   - It fixes the working directory to the script's parent if `features/` is not under the current directory.
   - After the run it re-reads the outfile and **forces exit code 1 if the text `Assertion Failed` appears**, because "evidently behave eats the exceptions" (comment in the file). CI must check the exit code, not just the log.
3. Read `logs/behave.log`: every step listed with its implementing file and line, e.g.
   ```
   Scenario: Raise Must be Meaningful         # features/salary_change.feature:13
     Given Employee 5 (Buchanan) - Salary 95k # features/steps/salary_change.py:9
     When Patch Salary to 96k                 # features/steps/salary_change.py:84
     Then Reject - Raise too small            # features/steps/salary_change.py:116
   ```
   Failures appear as `Assertion Failed` with the step's failure message. Per-scenario logic logs land in `logs/scenario_logic_logs/*.log` (16 files after the certified run).
4. Run one scenario only (exact form from the project's `.vscode/launch.json` "Behave Scenario" config, verified):
   ```bash
   python behave_run.py --outfile=logs/behave.log --name="Clone Existing Order"
   ```
5. Generate the report (after a run — it consumes `logs/behave.log` + the scenario logic logs):
   ```bash
   python behave_logic_report.py run
   ```
   Expect: `reports/Behave Logic Report.md` rewritten (~121KB after the certified run). The VS Code "  - Behave Logic Report" config additionally passes `--prepend_wiki=reports/Behave Logic Report Intro.md --wiki=reports/Behave Logic Report.md` (verified in `.vscode/launch.json`).
6. VS Code alternatives (launch config names verified in `.vscode/launch.json`): `Behave Run` (sets env `SECURITY_ENABLED=True`), `  - Behave No Security`, `  - Behave Scenario`, `  - Behave Logic Report`. Docs also name a `Windows Behave Run` variant (per docs, not live-verified).

### What the report looks like (verbatim excerpt, certified run of 2026-08-23)

Each scenario renders its Gherkin, a disclosure box, the step docstring ("Logic Doc"), the **Rules Used**, and the **Logic Log**. From `reports/Behave Logic Report.md`, scenario "Raise Must be Meaningful" (long row-image lines trimmed with `<...>`):

```
### Scenario: Raise Must be Meaningful
&emsp;  Scenario: Raise Must be Meaningful
&emsp;&emsp;    Given Employee 5 (Buchanan) - Salary 95k
&emsp;&emsp;    When Patch Salary to 96k
&emsp;&emsp;    Then Reject - Raise too small
<details markdown>
<summary>Tests - and their logic - are transparent.. click to see Logic</summary>

**Logic Doc** for scenario: Raise Must be Meaningful
Logic Patterns:
* State Transition Logic
...
**Rules Used** in Scenario: Raise Must be Meaningful
```
  Employee
    1. Constraint Function: <function declare_logic.<locals>.raise_over_20_percent at 0x7f0639ff0900>
```
**Logic Log** in Scenario: Raise Must be Meaningful
```
Logic Phase:		ROW LOGIC		(session=0x7f0638ddfc90) (sqlalchemy before_flush)
..Employee[5] {Update - client} Id: 5, LastName: Buchanan, <...> Salary:  [95000.0000000000-->] 96000, <...> ins_upd_dlt: upd
..Employee[5] {Constraint Failure: Buchanan needs a more meaningful raise} Id: 5, <...> Salary:  [95000.0000000000-->] 96000, <...>
```
</details>
```

Read it as: the requirement (Gherkin), the implementing rule (Rules Used), and the proof it executed — old value 95000, attempted 96000, named constraint failure. That triple is the evidence bar from §1 made concrete. Logic-log line format (`[old-->] new`, phases) is explained in **declarative-rules-reference**; symptom-driven reading in **apilogicserver-debugging-playbook**.

---

## 5. "Add a scenario" checklist

1. **Pick ONE use case** = one transaction through the API with a business-visible outcome (a derivation chain, or a rejection). If the logic does not exist yet, write it first per **apilogicserver-logic-patterns**.
2. **Predict the numbers before you run anything.** From current data, hand-compute the expected before/after values (the certified suite's comments say exactly this: `expected_adjustment = 56  # find this from inspecting data on test run`). A test without a predicted number only proves "something changed".
3. **Write the `.feature`** in `test/api_logic_server_behave/features/` — Given data state / When transaction / Then expected derivations AND constraint outcomes, with the numbers in the step text where readable (`Then Balance reduced 1086`).
4. **Implement steps** in `features/steps/<feature>.py`, copying the suite's conventions:

```python
from behave import *
import requests, json
import test_utils

@given('Customer Account: XYZ')
def step_impl(context):
    r = requests.get(url='http://localhost:5656/api/Customer/XYZ/',
                     headers=test_utils.login())
    context.before = json.loads(r.text)['data']['attributes']

@when('My Transaction Submitted')
def step_impl(context):
    scenario_name = 'My Scenario Name'          # MUST match the .feature scenario line
    test_utils.prt(f'\n\n\n{scenario_name}...\n', scenario_name)   # routes logic log capture
    patch_args = {"data": {"attributes": {"SomeColumn": 42, "Id": 1},
                           "type": "Order", "id": 1}}               # JSON:API shape
    r = requests.patch(url='http://localhost:5656/api/Order/1/',
                       json=patch_args, headers=test_utils.login())
    context.response_text = r.text

@then('Balance adjusted by predicted amount')
def step_impl(context):
    expected_adjustment = 999    # PREDICTED from data inspection, never observed-then-pasted blindly
    r = requests.get(url='http://localhost:5656/api/Customer/XYZ/', headers=test_utils.login())
    after = json.loads(r.text)['data']['attributes']
    assert context.before['Balance'] + expected_adjustment == after['Balance'], \
        f"expected {context.before['Balance']} + {expected_adjustment}, got {after['Balance']}"

@then('Rejected per My Constraint')
def step_impl(context):
    assert 'my error_msg fragment' in context.response_text, \
        f'constraint text not in: {context.response_text}'
```

   Conventions this skeleton preserves (all verified in the shipped suite): `test_utils.login()` on every request; `test_utils.prt(...)` in every `@when` (or the scenario has no logic log); step docstrings become the report's Logic Doc — write them for the business reader; leave the database as you found it (compensating write or delete in a final `Then`, as "Audit Salary Change" and "Good Order Custom Service" do).
5. **Order step patterns most-specific-first** if you use parameterized steps — behave binds each step to the FIRST matching pattern. Check with `python check_step_order.py` from `test/api_logic_server_behave/` (script shipped in the suite, verified on disk; docs call this "Rule #0.5").
6. **Run the suite** (§4) — the whole suite, not just your scenario, to catch data interference. All green, exit 0.
7. **Regenerate the report** (`python behave_logic_report.py run`) and read your scenario's section: does "Rules Used" list exactly the rules you meant? An unexpected extra rule firing is a finding, not a formality.
8. **Land it via change-control**: the new `.feature` + steps + regenerated `reports/Behave Logic Report.md` go in the same change set as the logic, through the gates in **apilogicserver-change-control**. A rule change without its scenario does not pass review.

---

## 6. Test data: what the suite assumes, and the honest restoration story

### Seeded rows the certified suite depends on

The suite hard-codes well-known sample rows (documented in the `place_order.py` header docstring and step code; key values re-verified live 2026-08-23):

| Row | Used by | Verified value (2026-08-23, live GET) |
|---|---|---|
| Customer `ALFKI` | most place_order scenarios | Balance **2102.0**, CreditLimit **2300.0** |
| Order `10643` (ALFKI) | ship/unship/pruning/clone scenarios | amount 1086 (per suite docstring) |
| Order `11011` (ALFKI) | Ready-flag scenarios | adjustment 960 (per step comment) |
| OrderDetail `1040` | "Alter Item Qty to exceed credit" | quantity patched to 1110 |
| Employee `5` (Buchanan) | all salary_change scenarios | Salary **95000.0** |
| Product `46` (Spegesild) | "Set Shipped" stock assertions | UnitsInStock +2 on ship |
| Customer `VINET`, Order `10248` | api.feature | filtered GET |
| Category `1`, Department `2`, Shipper `1` | about / api / opt_locking / authorization | fixed IDs |
| Users `aneu` (default), `u1`, `sam`, `s1`, `r1`, password `p` | login in every step / authorization counts (1, 3, 8, 1 rows) | sample auth DB (**apilogicserver-security-model**) |

The `assert before.Balance == 2102.0, "Looks like database does not have starting values"` guard means: **wrong seed data fails fast with that exact message** — restore before debugging anything else.

### Does the suite restore state? (what is actually true, from reading the steps)

- **There is no snapshot/rollback mechanism.** No fixture saves or restores `database/db.sqlite`; grep of the suite finds no restore code (verified 2026-08-23).
- **On success, yes — by compensating transactions written into the scenarios themselves**: "Audit Salary Change" patches Salary back to 95000 in its `@then`; "Good Order Custom Service" ends by finding and DELETEing the order it created (asserting Balance returns to start); "Order Made Not Ready" (−960) is immediately followed by "Order Made Ready" (+960); "Set Shipped" (−1086) is followed by "Reset Shipped" (+1086). **Scenario order is therefore load-bearing** — behave runs features alphabetically by filename and scenarios in file order; do not reorder or cherry-pick paired scenarios. Live proof the mechanism works: after the certified all-green run, GETs show ALFKI Balance back at 2102.0 and Buchanan Salary back at 95000.0 (verified 2026-08-23).
- **On failure, no.** The suite's own docstring: "if tests fail, database may have been altered (restore then required)". A half-run leaves partial writes.

### Restoring the database

- **Cheapest insurance (sqlite projects):** keep a pristine copy of `database/db.sqlite` under source control or copy one aside before risky work (`cp database/db.sqlite database/db.sqlite.golden` — then copy back with the server STOPPED). Source-control discipline for the db file: **apilogicserver-change-control**.
- **GenAI-created projects — per docs (Database-Changes/IDE-Rebuild-Test-Data), not live-executed here:** `als genai-utils --rebuild-test-data` regenerates test data in three steps — from `docs/response.json` build `database/test_data/test_data.py`, execute it to create `database/test_data/db.sqlite`, copy over `database/db.sqlite`. The flag exists in the 17.03.19 CLI (`als genai-utils --help` lists `--rebuild-test-data`, verified 2026-08-23). The docs' key principle: "Proper rule operation requires existing data be correct" — seed data must already satisfy your derivation rules, or every aggregate assertion starts from a lie. The nw sample's launch configs `REBUILD TEST DATA 1/2` run `database/test_data/response2code.py --test-data --response=docs/response.json` and `test_data_code.py` (config verified on disk; not executed here).
- **Last resort for samples:** re-create the project (`als create --db-url=nw+` — see **apilogicserver-cli-and-config**) and copy the fresh `database/db.sqlite` in.

### Writing tests that do not depend on seeds at all

`features/steps/test_data_helpers.py` (shipped in the suite) scaffolds the alternative: create fresh rows per test with millisecond-timestamp names (`unique_name = f"{name} {int(time.time() * 1000)}"`) so reruns never collide — the docs call this repeatability "Rule #0". Its header also encodes a trap worth repeating: **never POST a value into a derived aggregate** (e.g. balance) — it is rule-computed; create the child rows that derive it instead (see **apilogicserver-data-modeling** for aggregate columns). Adapt attribute names to your schema before using the scaffold.

### Repeatability footnote: optimistic locking

`opt_locking.feature` compares `S_CheckSum` values (optimistic locking = detect concurrent edits via a row checksum). The step file notes `# requires export PYTHONHASHSEED=0` for a stable expected checksum across processes (comment verified on disk; docs state the same). The shipped step self-heals by capturing the live checksum on first GET, but set `PYTHONHASHSEED=0` if you pin checksum literals in your own tests.

---

## 7. Scope boundaries

- **Behave = acceptance tests against the live API.** They exercise the full stack (HTTP → JSON:API → rules engine → database) exactly as clients do, and double as requirements documentation. Docs position them within a TDD workflow: write feature → implement steps → run → generate report (per docs, not a tool mandate).
- **Unit/smoke tests are separate and thinner.** `test/basic/server_test.py` (present in created projects; VS Code config "Test - test/basic/server_test.py") is a quick server smoke, not logic evidence. Nothing stops you adding pytest units for pure helpers, but logic evidence stays behavioral — rules only fire through the server's SQLAlchemy session (see **apilogicserver-architecture-contract**).
- **`als curl-test`** exists: CLI help reads "Test curl commands (nw only; must be r)" (verified 2026-08-23) — restricted to the nw sample; do not build project QA on it. Its sibling `als curl` ("Execute cURL command, providing auth headers from login") is a convenience for ad-hoc probes — usage in **apilogicserver-api-contract**.
- **AI-generated tests:** the suite ships `AI-Generated-Tests-from-Rules.md`, and docs reference training material for generating Behave tests from declared rules (`docs/training/testing.md`), with the caveat that generated scenarios can miss foreign-key-reassignment cases and need human review (per docs, not live-verified). Generation workflow lives in **apilogicserver-genai-development**; whatever generates a test, it must still clear §1's evidence bar and §5's checklist.
- **Behave Logic Report as docs-of-record** (referencing it from PRs, CLAUDE.md conventions): **apilogicserver-change-control**.

---

## Provenance and maintenance

Volatile facts and how to re-verify each (run from a project root created by `als create --db-url=nw+`, server running):

- Golden counts (7 features / 26 scenarios / 83 steps, ~1.4s): `cd test/api_logic_server_behave && python behave_run.py --outfile=logs/behave.log` and read the console summary.
- Suite file map: `ls -R test/api_logic_server_behave`
- Feature/scenario inventory: `grep -c Scenario: test/api_logic_server_behave/features/*.feature`
- `behave_run.py` "Assertion Failed" forced-exit behavior: `sed -n 55,64p test/api_logic_server_behave/behave_run.py`
- Report command and output: `cd test/api_logic_server_behave && python behave_logic_report.py run && ls -la reports/`
- Single-scenario flag and launch-config names: `grep -n "name\|--name" .vscode/launch.json | grep -i behave`
- Login/prt helper behavior: `sed -n 1,60p test/api_logic_server_behave/features/steps/test_utils.py`
- Seed values (ALFKI 2102/2300, Buchanan 95000): `als login --user=admin --password=p` then GET `/api/Customer/ALFKI/` and `/api/Employee/5/` per **apilogicserver-api-contract** (or curl with a Bearer token).
- `als curl-test` nw-only restriction: `als curl-test --help`
- `--rebuild-test-data` flag existence: `als genai-utils --help`
- Step-order linter: `cd test/api_logic_server_behave && python check_step_order.py`

Grounded in: https://apilogicserver.github.io/Docs/Behave/, https://apilogicserver.github.io/Docs/Behave-Creation/, https://apilogicserver.github.io/Docs/Behave-Logic-Report/, https://apilogicserver.github.io/Docs/IDE-Rebuild-Test-Data/ and a live Genai-Logic 17.03.19 install (2026-08-23) — suite source, logs, report, and API probes verified against a live install of the nw+ sample.
