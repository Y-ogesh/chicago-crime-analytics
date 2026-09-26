# Metric Definitions

## Purpose

These definitions are the project contract for SQL, Python, Tableau, and narrative reporting. Changes require an explicit documentation update and must not be made silently. Milestone 4 implemented the canonical record-level scope and validation flags; Milestones 5 and 6 applied these definitions to executed core and advanced SQL findings.

## Shared record scope

Unless a result explicitly says otherwise, the analytical population is `public.clean_chicago_crimes`. Each retained source record is keyed by `source_id`, copied from the official source `id`; the primary key enforces one row per source ID. Deterministic source-ID deduplication is applied during the rebuild, but removed zero records from the current unique-ID extract. The official source describes a row as a reported crime, with the important exception that murder records represent victims. Analyses must disclose this source convention.

Records lacking coordinates remain eligible for temporal, category, arrest-indicator, domestic-indicator, and other non-coordinate analyses when their required fields are valid. Geography-specific metrics apply their own eligibility rules and must report exclusions.

## Reported incident count

**Definition:** Number of records in the stated analytical scope.

**Canonical calculation:** `COUNT(*)` on `clean_chicago_crimes` after applying only the filters stated with the result.

**Rules:**

- Label the measure `reported incident count` or `reported incidents`, not total crime and not a crime rate.
- Do not count duplicate source identifiers more than once in the canonical table; duplicates, if found, require a documented resolution.
- State the date range, geography, and category filters used.
- Do not require coordinates unless the output itself requires coordinate mapping.

## Arrest percentage

**Definition:** Percentage of in-scope records with `arrest = TRUE` among records whose arrest indicator is non-null.

**Formula:**

```text
100 * count(records where arrest is TRUE)
    / count(records where arrest is TRUE or FALSE)
```

Null or unparseable arrest indicators are excluded from the denominator and their count must be reported as a data-quality exclusion. A zero denominator returns null, not zero. Round only for display after calculation. This is an **arrest percentage**, not a clearance, prosecution, or conviction rate; the field does not establish the timing or final disposition of an arrest.

## Domestic incident percentage

**Definition:** Percentage of in-scope records with `domestic = TRUE` among records whose domestic indicator is non-null.

**Formula:**

```text
100 * count(records where domestic is TRUE)
    / count(records where domestic is TRUE or FALSE)
```

Null or unparseable indicators are excluded from the denominator and reported. A zero denominator returns null. The metric describes the source domestic-related indicator and must not be generalized to unreported domestic violence.

## Year-over-year percentage change

**Definition:** Percentage change in reported incident count from a prior complete calendar year to the immediately following complete calendar year for the same scope.

**Formula:**

```text
100 * (current_year_count - prior_year_count) / prior_year_count
```

**Rules:**

- Both periods must be January 1 through December 31 and pass the complete-year rule below.
- Filters and category/geography eligibility must be identical in both years.
- If the prior-year count is zero, percentage change is null/undefined; report the two counts and absolute change.
- Do not substitute a non-adjacent year without explicitly renaming and documenting the comparison.
- Preserve full precision for calculation and round only the displayed value.
- A change is descriptive and must not be interpreted as causal.

## Community-area incident count

**Definition:** Reported incident count grouped by `clean_chicago_crimes.community_area` for rows where `community_area_eligible_flag = TRUE`. The clean field is copied from the source only when it is an integer from 1 through 77; the unchanged input remains available as `source_community_area`.

**Eligibility:** A community area is eligible for a reported comparison when it has a valid identifier in both compared periods. For year-over-year percentage change, a zero prior-year denominator produces an undefined percentage as described above; the area remains listed with counts and absolute change.

Missing, null, non-integer, and out-of-range community-area values are grouped separately as `Unknown/unassigned` for quality reporting and are excluded from named community-area rankings. Community-area availability does not imply coordinate availability, and coordinates must not be used to silently impute a community area unless a future, documented geospatial method is explicitly authorized.

### Community-area year-over-year ranking rule

`vw_community_area_yoy` returns every official community area for each adjacent complete-year comparison. Absolute-change and absolute-decrease ranks include all 77 areas because a record-count change remains interpretable at any baseline volume. Percentage-change and percentage-decrease ranks require at least **500 reported incidents in the prior year**. The threshold was selected before ranking because one incident then changes the percentage by no more than 0.2 percentage points; it retained 75 of 77 areas for 2023–2024 and 75 of 77 for 2024–2025 in the current extract. Areas below the threshold remain in the view with counts, absolute change, and calculated percentage, but their percentage ranks are null.

The two ranking concepts must remain distinct:

- `percentage_decrease_rank = 1` identifies the largest proportional decrease among threshold-eligible areas.
- `absolute_decrease_rank = 1` identifies the largest decrease in reported incident records among all 77 areas.

Community-area names come from the official City of Chicago [Boundaries - Community Areas (current)](https://data.cityofchicago.org/Facilities-Geographic-Boundaries/Boundaries-Community-Areas-current-/cauq-8yn6/about) lookup (map ID `cauq-8yn6`, underlying dataset ID `igwz-8jzy`). Names provide labels only; the source crime record's community-area identifier determines analytical membership.

## Geographic coverage percentage

**Definition:** Percentage of all in-scope analytical records with `coordinate_mappable_flag = TRUE`.

**Formula:**

```text
100 * count(records where coordinate_mappable_flag is TRUE)
    / count(all in-scope analytical records)
```

Both coordinates are required. The Milestone 4 approved validity rule defines a record as coordinate-mappable only when latitude and longitude are both present, pass global latitude/longitude limits, are not the pair `(0,0)`, and fall within the documented City map rectangular envelope. `coordinate_available_flag`, nullable `coordinate_valid_flag`, and nullable `within_city_bounds_flag` preserve the component results. The envelope is a plausibility screen, not a municipal point-in-polygon test. Records without a coordinate pair remain in the denominator and remain eligible for non-coordinate analyses. Any future change to this rule requires an explicit definition and impact update. A zero overall denominator returns null.

This implements the previously documented provision for an approved coordinate-validity rule. In the current extract, all 754,866 available coordinate pairs passed both validity screens, so adding the rule excluded zero additional records beyond the 6,697 missing pairs.

Community-area coverage is a separate quality measure:

```text
100 * count(records with community_area integer 1 through 77)
    / count(all in-scope analytical records)
```

The two coverage percentages must not be substituted for one another.

## Temporal feature definitions

All temporal features are derived from the timezone-unqualified source incident timestamp stored as `crime_timestamp`:

- `crime_date`: timestamp cast to calendar date.
- `crime_year`: four-digit calendar year.
- `crime_month`: integer 1–12.
- `month_name`: English month name mapped from `crime_month`.
- `crime_quarter`: calendar quarter 1–4.
- `day_of_week_num`: ISO weekday number, Monday=1 through Sunday=7.
- `day_of_week`: English weekday name mapped from `day_of_week_num`.
- `hour_of_day`: integer hour 0–23.
- `time_of_day`: `Overnight` for 00:00–05:59, `Morning` for 06:00–11:59, `Afternoon` for 12:00–17:59, and `Evening` for 18:00–23:59.
- `season`: meteorological `Winter` for December–February, `Spring` for March–May, `Summer` for June–August, and `Fall` for September–November.
- `weekend_flag`: true for Saturday or Sunday (`day_of_week_num` 6 or 7), false otherwise.

These definitions are database-constrained and must be reproduced exactly in Python and Tableau. The source says incident timestamps can be estimated, and no timezone or daylight-saving conversion is inferred.

## Full-year versus partial-year comparisons

### Complete calendar year

A year is eligible for annual comparison only when the authorized extract and validated `clean_chicago_crimes` data cover January 1 through December 31 and the year is closed relative to the documented source-data cutoff. Coverage is assessed from the extraction metadata and validation results, not merely from the minimum and maximum incident timestamps.

### Partial year or partial period

- The current/open year and any incompletely extracted year are labeled `partial` with exact start date, end date, and data cutoff.
- Partial-year totals are not compared with complete-year totals using the annual year-over-year metric.
- A matched-period comparison may be reported separately only when both years use identical month/day boundaries and the label states `matched-period change`, not full-year year-over-year change.
- Rolling periods must state their exact boundaries and are not called calendar years.
- Late reporting and source revisions remain limitations even for periods classified as complete.

## Display and validation conventions

- Store and validate counts as integers and percentages at full available precision.
- Apply display rounding consistently only in the presentation layer.
- Every result must carry or clearly reference its filters, period, data cutoff, and denominator.
- SQL, Python, Tableau, and README values must reconcile before publication.
