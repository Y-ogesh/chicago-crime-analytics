# PostgreSQL Database Setup and Raw Import

## Scope and outcome

Milestone 2 created a reproducible PostgreSQL raw-data layer for the acquired City of Chicago crime extract. The workflow preserves source rows in staging, converts all rows to documented PostgreSQL types in one transaction, and aborts instead of silently discarding malformed or mismatched values.

The executed database import used PostgreSQL 14.20 and completed successfully on September 25, 2026. No cleaning, category standardization, domain filtering, geographic correction, analytical transformation, or aggregation was performed.

## Prerequisites

- PostgreSQL server and `psql` client
- Python 3 for the loader orchestration and local evidence file
- Acquired raw CSV and metadata manifest under `data/raw/`
- A PostgreSQL role permitted to create tables in the target database

Connection settings come from standard `PG*` environment variables or the corresponding `POSTGRES_*` variables in a local `.env` file. The loader never embeds credentials or machine-specific paths.

```bash
cp .env.example .env
```

Leave `POSTGRES_HOST` and `POSTGRES_USER` blank to use local socket and operating-system user defaults, or provide appropriate values for a configured TCP/remote server. Keep `.env` out of Git.

## Database creation

Create the database once with an authorized PostgreSQL role:

```bash
export PGDATABASE=chicago_crime
createdb "$PGDATABASE"
```

The database itself is not created by version-controlled SQL because database creation requires cluster-level privileges that vary by environment. The tables are created by [the schema SQL](../sql/01_schema.sql).

## Tables and preservation strategy

### `raw_chicago_crimes_staging`

The staging table contains all 22 source fields as `text` plus a generated `source_row_number` that records import order. PostgreSQL parses the source CSV directly through client-side `\copy`, including quoted commas and embedded line breaks. Unavailable unquoted CSV fields follow PostgreSQL CSV semantics and become SQL `NULL`; the immutable CSV remains the byte-level source of truth.

### `raw_chicago_crimes`

| Column | PostgreSQL type | Nullable |
|---|---|---|
| `id` | `bigint` primary key | No |
| `case_number` | `text` | No |
| `date` | `timestamp(3) without time zone` | No |
| `block` | `text` | No |
| `iucr` | `text` | No |
| `primary_type` | `text` | No |
| `description` | `text` | No |
| `location_description` | `text` | Yes |
| `arrest` | `boolean` | No |
| `domestic` | `boolean` | No |
| `beat` | `text` | No |
| `district` | `text` | No |
| `ward` | `smallint` | Yes |
| `community_area` | `smallint` | Yes |
| `fbi_code` | `text` | No |
| `x_coordinate` | `integer` | Yes |
| `y_coordinate` | `integer` | Yes |
| `year` | `smallint` | No |
| `updated_on` | `timestamp(3) without time zone` | No |
| `latitude` | `numeric(12,9)` | Yes |
| `longitude` | `numeric(12,9)` | Yes |
| `location` | `text` | Yes |

Actual source profiling showed integer-form IDs and administrative/geographic codes, millisecond timestamps without offsets, exact boolean strings, integer projected coordinates, and coordinates with up to nine decimal places. Code-like values that can contain leading zeros remain `text`. No uniqueness constraint is applied to `case_number`; 64 case-number values repeat in the acquired file, with a maximum observed multiplicity of four.

### `raw_chicago_crimes_load_audit`

Each successful rebuild records the source filename and checksum, expected and actual counts, distinct source-ID count, date bounds, yearly counts, and load timestamp. Failed transactions create no audit row.

## Reproducible loading procedure

From the repository root, with the target database available:

```bash
python3 scripts/load_raw_postgres.py
```

An explicit database can be selected without changing code:

```bash
python3 scripts/load_raw_postgres.py --database chicago_crime
```

The loader performs these steps:

1. Verifies the raw CSV SHA-256 against the acquisition manifest.
2. Verifies the exact 22-column CSV header.
3. Applies `sql/01_schema.sql` idempotently.
4. Starts one transaction and obtains a project-specific advisory lock.
5. Truncates and rebuilds staging and typed raw tables.
6. Loads the CSV with client-side `\copy`.
7. Checks staging count, missing IDs, and distinct IDs before conversion.
8. Casts every staging row into `raw_chicago_crimes`; any invalid value aborts the transaction.
9. Reconciles every typed field against staging for every row. Coordinates use exact numeric equivalence because `numeric(12,9)` can display additional trailing zeros.
10. Writes the load audit and commits only after all checks pass.
11. Generates `data/processed/raw_import_validation.json`, which is local and Git-ignored.

The rebuild is idempotent with respect to staging and typed table contents. A failed rebuild rolls back the truncation and leaves the prior committed state intact. Successful reruns add audit history.

## Executed validation evidence

The final measured rebuild produced load audit ID 3 at `2026-09-25T19:39:53Z`. The database schema/load/post-load-validation portion completed in 12.384 seconds.

| Validation | Result |
|---|---:|
| Acquisition-manifest expected rows | 761,563 |
| Staging rows | 761,563 |
| Imported `raw_chicago_crimes` rows | 761,563 |
| Distinct source IDs | 761,563 |
| Duplicate source IDs | 0 |
| Minimum incident timestamp | `2023-01-01T00:00:00.000` |
| Maximum incident timestamp | `2025-12-31T23:58:00.000` |
| Source SHA-256 matched | Yes |
| Full-row staging-to-typed reconciliation | 0 mismatched rows |

### Records by year

| Year | Imported records |
|---:|---:|
| 2023 | 263,844 |
| 2024 | 259,633 |
| 2025 | 238,086 |
| **Total** | **761,563** |

### Important-column completeness

| Column | SQL `NULL` records |
|---|---:|
| `location_description` | 3,947 |
| `ward` | 4 |
| `community_area` | 35 |
| `x_coordinate` | 6,697 |
| `y_coordinate` | 6,697 |
| `latitude` | 6,697 |
| `longitude` | 6,697 |
| `location` | 6,697 |

These results match the acquisition-level empty-field counts. Missing-coordinate records remain in both staging and `raw_chicago_crimes`.

### Representative records

Three database records were compared directly with the source CSV across identifier, case number, timestamp, year, community area, coordinates, and location: source ID `27279` with coordinates and embedded location line breaks, source ID `12940082` with missing coordinates and source community area `0`, and maximum source ID `14337128`. All 21 representative field comparisons matched. The loader additionally reconciled all 22 fields for every imported row.

### Idempotency and discrepancy investigation

Three successful rebuilds produced the same staging count, imported count, distinct-ID count, date bounds, yearly totals, completeness counts, and representative records. The load-audit table contains three successful records and the final table state contains one copy of each source ID.

Two discrepancies were found during implementation and resolved before completion:

1. The initial schema treated `location` and `location_description` as non-null, but the source contains unavailable values. The transaction failed and rolled back with zero staging, raw, or audit rows. Both columns were corrected to nullable.
2. The first full reconciliation compared coordinate display strings. PostgreSQL `numeric(12,9)` padded trailing zeros for 142,759 rows while retaining the exact numeric values. That transaction also rolled back. Reconciliation now compares exact numeric values, while staging retains the source string representation.

No unexplained discrepancy remains.

## Manual validation

Run the version-controlled validation report at any time:

```bash
psql --dbname "${PGDATABASE:-chicago_crime}" --file sql/02_validate_raw.sql
```

The report returns the latest audit, independent table totals, distinct IDs, date bounds, yearly counts, completeness counts, and representative records.

## Limitations

- Typed conversion is not analytical cleaning; source values such as ward or community area `0` remain present.
- The immutable CSV, not PostgreSQL display formatting, is the byte-exact source artifact.
- `timestamp without time zone` preserves the source timestamp because the dataset provides no timezone offset; it does not assert UTC.
- Geographic presence does not establish coordinate validity or correct boundary assignment.
- The database is a local reproducible build artifact and is not committed to Git.
