# Data Dictionary

## Status and source

This dictionary documents the official City of Chicago [Crimes - 2001 to Present](https://data.cityofchicago.org/Public-Safety/Crimes-2001-to-Present/ijzp-q8t2/data) dataset (`ijzp-q8t2`) as verified on September 25, 2026. The acquired raw extract covers incident timestamps from January 1, 2023 through December 31, 2025 and contains 761,563 rows.

The official metadata contained 31 columns: 22 core published fields returned by the explicit CSV export and nine portal-computed geographic fields. The acquisition script preserved the 22 exported fields. Milestone 2 loaded all 761,563 records into a text staging table and the typed PostgreSQL table `raw_chicago_crimes` without filtering or analytical cleaning.

Empty-field counts below are observations from the raw CSV. PostgreSQL CSV parsing represents unavailable unquoted fields as SQL `NULL`; present text is retained unchanged in staging. Domain and geographic validity checks remain reserved for later milestones.

## Exported source fields

| Source column | API field | Socrata type | `raw_chicago_crimes` type | Empty fields | Interpretation / later validation |
|---|---|---|---|---:|---|
| ID | `id` | `number` | `bigint` | 0 | Source record identifier; 761,563 values were unique in this extract. |
| Case Number | `case_number` | `text` | `text` | 0 | Chicago Police Department Records Division number; source metadata describes it as incident-unique, but later checks must not substitute it for `id`. |
| Date | `date` | `calendar_date` | `timestamp(3) without time zone` | 0 | Reported occurrence timestamp, sometimes estimated; the source provides no timezone offset. |
| Block | `block` | `text` | `text` | 0 | Privacy-protected block-level location, not an exact address. |
| IUCR | `iucr` | `text` | `text` | 0 | Illinois Uniform Crime Reporting code; preserve leading zeros. |
| Primary Type | `primary_type` | `text` | `text` | 0 | Primary classification associated with the IUCR code; classifications may be revised. |
| Description | `description` | `text` | `text` | 0 | Secondary IUCR description. |
| Location Description | `location_description` | `text` | `text` | 3,947 | Categorical incident-location description; profile variants without modifying raw values. |
| Arrest | `arrest` | `checkbox` | `boolean` | 0 | Indicates whether an arrest was made; not a clearance, prosecution, or conviction field. |
| Domestic | `domestic` | `checkbox` | `boolean` | 0 | Domestic-related indicator as defined by the source. |
| Beat | `beat` | `text` | `text` | 0 | Police beat identifier; preserve as a code. |
| District | `district` | `text` | `text` | 0 | Police district identifier; preserve as a code. |
| Ward | `ward` | `number` | `smallint` | 4 | City Council ward; validate integer domain and historical comparability before analysis. |
| Community Area | `community_area` | `text` | `smallint` | 35 | Chicago community-area identifier; the analytical valid range is 1–77 after later parsing and validation. |
| FBI Code | `fbi_code` | `text` | `text` | 0 | FBI crime classification code; preserve as a code. |
| X Coordinate | `x_coordinate` | `number` | `integer` | 6,697 | Projected coordinate; coordinate reference system and range require verification. |
| Y Coordinate | `y_coordinate` | `number` | `integer` | 6,697 | Projected coordinate; coordinate reference system and range require verification. |
| Year | `year` | `number` | `smallint` | 0 | Source-provided year; later reconcile with parsed `date`. |
| Updated On | `updated_on` | `calendar_date` | `timestamp(3) without time zone` | 0 | Source record update timestamp; the source provides no timezone offset. |
| Latitude | `latitude` | `number` | `numeric(12,9)` | 6,697 | Approximate latitude; exact numeric value is retained while display scale can gain trailing zeros. |
| Longitude | `longitude` | `number` | `numeric(12,9)` | 6,697 | Approximate longitude; exact numeric value is retained while display scale can gain trailing zeros. |
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

Presence is not the same as geographic validity. Range, parse, cross-field consistency, and boundary checks have not been performed. Records without coordinates remain available for applicable non-coordinate analyses.

## Planned derived fields

No derived fields were created during acquisition. Later milestones may add calendar parts, complete-period flags, coordinate-availability flags, and data-quality status fields only after documenting their formulas and lineage. Source columns will not be silently overwritten.

## Database-load validation completed

- Every source timestamp and boolean value cast successfully.
- All integer and decimal source values cast successfully.
- Expected, staging, imported, and distinct source-ID counts each equal 761,563.
- Full-row reconciliation found no value mismatches after comparing coordinates by exact numeric equivalence.
- Typed-table date boundaries, yearly totals, and missing-value counts match the acquisition evidence.

## Data-quality checks reserved for later milestones

- Source-year versus parsed-date-year reconciliation
- Valid community-area, ward, district, and beat domains
- Coordinate numeric parsing, range, reference system, and cross-field consistency
- Category whitespace, spelling variants, and classification changes
- Record-version and update-timestamp implications for refreshes

See [dataset acquisition](dataset_acquisition.md) for source queries and extraction evidence, and [database setup](database_setup.md) for the executed PostgreSQL workflow.
