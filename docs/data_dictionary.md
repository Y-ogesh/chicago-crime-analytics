# Data Dictionary

## Status and source

This dictionary documents the official City of Chicago [Crimes - 2001 to Present](https://data.cityofchicago.org/Public-Safety/Crimes-2001-to-Present/ijzp-q8t2/data) dataset (`ijzp-q8t2`) as verified on September 25, 2026. The acquired raw extract covers incident timestamps from January 1, 2023 through December 31, 2025 and contains 761,563 rows.

The official metadata contained 31 columns: 22 core published fields returned by the explicit CSV export and nine portal-computed geographic fields. The acquisition script preserved the 22 exported fields. Milestone 2 loaded all 761,563 records into a text staging table and the typed PostgreSQL table `raw_chicago_crimes` without filtering or analytical cleaning.

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

## Planned derived fields

No derived fields have been created. A future authorized cleaning milestone may add calendar parts, complete-period flags, coordinate-availability flags, normalized join keys, and data-quality status fields only after documenting their formulas and lineage. Source columns will not be silently overwritten.

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

See [dataset acquisition](dataset_acquisition.md) for source queries and extraction evidence, [database setup](database_setup.md) for the executed PostgreSQL workflow, and [data quality assessment](data_quality_report.md) for counts, percentages, proposed treatments, validation queries, and limitations.
