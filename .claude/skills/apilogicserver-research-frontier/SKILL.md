---
name: apilogicserver-research-frontier
description: Open research problems and honest positioning for API Logic Server / Genai-Logic - what is PROVEN here (live-verified chaining/pruning, 400/2001 constraint evidence, all-green Behave 7/26/83, security row-filter matrix, MCP discovery), proven only per lineage docs (Versata 700+ sites / ~97% automated, Live API Creator, minutes-to-2s), CLAIMED not independently measured (40X conciseness, coverage percentages), or open/preview (MCP client executor Tech Preview, probabilistic logic). Use when writing papers, posts, talks, README or marketing claims about ALS; when asked "is this proven", "can we claim X", "what's novel", "what should we research next", "is probabilistic logic real", "is 40X legit"; when judging novelty vs SOTA; or picking a frontier problem (governed AI writes, NL-to-rules synthesis, non-decomposable aggregates, spreadsheet-to-rules extraction). Not for running experiments (apilogicserver-research-methodology) or history (apilogicserver-failure-archaeology).
---

# API Logic Server: Research Frontier and Positioning

## Purpose

This skill is the boundary between what this project can honestly claim and what it must still prove, plus the short list of open problems where this ecosystem is positioned to advance the state of the art (SOTA — the best published/verified capability anywhere, not just here). Every public statement about ALS must stand on a named row of the Positioning Ledger below; every research idea must end in a falsifiable "you have a result when..." statement. Wrong claims cost more than missing claims.

## Use this skill when

- Writing anything public-facing: paper, talk, blog, README, comparison table, grant text, marketing copy.
- Someone asks "is X proven?", "can we say 40X?", "has anyone measured this?", "what is actually novel here?"
- Choosing or scoping a research problem in the ALS ecosystem, or judging a proposed one for grounding.
- Deciding whether a docs claim (Versata numbers, minutes-to-2-seconds, coverage percentages) may be repeated, and with what label.
- Evaluating "probabilistic logic", "MCP client executor", or other preview-status material for production or publication.

## Do NOT use this skill when

- You need the evidence bar, predict-numbers-first discipline, or the idea lifecycle to actually RUN an experiment — that is **apilogicserver-research-methodology** (the execution counterpart to this skill's map).
- You want product history, dead ends, or "has this been tried" — **apilogicserver-failure-archaeology**.
- You want engine theory (adjustment, pruning, phases) — **declarative-rules-reference**; rule authoring — **apilogicserver-logic-patterns**.
- You want to test or prove a specific rule works — **apilogicserver-validation-and-qa**.
- You are migrating a legacy spreadsheet end-to-end — **apilogicserver-modernization-campaign**.
- Any procedure here that changes project files ends at the gates in **apilogicserver-change-control**; this skill never overrides them.

---

## 1. POSITIONING LEDGER — the no-oversell contract

**The rule: any public claim about ALS must cite which ledger row it stands on, using that row's citation form. A claim with no row is not made.** The project's own comparison document models this discipline — its author demoted an earlier draft ("44X reduction", "fundamentally superior") to an exhibit file and wrote: the substance stays, the exclamation marks go. Hold that line.

**Reproducibility standard for anything promoted upward:** versioned rules (`logic/declare_logic.py` + `logic/logic_discovery/` under source control at a stated Genai-Logic version) + a committed Behave suite exercising them + the generated `Behave Logic Report.md` artifacts (per-scenario logic logs). "Behave" is the Gherkin BDD test runner shipped in every project under `test/api_logic_server_behave/` (**apilogicserver-validation-and-qa**). Evidence that cannot be re-run is anecdote.

**Placing a new claim — decision list (first match wins):**

1. Executed in this environment with captured artifacts and a date? → Row 1.
2. About Versata / Live API Creator or any product that no longer exists? → Row 2 (it can never leave).
3. A number or superlative about today's product, asserted by docs/marketing but without Row-1-grade artifacts? → Row 3.
4. Docs label it preview/exploratory, or it exists only as pattern documentation? → Row 4.
5. None of the above → it is not a claim; it is a hypothesis. Take it to section 2 and **apilogicserver-research-methodology**.

### Row 1 — PROVEN-HERE

**Membership criteria:** verified by execution against a live Genai-Logic 17.03.19 install on 2026-08-23 (some items re-probed 2026-08-25), on real created projects (`basic_demo`, `nw_sample`), with captured outputs. Citation form: "verified <date>, Genai-Logic 17.03.19" plus the reproduction command.

| Claim | Evidence (all verified 2026-08-23, Genai-Logic 17.03.19) | Reproduce with |
|---|---|---|
| Multi-rule chaining fires on every API write; violating writes are refused | PATCH Item quantity 1→100 on an unshipped order → formula → sum → sum → constraint → HTTP 400, body `{"errors":[{"title":"Customer balance (9000...) exceeds credit limit (5000...)", "code":"2001"}]}` | The check-credit probe in **apilogicserver-debugging-playbook** |
| Pruning is real (where-clause stops the chain) | Same PATCH on a SHIPPED order succeeds — `where=date_shipped is None` yields delta 0, customer constraint never runs | Same probe, shipped-order control; theory in **declarative-rules-reference** §4 |
| Adjustment, not re-aggregation | Engine internals read from install: `_adjust_parent_aggregates()` delta path, no `SELECT SUM` during transactions | `grep -n adjust_from_updated_child` in installed `logic_bank/rule_type/aggregate.py` |
| Whole-project regression suite green | Behave: **7 features, 26 scenarios, 83 steps passed, 0 failed, ~1.4 s** on `nw_sample` | `cd test/api_logic_server_behave && python behave_run.py --outfile=logs/behave.log` (server running) |
| Declarative row security filters per role | Row-filter matrix: Customer admin=95 vs s1=**1**; Category 8/3/1/3 across roles; Product 77/69/69/77 (Category admin=8 re-probed 2026-08-25) | Matrix and curl probes in **apilogicserver-security-model** §6.3 |
| MCP discovery surface is live | `GET /.well-known/mcp.json` returns `base_url`, `description`, learning text, resources — served from `docs/mcp_learning/mcp_schema.json` + `mcp.prompt`; responds without a JWT even with security on (re-probed 2026-08-25) | `curl -s http://localhost:5656/.well-known/mcp.json`; details in **apilogicserver-integration-patterns** §3 |
| Rule declarations are checked at startup (registration as compile gate) | Startup logs a per-attribute dependency listing of discovered logic (verified). That a nonexistent rule API aborts start rather than failing silently is Python import semantics plus the docs' own demonstration (FAQ-AI: hallucinated rule code "does not even compile, much less run") — re-verify per Provenance before leaning on it in print | `python api_logic_server_run.py` and read the "discovered logic" listing |

MCP = Model Context Protocol, the discovery-plus-tools convention AI assistants use to call external systems.

**Row 1 includes verified defects — an honest ledger cuts both ways.** Also proven here (2026-08-23, 17.03.19): `config/server_setup.py`'s `short_format_exception` calls `result.splitlines('\n')` with an invalid argument, so logging a constraint violation prints a `TypeError: 'str' object cannot be interpreted as an integer` stack trace instead of the pretty logic log. Transaction integrity is unaffected (the 400 and rollback are correct) — but any publication showing constraint-violation console output must disclose this, or readers will read a healthy engine as broken. Details and status: **apilogicserver-failure-archaeology**; triage: **apilogicserver-debugging-playbook**.

### Row 2 — PROVEN-PER-LINEAGE

**Membership criteria:** commercial history of the same architecture reported in the project docs, not reproduced here and not reproducible here (the products are gone). Citation form: "per docs, not live-verified" — always attribute to the docs, never restate as a present-tense ALS measurement. Full entries: **apilogicserver-failure-archaeology** A2/A3/A4.

| Docs' claim | Docs' numbers (per docs, not live-verified) | Use it as |
|---|---|---|
| Versata: declarative transaction rules at enterprise scale | "over 700 sites"; author-measured "94-99% of logic automated by rules, typically ~97%" across dozens of production systems | Existence proof that the paradigm carried production load; NOT a measurement of today's engine |
| CA Live API Creator: second commercial proof | Same architecture, SaaS API delivery; proprietary + acquired = end-of-life | The distribution lesson (why ALS is open source, plain files) |
| Adjustment beats re-aggregation in production | Docs' cited case: "several minutes to 2 seconds", "no coding changes required" | Motivation for the adjustment architecture; the mechanism (not the number) is Row 1 |

### Row 3 — CLAIMED-NOT-INDEPENDENTLY-MEASURED

**Membership criteria:** quantitative claims the docs make about the current product that no independent measurement backs. Repeating them without the label below is oversell. Citation form: "the docs' claim, from a single A/B example / lineage-era measurement; not independently measured."

| Claim | Where it lives | What exists behind it | What an independent measurement would require |
|---|---|---|---|
| "40X more concise than code" / "40x less code to write, maintain, and debug" | docs FAQ-AI; `logic/readme_logic.md` in every created basic_demo | ONE A/B artifact: the same 7 requirements as ~220 lines of AI-written procedural code (2 real bugs, both missed-reparenting) vs 5 rules (0 bugs found). The artifact itself says: "It's one example, not a benchmark" and "This is a fact about practice, not a theorem" | A use-case corpus (dozens of specs, not one), procedural baselines per spec written blind (authors unaware of the comparison), blind declarative implementations, published line counts AND defect counts per the reproducibility standard above |
| Logic-coverage percentages (the lineage's "94-99%, typically ~97%") repeated as if they described today's engine | Lineage measurement (Row 2) echoed forward in positioning material | The Versata-era author measurement only — no modern-corpus equivalent exists | Same corpus approach: per-spec fraction of requirements expressible as the shipped rule types vs requiring Python events, measured on modern projects |
| Customs-system case: requirements assembled in 2 days vs "roughly two engineer-years"; compiled in 10 minutes; 130+ columns / 7 tables | docs Tech-Gov-By-Arch | Narrative case study, no published artifacts | Timed, logged replication with published rules + suite + report |
| "The governed version caught an 8-figure compliance exposure" | docs Tech-Ent-AI | Narrative | Named or anonymized case with auditable artifacts |

**Where the comparison artifact lives (verified on disk 2026-08-23):** every created `basic_demo` contains `logic/procedural/declarative-vs-procedural-comparison.md` (v1.0, 2026-07-22) plus the buggy `procedural_logic.py` lineage and the demoted overclaim draft `z-exhuberant_declarative-vs-procedural-comparison.md`. The GitHub copy is linked from `logic/declare_logic.py` (the `ApiLogicServer-src` prototypes path). Its companion (`basic_demo_logic_gov`) adds a committed Behave suite — which, per its own note, does NOT yet cover the reparenting scenarios that contained the two bugs. Quote those caveats whenever you quote the 40X.

Context worth keeping straight: the docs' "95% of enterprise AI pilots deliver no measurable financial impact" (Tech-Ent-AI) is the docs citing MIT's NANDA report about the industry — a problem statement, not an ALS capability claim. Do not conflate it with coverage percentages.

**Reuse the artifact's method, not just its number.** Both bugs surfaced only when the authors asked the implementation two pointed questions — "what would happen if an order's customer changed?" and "what if an item's product changed?" The reparenting probe is the highest-yield discriminating question against any hand-written multi-table logic, because it demands BOTH the old and the new parent be adjusted. Bake it into every F1 adversarial generator and every F2 corpus spec; a comparison study that skips it will overrate procedural baselines exactly the way the first drafts did.

### Row 4 — OPEN / PREVIEW

**Membership criteria:** the docs themselves label it preview/exploratory, or it exists only as pattern documentation with no shipped, benchmarked mechanism. Citation form: "open/candidate, per docs" — never present as production capability.

| Item | Docs' own status (per docs, not live-verified except as noted) |
|---|---|
| MCP **client** executor (`integration/mcp/mcp_client_executor.py`) | Verbatim: "MCP support is GA for the MCP Server Executor. The MCP Client Executor is in Tech Preview." (GA = general availability.) Code verified on disk; the LLM planning leg not exercised here (**apilogicserver-integration-patterns**) |
| Probabilistic logic (AI-chosen values inside rule flow) | Pattern documentation only — see F3 below for what it actually is. No shipped `Rule.*` type, no benchmark. The security-facing variant ("AI Rules", audit-trailed, opt-in) is likewise documented pattern, not measured capability |
| "Enterprise vibe" positioning | The docs page is an outline/stub (verified by fetch 2026-08-25) — there is no argument to cite yet |
| GenAI project/logic generation quality rates | Commands exist (Row 1: CLI verified); output quality is unmeasured — guardrails in **apilogicserver-genai-development**, honesty precedent: docs FAQ-AI shows an out-of-context generation and calls it what it is: "It is, as they say, an hallucination." |

### 1.5 Claim audit protocol — run this before anything ships publicly

Numbered checklist for any paper, post, README, slide, or comparison table:

1. List every quantitative or superlative claim in the text (numbers, "X times", "proven", "guaranteed", "cannot", percentages).
2. Assign each claim a ledger row. No row → delete the claim or run the experiment that earns it a row (**apilogicserver-research-methodology**).
3. Check the citation form matches the row: Row 1 gets "verified <date>, Genai-Logic <version>" + reproduction command; Rows 2-3 get "per docs" / "the docs' claim" attribution; Row 4 gets "open/preview".
4. For every Row 3 number, verify the text also carries the artifact's own caveat (for the 40X: "one example, not a benchmark"). Quoting the number without the caveat fails the audit.
5. Check tense and scope: lineage facts stay past-tense and attributed ("Versata sites ran..."), never present-tense about today's engine ("ALS automates 97%..." is a violation).
6. Check that no Row 4 item is described with production verbs ("supports", "provides") — use "documents a pattern for", "previews".
7. Confirm every "guaranteed on every write" statement carries its known boundary: guarantees hold for writes through the SQLAlchemy session/API; raw SQL bypasses rules (invariant list: **apilogicserver-architecture-contract**).
8. If the text proposes measuring something, confirm the measurement design is pre-registered per **apilogicserver-research-methodology** before the text promises results.

**Phrasing table — the same fact, said honestly vs oversold:**

| Fact | Allowed phrasing | Forbidden phrasing |
|---|---|---|
| 5 rules vs ~220 lines A/B | "In the project's published A/B example, the same 7 requirements took 5 rules vs ~220 procedural lines with 2 real bugs — one example, not a benchmark" | "Rules are 40X better", "44X reduction", any unqualified multiplier |
| Constraint enforcement | "Every write through the API/session runs the rules; a violating PATCH was refused 400/code-2001 (verified 2026-08-23, 17.03.19)" | "No bad data can ever enter the database" (raw SQL bypass exists) |
| Versata history | "The docs report the predecessor ran 700+ sites with ~97% of logic automated (per docs, not live-verified)" | "ALS is proven at 700+ enterprise sites" |
| MCP | "MCP Server Executor is GA; the Client Executor is Tech Preview (docs' labels)" | "Full agentic AI support" |
| Probabilistic logic | "The docs document a request-table pattern for AI-chosen values inside rule flow; no shipped mechanism or benchmark yet" | "ALS supports probabilistic logic" |
| Suite evidence | "The shipped suite passed 7 features / 26 scenarios / 83 steps in ~1.4 s (verified 2026-08-23)" | "Fully tested", "proven correct" (tests find gaps, not proofs — the docs say so themselves) |

**Row movement protocol.** Claims move UP only by execution: Row 4 → Row 1 when a mechanism ships and a pre-registered experiment passes with published artifacts; Row 3 → Row 1 when the independent-measurement requirements in its table cell are met; Row 2 never moves (its products are gone — it is history, permanently). Claims move DOWN immediately on a failed re-verification: date-stamp the failure, keep the old claim visible as history (the archaeology pattern), never silently edit. Every promotion or demotion is a behavior-relevant docs change — record it via the docs-of-record conventions in **apilogicserver-change-control**.

---

## 2. FRONTIER PROBLEMS

Six problems where this ecosystem holds a specific asset the SOTA lacks. Each ends falsifiable. Before starting any of them, load **apilogicserver-research-methodology** — a hunch becomes a result only through its lifecycle (predict numbers first, then run). All file paths are project-relative from a project root.

### 2.0 Compare against SOTA without strawmanning

The comparison artifact sets the standard here too. It states of its own headline result: "procedural code *can* handle these paths correctly; LogicBank's own engine is procedural code that does" — the claim is about reliability-per-implementation, not impossibility. Apply the same rigor outward:

| When positioning against | Do not say | Say instead (and cite) | Neighbor's real strength to acknowledge |
|---|---|---|---|
| Rete/BRMS engines (BRMS = business rules management system; Drools etc.) | "Rete is wrong" | "Rete targets stateless decisions; transaction logic needs old/new deltas and aggregate maintenance Rete engines re-query for" (**apilogicserver-failure-archaeology** A1/FAQ-RETE) | Superb at high-volume stateless rule matching |
| Incremental view maintenance (databases) | "Nobody does incremental aggregates" | "IVM solves this at the query layer; no transaction-time RULES engine ships it declaratively with constraints attached" (F4) | Decades of theory ALS's F4 should reuse, not reinvent |
| Agent guardrail frameworks | "Guardrails don't work" | "Output-side guardrails are probabilistic; commit-point rules are deterministic — different layer, composable" (F1) | Catch failure modes (tone, PII in text) rules never see |
| LLM codegen | "AI can't write logic" | "Unguided AI defaults to procedural code and missed 2 reparenting cases in the A/B; pointed at the rule IR it produced 0 found bugs" (Row 3 artifact) | Speed — the artifact itself calls it "real and worth keeping" |

### F1 — Deterministic governance for LLM-generated transactions

**Why current SOTA fails.** Agentic systems write to databases through APIs that carry no transaction logic; per docs Tech-Gov-By-Arch, "Agents now generate code, propose transactions, and write to systems of record at speeds no review cycle can match." Guardrail research targets prompts and outputs, not the commit point. No mainstream agent stack can show a per-transaction proof that integrity held.

**This project's specific asset.** Every write path already runs the rules: the 400/2001 refusal and the all-green suite are Row 1 facts, and the docs' architecture statement — "All Sources — APIs, agents, workflows, anything that writes to the database — funnel through one point" — is implemented, not aspirational. Plus a machine-readable surface for the attacker to discover: `/.well-known/mcp.json` (Row 1). The missing piece is the adversarial measurement.

**First three steps.**
1. Stand up the target: `als create --project-name=gov_bench --db-url=nw+` (security and logic included); verify baseline green: `cd test/api_logic_server_behave && python behave_run.py --outfile=logs/behave.log` expecting 0 failed (**apilogicserver-validation-and-qa**).
2. Enumerate the write surface mechanically — `curl -s http://localhost:5656/.well-known/mcp.json` plus the Swagger at `/api` — and build a generator in `test/adversarial/gen_txns.py` that logs in:

   ```bash
   curl -s -X POST http://localhost:5656/api/auth/login -H "Content-Type: application/json" -d '{"username":"admin","password":"p"}'
   ```

   then emits N JSON:API POST/PATCH/DELETE bodies covering: constraint-violating values, reparenting (FK changes), qualified-aggregate boundary flips (ship/unship), and security probes under non-admin tokens (payload grammar: **apilogicserver-api-contract**).
3. Execute with evidence capture: every response must be either 2xx with derivations still consistent (assert predicted sums after, the Row 1 chain arithmetic) or a typed 400/2001 (or 401/404-by-filter for security probes); capture per-transaction logic logs (`test/api_logic_server_behave/logs/scenario_logic_logs/` conventions). Any project changes needed along the way pass **apilogicserver-change-control** gates.

**You have a result when** an adversarial suite of N generated transactions — N declared before running, at least 1,000 — produces zero integrity violations: no accepted write leaves any derived value inconsistent with its rule, no violating write escapes refusal, and the suite plus logic logs are published per the reproducibility standard. One uncaught inconsistency falsifies the claim at that N.

*Ledger row today:* the enforcement mechanism is Row 1; "agents cannot corrupt a governed ALS system" is claimable only after this result — until then it is Row 3 phrasing and fails the claim audit.

### F2 — Natural-language-to-rules as verifiable program synthesis

**Why current SOTA fails.** LLM codegen emits open-ended imperative code that reviewers cannot exhaustively check; the Row 3 A/B artifact shows the concrete failure (2 missed-reparenting bugs in ~220 lines, invisible until probed), and docs Logic-Why-Declarative-GenAI states the verification gap plainly: "Tests find gaps but cannot prove coverage across all relationship variants."

**This project's specific asset.** A rule vocabulary small enough that the canonical check-credit spec is 5 declarations acts as a tiny intermediate representation (IR — a constrained target language for synthesis) with three checkable stages the SOTA lacks: (a) startup registration as a type-check — a hallucinated rule signature aborts server start with a readable error (Row 1); (b) the engine supplies ordering/propagation so synthesis only has to get the DECLARATION right; (c) predicted-number Behave tests give a binary pass per spec. The CLI hook exists and is verified: `als genai-logic --using <file-or-dir>`, with `--suggest`, `--logic TEXT`, `--retries` (flags verified from `--help`, 2026-08-25, 17.03.19; key setup and guardrails: **apilogicserver-genai-development**).

**First three steps.**
1. Build a held-out corpus: 20+ NL specs as `docs/logic/*.prompt` files, drawn from domains NOT in the shipped examples; seed the format (not the content) from the comparison doc's 7 requirements and the docs' Eval materials. Pre-register each spec's predicted numbers (a named transaction and the exact resulting values/refusal) per **apilogicserver-research-methodology**.
2. For each spec, run synthesis into a scratch project (`als genai-logic --using docs/logic/spec_k.prompt`), then apply the compile gate: `python api_logic_server_run.py` must reach the startup dependency listing with the new rules discovered — count startup failures as synthesis failures, not fixable noise.
3. Score with the predicted-number Behave scenario per spec; report pass rate with zero human repair (any hand edit moves that spec to the "repaired" bucket; the repaired diff is data). Project edits land under **apilogicserver-change-control** gates.

**You have a result when** a held-out corpus of stated size compiles to rules passing predicted-number tests at a stated rate with zero human repair, published with per-spec logic logs — and the rate is falsified or confirmed by anyone re-running the frozen corpus against a stated Genai-Logic version.

*Ledger row today:* the IR, compile gate, and test harness are Row 1; every synthesis-quality number is Row 4 until the corpus run exists (the CLI working is not the same as the CLI working WELL).

### F3 — Probabilistic logic: stochastic choice inside deterministic guarantees (OPEN)

**What the docs actually propose (per docs, not live-verified).** The Eval-probabilistic_logic pages document a PATTERN, not a new rule type: an early row event on the receiving entity calls a wrapper that inserts a request-table row (`SysXxxReq`, e.g. `SysSupplierReq` with `request`, `reason`, `created_on`, `fallback_used`, FK links, and chosen-value columns); an event on that request row calls an LLM to choose a value (e.g. best supplier price), writes the choice plus reasoning into the audit row; the receiver copies the chosen value; normal formulas/sums/constraints then run on it. Mandated fallback: "Reasonable Default → Fail-Fast" — deterministic default first, else raise with a `TODO_AI_FALLBACK` marker, never fail silently. Test inputs come from `config/ai_test_context.yaml` (e.g. `world_conditions: 'ship aground in Suez Canal'`). The pages carry production-debugging notes dated Nov 16-21 2025 (import order, delete-event guards, audit placement) — so the pattern has been exercised by its authors — but there is no shipped mechanism, no benchmark, and no measured result. Ledger Row 4.

Pattern skeleton as the docs present it (condensed; per docs, not live-verified — signatures use only shipped rule types):

```python
# logic/logic_discovery/<use_case>.py  — receiver side
Rule.early_row_event(on_class=models.Item, calling=set_item_unit_price_from_supplier)
    # wrapper: logic_row.new_logic_row(models.SysSupplierReq) → .link(to_parent=...) →
    #          .insert(reason="AI supplier selection request") → copy chosen value back

# logic/logic_discovery/ai_requests/<handler>.py  — request-table side
Rule.early_row_event(on_class=models.SysSupplierReq, calling=supplier_id_from_ai)
    # guard: if logic_row.is_deleted(): return   (check BEFORE touching old_row)
    # no API key → deterministic fallback: min(suppliers, key=lambda s: s.unit_cost)
    # with key  → LLM choice; either way populate chosen_*, request, reason (audit)
```

The receiver's formulas/sums/constraints then treat `chosen_unit_price` like any other input — which is exactly the research object: the choice is probabilistic, the enforcement is not.

**Why current SOTA fails.** ML-driven decisions in production systems either bypass business constraints (model output written directly) or bolt validation on per call site — the same enumerate-every-path failure the procedural A/B exposed. Neurosymbolic work rarely runs inside a transaction with rollback.

**This project's specific asset.** The choice is stochastic but everything around it is Row 1 machinery: the chosen value flows through formulas/sums and can be REFUSED by a constraint with a transactional rollback and a logged old→new trail; the request pattern provides the audit row (**apilogicserver-integration-patterns**). Determinism wraps the dice.

**First three steps.**
1. Read both Eval pages end-to-end; then reproduce the `SysSupplierReq` pattern in a scratch basic_demo clone, adding the request table via the docs' Alembic flow (`cd database && alembic revision --autogenerate`, clean the migration, `alembic upgrade head`) — gated by **apilogicserver-change-control**.
2. Define the benchmark BEFORE wiring any LLM: a task set of K decisions under varying `world_conditions`, each with (a) a hard constraint the choice can violate and (b) a deterministic min-cost fallback as baseline; pre-register expected refusal counts.
3. Run three arms — fallback-only, LLM-choice, adversarially-prompted LLM-choice — capturing for every decision the audit row and the constraint outcome; add Behave scenarios asserting refusals.

**You have a result when** a published benchmark shows 100% of constraint-violating AI choices intercepted (any uncaught violation falsifies the "determinism wraps the dice" claim), a complete audit row for every decision, and decision quality reported honestly against the deterministic baseline — including the case where the baseline wins.

*Ledger row today:* Row 4 entirely. The constraint machinery it would lean on is Row 1, but no probabilistic result exists to cite.

### F4 — Incremental maintenance beyond sum/count (non-decomposable aggregates)

**Why current SOTA fails (and why the engine stops where it does).** Adjustment works because sum/count are decomposable: the parent delta is computable from one child's `old_row`/`row` alone (the delta algebra in **declarative-rules-reference** §4, verified from `logic_bank/rule_type/aggregate.py`). Median, percentiles, windowed aggregates, and min/max under delete/eviction are non-decomposable — removing the current max or shifting a median requires knowledge of OTHER children, which one-row adjustment by design never touches. Incremental view maintenance literature solves this with auxiliary structures; no transaction-time rules engine ships it declaratively.

**This project's specific asset.** The adjustment infrastructure is already the hard part: `_adjust_parent_aggregates()`, old_row semantics, pruning, the logic-log `[old-->] new` evidence format, and a Behave harness that already validates sum across insert/update/delete/reparent. A new aggregate type inherits all of that scaffolding and its proof obligations are enumerable.

**First three steps.**
1. Read the installed delta algebra: `grep -n "adjust_from_updated_child\|adjust_from_updated_reparented_child" venv/lib/python*/site-packages/logic_bank/rule_type/aggregate.py` (adjust the venv path to yours).
2. Prototype ONE type with an auxiliary structure — e.g. min/max maintained by a parent-stored candidate plus a bounded rescan only on eviction (delete/decrease of the current extremum), or bucketed counts for approximate percentile — as an event-based `RuleExtension`-style prototype in a scratch project's `logic/logic_discovery/` (authoring mechanics: **apilogicserver-logic-patterns**).
3. Write the consistency argument covering the SAME four paths sum handles — insert, update, delete, reparent (the two-parent case that produced the A/B bugs) — then encode each path as a predicted-number Behave scenario. Ship nothing without **apilogicserver-change-control** gates.

**You have a result when** a new aggregate type ships with a written consistency argument over all four paths, Behave evidence including the delete-the-extremum and reparent discriminating cases, and a measured statement of its extra cost versus sum's O(1) adjustment. A single path where the stored value diverges from the ground-truth query falsifies it.

*Ledger row today:* sum/count adjustment is Row 1; any statement that the engine "handles aggregates" beyond sum/count is unfounded — there is no row for it at all yet.

### F5 — Spreadsheet-to-rules migration tooling

**Why current SOTA fails.** Spreadsheet modernization is manual archaeology: formulas and VBA embed multi-table logic with no schema, no tests, no audit; extraction tools recover formulas but not GOVERNED semantics. This repository's own legacy exhibit (`turbo3.5_excel_vba` + `api_Key.xlsm` — an Excel/VBA caller with client-embedded AI, 2 commits, no tests) is the instance.

**This project's specific asset.** A manual gold standard already exists: **apilogicserver-modernization-campaign** P3 defines the translation table (cell formula → `Rule.formula`; SUMIF → `Rule.sum` with `where`; VLOOKUP → `Rule.copy`; validation → `Rule.constraint`) and a measurable acceptance gate (predicted 400/2001 + logic-log chain + shipped-order control). Automation has a target to hit, not a vibe to chase.

**First three steps.**
1. Execute the campaign P0-P3 manually on the exhibit per **apilogicserver-modernization-campaign**; freeze the resulting translation table + P3 gate outputs as the gold standard.
2. Build the extractor: read formulas with openpyxl and VBA with oletools' olevba, emit a candidate rule set in the 5-rule vocabulary plus an "untranslatable" remainder list (that remainder is the coverage datum Row 3 needs).
3. Diff candidate vs gold rule-for-rule; run the SAME P3 gate against the auto-generated project (any edits gated by **apilogicserver-change-control**).

**You have a result when** automated extraction reproduces the manual P3 translation table on this exhibit rule-for-rule AND its generated project passes the identical P3 gate — before any claim about workbooks in general. Generalization then needs a workbook corpus (which feeds the Row 3 coverage measurement).

*Ledger row today:* the manual translation table and gate are the campaign's verified method; "automated spreadsheet migration" has no row and may not be claimed.

### F6 — Requirement-to-execution traceability as an audit artifact

**Why current SOTA fails.** Compliance auditing of code is sampling-based; per docs Tech-Ent-AI, "You can't audit what you can't read", and scattered procedural logic "cannot be fully verified". Docs Tech-Gov-By-Arch claims regulations can compile to rules with a report "mapping each transaction back to the rules that fired and the requirement they came from" — but the supporting case (customs system, 2 days vs "roughly two engineer-years") is Row 3 narrative.

**This project's specific asset.** The artifact chain already generates: Behave feature files name requirements, scenarios embed per-transaction logic logs, and `python behave_logic_report.py run` writes `reports/Behave Logic Report.md` — requirement → rule → execution trace, produced mechanically (Row 1; **apilogicserver-validation-and-qa**).

**First three steps.**
1. Pick one small, real, public regulation fragment (a handful of clauses with computable obligations); write each clause as a Behave feature narrative in `test/api_logic_server_behave/features/`.
2. Implement the clauses as rules; run the suite; generate the report (`cd test/api_logic_server_behave && python behave_run.py --outfile=logs/behave.log && python behave_logic_report.py run`).
3. Put the report in front of a person who audits for a living and record what fails them — the gap list is the research content. Changes gated by **apilogicserver-change-control**.

**You have a result when** an independent reviewer with audit experience can trace every clause of the chosen fragment to a rule and to a logged transaction using only the published report — or the recorded gap list explains precisely why not. This either substantiates a Row 3 claim upward or bounds it.

*Ledger row today:* the report generator is Row 1; "regulations compile to enforceable rules" is Row 3 narrative until an external reviewer signs off.

---

## 3. Where ideas come from here

The lineage has one repeating move — **keep the declarative thesis, change the delivery vehicle** (all history per docs; entries A2/A3 in **apilogicserver-failure-archaeology**):

| Generation | Vehicle | What the era's platform wave was | What died with the vehicle |
|---|---|---|---|
| Versata | Enterprise 4GL (fourth-generation language) with its own studio, per-CPU pricing, J2EE | J2EE | The studio (debugging/source-control friction) |
| CA Live API Creator | SaaS/commercial API tool | REST/API economy | The proprietary channel (acquired → end-of-life) |
| API Logic Server | Open-source Python, plain files, your IDE | Cloud-native / open source | (current) |
| Genai-Logic | Same engine; AI as the authoring front-end, MCP as the consumption front-end | AI agents | (current wave) |

Read the frontier list through that lens: every problem above is "declarative thesis × AI wave" — govern the agent's writes (F1), make the AI emit the IR instead of imperative code (F2), wrap the AI's choices in constraints (F3), extend the engine the thesis rides on (F4), automate entry from the pre-thesis world (F5), and turn enforcement into audit currency (F6). When a new idea appears, first ask which asset in Row 1 it stands on and which archaeology entry already tried it; an idea standing only on Row 3 numbers is marketing, not research.

Each wave also carries its characteristic failure, and the current one is documented in-house: **apilogicserver-failure-archaeology** A10 (GenAI overreach) — AI output treated as done instead of candidate. The docs' own security page states the counter-position this skill enforces at the claims layer: "nothing generated by AI is live by default" and "AI writes the logic; it doesn't run your business." Frontier work that weakens either sentence for a demo is repeating the wave's failure, not riding the wave.

**The handoff line: a hunch becomes a result only through apilogicserver-research-methodology** — its evidence bar, predict-numbers-first rule, and idea lifecycle govern execution; this skill only tells you where to aim and what you may say afterward.

---

## Provenance and maintenance

Volatile facts and how to re-verify each (run from any created project root unless noted):

- Genai-Logic version and CLI surface: `als welcome` (prints "Welcome to Genai-Logic <version>"); `als genai-logic --help` for F2's flags (`--using`, `--suggest`, `--logic`, `--retries` verified 2026-08-25 on 17.03.19).
- Engine chain / 400 code-2001 refusal shape: run the check-credit probe PATCH from **apilogicserver-debugging-playbook** against your own scratch project and read the response body + logic log.
- Behave golden counts (7/26/83, ~1.4 s on nw_sample): `cd test/api_logic_server_behave && python behave_run.py --outfile=logs/behave.log` with the server running.
- Row-filter matrix totals: the curl probes in **apilogicserver-security-model** §6 (login per user, read `meta.total`).
- MCP discovery surface and auth posture: `curl -s http://localhost:5656/.well-known/mcp.json` with no Authorization header.
- MCP client executor status label ("Tech Preview"): re-read https://apilogicserver.github.io/Docs/Integration-MCP/ — promote F-problem and ledger placement if the label changes.
- Probabilistic-logic status: re-read https://apilogicserver.github.io/Docs/Eval-probabilistic_logic/ and https://apilogicserver.github.io/Docs/Eval-probabilistic_logic_guide/ — currently pattern docs with Nov 2025 debugging notes, no shipped rule type; move F3 out of Row 4 only when a mechanism ships with a benchmark.
- The 40X / A/B artifact and its caveats: `cat logic/procedural/declarative-vs-procedural-comparison.md` in any created basic_demo (v1.0 dated 2026-07-22 as read here; check the version header and the companion-suite coverage note on re-read).
- Lineage numbers (700+ sites, ~97%, minutes→2s): re-fetch the docs URLs listed in **apilogicserver-failure-archaeology** Provenance; they are docs' claims and move only if the docs move.
- "Enterprise vibe" page: re-fetch https://apilogicserver.github.io/Docs/Tech-Enterprise-Vibe/ — a stub as of 2026-08-25; if it becomes prose, mine it for positioning language and re-check Row 4.
- Startup compile-gate behavior (F2's type-check claim): `python api_logic_server_run.py` in any project — confirm the discovered-logic dependency listing prints, and that an intentionally misspelled rule signature in a scratch `logic/logic_discovery/` file aborts start.
- Comparison-artifact link location in generated projects: `grep -n "declarative-vs-procedural" logic/declare_logic.py logic/readme_logic.md` in a created basic_demo.
- The `short_format_exception` logging bug (Row 1 defect entry): `grep -n "splitlines" config/server_setup.py` in a 17.03.19 project — if the call no longer passes `'\n'`, the bug is fixed; update Row 1 and the archaeology entry.
- F5's legacy exhibit: confirm `turbo3.5_excel_vba/` and `api_Key.xlsm` still sit at this repository's root before quoting the exhibit or starting the campaign baseline.
- If a docs URL is unreachable on re-verification: retry once, then keep the material labeled "per docs (unreachable on <date>)" — do not silently drop the label or the claim.

Grounded in: https://apilogicserver.github.io/Docs/Eval-probabilistic_logic/, https://apilogicserver.github.io/Docs/Eval-probabilistic_logic_guide/, https://apilogicserver.github.io/Docs/Logic-Why-Declarative-GenAI/, https://apilogicserver.github.io/Docs/Architecture-What-Is-GenAI/, https://apilogicserver.github.io/Docs/Tech-Gov-By-Arch/, https://apilogicserver.github.io/Docs/Tech-Ent-AI/, https://apilogicserver.github.io/Docs/Tech-Enterprise-Vibe/, https://apilogicserver.github.io/Docs/FAQ-AI/, https://apilogicserver.github.io/Docs/FAQ-AI-Security/, https://apilogicserver.github.io/Docs/Integration-MCP/ and a live Genai-Logic 17.03.19 install (2026-08-23). Live checks ran against real created projects (basic_demo, nw_sample) and a running server, verified against a live install; the on-disk comparison artifact and MCP discovery endpoint were re-probed 2026-08-25 during authoring.
