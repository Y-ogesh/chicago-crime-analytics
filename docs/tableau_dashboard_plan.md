# Tableau Dashboard Plan

## Milestone 9A status and scope

Tableau data preparation is complete. The PostgreSQL presentation layer and optional CSV extracts described below were created and validated on September 26, 2026. The four-page Tableau workbook is **planned but has not been created or manually tested**. Dashboard behavior in this document is therefore a build specification and acceptance checklist, not a claim of completed functionality.

The dashboard will use the official City of Chicago Crimes dataset (`ijzp-q8t2`) extract acquired September 25, 2026. Its analytical scope is 761,563 reported-incident records dated January 1, 2023 through December 31, 2025. All three years are complete calendar years. Counts are reported incidents, not population-normalized crime rates. Arrest percentages are source-indicator percentages, not clearance, prosecution, or conviction rates.

## Prepared data layer

Run [`sql/06_tableau_preparation.sql`](../sql/06_tableau_preparation.sql) after the advanced views in `sql/05_advanced_analysis.sql`. It creates nine non-materialized, page-oriented views and executes fail-fast reconciliations in one transaction.

| PostgreSQL view | Grain | Validated rows | Primary page |
|---|---|---:|---|
| `vw_tableau_executive_year` | Complete calendar year | 3 | Executive Overview |
| `vw_tableau_community_area_year` | Year × all 77 official community areas | 231 | Geographic Crime Patterns |
| `vw_tableau_district_year` | Year × observed source district code | 72 | Geographic Crime Patterns |
| `vw_tableau_area_category_year` | Year × community area × observed primary type | 5,395 | Geographic Crime Patterns |
| `vw_tableau_coordinate_density` | Year × 0.01-degree coordinate cell | 2,127 | Geographic Crime Patterns |
| `vw_tableau_monthly_patterns` | Calendar month | 36 | Temporal and Seasonal Patterns |
| `vw_tableau_time_patterns` | Year × ISO weekday × hour | 504 | Temporal and Seasonal Patterns |
| `vw_tableau_location_time` | Fixed full-period top-ten location descriptions × time band | 40 | Temporal and Seasonal Patterns |
| `vw_tableau_crime_arrest_year` | Year × source primary type | 93 | Crime and Arrest Analysis |

The existing `vw_geographic_crime_points` view remains available as an optional 754,866-row point layer. The planned dashboard should default to `vw_tableau_coordinate_density`, which is much smaller and makes its descriptive binning explicit. Point records are not required for the four planned pages.

### Canonical Tableau calculations

Create the following calculated fields only where a source contains the listed numerator and denominator. Do not average row-level percentages across multiple rows.

```text
Reported Incidents
SUM([reported_incident_count])

Weighted Arrest Percentage
IF SUM([arrest_indicator_denominator]) = 0 THEN NULL
ELSE 100.0 * SUM([arrest_count]) / SUM([arrest_indicator_denominator])
END

Weighted Domestic Incident Percentage
IF SUM([domestic_indicator_denominator]) = 0 THEN NULL
ELSE 100.0 * SUM([domestic_count]) / SUM([domestic_indicator_denominator])
END

Coordinate Coverage Percentage
IF SUM([reported_incident_count]) = 0 THEN NULL
ELSE 100.0 * SUM([coordinate_mappable_count]) / SUM([reported_incident_count])
END

Coordinate Excluded Count
SUM([reported_incident_count]) - SUM([coordinate_mappable_count])

Community Area Excluded Count
SUM([reported_incident_count]) - SUM([community_area_eligible_count])

Selected Year Filter
[crime_year] = [pSelectedYear]
```

Create the whole-number parameter `pSelectedYear` with allowable values 2023, 2024, and 2025 and a default of 2025. Use database-supplied `percentage_change`, rank, share, and rolling-average fields where provided. Display percentages to one decimal place on dashboards and four decimal places in validation tooltips. Preserve full database precision for calculations.

## Connection option A — PostgreSQL

PostgreSQL is the preferred development connection because it preserves data types and lets Tableau refresh the small aggregate views directly.

1. Rebuild and validate the presentation layer from the repository root:

   ```bash
   psql -d chicago_crime -X -v ON_ERROR_STOP=1 -P pager=off \
     -f sql/06_tableau_preparation.sql
   ```

2. Install Tableau's PostgreSQL driver if Tableau displays a driver requirement. Use Tableau's **Connect → To a Server → PostgreSQL** connector.
3. Enter the server and port from `POSTGRES_HOST` and `POSTGRES_PORT`; for a local socket installation use `localhost` and `5432` if TCP is enabled. Enter `chicago_crime` or the value of `POSTGRES_DB` as the database.
4. Use a read-only database account. Do not save a password in the repository or publish embedded credentials. A database administrator can grant a dedicated role access with:

   ```sql
   GRANT CONNECT ON DATABASE chicago_crime TO tableau_reader;
   GRANT USAGE ON SCHEMA public TO tableau_reader;
   GRANT SELECT ON public.vw_tableau_executive_year,
       public.vw_tableau_community_area_year,
       public.vw_tableau_district_year,
       public.vw_tableau_area_category_year,
       public.vw_tableau_coordinate_density,
       public.vw_tableau_monthly_patterns,
       public.vw_tableau_time_patterns,
       public.vw_tableau_location_time,
       public.vw_tableau_crime_arrest_year TO tableau_reader;
   ```

   Role creation and password policy are environment-specific and intentionally not scripted here.
5. Select schema `public`. Create **one Tableau data source per view** and name it after the view without the `vw_tableau_` prefix. Do not physically join these aggregate views: their grains differ and a join can multiply measures.
6. Choose **Extract** for the nine aggregate sources. Use a full refresh after rerunning the SQL. A live connection is also acceptable for local development. Keep `vw_geographic_crime_points` separate and use it only if a record-level point view is explicitly added later.
7. Assign geographic roles: `cell_latitude` → Latitude and `cell_longitude` → Longitude. Keep `community_area_name` as a text dimension unless an official boundary spatial file is added; do not rely on ambiguous automatic geocoding.

Official Tableau references: [PostgreSQL connector](https://help.tableau.com/current/pro/desktop/en-us/examples_postgresql.htm), [extract data](https://help.tableau.com/current/pro/desktop/en-us/extracting_data.htm), and [filter actions](https://help.tableau.com/current/pro/desktop/en-us/actions_filter.htm).

## Connection option B — documented CSV extracts

For a portable build without a live database connection:

```bash
python scripts/export_tableau_data.py
```

The script uses environment variables or a Git-ignored `.env`, forces PostgreSQL transactions to read-only mode, orders every export deterministically, rereads each CSV, reconciles its rows to the source view, and writes checksums and metadata to `data/processed/tableau/manifest.json`. It generated nine non-empty CSV files in the current validation run. The entire directory is ignored by Git.

In Tableau, choose **Connect → To a File → Text file** and add each required CSV as a separate data source. Confirm that year/order fields are whole numbers, dates are dates, counts are whole numbers, percentages are decimal numbers, and latitude/longitude are geographic decimal numbers. Do not union or join files with different grains.

## Global dashboard conventions

- Fixed dashboard size: 1,360 × 850 pixels; tiled layout with a consistent header, left filter rail, main canvas, and footer.
- Navigation: four labeled page buttons in the same position on every page.
- Default year: 2025, the latest complete year. Trend charts may show all three years even when summary sheets use a single-year selection.
- Data cutoff label: `Source extract: Sep 25, 2026 | Incident dates: Jan 1, 2023–Dec 31, 2025 | Complete years`.
- Required footer: `Reported incident counts are not population-normalized crime rates. Results are descriptive and do not establish causation.`
- Geographic footer addition: `Coordinate density excludes 6,697 records without mappable coordinates and is not a statistical hotspot test or a measure of individual risk.`
- Arrest footer addition: `Arrest percentage is the share of records marked arrest=true; it is not a clearance or conviction rate.`
- Missing values display as `Not available`, never zero. Undefined percentage changes caused by a zero or absent prior-year denominator remain null.
- Year labels are numeric and chronologically sorted. Month uses `month_start`; weekday uses `day_of_week_num`; time band uses the documented order Overnight, Morning, Afternoon, Evening.
- Dashboard filters use **Apply to Worksheets → Selected Worksheets**. Cross-source filters must be explicitly mapped by identically defined fields; do not assume a filter automatically controls unrelated data sources.

### Manual workbook build sequence

1. Create a workbook and add the nine sources listed above, using either PostgreSQL extracts or the nine documented CSVs. Keep every source separate.
2. Create `pSelectedYear` and the canonical calculations. Add `Selected Year Filter = True` to single-year sheets. Use a parameter action on E5 so selecting a year changes `pSelectedYear`; clearing the selection leaves the current parameter value unchanged.
3. Build worksheets E1–E6, G1–G5, T1–T5, and C1–C5 from the field specifications below. Add the required source/definition text to each caption before assembling dashboards.
4. Create four dashboards at 1,360 × 850 and add the common header, year control, page navigation, filter rail, limitation footer, and reset control.
5. Add a custom-field filter action from G2 to G3/G4 mapping `community_area` to `community_area`. Clearing the selection must show all values. Add a same-source filter action from T3 to T4 using weekday/hour, and from C1 to C2–C5 using `primary_type`.
6. Add navigation objects targeting the other three dashboards. Test every destination and keep the current page visually selected.
7. Use **Revert** as the reset control during development. If the workbook is published later, test that the published reset behavior restores `pSelectedYear = 2025` and clears all mark selections.
8. Run the dashboard-level validation checklist before saving screenshots or marking Milestone 9B complete.

## Page 1 — Executive Overview

Default source: `vw_tableau_executive_year`. The year control is single-select, defaults to 2025, and allows 2023–2025. The first year has no prior-year change and must display `Not available`.

| ID and visual | Data source | Dimensions and measures / calculation | Filters | Tooltip fields | Sorting | Expected interaction | Validation criterion |
|---|---|---|---|---|---|---|---|
| E1 KPI — Reported incidents | Executive year | `crime_year`; `SUM(reported_incident_count)` | Single selected year | Year, period dates/status, exact count | Not applicable | Updates with year selector; no cross-filter action | 2025 displays 238,086 |
| E2 KPI — Year-over-year change | Executive year | `crime_year`; `MIN(absolute_change)`, `MIN(percentage_change)` | Single selected year | Current/prior year and counts, absolute and percentage change | Not applicable | Updates with year; 2023 shows `Not available` | 2025 displays -21,547 and -8.2990% before display rounding |
| E3 KPI — Arrest percentage | Executive year | `Weighted Arrest Percentage` | Single selected year | Arrest count, non-null denominator, percentage, definition warning | Not applicable | Updates with year | 2025 uses 38,365 / 238,086 = 16.1139% |
| E4 KPI — Domestic incident percentage | Executive year | `Weighted Domestic Incident Percentage` | Single selected year | Domestic count, non-null denominator, percentage, limitation | Not applicable | Updates with year | 2025 uses 45,319 / 238,086 = 19.0347% |
| E5 line — Annual reported incidents | Executive year | `crime_year` on columns; `reported_incident_count` on rows | Always show all complete years; do not inherit KPI year filter | Year, count, prior count, absolute and percentage change | `crime_year` ascending | Selecting a mark updates a year-selection parameter or the four KPI sheets only | Three marks: 263,844; 259,633; 238,086 in chronological order |
| E6 bars — Geographic coverage | Executive year | Measure Names/Values for `community_area_eligible_count` and `coordinate_mappable_count`; percentage labels use their coverage fields | Single selected year | Eligible count, excluded count, coverage percentage, eligibility definition | Coverage type in fixed order: community area, coordinates | Hover only; no filtering | For 2025: 237,757 area eligible and 236,099 coordinate mappable; neither replaces the full incident denominator |

## Page 2 — Geographic Crime Patterns

This page reports incident volume and descriptive density, not population-normalized rates or individual risk. The year filter defaults to 2025. A primary-type filter applies only to G4 unless a future category-aware density layer is explicitly prepared.

| ID and visual | Data source | Dimensions and measures / calculation | Filters | Tooltip fields | Sorting | Expected interaction | Validation criterion |
|---|---|---|---|---|---|---|---|
| G1 symbol map — Descriptive coordinate density | Coordinate density | `cell_longitude`, `cell_latitude`, `SUM(reported_incident_count)` on size/color | Single year | Year, cell center, count, `0.01-degree descriptive cell` warning | Color/size by count; no rank label | Pan/zoom; selection highlights only the map unless an explicit density-cell action is added | Year totals equal 261,242 (2023), 257,525 (2024), and 236,099 (2025); title says not a statistical hotspot test |
| G2 bars — Community-area volume | Community area year | `community_area_name`; `SUM(reported_incident_count)` | Single year; optional Top N parameter default 15 | Area number/name, count, share of area-eligible total, full-year rank | Count descending, name ascending for ties | Selecting an area filters G3 and G4; map is not filtered because cells are not assigned to areas | All 77 areas are present for each year; 2025 totals sum to 237,757 |
| G3 diverging bars — Community-area YoY change | Community area year | `community_area_name`; `MIN(absolute_change)` with color by sign; label `MIN(percentage_change)` | Single year restricted to 2024 or 2025; optional rank method toggle | Prior/current values, absolute/percentage change, 500-count percentage-rank eligibility, both rank types | Absolute decrease ascending by default; explicit toggle may use percentage decrease among eligible rows | G2 selection highlights matching area; clear selection restores all | 2025 Austin is -1,152 absolute; Forest Glen is -24.9541% and percentage-decrease rank 1 among threshold-eligible areas |
| G4 heatmap — Area/category composition | Area category year | Rows `community_area_name`; columns `primary_type`; color `percentage_of_area_year_total`; label/tooltip count | Single year; primary type; default top-ten full-period categories documented in the caption | Area, category, count, area-year total/share, category-year share, both ranks | Areas by total volume descending; categories by selected-year total descending | Area selection from G2 filters rows; clicking a cell highlights matching area/category only | Counts across all cells for 2025 sum to 237,757 before category filtering |
| G5 bars — District-code volume and change | District year | `district_label`; `SUM(reported_incident_count)`; optional color `MIN(percentage_change)` | Single year | District code/reference flag, current/prior counts, absolute/percentage change, yearly share/rank | Count descending, code ascending for ties | Selecting a district highlights only G5; no spatial polygon inference | Each year's district counts sum to citywide total; unmatched code `061` remains visibly labeled |

## Page 3 — Temporal and Seasonal Patterns

The year filter defaults to all three years for T1 and to 2025 for T2–T5. Incident timestamps can be estimated; no timezone conversion is inferred.

| ID and visual | Data source | Dimensions and measures / calculation | Filters | Tooltip fields | Sorting | Expected interaction | Validation criterion |
|---|---|---|---|---|---|---|---|
| T1 dual line — Monthly incidents and rolling average | Monthly patterns | `month_start`; `reported_incident_count`; `trailing_three_month_average` as secondary line with synchronized axis | Date range/all complete years | Month, count, rolling average, same-month prior value/change | `month_start` ascending | Brush/select months to highlight T2 only; do not relabel as forecasting | 36 chronological months; incident counts sum to 761,563 |
| T2 heatmap — Month by year | Monthly patterns | Rows `crime_year`; columns `crime_month` displayed as `month_name`; color count | Year range | Year, month, count, annual share, same-month change | Years ascending; months 1–12 | Selecting a cell highlights the same month in T1 | Exactly 12 cells per year; each row sums to its executive annual total |
| T3 heatmap — Weekday by hour | Time patterns | Rows `day_of_week`; columns `hour_of_day`; color `SUM(reported_incident_count)` | Single or multi-year | Weekday, hour, time band, weekend flag, count | `day_of_week_num` 1–7; hour 0–23 | Selecting cells filters T4 only | Selected years sum to the corresponding executive total across all 168 cells |
| T4 bars — Time-of-day distribution | Time patterns | `time_of_day`; `SUM(reported_incident_count)` and percent-of-selected-total table calculation | Year; optional weekday/hour selection from T3 | Time band, count, selected-total percentage | Overnight, Morning, Afternoon, Evening | Responds to T3 filter; click clears or narrows T3 highlight | Four bands sum to the selected scope; bands follow documented hour boundaries |
| T5 100% stacked bars — Location/time profile | Location time | `location_description`; color `time_of_day`; `SUM(reported_incident_count)` with percent of location total | Fixed top ten; no year filter because source is intentionally full-period | Location rank/total, time band count/share, full-period scope warning | `full_period_location_rank`; time-band order 1–4 | Hover/highlight only; page year control must visibly state that it does not apply to this full-period visual | 40 marks; each location's shares sum to 100% subject to display rounding |

## Page 4 — Crime and Arrest Analysis

This page retains the City's source `primary_type` categories; no broader grouping is introduced. The arrest field indicates only whether an arrest was recorded on the incident row.

| ID and visual | Data source | Dimensions and measures / calculation | Filters | Tooltip fields | Sorting | Expected interaction | Validation criterion |
|---|---|---|---|---|---|---|---|
| C1 bars — Category incident volume | Crime/arrest year | `primary_type`; `SUM(reported_incident_count)` | Single or multi-year; optional Top N default 10 | Category, year scope, count, annual share/rank | Count descending, category ascending for ties | Selecting categories filters/highlights C2–C5 | With all years selected, category counts sum to 761,563; Theft is 173,282 |
| C2 diverging bars — Category YoY change | Crime/arrest year | `primary_type`; `MIN(absolute_change)`; label `MIN(percentage_change)` | Single year 2024 or 2025; category selection | Prior/current values, absolute and percentage change, denominator | Absolute change ascending by default | Responds to C1 selection; selecting a bar highlights the category trend in C3/C4 | 2025 Robbery is 9,120 to 5,817, -3,303 and -36.2171% |
| C3 lines/dots — Arrest percentage by category | Crime/arrest year | `crime_year`; `primary_type`; `Weighted Arrest Percentage` | Category selection; complete years only | Arrest numerator/denominator, percentage, definition warning | Year ascending; categories by full-period volume | C1 category selection limits lines; hover highlights one category | Aggregating all categories by year reproduces 12.2114%, 13.8237%, and 16.1139% |
| C4 lines/dots — Domestic incident percentage by category | Crime/arrest year | `crime_year`; `primary_type`; `Weighted Domestic Incident Percentage` | Category selection; complete years only | Domestic numerator/denominator, percentage, limitation | Year ascending; categories by full-period volume | C1 category selection limits lines; hover highlights one category | Aggregating all categories by year reproduces 17.8916%, 18.3790%, and 19.0347% |
| C5 scatter — Volume versus arrest percentage | Crime/arrest year | Detail/label `primary_type`; x `SUM(reported_incident_count)`; y `Weighted Arrest Percentage`; size count or fixed; color latest year | Single year | Category, count/share/rank, arrest numerator/denominator/percentage | Not applicable; reference lines may show medians but not causal thresholds | C1 selection highlights marks; selecting a mark filters C2–C4 to that category | One mark per observed category in selected year; weighted roll-up matches executive arrest percentage |

## Dashboard-level validation checklist

Before Milestone 9B can be marked complete:

1. Open the workbook in Tableau and verify all nine data sources refresh without credential exposure.
2. Confirm page titles, cutoff label, complete-year language, definitions, and limitation footers are visible at 1,360 × 850.
3. Test every filter, navigation button, highlight action, and reset action described above.
4. Verify chronological sorting for years, months, weekdays, hours, and time bands.
5. Reconcile the explicit benchmark values in every visual's validation criterion.
6. Confirm aggregate filters do not create fan-out, average percentages, or change precomputed rank meaning.
7. Confirm coordinate maps exclude exactly 6,697 non-mappable records while non-map visuals retain applicable records.
8. Confirm no count is labeled a crime rate, no density cell is called statistically significant, no location count is framed as individual risk, and no arrest percentage is called clearance or conviction.
9. Capture screenshots only after the workbook and interactions have been manually tested.

## Milestone 9A execution evidence

The SQL completed successfully with `ON_ERROR_STOP=1`. All nine views were created in a single committed transaction after one initial failed run rolled back cleanly due to an existing-view column-name mismatch; that reference was corrected before the successful run. The fail-fast block reconciled executive, community-area, district, area/category, monthly, weekday/hour, crime/indicator, and coordinate-density totals to their canonical scopes.

The extract script then generated all nine CSVs and verified each file's reloaded row count against PostgreSQL. The local manifest records row/column counts, byte sizes, deterministic ordering, and SHA-256 checksums. These extracts are derived data and remain excluded from Git.

No Tableau workbook, dashboard page, filter action, screenshot, or manual Tableau validation exists yet. Those tasks belong to Milestone 9B.
