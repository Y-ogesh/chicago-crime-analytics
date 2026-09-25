# Initial Data Dictionary

## Status and source

This is a planning-stage dictionary for the official City of Chicago [Crimes - 2001 to Present](https://data.cityofchicago.org/Public-Safety/Crimes-2001-to-Present/ijzp-q8t2/data) dataset (`ijzp-q8t2`). It records the portal's published fields and proposed PostgreSQL types. No source file has been acquired, so observed formats, null rates, domains, and proposed types remain unvalidated. They must be reconciled against the authorized extract before schema implementation.

The source portal states that records are reported crimes except that murder rows represent victims; dates may be estimates, addresses are block-level, and mapped locations are approximate. Records and classifications can be revised.

## Planned source fields

| Source column | API field | Portal type | Proposed PostgreSQL type | Initial interpretation / validation needed |
|---|---|---|---|---|
| ID | `id` | Number | `bigint` | Source record identifier; test uniqueness and non-nullness before using as the primary key. |
| Case Number | `case_number` | Text | `text` | Chicago Police Department Records Division number; do not assume uniqueness until tested. |
| Date | `date` | Floating Timestamp | `timestamp` | Reported occurrence timestamp, sometimes estimated; verify parsing and timezone convention. |
| Block | `block` | Text | `text` | Privacy-protected block-level location, not an exact address. |
| IUCR | `iucr` | Text | `text` | Illinois Uniform Crime Reporting code; preserve leading zeros. |
| Primary Type | `primary_type` | Text | `text` | Primary crime classification associated with IUCR; profile spelling and revisions. |
| Description | `description` | Text | `text` | Secondary IUCR description. |
| Location Description | `location_description` | Text | `text` | Categorical description of incident location; profile missing and variant values. |
| Arrest | `arrest` | Checkbox | `boolean` | Whether an arrest was indicated; not a clearance or conviction field. Validate nulls. |
| Domestic | `domestic` | Checkbox | `boolean` | Domestic-related indicator as defined by the source. Validate nulls. |
| Beat | `beat` | Text | `text` | Police beat identifier; preserve as a code and validate formatting. |
| District | `district` | Text | `text` | Police district identifier; preserve as a code and validate domain and missing values. |
| Ward | `ward` | Number | `smallint` | City Council ward; validate integer domain and historical comparability. |
| Community Area | `community_area` | Text | `smallint` | Chicago community area identifier; valid analytical range is 1–77 after parsing. |
| FBI Code | `fbi_code` | Text | `text` | FBI crime classification code; preserve as a code. |
| X Coordinate | `x_coordinate` | Number | `numeric` | Projected coordinate; coordinate reference and valid range require verification. |
| Y Coordinate | `y_coordinate` | Number | `numeric` | Projected coordinate; coordinate reference and valid range require verification. |
| Year | `year` | Number | `smallint` | Source-provided year; reconcile with parsed `date` year and document discrepancies. |
| Updated On | `updated_on` | Floating Timestamp | `timestamp` | Source record update timestamp; verify parsing and timezone convention. |
| Latitude | `latitude` | Number | `double precision` | Approximate latitude; mapping eligibility requires both latitude and longitude. |
| Longitude | `longitude` | Number | `double precision` | Approximate longitude; mapping eligibility requires both latitude and longitude. |
| Location | `location` | Point | staged as `text`; typed representation TBD | Combined portal point value; reconcile with latitude/longitude before selecting a database representation. |

## Planned derived fields

Derived fields are not implemented in Milestone 0. Later milestones may add fields such as calendar date parts, complete-period flags, coordinate-availability flags, and data-quality status fields only after formulas and lineage are documented. Source columns will not be silently overwritten.

## Data-quality checks reserved for later milestones

- Record and unique-ID counts
- Duplicate and null identifiers
- Timestamp parsing, minimum/maximum dates, and source-year reconciliation
- Boolean parsing and missing arrest/domestic indicators
- Community-area parse success and valid-range coverage
- Coordinate pair completeness, parse success, and approved validity checks
- Categorical nulls, whitespace, spelling variants, and classification changes
- Source update timestamps and extraction cutoff

No check above has been executed yet.
