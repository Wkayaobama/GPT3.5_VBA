---
name: apilogicserver-genai-development
description: AI-assisted development of API Logic Server (Genai-Logic) projects - the genai CLI family (als genai, genai-create, genai-iterate, genai-logic, genai-add-app, genai-graphics, genai-utils --fixup/--import-genai), WebGenAI, natural-language logic prompts (docs/logic/*.prompt), the in-project AI kit (CLAUDE.md, .github/copilot-instructions.md, docs/training/), and guardrails keeping AI output a candidate until verified. Use when creating or iterating a project from an NL prompt, adding logic in natural language, choosing a genai command, setting APILOGICSERVER_CHATGPT_APIKEY, importing a WebGenAI export, or on symptoms - "APILOGICSERVER_CHATGPT_APIKEY environment variable not set", failed LLM response, --repaired-response replay, genai-utils --fixup, hallucinated attribute broke server startup, AI wrote plausible-but-wrong rules, prompt drift across iterations, "should I let the AI write this rule".
---

# API Logic Server GenAI Development

## Purpose

This skill is the runbook for AI-assisted development of API Logic Server (ALS, packaged as Genai-Logic) projects: what each `genai*` CLI command does, which parts are deterministic vs. LLM-driven, how natural-language ("NL") logic becomes reviewable declarative rules, how created projects self-document for coding agents, and the guardrails that keep every AI output a *candidate* until it passes evidence gates. Facts labeled **verified 2026-08-23, Genai-Logic 17.03.19** were confirmed by execution or by reading the installed engine source and two live-created projects (`basic_demo`, Northwind `nw+` sample). Anything the LLM itself produces was NOT exercised here (no API key in the verification environment) and is labeled **per docs, not live-verified** — this skill says so plainly wherever it applies.

## Use this skill when

- You are about to run any `als genai*` command, or must choose between them (create vs. iterate vs. add-logic vs. add-app vs. graphics).
- You want to add business logic by writing natural language (in `docs/logic/*.prompt` files or an IDE AI chat) instead of hand-writing rules.
- You hit: `APILOGICSERVER_CHATGPT_APIKEY environment variable not set`, a failed/garbled LLM response, or need the `--repaired-response` deterministic replay.
- An AI assistant (any coding agent) is working in an ALS project and you need to know what context it should load and how to check its output.
- You are importing/exporting between the WebGenAI web product and a local project (`genai-utils --import-genai`, `docs/export/export.json`).
- A server broke *after* AI-generated changes (startup failure at rule activation, wrong numbers that "look right").
- You are deciding whether a change should go through GenAI at all.

## Do NOT use this skill when

- You are hand-writing or reviewing specific rule code → **apilogicserver-logic-patterns** (engine theory → **declarative-rules-reference**).
- You need MCP wiring details (mcp_client_executor, SysMcp, .well-known/mcp.json) → **apilogicserver-integration-patterns** (this skill only covers the `genai-add-mcp-client` command's place in the landscape).
- You need non-genai CLI commands, `--db-url` forms, config.py → **apilogicserver-cli-and-config**.
- You need the Behave suite mechanics and evidence format → **apilogicserver-validation-and-qa**.
- You need the rebuild/merge flow that lands a change → **apilogicserver-change-control** (every procedure here ends at its gates).
- You are running the full legacy-to-ALS migration → **apilogicserver-modernization-campaign**.
- You want the history of GenAI overreach and settled failures → **apilogicserver-failure-archaeology**.

---

## 1. The GenAI landscape

Definitions used throughout:

- **Manager** — the Genai-Logic workspace folder (created by `als start`, per docs) that holds your projects plus `system/genai/` (examples, templates, temp/conversation files). The installed package ships this as a prototype containing `system/genai/{examples, temp, prompt_inserts, reference, ...}` (verified 2026-08-23, Genai-Logic 17.03.19).
- **Prompt** — a plain-text natural-language requirement file (`*.prompt`).
- **Response file** — the raw LLM reply (JSON), saved under `system/genai/temp/<project>/` for diagnosis and replay (per docs).
- **LLM-dependent** — the step calls OpenAI (or Azure OpenAI) and requires the API key below. **None of the LLM-dependent behavior was live-verified here (no API key)** — commands, flags, and file conventions were verified; the generation quality and exact outputs were not.

### 1.1 LLM prerequisites (verified from installed engine source)

Verified 2026-08-23, Genai-Logic 17.03.19, by reading `api_logic_server_cli/genai/client.py`, `genai_logic_builder.py`, `genai_utils.py` in the installed package:

| Env var | Meaning | Behavior if unset |
|---|---|---|
| `APILOGICSERVER_CHATGPT_APIKEY` | OpenAI API key (exact name) | `client.py` raises `Exception("APILOGICSERVER_CHATGPT_APIKEY environment variable not set")`; `genai_logic_builder.py` logs `Missing env value: APILOGICSERVER_CHATGPT_APIKEY` |
| `APILOGICSERVER_CHATGPT_MODEL` | Model selection | default `gpt-4o-2024-08-06` (in `genai_utils.py`) |
| `APILOGICSERVER_CHATGPT_AZURE_ENDPOINT` | Use Azure OpenAI instead | falls back to plain OpenAI client |
| `APILOGICSERVER_CHATGPT_AZURE_API_VERSION` | Azure API version | default `2024-10-21` |

Set the key in your shell (or IDE env) before any LLM-dependent command. Do not put keys in `config/config.py` or commit them.

### 1.2 Command landscape table

"What it does" quotes the installed `--help` verbatim where quoted. Verification column: **V** = command + flags verified 2026-08-23, Genai-Logic 17.03.19 (help text executed; behavior with a live LLM NOT exercised); **D** = per docs, not live-verified.

| Command | What it does | LLM? | Deterministic parts | Ver. |
|---|---|---|---|---|
| `als genai-create --project-name=X --using="description"` | "Create new project from --using prompt text" — one-line NL description → full project. Help: "cd to the manager, and..." | Yes (schema + rules + test data from NL) | Project scaffold, API, admin app generated conventionally from the LLM-produced model | V |
| `als genai --using=<file-or-dir>` | "Creates new customizable project (overwrites)." Runs a prompt file or a directory of prompts (a conversation); also the replay entry point (`--repaired-response`) | Yes, EXCEPT with `--repaired-response` (no LLM call) | Everything after the LLM response: models.py, API, admin app, project layout via standard `als create` machinery | V |
| `als genai-iterate --project-name=X --using="add xx table"` | "Iterate current project from --using prompt text" — evolve an existing genai project with a follow-up prompt | Yes | Regeneration pipeline; prior iterations kept under `system/genai/temp/<project>/` (per docs) | V (help) / D (flow) |
| `als genai-logic` (no args: reads `docs/logic/*.prompt`) or `als genai-logic --logic="balance is total of order amounts"` | "Adds (or suggests) logic to current project" — NL → LogicBank rules written into `logic/logic_discovery/` | Yes | Rule files land in `logic/logic_discovery/` where normal discovery loads them (discovery verified) | V (help + prompt-dir convention read from live project) |
| `als genai-logic --suggest` (then `--suggest --logic='*'`) | Ask the LLM to *suggest* rules for your schema; second form shows generated rule code. Work dir: `docs/logic_suggestions/` (dir + readme verified in both live projects) | Yes | — | V (dirs) / D (flow) |
| `als genai-add-app --app-name=myapp --vibe` | "Add customizable react app in ui/ for current project, ready for vibe" — generates React app from `ui/admin/admin.yaml` (default `--schema`), `--retries` = lint retries | Yes (generation + lint-fix loop) | Input schema is the deterministic `admin.yaml` | V (help) / D (output) |
| `als genai-graphics` (reads `docs/graphics/*.prompt`) | "Adds graphics to current project" — NL prompt → dashboard graphic (SQL query + chart HTML) into `api/api_discovery/`; `--replace-with` retries/deletes | Yes | Landing spot `api/api_discovery/` (API auto-discovery verified). Live example artifacts (`request.json`, `response.yaml` with `sql_query` + `html_code`) shipped in the nw+ sample, read here | V (help + artifacts) / D (run) |
| `als genai-add-mcp-client [--admin-app]` | "Adds mcp-client to project: db, logic, admin app" — scaffolds the MCP client executor pieces. Details → **apilogicserver-integration-patterns** | Command itself: No (scaffold add). Runtime NL processing: Yes (executor reads `APILOGICSERVER_CHATGPT_APIKEY`, verified in shipped executor source) | Scaffolding | V |
| `als genai-utils --fixup` | "Fix data model and test data" — repairs the model/test data when added rules reference missing attributes | Yes | — | V (help) / D (flow) |
| `als genai-utils --import-genai` / `--import-resume` | "Import Web-Genai Export" into a local project / "Fix import models, and restart" | Per docs, merge is tool-driven | Import/merge bookkeeping | V (help) / D (flow) |
| `als genai-utils --rebuild-test-data` / `--submit --using=...` / `--response <file>` | Rebuild DB test data for derivation rules / raw prompt submit / use a saved response file | Yes (rebuild, submit) | — | V (help) / D (flow) |
| **WebGenAI** (web product, apifabric.ai public trial or docker) | Browser app: NL prompt → running system (database, JSON:API, admin app) with logic editor, suggestions, accept/reject, iteration; download/export to IDE | Yes | Built on ALS — "API Logic Server provides the CLI functions used by WebGenAI" (per docs) | D |
| **GenAI-Logic Web Studio** ("Project Studio") | BA/PM-facing web product positioning ("5 rules instead of ~200 lines of code"); docs page does not state its exact relationship to WebGenAI or GA status | Yes | — | D — status open/candidate |

Notes, all verified 2026-08-23, Genai-Logic 17.03.19 unless marked:

1. **`als genai` OVERWRITES.** The help says "(overwrites)" — never point `--using` at a name whose project directory holds uncommitted work. Commit first (change-control non-negotiable).
2. **17.03.19 help-text defects (verified):** in `als genai --help`, `--temperature` is described as "Number of test data rows", `--use-relns` as "Project location", and `--active-rules` as "Show this message and exit." — the descriptions are misaligned. Trust the flag *names*; for semantics of anything beyond `--using`, `--db-url`, `--genai-version`, `--repaired-response`, `--retries`, consult the WebGenAI-CLI docs page, and treat those flags as **per docs, not live-verified**.
3. The docs' Sample-Genai page also shows `--gen-using-file=...` (simulate without an API key); that flag is **not** listed in the installed 17.03.19 `als genai --help` — per docs, not live-verified; expect it may be absent.
4. Entry points installed: SIX equivalents — `ApiLogicServer`, `als`, `genai-logic`, `gail`, `gal`, `gl` — all declared in `entry_points.txt` and verified working (2026-08-26; an earlier capture wrongly recorded `gail`/`gal` as absent). Script against `als`/`ApiLogicServer` for portability.
5. Full non-genai command catalog → **apilogicserver-cli-and-config**.

### 1.3 What the LLM produces vs. what conventional generation produces

Per docs (Architecture-What-Is-GenAI), the LLM is used for exactly three things: **the data model, NL-logic→rules translation, and test data**. Everything else — SQLAlchemy models.py from that model, JSON:API, admin app, project layout, rules *engine* — is the same deterministic generation as `als create` from an existing database (that path fully verified; see **apilogicserver-architecture-contract**). This is the safety-relevant boundary: the LLM writes *inputs to generators and rule declarations*, not the runtime.

Canonical example prompt, verbatim from the installed Manager prototype `system/genai/examples/genai_demo/genai_demo.prompt` (verified 2026-08-23, Genai-Logic 17.03.19):

```
Create a system with customers, orders, items and products.

Include a notes field for orders.

Use case: Check Credit    
    1. The Customer's balance is less than the credit limit
    2. The Customer's balance is the sum of the Order amount_total where date_shipped is null
    3. The Order's amount_total is the sum of the Item amount
    4. The Item amount is the quantity * unit_price
    5. The Item unit_price is copied from the Product unit_price

Use case: App Integration
    1. Send the Order to Kafka topic 'order_shipping' if the date_shipped is not None.
```

Run it (per docs): `als genai --using=system/genai/examples/genai_demo/genai_demo.prompt` from the Manager. Recovery paths if the LLM response is bad — see §5, Deterministic replay.

### 1.4 Runbook: NL logic via prompt files (`als genai-logic`)

Directory conventions verified 2026-08-23, Genai-Logic 17.03.19 (read from both live projects' shipped readmes); the generation step itself is LLM-dependent, not live-verified here.

1. From the project root, write one requirement per file in `docs/logic/`, e.g. `docs/logic/valid_currency.prompt` containing: `Customer credit limits cannot be negative; Product prices must be positive.` Use the numbered use-case format of §2 for multi-sentence logic.
2. Check the data model FIRST: any derived attribute the prompt names (a balance, a total) must already exist as a column, initialized in the database — the shipped readme states both requirements explicitly. If it does not exist, add it via the **apilogicserver-change-control** rebuild flow *before* generating (or expect a `genai-utils --fixup` cycle).
3. Ensure `APILOGICSERVER_CHATGPT_APIKEY` is set (§1.1). Run `als genai-logic` from the project root. Expect (per docs): new rule file(s) in `logic/logic_discovery/`.
4. Rename consumed prompts `valid_currency.prompt` → `valid_currency.z-prompt` so re-runs skip them (shipped convention — otherwise the next run regenerates them).
5. Review the generated rules 1:1 against your sentences (§2), then run gates (a)-(d) of §5. Do not skip to the admin app "looks right" check — that is not a gate.

Same shape for graphics: `docs/graphics/*.prompt` → `als genai-graphics` → artifacts into `api/api_discovery/` (the nw+ sample ships worked examples: `sales_by_category.prompt` and the captured `request.json`/`response.yaml` showing the LLM returns `sql_query` + Chart.js `html_code` per graphic). Note the generated chart HTML references a CDN — review it like any AI code before landing.

---

## 2. The NL→rules bridge: THE teaching example

This is the core of why NL logic in ALS is *reviewable* rather than a leap of faith. The following is verbatim from a live-created project, `logic/declare_logic.py` in `basic_demo` after `als add-cust` (verified 2026-08-23, Genai-Logic 17.03.19). First the natural language, kept in the file as a docstring:

```python
    # Logic from GenAI
    '''
    You can enter logic in 2 ways:
        1. Using your IDE and code completion (Rule.)

        2. Use your AI Assistant and enter logic in Natural Language, e.g.:
            Create Business Logic for Use Case = Check Credit:  
                1. The Customer's balance is less than the credit limit
                2. The Customer's balance is the sum of the Order amount_total where date_shipped is null
                3. The Order's amount_total is the sum of the Item amount
                4. The Item amount is the quantity * unit_price
                5. The Item unit_price is copied from the Product unit_price

            Use case: App Integration
                1. Send the Order to Kafka topic 'order_shipping' if the date_shipped is not None.
    '''
```

Then its exact translation — the entire executable output for those six sentences:

```python
    Rule.constraint(validate=Customer, as_condition=lambda row: row.balance <= row.credit_limit, error_msg="Customer balance ({row.balance}) exceeds credit limit ({row.credit_limit})")
    Rule.sum(derive=Customer.balance, as_sum_of=Order.amount_total, where=lambda row: row.date_shipped is None)
    Rule.sum(derive=Order.amount_total, as_sum_of=Item.amount)
    Rule.formula(derive=Item.amount, as_expression=lambda row: row.quantity * row.unit_price)
    Rule.copy(derive=Item.unit_price, from_parent=Product.unit_price)
    Rule.after_flush_row_event(on_class=Order, calling=kafka_producer.send_row_to_kafka, if_condition=lambda row: row.date_shipped is not None, with_args={'topic': 'order_shipping'})
```

**Why this makes NL logic safe — rules as a verifiable intermediate representation (IR):**

1. **1:1 sentence↔rule mapping.** Each numbered NL sentence maps to exactly one declaration. A reviewer diffs six lines against six sentences. The same file states the alternative: "The 5 declarative lines below represent the same logic as 200 lines" of procedural Python, and "Consider a 100 table system: 1,000 rules vs. 40,000 lines of code" (verbatim comments in the live file). Nobody reviews 200 generated procedural lines per use case; everybody can review 5 rules.
2. **The target language is constrained.** The LLM emits `Rule.sum / formula / constraint / copy / event` declarations — a tiny DSL of data invariants — not free-form code with hidden control flow. Docs frame it: "You want AI to generate SQL for the database runtime engine — not generate the database engine itself. The same principle applies to business logic" (Tech-AI-Collaboration, per docs). Ordering, change-path coverage, and re-derivation are the *engine's* job (see **declarative-rules-reference**), so a whole class of AI bugs (missed change paths — 2 bugs in the 220-line procedural A/B version, per the project's shipped context file) cannot be written at all.
3. **The IR is executable and observable.** Rules register in a startup dependency listing, fire visibly in the logic log with `[old-->] new` values, and reject bad data with typed 400s (all verified — formats in **apilogicserver-debugging-playbook**). So an NL claim like sentence 2 is *checkable*: PATCH an Item on an unshipped order and watch the chain formula→sum→sum→constraint fire (this exact experiment verified live, including the shipped-order case where the `where=` clause correctly suppresses it).

Consequence for practice: **review the rules, not the prose; then verify the rules with numbers** (§5). When using an IDE AI assistant instead of the CLI, paste the NL block in the same numbered-use-case format above — it is the format every created project teaches its assistant (§3).

### 2.1 Runbook: NL logic via an IDE assistant (no CLI, no genai run)

This is the zero-API-key path — the assistant's own model does the translation, guided by the in-project kit (§3). Steps:

1. Open the project root in the IDE so the kit loads (Claude Code: automatic via `CLAUDE.md`; Copilot: say `Please load .github/copilot-instructions.md` — activation phrase verified as shipped content).
2. State the logic in the numbered use-case format of §2, one sentence per rule, naming real model attributes (check `database/models.py` / `docs/db.dbml` first — **apilogicserver-data-modeling**).
3. Expect the assistant to write a new file `logic/logic_discovery/<use_case>.py` (one file per use case, named after it — the kit mandates this; discovery of such files verified live) containing only `Rule.` declarations plus a `declare_logic()` wrapper, imports inside the function per the training corpus (§4).
4. Reject on sight: procedural code where a rule type exists (Pattern 8, §4), `calling=` on sum/count/copy, event handlers missing the three-parameter signature, module-level LogicBank imports.
5. Run gates (a)-(d) of §5 yourself. The assistant claiming success is not evidence; the startup listing, predicted numbers, and logic log are.

---

## 3. How created projects teach AI assistants (the in-project kit)

Every project created by 17.03.19 ships a self-documentation kit for coding agents. All filenames below were read from the two live-created projects — both `basic_demo` and `nw_sample` carry the identical kit (verified 2026-08-23, Genai-Logic 17.03.19). One-line purposes are from reading each file:

| File | Purpose (from reading it) |
|---|---|
| `CLAUDE.md` | Two `@`-include lines only: `@.github/copilot-instructions.md` and `@docs/training/logic_bank_api.md` — auto-loads the master context + full rule API into a Claude Code session at start. |
| `.claude/settings.json` | Pre-approves `Bash(*)`, `Read`, `Write`, `Edit` permissions for Claude Code in the project. |
| `.github/copilot-instructions.md` | The master context file ("Context Engineering... version 3.6", 2,923 lines): activation protocol, capabilities menu, discovery-systems rules (one logic file per use case in `logic/logic_discovery/`), "impl req" requirements workflow, declarative-vs-procedural argument with the 9-change-path table, Request Pattern, testing pointers, MCP overview, `logs/als.log` is AI-readable. The docs call this the "message in a bottle". |
| `.github/welcome.md` | The clean welcome screen an activated assistant must display; wires the "guide me through" tour trigger. |
| `.github/agents/genai-logic.agent.md` | A custom agent definition ("GenAI-Logic"): silently internalize copilot-instructions.md, display only welcome.md, then treat copilot-instructions.md as the standing session reference; declares a preferred-model list. |
| `.github/instructions/eai_subscribe.instructions.md` | Scoped instruction file (frontmatter `applyTo: "**/kafka_subscribe_discovery/**"`): a mandatory pre-implementation read for Kafka-consume work — read `docs/training/eai_subscribe.md` in full, 2-message design mandatory, replay/delete-integrity checks must pass. Pattern to copy for your own guarded areas. |
| `tutor.md` | 1,453-line guided-tour choreography, activated by "guide me through"; the assistant is instructed to follow it exactly. |
| `start_here.md` / `readme.md` | Human-facing orientation; readme embeds working examples the assistant may cite. |
| `docs/training/` | The AI training corpus — §4. |
| `docs/logic/readme.md` | How to drop NL `*.prompt` logic files here for `als genai-logic`; rename to `*.z-prompt` after a run so they are skipped next time. |
| `docs/logic_suggestions/` | Work directory for `als genai-logic --suggest`. |
| `docs/graphics/` | NL `*.prompt` files for `als genai-graphics` (nw+ sample ships real ones plus captured `request.json`/`response.yaml` LLM artifacts). |
| `docs/requirements/` | `project_creation_prompt.md` (what was asked), `project_creation_report.md` (scaffold provenance; each "impl req" run appends its use case here), `readme-workflow.md`. |
| `docs/mcp_learning/` | `mcp.prompt` (LLM instructions for driving the API, fan-out syntax, response schema), `mcp_schema.json` (+ `mcp_discovery.json` after MCP discovery runs) → details in **apilogicserver-integration-patterns**. |
| `docs/system-creation-vibe.md` | A recorded end-to-end vibe transcript: create from DB, react app, MCP client, then the exact Check Credit NL block of §2. |
| `docs/export/export.json` (WebGenAI-synced projects) | Rules export consumed at startup when env `WG_PROJECT` is set — `logic/load_verify_rules.py` reads `EXPORT_JSON_PATH` (default `./docs/export/export.json`), verifies rules, then activates (path verified from live project code; WebGenAI round-trip itself per docs). |

**Implication:** point any coding agent at the project root and this context loads — Claude Code via `CLAUDE.md`'s `@`-includes automatically; VS Code Copilot via `.github/copilot-instructions.md` / the custom agent; any other agent via the documented activation phrase `Please load .github/copilot-instructions.md`. **This skill library complements the kit at ecosystem level**: the in-project kit teaches an assistant to *drive that project*; this library adds cross-project ground truth (verified behaviors, bugs, gates) the kit does not carry. Where they conflict on facts, prefer the labels here and the live logs.

Two cautions (owner-ratified): (a) the kit's "silent activation" blocks instruct assistants to hide the loading step — fine for UX, but never let it suppress the evidence gates of §5; (b) the kit is regenerated project infrastructure — treat edits to it as changes classified under **apilogicserver-change-control** (docs-of-record section).

---

## 4. The docs' own AI training corpus (`docs/training/`)

The docs pages **Eval-genai_logic_patterns** and **Eval-logic_bank_patterns** publish, for evaluation, the same two files every project ships in `docs/training/`. Both files were read in full from the live-created projects (verified 2026-08-23, Genai-Logic 17.03.19) — the docs pages mirror them. They are gold for prompting logic correctly: paste-adjacent, with explicit WRONG/CORRECT pairs.

**`genai_logic_patterns.md` (v1.0, "GenAI Logic Patterns - Universal Guide")** — patterns for calling AI *from inside* business logic at runtime:

1. *Critical Imports - AVOID CIRCULAR IMPORTS* — import `Rule`/`LogicRow` inside functions, never at module level in discovered files (auto-discovery otherwise fails with "cannot import name 'LogicRow' from partially initialized module").
2. *LogicBank Triggered Insert Pattern* — never `session.add()+flush()` inside a formula ("Session is already flushing"); use `logic_row.new_logic_row(ModelClass)` → `.link(to_parent=...)` → `.insert(reason=...)`.
3. *AI Value Computation Architecture* — use-case logic in `logic/logic_discovery/`, reusable AI handlers in an `ai_requests/` subfolder, Request Pattern encapsulated.
4. *Auto-Discovery ... RECURSIVE SCANNING REQUIRED* — subdirectory modules need `declare_logic()` and correct `os.walk` pathing.
5. *Formula Pattern with AI* — conditional formulas: deterministic fallback when data is insufficient, AI value otherwise.
6. *Event Handler Patterns* — `early_row_event` to populate fields other rules consume; `row_event` for side effects.
7. *Common Patterns Summary* — simple AI formula / conditional / AI-with-audit-trail / reusable handler, as copyable code.
8. *Testing Patterns* — test AI handlers independently; mock the AI call.
9. *Error Handling* — graceful fallback values; record error details on the audit row.
10. *Best Practices* — ten-point list (fallbacks always, audit via Request Pattern, `logic_row.log()` for visibility...).

This is the runtime-AI ("probabilistic logic") side — the docs' Logic-Using-AI page's example: "Use AI to Set Item field unit_price by finding the optimal Product Supplier based on cost, lead time, and world conditions" (per docs, not live-verified). Deeper treatments ship alongside: `probabilistic_logic.md`, `probabilistic_logic_guide.md`, `probabilistic_template.py` (which reads `APILOGICSERVER_CHATGPT_APIKEY` — verified in shipped source).

**`logic_bank_patterns.md` (v1.1, "LogicBank Patterns - The Hitchhiker's Guide")** — general rule-authoring patterns any AI (or human) must obey:

1. *Event Handler Signature* — always `(row, old_row, logic_row)`; `LogicRow.get_logic_row(row)` does not exist.
2. *Logging with logic_row.log()* — not `app_logger`, so output lands indented in the logic trace.
3. *Request Pattern (ROP) - Integration Services* — request fields in, event computes, response fields out, automatic audit; recognition signal in prompts: "calculate/determine/select X when Y is given".
4. *Rule API Syntax Reference* — which rule types have `calling` (formula, constraint) and which never do (sum, count, copy, parent_check); includes the LBActivateException scanner pitfall (see §6).
5. *Common Anti-Patterns* — the five recurring AI mistakes, each with the exact wrong code.
6. *Type Handling for Database Fields* — `int` for FKs (SQLite rejects Decimal there), `Decimal(str(...))` for money.
7. *Testing and Debugging Patterns* — `logic_row.log()` liberally, `old_row` change detection, `is_inserted/updated/deleted`.
8. *Rules vs Events — Rules Are ALWAYS Preferred* — events only for side effects or opaque external calls; a decision table, plus the event-ordering rule (declaration order guaranteed within one `declare_logic()`, non-deterministic across discovered files).

**How to use the corpus when prompting for logic:** instruct the assistant to read `docs/training/logic_bank_api.md` (the full 1,484-line rule API) plus these two pattern files *before* writing rules — this is exactly what `CLAUDE.md` and the activation protocol already mandate. `docs/training/README.md` is the corpus index (also: `implement_requirements.md` for whole subsystems, `testing.md` before writing tests, `eai_subscribe.md` before Kafka consume). The corpus is deliberately project-agnostic (`OVERVIEW.md`: "ALL FILES IN THIS FOLDER MUST BE PROJECT-AGNOSTIC") — treat it as regenerated framework material under change control, not a place for your project's specifics.

---

## 5. GUARDRAILS: AI output is a CANDIDATE until proven

Owner-ratified, docs-grounded, and consistent with **apilogicserver-change-control**. AI-generated schema, rules, test data, or code — from any `genai*` command, WebGenAI, or an IDE assistant — is a *candidate*. It becomes real only after ALL four gates:

**Gate (a) — It loads.** Start the server (`python api_logic_server_run.py`). Expect the normal banner ending "Explore data and API at ... http://localhost:5656" (verified format). Then confirm every new rule *registered*: the startup log prints a per-attribute dependency listing (verified format: lines like `..Customer.balance: constraint`, `..Order.amount_total: sum derived from ...`) and discovered-logic lines for each `logic/logic_discovery/` file. A rule that is absent from the listing does not exist, no matter what the source file says. Triage of activation failures → §6 and **apilogicserver-debugging-playbook**.

**Gate (b) — Predicted numbers pass.** Before running anything, write the acceptance scenario WITH the expected numbers ("PATCH Item.quantity 1→100 at unit_price 90 ⇒ Item.amount 9000 ⇒ Order.amount_total ... ⇒ Customer.balance ... ⇒ 400 constraint"). Then run it as a Behave scenario (or `als curl` probe first). Predicting the numbers *before* execution is what catches plausible-but-wrong logic (§6) — a passing green bar on numbers you didn't predict proves nothing. Mechanics and golden suite → **apilogicserver-validation-and-qa**.

**Gate (c) — Logic log reviewed.** Read the logic log of the new transactions (console or `logs/als.log`): confirm the expected rule chain fired, in the `[old-->] new` notation, and that "These Rules Fired" lists exactly the rules you meant — no extra AI-added rule silently adjusting other attributes. Reading guide → **apilogicserver-debugging-playbook**.

**Gate (d) — Lands via change control.** The change is then classified, reviewed, and merged per **apilogicserver-change-control** (its non-negotiables apply: commit before any overwriting command; genai-created schema changes follow the rebuild runbook; regenerated files never hand-forked). No AI output skips this because "the tool wrote it".

### Deterministic replay: the repaired-response mechanism (per docs, not live-verified)

When an LLM run fails or produces a broken model, you do NOT re-roll the dice. The system saves the conversation under `system/genai/temp/<project>/` (response JSON, `create_db_models.py` model file). Two recovery paths, per the WebGenAI-CLI and Sample-Genai docs:

```bash
# Path 1 - fix the generated MODEL file, then create conventionally (no LLM call):
als create --project-name=genai_demo --from-model=system/genai/temp/create_db_models.py --db-url=sqlite

# Path 2 - fix the saved RESPONSE JSON, then replay it (no LLM call):
als genai --repaired-response=system/genai/temp/genai_demo/response.json --project-name=genai_demo
```

`--repaired-response` re-runs the *deterministic* half of the pipeline from a file you edited and can diff — this is the auditable re-run path, and the reason to keep `system/genai/temp/` artifacts (and `docs/requirements/`) under source control per change-control's docs-of-record rules. `--retries INTEGER` (verified flag) bounds automatic LLM retry attempts before you drop to manual repair. For missing-attribute damage after adding rules, `als genai-utils --fixup` is the documented repair (per docs, not live-verified) — then re-run gates (a)-(d).

---

## 6. Failure modes

| Failure | Where it appears | What to do | Ver. |
|---|---|---|---|
| **Hallucinated attribute in a rule target** (e.g. `derive=Customer.ballance`, or a `calling=` body the dependency scanner misparses) | Server startup, during logic activation — BEFORE the "Explore data and API" banner; console + `logs/als.log`. Scanner-misparse case raises `LBActivateException: ['Charge.project_id).first: constraint']` (exact format from the shipped training file); a bad `derive=`/`as_sum_of=` class attribute fails at import of the rule module. Gate (a) catches all of these: the attribute is missing/garbled in the startup dependency listing | Fix the rule (or extract `row.x` to a local variable before chained calls — the documented scanner fix); if the *model* lacks the attribute the NL assumed, either add it via the **apilogicserver-change-control** rebuild flow or run `als genai-utils --fixup` (per docs) | verified 2026-08-23 (listing format, exception format from shipped file); fixup per docs |
| **Hallucinated attribute inside a lambda body only** | May pass activation and fail at FIRST FIRING (runtime AttributeError → 500 on the triggering transaction) — which is why gate (b)'s probe transaction is mandatory, not optional | Same fixes as above; find the firing rule in the logic log | failure surface reasoned from verified activation behavior; exact runtime path not live-verified |
| **Plausible-but-wrong logic** — loads fine, numbers wrong. Canonical example: AI omits `where=lambda row: row.date_shipped is None` from the balance sum (or inverts it). Every rule registers; the admin app "looks right" | Only at gate (b): your predicted numbers fail. Live-verified discriminator: with the correct `where=`, PATCH on a SHIPPED order's item succeeds (excluded from balance) while the same PATCH on an UNSHIPPED order 400s — an AI that dropped the `where=` flips that outcome. If you didn't predict numbers first, nothing fails | Numbers-first always (§5b); review each rule against its NL sentence 1:1 (§2); run the logic log (gate c) to see which orders adjusted the balance | verified 2026-08-23 (the discriminating experiment; the omission scenario is the reasoned inverse) |
| **Prompt drift across iterations** — each `genai-iterate` run resubmits the accumulated conversation; the LLM may regenerate schema/test data differently, renaming or dropping things earlier prompts established; entered data is not carried ("If you have entered important data, it is still available in the previous iteration" — WebGenAI docs) | Diff the project after every iteration (git, gate d); compare `docs/db.dbml` and the startup dependency listing against the previous run | Keep prompts cumulative and explicit (restate names you depend on); iterate in small steps; after each, run gates (a)-(c); pin recovered states via `--repaired-response` replay rather than re-prompting | per docs (genai-iterate/WebGenAI), not live-verified |
| **LLM run fails outright / garbled JSON** | CLI error; artifacts under `system/genai/temp/` | §5 replay paths; bound retries with `--retries` | per docs |
| **No API key** | `Exception: APILOGICSERVER_CHATGPT_APIKEY environment variable not set` | Export the key (§1.1); for logic, you can always write the rules by hand instead → **apilogicserver-logic-patterns** | verified 2026-08-23 (message in installed source) |

---

## 7. When NOT to use genai

Use the deterministic path instead when any of these hold:

1. **The change is mechanical and known.** You already know the rule/column/endpoint — write it directly (`Rule.` code completion, **apilogicserver-logic-patterns**; schema via **apilogicserver-change-control** rebuild flow). An LLM round-trip adds a regeneration blast radius (`als genai` overwrites; iterate regenerates test data) for zero information gain.
2. **You cannot write an acceptance scenario for it.** If you cannot state, before running, what transaction with what numbers proves it correct, gate (b) is impossible — so the output can never leave candidate status. Sharpen the requirement first (**apilogicserver-validation-and-qa** for scenario form).
3. **The project holds real data or uncommitted work** and the command regenerates (genai, genai-iterate, genai-utils --rebuild-test-data). Commit first; never point genai at production anything.
4. **The task is read-only analytics, a complex algorithm, or workflow orchestration** — the project's own shipped guidance excludes these from rules territory entirely (copilot-instructions "When NOT to use rules", verified as shipped content); NL→rules cannot help where rules don't apply.
5. **You are tempted to accept unreviewed output because it ran once.** That is the GenAI-overreach pattern chronicled in **apilogicserver-failure-archaeology** — the gates of §5 exist precisely for this.

Cheap sanity habit either way: `als genai-logic --suggest` (per docs) to get *candidate* rules to review, rather than letting generation land directly — suggestions cost nothing to reject.

---

## Provenance and maintenance

Volatile facts and how to re-verify each (run from any project root, venv active):

- genai command set and flags: `als --help` and `als genai --help; als genai-create --help; als genai-logic --help; als genai-iterate --help; als genai-add-app --help; als genai-graphics --help; als genai-add-mcp-client --help; als genai-utils --help`
- Help-text defect (misaligned descriptions for `--temperature`/`--use-relns`/`--active-rules`): re-run `als genai --help` and read the option descriptions.
- API-key env var name and missing-key message: `grep -rn "APILOGICSERVER_CHATGPT" "$(python -c 'import api_logic_server_cli,os;print(os.path.dirname(api_logic_server_cli.__file__))')/genai/client.py"`
- Default model / Azure vars: `grep -n "CHATGPT" "$(python -c 'import api_logic_server_cli,os;print(os.path.dirname(api_logic_server_cli.__file__))')/genai/genai_utils.py"`
- Canonical genai_demo prompt: `cat "$(python -c 'import api_logic_server_cli,os;print(os.path.dirname(api_logic_server_cli.__file__))')/prototypes/manager/system/genai/examples/genai_demo/genai_demo.prompt"`
- The NL block + 5-rule translation: `grep -n "Rule\.\|Check Credit" logic/declare_logic.py`
- In-project AI kit inventory: `ls CLAUDE.md .claude .github/agents .github/instructions docs/training docs/logic docs/logic_suggestions docs/graphics docs/mcp_learning docs/requirements`
- Training-corpus pattern lists: `grep -n "^PATTERN\|^## " docs/training/logic_bank_patterns.md docs/training/genai_logic_patterns.md`
- WebGenAI export path: `grep -n "EXPORT_JSON_PATH" logic/load_verify_rules.py`
- Startup dependency listing / discovered logic (gate a): `python api_logic_server_run.py` then read the pre-banner log, or `tail -200 logs/als.log`
- Repaired-response artifacts: `ls system/genai/temp/` in the Manager after any genai run.

Grounded in: https://apilogicserver.github.io/Docs/Architecture-What-Is-GenAI/, https://apilogicserver.github.io/Docs/WebGenAI/, https://apilogicserver.github.io/Docs/WebGenAI-CLI/, https://apilogicserver.github.io/Docs/Sample-Genai/, https://apilogicserver.github.io/Docs/Logic-Using-AI/, https://apilogicserver.github.io/Docs/Project-AI-Enabled/, https://apilogicserver.github.io/Docs/Eval-genai_logic_patterns/, https://apilogicserver.github.io/Docs/Eval-logic_bank_patterns/, https://apilogicserver.github.io/Docs/Tech-AI-Collaboration/, https://apilogicserver.github.io/Docs/Genai-logic-web-studio/ and a live Genai-Logic 17.03.19 install (2026-08-23).
