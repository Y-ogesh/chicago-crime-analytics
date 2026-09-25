# Project Plan

## Purpose and governance

This plan defines the gated delivery of the Chicago Crime Analytics portfolio project. Work proceeds one milestone at a time and requires explicit authorization before the next milestone begins. Every milestone must inspect existing repository and database state, implement only authorized scope, execute relevant validation, correct discovered errors, update documentation with actual results, and report changes and limitations without committing.

Rules that apply throughout:

- Preserve downloaded source files unchanged and keep them out of Git.
- Use repository-relative paths and environment variables; never commit credentials.
- Keep metric definitions synchronized across SQL, Python, Tableau, and documentation.
- Use complete calendar years for annual comparisons and label partial periods explicitly.
- Keep incident counts distinct from population-normalized rates.
- Describe the `arrest` field as an arrest indicator and never as clearance or conviction.
- Retain non-coordinate records for applicable analysis and report coordinate coverage separately.
- Treat reported-crime and geographic limitations explicitly and avoid causal inference.
- Record evidence for counts, percentages, checks, and portfolio or resume claims.

## Milestone 0 — Repository foundation

### Scope

Create the repository scaffold, environment template, dependency declaration, ignore rules, project roadmap, metric definitions, initial data dictionary, and a README that clearly separates completed work from planned work.

### Acceptance criteria

- Required root files and directories exist with placeholders where needed.
- Raw CSVs, credentials, environments, notebook checkpoints, temporary files, database dumps, Tableau extracts, and large exports are ignored.
- README documents the source, objectives, questions, architecture, structure, roadmap, reproducibility approach, and honest current status.
- Metric definitions state exact numerators, denominators, eligibility rules, null handling, and full-year/partial-year policy.
- Initial data dictionary maps the official source fields without claiming that data was acquired.
- All repository-relative documentation links resolve.
- No dataset is downloaded, no database object is created, and no analysis is performed.

### Completion record (2026-09-25)

Milestone 0 is complete. The required root files, eight required directories, and seven `.gitkeep` placeholders were created. A read-only validation checked 22 required paths, three repository-relative documentation links, six representative ignored artifacts, and seven unignored placeholders with zero errors. A separate scan found no raw or processed tabular data files. No dataset was acquired, no SQL was executed, and no analytical result was produced. PostgreSQL did not respond at `localhost:5432`; a database connection was not required for this repository-foundation milestone.

## Milestone 1 — Source acquisition and raw-data integrity

### Scope

Implement a reproducible, parameterized extraction from the official City of Chicago dataset; save immutable raw input and extraction metadata locally; and profile the source without transforming it.

### Acceptance criteria

- Authorized extraction covers at least 500,000 records and records dataset ID, query/filter, extraction timestamp, source update timestamp when available, row count, file size, and checksum.
- Extraction uses a repeatable script with pagination or another documented complete-export method.
- Raw data remains byte-for-byte unchanged after acquisition and excluded from Git.
- Source columns and types are reconciled with the data dictionary.
- Duplicate identifiers, nulls, date range, and basic domain values are profiled with saved, reproducible evidence.
- Partial and complete calendar-year availability is documented without presenting analytical findings.

### Completion record (2026-09-25)

Milestone 1 is complete. The reproducible downloader selected the three adjacent complete calendar years 2023–2025 and used the half-open source filter `date >= '2023-01-01T00:00:00.000' AND date < '2026-01-01T00:00:00.000'`. It downloaded 761,563 untransformed source rows in 16 keyset-paginated API requests ordered by `id ASC`. The pre-download source count, downloaded count, post-download source count, and unique source-ID count all equaled 761,563; no duplicate IDs were found. The raw CSV is 219,747,521 bytes with SHA-256 `8b74425af7936af7b88226664b1b1cafe6c8805fe95ff1ca6ac4d75d364c4757` and remains excluded from Git. Source schema, empty-field counts, extraction timestamps, geographic-field presence, limitations, and commands are recorded in [dataset acquisition](dataset_acquisition.md) and [the data dictionary](data_dictionary.md). No database import, cleaning, or crime-pattern analysis was performed.

## Milestone 2 — PostgreSQL schema and reproducible load

### Scope

Create version-controlled PostgreSQL DDL and load workflows for raw staging and typed crime records.

### Acceptance criteria

- Environment-based connection configuration works without committed secrets.
- Schemas, tables, keys, data types, constraints, and indexes are documented and reproducible from SQL/scripts.
- Load is restartable or idempotent and does not modify the raw source file.
- Source, staging, and typed-table row counts reconcile or every difference is explained.
- Unique record identifiers, parsing behavior, rejected rows, and load duration are validated and reported.
- No analytical conclusion is claimed from load validation alone.

### Completion record (2026-09-25)

Milestone 2 is complete. PostgreSQL 14.20 was configured with a local `chicago_crime` database and three version-controlled tables: text-preserving staging, typed `raw_chicago_crimes`, and load audit. The loader verified the raw SHA-256 and header, loaded 761,563 staging rows, cast all rows transactionally, and reconciled every source field to its typed representation. Expected, staging, imported, and distinct-ID counts all equaled 761,563; date bounds and yearly counts matched the acquisition manifest. The final measured schema/load/validation workflow completed in 12.384 seconds. Repeated successful rebuilds produced identical table totals, proving idempotent table contents. Two implementation discrepancies—source-null location fields and coordinate display-scale normalization—were investigated; both failed attempts rolled back with zero partial rows before the schema and validation rules were corrected. No cleaning, analytical transformation, or finding was produced. Full commands, types, checks, and evidence are recorded in [database setup](database_setup.md).

## Milestone 3 — Data quality, cleaning, and analytical layer

### Scope

Implement documented quality rules and reusable analytical tables or views while preserving source values and lineage.

### Acceptance criteria

- Cleaning rules for identifiers, timestamps, categorical values, booleans, community areas, and coordinates are explicit and tested.
- Source columns remain available or traceable; transformations never silently overwrite raw values.
- Missing coordinates are flagged separately from records retained for non-map analysis.
- Valid community areas are separated from missing or invalid values using the documented eligibility rule.
- Complete-year and partial-period flags are reproducibly derived using a recorded data cutoff.
- SQL and Python quality checks reconcile record counts and key distributions.

## Milestone 4 — SQL analysis and verified year-over-year metrics

### Scope

Create reproducible SQL for temporal, geographic, seasonal, category, domestic, arrest, and year-over-year analyses.

### Acceptance criteria

- Citywide year-over-year changes use adjacent complete calendar years and the approved formula.
- Community-area year-over-year changes cover every eligible community area and document exclusions and zero denominators.
- Temporal, category, domestic, arrest-indicator, and geographic outputs use the shared definitions.
- Incident counts are never labeled rates; arrest percentages are never described as clearance or conviction rates.
- Independent reconciliation queries verify totals, denominators, year coverage, and ranking outputs.
- Results and caveats are recorded only from executed queries.

## Milestone 5 — Python exploratory analysis and static visuals

### Scope

Implement reproducible Python analysis that validates SQL outputs and produces portfolio-quality exploratory charts.

### Acceptance criteria

- Scripts or notebooks run from repository-relative paths with documented commands.
- Pandas results reconcile with selected PostgreSQL totals and percentages within documented tolerances.
- Visuals have accurate titles, units, date coverage, source attribution, and accessible labeling.
- Partial periods, missing geography, and category grouping are visibly or textually disclosed.
- Generated images are reproducible; large intermediate exports remain ignored.
- Observed associations are not framed as causal effects.

## Milestone 6 — Four-page interactive Tableau dashboard

### Scope

Build and document a four-page Tableau dashboard using validated analytical data.

### Acceptance criteria

- Four pages cover executive overview, temporal/seasonal patterns, geographic/community-area patterns, and category/arrest/domestic patterns.
- Filters, tooltips, legends, navigation, and interaction behavior are documented and manually tested in Tableau.
- KPI values reconcile with validated SQL/Python outputs for defined test cases.
- Full-year and partial-year labels, counts versus percentages, data cutoff, and limitations are visible.
- Missing-coordinate records are excluded only from coordinate maps and are disclosed through coverage metrics.
- Dashboard completion is claimed only after the workbook is opened and tested in Tableau; screenshots reflect actual functionality.

## Milestone 7 — Findings and resource-planning recommendations

### Scope

Synthesize verified evidence into findings and cautious resource-planning recommendations.

### Acceptance criteria

- Every numeric statement traces to a saved SQL query or reproducible Python output.
- Recommendations identify the relevant place, time, or category pattern, the supporting evidence, and important uncertainty.
- Recommendations are operational hypotheses, not causal or predictive claims beyond the analysis.
- Reported-crime undercoverage, record revisions, approximate geography, missing data, and population-rate limitations are explicit.
- Citywide and community-area statements use the correct comparison eligibility rules.
- README and technical reports agree on findings, definitions, and date coverage.

## Milestone 8 — Final QA, portfolio packaging, and resume metrics

### Scope

Audit the full repository, finalize reproducibility instructions, package portfolio artifacts, and derive interview-defensible resume metrics.

### Acceptance criteria

- A clean-environment reproduction test is executed where available, with commands and actual outcomes recorded.
- SQL, Python, Tableau, and documentation metrics reconcile for a defined validation sample.
- Git contains no credentials, raw datasets, database dumps, oversized exports, or machine-specific paths.
- README accurately distinguishes implemented functionality from limitations and optional future work.
- Dashboard evidence and final reports correspond to the tested workbook and data cutoff.
- Each resume metric has a documented calculation, source artifact, date coverage, and validation evidence.
- Final file/link checks pass and no unexecuted validation is represented as successful.
