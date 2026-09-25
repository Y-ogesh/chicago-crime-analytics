# Data Quality Assessment

## Assessment scope

This report records the Milestone 3 read-only assessment of `public.raw_chicago_crimes`. The assessment was executed on September 25, 2026 against PostgreSQL 14.20 and the immutable 2023–2025 extract acquired from the City of Chicago **Crimes - 2001 to Present** dataset (`ijzp-q8t2`). It profiles source quality and proposes treatments; it does not clean, update, delete, or exclude source records.

The reusable query suite is [`sql/02_data_quality.sql`](../sql/02_data_quality.sql). It begins with `BEGIN TRANSACTION READ ONLY`, stops on the first SQL error, and completed through `COMMIT`. All percentages use 761,563 raw records as the denominator and are rounded to four decimal places.

## Baseline and coverage

| Measure | Observed value |
|---|---:|
| Total records | 761,563 |
| Distinct source IDs | 761,563 |
| Minimum incident timestamp | 2023-01-01 00:00:00 |
| Maximum incident timestamp | 2025-12-31 23:58:00 |
| Complete calendar years | 2023, 2024, 2025 |
| Records with latitude and longitude | 754,866 (99.1206%) |
| Records without latitude and longitude | 6,697 (0.8794%) |

Missing coordinates do **not** make an incident unusable. All 761,563 records remain eligible for applicable non-map analyses. Only the 6,697 records without a coordinate pair require exclusion from point-based mapping, with geographic coverage reported alongside map results.

## Meaningful issues and proposed treatments

No treatment in this table has been implemented. Every raw row and value remains unchanged.

| Observed issue | Affected rows | Percent | Analytical impact | Proposed treatment for a future cleaned layer | Retain? | Validation query |
|---|---:|---:|---|---|---|---|
| Repeated case numbers: 64 case-number values occur on 138 rows | 138 | 0.0181% | `case_number` cannot be used as a row key or assumed to identify duplicate source rows. | Use source `id` as the record key. Preserve case number for grouping and investigate context before any case-level analysis. | Yes, all rows | Q02, Q02b |
| Repeated substantive fingerprints occur only among `HOMICIDE` records | 34 | 0.0045% | Seventeen apparent pairs match across the profiled analytical fields, but still have unique source IDs. The City notes that murder rows represent victims, so automated row deletion could undercount victims. | Do not deduplicate. Retain source-ID-level rows and document the source convention in homicide analyses. | Yes, all rows | Q02b, Q02c |
| Missing location description | 3,947 | 0.5183% | Location-category breakdowns would otherwise omit these incidents or produce an unlabeled null group. | Preserve null in raw; expose an explicit `Unknown / not reported` analytical label without altering the source field. | Yes | Q08 |
| Missing latitude/longitude, projected coordinates, and location point | 6,697 | 0.8794% | These records cannot appear on point maps, but remain usable for temporal, category, arrest, domestic, and any valid administrative-geography analysis. | Derive a coordinate-availability flag; exclude only from coordinate-dependent outputs and publish coverage. | Yes | Q06, Q08 |
| Missing community area | 35 | 0.0046% | Cannot be assigned to an eligible named community area for area-level rankings or year-over-year comparisons. | Preserve null and classify as `Unknown / unassigned`; exclude only from community-area outputs requiring values 1–77. | Yes | Q05, Q05b, Q08 |
| Community area value `0`, outside the documented 1–77 domain | 1,032 | 0.1355% | Not eligible for named community-area analysis and would create a false 78th area if treated as valid. | Preserve `0` in raw and classify as `Unknown / unassigned`; do not impute an area without an authoritative spatial rule. | Yes | Q05, Q05b |
| Missing ward | 4 | 0.0005% | Unavailable for ward-level grouping. | Preserve null and classify as `Unknown / unassigned` in ward outputs. | Yes | Q05, Q05b, Q08 |
| Ward value `0`, outside the documented 1–50 domain | 1,032 | 0.1355% | Not a valid numbered ward and would distort ward cardinality. | Preserve `0` in raw and classify as `Unknown / unassigned`; do not impute without evidence. | Yes | Q05, Q05b |
| District code `16` is not in the three-character source format | 1 | 0.0001% | It represents the same numeric code as current district `016`, but prevents direct text joins. | In a future derived field only, left-pad verified one-to-three-digit numeric codes to three characters; preserve raw `district`. | Yes | Q04c, Q04d |
| District code `061` is absent from the current official district reference | 1,020 | 0.1339% | Direct joining to the current district lookup leaves these records unmatched. A current-boundary reference may not explain special or historical source codes. | Preserve and classify as `Non-current / unmapped` pending authoritative code documentation. Do not silently remap or discard. | Yes | Q04c, Q04d |

The district reference check used the City of Chicago [current police district boundaries](https://data.cityofchicago.org/Public-Safety/Boundaries-Police-Districts-current-/fthy-xz3r/about), whose underlying data identifies current district codes. This is a current-reference consistency check, not proof that every unmatched source code is erroneous.

## Checks with no observed issue

| Check | Affected rows | Percent | Validation query |
|---|---:|---:|---|
| Duplicate source IDs | 0 | 0.0000% | Q02 |
| Missing source, typed, or update dates | 0 | 0.0000% | Q03 |
| Nonstandard source date strings | 0 | 0.0000% | Q03 |
| Source year differing from incident-date year | 0 | 0.0000% | Q03 |
| Missing primary crime type | 0 | 0.0000% | Q04 |
| Outer whitespace in tested categorical/code fields | 0 | 0.0000% | Q04 |
| IUCR codes associated with multiple primary types in this extract | 0 | 0.0000% | Q04b |
| Missing district or beat | 0 | 0.0000% | Q05 |
| Partial latitude/longitude or projected-coordinate pair | 0 | 0.0000% | Q06 |
| Globally invalid, zero, or outside-screen coordinates among present pairs | 0 | 0.0000% | Q06 |
| Latitude/longitude versus projected-coordinate presence mismatch | 0 | 0.0000% | Q06 |
| Missing arrest or domestic indicators | 0 | 0.0000% | Q08 |

The coordinate plausibility screen checked global latitude/longitude limits and the rectangular envelope published with the City's map data. It is not a point-in-polygon test and therefore does not independently prove that every point lies within the municipal boundary. Observed coordinates ranged from 41.644589713 to 42.022558955 latitude and -87.939732936 to -87.524529378 longitude.

## Indicator distributions

These distributions are descriptive validation, not quality defects. `arrest = true` supports an **arrest percentage** only; it is not a clearance or conviction measure.

| Indicator | Value | Records | Percent |
|---|---|---:|---:|
| Arrest | False | 655,088 | 86.0189% |
| Arrest | True | 106,475 | 13.9811% |
| Domestic | False | 621,320 | 81.5848% |
| Domestic | True | 140,243 | 18.4152% |

## Records by complete calendar year

| Year | Records | Percent of extract |
|---:|---:|---:|
| 2023 | 263,844 | 34.6451% |
| 2024 | 259,633 | 34.0921% |
| 2025 | 238,086 | 31.2628% |

All three years are complete under the project's calendar-year rule. These totals are quality and coverage evidence, not a year-over-year finding; change calculations remain a future milestone.

## Category cardinality and consistency

| Field | Distinct non-null values |
|---|---:|
| Primary type | 31 |
| Description | 337 |
| Location description | 142 |
| IUCR | 359 |
| FBI code | 26 |
| District | 25 |
| Beat | 276 |
| Ward | 51 |
| Community area | 78 |

The 51 ward values and 78 community-area values include the invalid analytical value `0`. Raw and uppercased/trimmed cardinality both equal 31 for primary type and 142 for location description, so the tested normalization did not reveal case or outer-whitespace variants. This does not establish semantic equivalence across every category or across future source refreshes.

## Null and blank-field profile

Nonzero missing counts were limited to location description (3,947), latitude (6,697), longitude (6,697), X coordinate (6,697), Y coordinate (6,697), location point (6,697), community area (35), and ward (4). The other 14 imported source fields had zero null or blank values: `id`, `case_number`, `date`, `block`, `iucr`, `primary_type`, `description`, `arrest`, `domestic`, `beat`, `district`, `fbi_code`, `year`, and `updated_on`.

## Proposed cleaning rules — not implemented

1. Keep `id` as the canonical incident-record key and never delete rows solely because `case_number` or a substantive fingerprint repeats.
2. Preserve every source column in the raw layer. Add normalized values only as separately named, lineage-documented derived fields.
3. Retain all incidents for analyses that do not require a missing field. Apply field-specific eligibility rather than a global complete-case filter.
4. Represent missing categorical values with an explicit analytical label while preserving source nulls.
5. Treat community areas 1–77 and wards 1–50 as valid numbered domains. Classify null and `0` as unknown/unassigned; do not impute during generic cleaning.
6. Left-pad verified numeric district codes for a derived join key, while preserving raw values. Keep codes absent from the chosen reference as unmapped until authoritative documentation supports a mapping.
7. Derive separate flags for coordinate-pair presence and coordinate validity. Exclude records only from analyses that require point coordinates and disclose coverage.
8. Retain source booleans without recoding semantics. Calculate arrest and domestic percentages using all eligible incidents in the selected scope as the denominator.
9. Retain source timestamps as loaded. Re-run date format, null, and date/year consistency checks after every refresh.
10. Version and test any future category mappings; do not silently combine crime types or location descriptions.

## Validation query index

| Query | Purpose |
|---|---|
| Q01 | Dataset baseline, ID count, and date coverage |
| Q02–Q02c | Duplicate IDs, repeated case numbers, and repeated substantive fingerprints |
| Q03 | Missing, malformed, and inconsistent dates |
| Q04–Q04d | Crime-type completeness, categorical formatting, IUCR consistency, and district-reference checks |
| Q05–Q05b | Missing and invalid administrative geography |
| Q06–Q06b | Coordinate completeness, plausibility, cross-field consistency, and ranges |
| Q07 | Arrest and domestic indicator distributions |
| Q08 | Null and blank profile across all imported source fields |
| Q09 | Records by complete calendar year |
| Q10 | Category cardinality |
| Q11 | Full primary-type distribution |

Execute the complete suite with:

```bash
psql -d chicago_crime -X -v ON_ERROR_STOP=1 -P pager=off \
  -f sql/02_data_quality.sql
```

## Limitations

- The source contains reported crimes, not all crime, and records may be updated or reclassified after extraction.
- The City states that murder rows represent victims; record-level and case-level counts can therefore answer different questions.
- Locations are approximate for privacy. Coordinate presence or plausibility does not establish positional accuracy.
- The current district reference does not by itself explain historical, administrative, or special-purpose codes.
- A rectangular coordinate envelope is a screening rule, not municipal-boundary validation.
- This assessment proposes treatments but intentionally does not implement or validate a cleaned analytical layer.
