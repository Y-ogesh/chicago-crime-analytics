# Metric Definitions

## Purpose

These definitions are the project contract for SQL, Python, Tableau, and narrative reporting. Changes require an explicit documentation update and must not be made silently. No metric has been calculated yet.

## Shared record scope

Unless a result explicitly says otherwise, the analytical population is the canonical typed crime table after load and documented quality checks. Each retained source record is keyed by the source `id`; the canonical table will enforce one row per `id`. The official source describes a row as a reported crime, with the important exception that murder records represent victims. Analyses must disclose this source convention.

Records lacking coordinates remain eligible for temporal, category, arrest-indicator, domestic-indicator, and other non-coordinate analyses when their required fields are valid. Geography-specific metrics apply their own eligibility rules and must report exclusions.

## Reported incident count

**Definition:** Number of records in the stated analytical scope.

**Canonical calculation:** `COUNT(*)` on the canonical one-row-per-`id` table after applying only the filters stated with the result.

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

**Definition:** Reported incident count grouped by the source community-area identifier for records whose community area is an integer from 1 through 77.

**Eligibility:** A community area is eligible for a reported comparison when it has a valid identifier in both compared periods. For year-over-year percentage change, a zero prior-year denominator produces an undefined percentage as described above; the area remains listed with counts and absolute change.

Missing, null, non-integer, and out-of-range community-area values are grouped separately as `Unknown/unassigned` for quality reporting and are excluded from named community-area rankings. Community-area availability does not imply coordinate availability, and coordinates must not be used to silently impute a community area unless a future, documented geospatial method is explicitly authorized.

## Geographic coverage percentage

**Definition:** Percentage of all in-scope analytical records that have both parseable, non-null latitude and longitude values and are therefore eligible for coordinate-based mapping.

**Formula:**

```text
100 * count(records with usable latitude and usable longitude)
    / count(all in-scope analytical records)
```

Both coordinates are required. Records with a missing or unparseable coordinate are `not coordinate-mappable`, remain in the denominator, and remain eligible for non-coordinate analyses. Coordinate values later found outside an approved validity rule must be separately flagged; that rule and its impact must be documented before exclusion. A zero overall denominator returns null.

Community-area coverage is a separate quality measure:

```text
100 * count(records with community_area integer 1 through 77)
    / count(all in-scope analytical records)
```

The two coverage percentages must not be substituted for one another.

## Full-year versus partial-year comparisons

### Complete calendar year

A year is eligible for annual comparison only when the authorized extract and validated canonical data cover January 1 through December 31 and the year is closed relative to the documented source-data cutoff. Coverage is assessed from the extraction metadata and validation results, not merely from the minimum and maximum incident timestamps.

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

