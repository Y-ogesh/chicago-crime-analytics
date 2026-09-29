# Tableau Dashboard Plan

## Milestone 9A status and scope

Tableau data preparation and implementation are complete. All four dashboards are generated and validated in Tableau Desktop 2026.2.3 in `tableau/chicago_crime_analytics.twb`.

The dashboard will use the official City of Chicago Crimes dataset (`ijzp-q8t2`) extract acquired September 25, 2026. Its analytical scope is 761,563 reported-incident records dated January 1, 2023 through December 31, 2025. All three years are complete calendar years. Counts are reported incidents, not population-normalized crime rates. Arrest percentages are source-indicator percentages, not clearance, prosecution, or conviction rates.

## Prepared data layer

Run [`sql/06_tableau_preparation.sql`](../sql/06_tableau_preparation.sql) after the advanced views in `sql/05_advanced_analysis.sql`. It creates ten non-materialized, page-oriented views and executes fail-fast reconciliations in one transaction.

| PostgreSQL view | Grain | Validated rows | Primary page |
|---|---|---:|---|
| `vw_tableau_executive_year` | Complete calendar year | 3 | Executive Overview |
| `vw_tableau_community_area_year` | Year × all 77 official community areas | 231 | Geographic Crime Patterns |
| `vw_tableau_district_year` | Year × observed source district code | 72 | Geographic Crime Patterns |
| `vw_tableau_area_category_year` | Year × community area × observed primary type | 5,395 | Geographic Crime Patterns |
| `vw_tableau_coordinate_density` | Year × 0.01-degree coordinate cell | 2,127 | Geographic Crime Patterns |
| `vw_tableau_monthly_patterns` | Calendar month | 36 | Temporal and Seasonal Patterns |
| `vw_tableau_month_category` | Calendar month × all 31 source primary types | 1,116 | Executive Overview filtered monthly trend |
| `vw_tableau_time_patterns` | Year × ISO weekday × hour | 504 | Temporal and Seasonal Patterns |
| `vw_tableau_location_time` | Fixed full-period top-ten location descriptions × time band | 40 | Temporal and Seasonal Patterns |
| `vw_tableau_crime_arrest_year` | Year × source primary type | 93 | Crime and Arrest Analysis |
| `vw_tableau_geographic_detail` | Year × primary type × area × district × coordinate eligibility × 0.01° cell | 50,037 | Implemented Geographic Crime Patterns |
| `vw_tableau_temporal_detail` | Month × primary type × ISO weekday × recorded hour | 87,809 | Implemented Temporal and Seasonal Patterns |
| `vw_tableau_temporal_kpis` | Complete year × crime-type filter scope | 96 | Page 3 peak KPI cards |

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
       public.vw_tableau_month_category,
       public.vw_tableau_time_patterns,
       public.vw_tableau_location_time,
       public.vw_tableau_crime_arrest_year,
       public.vw_tableau_geographic_detail TO tableau_reader;
   ```

   Role creation and password policy are environment-specific and intentionally not scripted here.
5. Select schema `public`. Create **one Tableau data source per view** and name it after the view without the `vw_tableau_` prefix. Do not physically join these aggregate views: their grains differ and a join can multiply measures.
6. Choose **Extract** for the ten aggregate sources. Use a full refresh after rerunning the SQL. A live connection is also acceptable for local development. Keep `vw_geographic_crime_points` separate and use it only if a record-level point view is explicitly added later.
7. Assign geographic roles: `cell_latitude` → Latitude and `cell_longitude` → Longitude. Keep `community_area_name` as a text dimension unless an official boundary spatial file is added; do not rely on ambiguous automatic geocoding.

Official Tableau references: [PostgreSQL connector](https://help.tableau.com/current/pro/desktop/en-us/examples_postgresql.htm), [extract data](https://help.tableau.com/current/pro/desktop/en-us/extracting_data.htm), and [filter actions](https://help.tableau.com/current/pro/desktop/en-us/actions_filter.htm).

## Connection option B — documented CSV extracts

For a portable build without a live database connection:

```bash
python scripts/export_tableau_data.py
```

The script uses environment variables or a Git-ignored `.env`, forces PostgreSQL transactions to read-only mode, orders every export deterministically, rereads each CSV, reconciles its rows to the source view, and writes checksums and metadata to `data/processed/tableau/manifest.json`. The `--profile page1` option writes the two Executive Overview sources under `data/processed/tableau/page1/`; `--profile page2` writes `vw_tableau_geographic_detail.csv`; and `--profile page3` writes `vw_tableau_temporal_detail.csv` under the matching page directory with a dedicated manifest. The entire processed Tableau directory is ignored by Git.

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

1. Create a workbook and add only the sources required by the page being built. Keep every aggregate source separate.
2. Create `pSelectedYear` and the canonical calculations. Add `Selected Year Filter = True` to single-year sheets. Use a parameter action on E5 so selecting a year changes `pSelectedYear`; clearing the selection leaves the current parameter value unchanged.
3. Build worksheets E1–E6, G1–G5, T1–T5, and C1–C5 from the field specifications below. Add the required source/definition text to each caption before assembling dashboards.
4. Create four dashboards at 1,360 × 850 and add the common header, year control, page navigation, filter rail, limitation footer, and reset control.
5. Add a custom-field filter action from G2 to G3/G4 mapping `community_area` to `community_area`. Clearing the selection must show all values. Add a same-source filter action from T3 to T4 using weekday/hour, and from C1 to C2–C5 using `primary_type`.
6. Add navigation objects as the remaining dashboards are implemented. Test every destination and keep the current page visually selected.
7. Use **Revert** as the reset control during development. If the workbook is published later, test that the published reset behavior restores `pSelectedYear = 2025` and clears all mark selections.
8. Run the dashboard-level validation checklist before saving screenshots or marking Milestone 9B complete.

## Page 1 — Executive Overview

**Implementation status: Complete.** The data sources, validation SQL, reproducible workbook generator, opening instructions, Tableau Desktop results, and exported screenshots are documented in [the Page 1 build guide](tableau_page1_build_guide.md). Pages 2–4 are complete under Milestones 9C–9E.

Generate the Page 1 bundle with `python scripts/export_tableau_data.py --profile page1`, then create or refresh the workbook with `python scripts/generate_tableau_workbook.py`. The generated workbook references `data/processed/tableau/page1/vw_tableau_crime_arrest_year.csv` as `Executive Category Year` and `data/processed/tableau/page1/vw_tableau_month_category.csv` as `Executive Month Category`. The paths are relative to the workbook. The sources are not joined, related, unioned, or blended; workbook parameters synchronize Year and Crime Type filters. `vw_tableau_executive_year` remains the PostgreSQL validation benchmark rather than a third Tableau source.

| ID and visual | Data source | Dimensions and measures / calculation | Filters | Tooltip fields | Sorting | Expected interaction | Validation criterion |
|---|---|---|---|---|---|---|---|
| E1 KPI — Reported incidents | Crime/arrest year | `SUM(reported_incident_count)` | Selected year; primary type | Year, category scope, exact count | Not applicable | Updates with year and crime-type controls | 2025 All = 238,086; 2025 Theft = 55,198 |
| E2 KPI — Arrest percentage | Crime/arrest year | Weighted `SUM(arrest_count) / SUM(arrest_indicator_denominator) * 100` | Selected year; primary type | Numerator, non-null denominator, percentage, definition warning | Not applicable | Updates with year and crime-type controls | 2025 All = 16.1139%; Theft = 9.0420% |
| E3 KPI — Domestic incident percentage | Crime/arrest year | Weighted `SUM(domestic_count) / SUM(domestic_indicator_denominator) * 100` | Selected year; primary type | Numerator, non-null denominator, percentage, limitation | Not applicable | Updates with year and crime-type controls | 2025 All = 19.0347%; Theft = 5.1270% |
| E4 line — Annual reported incidents | Crime/arrest year | `crime_year`; `SUM(reported_incident_count)` | Primary type; intentionally ignores selected-year filter | Year, category scope, exact count | `crime_year` ascending | Crime-type selection updates all three complete-year marks | All-category marks: 263,844; 259,633; 238,086 |
| E5 bars — Leading crime categories | Crime/arrest year | `primary_type`; `SUM(reported_incident_count)`; source `incident_volume_rank <= 10` when All is selected | Selected year; parameter-aware category display | Year, type, count, annual share/rank | Count descending; type ascending for ties | All shows the top 10; a specific Crime Type displays that category even if it is outside the top 10 | 2025 leader is Theft with 55,198; top ten match saved SQL |
| E6 line — Monthly trend | Month/category | `month_start`; `SUM(reported_incident_count)`; category rolling average in tooltip | Selected year and primary type through shared parameters | Month, type scope, count, trailing-three-month average | `month_start` ascending | Year and crime-type parameters update all 12 months | 2025 All sums to 238,086; 2025 Theft sums to 55,198 |

## Page 2 — Geographic Crime Patterns

**Implementation status: Complete and validated in Tableau Desktop.** Generate its source with `python scripts/export_tableau_data.py --profile page2`, then regenerate the workbook with `python scripts/generate_tableau_workbook.py`. The workbook references `data/processed/tableau/page2/vw_tableau_geographic_detail.csv` as `Geographic Detail`. This single 50,037-row source contains every clean incident exactly once at a filterable aggregate grain, so all four controls can update every Page 2 worksheet without joining differently aggregated sources.

The page reports incident volume and descriptive coordinate concentration, not population-normalized rates, statistical hotspot significance, or individual risk. Year defaults to 2025; Crime Type, Community Area, and Police District default to their All values. Records without valid coordinates remain in the incident KPI and non-map rankings but are excluded from the map. Community-area ranking explicitly restricts to the 77 eligible official areas.

| ID and visual | Data source | Dimensions and measures / calculation | Filters | Tooltip fields | Sorting | Expected interaction | Validation criterion |
|---|---|---|---|---|---|---|---|
| G1 KPI — Incidents | Geographic Detail | `SUM(reported_incident_count)` | Shared Year, Crime Type, Community Area, Police District parameters | Definition available in worksheet metadata; dashboard shows exact count | Not applicable | Updates with every control | 2025 All = 238,086; THEFT = 55,198; Austin/THEFT = 1,967; District 008/THEFT = 3,112 |
| G2 KPI — Coverage | Geographic Detail | `100 * SUM(IF coordinate_mappable_flag=1 THEN reported_incident_count END) / SUM(reported_incident_count)` | All four controls | Coverage definition and denominator warning | Not applicable | Updates with every control | 2025 All = 99.1654% (99.2% displayed); THEFT = 99.3677% (99.4% displayed) |
| G3 symbol map — Descriptive incident density | Geographic Detail | Average cell latitude/longitude; cell ID on detail; incident count on color/size | All four controls plus `coordinate_mappable_flag=1` | Cell ID, exact count, descriptive-cell warning | Color/size by count | Pan/zoom; parameter controls update cells | 2025 All map sums to 236,099; THEFT map sums to 54,849; title identifies 0.01° cells |
| G4 bars — Community-area ranking | Geographic Detail | `community_area_name`; `SUM(reported_incident_count)` | All four controls plus `community_area_eligible_flag=1` | Area and exact count | Count descending; area ascending for ties | Controls update the ranked population; vertical scroll exposes all eligible areas | All 77 areas are available; 2025 leader is Austin at 11,806; 2025 THEFT leader is Near North Side at 4,637 |
| G5 bars — Police-district comparison | Geographic Detail | `district_label`; `SUM(reported_incident_count)` | All four controls | District label and exact count | Count descending; label ascending for ties | Controls update the ranked districts; scroll exposes all 24 labels | 2025 leader is District 008 at 15,278; THEFT leader is District 018 at 5,522 |
| G6 bars — Crime categories in selected geography | Geographic Detail | `primary_type`; `SUM(reported_incident_count)` | All four controls | Crime type and exact count | Count descending; type ascending for ties | Area or district selection recomputes the category mix; a specific Crime Type produces one bar | 2025 All leader is THEFT at 55,198; selected-category total equals the incident KPI |

## Page 3 — Temporal and Seasonal Patterns

**Implementation status: Complete.** The generated workbook contains nine Page 3 worksheets and the fixed-size `Temporal and Seasonal Patterns` dashboard. Tableau Desktop 2026.2.3 rendered the corrected 2025 / All Crime Types and 2025 / THEFT states, and the retained screenshots reconcile to PostgreSQL benchmarks. The implementation definitions and benchmarks remain in [the Page 3 build guide](tableau_page3_build_guide.md).

Page 3 uses `data/processed/tableau/page3/vw_tableau_temporal_detail.csv` for all additive charts and the total KPI, plus `vw_tableau_temporal_kpis.csv` for the three peak cards. The 87,809-row detail source is at month × source primary type × ISO weekday × recorded hour grain, and every clean incident contributes once. The 96-row KPI source is independently filtered by the same Year and Crime Type parameters and is never joined to the detail source, preventing cross-grain double counting. Incident timestamps can be estimated; no timezone conversion is inferred.

| ID and visual | Data source | Dimensions and measures / calculation | Filters | Tooltip fields | Sorting | Expected interaction | Validation criterion |
|---|---|---|---|---|---|---|---|
| T1 heatmap — Weekday by hour | Temporal Detail | Rows `day_of_week`; columns `hour_of_day`; color `SUM(reported_incident_count)` | Selected Year and Crime Type Boolean filters | Day, hour, count, weighted arrest/domestic percentages | `day_of_week_num` 1–7; hour 0–23 | Shared controls update the complete heatmap | 2025 All totals 238,086; largest cell Saturday hour 0 = 2,656. THEFT largest cell Friday hour 12 = 590 |
| T2 line — Monthly crime trend | Temporal Detail | Continuous month of `month_start`; `SUM(reported_incident_count)` | Selected Year and Crime Type | Month, count, weighted indicator percentages | `month_start` ascending | Shared controls update all 12 months | 2025 All and THEFT sum to 238,086 and 55,198; both peak in July at 22,710 and 5,404 |
| T3 bars — Seasonal comparison | Temporal Detail | `season`; `SUM(reported_incident_count)` | Selected Year and Crime Type | Season, count, documented definition | `season_order` 1–4 | Shared controls update four bars | 2025 All: 52,738; 60,120; 65,283; 59,945 in Winter–Fall order |
| T4 bars — Time-of-day distribution | Temporal Detail | Physical `time_of_day_display`; `SUM(reported_incident_count)` | Selected Year and Crime Type | Display/source band, count, hour boundaries | `time_of_day_order` 1–4 | Shared controls update four bars | 2025 All: 46,595; 50,349; 74,654; 66,488 in Night–Evening order |
| T5 lines — Category monthly comparison | Temporal Detail | Continuous month; count; `primary_type` on color; parameter-aware annual rank ≤ 5 | Selected Year, Crime Type, and leading-category Boolean filter | Month, source crime type, count | Month ascending; annual category rank | All shows five leading categories; a selected type shows one line | 2025 top five are Theft, Battery, Criminal Damage, Assault, and Motor Vehicle Theft |
| T6 KPI group — Current temporal scope | Temporal Detail for total; Temporal KPI Scope for three peaks | Total count plus materialized peak hour, weekday, and exact month | Both sources use the shared Year and Crime Type parameters; KPI scope matches them exactly | Selected value and supporting count | PostgreSQL count descending; deterministic time-order tie break | All four cards update with both controls without a join | 2025 All: 238,086; 00:00; Friday; July. THEFT: 55,198; 12:00; Friday; July |

## Page 4 — Crime and Arrest Analysis

**Implementation status: Complete and validated in Tableau Desktop.** This page retains the City's source `primary_type` categories; no broader grouping is introduced. The arrest field indicates only whether an arrest was recorded on the incident row, not clearance or conviction. It reuses `data/processed/tableau/page1/vw_tableau_crime_arrest_year.csv` (`Executive Category Year`) at year × source primary-type grain. No additional CSV or cross-grain join is used.

The Page 4 calculations intentionally use the user-specified incident-count denominator:

```text
Arrest Percentage
IF SUM([reported_incident_count]) = 0 THEN NULL
ELSE 100.0 * SUM([arrest_count]) / SUM([reported_incident_count])
END

Domestic Incident Percentage
IF SUM([reported_incident_count]) = 0 THEN NULL
ELSE 100.0 * SUM([domestic_count]) / SUM([reported_incident_count])
END
```

| ID and visual | Data source | Dimensions and measures / calculation | Filters | Tooltip fields | Sorting | Expected interaction | Validation criterion |
|---|---|---|---|---|---|---|---|
| C1 KPI — Reported incidents | Crime/arrest year | `SUM(reported_incident_count)` | Selected Year and Crime Type | Exact count and current scope | Not applicable | Both controls update the card | 2025 All = 238,086; THEFT = 55,198 |
| C2 KPI — Arrest percentage | Crime/arrest year | Page 4 Arrest Percentage | Selected Year and Crime Type | Arrest count, incident denominator, percentage | Not applicable | Both controls update the card | 2025 All = 16.1139%; THEFT = 9.0420% |
| C3 KPI — Domestic percentage | Crime/arrest year | Page 4 Domestic Incident Percentage | Selected Year and Crime Type | Domestic count, incident denominator, percentage | Not applicable | Both controls update the card | 2025 All = 19.0347%; THEFT = 5.1270% |
| C4 bars — Category incident volume | Crime/arrest year | `primary_type`; `SUM(reported_incident_count)` | Selected Year and Crime Type; parameter-aware top 10 | Category and count | Count descending | All shows the selected year's top 10; a selected crime type shows one category | 2025 leader = THEFT at 55,198 |
| C5 bars — Arrest percentage by category | Crime/arrest year | `primary_type`; Page 4 Arrest Percentage | Selected Year and Crime Type; parameter-aware top 10 | Category, arrest numerator, incident denominator, percentage | Percentage descending | Both controls recompute weighted category percentages | 2025 THEFT = 9.0420%; BATTERY = 19.2546% |
| C6 line — Arrest percentage over time | Crime/arrest year | `crime_year`; Page 4 Arrest Percentage | Crime Type only; Year intentionally ignored | Year, arrest count, incident denominator, percentage | Year ascending | Crime Type switches the three-year trend | All = 12.2114%, 13.8237%, 16.1139%; THEFT = 4.9717%, 6.8150%, 9.0420% |
| C7 scatter — Incident volume versus arrest percentage | Crime/arrest year | Detail `primary_type`; x `SUM(reported_incident_count)`; y/color Page 4 Arrest Percentage | Selected Year and Crime Type | Category, count, arrest count, percentage | Not applicable | All shows one mark per crime type; a selected type shows one mark | 2025 weighted roll-up matches 16.1139%; THEFT mark is 55,198 and 9.0420% |
| C8 bars — Domestic percentage by category | Crime/arrest year | `primary_type`; Page 4 Domestic Incident Percentage | Selected Year and Crime Type; parameter-aware top 10 | Category, domestic numerator, incident denominator, percentage | Percentage descending | Both controls recompute weighted category percentages | 2025 THEFT = 5.1270%; BATTERY = 53.0755% |

## Dashboard-level validation checklist

Before Milestone 9B can be marked complete:

1. Open the workbook in Tableau and verify every data source used by the implemented pages refreshes without credential exposure.
2. Confirm page titles, cutoff label, complete-year language, definitions, and limitation footers are visible at 1,360 × 850.
3. Test every filter, navigation button, highlight action, and reset action described above.
4. Verify chronological sorting for years, months, weekdays, hours, and time bands.
5. Reconcile the explicit benchmark values in every visual's validation criterion.
6. Confirm aggregate filters do not create fan-out, average percentages, or change precomputed rank meaning.
7. Confirm coordinate maps exclude exactly 6,697 non-mappable records while non-map visuals retain applicable records.
8. Confirm no count is labeled a crime rate, no density cell is called statistically significant, no location count is framed as individual risk, and no arrest percentage is called clearance or conviction.
9. Capture screenshots only after the workbook and interactions have been manually tested.

## Milestone 9A execution evidence

The SQL completed successfully with `ON_ERROR_STOP=1`. The original nine-view preparation completed in a single committed transaction after one initial failed run rolled back cleanly due to an existing-view column-name mismatch. Page 1 preparation later added the validated `vw_tableau_month_category` view, bringing the presentation layer to ten views. Its complete 1,116-row grid reconciles to both monthly citywide totals and all 93 year/category rows.

The extract script verifies every exported file's reloaded row count against PostgreSQL. The Page 1 profile generated exactly two CSVs—93 annual/category rows and 1,116 month/category rows—plus a local manifest recording row/column counts, byte sizes, deterministic ordering, and SHA-256 checksums. These extracts are derived data and remain excluded from Git.

Milestone 9B generated `tableau/chicago_crime_analytics.twb` with six Page 1 worksheets, a fixed-size Executive Overview dashboard, and Year/Crime Type parameter controls. XML and source-reference checks passed, PostgreSQL benchmarks reconciled, and Tableau Desktop 2026.2.3 completed load, layout, model-computation, visual-rendering, and filter-interaction checks. Page 1 displays the year without grouping, emphasizes KPI values, labels the annual trend, uses human-readable measure captions, and limits the all-crimes distribution to a parameter-aware top 10 while preserving any specifically selected crime type. Tableau-exported 2025 All Crime Types and THEFT screenshots are stored under `images/tableau/`.

Milestone 9C extended the same workbook with six Page 2 worksheets, the `Geographic Detail` CSV source, four synchronized parameters, and the fixed-size Geographic Crime Patterns dashboard. SQL, export, XML, source-reference, and Tableau checks passed. Tableau verified 2025 All Crime Types, 2025 THEFT, Austin/THEFT, and District 008/THEFT; screenshots are stored under `images/tableau/`.

Milestone 9D extends the generator and workbook with `Temporal Detail`, `Temporal KPI Scope`, nine Page 3 worksheets, shared Year and Crime Type parameters, and the fixed-size Temporal and Seasonal Patterns dashboard. `sql/10_tableau_temporal_page.sql` creates both temporal views, `sql/11_tableau_page3_validation.sql` supplies fail-fast checks and benchmarks, and `python scripts/export_tableau_data.py --profile page3` writes both Git-ignored CSVs and their checksum manifest. PostgreSQL and reloaded-CSV checks reconciled 87,809 detail rows, 96 KPI rows, and 761,563 represented incidents with exact annual, indicator, monthly, seasonal, weekday/hour, category, and peak-KPI totals.

An initial 2025 / THEFT screenshot exposed three peak cards that did not recompute and a blank time-of-day chart. The generator now reads peak values from the materialized KPI source and uses a physical display field for the four time bands. The regenerated workbook passes PostgreSQL, CSV, XML, checksum, source-reference, worksheet, dashboard, formula, and benchmark checks. Tableau Desktop rendered both required filter states without errors; evidence is stored in [`temporal_seasonal_patterns_2025_all.png`](../images/tableau/temporal_seasonal_patterns_2025_all.png) and [`temporal_seasonal_patterns_2025_theft.png`](../images/tableau/temporal_seasonal_patterns_2025_theft.png).

Milestone 9E extends the generator and workbook with six Page 4 worksheets and the fixed-size `Crime and Arrest Analysis` dashboard while reusing the existing reported-incidents KPI and category-volume worksheet. [`sql/12_tableau_page4_validation.sql`](../sql/12_tableau_page4_validation.sql) validates the 93-row annual/category source, complete-period totals, weighted calculations, 2025 filter states, leading categories, and THEFT trend. The generated workbook contains 27 worksheets, four dashboards, five CSV-backed data sources, and shared parameters. XML, relative file references, formulas, worksheet/dashboard membership, and embedded benchmark checks pass.

After restarting the application, Tableau Desktop 2026.2.3 rendered Page 4 successfully. The 2025 All Crime Types state displayed 238,086 incidents, 16.1% arrest, and 19.0% domestic. The 2025 THEFT state displayed 55,198 incidents, 9.0% arrest, and 5.1% domestic; category bars, the three-year arrest trend, and the single-category scatter mark updated correctly. Tableau-exported evidence is stored in [`crime_arrest_analysis_2025_all.png`](../images/tableau/crime_arrest_analysis_2025_all.png) and [`crime_arrest_analysis_2025_theft.png`](../images/tableau/crime_arrest_analysis_2025_theft.png).

The final cross-page review compared the four retained 2025 All Crime Types exports and confirmed consistent dashboard size, typography, blue palette, KPI treatment, filter placement, complete-year language, reported-incident terminology, readable labels, and caveat footers. Existing Page 1–3 screenshots, PostgreSQL benchmarks, and workbook structural checks remained valid. The four-page Milestone 9B and Page 4 Milestone 9E are complete.
