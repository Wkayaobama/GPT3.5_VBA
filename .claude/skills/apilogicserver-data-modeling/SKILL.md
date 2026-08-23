---
name: apilogicserver-data-modeling
description: Reference for the data-model layer of an API Logic Server (Genai-Logic) project - the generated database/models.py (SAFRSBaseX base class, _s_collection_name, Mapped relationship accessors like OrderList), primary/foreign-key requirements, keyless tables and views, quoted identifiers and column aliases, customize_models.py virtual attributes and added relationships, multiple databases via als add-db and bind keys, test-data seeding under database/test_data/, docs/db.dbml diagrams, and per-database (sqlite/postgres) notes. Use when reading or editing models.py, when a table is missing from the API or admin app ("created as table, no api, no rules"), when parent/child accessor names are unclear, when a relationship or sum fails for lack of a foreign key, when adding a derived attribute or relationship without a schema change, when seeding or rebuilding test data, when attaching a second database, or on keywords: models.py, SAFRSBaseX, allow_client_generated_ids, bind key, S_CheckSum, db.dbml, db_debug.
---

# API Logic Server Data Modeling

## Purpose

This skill explains the data-model layer of an API Logic Server project: the generated SQLAlchemy classes in `database/models.py`, the key and foreign-key requirements those classes depend on, how to customize the model without losing work, how test data is seeded, and how additional databases attach. SQLAlchemy is the Python ORM (Object-Relational Mapper: library that maps database tables to Python classes and rows to objects); API Logic Server generates the mapping for you by schema introspection (reading table/column/key definitions from a live database) and everything else — JSON:API endpoints, admin app, rules — keys off these classes. Get the model layer right and the rest of the stack follows; get keys or foreign keys wrong and the symptoms surface far away (missing endpoints, sums that never fire, empty relationship trees).

## Use this skill when

- You need to read or explain `database/models.py`: base classes, accessor names, aliases, types.
- A table has no API endpoint, no admin page, or "no rules" — likely a missing primary key.
- A `Rule.sum`/`Rule.copy` or a multi-table page cannot find its parent/child — likely a missing foreign key or relationship.
- You are adding a relationship or virtual attribute the schema does not have (`customize_models.py`).
- You are designing a NEW schema that API Logic Server will introspect (key types, indexes, stored-aggregate columns).
- You are seeding or repairing test data under `database/test_data/`.
- You are attaching a second database (`als add-db`, bind keys) or inspecting drift with `db_debug.py` / `docs/db.dbml`.

## Do NOT use this skill when

- Writing or debugging rules themselves → **apilogicserver-logic-patterns** (catalog) and **declarative-rules-reference** (theory).
- Changing the schema and regenerating/merging `models.py` → **apilogicserver-change-control** owns the rebuild runbook; this skill only tells you what the generated artifacts look like.
- JSON:API request syntax, filters, PATCH shapes, optimistic-locking protocol on the wire → **apilogicserver-api-contract**.
- `db-url` syntax catalog and `config.py` variables → **apilogicserver-cli-and-config**.
- Installing DB drivers (psycopg2, oracledb) or venv issues → **apilogicserver-build-and-env**.
- Roles, grants, and the authentication database's security semantics → **apilogicserver-security-model**.

---

## 1. Map of the database/ directory

Verified 2026-08-23, Genai-Logic 17.03.19, by listing two live-created projects (basic_demo and the Northwind sample).

| Path (project-relative) | What it is | Verification |
|---|---|---|
| `database/models.py` | Generated SQLAlchemy classes — the model of record | verified |
| `database/db.sqlite` | The project database itself (sqlite projects) | verified |
| `database/authentication_db.sqlite` | Auth database after `als add-auth` | verified |
| `database/system/SAFRSBaseX.py` | Base classes `SAFRSBaseX` and `TestBase` (do not edit) | verified |
| `database/customize_models.py` | YOUR model extensions — survives regeneration | verified |
| `database/database_discovery/` | Auto-imported model modules (auth models, graphics services) | verified |
| `database/bind_dbs.py` | Registers extra databases as SQLAlchemy binds | verified |
| `database/test_data/` | Seed-data scripts + readme (see section 7) | verified |
| `database/db_debug/db_debug.py` | Read-only schema inspector script (see section 8) | verified |
| `database/alembic/` + `alembic.ini` | Alembic migration scaffolding (schema-change flow: **apilogicserver-change-control**) | verified (present) |
| `docs/db.dbml` | DBML text diagram of the schema (see section 9) | verified |

---

## 2. Anatomy of generated models.py

All quotes below are verbatim from live-created 17.03.19 projects (verified 2026-08-23).

### 2.1 The file header — read it before touching the file

```python
########################################################################################################################
# Classes describing database for SqlAlchemy ORM, initially created by schema introspection.
#
# Alter this file per your database maintenance policy
#    See https://apilogicserver.github.io/Docs/Project-Rebuild/#rebuilding
#
# Created:  August 21, 2026 22:56:06
# Database: sqlite:////.../nw_sample/database/db.sqlite
# Dialect:  sqlite
#
# mypy: ignore-errors
########################################################################################################################
```

- "initially created by schema introspection" — the file is generated once at `als create`, then it is YOURS. Manual edits are expected ("Alter this file per your database maintenance policy") but must follow the merge discipline in **apilogicserver-change-control** because rebuild commands regenerate it.
- The `Created:`/`Database:` lines are stamped at generation time. Sample projects ship with the vendor's original path in the header — cosmetic only.
- The Northwind sample header adds a search guide: `manual  - illustrates you can make manual changes to models.py` and `example - more complex cases (explore in database/db_debug/db_debug.py)`. Grep `manual fix` in that file to find every sanctioned hand-edit example.

### 2.2 Base classes: SAFRSBaseX vs TestBase

Every generated class inherits from a `Base` chosen at import time (verbatim):

```python
from database.system.SAFRSBaseX import SAFRSBaseX, TestBase
...
if os.getenv('APILOGICPROJECT_NO_FLASK') is None or os.getenv('APILOGICPROJECT_NO_FLASK') == 'None':
    Base = SAFRSBaseX   # enables rules to be used outside of Flask, e.g., test data loading
else:
    Base = TestBase     # ensure proper types, so rules work for data loading
```

- `SAFRSBaseX` (in `database/system/SAFRSBaseX.py`) is `class SAFRSBaseX(SAFRSBase, safrs.DB.Model)`, abstract. SAFRS is the library that exposes SQLAlchemy classes as JSON:API endpoints (JSON:API: the REST convention with `data/attributes/relationships` payloads). SAFRSBaseX adds date-string parsing and the `filter[]` implementation.
- `TestBase` is selected when env var `APILOGICPROJECT_NO_FLASK=1` is set: a plain declarative base whose `__init__` coerces kwargs to proper column Python types so rules compute correctly during standalone (no-Flask) test-data loading. You never set this env var during normal server runs — only seed scripts set it (section 7).

### 2.3 A full generated class, annotated (basic_demo Order, verbatim)

```python
class Order(Base):  # type: ignore
    __tablename__ = 'order'
    _s_collection_name = 'Order'  # type: ignore

    id = Column(Integer, primary_key=True)
    notes = Column(String)
    customer_id = Column(ForeignKey('customer.id'), nullable=False)
    CreatedOn = Column(Date)
    date_shipped = Column(Date)
    amount_total : DECIMAL = Column(DECIMAL)

    # parent relationships (access parent)
    customer : Mapped["Customer"] = relationship(back_populates=("OrderList"))

    # child relationships (access children)
    ItemList : Mapped[List["Item"]] = relationship(back_populates="order")
```

Line by line:

| Element | Meaning |
|---|---|
| `__tablename__` | Physical table name; may differ from class name (see 2.5) |
| `_s_collection_name` | The API endpoint / admin-app name for this class. Defaults from the class name; edit it to rename the endpoint |
| `primary_key=True` | Required — see section 3 |
| `ForeignKey('customer.id')` | Physical FK; this is what makes the two `relationship()` lines exist |
| `amount_total : DECIMAL = Column(DECIMAL)` | Numeric columns carry a Python-side `: DECIMAL` annotation so rule arithmetic runs in `Decimal`, not float |
| `# parent relationships (access parent)` | One accessor per FK pointing OUT of this table: `anOrder.customer` returns the parent `Customer` object |
| `# child relationships (access children)` | One accessor per FK pointing IN: `anOrder.ItemList` returns the list of child `Item` rows |

### 2.4 Accessor naming — verified against the live API

Naming convention (generated, and surfaced verbatim in JSON:API `relationships`):

- **Parent accessor** (child → parent, to-one): the parent class name, lower- or same-cased as generated (`customer`, or `Customer` in the Northwind sample).
- **Child accessor** (parent → children, to-many): parent side gets `<ChildClass>List` — `OrderList`, `ItemList`, `OrderDetailList`.

Verified 2026-08-23 by GET against a running 17.03.19 server: an `Order` row's `relationships` keys were exactly `['Customer', 'Employee', 'Location', 'Order', 'OrderDetailList', 'OrderList']` — the same identifiers as in models.py. Rules reference these too (`Rule.sum(derive=Order.amount_total, as_sum_of=Item.amount)` walks `ItemList`). Renaming an accessor in models.py renames it everywhere: API, admin app, and any rule that used the old name breaks at startup.

When several relationships join the same pair of tables, the generator disambiguates with the FK name or a numeric suffix (per docs, not live-verified for the suffix case; the FK-name case is verified below).

### 2.5 Richer generated patterns (all verbatim from the Northwind sample, verified)

**Class name ≠ table name, and column alias.** The API name stays clean even when the physical name is ugly:

```python
class Category(Base):  # type: ignore
    __tablename__ = 'CategoryTableNameTest'
    _s_collection_name = 'Category'  # type: ignore

    Id = Column(Integer, primary_key=True)
    CategoryName = Column('CategoryName_ColumnName', String(8000))  # manual fix - alias
```

The Python attribute (`CategoryName`) is what API, admin, and rules see; the first `Column()` argument is the physical column. Same pattern on Order: `ShipZip = Column('ShipPostalCode', String(8000))  # manual fix - alias` — and the live API returns attribute `ShipZip`, not `ShipPostalCode` (verified in a GET response).

**Self-referential relationship** (Department has sub-departments):

```python
    DepartmentId = Column(ForeignKey('Department.Id'))
    # parent relationships (access parent) -- example: self-referential
    Department : Mapped["Department"] = relationship(remote_side=[Id], back_populates=("DepartmentList"))
    # child relationships (access children)
    DepartmentList : Mapped[List["Department"]] = relationship(back_populates="Department")
```

**Two FKs to the same parent** (Employee works-for / on-loan-to Department) — `foreign_keys=` disambiguates:

```python
    WorksForDepartmentId = Column(ForeignKey('Department.Id'))
    OnLoanDepartmentId = Column(ForeignKey('Department.Id'))
    OnLoanDepartment : Mapped["Department"] = relationship(foreign_keys='[Employee.OnLoanDepartmentId]', back_populates=("EmployeeList"))
    WorksForDepartment : Mapped["Department"] = relationship(foreign_keys='[Employee.WorksForDepartmentId]', back_populates=("WorksForEmployeeList"))
```

**Composite primary key + client-supplied keys** (Location):

```python
    country = Column(String(50), primary_key=True)
    city = Column(String(50), primary_key=True)
    ...
    allow_client_generated_ids = True
```

`allow_client_generated_ids = True` appears on every class whose primary key the client must supply (String PKs like Northwind `Customer.Id = 'ALFKI'`, composite PKs). Without it, SAFRS expects to autonumber and POSTs with explicit ids fail.

**Composite foreign key** — declared in `__table_args__`, not on a column:

```python
class Order(Base):
    __table_args__ = (
        ForeignKeyConstraint(['Country', 'City'], ['Location.country', 'Location.city']),
    )
```

**Manual referential-integrity fix** (SQLite does not cascade for you):

```python
    OrderDetailList : Mapped[List["OrderDetail"]] = relationship(cascade="all, delete", back_populates="Order")  # manual fix
```

Add `cascade="all, delete"` on the parent's child accessor when deleting a parent must delete its children.

### 2.6 Type mapping observed in generated files (verified)

| Schema type | Generated | Notes |
|---|---|---|
| INTEGER | `Column(Integer)` | |
| VARCHAR(n) | `Column(String(8000))`, `Column(String(50))` … | length preserved |
| DECIMAL | `x : DECIMAL = Column(DECIMAL)` | Python `Decimal` annotation for rule math |
| DECIMAL(10,2) | `Column(DECIMAL(10, 2))` | precision preserved |
| DATE | `Column(Date)` | |
| BOOLEAN | `Column(Boolean)` | |
| TEXT | `Column(Text)` | |
| DOUBLE | `Column(Double)` | |
| column default | `server_default=text("0")`, `text("Salaried")` | see section 4 on aggregate defaults |
| unmappable | `NullType` is imported with a `# datatype fixup` comment hook | fix by editing the column type |

Caveat, verified: introspection is faithful to the schema, including its sins — Northwind stores `Employee.BirthDate` and `Order.OrderDate` as `String(8000)` because the legacy schema did. Date-typed rules against string columns will not behave; fix the schema (change-control) or the column type, do not work around it in logic.

### 2.7 S_CheckSum — optimistic locking is NOT in models.py

Optimistic locking (detect that another user changed a row between your read and your write) rides on a virtual attribute `S_CheckSum`. It is **not a database column**. Attach point, verbatim from `api/expose_api_models.py`:

```python
def add_check_sum(cls):
    @safrs.jsonapi_attr
    def _check_sum_(self):
        ...
        return self._check_sum_property
    ...
    cls.S_CheckSum = _check_sum_
    return cls
```

Every exposed class is wrapped: `api.expose_object(add_check_sum(obj), ...)`. The value is stamped by `api/system/opt_locking/opt_locking.py`, which listens for SQLAlchemy's `loaded_as_persistent` (row read) and `after_flush` (row inserted) events. Flush is the ORM step that writes pending changes to the database inside a transaction. Config default is `OPT_LOCKING = "optional"` in `config/config.py`.

Verified 2026-08-23 on a live server: `Customer` GET rows carry `S_CheckSum` in `attributes`; in the same probe, `Order` rows did not — presence can vary by class/configuration, so never hardcode an expectation that every row has it. Wire-protocol behavior (sending `S_CheckSum` back on PATCH, the mismatch error) belongs to **apilogicserver-api-contract**. Takeaway for this skill: `grep S_CheckSum database/models.py` finds nothing, and that is correct — look in `api/expose_api_models.py`.

---

## 3. Key and relationship requirements

### 3.1 Primary keys are mandatory for full function

Per docs (Data-Model-Keys), not live-verified except where noted:

- A table **with** a primary key becomes a class → API endpoint + admin page + rules eligibility.
- A table **without** a primary key becomes a plain `Table(...)` object — per docs this "significantly reduces functionality: no api, no rules, no admin app, etc." Verified concretely in the Northwind sample: the keyless view is generated as
  ```python
  t_ProductDetails_View = Table(
      'ProductDetails_View', metadata,
      Column('Id', Integer), ...
  )
  ```
  and it is invisible to the API because `api/expose_api_models.py` only exposes subclasses of `SAFRSBaseX` (verified: the expose loop tests `issubclass(obj, database.models.SAFRSBaseX)`).
- Generation log symptom, per docs: `Create EmployeeSkills as table, because no Unique Constraint`.
- Rescue for tables that at least have a unique column/constraint/index: the create-time flag. Docs name it `--infer_unique_keys`; the installed 17.03.19 CLI names it `--infer-primary-key / --no-infer-primary-key` ("Infer primary-key for unique cols") — verified 2026-08-23 in `als create --help`; the install wins. With it, the unique column is presumed the primary key and a full class is generated.
- Views: same rule — keyless view ⇒ `Table` object, readable via raw SQLAlchemy but no endpoint. To expose a view, give it an inferable unique column or hand-write a class for it (then treat as a manual edit under change-control).

### 3.2 Foreign keys drive everything multi-table

A foreign key (FK: column(s) constrained to reference a parent's key) is the ONLY thing the generator uses to infer `relationship()` pairs. No FK ⇒ no parent/child accessors ⇒ no multi-table API includes, no admin joins, and no `Rule.sum`/`count`/`copy` across that link.

Verified counter-example in the Northwind sample: `Product.SupplierId = Column(Integer, nullable=False)` is a plain Integer, **not** a `ForeignKey` — and correspondingly class `Supplier` has an empty "child relationships" section. The column exists; the relationship does not.

Fix order of preference:
1. Add the FK in the database, then rebuild (→ **apilogicserver-change-control**).
2. If you cannot alter the schema (legacy DB), declare the relationship in the model yourself — the supported place is `database/customize_models.py` (section 5), which the docs explicitly recommend for missing-FK repair.

### 3.3 Quoted identifiers, case, reserved words

Per docs (Data-Model-Quotes), not live-verified: if the database was created with quoted column names (Oracle-style `"id"`, mixed case, or accented names like `SerieNúmero`), pass `--quote` on `als create` (flag existence verified in 17.03.19 `als create --help`; also available on `als add-db`). ALS aliases accented column names by stripping non-roman8 characters. Reserved-word table names are handled by the alias machinery you saw in 2.5 (`__tablename__ = 'Order'` works; class `Union` maps table `Union` — verified in the sample).

### 3.4 Filtering which tables get generated

Per docs (Data-Model-Filters): `als create --project_name=nw_filtered --db_url=nw --include_tables=nw_filter.yml`, where the YAML holds `include:` / `exclude:` lists of regex patterns; regex has implicit leading/trailing wildcards, so exact-match with `^Region$`. Flag existence verified in 17.03.19 help as `--include-tables TEXT  yml for include, exclude`. Note both spellings work: the installed help prints dash forms (`--db-url`), and underscore forms (`--db_url`) were also accepted in live project creation (verified 2026-08-23).

---

## 4. Designing a NEW schema for API Logic Server (checklist)

Distilled from docs (Data-Model-Design) plus verified generated-file evidence. Use this when the modernization campaign (or any greenfield) lets you choose the schema.

1. **Give every table a single-column Integer surrogate primary key** (`id INTEGER PRIMARY KEY`). Verified: every basic_demo table does this; String/composite PKs work but force `allow_client_generated_ids` and uglier URLs. (Integer-key preference is design guidance, not a documented hard requirement.)
2. **Declare every parent link as a real FOREIGN KEY.** Section 3.2 — no FK, no automation.
3. **Index your foreign keys.** Docs, verbatim: "In general, add indices for your Foreign Keys. Note performance may be fine in dev, but degrade when product data volumes are encountered (e.g., pre-production testing)." Verified generated evidence: Northwind `Order.CustomerId`/`EmployeeId` carry `index=True`.
4. **Add a physical column for every stored aggregate** you will derive with rules: `Customer.balance`, `Order.amount_total`, counts like `OrderCount`. Give them a database default of zero — generated form `server_default=text("0")` (verified in the sample).
5. **Adding an aggregate column to a database that already has data? Initialize it manually** — the rules engine maintains aggregates by *adjustment* (delta updates), so it needs a correct starting value. Docs example, verbatim:
   ```sql
   update Customer set Balance = (select AmountTotal from "Order"
   where Customer.Id = CustomerId and ShippedDate is null);
   ```
6. **Type money as DECIMAL**, dates as DATE — never strings (see the Northwind cautionary columns in 2.6).
7. **Name join/intersection tables** as `ParentChild` (`EmployeeTerritory`) so the generated `<Class>List` accessors read naturally.

**Why stored aggregates are a feature here, not a denormalization sin.** In hand-coded systems a stored `balance` is feared because nothing guarantees it stays consistent with its detail rows. In API Logic Server the rules engine *owns* the column: every insert/update/delete of a watched child adjusts the parent with a one-row update inside the same transaction (verified in live logic logs — adjustments, not `SUM()` re-queries), so the value cannot drift while writes go through the engine, and reads/constraints get O(1) access instead of aggregate queries. The full watch/react/chain and pruning/adjustment theory lives in **declarative-rules-reference**; the schema-side takeaway is: budget a column (with a zero default) for each sum/count/formula result you want persisted, and initialize it when retrofitting (item 5).

---

## 5. Customizing the model — what goes where

Verified 2026-08-23: `database/customize_models.py` exists in freshly created 17.03.19 projects and is imported at server startup by `config/server_setup.py` (`from database import customize_models`) after `database.models` loads and **before** logic activates and endpoints are exposed — so additions are visible to rules, API, and admin.

| Change | Where | Why |
|---|---|---|
| Column type fixes, aliases (`Column('Physical_Name', ...)`), `cascade="all, delete"`, adding a missing `ForeignKey(...)` on the column | `database/models.py` (mark with `# manual fix`) | Must live on the mapped class itself; follow **apilogicserver-change-control** merge discipline on rebuilds |
| Added relationships where no FK exists, virtual/derived attributes, helper methods | `database/customize_models.py` | Survives `models.py` regeneration untouched |
| New tables/columns | The database itself, then rebuild | → **apilogicserver-change-control** |
| Endpoint rename | `_s_collection_name` in `models.py` | Admin app and clients follow |

### 5.1 Add a relationship without a schema FK (verbatim from the sample's customize_models.py)

```python
models.Employee.Manager = relationship('Employee', cascade_backrefs=False, backref='Manages',
                                       primaryjoin=remote(models.Employee.Id) == foreign(models.Employee.ReportsTo))
```

The file's own comment (verbatim): "added relationships appear in your api / swagger, automatically. They must be manually added to your ui/admin/admin.yaml", with the exact YAML stanza to paste (a `direction: tomany`/`toone` entry naming `fks`, `name`, `resource`).

### 5.2 Add a virtual (computed, non-stored) attribute

Same file shows the full pattern: an `add_method(cls)` decorator + `@jsonapi_attr` getter/setter pair defining `ProperSalary` on `Employee` (`Decimal('1.25') * self.Salary`), finished with `models.Employee.ProperSalary = __proper_salary__`. Virtual attributes appear in API responses but have no column; use a rule-derived stored column instead when you need to filter/sort on it in the database (→ **apilogicserver-logic-patterns**).

### 5.3 database_discovery auto-import

`customize_models.py` also calls `discover_models()` from `database/database_discovery/auto_discovery.py` (verified), which walks `database/database_discovery/` and imports every `.py` module (skipping itself and `authentication_models.py`, which the auth path loads separately). This is how add-on model files (e.g., graphics services, additional-database models) join the metadata without editing `models.py`. To add your own model module: drop a file in `database/database_discovery/` — no registration needed.

---

## 6. Multiple databases (binds)

A "bind" is Flask-SQLAlchemy's name for an extra database attached under a key. Verified evidence in every 17.03.19 project (the auth database is itself a bind):

- `database/bind_dbs.py` (verified filename — docs call it `bind_databases.py`; the install wins, 2026-08-23) registers all binds in one call:
  ```python
  flask_app.config.update(SQLALCHEMY_BINDS = {
    'authentication': flask_app.config['SQLALCHEMY_DATABASE_URI_AUTHENTICATION'],
    'landing_page' : flask_app.config['SQLALCHEMY_DATABASE_URI_LANDING']
  })
  ```
  Its docstring warns: all binds must be registered in ONE `update` call, not one per database.
- Per-bind models live in `database/database_discovery/<bind>_models.py` — verified: `authentication_models.py`, where each class carries `__bind_key__ = 'authentication'` and a prefixed collection name `_s_collection_name = 'authentication-Role'` (so endpoints from different databases cannot collide).
- Per-bind URI settings live in `config/config.py` (verified keys: `SQLALCHEMY_DATABASE_URI_AUTHENTICATION`, `SQLALCHEMY_DATABASE_URI_LANDING`); docs mention `conf/config.py` — real path is `config/config.py` (install wins).

### 6.1 Adding a database: als add-db

Flags verified 2026-08-23 from `als add-db --help`:

```
als add-db --db-url=<SQLAlchemy-URL> --bind-key=<KeyName>
# also accepts: --quote, --project-name, --api-name
```

Per docs (Data-Model-Multi), not live-verified here (no add-db was executed in this container): the command generates `<BindKey>_models.py`, wires the bind into config and the bind-registration file, regenerates API exposure, and creates `ui/admin/<BindKey>_admin.yaml`; the new tables then appear in Swagger, and the extra admin app is served under a bind-prefixed URL. Docs do not state that rules can span databases — treat cross-database sums/copies as unsupported until proven (**apilogicserver-research-frontier** for open questions). Within one database, everything in this skill applies per bind.

For `db-url` forms per backend, see **apilogicserver-cli-and-config**.

---

## 7. Test data

Verified 2026-08-23 — `database/test_data/` contents in both live projects: `readme.md`, `alp_init.py`, `test_data_preamble.py`, `response2code.py`.

Two supported seeding styles (from the project's own readme, verified):

1. **Canonical — `alp_init.py`** (Flask context, rules active). Run from project root:
   ```bash
   PROJECT_DIR=$(pwd) python database/test_data/alp_init.py
   ```
   Because LogicBank rules fire on insert, derived columns (sums, formulas) populate themselves — you never hand-compute `balance` in seed data. Edit the `seed_<name>_data(session)` function to change the data.
2. **Alternative — `test_data_preamble.py`** (no Flask). It sets `APILOGICPROJECT_NO_FLASK=1` (which flips models.py to `TestBase`, section 2.2), calls `LogicBank.activate(...)` itself, and — important — writes to a TEST COPY `database/test_data/db.sqlite`, not the live `database/db.sqlite` (verified in the script; the copy does not exist until you run it). Change `db_url` in the script to target the live database deliberately.

Common failures table (condensed from the verified readme):

| Symptom | Cause | Fix |
|---|---|---|
| `ModuleNotFoundError: No module named 'config'` | project root not on `sys.path` | keep the script's `sys.path.insert(0, ...)` first |
| all computed fields are 0 | NO_FLASK set but `LogicBank.activate()` never called | activate after session creation |
| garbled heredoc | shell mangling multi-line SQL | write a `.py` file; never `sqlite3 db << 'SQL'` |

`response2code.py` and `als genai-utils --rebuild-test-data` regenerate test data from WebGenAI `docs/*.response` files — WebGenAI projects only (per the readme; command not executed here). Sample projects arrive pre-seeded: `database/db.sqlite` ships with the demo rows (verified — live probes returned data). The IDE "Rebuild Test Data" procedure and the evidence discipline around golden data belong to **apilogicserver-validation-and-qa**.

---

## 8. Inspecting the real database (drift happens)

`database/db_debug/db_debug.py` is a read-only inspector: it connects using `config.Config.SQLALCHEMY_DATABASE_URI` and prints tables, views, and columns. Run from project root (verified 2026-08-23, ran clean):

```bash
python database/db_debug/db_debug.py
```

Why you care — verified drift example: in a live basic_demo (after the add-cust iteration exercises), `db_debug.py` reported database tables `product_supplier` and `supplier` that do **not** exist in `database/models.py`, and `docs/db.dbml` showed them too. The database had evolved; the model had not been rebuilt. Rules of thumb:

- **What the server actually serves = models.py.** The API and rules see only mapped classes, no matter what the database holds.
- When `db_debug.py` (or `db.dbml`) disagrees with `models.py`, you are mid-schema-change: go to **apilogicserver-change-control** for the rebuild/merge runbook. Do not "fix" it by ad-hoc editing both sides.
- The script imports `oracledb` at top (verified — installed as an ALS dependency, so it runs even for sqlite projects).

---

## 9. Database diagram: docs/db.dbml

Verified: every created project has `docs/db.dbml` — a DBML (Database Markup Language) text rendering of the schema, header verbatim:

```
// Copy this text, paste to https://dbdiagram.io/d
// Or, https://databasediagram.com/app
// Or, view in VSCode with extension: "DBML Live Preview"
```

Tables appear as `Table Customer { id INTEGER [primary key] ... }` with `Ref: Item.(order_id) > Order.(id)` lines for FKs. In the Northwind sample the dbml matched models.py class-for-class (17 tables, keyless view excluded — verified); in basic_demo it reflected the evolved database, not the stale models.py (the drift case in section 8) — so treat db.dbml as a snapshot, and models.py as the model of record.

---

## 10. Per-database notes

| Backend | Facts | Verification |
|---|---|---|
| SQLite | Project DB is the file `database/db.sqlite`; auth DB `database/authentication_db.sqlite`; URL form `sqlite:///.../database/db.sqlite` (from generated headers). SQLite does not enforce cascade delete by default — add `cascade="all, delete"` on child accessors (section 2.5); docs flag this as the SQLite special consideration. Sample shortcuts (`--db-url=nw`, `nw+`, `basic_demo`, `auth`, `allocation`, `BudgetApp`) create sqlite projects — full catalog in **apilogicserver-cli-and-config** | file locations + URL form verified; cascade note per docs |
| PostgreSQL | URL `--db_url=postgresql://postgres:p@localhost/northwind`; driver psycopg2. SERIAL keys generate `server_default=text("nextval('...__seq'::regclass)")`; after bulk-loading data reset sequences: `SELECT setval('employees_employee_id_seq', (SELECT MAX(employee_id) FROM employees));` | per docs, not live-verified — EXCEPT: `config/config.py` auto-rewrites `postgresql://` → `postgresql+psycopg://` on Python ≥ 3.13 (verified in generated config, 2026-08-23) |
| MySQL / SQL Server / Oracle | Supported via standard SQLAlchemy URLs; Oracle commonly needs `--quote` (docs example: `als create --project_name=oracle_stress --quote --db_url='oracle+oracledb://...'`). Driver installs → **apilogicserver-build-and-env**; URL forms → **apilogicserver-cli-and-config** | per docs, not live-verified |

---

## 11. Changing the schema

One procedure, one home: alter the database (or model), then rebuild and merge per **apilogicserver-change-control** (`als rebuild-from-database` / `als rebuild-from-model` exist in the 17.03.19 command list — verified; the runbook, admin-merge files, and what-may-be-edited gates live in that skill). Any model edit that changes behavior ends at that skill's gates before it ships.

---

## Provenance and maintenance

Volatile facts and how to re-verify each (run from any project root unless noted):

- Package/version and command list: `als welcome` and `als --help`
- `models.py` base-class switch and header: `head -50 database/models.py`
- Accessor naming as served: login, then `curl -s http://localhost:5656/api/Order/?page%5Blimit%5D=1 -H "Authorization: Bearer $TOKEN"` and read `relationships` keys
- S_CheckSum attach point (not in models): `grep -n S_CheckSum database/models.py api/expose_api_models.py`
- Opt-locking default: `grep -n OPT_LOCKING config/config.py`
- `add-db` flags: `als add-db --help`
- `create` model-shaping flags: `als create --help | grep -E "quote|include-tables|infer-primary-key"`
- Keyless-table handling in the sample: `grep -n "t_ProductDetails_View" database/models.py` (Northwind project)
- Missing-FK counter-example: `grep -n "SupplierId" database/models.py` (Northwind project)
- customize_models load order: `grep -n "customize_models" config/server_setup.py`
- Bind registration and per-bind models: `cat database/bind_dbs.py; grep -rn __bind_key__ database/database_discovery/`
- Test-data conventions: `cat database/test_data/readme.md`
- Schema vs model drift: `python database/db_debug/db_debug.py` and diff its table list against `grep "__tablename__" database/models.py`
- Diagram file: `head -5 docs/db.dbml`

Grounded in: https://apilogicserver.github.io/Docs/Data-Model-Classes/, https://apilogicserver.github.io/Docs/Data-Model-Keys/, https://apilogicserver.github.io/Docs/Data-Model-Customization/, https://apilogicserver.github.io/Docs/Data-Model-Design/, https://apilogicserver.github.io/Docs/Data-Model-Multi/, https://apilogicserver.github.io/Docs/Data-Model-Examples/, https://apilogicserver.github.io/Docs/Data-Model-Filters/, https://apilogicserver.github.io/Docs/Data-Model-Quotes/, https://apilogicserver.github.io/Docs/Data-Model-Sqlite/, https://apilogicserver.github.io/Docs/Data-Model-Postgresql/, https://apilogicserver.github.io/Docs/Database-Diagram/ and a live Genai-Logic 17.03.19 install (2026-08-23) — generated projects (basic_demo, Northwind sample) read on disk and probed over a running server.
