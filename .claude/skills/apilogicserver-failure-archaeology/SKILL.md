---
name: apilogicserver-failure-archaeology
description: >-
  Chronicle of settled battles, dead ends, and open bugs in API Logic Server /
  Genai-Logic — symptom → root cause → evidence → status — so nobody re-fights
  them. Covers: why a Rete/BRMS decision engine was rejected for transaction
  logic (aggregate-query cost, manual invocation, no old/new deltas); what
  Versata (700+ sites, ~97% logic automated) and CA Live API Creator proved,
  and their studio/distribution lessons; the aggregate-performance wall settled
  by adjustment ("minutes to 2 seconds"); the 5-rules-vs-200-lines explosion;
  the rebuild-clobber/admin-merge trap; environment hell (port 5656 in use,
  venv, PATH, DB drivers); the OPEN short_format_exception splitlines TypeError
  logging bug (config/server_setup.py, v17.03.19); the Excel/VBA legacy
  exhibit; GenAI overreach. Use when someone proposes Rete/Drools or "just
  re-aggregate", asks "has this been tried before", sees a TypeError stack
  trace when a constraint fires, cites product lineage, or wants to reopen a
  settled debate.
---

# API Logic Server Failure Archaeology

## Purpose

This skill is the incident-and-decision ledger for API Logic Server (the product now installed as **Genai-Logic**). Every major investigation, rejected approach, performance wall, recurring trap, and known bug is recorded here once, in a fixed format, with evidence, so a zero-context engineer or model does not re-run a settled experiment or misread a known bug as a new one. Wrong conclusions about history are expensive: the entries below name what was tried, what the evidence was, and what the standing verdict is.

## Use this skill when

- Someone proposes adopting a Rete/BRMS engine (Drools, etc.) for transaction logic, or asks "why not Rete?" → read A1 before responding.
- Someone asks whether declarative transaction rules are "proven" or just a demo idea → A2, A3.
- A rule-heavy transaction is feared or observed to be slow, or someone proposes recomputing aggregates with `SELECT SUM` → A4.
- Someone proposes writing multi-table logic as procedural handler code, or an AI has generated pages of it → A5, A10.
- A rebuild appears to have "overwritten customizations", or `admin-created.yaml` / `admin-merge.yaml` appeared → A6.
- The server won't start, `als` behaves like an older version, a driver won't build, or "Port 5656 is in use" → A7.
- A constraint violation produces a `TypeError: 'str' object cannot be interpreted as an integer` stack trace in the console → A8 (known logging bug; the engine is fine).
- You are assessing the legacy Excel/VBA artifact in this repo, or any application-embedded API glue like it → A9.
- Anyone wants to merge AI-generated schema or logic without deterministic verification → A10.
- You discovered a new failure or settled a new debate and need to record it → "How to add an entry".

## Do NOT use this skill when

- You are actively debugging a live symptom step-by-step → **apilogicserver-debugging-playbook** (this skill tells you whether the battle was already fought; that one tells you how to fight it).
- You need the *mechanism* of adjustment, pruning, ordering, or the full Rete-vs-LogicBank technical comparison → **declarative-rules-reference** (its §4–§5 own the theory; A1/A4 here own the historical verdict).
- You need the rebuild/merge *runbook* → **apilogicserver-change-control** (A6 here records why the trap exists; that skill owns the procedure).
- You need install/venv/driver *fixes* → **apilogicserver-build-and-env** (A7 here is the index of the cluster, not the repair manual).
- You are executing the legacy-to-ALS migration → **apilogicserver-modernization-campaign** (A9 here is the autopsy of the legacy artifact, not the campaign plan).
- You need GenAI command usage and guardrails → **apilogicserver-genai-development**.

---

## Entry format (strict — use it for every entry, including new ones)

Each entry carries exactly these fields:

1. **ID** — `A<n>`, never reused.
2. **Title** — short, names the battle.
3. **Date/era** — when it happened or was verified.
4. **Symptom or claim** — what a newcomer sees or says.
5. **Investigation** — what was actually done or read.
6. **Root cause / resolution** — the verdict.
7. **Evidence** — docs URL or verified artifact; every fact labeled `verified <date>, Genai-Logic <version>` or `per docs, not live-verified`.
8. **Status** — `SETTLED` (verdict stands; do not reopen without new evidence meeting the **apilogicserver-research-methodology** bar) | `OPEN` (real, unresolved; re-verify before building on it) | `MONITOR` (resolved by procedure or guardrail; watch for compliance drift). Compound statuses allowed where warranted (A6, A9).

Jargon used below, defined once:

- **BRMS** = Business Rule Management System. **Rete** = the pattern-matching algorithm behind classic BRMS *decision* engines (e.g. Drools).
- **Decision logic** = stateless rule evaluation, explicitly invoked, no database presumptions. **Transaction logic** = derivations and constraints enforced automatically on every database write.
- **ORM** = object-relational mapper (SQLAlchemy here). **Flush** = the point where the ORM emits pending row changes as SQL; ALS logic runs in `before_flush`.
- **Derivation** = a rule that computes a value (sum, count, formula, copy). **Constraint** = a rule condition that must hold or the transaction rolls back.
- **Adjustment** = updating a parent aggregate by applying the old→new delta of one child row (a one-row `UPDATE`) instead of re-aggregating all children.
- **venv** = Python virtual environment. **JSON:API** = the standardized REST response format ALS serves (`data/attributes/relationships`).

### Index

| ID | Title | Status | One-line takeaway |
|----|-------|--------|-------------------|
| A1 | The Rete question | SETTLED | Decision engines rejected for transaction logic: no old/new deltas → aggregate queries → orders-of-magnitude cost, plus manual-invocation integrity risk. |
| A2 | Versata — the enterprise proof | SETTLED | Rules ran 700+ enterprise sites, ~97% of logic automated; its studio-based delivery is the adoption lesson. |
| A3 | Live API Creator — proof #2, distribution lesson | SETTLED | Same architecture proved again commercially; proprietary + acquired = end-of-life; hence open source, plain files. |
| A4 | The aggregate-performance wall | SETTLED | Adjustment (delta, one-row update) + pruning replaced re-aggregation; docs: "minutes → 2 seconds, zero code changes". |
| A5 | The 200-line explosion | SETTLED | Procedural ordering/reuse failure: 5 rules ≡ ~200 lines; the comparison file is linked from every generated `declare_logic.py`. |
| A6 | Rebuild clobber / admin-merge trap | SETTLED / MONITOR | Rebuilds regenerate `models.py` but never `admin.yaml`; the created/merge YAML dance exists so customizations survive — if you do the dance. |
| A7 | Environment hell cluster | MONITOR | Top time-sink: port 5656 collision, venv-not-active, multi-Python PATH, driver builds. One-line detect each; fixes in build-and-env. |
| A8 | `short_format_exception` logging bug | OPEN | v17.03.19 `config/server_setup.py:~203` calls `splitlines('\n')` → TypeError while logging constraint violations. Cosmetic; integrity unaffected. |
| A9 | The legacy exhibit (`turbo3.5_excel_vba`) | SETTLED-BY-REPLACEMENT-PLAN | String-built JSON + InStr parsing + no error handling: application-embedded glue with no contract, gating, or evidence. |
| A10 | GenAI overreach guard | MONITOR | LLM output is accepted only as reviewable rules with deterministic verification, never as trusted code. |

---

## A1 — The Rete question

**ID:** A1 · **Title:** The Rete question · **Date/era:** design decision predating LogicBank/ALS; documented in the current FAQ.

**Symptom or claim:** "Why didn't ALS use a standard Rete/BRMS engine? Shouldn't we swap one in?"

**Investigation:** A Rete decision engine was evaluated against the requirements of transaction logic. The docs' full argument (FAQ-RETE, quoted verbatim, per docs):

1. **Category mismatch.** "RETE is appropriate for **Decision Logic**, where there are no presumptions about a database." ALS ships "Logic Bank, a purpose-built rules engine for **Transaction Logic**."
2. **Manual invocation risk.** "decision logic is *explicitly called*. That means that you need to audit *all* of the accessing code to verify the logic is enforced." Transaction logic instead guarantees "that all sqlalchemy access enforces the logic" — rules fire automatically in the ORM's `before_flush`, on every write path (JSON:API, custom endpoint, Admin App, integration).
3. **No old/new deltas → aggregate-query cost.** "Decision engines *cannot* make presumptions about old rows, so when they encounter a rule like `balance is sum of order amounts`, it has *no choice* but to read all the Orders (and each of their OrderDetails)." Consequence: "this can reduce performance by **multiple orders of magnitude**."
4. **What LogicBank does instead:** old-row access enables "pruning and sql optimizations" — "avoid expensive aggregate queries, and use the old/new delta to compute a 1-row adjustment to the parent row."

**Root cause / resolution:** Rete solves a different problem (stateless decisions) and structurally lacks the two things transaction logic needs: automatic enforcement bound to the ORM session, and old/new row deltas for adjustment-based aggregates. Rejected; LogicBank built instead. Mechanism details: **declarative-rules-reference** §4–§5.

**Evidence:** https://apilogicserver.github.io/Docs/FAQ-RETE/ (per docs). Live corroboration of the adjustment architecture: stack traces from the running engine show `logic_bank/exec_row_logic/logic_row.py` `_adjust_parent_aggregates()` → `save_altered_parents(do_not_adjust_list=...)` — adjustment calls, not aggregate queries (verified 2026-08-23, Genai-Logic 17.03.19).

**Status:** **SETTLED.** Do not re-propose a Rete/decision engine for transaction logic without new evidence meeting the **apilogicserver-research-methodology** bar (predicted numbers first, reproducible benchmark, old/new-delta semantics addressed).

## A2 — Versata: the enterprise proof

**ID:** A2 · **Title:** Versata — the enterprise proof · **Date/era:** production systems measured 1995–2010; IPO 2000. All business history here is **per docs, not live-verified**.

**Symptom or claim:** "Declarative transaction rules are academic — nobody ran a business on them."

**Investigation:** The docs' lineage pages record two commercial generations before ALS:

- Precursor: **PACE** (Wang's DBMS) — "over 6500 installed sites", with "several patents for rules and application generation".
- **Versata**, "a major innovator for business rules on J2EE": "over 700 sites"; funded by "Founders of Microsoft, SAP, Ingres and Informix"; IPO in "2000 with an IPO exceeding $3B"; priced "in the range of $35,000 - $50,000 per CPU".
- The load-bearing measurement: Val Huber (CTO/architect of both Versata and Genai-Logic) measured the automated-vs-manual code ratio across several dozen Versata production systems: **"94-99% of logic automated by rules, typically ~97%"** — the remaining 3–6% being "hand-written procedural code — event handlers and custom logic". That residual is why ALS rules are *extensible with Python events*, not rules-only.

**Root cause / resolution:** What it proved: rules cover the overwhelming majority of real transaction logic at enterprise scale, in production, for 15 years. What its era teaches (docs' own retrospective):

- "Pre-IDEs, the Versata Studio presented challenges in debugging, source control, etc."
- "While rules were effective, some clients found it difficult to achieve the look and feel they desired."
- "Many customers 'got' rules, but too many did not."
- The adoption killer: "As soon as you looked away, the devs all too often 'ran home to code'", because "Devs were resistant to studio-based rules if it meant losing their IDE."
- ALS's answers are direct negations: rules as plain Python in your own IDE (debugger, source control), open APIs for any client, standard containers. Versata also "gained value by riding the J2EE wave" — platform waves matter to distribution (see A3, A10).

**Evidence:** https://apilogicserver.github.io/Docs/FAQ-Versata/, https://apilogicserver.github.io/Docs/Tech-Proven/, https://apilogicserver.github.io/Docs/Tech-Realizations/ (all per docs; the docs give no customer names or transaction volumes — do not invent any).

**Status:** **SETTLED** (as historical proof; the ~97% figure is the docs' claim from its author's measurement, not reproduced here).

## A3 — Live API Creator: proof #2 and a distribution lesson

**ID:** A3 · **Title:** Live API Creator — proof #2 and a distribution lesson · **Date/era:** Espresso Logic → CA Technologies era, post-Versata; **per docs, not live-verified**.

**Symptom or claim:** "Maybe Versata was a one-off. And why is ALS open source instead of a commercial product?"

**Investigation:** Live API Creator (LAC, CA/Espresso Logic) was the second commercial build of the same architecture, per docs:

- "instant creation of projects with *multi-table APIs*" and "instant creation of *multi-page Admin Apps*";
- "declarative business logic - *rules, extensible with code*";
- role-based row security plus "role-based column security";
- the same people built both generations: the authors "served as lead engineers on both".
- Its fate: "CA/Live API Creator has reached end-of-life and soon end-of-support."

**Root cause / resolution:** Proof #2 that the API + admin-app + rules bundle works as a product. The distribution lesson: a proprietary product inside an acquired vendor dies on the vendor's schedule, not the users' — hence ALS's deliberate inversions, per docs: open source; IDE-driven rather than studio-based; "file-based artifacts manageable in GitHub"; self-serve APIs "not requiring central custom development"; and "GenAI: provides order of magnitude more simplicity and speed". A migration utility for LAC logic and security exists (per docs).

**Evidence:** https://apilogicserver.github.io/Docs/FAQ-Live-API-Creator/ (per docs).

**Status:** **SETTLED.** When evaluating ALS's longevity risk, cite this entry: the mitigation for "what if the vendor disappears" is that projects are plain Python files in your repo, runnable without any studio.

## A4 — The aggregate-performance wall

**ID:** A4 · **Title:** The aggregate-performance wall · **Date/era:** hit in the pre-ALS lineage; architecture carried into LogicBank; mechanism verified live 2026-08-23.

**Symptom or claim:** "Rule engines are slow for chained aggregates — each parent sum re-reads all children, so multi-level chains (Customer.balance ← Order.amount_total ← Item.amount) explode."

**Investigation:** True for engines that compute aggregates by query (see A1). The docs record the wall and its fall:

- Recomputing "balance is sum of order amounts" by reading "all the Orders (and each of their OrderDetails)" costs "multiple orders of magnitude" (per docs, FAQ-RETE).
- With adjustment, the docs' cited case went "from minutes to 2 seconds" — restated in FAQ-Overview as "minutes → 2 seconds, zero code changes" (per docs).
- Live verification of the mechanism (2026-08-23, Genai-Logic 17.03.19, basic_demo): PATCH one Item's `quantity` 1→100 on an unshipped order → formula recomputes `amount` (log shows `quantity:  [1-->] 100, amount:  [90.0000000000-->] 9000.0000000000` — old→new deltas are first-class) → `Order.amount_total` adjusted → `Customer.balance` adjusted → constraint rejects with HTTP 400.
- The same PATCH on a SHIPPED order succeeds, because the sum's `where=lambda row: row.date_shipped is None` excludes shipped orders — adjustment respects qualifications. This is the canonical discriminating experiment for "why didn't my constraint fire".
- Engine internals confirm one-row adjustment calls (`_adjust_parent_aggregates()`), not `SELECT SUM`.

**Root cause / resolution:** SETTLED by the adjustment architecture: aggregates are stored columns maintained by delta, derivations are pruned when their referenced attributes did not change, and execution order comes from dependency analysis at startup. Full mechanism: **declarative-rules-reference** §3–§4. Practical implication you must respect: stored aggregates mean **raw SQL that bypasses the ORM leaves sums stale** — see **apilogicserver-architecture-contract** invariants and **apilogicserver-change-control** ("stale sums after direct SQL").

**Evidence:** https://apilogicserver.github.io/Docs/FAQ-RETE/ and https://apilogicserver.github.io/Docs/FAQ-Overview/ (numbers per docs); chain experiment and logic-log excerpts verified 2026-08-23 against the live install; reproduce any time via **apilogicserver-debugging-playbook**.

**Status:** **SETTLED.** Anyone proposing "just recompute the sum per request" is proposing to rebuild the wall.

## A5 — The 200-line explosion

**ID:** A5 · **Title:** The 200-line explosion · **Date/era:** recurring across the Versata era and modern AI codegen; quantified in current docs and in every generated project.

**Symptom or claim:** "We'll just write the check-credit logic as normal handler code." Later: the handler misfires on one of the update paths, or ordering breaks when a dependency changes.

**Investigation:**

- Procedural multi-table logic fails on **ordering** (you must hand-sequence dependent computations), **reuse** (the same logic must be re-invoked for insert, update, delete, and reparenting on *each* table in the chain), and **change amplification** (a new dependency forces re-sequencing everything).
- The docs' modern measurement of the same failure: "AI, on its own, translates requirements to native code. Lots of it: 5 rules become 200 lines"; "The intent is obscured. You can't govern what you can't read"; the generated bugs were "hard to spot, but fatal to data integrity" (per docs, Tech-Realizations).
- FAQ-Overview states the ratio as "~40X more concise than procedural code" (per docs).
- Every generated project carries the receipt — quoted verbatim from `logic/declare_logic.py` of the live-created basic_demo project (verified on disk 2026-08-23, Genai-Logic 17.03.19; note the shipped comment's own typo, "200 lines of *declarative* Python", where *procedural* is plainly meant — the linked file is named `declarative-vs-procedural-comparison.md`):

  ```text
  The 5 *declarative* lines below represent the same logic as 200 lines of *declarative* Python
      1. To view the AI procedural/declarative comparison, [click here](https://github.com/ApiLogicServer/ApiLogicServer-src/blob/main/api_logic_server_cli/prototypes/basic_demo/logic/procedural/declarative-vs-procedural-comparison.md)
      2. Consider a 100 table system: 1,000 rules vs. 40,000 lines of code
  ```

- The five rules in question are the canonical check-credit chain (constraint, two sums, formula, copy — signatures in **apilogicserver-logic-patterns**).

**Root cause / resolution:** Procedural code makes ordering and reuse the programmer's job on every change; declaration makes them the engine's job once. This is the motivating failure behind the 5-rule pattern; the theory is **declarative-rules-reference** §2.

**Evidence:** `logic/declare_logic.py` comment (verified on disk in a live-created project, 2026-08-23); the comparison document at the GitHub URL quoted above (per docs/repo link, not fetched here); https://apilogicserver.github.io/Docs/Tech-Realizations/ and https://apilogicserver.github.io/Docs/FAQ-Overview/ (per docs).

**Status:** **SETTLED.** Hand-written procedural multi-table logic in an ALS project is a defect unless the case is a documented rules limit (declarative-rules-reference §7), in which case it goes in an event with a comment saying why.

## A6 — Rebuild clobber / admin-merge trap

**ID:** A6 · **Title:** Rebuild clobber / admin-merge trap · **Date/era:** inherent to the generate-then-customize lifecycle; current in 17.03.19.

**Symptom or claim:** "The rebuild overwrote my customizations!" — or its quieter twin, "the Admin App doesn't show the new column" weeks after a schema change.

**Investigation:** Two opposite mistakes share one root:

1. **Hand-edits placed in regenerated files.** `database/models.py` and `api/expose_api_models.py` are rewritten by `als rebuild-from-database` / `rebuild-from-model`, so edits there are lost by design — customizations belong in `database/customize_models.py`, `logic/`, `api/customize_api.py`.
2. **Merge artifacts ignored.** `ui/admin/admin.yaml` is **never overwritten after create**; a rebuild instead writes `ui/admin/admin-created.yaml` (fresh model from the new schema) and `ui/admin/admin-merge.yaml` (per docs, the merge of your `admin.yaml` with the new classes) *beside* it — precisely so your admin customizations survive. But new columns reach users only when you consciously merge and delete the artifacts. Skipping the dance yields a stale UI with no error.

**Root cause / resolution:** The created/merge-yaml dance exists exactly to protect customizations; the trap is not knowing which class a file is in. The clobber table, merge steps, and Alembic flow are owned by **apilogicserver-change-control** (§3–§4 there) — every schema-change procedure must end at that skill's gates.

**Evidence:** File classes and merge-artifact behavior verified on disk in both live-created projects, 2026-08-23, Genai-Logic 17.03.19 ("`ui/admin/admin.yaml` … never overwritten after create; rebuilds write admin-created.yaml / admin-merge.yaml per docs Database-Changes"); docs page Database-Changes (per docs, cited via change-control).

**Status:** **SETTLED by procedure, MONITOR for compliance.** Every PR touching schema gets checked for stray `admin-created.yaml` / `admin-merge.yaml` / `expose_api_models_created.py` left unmerged.

## A7 — Environment hell cluster

**ID:** A7 · **Title:** Environment hell cluster · **Date/era:** perpetual; port collision verified live 2026-08-23. Ratified by this skill library's owner as the top time-sink across the project's history.

**Symptom or claim:** "ALS is broken" — when actually the environment is. Four recurring sub-battles, each mistaken for a product bug at least once:

| # | Sub-battle | 1-line detect | 1-line fix | Verification |
|---|-----------|----------------|------------|--------------|
| 1 | **Port 5656 collision** — second server start fails: "Port 5656 is in use by another program … Address already in use" | `curl -s --noproxy '*' http://localhost:5656/` answers → something already listening | Stop the other server, or run on another port (`APILOGICPROJECT_PORT` / `--port` → **apilogicserver-cli-and-config**; stop/start → **apilogicserver-operate-and-deploy**) | verified 2026-08-23 (live collision transcript), Genai-Logic 17.03.19 |
| 2 | **venv-not-active installs** — `pip install` landed in system Python; `command not found: als` or `No module named ...` | `which als` does not print a path under your venv's `bin/` | Activate the venv, reinstall; full repair → **apilogicserver-build-and-env** §3–§5 | verified 2026-08-23 (install performed in venv; entry points enumerated) |
| 3 | **Multi-Python PATH confusion** — old version runs despite new install; or docs-era commands fail | `als welcome` → expect `Welcome to Genai-Logic 17.03.19`. Note: `ApiLogicServer version` is NOT a command in 17.03.19; the help-text synonyms `gail`/`gal` (and `gl`) ARE installed, working entry points — a working `gail` is a healthy install, not PATH damage | Fix interpreter/PATH per **apilogicserver-build-and-env** §1, §4 (`python venv_setup/py.py sys-info` per docs) | verified 2026-08-23; entry points corrected and re-verified 2026-08-26 (all six execute) |
| 4 | **DB driver builds** — pyodbc: `fatal error: 'sql.h' file not found`; psycopg2/pg_config errors; Oracle needs thick-client mode; macOS `error: Unsupported architecture` (fix: `export ARCHFLAGS="-arch x86_64"`); SSL `CERTIFICATE_VERIFY_FAILED` | The compiler/SSL error text itself | OS-specific headers/clients per **apilogicserver-build-and-env** §6 | per docs (Troubleshooting), not live-verified |

**Investigation:** Each sub-battle was chased at least once as a suspected engine bug; each closed as environment. The docs' Troubleshooting page catalogs the long tail: Docker port reassignment to 5657, `Dynamic model import failed` on odd schemas, PyCharm venv quirks, browser cache hiding admin-app changes, Azure SQL auth-type mismatches.

**Root cause / resolution:** Python-ecosystem environment variance, not ALS logic. Standing order: before filing any bug, run the 60-second environment self-test in **apilogicserver-build-and-env** §4 and the port probe above.

**Evidence:** items 1–3 verified 2026-08-23, Genai-Logic 17.03.19 (live install and collision transcript); item 3's entry-point fact corrected 2026-08-26 — all six synonyms (`ApiLogicServer`, `als`, `genai-logic`, `gail`, `gal`, `gl`) are declared in `entry_points.txt` and execute; https://apilogicserver.github.io/Docs/Troubleshooting/ (item 4 and long tail, per docs).

**Status:** **MONITOR.** Settled individually, but the cluster regenerates with every new machine, container, and Python minor version.

## A8 — `short_format_exception` logging bug (OPEN)

**ID:** A8 · **Title:** `short_format_exception` splitlines TypeError during constraint-violation logging · **Date/era:** present in Genai-Logic 17.03.19; verified 2026-08-23, re-confirmed on disk 2026-08-24.

**Symptom or claim:** When a constraint violation (or other handled exception) is logged, the console shows a logging-machinery stack trace ending in `TypeError: 'str' object cannot be interpreted as an integer`, instead of the prettified short stack trace. Readers routinely misread this as "the rules engine crashed".

**Investigation:** `config/server_setup.py`, function `patch_stacktrace_formatters` → inner `short_format_exception` (line 203 in both live-created projects), does:

```python
result = logging.Formatter.formatException(self, exc_info)
lines = result.splitlines('\n')          # line ~203 — the bug
```

- `str.splitlines` takes an optional boolean `keepends`, not a separator string; passing `'\n'` raises `TypeError: 'str' object cannot be interpreted as an integer`.
- Because this code monkey-patches every formatter's `formatException`, the TypeError fires *inside the logging machinery* whenever an exception with a traceback is logged — the constraint-violation path is the common trigger.
- Reproduced standalone in the project venv (Python 3.11.15): `python -c "'a\nb'.splitlines('\n')"` → the exact TypeError.

**Root cause / resolution:** Generated-code bug (wrong argument to `splitlines`), cosmetic scope. **Transaction integrity is unaffected**: the constraint still returns HTTP 400 with the JSON:API error body (`code: "2001"`, the interpolated `error_msg`) and the rollback is correct — verified live. Only the pretty logic log for the failed transaction is replaced by the logging stack trace. Local mitigation, if the noise blocks debugging: change line ~203 to `lines = result.splitlines()` — this edits a generated `config/` file, so route it through **apilogicserver-change-control** gates and record it as a divergence-from-generated; expect a future `als` release to fix or rewrite the file. Not observed fixed in any release as of 2026-08-24; treat any upstream-fix claim as unverified until the grep below comes back empty.

**Evidence:** verified 2026-08-23/24, Genai-Logic 17.03.19: `config/server_setup.py:203` reads `lines = result.splitlines('\n')` in both live-created projects (basic_demo and nw_sample); TypeError reproduced in the project venv; 400-with-rollback behavior verified live.

**Status:** **OPEN.** Re-verify before building on it (or on its absence):

```bash
grep -n "splitlines('" config/server_setup.py
# expect:  203:        lines = result.splitlines('\n')   → bug still present
# empty output → bug fixed in your version; update this entry to SETTLED with the version number
python -c "'a\nb'.splitlines('\n')"
# expect: TypeError: 'str' object cannot be interpreted as an integer
```

Triage rule for everyone downstream: a TypeError stack trace mentioning `formatException` / `short_format_exception` after a constraint fires is THIS bug — check the HTTP response and the data before concluding anything about the engine (**apilogicserver-debugging-playbook**).

## A9 — The legacy exhibit: `turbo3.5_excel_vba`

**ID:** A9 · **Title:** The legacy exhibit — this repo's Excel/VBA API caller · **Date/era:** the legacy system landed in 2 commits with no CI/tests/docs (re-verified 2026-08-26: `git log --oneline -- turbo3.5_excel_vba api_Key.xlsm | wc -l` → 2; the repo's TOTAL commit count has since grown as this skill library landed); analyzed line-by-line 2026-08-24.

**Symptom or claim:** "It works — why replace 42 lines of VBA?" The file `turbo3.5_excel_vba` (repo root, beside `api_Key.xlsm`) is a VBA `Function OpenAI(prompt As String) As String` calling the OpenAI chat-completions API from Excel. It is this project's canonical specimen of ungoverned application-embedded glue.

**Investigation (line-by-line; line numbers from the file as committed):**

1. **Line 6 — hardcoded secret slot:** `apiKey = "YOUR OPENAI API KEY"` — the credential lives in source (and, in practice, in the sibling workbook `api_Key.xlsm`, a binary blob no diff can review). No secret management, no rotation; the key ships with every copied workbook.
2. **Lines 10–12 — string-concatenated JSON:** the request body is built by pasting `prompt` raw into a JSON string (`"""messages"":[{""role"":""user"",""content"":""" & prompt & """}]"`). Any double quote, backslash, or newline in the prompt yields invalid JSON — the request fails, or worse, silently changes meaning (a crafted cell value can inject JSON keys). No JSON library, no escaping, no contract.
3. **Lines 24–25 — 16-bit indexes:** `Dim ContentStart As Integer` / `Dim ContentEnd As Integer`. VBA `Integer` is 16-bit (max 32,767); any response beyond ~32 KB overflows on assignment from `InStr` → run-time error 6.
4. **Lines 28–37 — InStr response "parsing"** — quoted verbatim:

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

   Verified failure modes of this loop:
   - (a) **Escaped-quote logic is wrong for `\\"`** — content ending in a literal backslash (JSON `"…\\"`) puts a `\` immediately before the true closing quote, so the loop treats the real terminator as escaped and overruns into the surrounding JSON.
   - (b) **Format drift** — the search key is the literal `"content": "` *with a space*; a compact-serialized response (`"content":"`) makes `InStr` return 0, so extraction starts at a fixed offset near the head of the response and returns garbage, silently.
   - (c) **No-match / error responses** — an HTTP 401/429 error body has no `"content": "` either → same silent-garbage path; and if no unescaped quote is ever found, `InStr` returns 0 and `Mid(json, -1, 1)` raises run-time error 5.
   - (d) Even on success, JSON escapes (`\n`, `\"`, `\\`, `\uXXXX`) are returned **un-decoded**.
5. **Whole file — no error handling, no evidence:** no `On Error`; `response.Status` never read (an error body is parsed as if success); no timeout configuration; no retry/backoff for rate limits; no logging or audit trail of what was sent or received. The call is synchronous (`response.Open "POST", url, False`), freezing Excel for the duration. Model (`gpt-3.5-turbo`) and temperature are hardcoded in the client.
6. **Governance:** the business behavior (what gets asked, what comes back, what decisions it feeds) lives client-side in per-user workbook copies — unversioned, untested, unreviewed, invisible to IT.

**Root cause / resolution:** Not "bad VBA" — the pattern itself: **application-embedded glue with no contract** (hand-built wire format in both directions), **no gating** (no review, tests, or CI — the legacy files landed in 2 commits), **no evidence** (no logs, no audit). Every failure mode above is a special case of those three absences. Resolution path: replace, don't patch — server-side and governed, per **apilogicserver-modernization-campaign** (the gated legacy-to-ALS campaign); the server-side request pattern that supersedes client-embedded calls is owned by **apilogicserver-integration-patterns**.

**Evidence:** the file itself at repo root (`turbo3.5_excel_vba`, read in full 2026-08-24); legacy history (2 commits touching `turbo3.5_excel_vba`/`api_Key.xlsm`, no CI/tests/docs) re-verified 2026-08-26 via `git log --oneline -- turbo3.5_excel_vba api_Key.xlsm`.

**Status:** **SETTLED-BY-REPLACEMENT-PLAN.** Do not invest in hardening this file; it exists as the before-picture and the campaign's acceptance foil.

## A10 — GenAI overreach guard

**ID:** A10 · **Title:** GenAI overreach — accepting LLM output without deterministic verification · **Date/era:** current; the docs record the failure class from recent AI-driven projects.

**Symptom or claim:** "The model generated the schema and the logic and it looks right — merge it." The temptation scales with how good the generation looks.

**Investigation:**

- The docs record what happens when AI output is accepted as code: "AI, on its own, translates requirements to native code. Lots of it: 5 rules become 200 lines"; "The intent is obscured. You can't govern what you can't read"; and the resulting bugs were "hard to spot, but fatal to data integrity" (per docs, Tech-Realizations — the same mechanism as A5, now automated).
- The docs' counter-design is to point AI at *rules*, not code: "Rules are the governance enterprises require: logic they can read, trust and maintain"; reliability comes from Context Engineering (problem-independent knowledge packaged for the model) rather than prompt craft; the genai flow generates declarative rules that the engine then executes deterministically.
- Local ground truth for the verification half: rules load and are dependency-analyzed at startup (a bad rule fails fast); the Behave suite plus Behave Logic Report provide per-scenario logic-log evidence (7 features / 26 scenarios / 83 steps passing — verified 2026-08-23, Genai-Logic 17.03.19).
- GenAI-with-live-LLM commands themselves (`genai-create`, `genai-iterate`) were **not exercised in this workspace** (require `APILOGICSERVER_CHATGPT_APIKEY`) — per docs, not live-verified.

**Root cause / resolution:** LLM output is a *proposal*, not a change. The guardrail chain: AI proposes → output must be declarative and human-readable (rules, models — never opaque handler code) → deterministic verification gates it (startup rule activation, Behave scenarios with predicted numbers, Logic Report evidence per **apilogicserver-validation-and-qa**) → merge passes **apilogicserver-change-control** gates. Operating guardrails for the genai command family: **apilogicserver-genai-development**.

**Evidence:** https://apilogicserver.github.io/Docs/Tech-Realizations/, https://apilogicserver.github.io/Docs/FAQ-Overview/ (per docs); verification machinery verified 2026-08-23, Genai-Logic 17.03.19.

**Status:** **MONITOR.** Standing rule: no AI-generated schema or logic is merged without the deterministic-verification chain above; any exception is itself an incident for this ledger.

---

## How to add an entry

1. **Check for a duplicate.** Grep this file for the symptom's key error text or topic. If an entry exists, update it (append to Investigation with a date) instead of adding a new one.
2. **Reproduce or capture.** Get the symptom into a copy-pasteable form: exact command, exact output. If you cannot reproduce, the entry still qualifies — but the Evidence field must say what was captured and what wasn't.
3. **Write the entry in the strict format** — ID (next free `A<n>`), Title, Date/era, Symptom or claim, Investigation, Root cause / resolution, Evidence, Status. Label every fact: `verified <date>, Genai-Logic <version>` for things you executed; `per docs, not live-verified` for things you read. Never blend the two in one unlabeled sentence.
4. **Assign status honestly.** `SETTLED` requires evidence a stranger can check (a doc URL, a command with expected output, a file at a path). `OPEN` requires a 1-line re-verification command inside the entry itself. `MONITOR` requires naming what compliance looks like and who/what checks it.
5. **Cross-reference, don't duplicate.** Mechanisms, runbooks, and fixes live in the sibling skills; this ledger holds the verdict and the pointer. Any resolution that changes project behavior ends at **apilogicserver-change-control** gates.
6. **The OPEN rule (non-negotiable):** before building anything on an `OPEN` entry — including assuming the bug is still there — run its re-verification command and re-stamp the entry with the date and version. An OPEN entry with a stale stamp is a rumor, not a fact.

---

## Provenance and maintenance

Volatile facts and their 1-line re-verification commands (run from any ALS project root, venv active):

- **A8 bug presence** (v17.03.19): `grep -n "splitlines('" config/server_setup.py` — expect line ~203 `result.splitlines('\n')`; empty = fixed, update A8.
- **A8 TypeError semantics** (Python-level, version-independent): `python -c "'a\nb'.splitlines('\n')"` — expect `TypeError: 'str' object cannot be interpreted as an integer`.
- **Installed version / entry points** (A7 item 3): `als welcome` — expect `Welcome to Genai-Logic 17.03.19` (or newer; re-stamp entries on bump). `ApiLogicServer version` erroring is expected in 17.03.19; `gail`/`gal`/`gl` succeeding is expected too (six synonym entry points, re-verified 2026-08-26).
- **A5 comment still shipped**: `grep -n "declarative-vs-procedural-comparison" logic/declare_logic.py` — expect the GitHub link line in any freshly created basic_demo-style project.
- **A6 file classes**: after any rebuild, `ls ui/admin/` — `admin-created.yaml` / `admin-merge.yaml` present means the merge dance is pending (runbook: apilogicserver-change-control).
- **A7 port collision**: with one server running, `curl -s --noproxy '*' -o /dev/null -w "%{http_code}\n" http://localhost:5656/` — non-`000` means the port is taken; a second `python api_logic_server_run.py` will report "Port 5656 is in use by another program".
- **A9 exhibit unchanged**: `wc -l turbo3.5_excel_vba` at this repo's root (42 content lines as analyzed) and re-read lines 28–37 for the quoted loop; legacy history: `git log --oneline -- turbo3.5_excel_vba api_Key.xlsm | wc -l` → 2 (the repo's TOTAL commit count grows with this skill library — do not use it as the legacy measure).
- **Docs-derived entries (A1–A5, A10 claims, A7 item 4)**: re-fetch the URLs below on any docs revision; the numbers (6500 sites, 700 sites, $3B IPO, ~97%, "minutes → 2 seconds", "~40X") are the docs' claims, not measurements reproduced here.

Grounded in: https://apilogicserver.github.io/Docs/FAQ-RETE/, https://apilogicserver.github.io/Docs/FAQ-Versata/, https://apilogicserver.github.io/Docs/FAQ-Live-API-Creator/, https://apilogicserver.github.io/Docs/Tech-Proven/, https://apilogicserver.github.io/Docs/FAQ-Overview/, https://apilogicserver.github.io/Docs/Troubleshooting/, https://apilogicserver.github.io/Docs/Tech-Realizations/ and a live Genai-Logic 17.03.19 install (2026-08-23). Live checks ran against real created projects (basic_demo, nw_sample) and a running server, verified against a live install; the legacy exhibit `turbo3.5_excel_vba` was read in full from this repository.
