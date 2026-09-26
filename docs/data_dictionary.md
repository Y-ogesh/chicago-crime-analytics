# Data Dictionary

## Status and source

This dictionary documents the official City of Chicago [Crimes - 2001 to Present](https://data.cityofchicago.org/Public-Safety/Crimes-2001-to-Present/ijzp-q8t2/data) dataset (`ijzp-q8t2`) as verified on September 25, 2026. The acquired raw extract covers incident timestamps from January 1, 2023 through December 31, 2025 and contains 761,563 rows.

The official metadata contained 31 columns: 22 core published fields returned by the explicit CSV export and nine portal-computed geographic fields. The acquisition script preserved the 22 exported fields. Milestone 2 loaded all 761,563 records into a text staging table and the typed PostgreSQL table `raw_chicago_crimes` without filtering or analytical cleaning. Milestone 4 created `clean_chicago_crimes` with the same 761,563 source IDs, preserved source-value columns, validated analytical geography, and constrained temporal features.

Empty-field counts below are observations from the raw CSV. PostgreSQL CSV parsing represents unavailable unquoted fields as SQL `NULL`; present text is retained unchanged in staging. Milestone 3 assessed domain, formatting, completeness, and geographic plausibility without modifying the raw layer.

## Exported source fields

| Source column | API field | Socrata type | `raw_chicago_crimes` type | Empty fields | Interpretation / later validation |
|---|---|---|---|---:|---|
| ID | `id` | `number` | `bigint` | 0 | Source record identifier; 761,563 values were unique in this extract. |
| Case Number | `case_number` | `text` | `text` | 0 | Chicago Police Department Records Division number. Sixty-four values repeat across 138 rows, so it must not substitute for source `id` or drive automatic deduplication. |
| Date | `date` | `calendar_date` | `timestamp(3) without time zone` | 0 | Reported occurrence timestamp, sometimes estimated; the source provides no timezone offset. |
| Block | `block` | `text` | `text` | 0 | Privacy-protected block-level location, not an exact address. |
| IUCR | `iucr` | `text` | `text` | 0 | Illinois Uniform Crime Reporting code; preserve leading zeros. |
| Primary Type | `primary_type` | `text` | `text` | 0 | Primary classification associated with the IUCR code; classifications may be revised. |
| Description | `description` | `text` | `text` | 0 | Secondary IUCR description. |
| Location Description | `location_description` | `text` | `text` | 3,947 | Categorical incident-location description; 142 non-null values were observed, with no tested case/outer-whitespace cardinality difference. |
| Arrest | `arrest` | `checkbox` | `boolean` | 0 | Indicates whether an arrest was made; not a clearance, prosecution, or conviction field. |
| Domestic | `domestic` | `checkbox` | `boolean` | 0 | Domestic-related indicator as defined by the source. |
| Beat | `beat` | `text` | `text` | 0 | Police beat identifier; preserve as a code. |
| District | `district` | `text` | `text` | 0 | Police district identifier. One row uses non-padded `16`; 1,020 use `061`, absent from the current official district reference. Preserve raw codes. |
| Ward | `ward` | `number` | `smallint` | 4 | City Council ward. Values 1–50 are valid for numbered-ward analysis; 1,032 additional rows contain `0` and require an unknown/unassigned classification. |
| Community Area | `community_area` | `text` | `smallint` | 35 | Chicago community-area identifier. Values 1–77 are eligible for named-area analysis; 1,032 additional rows contain `0` and are out of range. |
| FBI Code | `fbi_code` | `text` | `text` | 0 | FBI crime classification code; preserve as a code. |
| X Coordinate | `x_coordinate` | `number` | `integer` | 6,697 | Projected coordinate. Missingness exactly matches latitude, longitude, and location; no partial pair was observed. |
| Y Coordinate | `y_coordinate` | `number` | `integer` | 6,697 | Projected coordinate. Missingness exactly matches latitude, longitude, and location; no partial pair was observed. |
| Year | `year` | `number` | `smallint` | 0 | Source-provided year; all 761,563 values matched the year extracted from `date`. |
| Updated On | `updated_on` | `calendar_date` | `timestamp(3) without time zone` | 0 | Source record update timestamp; the source provides no timezone offset. |
| Latitude | `latitude` | `number` | `numeric(12,9)` | 6,697 | Approximate latitude; present values passed global and City map-envelope screens. Missing rows remain usable outside point mapping. |
| Longitude | `longitude` | `number` | `numeric(12,9)` | 6,697 | Approximate longitude; present values passed global and City map-envelope screens. Missing rows remain usable outside point mapping. |
| Location | `location` | `location` | `text` | 6,697 | Combined portal location text; present values preserve embedded line breaks. |

## PostgreSQL raw layer

Three tables implement the raw import:

- `raw_chicago_crimes_staging` stores the 22 parsed source fields as text plus a generated `source_row_number`. It preserves source strings before type conversion; PostgreSQL CSV `NULL` semantics represent unavailable unquoted fields.
- `raw_chicago_crimes` stores the same 22 fields with the types documented above and enforces source `id` as the primary key. Every staging row must cast and reconcile before the transaction commits.
- `raw_chicago_crimes_load_audit` records the source filename, SHA-256, expected/staging/imported/distinct-ID counts, date bounds, yearly counts, and load timestamp for every successful rebuild.

Text identifiers such as `iucr`, `beat`, and `district` remain text so leading zeros are preserved. `case_number` is not constrained as unique because the acquired file contains repeated case-number values. Source values such as `ward = 0` and `community_area = 0` remain unchanged; later milestones must classify validity without rewriting the raw layer.

## Portal-computed geographic metadata fields

These nine fields were present in official dataset metadata but marked with `:@computed_region_...` API names. They were not part of the 22-field explicit raw CSV export and are not silently treated as substitutes for the source `community_area`, police, ward, coordinate, or ZIP fields.

| Metadata column | API field | Socrata type |
|---|---|---|
| Historical Wards 2003-2015 | `:@computed_region_awaf_s7ux` | `number` |
| Zip Codes | `:@computed_region_6mkv_f3dw` | `number` |
| Community Areas | `:@computed_region_vrxf_vc4k` | `number` |
| Census Tracts | `:@computed_region_bdys_3d7i` | `number` |
| Wards | `:@computed_region_43wa_7qmu` | `number` |
| Boundaries - ZIP Codes | `:@computed_region_rpca_8um6` | `number` |
| Police Districts | `:@computed_region_d9mm_jgwp` | `number` |
| Police Beats | `:@computed_region_d3ds_rm58` | `number` |
| Wards 2023- | `:@computed_region_8hcu_yrd4` | `number` |

## Acquisition-level observations

- Source rows, downloaded rows, and distinct `id` values: 761,563 each
- Observed incident timestamp range: `2023-01-01T00:00:00.000` through `2025-12-31T23:58:00.000`
- Both latitude and longitude present: 754,866 records
- Missing or incomplete latitude/longitude pair: 6,697 records
- Non-empty source `community_area`: 761,528 records
- Empty source `community_area`: 35 records

Milestone 3 confirmed no partial coordinate pairs, no latitude/longitude versus projected-coordinate presence mismatches, no globally invalid or zero coordinate pairs, and no points outside the tested City map envelope. The envelope is a rectangular plausibility screen, not a point-in-polygon or positional-accuracy test. Records without coordinates remain available for applicable non-coordinate analyses.

## PostgreSQL clean layer

`clean_chicago_crimes` is a reproducibly rebuilt one-row-per-`source_id` analytical table. It retains every current raw source ID. Exact source versions of normalized identifiers and categories use a `source_` prefix; analytical counterparts are uppercase/outer-trimmed or domain-validated as documented below. The raw table remains authoritative and unchanged.

### Identity and source-preservation fields

| Clean column | Type | Definition / lineage |
|---|---|---|
| `source_id` | `bigint` | Official `raw_chicago_crimes.id`; clean primary key and deterministic deduplication key. |
| `source_case_number` | `text` | Exact raw case number. Repeated values are retained. |
| `case_number` | `text` | Uppercase/outer-trimmed case number for consistent filtering. |
| `source_iucr`, `source_beat`, `source_district`, `source_fbi_code` | `text` | Exact raw identifier/code values. |
| `iucr`, `beat`, `fbi_code` | `text` | Uppercase/outer-trimmed analytical codes; leading zeros are retained. |
| `district` | `text` | Uppercase/outer-trimmed district join key; one-to-three-digit numeric codes are left-padded to three characters. |
| `district_current_flag` | `boolean` | True when `district` matches the current City district reference verified September 25, 2026. False is an unmatched-reference status, not proof of source error. |
| `block` | `text` | Exact privacy-protected raw block value. |
| `updated_on` | `timestamp(3) without time zone` | Exact typed source update timestamp. |

### Crime-category and indicator fields

| Clean column | Type | Definition / lineage |
|---|---|---|
| `source_primary_type` | `text` | Exact raw primary crime category. |
| `primary_type` | `text` | Uppercase/outer-trimmed source primary type. No broader grouping is applied. |
| `source_description` | `text` | Exact raw secondary description. |
| `description` | `text` | Uppercase/outer-trimmed description. |
| `source_location_description` | `text` | Exact nullable raw location category. |
| `location_description` | `text` | Uppercase/outer-trimmed location category; null/blank becomes `UNKNOWN / NOT REPORTED`. |
| `arrest` | `boolean` | Unchanged source arrest indicator; not clearance or conviction. |
| `domestic` | `boolean` | Unchanged source domestic-related indicator. |

### Temporal fields

| Clean column | Type | Definition / allowed values |
|---|---|---|
| `crime_timestamp` | `timestamp(3) without time zone` | Typed raw incident timestamp; no timezone is inferred. |
| `crime_date` | `date` | Calendar date cast from `crime_timestamp`. |
| `source_year` | `smallint` | Exact typed source year. |
| `crime_year` | `smallint` | Year extracted from `crime_timestamp`; constrained to equal `source_year`. |
| `crime_month` | `smallint` | Month 1–12. |
| `month_name` | `text` | English month name mapped from `crime_month`. |
| `crime_quarter` | `smallint` | Calendar quarter 1–4. |
| `day_of_week_num` | `smallint` | ISO weekday: Monday=1 through Sunday=7. |
| `day_of_week` | `text` | English weekday mapped from `day_of_week_num`. |
| `hour_of_day` | `smallint` | Hour 0–23. |
| `time_of_day` | `text` | `Overnight` 00–05; `Morning` 06–11; `Afternoon` 12–17; `Evening` 18–23. |
| `season` | `text` | Meteorological `Winter` Dec–Feb, `Spring` Mar–May, `Summer` Jun–Aug, `Fall` Sep–Nov. |
| `weekend_flag` | `boolean` | True for Saturday/Sunday; false otherwise. |

### Administrative and coordinate geography

| Clean column | Type | Definition / lineage |
|---|---|---|
| `source_ward` | `smallint` | Exact typed raw ward, including null or `0`. |
| `ward` | `smallint` | Source ward when 1–50; otherwise null. |
| `ward_eligible_flag` | `boolean` | True exactly when `ward` is non-null. |
| `source_community_area` | `smallint` | Exact typed raw community area, including null or `0`. |
| `community_area` | `smallint` | Source community area when 1–77; otherwise null. |
| `community_area_eligible_flag` | `boolean` | True exactly when `community_area` is non-null. |
| `x_coordinate`, `y_coordinate` | `integer` | Unchanged nullable typed source projected coordinates. |
| `latitude`, `longitude` | `numeric(12,9)` | Unchanged nullable typed source geographic coordinates. |
| `location` | `text` | Unchanged nullable raw combined-location text. |
| `coordinate_available_flag` | `boolean` | True when both latitude and longitude are present. |
| `coordinate_valid_flag` | `boolean` | For present pairs, true when values satisfy global limits and are not `(0,0)`; null when unavailable. |
| `within_city_bounds_flag` | `boolean` | For present pairs, result of the documented City map rectangular-envelope screen; null when unavailable. |
| `coordinate_mappable_flag` | `boolean` | True when the pair is available, globally valid, and within the City envelope. |

Milestone 4 produced 760,496 community-area-eligible rows, 760,527 ward-eligible rows, and 754,866 coordinate-mappable rows. All 6,697 rows lacking coordinates remain in the table for applicable non-coordinate analysis.

## Milestone 6 analytical views

All objects below are non-materialized PostgreSQL views created reproducibly by `sql/05_advanced_analysis.sql`; they do not replace or modify the raw or clean tables.

| View | Grain | Purpose and key fields |
|---|---|---|
| `vw_community_area_lookup` | One row per official community area (77 rows) | Maps `community_area` to `community_area_name` using City dataset `igwz-8jzy` (map `cauq-8yn6`). |
| `vw_executive_kpis` | One row | Canonical count/date coverage, geographic and community-area coverage, arrest/domestic numerators and denominators, and latest complete-year change. |
| `vw_yearly_crime_trends` | One row per complete year | `reported_incident_count`, prior year/count, absolute and percentage change, and volume rank. |
| `vw_community_area_yoy` | One row per area per adjacent-year comparison | Official name, prior/current counts, absolute/percentage changes, 500-record percentage-rank eligibility, percentage ranks, and all-area absolute ranks. |
| `vw_crime_type_trends` | One row per year and source `primary_type` | Counts, annual percentage of total, prior values, changes, and within-year category volume rank. |
| `vw_temporal_patterns` | One row per calendar month | Monthly count/share, trailing three-month average, and same-month prior-year absolute/percentage change. |
| `vw_geographic_crime_points` | One row per coordinate-mappable incident | Selected incident, category, time, geography, coordinate, and indicator fields for point mapping; non-mappable incidents remain in `clean_chicago_crimes`. |

All view percentages retain PostgreSQL numeric precision and are rounded only in query/report display. Their metric and denominator rules are defined in [metric definitions](metric_definitions.md).

## Milestone 9A Tableau presentation views

All objects below are non-materialized PostgreSQL views created by `sql/06_tableau_preparation.sql`. They summarize the canonical clean table at dashboard-safe grains. Views with different grains must remain separate Tableau data sources; physically joining them can duplicate measures.

| View | Grain / validated rows | Purpose and key fields |
|---|---|---|
| `vw_tableau_executive_year` | Complete calendar year / 3 | Period dates/status, source metadata, reported incidents, prior-year values/change, arrest and domestic numerators/denominators/percentages, and community/coordinate coverage. |
| `vw_tableau_community_area_year` | Year × 77 official areas / 231 | Area count, yearly eligible denominator/share/rank, canonical adjacent-year values, 500-record percentage-rank eligibility, and percentage/absolute ranks. |
| `vw_tableau_district_year` | Year × observed source district code / 72 | District label/reference status, count, citywide denominator/share/rank, and adjacent-year values. Unmatched current-reference codes remain visible. |
| `vw_tableau_area_category_year` | Year × area × observed `primary_type` / 5,395 | Count, area-year and category-year denominators/shares, category rank within area, and area rank within category. |
| `vw_tableau_monthly_patterns` | Calendar month / 36 | `month_start`, month/quarter/season, count/share, trailing three-month average, same-month prior-year change, and weighted indicator components. |
| `vw_tableau_time_patterns` | Year × ISO weekday × hour / 504 | Count and arrest/domestic components with documented day, hour, time-of-day, and weekend fields. |
| `vw_tableau_location_time` | Fixed full-period top-ten locations × four time bands / 40 | Location rank/total, ordered time band, count, and percentage of the location total. This view is intentionally full-period rather than year-filterable. |
| `vw_tableau_crime_arrest_year` | Year × source `primary_type` / 93 | Count/share/rank, prior-year values/change, and arrest/domestic numerators, denominators, and percentages. |
| `vw_tableau_coordinate_density` | Year × 0.01-degree display cell / 2,127 | Cell-center latitude/longitude, stable cell ID, and reported-incident count for coordinate-mappable records. Cells are descriptive, resolution-dependent, not equal-area, and do not test statistical significance. |

The optional exporter writes one CSV per view plus a checksum manifest under Git-ignored `data/processed/tableau/`. Detailed visual assignments and aggregation rules are in [the Tableau dashboard plan](tableau_dashboard_plan.md).

## Database-load validation completed

- Every source timestamp and boolean value cast successfully.
- All integer and decimal source values cast successfully.
- Expected, staging, imported, and distinct source-ID counts each equal 761,563.
- Full-row reconciliation found no value mismatches after comparing coordinates by exact numeric equivalence.
- Typed-table date boundaries, yearly totals, and missing-value counts match the acquisition evidence.

## Data-quality assessment completed

- All 761,563 source IDs are unique. Repeated case numbers affect 138 rows (0.0181%) and are not treated as duplicate source records.
- No incident-date nulls, nonstandard source-date strings, update-date nulls, or date/year mismatches were found.
- No missing primary types, tested outer-whitespace variants, or conflicting IUCR-to-primary-type mappings were found.
- Location description is missing on 3,947 rows (0.5183%).
- Community area is null on 35 rows and `0` on 1,032 rows; ward is null on four rows and `0` on 1,032 rows.
- Coordinates and location are jointly missing on 6,697 rows (0.8794%). Present coordinate pairs passed the implemented plausibility screens.
- Arrest and domestic fields are complete booleans. Their observed distributions are validation evidence, not clearance or conviction measures.
- Raw category cardinality is 31 primary types, 337 descriptions, 142 non-null location descriptions, 359 IUCR codes, and 26 FBI codes.

## Cleaning and feature-engineering validation completed

- Raw rows, distinct raw IDs, clean rows, and distinct clean IDs each equal 761,563; no record was removed.
- Source-ID lineage differences in either direction: 0.
- Missing required temporal/category features: 0; exact temporal-definition mismatches: 0.
- Source and clean primary-type cardinality: 31 each; source and clean description cardinality: 337 each.
- Location-description source nulls labeled in the analytical column: 3,947.
- Clean community-area nulls after 1–77 validation: 1,067; clean ward nulls after 1–50 validation: 1,036.
- Coordinate-mappable rows: 754,866 (99.1206%); missing-coordinate rows retained: 6,697.
- Preserved-source-field mismatches across all source columns copied into the clean table: 0.
- The idempotent rebuild completed three times with the same validated totals.

See [dataset acquisition](dataset_acquisition.md) for source queries and extraction evidence, [database setup](database_setup.md) for the executed PostgreSQL workflow, [data quality assessment](data_quality_report.md) for observed issues, and [cleaning report](cleaning_report.md) for transformations, features, validation evidence, indexes, and limitations.
