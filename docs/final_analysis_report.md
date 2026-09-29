# Final Analysis Report

## 1. Executive summary

This project analyzed 761,563 source-ID-distinct records from the official City of Chicago Crimes dataset (`ijzp-q8t2`) covering the three complete calendar years January 1, 2023 through December 31, 2025. PostgreSQL, independently executed Pandas notebooks, geographic analysis, and four Tableau dashboards were reconciled before publication.

Seven findings provide the strongest decision-relevant summary:

1. Citywide reported incidents decreased from 259,633 in 2024 to 238,086 in 2025, a reduction of 21,547 records or 8.2990%.
2. The citywide decline was not uniform by source crime category: Theft decreased by 5,360 records, Motor Vehicle Theft by 4,455, Battery by 3,527, and Robbery by 3,303, while Narcotics increased by 1,421 and Burglary by 1,303.
3. Seventy-one of 77 community areas decreased in 2025. Forest Glen had the largest eligible percentage decrease at 24.9541% (-136 records), while Austin had the largest absolute decrease at 1,152 records (-8.8903%).
4. Every calendar month in 2025 was below its 2024 counterpart. Summer remained the largest seasonal count in 2025 at 65,283 records, or 27.4199% of that year's total.
5. Incident volume remained geographically concentrated by raw count: Austin led community areas with 37,464 records across 2023–2025, and District 008 led observed district codes with 49,610. These are counts, not population-normalized rates.
6. The arrest-indicator percentage increased from 13.8237% in 2024 to 16.1139% in 2025, a 2.2902 percentage-point increase, while citywide reported incident volume declined.
7. The domestic-indicator percentage increased from 17.8916% in 2023 to 19.0347% in 2025, a 1.1431 percentage-point increase. Across the full period, Overnight had the largest domestic-indicator percentage at 21.4516%.

The supplied candidate claims were not reproduced. The canonical extract supports a 2024–2025 citywide decline of 8.2990%, not 8.7%, and a Forest Glen decline of 24.9541%, not 25.1%. Filters and definitions were not changed to target proposed values.

## 2. Dataset and methodology

### Source and analytical population

- **Official source:** City of Chicago, *Crimes - 2001 to Present*, dataset ID `ijzp-q8t2`.
- **Extraction date:** September 25, 2026.
- **Authorized incident period:** January 1, 2023 through December 31, 2025.
- **Analytical population:** 761,563 records in `public.clean_chicago_crimes`, with 761,563 distinct source IDs.
- **Complete-year rule:** Only January 1–December 31 periods were used for annual year-over-year comparisons. Partial-year 2026 data was not acquired or compared with complete years.

The immutable source extract was loaded into PostgreSQL without changing raw records. The clean analytical table applied documented timestamp parsing, blank normalization, geographic validation, and deterministic source-ID deduplication. The source contained no duplicate IDs, so cleaning removed zero records. Records without valid coordinates remained eligible for non-coordinate analysis.

### Analytical definitions

- **Reported incident count:** Count of in-scope records. It is not a population-normalized crime rate. The source notes that murder rows represent victims, so rows are not universally equivalent to criminal cases.
- **Year-over-year change:** `(current complete-year count - prior complete-year count) / prior complete-year count * 100` for identical analytical scopes.
- **Arrest percentage:** Records marked `arrest = true` divided by records with a non-null arrest indicator. The current extract has no null arrest indicators. This is not a clearance, prosecution, or conviction rate.
- **Domestic incident percentage:** Records marked `domestic = true` divided by records with a non-null domestic indicator. The current extract has no null domestic indicators.
- **Community-area percentage ranking:** All 77 areas are retained, but percentage-change ranks require at least 500 prior-year incidents; 75 areas qualified for 2024–2025.
- **Geographic coverage:** Coordinate-mappable records divided by all in-scope records. Missing coordinates are excluded from maps, not from applicable non-geographic totals.

### Reproducibility and validation

Core and advanced SQL are in [`sql/04_business_analysis.sql`](../sql/04_business_analysis.sql) and [`sql/05_advanced_analysis.sql`](../sql/05_advanced_analysis.sql). Final published values were rerun through the read-only [`sql/13_final_findings_validation.sql`](../sql/13_final_findings_validation.sql), which completed with stop-on-error behavior and rolled back its read-only transaction. Independent record-level checks are in [`01_data_validation.ipynb`](../notebooks/01_data_validation.ipynb), [`02_exploratory_analysis.ipynb`](../notebooks/02_exploratory_analysis.ipynb), and [`03_geographic_analysis.ipynb`](../notebooks/03_geographic_analysis.ipynb). SQL and Pandas differed by zero for annual counts, geographic eligibility, and all 154 adjacent-year community-area comparisons.

## 3. Citywide trends

### Finding 1 — the verified 2024–2025 decline was 8.2990%

- **Actual result:** Reported incidents decreased from 259,633 in 2024 to 238,086 in 2025: -21,547 records and -8.2990%. The earlier 2023–2024 comparison was -4,211 records, or -1.5960%.
- **Period:** Complete calendar year 2024 versus complete calendar year 2025.
- **Metric definition:** Reported incident count is `COUNT(*)` on the clean, source-ID-distinct analytical population. Year-over-year percentage change uses the prior complete-year count as the denominator.
- **Evidence:** F01 in [`sql/13_final_findings_validation.sql`](../sql/13_final_findings_validation.sql); A01, A02, and E01 in [`sql/05_advanced_analysis.sql`](../sql/05_advanced_analysis.sql); independent annual aggregation in [`01_data_validation.ipynb`](../notebooks/01_data_validation.ipynb).
- **Interpretation:** The extracted reported-incident population was lower in 2025, and the decline was larger than the one observed in 2024. The analysis does not determine whether reporting behavior, enforcement, prevention, population movement, administrative revision, or other factors produced the change.

The proposed 260,381-to-237,849 decline was not found. Those proposed counts imply -8.6535%, whereas the canonical extract produced 259,633 to 238,086 (-8.2990%).

## 4. Crime-category findings

### Finding 2 — category movement was materially uneven

- **Actual result:** From 2024 to 2025, Theft changed from 60,558 to 55,198 (-5,360; -8.8510%), Motor Vehicle Theft from 21,712 to 17,257 (-4,455; -20.5186%), Battery from 46,187 to 42,660 (-3,527; -7.6363%), and Robbery from 9,120 to 5,817 (-3,303; -36.2171%). Narcotics increased from 5,998 to 7,419 (+1,421; +23.6912%), and Burglary increased from 8,437 to 9,740 (+1,303; +15.4439%).
- **Period:** Complete calendar year 2024 versus complete calendar year 2025.
- **Metric definition:** Reported incident count grouped by the City's source `primary_type`; percentage change uses the prior category-year count as its denominator.
- **Evidence:** F02 in [`sql/13_final_findings_validation.sql`](../sql/13_final_findings_validation.sql); C04 and `vw_crime_type_trends` in [`sql/05_advanced_analysis.sql`](../sql/05_advanced_analysis.sql); annual category analysis in [`02_exploratory_analysis.ipynb`](../notebooks/02_exploratory_analysis.ipynb).
- **Interpretation:** A single citywide percentage obscures divergent category patterns. Robbery had the largest percentage decrease among the ten categories with the largest absolute 2025 changes, while Narcotics and Burglary moved against the citywide direction. These source categories can be reclassified and do not measure unreported offenses.

Across all three years, Theft remained the largest source category with 173,282 records, or 22.7535% of the extract. Its annual counts were 57,526, 60,558, and 55,198.

## 5. Community-area year-over-year findings

### Finding 3 — proportional and absolute change identify different areas

- **Actual result:** Seventy-one community areas decreased in 2025, six increased, and none were unchanged. Forest Glen fell from 545 to 409 (-136; -24.9541%) and ranked first for percentage decrease among the 75 areas meeting the 500-incident baseline threshold, but 46th for absolute decrease. Austin fell from 12,958 to 11,806 (-1,152; -8.8903%) and ranked first for absolute decrease across all 77 areas, but 34th for eligible percentage decrease.
- **Period:** Complete calendar year 2024 versus complete calendar year 2025.
- **Metric definition:** Community-area incident count includes records with a valid source community-area ID from 1 through 77. Absolute ranks use all areas; percentage ranks require at least 500 prior-year records.
- **Evidence:** F03 in [`sql/13_final_findings_validation.sql`](../sql/13_final_findings_validation.sql); B01, B02, E01, and `vw_community_area_yoy` in [`sql/05_advanced_analysis.sql`](../sql/05_advanced_analysis.sql); independent rank reproduction in [`01_data_validation.ipynb`](../notebooks/01_data_validation.ipynb).
- **Interpretation:** Forest Glen experienced the largest proportional change within the defensible baseline population, while Austin represented the largest reduction in record volume. Neither ranking is a population-normalized rate, and one should not substitute for the other when describing operational scale.

The supplied Forest Glen value of -25.1% was not reproduced. The verified calculation is `(409 - 545) / 545 * 100 = -24.9541%`, which displays as -25.0% at one decimal.

## 6. Temporal and seasonal findings

### Finding 4 — the 2025 decline appeared in every month while seasonal ordering persisted

- **Actual result:** All 12 calendar months in 2025 had fewer reported incidents than the corresponding months in 2024. Summer remained the largest meteorological season in every year: 71,206 records in 2023 (26.9879%), 70,442 in 2024 (27.1314%), and 65,283 in 2025 (27.4199%). Across the full period, Afternoon contained 237,155 records (31.1406%) and Evening 215,485 (28.2951%).
- **Period:** Monthly comparison of complete years 2024 and 2025; seasonal and time-band summaries cover January 1, 2023 through December 31, 2025.
- **Metric definition:** Months are calendar months; seasons are Winter (December–February), Spring (March–May), Summer (June–August), and Fall (September–November). Time bands are Overnight 00:00–05:59, Morning 06:00–11:59, Afternoon 12:00–17:59, and Evening 18:00–23:59.
- **Evidence:** F04 in [`sql/13_final_findings_validation.sql`](../sql/13_final_findings_validation.sql); C01 and `vw_temporal_patterns` in [`sql/05_advanced_analysis.sql`](../sql/05_advanced_analysis.sql); monthly, seasonal, weekday, and hourly analysis in [`02_exploratory_analysis.ipynb`](../notebooks/02_exploratory_analysis.ipynb).
- **Interpretation:** The annual decline was not driven by only one or two calendar months. Higher summer and afternoon/evening counts identify recurring descriptive workload windows, but month length, holidays, weather, exposure, and estimated incident times were not controlled; the patterns are not evidence of a seasonal or time-of-day cause.

Midnight was the largest exact recorded hour with 54,217 records (7.1192%), but the source warns that incident times can be estimated. Midnight should therefore not be treated as a precise event-time peak without additional source validation.

## 7. Geographic concentration findings

### Finding 5 — high-volume geographies persisted, with high but incomplete mapping coverage

- **Actual result:** Austin had 37,464 reported incidents across 2023–2025, or 4.9263% of the 760,496 community-area-eligible records. District 008 had 49,610 records, or 6.5142% of all records. Austin, Near North Side, Near West Side, Loop, South Shore, and West Town held community-area volume ranks 1–6 in the same order in every complete year. Community-area coverage was 99.8599%; coordinate-mapping coverage was 99.1206% (754,866 records), leaving 6,697 records unavailable for coordinate displays.
- **Period:** January 1, 2023 through December 31, 2025.
- **Metric definition:** Geography rankings are reported incident counts grouped by valid source community-area or observed district code. Coordinate coverage requires valid source latitude and longitude; it is independent of community-area eligibility.
- **Evidence:** F05 in [`sql/13_final_findings_validation.sql`](../sql/13_final_findings_validation.sql); executed analyses in [`03_geographic_analysis.ipynb`](../notebooks/03_geographic_analysis.ipynb); methodology and validations in [`docs/geographic_analysis_report.md`](geographic_analysis_report.md).
- **Interpretation:** Several areas repeatedly represented high raw incident volumes, supporting continued descriptive monitoring. These rankings do not measure individual risk or underlying incidence rates because population, commuting, tourism, land use, and other exposure denominators were not included. Coordinate concentrations are descriptive density, not statistically significant hotspots.

## 8. Arrest and domestic incident analysis

### Finding 6 — the arrest indicator increased while reported incident volume decreased

- **Actual result:** The arrest-indicator percentage increased from 13.8237% in 2024 (35,891 of 259,633 records) to 16.1139% in 2025 (38,365 of 238,086), an increase of 2.2902 percentage points. The 2023 value was 12.2114%.
- **Period:** Complete calendar year 2024 versus complete calendar year 2025, with 2023 shown for context.
- **Metric definition:** Records marked `arrest = true` divided by all records with a non-null arrest indicator. The extract has zero null arrest indicators.
- **Evidence:** F06 in [`sql/13_final_findings_validation.sql`](../sql/13_final_findings_validation.sql); C05 in [`sql/05_advanced_analysis.sql`](../sql/05_advanced_analysis.sql); independent indicator aggregation in [`02_exploratory_analysis.ipynb`](../notebooks/02_exploratory_analysis.ipynb); validated Page 4 Tableau screenshots.
- **Interpretation:** A larger share of 2025 incident rows carried an arrest flag, and the arrest-flag count increased despite lower total incident volume. This cannot be described as a higher clearance, prosecution, or conviction rate and does not explain why either numerator or denominator changed.

### Finding 7 — the domestic indicator's share increased, with the largest full-period percentage Overnight

- **Actual result:** The domestic-indicator percentage increased from 17.8916% in 2023 (47,206 of 263,844) to 19.0347% in 2025 (45,319 of 238,086), a 1.1431 percentage-point increase even though the flagged-record count was lower. Across 2023–2025, Overnight had the largest time-band domestic percentage at 21.4516% (32,441 of 151,229); Evening had the largest domestic-flag count at 41,375 of 215,485 records (19.2009%).
- **Period:** Annual trend from complete year 2023 through complete year 2025; time-band totals cover the full three-year extract.
- **Metric definition:** Records marked `domestic = true` divided by all records with a non-null domestic indicator in the stated scope. The extract has zero null domestic indicators.
- **Evidence:** F06 in [`sql/13_final_findings_validation.sql`](../sql/13_final_findings_validation.sql); Q24–Q26 in [`sql/04_business_analysis.sql`](../sql/04_business_analysis.sql); annual indicator analysis in [`02_exploratory_analysis.ipynb`](../notebooks/02_exploratory_analysis.ipynb); validated Page 4 Tableau screenshots.
- **Interpretation:** Domestic-flagged records represented a larger share of reported incidents even though their absolute count did not rise from 2023 to 2025. The source field does not capture unreported domestic violence, service needs, severity, or case outcome, and the temporal pattern does not establish causation.

## 9. Evidence-based recommendations

These recommendations are planning hypotheses grounded in descriptive evidence. They should be tested against operational context, service outcomes, staffing constraints, and community input before implementation.

| Recommendation | Evidence basis | Intended use and guardrail |
|---|---|---|
| Maintain a complete-year and same-month monitoring scorecard. | Citywide records fell 8.2990% in 2025, and all 12 months were below their 2024 counterparts. | Monitor whether the broad decline persists. Compare complete years or identical matched periods only; do not mix partial-year and full-year totals. |
| Review categories separately rather than applying a uniform citywide allocation rule. | Theft, Motor Vehicle Theft, Battery, and Robbery decreased, while Narcotics and Burglary increased. | Use category-specific workload reviews and qualitative context. A change in recorded incidents alone does not establish changed underlying prevalence or intervention effectiveness. |
| Use both absolute and proportional community-area change in planning discussions. | Austin led absolute decline (-1,152), while Forest Glen led eligible percentage decline (-24.9541%; -136). | Separate operational volume from proportional change. Add population or exposure denominators before describing relative risk or rates. |
| Treat summer and afternoon/evening patterns as candidate coverage windows for evaluation. | Summer was the largest season in every year; Afternoon and Evening together represented 59.4357% of full-period records. | Compare existing service availability with observed demand windows, then evaluate any scheduling change prospectively. Do not infer a weather or time-of-day cause, and do not treat midnight timestamps as precise without further validation. |
| Sustain focused analytical review of persistent high-volume geographies while preserving citywide coverage. | Six community areas retained ranks 1–6 in every year; Austin and District 008 had the largest three-year counts in their respective groupings. | Prioritize diagnostic review, not automatic enforcement intensity. Combine counts with population, foot traffic, land use, calls for service, and community input before resource decisions. |
| Review domestic-related service and referral capacity across Overnight and Evening periods. | Overnight had the largest domestic percentage (21.4516%); Evening had the largest domestic-flag count (41,375). | Use the pattern to examine availability of victim services, referral pathways, and trained response capacity. The data does not measure unreported need or demonstrate that schedule changes will improve outcomes. |
| Keep arrest percentage separate from outcome metrics. | The arrest indicator rose 2.2902 percentage points in 2025 while incident volume declined. | Report the source flag with numerator and denominator. Do not present it as clearance, prosecution, conviction, effectiveness, or causal evidence. |
| Retain non-geocoded incidents in all eligible non-map analysis and display coverage with maps. | Coordinate coverage was 99.1206%; 6,697 records lacked map-eligible coordinates. | Prevent maps from silently redefining the analytical population. Continue displaying geographic coverage and investigate data-quality improvements without imputing locations silently. |

## 10. Limitations and future work

### Limitations

- The dataset represents reported crime, not all crime. Reporting behavior, access to reporting, administrative practices, and later source revisions can affect counts.
- The source states that murder records represent victims, so a row is not universally equivalent to a distinct criminal case.
- The extract was taken on September 25, 2026 and can differ from later portal versions for the same incident dates.
- Only complete years 2023–2025 were used for annual comparisons. A partial current year must be labeled separately and compared only with an identical matched period, never with a complete-year total.
- Community-area, district, category, and temporal values are counts or shares, not population-normalized crime rates or individual-risk estimates.
- Community-area analysis excludes 1,067 records with missing or invalid source area values. Coordinate displays exclude 6,697 records without valid map coordinates; those records remain in applicable non-map analysis.
- Coordinates are approximate, and the dashboard's coordinate cells are resolution-dependent descriptive concentrations. No formal spatial-significance or hotspot test was performed.
- Incident times can be estimated. Exact-hour concentrations—especially midnight—may reflect recording practices.
- Arrest and domestic flags are limited source attributes, not complete case histories or outcome measures.
- Category labels can be revised, and the analysis does not control for month length, holidays, weather, population movement, enforcement activity, or other contextual variables.
- All recommendations are observational planning hypotheses. The analysis does not establish causes or predict the effect of resource changes.

### Future work

1. Add authoritative, year-aligned population and exposure data to calculate clearly labeled rates alongside—not in place of—incident counts.
2. Establish a reproducible matched-period current-year view that cannot be confused with complete-year year-over-year reporting.
3. Add formal spatial analysis only after documenting projection, neighborhood adjacency, multiple-testing, and statistical-significance methods.
4. Incorporate calls for service, service availability, land use, transit, and foot-traffic context where data quality and governance permit.
5. Evaluate any operational change prospectively with predefined outcome measures and comparison logic rather than attributing observed changes after implementation.
6. Refresh the official extract on a documented cadence and rerun all SQL, Python, Tableau, and narrative reconciliation gates before updating published findings.

The interactive evidence is retained in [`tableau/chicago_crime_analytics.twb`](../tableau/chicago_crime_analytics.twb), with validated screenshots and page-level specifications linked from the project [`README.md`](../README.md) and [Tableau dashboard plan](tableau_dashboard_plan.md).
