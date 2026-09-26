# Chicago Crime Analytics

An end-to-end data analytics and business intelligence portfolio project built from official City of Chicago reported-crime data. The project uses reproducible acquisition workflows and will use PostgreSQL, SQL, and Python to examine temporal, geographic, seasonal, crime-category, domestic-incident, and arrest patterns. The acquired source extract contains 761,563 records across the three complete calendar years 2023–2025. A four-page Tableau dashboard and evidence-backed resource-planning recommendations are planned deliverables; they have not yet been built.

## Project objective

The objective is to produce an auditable analysis of reported crime patterns in Chicago while keeping metric definitions consistent across SQL, Python, Tableau, and project documentation. The project will calculate verified citywide and eligible community-area year-over-year changes using complete calendar years, distinguish incident counts from population-normalized rates, and avoid causal claims from observational data.

## Official dataset source

The primary source is the City of Chicago Data Portal's [Crimes - 2001 to Present](https://data.cityofchicago.org/Public-Safety/Crimes-2001-to-Present/ijzp-q8t2/data) dataset (dataset identifier `ijzp-q8t2`), provided by the Chicago Police Department. The portal describes rows as reported crimes, except that murder records represent victims, and notes that records and classifications can change. On September 25, 2026, the project acquired source records with incident timestamps from January 1, 2023 through December 31, 2025. Partial-year 2026 records were excluded.

The eventual analysis must acknowledge that reported-crime data does not measure all crime, locations are approximate, coordinate and community-area fields may be missing, and administrative practices or later record updates may affect comparisons. Findings will describe associations and observed patterns, not causation.

## Technology stack

- PostgreSQL and SQL for storage, validation, transformation, and analytical queries
- Python, Pandas, and NumPy for reproducible analysis
- Matplotlib for static exploratory visualizations
- Tableau for the planned four-page interactive dashboard
- Git and GitHub for version control and portfolio delivery

## Analytical questions

The project is designed to answer:

1. How do reported incident counts change by year, month, season, day of week, and hour?
2. Which crime categories account for the largest counts and changes over time?
3. How are reported incidents distributed across Chicago community areas and coordinate-mappable locations?
4. Which eligible community areas show the largest verified full-year year-over-year changes?
5. What percentages of reported incidents are marked as arrest-related or domestic-related, and how do those percentages vary?
6. What operationally relevant patterns could inform resource-planning hypotheses without implying causation?

Population-normalized crime rates are outside the initial scope until an authoritative, year-aligned population source and rate methodology are added and documented. Counts must never be labeled as rates.

## Project architecture

```text
Official City source
        |
        v
data/raw (immutable, local, Git-ignored)
        |
        v
PostgreSQL staging -> data-quality assessment -> validated record-level clean table
        |                                      |
        v                                      v
Python QA and EDA                         Tableau extracts/dashboard
        |                                      |
        +------------------+-------------------+
                           v
              documented findings and metrics
```

The repository foundation, raw-data acquisition, PostgreSQL raw import, read-only data-quality assessment, record-level cleaning/feature engineering, and core SQL analysis are complete. Python analysis, visualization, and Tableau work remain planned.

## Repository structure

```text
.
├── README.md
├── .env.example
├── .gitignore
├── requirements.txt
├── data/
│   ├── raw/             # Immutable source files; contents ignored by Git
│   └── processed/       # Reproducible derived files; large exports ignored
├── docs/                # Plans, definitions, dictionary, and reports
├── images/              # Versionable documentation images
├── notebooks/           # Reproducible analysis notebooks
├── scripts/             # Acquisition, loading, validation, and analysis code
├── sql/                 # DDL, validation, transformation, and analysis SQL
└── tableau/             # Tableau workbook instructions and small artifacts
```

Empty working directories are retained with `.gitkeep` placeholders. Raw and generated data remain local and are not committed.

## Milestone roadmap

| Milestone | Scope | Status |
|---|---|---|
| 0 | Repository foundation and analytical definitions | Complete |
| 1 | Source acquisition and raw-data integrity | Complete |
| 2 | PostgreSQL schema and reproducible load | Complete |
| 3 | Read-only data-quality assessment and proposed treatments | Complete |
| 4 | Data cleaning and feature engineering | Complete |
| 5 | Core SQL analysis and verified year-over-year metrics | Complete |
| 6 | Python exploratory analysis and static visuals | Planned |
| 7 | Four-page interactive Tableau dashboard | Planned |
| 8 | Findings and resource-planning recommendations | Planned |
| 9 | Final QA, portfolio packaging, and resume metrics | Planned |

Detailed gates and acceptance criteria are in the [project plan](docs/project_plan.md). The executed extraction evidence is in [dataset acquisition](docs/dataset_acquisition.md), the PostgreSQL workflow and import validation are in [database setup](docs/database_setup.md), observed quality issues are in the [data-quality report](docs/data_quality_report.md), implemented record-level transformations are in the [cleaning report](docs/cleaning_report.md), and verified descriptive SQL findings are in the [core SQL analysis report](docs/sql_analysis_report.md). Metric formulas and comparison rules are in [metric definitions](docs/metric_definitions.md), and raw and clean fields are described in the [data dictionary](docs/data_dictionary.md).

## Reproducibility overview

The workflow uses environment variables copied from `.env.example`, scripts and version-controlled SQL instead of manual transformations, immutable raw inputs, documented extraction metadata, and validation checks at each milestone. Paths in project code and documentation are repository-relative. Credentials, raw CSV files, database dumps, Tableau extracts, and other large generated exports are excluded from Git.

The acquisition is reproducible from a clean checkout after installing `requirements.txt`:

```bash
python3 scripts/download_crimes.py
```

The script applies the documented date filter, downloads 50,000-row pages using source-ID keyset pagination, orders records by `id ASC`, retries transient API failures, refuses to overwrite existing raw artifacts, and validates source counts before and after download. It writes an immutable Git-ignored CSV and JSON evidence manifest under `data/raw/`. See [dataset acquisition](docs/dataset_acquisition.md) for exact commands, filters, outputs, and limitations. The full dependency set has not yet been tested in a clean virtual environment.

After creating a PostgreSQL database and configuring connection variables, the raw import is reproducible with:

```bash
python3 scripts/load_raw_postgres.py
```

The loader verifies the raw-file checksum and header, preserves parsed source fields in a text staging table, transactionally rebuilds the typed `raw_chicago_crimes` table, reconciles every row and field, and records a load audit. It rolls back the entire rebuild on any count, ID, cast, or reconciliation error. See [database setup](docs/database_setup.md) for database creation, schema, commands, and executed validation evidence.

The raw table can be profiled without modifying it by running:

```bash
psql -d chicago_crime -X -v ON_ERROR_STOP=1 -P pager=off \
  -f sql/02_data_quality.sql
```

The quality script runs inside a read-only transaction and reports duplicate identifiers, case-number repetition, date consistency, categorical quality, administrative-geography domains, coordinate coverage and plausibility, boolean distributions, field completeness, yearly coverage, and category cardinality. The subsequent clean-table implementation is documented separately below.

The clean table can be rebuilt and validated with:

```bash
psql -d chicago_crime -X -v ON_ERROR_STOP=1 \
  -f sql/03_data_cleaning.sql
```

The script transactionally recreates `clean_chicago_crimes` while leaving `raw_chicago_crimes` unchanged. It preserves source identifiers and crime categories, applies deterministic source-ID deduplication, validates administrative and coordinate geography, derives calendar/time features, creates targeted indexes, and aborts on row-lineage or feature-definition failures. Missing-coordinate incidents remain in the clean table for non-map analysis.

The 29-query core SQL analysis can be reproduced with:

```bash
psql -d chicago_crime -X -v ON_ERROR_STOP=1 \
  -f sql/04_business_analysis.sql
```

Each query documents its business question, metric, assumptions, and denominator. The suite covers dataset coverage, complete-year changes, categories and descriptions, month/day/hour/time-band patterns, weekday versus weekend, community areas, police districts, location descriptions, arrest and domestic indicators, seasonal patterns, and cross-query reconciliation. It executes inside a read-only transaction.

## Current status

Milestone 5 was completed on September 25, 2026. All 29 read-only business queries executed successfully against 761,563 clean records, including 154 adjacent-year comparisons covering all 77 eligible community areas with zero undefined prior-year denominators. Every year/category/month/weekday/hour/time-band/district/location/season reconciliation returned zero difference from the canonical total. Verified citywide reported incident counts were 263,844 in 2023, 259,633 in 2024, and 238,086 in 2025, corresponding to adjacent-year changes of -1.5960% and -8.2990%. Theft was the largest source primary type (173,282; 22.7535%); July had the largest pooled calendar-month count; Afternoon was the largest six-hour time band; and Summer was the largest meteorological-season count. Geographic tables report counts—not population-normalized rates—and retain separate coverage denominators. Arrest results are explicitly labeled arrest percentages, not clearance or conviction rates. No Python analysis, Tableau workbook, causal conclusion, resource-planning recommendation, or resume metric has been produced.
