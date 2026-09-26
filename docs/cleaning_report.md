# Data Cleaning and Feature Engineering Report

## Scope and execution

Milestone 4 created `public.clean_chicago_crimes` from `public.raw_chicago_crimes` on September 25, 2026 using PostgreSQL 14.20. The implementation is reproducible through [`sql/03_data_cleaning.sql`](../sql/03_data_cleaning.sql). It rebuilds only the clean table inside a transaction, acquires a read-compatible lock to stabilize the source during the rebuild, validates the result before commit, and never updates or deletes raw records.

The script was executed successfully three times while validation was strengthened. The final execution dropped and recreated the clean table, inserted and validated the same 761,563 source IDs, reconciled every preserved source field, rebuilt the same five indexes, and completed with zero validation errors. No analytical aggregation or year-over-year analysis was performed.

Execute the milestone from the repository root with:

```bash
psql -d chicago_crime -X -v ON_ERROR_STOP=1 \
  -f sql/03_data_cleaning.sql
```

Connection parameters can instead be supplied through the standard PostgreSQL environment variables documented in `.env.example`.

## Cleaning decisions

| Area | Implemented decision | Justification and effect |
|---|---|---|
| Raw preservation | Read from `raw_chicago_crimes`; write only to a transactionally rebuilt `clean_chicago_crimes`. | Maintains source lineage and leaves all 761,563 raw rows unchanged. |
| Timestamp conversion | Copy the already typed raw `date` timestamp to `crime_timestamp`; derive `crime_date` and calendar features from it. | Milestone 2 had already validated conversion from source text. Reparsing would add no value and could introduce inconsistency. The timestamp remains without an asserted timezone. |
| Source-ID deduplication | Rank rows within each `id` by a complete deterministic ordering led by latest `updated_on`, and retain rank 1. | The raw primary key already guarantees one row per ID, so this removed zero rows. The rule is explicit and repeatable if upstream version handling changes later. |
| Repeated case numbers | Retain every unique source ID even when `case_number` repeats. | The 64 repeated values affecting 138 rows are not proof of duplicate incidents; homicide records may be victim-based. |
| Identifier preservation | Keep original identifiers in `source_id`, `source_case_number`, `source_iucr`, `source_beat`, `source_district`, and `source_fbi_code`; add normalized counterparts where useful. | Enables exact traceability while providing stable analytical join/filter values. |
| Category preservation | Keep exact source values in `source_primary_type`, `source_description`, and `source_location_description`; expose uppercase/outer-trimmed analytical values separately. | The quality assessment found no case or outer-whitespace variants, so primary-type and description cardinalities did not change. |
| Blank normalization | Convert null or blank location descriptions to `UNKNOWN / NOT REPORTED` only in the analytical `location_description`; preserve the source value separately. | Avoids silent exclusion from grouped output while retaining the original null. Exactly 3,947 rows received this label. |
| Broader crime groups | Do not create a broader crime grouping. | No authoritative grouping was supplied, and an analyst-designed mapping would add avoidable subjectivity. The 31 source primary types remain intact. |
| District normalization | Uppercase/trim district codes and left-pad one-to-three-digit numeric codes to three characters. Keep the original code and add `district_current_flag`. | One source `16` became analytical `016`. All 1,020 `061` rows remain `061` and are flagged as absent from the current reference; they are not discarded or remapped. |
| Ward validity | Preserve `source_ward`; set analytical `ward` only for values 1–50 and expose `ward_eligible_flag`. | Four source nulls and 1,032 source zeros produce 1,036 analytical nulls. All rows remain retained. |
| Community-area validity | Preserve `source_community_area`; set analytical `community_area` only for values 1–77 and expose `community_area_eligible_flag`. | Thirty-five source nulls and 1,032 source zeros produce 1,067 analytical nulls. These rows remain usable outside named community-area analysis. |
| Coordinate availability | Set `coordinate_available_flag` when both latitude and longitude are present. | Retains and explicitly identifies 6,697 non-geocoded incidents for non-map analysis. |
| Coordinate validation | For present pairs, test global coordinate ranges/nonzero values and the documented City map rectangular envelope. | All 754,866 present pairs passed. The envelope is a plausibility screen, not a municipal point-in-polygon test. |
| Coordinate mapping | Set `coordinate_mappable_flag` only when a pair is available, globally valid, and within the approved envelope. | 754,866 rows are mappable and 6,697 remain retained but not coordinate-mappable. |

## Feature definitions

Every feature is derived from `crime_timestamp`. Database constraints enforce the exact mappings.

| Feature | Definition |
|---|---|
| `crime_date` | Calendar date cast from `crime_timestamp`. |
| `crime_year` | Four-digit year extracted from `crime_timestamp`; validated against `source_year`. |
| `crime_month` | Integer month 1–12. |
| `month_name` | English month name mapped deterministically from `crime_month`. |
| `crime_quarter` | Calendar quarter 1–4. |
| `day_of_week_num` | ISO weekday number: Monday=1 through Sunday=7. |
| `day_of_week` | English weekday name mapped from `day_of_week_num`. |
| `hour_of_day` | Integer hour 0–23. |
| `time_of_day` | `Overnight` 00:00–05:59; `Morning` 06:00–11:59; `Afternoon` 12:00–17:59; `Evening` 18:00–23:59. |
| `season` | Meteorological seasons: `Winter` December–February; `Spring` March–May; `Summer` June–August; `Fall` September–November. |
| `weekend_flag` | True for ISO weekday 6 or 7 (Saturday or Sunday); false otherwise. |

The features use the source incident timestamp, which the City states may be estimated. They do not encode holidays, daylight-saving offsets, or astronomical seasons.

## Row-count reconciliation

| Measure | Result |
|---|---:|
| Raw records | 761,563 |
| Distinct raw source IDs | 761,563 |
| Duplicate source-ID excess rows | 0 |
| Clean records | 761,563 |
| Distinct clean source IDs | 761,563 |
| Actual raw-to-clean row-count difference | 0 |
| Raw IDs missing from clean | 0 |
| Clean IDs absent from raw | 0 |
| Rows with any preserved-source-field mismatch | 0 |

Deterministic source-ID deduplication removed zero rows. Repeated case-number coverage was unchanged: 64 repeated values, 138 affected rows, and 74 rows beyond one per repeated value.

## Date and feature validation

| Check | Result |
|---|---|
| Timestamp coverage | 2023-01-01 00:00:00 through 2025-12-31 23:58:00 |
| Date coverage | 2023-01-01 through 2025-12-31 |
| Source-year mismatches | 0 |
| 2023 records | 263,844 |
| 2024 records | 259,633 |
| 2025 records | 238,086 |
| Missing required identifiers, timestamps, or derived features | 0 |
| Month range / distinct names | 1–12 / 12 |
| Quarter range | 1–4 |
| ISO weekday range / distinct names | 1–7 / 7 |
| Hour range | 0–23 |
| Time-of-day categories | 4 |
| Season categories | 4 |
| Exact feature-definition mismatches | 0 |

Feature distributions were validated for total reconciliation:

| Feature | Category | Records |
|---|---|---:|
| Time of day | Overnight | 151,229 |
| Time of day | Morning | 157,694 |
| Time of day | Afternoon | 237,155 |
| Time of day | Evening | 215,485 |
| Season | Winter | 173,386 |
| Season | Spring | 188,658 |
| Season | Summer | 206,931 |
| Season | Fall | 192,588 |
| Weekend flag | False | 542,176 |
| Weekend flag | True | 219,387 |

These are validation distributions, not interpreted crime-pattern findings.

## Geographic validation

| Measure | Records | Percent of clean records |
|---|---:|---:|
| Valid community area 1–77 | 760,496 | 99.8599% |
| Unknown/ineligible community area | 1,067 | 0.1401% |
| Valid ward 1–50 | 760,527 | 99.8640% |
| Unknown/ineligible ward | 1,036 | 0.1360% |
| Coordinate pair available | 754,866 | 99.1206% |
| Coordinate pair unavailable and retained | 6,697 | 0.8794% |
| Present pair failing global validation | 0 | 0.0000% |
| Present pair outside the City envelope | 0 | 0.0000% |
| Coordinate-mappable | 754,866 | 99.1206% |

Community-area eligibility and coordinate-mapping eligibility are different measures and must not be substituted for one another.

## Category validation

- Source and clean primary-type cardinality both equal 31.
- Source and clean description cardinality both equal 337.
- Primary-type standardization mismatches: 0.
- Description/IUCR normalization is deterministic and source versions remain available.
- Location-description standardization mismatches among non-null source values: 0.
- Null source location descriptions labeled `UNKNOWN / NOT REPORTED`: 3,947.
- No broader category mapping was created.

## Indexes

Five B-tree indexes support the expected access patterns:

| Index | Columns / predicate | Intended access pattern |
|---|---|---|
| `clean_chicago_crimes_pkey` | `source_id` unique | Source lineage, joins, uniqueness |
| `clean_crimes_crime_date_idx` | `crime_date` | Date-range filtering |
| `clean_crimes_year_month_idx` | `crime_year, crime_month` | Annual/monthly temporal grouping and filtering |
| `clean_crimes_year_primary_type_idx` | `crime_year, primary_type` | Category trends by year |
| `clean_crimes_year_community_area_idx` | `crime_year, community_area` where eligible | Full-year community-area analysis without indexing invalid/null values |

Boolean-only indexes were intentionally omitted because their low selectivity is unlikely to help the anticipated aggregate scans. Index usefulness should be revisited with `EXPLAIN (ANALYZE, BUFFERS)` when analytical SQL exists.

## Limitations

- Cleaning improves consistency and eligibility signaling; it does not correct underreporting, later source revisions, classification changes, or estimated incident timestamps.
- The current police-district reference may not explain special, administrative, or historical codes such as `061`.
- The coordinate envelope does not establish that a point lies inside Chicago or that its approximate position is accurate.
- No spatial imputation was performed for missing community areas, wards, or coordinates.
- Source crime categories were not combined into broader groups, so cross-category interpretation still depends on City/IUCR classifications.
- This milestone produced a validated record-level table only. It did not execute analytical SQL, calculate year-over-year changes, or produce findings.
