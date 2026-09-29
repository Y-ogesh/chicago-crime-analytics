# Tableau Page 3 Manual Build Guide

## Status and scope

Page 3 is **Complete**. The workbook generator creates the nine documented worksheets and the fixed-size `Temporal and Seasonal Patterns` dashboard. An initial 2025 / THEFT screenshot exposed incorrect peak-card values and a blank time-of-day chart; the corrected workbook uses a materialized KPI source and a physical time-band display field. Tableau Desktop 2026.2.3 rendered both required filter states, retained as [`temporal_seasonal_patterns_2025_all.png`](../images/tableau/temporal_seasonal_patterns_2025_all.png) and [`temporal_seasonal_patterns_2025_theft.png`](../images/tableau/temporal_seasonal_patterns_2025_theft.png). This guide remains the field-level implementation and reconciliation reference.

The source is the official City of Chicago Crimes dataset (`ijzp-q8t2`) extract acquired September 25, 2026. It covers 761,563 reported-incident records dated January 1, 2023 through December 31, 2025. All three years are complete calendar years. Counts are reported incidents, not population-normalized crime rates. Arrest percentage, if used in a tooltip, is the share of records marked `arrest=true`; it is not a clearance or conviction rate.

Incident timestamps may be estimated. Exact-hour concentrations, especially midnight, may partly reflect recording practices. The dashboard is descriptive and does not establish seasonality causes.

## 1. Rebuild and export the Page 3 source

From the repository root, with the documented PostgreSQL environment configured:

```bash
psql --no-psqlrc --dbname "${PGDATABASE:-chicago_crime}" \
  -v ON_ERROR_STOP=1 -P pager=off \
  --file sql/10_tableau_temporal_page.sql

psql --no-psqlrc --dbname "${PGDATABASE:-chicago_crime}" \
  -v ON_ERROR_STOP=1 -P pager=off \
  --file sql/11_tableau_page3_validation.sql

./.venv/bin/python scripts/export_tableau_data.py --profile page3
```

Output:

`data/processed/tableau/page3/vw_tableau_temporal_detail.csv`

`data/processed/tableau/page3/vw_tableau_temporal_kpis.csv`

The detail CSV has 87,809 rows and 21 columns. Its grain is complete calendar month × source crime type × ISO weekday × recorded hour. Every clean incident contributes exactly once. The KPI CSV has 96 rows and 12 columns at complete year × crime-type filter scope grain. The sources remain independent; do not join, union, blend, or relate them.

## 2. Connect the CSV in Tableau

1. Open the existing Chicago Crime Analytics workbook.
2. Select **Data → New Data Source**.
3. Under **To a File**, choose **Text File**.
4. Open `data/processed/tableau/page3/vw_tableau_temporal_detail.csv`.
5. Rename the data source to **Temporal Detail (Page 3)**.
6. Repeat **Data → New Data Source → Text File** for `data/processed/tableau/page3/vw_tableau_temporal_kpis.csv` and rename it **Temporal KPI Scope (Page 3)**.
7. Confirm that Tableau assigned these types:

| Field | Tableau type |
|---|---|
| `month_start` | Date |
| `crime_year`, `crime_month`, `crime_quarter` | Number (whole) |
| `season_order`, `annual_category_rank` | Number (whole) |
| `day_of_week_num`, `hour_of_day`, `time_of_day_order` | Number (whole) |
| `weekend_flag` | Number (whole) |
| `reported_incident_count`, `arrest_count`, `arrest_indicator_denominator` | Number (whole) |
| `domestic_count`, `domestic_indicator_denominator` | Number (whole) |
| `month_name`, `season`, `primary_type`, `day_of_week`, `time_of_day`, `time_of_day_display` | String |

If `month_start` appears as text, click its data-type icon and choose **Date**. Do not create joins to the Page 1 or Page 2 sources.

## 3. Reuse the existing controls

Pages 1–2 already contain workbook parameters with captions **Year** and **Crime Type**. Reuse them:

- Internal parameter `[pSelectedYear]`: String list `2023`, `2024`, `2025`; current value `2025`.
- Internal parameter `[pCrimeType]`: String list beginning with `All Crime Types`, followed by the 31 source `primary_type` values.

If either parameter is absent, create it with the exact internal name and values above. Then create these calculated fields in **Temporal Detail (Page 3)**.

### Selected Year Filter

```tableau
STR([crime_year]) = [pSelectedYear]
```

### Selected Crime Type Filter

```tableau
[pCrimeType] = "All Crime Types"
OR [primary_type] = [pCrimeType]
```

### Show Leading Categories

```tableau
[pCrimeType] <> "All Crime Types"
OR [annual_category_rank] <= 5
```

### Time of Day Display

The database definition remains `Overnight` for 00:00–05:59. The export supplies physical field `time_of_day_display`, which shows that band as **Night**. Use the physical field in the generated workbook; the formula below is retained only as a manual-build fallback.

```tableau
IF [time_of_day] = "Overnight" THEN "Night"
ELSE [time_of_day]
END
```

### Hour Label

```tableau
RIGHT("0" + STR([hour_of_day]), 2) + ":00"
```

### Arrest Percentage

Create this only for optional tooltips. Do not average row-level percentages.

```tableau
IF SUM([arrest_indicator_denominator]) = 0 THEN NULL
ELSE SUM([arrest_count]) / SUM([arrest_indicator_denominator])
END
```

Format as Percentage with one decimal place. The underlying formula returns a decimal; do not multiply by 100.

### Domestic Incident Percentage

```tableau
IF SUM([domestic_indicator_denominator]) = 0 THEN NULL
ELSE SUM([domestic_count]) / SUM([domestic_indicator_denominator])
END
```

Format as Percentage with one decimal place.

For every Page 3 worksheet, drag **Selected Year Filter** and **Selected Crime Type Filter** to Filters and retain `True`. The workbook parameters then control every worksheet without cross-source filter mapping.

## 4. Worksheet instructions

### Worksheet T1 — `P3 Day-Hour Heatmap`

**Purpose:** Day of week × recorded hour reported-incident concentration.

1. Select data source **Temporal Detail (Page 3)**.
2. Drag `hour_of_day` to **Columns**. Right-click the pill and choose **Dimension** and **Discrete**.
3. Drag `day_of_week` to **Rows**.
4. Set **Marks** to **Square**.
5. Drag `reported_incident_count` to **Color** and keep aggregation `SUM`.
6. Drag `reported_incident_count`, `day_of_week`, `hour_of_day`, `Arrest Percentage`, and `Domestic Incident Percentage` to **Tooltip**.
7. Do not place a field on Label, Size, or Detail.
8. Add **Selected Year Filter = True** and **Selected Crime Type Filter = True**.
9. Sort `day_of_week` by **Field → Minimum → day_of_week_num → Ascending**. Verify Monday through Sunday.
10. Ensure `hour_of_day` is ascending from 0 through 23. Choose **Entire View** or **Fit Width**.
11. Use a sequential blue color palette. Keep the legend visible and title it **Reported Incidents**.
12. Edit the tooltip to:

```text
<Day of Week>, <Hour Label>
Reported incidents: <SUM(Reported Incident Count)>
Arrest percentage: <AGG(Arrest Percentage)>
Domestic incident percentage: <AGG(Domestic Incident Percentage)>
Recorded times may be estimated.
```

**Expected validation:**

- 2025 / All Crime Types totals 238,086 across the heatmap. The largest cell is Saturday at hour 0 with 2,656 incidents.
- 2025 / THEFT totals 55,198. The largest cell is Friday at hour 12 with 590 incidents.

**Common mistakes:**

- Alphabetical weekdays: sort by minimum `day_of_week_num`, not by name.
- A continuous hour axis: convert `hour_of_day` to a discrete dimension.
- Too few cells: confirm both Boolean filters equal `True`, not `False` or `All`.
- Percentages above 100%: use the weighted formulas above; never sum or average precomputed percentages.

### Worksheet T2 — `P3 Monthly Crime Trend`

**Purpose:** Chronological monthly incident trend on a real year-aware date axis.

1. Select **Temporal Detail (Page 3)**.
2. Drag `month_start` to **Columns**.
3. From the pill menu select **Month** from the continuous date section so the pill is green. Do not use discrete `month_name`.
4. Drag `reported_incident_count` to **Rows** as `SUM`.
5. Set **Marks** to **Line**. Use the established Page 1 blue and a medium line weight.
6. Drag `month_start`, `reported_incident_count`, `Arrest Percentage`, and `Domestic Incident Percentage` to **Tooltip**.
7. Do not place fields on Color, Size, Detail, or Label.
8. Add **Selected Year Filter = True** and **Selected Crime Type Filter = True**.
9. Keep `month_start` ascending. Format the axis as `MMM` because the Year control already states the year; the underlying field remains a full date.
10. Format the y-axis title as **Reported Incidents** with whole-number thousands separators and a zero baseline.
11. Tooltip text:

```text
<MONTH(Month Start)>
Reported incidents: <SUM(Reported Incident Count)>
Arrest percentage: <AGG(Arrest Percentage)>
Domestic incident percentage: <AGG(Domestic Incident Percentage)>
```

**Expected validation:**

| Month | 2025 All | 2025 THEFT |
|---|---:|---:|
| January | 18,566 | 4,316 |
| February | 16,581 | 3,935 |
| March | 19,827 | 4,548 |
| April | 19,728 | 4,500 |
| May | 20,565 | 4,807 |
| June | 21,186 | 4,941 |
| July | 22,710 | 5,404 |
| August | 21,387 | 5,001 |
| September | 20,404 | 4,549 |
| October | 21,048 | 4,794 |
| November | 18,493 | 4,241 |
| December | 17,591 | 4,162 |

**Common mistakes:**

- Alphabetical month order: use continuous `month_start`, not `month_name`.
- Multiple marks per month: remove `day_of_week`, `hour_of_day`, and `primary_type` from Detail.
- Double counting: connect only this CSV; do not join it to `vw_tableau_month_category.csv`.

### Worksheet T3 — `P3 Seasonal Comparison`

**Purpose:** Compare reported-incident counts across meteorological seasons.

1. Select **Temporal Detail (Page 3)**.
2. Drag `season` to **Columns**.
3. Drag `reported_incident_count` to **Rows** as `SUM`.
4. Set **Marks** to **Bar**.
5. Drag `reported_incident_count` to **Label** and **Tooltip**.
6. Do not place fields on Color, Size, or Detail. Use the established blue for all bars.
7. Add **Selected Year Filter = True** and **Selected Crime Type Filter = True**.
8. Sort `season` by **Field → Minimum → season_order → Ascending**. The required order is Winter, Spring, Summer, Fall.
9. Show labels outside the bars where space allows; format as whole numbers with commas.
10. Add this subtitle or caption: `Winter = Dec–Feb; Spring = Mar–May; Summer = Jun–Aug; Fall = Sep–Nov. Counts are not adjusted for days per season.`

**Expected validation:**

| Season | 2025 All | 2025 THEFT |
|---|---:|---:|
| Winter | 52,738 | 12,413 |
| Spring | 60,120 | 13,855 |
| Summer | 65,283 | 15,346 |
| Fall | 59,945 | 13,584 |

**Common mistakes:**

- Alphabetical seasons: sort by minimum `season_order`.
- Treating seasonal counts as weather effects: use descriptive wording only.
- Comparing unadjusted totals as daily rates: do not label the measure a rate.

### Worksheet T4 — `P3 Time-of-Day Distribution`

**Purpose:** Compare four documented hour bands.

1. Select **Temporal Detail (Page 3)**.
2. Drag calculated field `Time of Day Display` to **Rows**.
3. Drag `reported_incident_count` to **Columns** as `SUM`.
4. Set **Marks** to **Bar**.
5. Drag `reported_incident_count` to **Label** and **Tooltip**.
6. Drag `time_of_day` and `time_of_day_order` to **Tooltip** only if helpful for QA; do not expose `Overnight` as a second visible category.
7. Add **Selected Year Filter = True** and **Selected Crime Type Filter = True**.
8. Sort `Time of Day Display` by **Field → Minimum → time_of_day_order → Ascending**. The order is Night, Morning, Afternoon, Evening.
9. Format counts with commas. Use one consistent blue rather than decorative category colors.
10. Caption: `Night 00:00–05:59; Morning 06:00–11:59; Afternoon 12:00–17:59; Evening 18:00–23:59.`

**Expected validation:**

| Display band | Source value | 2025 All | 2025 THEFT |
|---|---|---:|---:|
| Night | Overnight | 46,595 | 7,877 |
| Morning | Morning | 50,349 | 12,541 |
| Afternoon | Afternoon | 74,654 | 21,131 |
| Evening | Evening | 66,488 | 13,649 |

**Common mistakes:**

- Reclassifying hours: use the supplied `time_of_day`; only rename Overnight to Night for display.
- Sorting alphabetically: sort by minimum `time_of_day_order`.
- Recreating bands with different boundaries: do not use Tableau's automatic bins.

### Worksheet T5 — `P3 Category Monthly Comparison`

**Purpose:** Compare monthly patterns for the five leading categories in the selected year; show one selected category when Crime Type is not All.

1. Select **Temporal Detail (Page 3)**.
2. Drag `month_start` to **Columns** and choose continuous **Month**.
3. Drag `reported_incident_count` to **Rows** as `SUM`.
4. Set **Marks** to **Line**.
5. Drag `primary_type` to **Color** and **Detail**.
6. Drag `month_start`, `primary_type`, and `reported_incident_count` to **Tooltip**.
7. Add **Selected Year Filter = True**, **Selected Crime Type Filter = True**, and **Show Leading Categories = True** to Filters.
8. Keep `month_start` ascending. Do not use `month_name` as the axis.
9. Use a color-blind-safe categorical palette. Keep the legend visible. Do not label every point; rely on hover tooltips.
10. Use **Fit Width**. Format the y-axis as whole reported incidents.

**Expected validation:** 2025 / All Crime Types contains these five lines and annual totals:

| Rank | Crime type | Reported incidents |
|---:|---|---:|
| 1 | THEFT | 55,198 |
| 2 | BATTERY | 42,660 |
| 3 | CRIMINAL DAMAGE | 26,248 |
| 4 | ASSAULT | 21,601 |
| 5 | MOTOR VEHICLE THEFT | 17,257 |

For 2025 / THEFT, exactly one line remains and its 12 monthly marks sum to 55,198.

**Common mistakes:**

- Hard-coding a category list: use `annual_category_rank` through **Show Leading Categories**.
- Empty view for a selected lower-ranked category: verify the calculated field uses the parameter-aware `OR` formula exactly.
- Thirty-one unreadable lines: confirm **Show Leading Categories = True**.

### Worksheet K1 — `P3 KPI Total Incidents`

1. Select **Temporal Detail (Page 3)**.
2. Set **Marks** to **Text**.
3. Drag `reported_incident_count` to **Text** as `SUM`.
4. Add both selected filters as `True`.
5. Format the value as `#,##0`, Tableau Semibold, 24–28 pt, dark navy.
6. Title: **Reported Incidents**.

Expected: 238,086 for 2025 / All and 55,198 for 2025 / THEFT.

Common mistake: more than one mark means a dimension remains on Detail; remove all dimensions from the Marks card.

### Worksheet K2 — `P3 KPI Peak Hour`

1. Select **Temporal KPI Scope (Page 3)**.
2. Create **Selected Temporal KPI Scope**: `STR([crime_year]) = [pSelectedYear] AND [primary_type_scope] = [pCrimeType]`.
3. Add **Selected Temporal KPI Scope** to Filters as `True`.
4. Set **Marks** to **Text**.
5. Drag `peak_hour_label` to **Text** as `MIN`; add `peak_hour_incident_count` to Tooltip as `MIN`.
6. Display the hour on the card and include the supporting incident count in the tooltip.
7. Format the hour at 22–24 pt and the count at 10–11 pt. Title: **Peak Recorded Hour**.

Expected: 00:00 with 16,749 incidents for 2025 / All; 12:00 with 3,748 for 2025 / THEFT.

Common mistake: using a Top 1 table calculation on Temporal Detail can leave the prior category's value visible. Use the materialized KPI source and exact-scope filter.

### Worksheet K3 — `P3 KPI Peak Day`

1. Select **Temporal KPI Scope (Page 3)**.
2. Add **Selected Temporal KPI Scope** to Filters as `True`.
3. No Top N filter or table calculation is required.
4. Set **Marks** to **Text**.
5. Drag `peak_day` to **Text** as `MIN`; add `peak_day_incident_count` to Tooltip as `MIN`.
6. Display the weekday on the card and include the supporting count in the tooltip. Title: **Peak Day**.

Expected: Friday with 35,445 incidents for 2025 / All; Friday with 8,421 for 2025 / THEFT.

Common mistake: filtering the KPI source with the detail source's OR-based crime-type filter. The KPI source requires exact equality to `primary_type_scope`.

### Worksheet K4 — `P3 KPI Peak Month`

1. Select **Temporal KPI Scope (Page 3)**.
2. Add **Selected Temporal KPI Scope** to Filters as `True`.
3. No date-part, Top N, or table calculation is required.
4. Confirm the filtered KPI source contains exactly one row.
5. Set **Marks** to **Text**.
6. Drag `peak_month` to Text as `MIN`; add `peak_month_incident_count` to Tooltip as `MIN`.
7. Display the month on the card and include the supporting count in the tooltip. Title: **Peak Month**.

Expected: July with 22,710 incidents for 2025 / All; July with 5,404 for 2025 / THEFT.

Common mistake: relating or joining KPI rows to Temporal Detail. Keep the sources independent and parameter-filtered to prevent cross-grain fan-out.

## 5. Dashboard assembly

Create a dashboard named **Temporal and Seasonal Patterns** with fixed size **1,360 × 850**. Use the same navy headings, blue marks, thin pale-blue borders, white background, typeface, and footer styling as Pages 1–2.

Use tiled containers. Keep 12–16 px internal padding and approximately 16 px between major panels.

```text
+--------------------------------------------------------------------------------+
| Chicago Crime Analytics — Temporal and Seasonal Patterns     Year | Crime Type |
| Complete calendar years 2023–2025 | Recorded times may be estimated            |
+----------------+----------------+----------------+-------------------------------+
| Incidents KPI  | Peak Hour KPI  | Peak Day KPI   | Peak Month KPI                |
+-----------------------------------------------+--------------------------------+
| Day of Week × Hour Heatmap                    | Monthly Crime Trend             |
|                                               |                                |
+------------------------+----------------------+--------------------------------+
| Seasonal Comparison    | Time-of-Day          | Category Monthly Comparison     |
|                        | Distribution         |                                |
+--------------------------------------------------------------------------------+
| Source/cutoff and limitations footer                                           |
+--------------------------------------------------------------------------------+
```

Recommended height allocation:

- Header and controls: 90 px.
- KPI row: 105 px.
- Middle row: 315 px.
- Bottom row: 270 px.
- Footer: 70 px.

Place the Year and Crime Type parameter controls in the upper-right. Use **Single Value (dropdown)** style. Do not add separate filter cards for every worksheet.

Suggested worksheet titles:

- **Reported Incidents by Day and Hour**
- **Monthly Reported-Incident Trend**
- **Reported Incidents by Season**
- **Reported Incidents by Time of Day**
- **Monthly Patterns for Leading Crime Types**

Only the heatmap requires a continuous color legend. The category comparison keeps its crime-type legend. Hide redundant legends elsewhere.

Dashboard interaction behavior is control-driven: Year and Crime Type update every worksheet. Do not add a heatmap-to-time-band filter action for the initial implementation; it would make KPI scope less obvious. Hover tooltips remain enabled. Selecting a mark may highlight it, but should not filter other worksheets.

Footer text:

```text
Source extract: Sep 25, 2026 | Incident dates: Jan 1, 2023–Dec 31, 2025 | Complete years
Counts are reported incidents, not population-normalized crime rates. Recorded incident times may be estimated. Seasonal and hourly patterns are descriptive and do not establish causation.
```

## 6. Manual validation checklist

### A. 2025 / All Crime Types

1. Set Year to `2025` and Crime Type to `All Crime Types`.
2. Confirm Total Incidents = **238,086**.
3. Confirm Peak Recorded Hour = **00:00 / 16,749**.
4. Confirm Peak Day = **Friday / 35,445**.
5. Confirm Peak Month = **July / 22,710**.
6. Confirm the heatmap's largest cell is **Saturday at hour 0 / 2,656**.
7. Confirm season totals are 52,738; 60,120; 65,283; 59,945 in documented order and sum to 238,086.
8. Confirm time-band totals are 46,595; 50,349; 74,654; 66,488 and sum to 238,086.
9. Confirm the category comparison contains exactly the five documented leading categories.

### B. 2025 / THEFT

1. Set Year to `2025` and Crime Type to `THEFT`.
2. Confirm Total Incidents = **55,198**.
3. Confirm Peak Recorded Hour = **12:00 / 3,748**.
4. Confirm Peak Day = **Friday / 8,421**.
5. Confirm Peak Month = **July / 5,404**.
6. Confirm the heatmap's largest cell is **Friday at hour 12 / 590**.
7. Confirm season totals are 12,413; 13,855; 15,346; 13,584 and sum to 55,198.
8. Confirm time-band totals are 7,877; 12,541; 21,131; 13,649 and sum to 55,198.
9. Confirm the category comparison contains one THEFT line and its monthly marks sum to 55,198.

### C. Year control

1. Change Year from 2025 to 2024, then 2023.
2. Confirm total incidents change to **259,633** and **263,844**, respectively.
3. Confirm the monthly axis remains January–December for the selected year.
4. Confirm KPI Top 1 values recalculate. If not, verify both selected filters are context filters on K2–K4.

### D. Crime Type control

1. Return to Year 2025.
2. Switch between All Crime Types, THEFT, BATTERY, and another category.
3. Confirm every worksheet changes, including all four KPIs.
4. Confirm the category comparison shows the top five only for All and the selected single category otherwise.

### E. Ordering and reconciliation

- Heatmap rows: Monday through Sunday.
- Heatmap columns: 0 through 23.
- Monthly trend: chronological date order; never alphabetical month names.
- Seasons: Winter, Spring, Summer, Fall.
- Time bands: Night, Morning, Afternoon, Evening.
- For every filter state, monthly, seasonal, time-band, weekday, and hourly totals must each reconcile to the Total Incidents KPI.
- Do not mark Page 3 complete until the workbook has been saved, reopened, and these checks pass in Tableau Desktop.

## 7. Prepared-data limitations

- The two Page 3 CSVs are generated data and remain excluded from Git; regenerate them from PostgreSQL when needed.
- No zero-count month × type × weekday × hour combinations are inserted. Tableau still displays all 12 months, seven weekdays, and 24 hours for the validated 2025 All/THEFT states because each combination is observed.
- The source uses the City's recorded incident timestamp without timezone conversion.
- A high count at midnight does not prove that incidents occurred precisely at midnight.
- Meteorological-season counts are not adjusted for differing month or season lengths.
- No forecasting, causal inference, or formal seasonality test is implemented.
