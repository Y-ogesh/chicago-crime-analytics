# Tableau Executive Overview — Page 1 Build Guide

## Status

The two Tableau-ready CSV sources, their PostgreSQL views, validation SQL, workbook generator, six worksheets, and Executive Overview dashboard are implemented. The generated workbook passed XML, source-reference, calculation/filter, PostgreSQL benchmark, Tableau Desktop load, visual-rendering, and filter-interaction checks. Executive Overview Page 1 is validated in Tableau Desktop. Milestone 9B remains in progress because the other three planned dashboard pages are not implemented.

## Generated workbook

The deliverable is:

```text
tableau/chicago_crime_analytics.twb
```

Rebuild the sources and workbook from the repository root with the project virtual environment active:

```bash
python scripts/export_tableau_data.py --profile page1
python scripts/generate_tableau_workbook.py
```

The generator is deterministic with respect to the source data and writes the workbook atomically. It verifies:

- well-formed Tableau workbook XML targeting workbook format `18.1` and the installed 2026.2 build;
- exactly two independent CSV connections plus the workbook parameter data source;
- all six required worksheet definitions and their dashboard zones;
- Year = 2025 and Crime Type = All Crime Types defaults, with the year displayed without a thousands separator;
- canonical selected-year, selected-crime-type, weighted-arrest, and weighted-domestic calculations;
- a parameter-aware top-10 category rule that still displays any specifically selected crime type;
- the annual trend intentionally omits only the selected-year filter;
- relative CSV paths resolve to existing validated files;
- manifest checksums, 93 annual/category rows, 1,116 month/category rows, 31 primary types, and 12 months for every year/type combination;
- annual/category versus monthly/category incident and indicator reconciliation;
- 2025 citywide and Theft KPI benchmarks.

Tableau Desktop Free Edition 2026.2.3 on Apple silicon completed `workspace.open-workbook`, dashboard layout, and worksheet model computation without workbook-scoped error or fatal log entries. The rendered dashboard was then tested at Year = 2025 under both All Crime Types and THEFT. All selected-year KPIs and charts updated; the yearly trend retained 2023–2025 by design; the parameter was restored to All Crime Types afterward. Tableau's Data menu exposed both independent sources, `Executive Category Year` and `Executive Month Category`; no blend or relationship was present.

## Tableau Desktop validation evidence

| Filter state | Reported incidents | Arrest percentage | Domestic percentage | Screenshot |
|---|---:|---:|---:|---|
| 2025 / All Crime Types | 238,086 | 16.1% | 19.0% | [Executive Overview — all crimes](../images/tableau/executive_overview_2025_all_crime_types.png) |
| 2025 / THEFT | 55,198 | 9.0% | 5.1% | [Executive Overview — Theft](../images/tableau/executive_overview_2025_theft.png) |

Both PNGs were exported by Tableau Desktop at 2,720 × 1,700 pixels from the fixed 1,360 × 850 dashboard. The displayed percentages use one decimal place; PostgreSQL validation retains full precision at 16.1139% and 19.0347% for all 2025 incidents, and 9.0420% and 5.1270% for 2025 Theft. The screenshots are evidence of rendered states, not additional analytical data sources.

## Open the generated workbook in Tableau Desktop

1. Keep the repository structure unchanged so the workbook's relative data paths continue to resolve.
2. Confirm these files exist:
   - `data/processed/tableau/page1/vw_tableau_crime_arrest_year.csv`
   - `data/processed/tableau/page1/vw_tableau_month_category.csv`
3. Open Tableau Desktop Free Edition.
4. Choose **File → Open** or press **Command–O**.
5. Select `tableau/chicago_crime_analytics.twb` from the repository and click **Open**.
6. If Tableau asks whether to update the workbook to the installed release, allow the update but save only after the dashboard has been checked. Do not replace or relocate either CSV.
7. Open the **Executive Overview** dashboard tab. Confirm both `Executive Category Year` and `Executive Month Category` appear as separate data sources; do not create a relationship, join, union, or blend.
8. Leave `Year` at `2025` and `Crime Type` at `All Crime Types`, then capture the full dashboard.
9. Change `Crime Type` to `THEFT`, confirm every selected-year sheet updates while the yearly trend still displays 2023–2025, and capture the full dashboard.
10. Reconcile the visible KPIs to the evidence table above. The repository screenshots document the accepted Page 1 states; repeat this check after any workbook-generator or source-data change.

## Exact Page 1 data sources

Page 1 uses exactly two independent CSV data sources:

| Tableau data source name | PostgreSQL view | CSV file | Grain | Rows |
|---|---|---|---|---:|
| `Executive Category Year` | `vw_tableau_crime_arrest_year` | `vw_tableau_crime_arrest_year.csv` | Complete calendar year × source primary type | 93 |
| `Executive Month Category` | `vw_tableau_month_category` | `vw_tableau_month_category.csv` | Calendar month × source primary type, including zero-count grid rows | 1,116 |

The first source supports the three KPIs, three-year trend, leading categories, and exact weighted arrest/domestic calculations. The second supports the monthly trend under the same Year and Crime Type selections. Do not join, relate, union, or blend these sources. Each worksheet uses only one source, which prevents fan-out and double counting.

`vw_tableau_executive_year` remains the independent PostgreSQL validation benchmark; it is not a third Tableau Page 1 source.

## Rebuild and validate PostgreSQL

From the repository root:

```bash
psql -d chicago_crime -X -v ON_ERROR_STOP=1 -P pager=off \
  -f sql/06_tableau_preparation.sql

psql -d chicago_crime -X -v ON_ERROR_STOP=1 -P pager=off \
  -f sql/07_tableau_page1_validation.sql
```

`sql/07_tableau_page1_validation.sql` runs inside a read-only transaction. It validates:

- 93 year/category rows and 1,116 month/category rows;
- a complete 12-month grid for every year/category combination;
- month/category rollups against year/category counts and indicator components;
- both source totals against the independent executive-year view;
- 2025 citywide benchmarks;
- 2025 Theft benchmarks at both annual and monthly grains.

## Generate only the two Page 1 CSVs

```bash
python scripts/export_tableau_data.py --profile page1
```

This writes:

```text
data/processed/tableau/page1/vw_tableau_crime_arrest_year.csv
data/processed/tableau/page1/vw_tableau_month_category.csv
data/processed/tableau/page1/manifest.json
```

The exporter uses environment variables or the Git-ignored `.env`, forces PostgreSQL transactions to read-only mode, applies deterministic ordering, rereads each CSV, checks its rows against PostgreSQL, and records byte sizes and SHA-256 checksums. The output directory is excluded from Git.

## Manual connection fallback — first CSV

From the Tableau start screen:

1. Under **Connect**, choose **Text file**.
2. Navigate to the repository and open:

   ```text
   data/processed/tableau/page1/vw_tableau_crime_arrest_year.csv
   ```

3. On the Data Source page, rename the source `Executive Category Year`.
4. Confirm the file appears once on the canvas. Do not add another table, join, union, or relationship.
5. Confirm field types:
   - `period_start`: Date
   - `crime_year`, ranks, previous year, and count fields: Number (Whole)
   - percentage fields: Number (Decimal)
   - `primary_type`: String
6. Open a new worksheet to confirm that Tableau recognizes the source.

## Manual connection fallback — second CSV

1. In the top menu choose **Data → New Data Source**.
2. Choose **Text file**.
3. Open:

   ```text
   data/processed/tableau/page1/vw_tableau_month_category.csv
   ```

4. Rename the source `Executive Month Category`.
5. Do not connect it to the first source.
6. Confirm field types:
   - `month_start`: Date
   - `crime_year`, `crime_month`, `crime_quarter`, counts, and denominators: Number (Whole)
   - percentages and `trailing_three_month_average`: Number (Decimal)
   - `month_name`, `season`, and `primary_type`: String

## Create shared parameter controls

Parameters are workbook-wide and safely control both independent sources without joining them.

### Year parameter

```text
Name: pSelectedYear
Data type: Integer
Allowable values: List
Values: 2023, 2024, 2025
Current value: 2025
Display format: no thousands separator
```

### Crime Type parameter

```text
Name: pCrimeType
Data type: String
Allowable values: List
Current value: All Crime Types
```

Add `All Crime Types`, then use **Add values from → Executive Category Year → primary_type** to add the 31 source categories. If the edition does not show **Add values from**, copy the distinct values from the `primary_type` column in the 93-row CSV. Do not manually regroup or rename source categories.

Show both parameter controls and title them `Year` and `Crime Type`.

## Create filters in both data sources

Create these two calculated fields separately in `Executive Category Year` and `Executive Month Category`:

```text
Selected Year Filter
[crime_year] = [pSelectedYear]
```

```text
Selected Crime Type Filter
[pCrimeType] = "All Crime Types"
OR [primary_type] = [pCrimeType]
```

Place the applicable fields on Filters and select `True`. Because the calculations exist in both sources and reference the same workbook parameters, Year and Crime Type control all selected-year Page 1 worksheets without a cross-source join.

The annual trend intentionally uses only `Selected Crime Type Filter`; it omits `Selected Year Filter` so all three complete years remain visible.

## Create measures in Executive Category Year

```text
Reported Incidents
SUM([reported_incident_count])
```

```text
Weighted Arrest Percentage
IF SUM([arrest_indicator_denominator]) = 0 THEN NULL
ELSE
    100.0 * SUM([arrest_count])
    / SUM([arrest_indicator_denominator])
END
```

```text
Weighted Domestic Incident Percentage
IF SUM([domestic_indicator_denominator]) = 0 THEN NULL
ELSE
    100.0 * SUM([domestic_count])
    / SUM([domestic_indicator_denominator])
END
```

```text
Show Top 10
INDEX() <= 10
```

Format both percentage calculations as **Number (Custom)** with one decimal place and a `%` suffix. Do not choose Tableau's Percentage format because these calculations already multiply by 100. Use four decimals in validation tooltips when practical.

## Build the six worksheets

### E1 — Total Incidents

1. Select `Executive Category Year` and create `E1 Total Incidents`.
2. Set Marks to **Text**.
3. Place `Reported Incidents` on Text.
4. Add `Selected Year Filter = True`.
5. Add `Selected Crime Type Filter = True`.
6. Format with a thousands separator and zero decimals.
7. Title: `Reported Incidents`.

### E2 — Arrest Percentage

1. Duplicate E1 and rename it `E2 Arrest Percentage`.
2. Replace Text with `Weighted Arrest Percentage`.
3. Add `SUM(arrest_count)` and `SUM(arrest_indicator_denominator)` to Detail.
4. Tooltip: numerator, denominator, percentage, and `This is not a clearance or conviction rate.`

### E3 — Domestic Incident Percentage

1. Duplicate E2 and rename it `E3 Domestic Percentage`.
2. Replace Text with `Weighted Domestic Incident Percentage`.
3. Replace Detail with `SUM(domestic_count)` and `SUM(domestic_indicator_denominator)`.
4. Identify the measure as the source domestic indicator percentage.

### E4 — Yearly Crime Trend

1. Select `Executive Category Year` and create `E4 Yearly Crime Trend`.
2. Place `crime_year` on Columns as a discrete whole number.
3. Place `SUM(reported_incident_count)` on Rows.
4. Set Marks to **Line** and enable markers.
5. Add only `Selected Crime Type Filter = True`.
6. Do not add the selected-year filter.
7. Sort years ascending and display exact counts in tooltips.

### E5 — Leading Crime Categories

1. Select `Executive Category Year` and create `E5 Leading Crime Categories`.
2. Place `primary_type` on Rows.
3. Place `SUM(reported_incident_count)` on Columns.
4. Add `Selected Year Filter = True` and `Selected Crime Type Filter = True`.
5. Sort descending by count.
6. Add `Show Top 10 = True` to Filters.
7. Edit its table calculation to compute using `primary_type`.
8. Set Marks to **Bar** and show count labels.
9. Add year, primary type, count, annual share, and category rank to the tooltip.

With `All Crime Types`, E5 shows the ten leaders. With a specific category selected, it shows the selected category rather than returning a misleading citywide ranking.

### E6 — Monthly Trend

1. Select `Executive Month Category` and create `E6 Monthly Trend`.
2. Add `Selected Year Filter = True` and `Selected Crime Type Filter = True`.
3. Place `month_start` on Columns as a continuous Month date.
4. Place `SUM(reported_incident_count)` on Rows.
5. Set Marks to **Line** and enable markers.
6. Sort chronologically by `month_start`.
7. Add `month_name`, `reported_incident_count`, and `trailing_three_month_average` to the tooltip.
8. Title: `Monthly Reported-Incident Trend`.

The complete month/category grid ensures 12 marks for every year and crime-type selection, including zero-count months if any occur.

## Assemble Page 1

Create dashboard `1 Executive Overview`:

- Fixed size: 1,360 × 850 pixels.
- Header: `Chicago Crime Analytics — Executive Overview`.
- Left rail: `pSelectedYear` and `pCrimeType` parameter controls.
- Top row: E1, E2, E3.
- Middle row: E4 and E5.
- Bottom row: E6.
- Source label: `Source extract: Sep 25, 2026 | Incident dates: Jan 1, 2023–Dec 31, 2025 | Complete years`.
- Footer: `Reported incident counts are not population-normalized crime rates. Results are descriptive and do not establish causation. Arrest percentage is not a clearance or conviction rate.`

Do not add a relationship, join, blend, or dashboard filter action between the two CSV sources. The shared parameter controls provide the intended synchronized behavior.

## Validation benchmarks

### 2025 and All Crime Types

| Metric | Expected value |
|---|---:|
| Reported incidents | 238,086 |
| Arrest numerator / denominator | 38,365 / 238,086 |
| Arrest percentage | 16.1139% |
| Domestic numerator / denominator | 45,319 / 238,086 |
| Domestic incident percentage | 19.0347% |

Annual trend: 263,844 in 2023; 259,633 in 2024; 238,086 in 2025.

The 2025 category leaders begin with Theft 55,198; Battery 42,660; Criminal Damage 26,248; Assault 21,601; and Motor Vehicle Theft 17,257. The 12 monthly marks sum to 238,086; July is the largest month at 22,710.

### 2025 and Theft

| Metric | Expected value |
|---|---:|
| Reported incidents | 55,198 |
| Arrest numerator / denominator | 4,991 / 55,198 |
| Arrest percentage | 9.0420% |
| Domestic numerator / denominator | 2,830 / 55,198 |
| Domestic incident percentage | 5.1270% |

The Theft annual trend is 57,526 in 2023, 60,558 in 2024, and 55,198 in 2025. The 2025 monthly Theft marks are January 4,316; February 3,935; March 4,548; April 4,500; May 4,807; June 4,941; July 5,404; August 5,001; September 4,549; October 4,794; November 4,241; and December 4,162. They sum to 55,198.

## Completion evidence recorded

1. Tableau-exported full-page PNG with 2025 and All Crime Types: `images/tableau/executive_overview_2025_all_crime_types.png`.
2. Tableau-exported full-page PNG with 2025 and THEFT: `images/tableau/executive_overview_2025_theft.png`.
3. Tableau's Data menu exposed exactly `Executive Category Year` and `Executive Month Category`; blend and replace-source commands remained disabled.
4. Changing Crime Type updated every intended sheet and left the annual trend at three complete-year marks.
5. The workbook remains at `tableau/chicago_crime_analytics.twb`, and the control was restored to its All Crime Types default after validation.

This evidence supports describing Executive Overview Page 1 as implemented and validated. It does not support claiming that the other three pages or the full four-page Milestone 9B workbook are complete.
