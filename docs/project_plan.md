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

### Status: Complete

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

### Status: Complete

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

### Status: Complete

Milestone 2 is complete. PostgreSQL 14.20 was configured with a local `chicago_crime` database and three version-controlled tables: text-preserving staging, typed `raw_chicago_crimes`, and load audit. The loader verified the raw SHA-256 and header, loaded 761,563 staging rows, cast all rows transactionally, and reconciled every source field to its typed representation. Expected, staging, imported, and distinct-ID counts all equaled 761,563; date bounds and yearly counts matched the acquisition manifest. The final measured schema/load/validation workflow completed in 12.384 seconds. Repeated successful rebuilds produced identical table totals, proving idempotent table contents. Two implementation discrepancies—source-null location fields and coordinate display-scale normalization—were investigated; both failed attempts rolled back with zero partial rows before the schema and validation rules were corrected. No cleaning, analytical transformation, or finding was produced. Full commands, types, checks, and evidence are recorded in [database setup](database_setup.md).

## Milestone 3 — Data quality assessment

### Scope

Profile the imported raw table without modifying it, quantify material data-quality issues, and document proposed treatments for a future cleaned layer.

### Acceptance criteria

- A reusable SQL suite profiles identifiers, case numbers, dates, categories, location descriptions, administrative geography, coordinates, arrest/domestic indicators, nulls, yearly totals, and category cardinality.
- Every material issue includes an affected-row count, percentage, analytical impact, proposed treatment, retention decision, and validation query.
- Repeated case numbers are assessed separately from duplicate source IDs and are not automatically treated as duplicate incidents.
- Missing coordinates are separated from incidents retained for non-map analysis; coordinate coverage is quantified.
- Valid community areas are separated from missing or out-of-range values using the documented 1–77 eligibility rule.
- Every quality query executes successfully inside a read-only transaction, and source values remain unchanged.
- README, project plan, data dictionary, and quality report agree on the executed results and explicitly identify cleaning as future work.

### Status: Complete

Milestone 3 is complete as a read-only assessment. All queries in `sql/02_data_quality.sql` executed successfully against 761,563 raw records inside a PostgreSQL read-only transaction. Source IDs were unique; source/typed dates, year consistency, primary crime type, tested categorical whitespace, and arrest/domestic completeness had no observed defects. The assessment found 64 repeated case-number values affecting 138 rows, including 17 repeated substantive homicide fingerprints affecting 34 source-ID-distinct rows; no automatic deduplication is proposed. It also quantified 6,697 records without coordinate pairs (0.8794%), 3,947 without location descriptions (0.5183%), 35 missing and 1,032 out-of-range community areas, four missing and 1,032 out-of-range wards, one non-padded district code, and 1,020 records using district `061`, which is absent from the current official district reference. All records were retained and the raw layer was not modified. Proposed treatments and limitations are recorded in [data quality assessment](data_quality_report.md); no cleaning or analytical layer was implemented.

## Milestone 4 — Data cleaning and feature engineering

### Scope

Build a reproducible, record-level clean table from the validated raw table without changing the raw layer; preserve source lineage; implement only evidence-backed treatments; and derive constrained temporal and geographic eligibility features.

### Acceptance criteria

- `clean_chicago_crimes` is reproducibly rebuilt from `raw_chicago_crimes` inside a transaction without modifying raw records.
- Deterministic source-ID deduplication is explicit; repeated case numbers do not trigger row removal.
- Original source identifiers, source crime categories, and relevant invalid source values remain traceable in separate columns.
- Blank normalization, text standardization, invalid-domain handling, and coordinate validation follow the completed quality assessment.
- Non-geocoded incidents remain available for every analysis that does not require coordinates.
- Calendar date/year/month/quarter, month/day labels, ISO weekday number, hour, time-of-day, season, and weekend features use documented exact definitions and database constraints.
- Raw and clean row counts, IDs, date coverage, feature completeness/ranges, geography eligibility, category cardinality, and source lineage reconcile with no unexplained loss.
- Indexes support documented temporal, crime-category, and eligible-community-area access patterns.
- README, project plan, data dictionary, metric definitions, and cleaning report agree with the executed implementation.

### Status: Complete

Milestone 4 is complete. `sql/03_data_cleaning.sql` transactionally rebuilt and validated `clean_chicago_crimes` three times on PostgreSQL 14.20. Raw rows, distinct raw IDs, clean rows, and distinct clean IDs each equaled 761,563, producing zero deduplication removals, zero unexplained record loss, zero source-lineage gaps, and zero preserved-source-field mismatches. All 138 rows associated with 64 repeated case numbers were retained. Required temporal features had zero nulls and zero definition mismatches across year 2023–2025, month 1–12, quarter 1–4, ISO weekday 1–7, and hour 0–23. The clean table retained 6,697 records without coordinates, flagged 754,866 as coordinate-mappable (99.1206%), validated 760,496 records for named community-area analysis, normalized one district `16` to derived `016`, and preserved 1,020 `061` rows as non-current-reference codes. Source and clean primary-type cardinality both remained 31; no broader crime grouping was created. Five targeted indexes were built. Full decisions, counts, definitions, queries, and limitations are recorded in [the cleaning report](cleaning_report.md). No analytical SQL or year-over-year metric was produced.

## Milestone 5 — SQL analysis and verified year-over-year metrics

### Scope

Create reproducible SQL for temporal, geographic, seasonal, category, domestic, arrest, and year-over-year analyses.

### Acceptance criteria

- Citywide year-over-year changes use adjacent complete calendar years and the approved formula.
- Community-area year-over-year changes cover every eligible community area and document exclusions and zero denominators.
- Temporal, category, domestic, arrest-indicator, and geographic outputs use the shared definitions.
- Incident counts are never labeled rates; arrest percentages are never described as clearance or conviction rates.
- Independent reconciliation queries verify totals, denominators, year coverage, and ranking outputs.
- Results and caveats are recorded only from executed queries.

### Status: Complete

Milestone 5 is complete. `sql/04_business_analysis.sql` contains 29 read-only analytical queries, each documenting its business question, metric definition, assumptions, and denominator. Every query executed successfully against 761,563 records in `clean_chicago_crimes`. The suite covers scope and coverage, complete-year totals and adjacent-year changes, source categories and descriptions, calendar month and year-month patterns, ISO weekday, hour, time of day, weekday/weekend comparisons, all 77 eligible community areas, 154 adjacent-year community-area comparisons with zero undefined prior-year denominators, current-reference and unmatched police districts, location descriptions, arrest percentages, domestic-indicator percentages, and seasonal patterns for the fixed ten largest primary categories. The final validation reconciled year, category, month, weekday, hour, time-of-day, weekend, district, location, season, and community-area partitions to the canonical total with zero mismatches; arrest and domestic null-indicator counts were also zero. Verified findings and limitations are documented in [the core SQL analysis report](sql_analysis_report.md). Counts are never labeled population-normalized rates, arrest percentages are not presented as clearance or conviction rates, and no causal claim or resource-planning recommendation was produced.

## Milestone 6 — Advanced SQL and quantified portfolio findings

### Scope

Create reusable analytical views and advanced SQL for complete-year citywide and community-area change, rolling temporal patterns, source-category trends, persistent high-volume areas, arrest-indicator trends, and seasonal patterns. Test supplied candidate figures without changing canonical filters and document only executed, denominator-backed portfolio findings.

### Acceptance criteria

- Advanced SQL demonstrates CTEs, `LAG`, `RANK`, `DENSE_RANK`, partitioned windows, conditional aggregation, rolling averages, and percentage-of-total calculations.
- Citywide comparisons return every complete year, prior values, absolute changes, percentage changes, and observed extrema with safe zero-denominator handling.
- Community-area output covers all 77 official areas, includes City names, distinguishes percentage from absolute rankings, and documents a defensible percentage-rank baseline.
- Forest Glen and the supplied citywide candidate values are tested against canonical data without filter manipulation.
- Reusable views centralize executive, annual, community-area, category, temporal, and coordinate-mapping outputs without redundant persisted data.
- Annual and community-area counts reconcile to clean and raw source records, and all view validation executes successfully.
- Claim-level findings record periods, prior/current values, absolute/percentage changes, supporting SQL, denominators, and caveats.

### Status: Complete

Milestone 6 is complete. `sql/05_advanced_analysis.sql` created seven non-materialized views, including the official 77-area lookup, and executed all advanced analyses plus fail-fast validation. Citywide view totals matched the immutable raw source and clean table in every year; annual category/month totals, 154 community-area comparisons, and 754,866 geographic-point rows also reconciled with zero differences. Percentage ranks use a 500-incident prior-year minimum, retaining 75 of 77 areas in each comparison, while absolute ranks retain all 77. The canonical 2024–2025 citywide result was 259,633 to 238,086 (-21,547; -8.2990%), not the supplied 260,381 to 237,849. Forest Glen was the largest eligible percentage decrease at 545 to 409 (-24.9541%, not -25.1%), while Austin had the largest absolute decrease at -1,152 records. Evidence, denominators, caveats, and interview-defensible wording are recorded in [quantified findings](quantified_findings.md). No Python, Tableau, causal, or resource-planning work was performed.

## Milestone 7 — Python exploratory analysis and static visuals

### Scope

Implement reproducible Python analysis that validates SQL outputs and produces portfolio-quality exploratory charts.

### Acceptance criteria

- Scripts or notebooks run from repository-relative paths with documented commands.
- Pandas results reconcile with selected PostgreSQL totals and percentages within documented tolerances.
- Visuals have accurate titles, units, date coverage, source attribution, and accessible labeling.
- Partial periods, missing geography, and category grouping are visibly or textually disclosed.
- Generated images are reproducible; large intermediate exports remain ignored.
- Observed associations are not framed as causal effects.

### Status: Complete

Milestone 7 is complete. Both version-controlled notebooks were rebuilt, restarted, and executed from beginning to end using a fresh repository-local virtual environment and read-only PostgreSQL connections configured through environment variables. `01_data_validation.ipynb` executed nine code cells with zero errors and passed all 10 gates: 761,563 records and source IDs, annual counts, adjacent-year percentages, 760,496 community-area-eligible records, all 154 area comparisons, rank eligibility, and all percentage/absolute ranks reconciled between independently calculated Pandas results and SQL. The maximum annual count difference and maximum community-area numeric difference were both zero. `02_exploratory_analysis.ipynb` executed 14 code cells with zero errors, covered every required analytical domain, added category-specific calendar-month profiles, and regenerated eight visually inspected Matplotlib PNGs. Findings and limitations are documented in [the Python EDA report](python_eda_report.md). No Tableau, causal, or resource-planning work was performed.

## Milestone 8 — Geographic and descriptive hotspot analysis

### Scope

Validate geographic coverage and analyze community-area, district, category-concentration, annual-change, persistent-volume, location-time, and coordinate-density patterns. Produce reproducible geographic figures and compact Tableau-ready derived datasets while distinguishing incident volume, population-normalized rates, descriptive density, statistical significance, and individual risk.

### Acceptance criteria

- Community-area and coordinate coverage reconcile to SQL and remain separate denominators.
- All 77 official community areas use the documented City lookup; invalid or missing IDs are not imputed from coordinates.
- District analysis retains observed source-derived codes and documents current-reference exceptions.
- Category geographic concentration, annual change, persistence, and location-time patterns use stated denominators and complete-year ordering.
- Coordinate density excludes only non-mappable records, documents binning and resolution dependence, and is never labeled statistically significant without a formal spatial test.
- Incident-volume rankings are never called population-normalized rates or individual-risk measures.
- Tableau-ready geographic data or views are reproducible, documented, and excluded from Git when they are generated datasets.
- The notebook restarts and executes completely, all geographic totals reconcile to SQL, and reports contain only executed findings.

### Status: Complete

Milestone 8 is complete. `03_geographic_analysis.ipynb` executed 15 code cells with zero errors, passed all 14 geographic validation checks, and generated seven source-attributed figures. Pandas matched 761,563 clean records, 760,496 community-area-eligible records, 754,866 coordinate-mappable records, all 77 community-area totals, and all 154 adjacent-year area comparisons to SQL with zero observed difference. The analysis covered community areas, 24 observed district codes, category concentration, annual changes, persistent high-volume areas, location-description time profiles, and coordinate density. Five compact Tableau-ready CSVs were created locally under Git-ignored `data/processed/tableau_geographic/`; `vw_geographic_crime_points` remains the 754,866-row point layer. Density outputs are explicitly descriptive, no formal hotspot-significance method was applied, and no Tableau dashboard was built. Full methods, findings, validation, and limitations are in [the geographic analysis report](geographic_analysis_report.md).

## Milestone 9A — Tableau data preparation and dashboard specification

### Status: Complete

### Scope

Create an efficient, validated Tableau presentation layer; provide reproducible local extracts; and specify every visual and interaction for the four planned dashboard pages without claiming that the workbook exists.

### Acceptance criteria

- Page-oriented views cover executive KPIs, community areas, district codes, area/category composition, coordinate density, monthly patterns, weekday/hour patterns, location/time profiles, and category arrest/domestic indicators.
- Every view has a documented grain and reconciles to the applicable citywide, geographic, category, temporal, arrest, or domestic denominator.
- Optional extracts use environment-configured read-only access, deterministic ordering, row-count checks, and Git-ignored output paths.
- The dashboard plan specifies four pages: Executive Overview, Geographic Crime Patterns, Temporal and Seasonal Patterns, and Crime and Arrest Analysis.
- Every planned visual documents its data source, dimensions/measures, calculations, filters, tooltip fields, sorting, interactions, and validation criteria.
- Exact PostgreSQL and CSV connection instructions preserve credentials outside Git and avoid joins that could multiply aggregate measures.
- Counts remain distinct from population-normalized rates; density remains descriptive; arrest percentage remains distinct from clearance or conviction.
- README, data dictionary, project plan, SQL, export tooling, and dashboard specification agree on completed versus planned work.

### Completion evidence

[`sql/06_tableau_preparation.sql`](../sql/06_tableau_preparation.sql) originally created nine non-materialized views in a single successful transaction and executed fail-fast validation. Executive Overview preparation later added a tenth view: the complete 1,116-row month/category grid required for synchronized crime-type filtering. The presentation layer also contains 3 executive-year rows, 231 community-area/year rows, 72 district/year rows, 5,395 area/category/year rows, 36 citywide monthly rows, 504 weekday/hour/year rows, 40 location/time rows, 93 crime-type/year rows, and 2,127 descriptive coordinate-density rows. Executive, temporal, month/category, and indicator totals reconcile to 761,563 clean records; community-area views reconcile to 760,496 eligible records; coordinate density reconciles to 754,866 mappable records.

[`scripts/export_tableau_data.py`](../scripts/export_tableau_data.py) executes through a read-only PostgreSQL connection. Its full profile produces all ten Git-ignored presentation CSVs; its Page 1 profile produces exactly two CSVs plus a checksum manifest under `data/processed/tableau/page1/`. Every reloaded CSV row count must match its source view. The exact four-page visual and interaction specification, connection procedure, metric rules, and validation gates are in [the Tableau dashboard plan](tableau_dashboard_plan.md).

One initial SQL execution encountered an existing-view column-name mismatch and rolled back before commit. The reference was corrected and the full script then completed successfully. Milestone 9A did not create a Tableau workbook; Executive Overview implementation began separately under Milestone 9B.

## Milestone 9B — Four-page interactive Tableau workbook

### Status: Complete

### Scope

Build and document the four-page Tableau workbook from the Milestone 9A specification.

### Acceptance criteria

- Four pages cover Executive Overview, Geographic Crime Patterns, Temporal and Seasonal Patterns, and Crime and Arrest Analysis.
- Filters, tooltips, legends, navigation, and interaction behavior are implemented and manually tested in Tableau.
- KPI values and defined visual samples reconcile with validated SQL/Python outputs.
- Complete-year labels, counts versus percentages, data cutoff, and limitations are visible.
- Missing-coordinate records are excluded only from coordinate maps and are disclosed through coverage metrics.
- Dashboard completion is claimed only after the workbook is opened and tested in Tableau; screenshots reflect actual functionality.

### Executive Overview implementation checkpoint — Tableau validation complete

Executive Overview Page 1 is generated and validated in Tableau Desktop. The remaining pages are tracked under completed Milestones 9C–9E below, and the four-page Milestone 9B is complete. [`sql/07_tableau_page1_validation.sql`](../sql/07_tableau_page1_validation.sql) provides read-only KPI, category, monthly/category, and filter-test benchmarks. `python scripts/export_tableau_data.py --profile page1` reproducibly creates exactly two Git-ignored CSV sources: 93 year/category rows and 1,116 month/category rows. Both sources contain `crime_year` and `primary_type`, reconcile to PostgreSQL, and remain independent to prevent double counting.

[`scripts/generate_tableau_workbook.py`](../scripts/generate_tableau_workbook.py) writes [`tableau/chicago_crime_analytics.twb`](../tableau/chicago_crime_analytics.twb). The workbook defines the two independent text-file sources, workbook-wide Year and Crime Type parameters, six Executive Overview worksheets, and one fixed-size 1,360 × 850 dashboard. Generation validates XML well-formedness, relative file references, source row counts and checksums, parameter defaults, canonical filter and indicator calculations, sheet/dashboard membership, annual-versus-monthly reconciliation, and the documented 2025 citywide and Theft benchmarks.

Tableau Desktop Free Edition 2026.2.3 on Apple silicon initially rejected unsupported workbook markup during development; each reported element was removed before acceptance. The final file completed Tableau's `workspace.open-workbook` path, dashboard layout, and worksheet model computation without workbook-scoped error or fatal log entries. Visual validation confirmed the enlarged KPI typography, ungrouped `2025` display, human-readable axes, labeled annual trend, parameter-aware top-10 category view, and readable limitation footer. At Year = 2025, All Crime Types rendered 238,086 incidents, 16.1% arrest, and 19.0% domestic; THEFT rendered 55,198, 9.0%, and 5.1%. The yearly trend retained 2023–2025, both independent sources were visible in Tableau's Data menu, and Tableau-exported PNG evidence is stored under `images/tableau/`.

## Milestone 9C — Geographic Crime Patterns dashboard

### Status: Complete

### Scope

Extend the existing workbook with a separate geographic dashboard while preserving the validated Executive Overview. Use a single filterable geographic source so Year, Crime Type, Community Area, and Police District selections update all relevant Page 2 worksheets without cross-grain joins or double counting.

### Acceptance criteria

- A coordinate-based Chicago map displays only records with valid source coordinates and is explicitly labeled descriptive rather than statistically significant.
- Community-area, police-district, and selected-geography crime-category rankings use reported incident counts, readable labels, and descending ordering.
- Incident and coordinate-coverage KPIs reconcile with PostgreSQL for the selected scope.
- Year, Crime Type, Community Area, and Police District controls update every relevant Page 2 worksheet consistently.
- Records without valid coordinates remain in KPI and ranking totals but are excluded from the map.
- Page 1 remains intact, workbook XML and relative source references validate, and Page 2 renders and filters successfully in Tableau Desktop.

### Completion evidence

[`sql/08_tableau_geographic_page.sql`](../sql/08_tableau_geographic_page.sql) creates `vw_tableau_geographic_detail` at year × primary type × community area × district × coordinate eligibility × 0.01-degree coordinate-cell grain. The 50,037-row view retains every clean incident exactly once; nonmappable records have null cell coordinates and remain available to non-map worksheets. [`sql/09_tableau_page2_validation.sql`](../sql/09_tableau_page2_validation.sql) passed all fail-fast checks, including exact reconciliation to 761,563 clean incidents, 760,496 community-area-eligible incidents, 754,866 coordinate-mappable incidents, zero duplicate analytical-grain rows, and zero coordinate-validity violations.

`python scripts/export_tableau_data.py --profile page2` creates `data/processed/tableau/page2/vw_tableau_geographic_detail.csv` plus a checksum manifest. The exporter reloaded and validated 50,037 rows, 77 community areas, and 24 district labels. The generated workbook contains six Page 2 worksheets and the fixed-size `Geographic Crime Patterns` dashboard while retaining all six Page 1 worksheets and the `Executive Overview` dashboard.

Tableau Desktop 2026.2.3 rendered and filtered the generated workbook. Verified states were 2025 All Crime Types at 238,086 incidents and 236,099 mapped incidents (99.1654%, displayed 99.2%); 2025 THEFT at 55,198 and 54,849 (99.3677%, displayed 99.4%); Austin/THEFT at 1,967; and District 008/THEFT at 3,112. The map, area ranking, district comparison, category analysis, KPIs, and four controls updated without Tableau errors. Tableau-exported screenshots are stored under `images/tableau/`. Full Page 2 methods and evidence are in [the build guide](tableau_page2_build_guide.md).

## Milestone 9D — Temporal and Seasonal Crime dashboard

### Status: Complete

### Scope

Create the minimum validated temporal data source, extend the existing workbook generator, build the Page 3 worksheets and dashboard, preserve Pages 1–2, and validate the generated result in Tableau Desktop.

### Acceptance criteria

- One or more deterministic CSV sources support Year, Month, Month Name, weekday, recorded hour, time band, season, and source crime type without double counting.
- Reported-incident, arrest, and domestic components retain the established SQL definitions and complete-year scope.
- Page 3 source totals reconcile to `clean_chicago_crimes` and PostgreSQL benchmarks for 2025 All Crime Types and THEFT.
- Nine generated worksheets implement the required heatmap, monthly, seasonal, time-band, category-comparison, and KPI views.
- The 1,360 × 850 dashboard layout and Year/Crime Type control behavior match the established workbook design.
- The workbook passes XML/source-reference checks and loads, renders, and filters in Tableau Desktop 2026.2.3.

### Implementation and validation evidence

[`sql/10_tableau_temporal_page.sql`](../sql/10_tableau_temporal_page.sql) creates `vw_tableau_temporal_detail` at complete calendar month × source primary type × ISO weekday × recorded hour grain and `vw_tableau_temporal_kpis` at year × filter-scope grain. Every clean incident contributes once to the detail source. The small KPI source materializes deterministic peak-hour, weekday, and month results for `All Crime Types` and each source crime type, avoiding fragile Tableau table-calculation addressing.

[`sql/11_tableau_page3_validation.sql`](../sql/11_tableau_page3_validation.sql) passes all fail-fast blocks and produces the documented manual benchmarks. The detail view contains 87,809 rows, 21 columns, 31 crime types, no duplicate declared-grain rows, and 761,563 represented incidents from January 2023 through December 2025. The KPI view contains 96 rows and 12 columns. Annual counts, indicator components, time bands, and both 2025 KPI scopes reconcile exactly. Both CSVs reload at the PostgreSQL row count and match the manifest SHA-256 checksums.

`./.venv/bin/python scripts/export_tableau_data.py --profile page3` writes `data/processed/tableau/page3/vw_tableau_temporal_detail.csv`, `vw_tableau_temporal_kpis.csv`, and `manifest.json`. The data is Git-ignored. The implementation definitions and benchmark checklist are in [the Page 3 build guide](tableau_page3_build_guide.md).

At the Milestone 9D checkpoint, [`scripts/generate_tableau_workbook.py`](../scripts/generate_tableau_workbook.py) produced 21 worksheets, three fixed-size dashboards, five CSV-backed data sources, and shared parameters while preserving the Page 1–2 XML definitions. That corrected three-page workbook passed XML, file-reference, checksum, worksheet/dashboard membership, formula, and benchmark validation.

An initial 2025 / THEFT screenshot exposed incorrect peak-card values and a blank time-of-day chart. Those defects were corrected: peak cards now read from `vw_tableau_temporal_kpis`, and the time-band chart uses the physical `time_of_day_display` field. Tableau Desktop 2026.2.3 then rendered the corrected 2025 / All Crime Types and 2025 / THEFT states. The retained screenshots verify totals of 238,086 and 55,198; peak hours of 00:00 and 12:00; Friday and July as both scopes' peak day and month; all monthly, seasonal, heatmap, and category views; and the four time-band counts. Evidence is stored in [`temporal_seasonal_patterns_2025_all.png`](../images/tableau/temporal_seasonal_patterns_2025_all.png) and [`temporal_seasonal_patterns_2025_theft.png`](../images/tableau/temporal_seasonal_patterns_2025_theft.png).

## Milestone 9E — Crime and Arrest Analysis dashboard

### Status: Complete

### Scope

Extend the existing workbook with Page 4 while preserving Pages 1–3. Reuse the validated year × source-crime-type data source and calculate arrest and domestic percentages from summed numerators and reported-incident denominators.

### Acceptance criteria

- Category incident volume, category arrest percentage, arrest-percentage trend, incident volume versus arrest percentage, domestic incident analysis, and KPI summaries are implemented.
- Arrest percentage is `100 * SUM(arrest_count) / SUM(reported_incident_count)` and domestic incident percentage is `100 * SUM(domestic_count) / SUM(reported_incident_count)`, with zero denominators returning null.
- Year and Crime Type controls update all applicable Page 4 worksheets; the three-year arrest trend intentionally ignores Year while respecting Crime Type.
- The 1,360 × 850 dashboard follows the established design and introduces no joins or duplicated aggregate grains.
- PostgreSQL benchmarks, workbook XML, calculations, data references, worksheet definitions, dashboard zones, and both required filter states validate.
- Tableau Desktop renders 2025 / All Crime Types and 2025 / THEFT, filters update correctly, Pages 1–3 remain functional, and screenshots document the tested states.

### Implementation and validation evidence

Page 4 reuses `data/processed/tableau/page1/vw_tableau_crime_arrest_year.csv`, which contains 93 rows at year × source primary-type grain. No new CSV, join, relationship, union, or blend was added. [`sql/12_tableau_page4_validation.sql`](../sql/12_tableau_page4_validation.sql) runs read-only fail-fast reconciliation and benchmark queries. It validated 761,563 incidents, 106,475 arrest flags, 140,243 domestic flags, 31 crime types, and complete years 2023–2025.

The generator now writes 27 worksheets and four fixed-size dashboards. Page 4 adds six worksheets and reuses the existing total-incident KPI and category-volume worksheet. The generated XML, five relative CSV references, calculated-field formulas, parameters, worksheet membership, dashboard zones, and 2025 benchmarks pass automated validation. PostgreSQL returned 238,086 incidents, 16.1139% arrest, and 19.0347% domestic for 2025 All Crime Types; 2025 THEFT returned 55,198, 9.0420%, and 5.1270%.

After restarting the application, Tableau Desktop 2026.2.3 loaded and rendered the generated workbook. Page 4 displayed 238,086 incidents, 16.1% arrest, and 19.0% domestic for 2025 All Crime Types; the THEFT selection displayed 55,198, 9.0%, and 5.1%. Category charts, the three-year arrest trend, and the volume-versus-arrest scatter updated consistently. Tableau exported full-dashboard evidence to [`crime_arrest_analysis_2025_all.png`](../images/tableau/crime_arrest_analysis_2025_all.png) and [`crime_arrest_analysis_2025_theft.png`](../images/tableau/crime_arrest_analysis_2025_theft.png).

A focused cross-page review compared the retained 2025 All Crime Types exports for all four dashboards. Titles, blue visual palette, KPI typography, filter placement, complete-year scope, reported-incident terminology, readable labels, and limitation footers were consistent. Page 4 reused existing parameters and data references without breaking the previously validated pages. Milestones 9E and 9B are complete.

## Milestone 10 — Findings and resource-planning recommendations

### Status: Planned

### Scope

Synthesize verified evidence into findings and cautious resource-planning recommendations.

### Acceptance criteria

- Every numeric statement traces to a saved SQL query or reproducible Python output.
- Recommendations identify the relevant place, time, or category pattern, the supporting evidence, and important uncertainty.
- Recommendations are operational hypotheses, not causal or predictive claims beyond the analysis.
- Reported-crime undercoverage, record revisions, approximate geography, missing data, and population-rate limitations are explicit.
- Citywide and community-area statements use the correct comparison eligibility rules.
- README and technical reports agree on findings, definitions, and date coverage.

## Milestone 11 — Final QA, portfolio packaging, and resume metrics

### Status: Planned

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
