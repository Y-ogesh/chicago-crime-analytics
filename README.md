# Chicago Crime Analytics

An end-to-end data analytics and business intelligence portfolio project built from official City of Chicago reported-crime data. The project will use reproducible PostgreSQL, SQL, and Python workflows to examine temporal, geographic, seasonal, crime-category, domestic-incident, and arrest patterns across at least 500,000 records. A four-page Tableau dashboard and evidence-backed resource-planning recommendations are planned deliverables; they have not yet been built.

## Project objective

The objective is to produce an auditable analysis of reported crime patterns in Chicago while keeping metric definitions consistent across SQL, Python, Tableau, and project documentation. The project will calculate verified citywide and eligible community-area year-over-year changes using complete calendar years, distinguish incident counts from population-normalized rates, and avoid causal claims from observational data.

## Official dataset source

The planned primary source is the City of Chicago Data Portal's [Crimes - 2001 to Present](https://data.cityofchicago.org/Public-Safety/Crimes-2001-to-Present/ijzp-q8t2/data) dataset (dataset identifier `ijzp-q8t2`), provided by the Chicago Police Department. The portal describes rows as reported crimes, except that murder records represent victims, and notes that recent records and classifications can change. No data has been downloaded for this project yet.

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
PostgreSQL staging -> validation/cleaning -> analytical tables/views
        |                                      |
        v                                      v
Python QA and EDA                         Tableau extracts/dashboard
        |                                      |
        +------------------+-------------------+
                           v
              documented findings and metrics
```

The architecture is planned beyond the repository-foundation layer. Only the folder structure and foundational documentation exist at Milestone 0.

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
| 0 | Repository foundation and analytical definitions | Complete (2026-09-25) |
| 1 | Source acquisition and raw-data integrity | Planned |
| 2 | PostgreSQL schema and reproducible load | Planned |
| 3 | Data quality, cleaning, and analytical layer | Planned |
| 4 | SQL analysis and verified year-over-year metrics | Planned |
| 5 | Python exploratory analysis and static visuals | Planned |
| 6 | Four-page interactive Tableau dashboard | Planned |
| 7 | Findings and resource-planning recommendations | Planned |
| 8 | Final QA, portfolio packaging, and resume metrics | Planned |

Detailed gates and acceptance criteria are in the [project plan](docs/project_plan.md). Metric formulas and comparison rules are in [metric definitions](docs/metric_definitions.md), and source fields are described in the initial [data dictionary](docs/data_dictionary.md).

## Reproducibility overview

The planned workflow will use environment variables copied from `.env.example`, scripts and version-controlled SQL instead of manual transformations, immutable raw inputs, documented extraction metadata, and validation checks at each milestone. Paths in project code and documentation will be repository-relative. Credentials, raw CSV files, database dumps, Tableau extracts, and other large generated exports are excluded from Git.

Dependency declarations are provided in `requirements.txt`; installation and runtime compatibility have not yet been validated. Exact setup, acquisition, database, and execution commands will be added only when their corresponding milestones are implemented and tested.

## Current status

Milestone 0 was completed on September 25, 2026. The required repository scaffold, documentation links, and representative ignore rules were validated successfully. No crime data has been acquired or analyzed, no PostgreSQL objects have been created, and no Tableau workbook or analytical findings have been produced. Dependency installation and runtime compatibility remain unvalidated and belong to later authorized work.
