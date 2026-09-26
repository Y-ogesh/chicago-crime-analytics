# Core SQL Analysis Report

## Scope and execution

Milestone 5 analyzed `public.clean_chicago_crimes` using 29 documented queries in [`sql/04_business_analysis.sql`](../sql/04_business_analysis.sql). Every query was executed successfully on September 25, 2026 against PostgreSQL 14.20 inside `BEGIN TRANSACTION READ ONLY`.

The analytical population contains 761,563 retained source-ID records dated January 1, 2023 through December 31, 2025. All three years passed the documented complete-calendar-year rule. Unless a query explicitly applies geographic eligibility, every record remains in scope, including 6,697 incidents without map-eligible coordinates.

Run the complete suite from the repository root with:

```bash
psql -d chicago_crime -X -v ON_ERROR_STOP=1 \
  -f sql/04_business_analysis.sql
```

## Interpretation rules

- Every count is a **reported incident count**, not a population-normalized crime rate.
- `arrest_pct` describes the source `arrest` indicator. It is not a clearance, prosecution, or conviction rate.
- Domestic percentages describe the source domestic-related indicator and cannot measure unreported domestic violence.
- Annual changes compare adjacent complete calendar years using identical citywide scope.
- Community-area and police-district comparisons are counts without population, land-area, visitor, or exposure adjustment.
- Source incident timestamps may be estimated. Temporal concentrations, especially exact-hour results, require caution.
- Results are descriptive associations and do not establish causes.

## Query catalog

Each SQL query contains its business question, metric definition, assumptions, and denominator immediately above the executable statement.

| Query | Analytical output | Primary denominator |
|---|---|---|
| Q01 | Dataset overview and geographic coverage | All clean records |
| Q02 | Reported incidents by complete year | All clean records for share |
| Q03 | Adjacent-year citywide change | Prior complete-year count |
| Q04 | Primary-category distribution | All clean records |
| Q05 | Fixed top-ten categories by year | Corresponding year count |
| Q06 | Leading primary-type/description pairs | All clean records |
| Q07 | Top descriptions within major categories | Corresponding category count |
| Q08 | Pooled calendar-month pattern | All clean records; three complete years for average |
| Q09 | Year-month trend | Not applicable to count |
| Q10 | ISO weekday pattern and daily average | All records; observed dates for daily average |
| Q11 | Hourly pattern | All clean records |
| Q12 | Four time-of-day bands | All clean records |
| Q13 | Weekday versus weekend | All records; observed dates for daily average |
| Q14 | All 77 eligible community-area counts | Eligible-area and citywide populations, separately |
| Q15 | Community-area eligibility by year | Corresponding year count |
| Q16 | Adjacent-year change for all eligible community areas | Prior-year area count |
| Q17 | Current-reference police districts | Records matching current reference |
| Q18 | District reference-status coverage | All clean records |
| Q19 | Leading location descriptions | All clean records |
| Q20 | Unknown location-description coverage | Corresponding year count |
| Q21 | Arrest percentage overall and by year | Non-null arrest indicators in scope |
| Q22 | Arrest percentage by primary category | Non-null arrest indicators in category |
| Q23 | Arrest percentage by year for major categories | Non-null indicators in category-year |
| Q24 | Domestic percentage overall and by year | Non-null domestic indicators in scope |
| Q25 | Domestic percentage by primary category | Non-null domestic indicators in category |
| Q26 | Domestic percentage by time of day | Non-null domestic indicators in band |
| Q27 | Seasonal distribution | All clean records |
| Q28 | Seasonal distribution within major categories | Corresponding category count |
| Q29 | Cross-query reconciliation | Canonical clean-table count |

“Major categories” means the ten primary types with the largest full-period reported incident counts, ordered deterministically by count and then category name. The fixed set is: `THEFT`, `BATTERY`, `CRIMINAL DAMAGE`, `MOTOR VEHICLE THEFT`, `ASSAULT`, `OTHER OFFENSE`, `DECEPTIVE PRACTICE`, `ROBBERY`, `BURGLARY`, and `WEAPONS VIOLATION`. No broader crime taxonomy was created.

## Dataset overview and annual change

| Measure | Verified result |
|---|---:|
| Reported incidents | 761,563 |
| Distinct source IDs | 761,563 |
| Complete years | 3 |
| Source primary types | 31 |
| Community-area eligible | 760,496 (99.8599%) |
| Coordinate-mappable | 754,866 (99.1206%) |

| Year | Reported incidents | Share of extract | Absolute change | Year-over-year change |
|---:|---:|---:|---:|---:|
| 2023 | 263,844 | 34.6451% | — | — |
| 2024 | 259,633 | 34.0921% | -4,211 | -1.5960% |
| 2025 | 238,086 | 31.2628% | -21,547 | -8.2990% |

The executed adjacent-year calculation shows lower citywide reported incident counts in both comparisons. These changes describe the extracted reported-crime records and do not identify why counts changed.

## Crime categories and descriptions

### Leading primary categories

| Rank | Primary type | Reported incidents | Share of all records |
|---:|---|---:|---:|
| 1 | Theft | 173,282 | 22.7535% |
| 2 | Battery | 133,150 | 17.4838% |
| 3 | Criminal Damage | 84,903 | 11.1485% |
| 4 | Motor Vehicle Theft | 68,225 | 8.9585% |
| 5 | Assault | 67,730 | 8.8936% |
| 6 | Other Offense | 49,767 | 6.5349% |
| 7 | Deceptive Practice | 49,445 | 6.4926% |
| 8 | Robbery | 25,996 | 3.4135% |
| 9 | Burglary | 25,671 | 3.3708% |
| 10 | Weapons Violation | 21,896 | 2.8751% |

Theft was the largest source primary type in every year: 57,526 in 2023, 60,558 in 2024, and 55,198 in 2025. Motor Vehicle Theft counts were 29,256, 21,712, and 17,257 respectively. These are category counts, not rates, and source classifications can be revised.

### Leading primary-type/description combinations

| Primary type | Description | Reported incidents | Share of all records |
|---|---|---:|---:|
| Battery | Domestic Battery Simple | 59,126 | 7.7638% |
| Theft | $500 and Under | 53,547 | 7.0312% |
| Theft | Over $500 | 52,797 | 6.9327% |
| Motor Vehicle Theft | Automobile | 49,329 | 6.4773% |
| Criminal Damage | To Vehicle | 46,591 | 6.1178% |
| Battery | Simple | 46,400 | 6.0927% |
| Assault | Simple | 44,191 | 5.8027% |
| Theft | Retail Theft | 36,912 | 4.8469% |
| Criminal Damage | To Property | 35,230 | 4.6260% |
| Theft | From Building | 15,631 | 2.0525% |

The SQL also reports the three leading descriptions within each major primary category so that description meaning is not detached from its parent category.

## Temporal patterns

### Calendar month across three complete years

| Month | Reported incidents | Average per complete year | Share |
|---|---:|---:|---:|
| January | 59,680 | 19,893.33 | 7.8365% |
| February | 55,092 | 18,364.00 | 7.2341% |
| March | 61,627 | 20,542.33 | 8.0922% |
| April | 61,112 | 20,370.67 | 8.0245% |
| May | 65,919 | 21,973.00 | 8.6558% |
| June | 67,246 | 22,415.33 | 8.8300% |
| July | 70,970 | 23,656.67 | 9.3190% |
| August | 68,715 | 22,905.00 | 9.0229% |
| September | 66,131 | 22,043.67 | 8.6836% |
| October | 66,721 | 22,240.33 | 8.7611% |
| November | 59,736 | 19,912.00 | 7.8439% |
| December | 58,614 | 19,538.00 | 7.6965% |

July had the largest pooled monthly count and February the smallest. These totals are not adjusted for the number of days in each month, so they should not be interpreted as daily incidence rates.

### ISO weekday

| Day | Reported incidents | Observed dates | Average per observed date |
|---|---:|---:|---:|
| Monday | 109,184 | 157 | 695.44 |
| Tuesday | 107,342 | 157 | 683.71 |
| Wednesday | 107,978 | 157 | 687.76 |
| Thursday | 106,247 | 156 | 681.07 |
| Friday | 111,425 | 156 | 714.26 |
| Saturday | 110,404 | 156 | 707.72 |
| Sunday | 108,983 | 157 | 694.16 |

Friday had the largest count and largest average per observed date; Thursday had the smallest of both among weekdays. The differences are descriptive and relatively modest compared with the full-period daily volume.

### Time of day and weekday/weekend

| Time band | Reported incidents | Share |
|---|---:|---:|
| Overnight | 151,229 | 19.8577% |
| Morning | 157,694 | 20.7066% |
| Afternoon | 237,155 | 31.1406% |
| Evening | 215,485 | 28.2951% |

| Day group | Reported incidents | Observed dates | Average per observed date | Share |
|---|---:|---:|---:|---:|
| Weekday | 542,176 | 783 | 692.43 | 71.1925% |
| Weekend | 219,387 | 313 | 700.92 | 28.8075% |

The weekday total is larger because it represents five days per week versus two. On a per-observed-date basis, weekend dates averaged 700.92 records and weekdays averaged 692.43.

Midnight (`hour_of_day = 0`) had the largest exact-hour count at 54,217 (7.1192%), followed by noon at 43,582 (5.7227%). Because the source says incident times can be estimated, the midnight concentration may partly reflect timestamp-recording practices and should not be treated as a causal or precise operational peak without further source validation.

## Geographic and location patterns

### Leading eligible community areas

| Rank | Community area ID | Reported incidents | Share of eligible-area records |
|---:|---:|---:|---:|
| 1 | 25 | 37,464 | 4.9263% |
| 2 | 8 | 33,810 | 4.4458% |
| 3 | 28 | 31,729 | 4.1721% |
| 4 | 32 | 26,725 | 3.5142% |
| 5 | 43 | 25,447 | 3.3461% |
| 6 | 24 | 22,923 | 3.0142% |
| 7 | 23 | 20,212 | 2.6577% |
| 8 | 29 | 20,185 | 2.6542% |
| 9 | 71 | 19,657 | 2.5848% |
| 10 | 6 | 19,426 | 2.5544% |

All 77 eligible community-area IDs are returned by Q14. The table above is a count ranking, not a crime-rate ranking. No population source was introduced in this milestone.

| Year | Eligible area records | Unknown/unassigned | Coverage |
|---:|---:|---:|---:|
| 2023 | 263,447 | 397 | 99.8495% |
| 2024 | 259,292 | 341 | 99.8687% |
| 2025 | 237,757 | 329 | 99.8618% |

### Community-area year-over-year changes

Q16 returned both adjacent-year comparisons for all 77 eligible community areas: 154 area-year comparisons in total, with zero prior-year denominators equal to zero. The table shows the three largest absolute increases and decreases in each comparison; rankings use record-count change, not percentage change.

| Comparison | Direction | Community area | Prior count | Current count | Absolute change | Percentage change |
|---|---|---:|---:|---:|---:|---:|
| 2023–2024 | Increase | 28 | 10,424 | 10,979 | +555 | +5.3243% |
| 2023–2024 | Increase | 32 | 8,810 | 9,331 | +521 | +5.9137% |
| 2023–2024 | Increase | 7 | 3,940 | 4,316 | +376 | +9.5431% |
| 2023–2024 | Decrease | 29 | 7,151 | 6,616 | -535 | -7.4815% |
| 2023–2024 | Decrease | 44 | 6,392 | 5,866 | -526 | -8.2290% |
| 2023–2024 | Decrease | 49 | 6,115 | 5,642 | -473 | -7.7351% |
| 2024–2025 | Increase | 41 | 2,427 | 2,558 | +131 | +5.3976% |
| 2024–2025 | Increase | 52 | 1,303 | 1,412 | +109 | +8.3653% |
| 2024–2025 | Increase | 72 | 917 | 989 | +72 | +7.8517% |
| 2024–2025 | Decrease | 25 | 12,958 | 11,806 | -1,152 | -8.8903% |
| 2024–2025 | Decrease | 24 | 8,011 | 6,887 | -1,124 | -14.0307% |
| 2024–2025 | Decrease | 22 | 5,459 | 4,533 | -926 | -16.9628% |

These are changes in reported incident counts, not changes in population-normalized crime rates. The same 1–77 eligibility rule is applied in both years, and the changes are not interpreted causally.

### Leading current-reference police districts

| District | Reported incidents | Share of current-reference records |
|---:|---:|---:|
| 008 | 49,610 | 6.5230% |
| 012 | 47,142 | 6.1985% |
| 006 | 44,341 | 5.8302% |
| 001 | 43,013 | 5.6556% |
| 004 | 41,894 | 5.5084% |
| 011 | 41,074 | 5.4006% |
| 019 | 40,467 | 5.3208% |
| 018 | 40,171 | 5.2819% |
| 002 | 39,525 | 5.1969% |
| 003 | 39,166 | 5.1497% |

District `061` accounts for 1,020 records (0.1339% citywide) and remains flagged as unmatched to the current reference. It was retained and was not assumed invalid.

### Leading location descriptions

| Location description | Reported incidents | Share |
|---|---:|---:|
| Street | 209,744 | 27.5413% |
| Apartment | 145,962 | 19.1661% |
| Residence | 91,805 | 12.0548% |
| Sidewalk | 38,937 | 5.1128% |
| Parking Lot / Garage (Non Residential) | 27,197 | 3.5712% |
| Small Retail Store | 26,070 | 3.4232% |
| Alley | 17,360 | 2.2795% |
| Restaurant | 17,046 | 2.2383% |
| Department Store | 15,536 | 2.0400% |
| Other (Specify) | 12,739 | 1.6727% |

Unknown location-description percentages were 0.5882% in 2023, 0.4518% in 2024, and 0.5133% in 2025. These are missing categorical descriptions, not missing incidents.

## Arrest-indicator patterns

| Scope | Reported incidents | Arrest=true | Arrest denominator | Arrest percentage |
|---|---:|---:|---:|---:|
| All years | 761,563 | 106,475 | 761,563 | 13.9811% |
| 2023 | 263,844 | 32,219 | 263,844 | 12.2114% |
| 2024 | 259,633 | 35,891 | 259,633 | 13.8237% |
| 2025 | 238,086 | 38,365 | 238,086 | 16.1139% |

The source arrest percentage increased across the three complete-year results even while total reported incident counts declined. This juxtaposition does not establish that enforcement, clearance, or case outcomes improved; the field only indicates whether an arrest was recorded.

For the ten major categories, full-period arrest percentages included Weapons Violation at 64.2218%, Other Offense at 18.5304%, Battery at 17.3669%, Assault at 11.1634%, Robbery at 7.7820%, Theft at 6.9124%, Burglary at 5.5198%, Criminal Damage at 3.7631%, Deceptive Practice at 3.5595%, and Motor Vehicle Theft at 2.9241%. Q23 supplies category-year numerators and denominators; for example, Weapons Violation increased from 58.0207% in 2023 to 78.1858% in 2025. These are arrest-indicator percentages, not clearance or conviction rates.

## Domestic-indicator patterns

| Scope | Reported incidents | Domestic=true | Domestic denominator | Domestic percentage |
|---|---:|---:|---:|---:|
| All years | 761,563 | 140,243 | 761,563 | 18.4152% |
| 2023 | 263,844 | 47,206 | 263,844 | 17.8916% |
| 2024 | 259,633 | 47,718 | 259,633 | 18.3790% |
| 2025 | 238,086 | 45,319 | 238,086 | 19.0347% |

The largest category-level domestic percentages were Offense Involving Children (76.1157%), Battery (53.4022%), Stalking (48.1618%), Kidnapping (38.0368%), and Other Offense (36.2067%). Percentages with small category denominators should be interpreted cautiously; Q25 reports every numerator and denominator.

| Time band | Reported incidents | Domestic=true | Domestic percentage |
|---|---:|---:|---:|
| Overnight | 151,229 | 32,441 | 21.4516% |
| Morning | 157,694 | 29,773 | 18.8802% |
| Afternoon | 237,155 | 36,654 | 15.4557% |
| Evening | 215,485 | 41,375 | 19.2009% |

## Seasonal patterns

| Season | Reported incidents | Share |
|---|---:|---:|
| Winter | 173,386 | 22.7671% |
| Spring | 188,658 | 24.7725% |
| Summer | 206,931 | 27.1719% |
| Fall | 192,588 | 25.2885% |

Summer had the largest pooled seasonal count. Among the ten major categories, summer also had the largest within-category share for Theft (27.9065%), Battery (27.4593%), Assault (27.2479%), Criminal Damage (27.7634%), Motor Vehicle Theft (27.2349%), Robbery (27.8312%), and Weapons Violation (29.5168%). Burglary's largest seasonal share was Fall (28.3900%). These are unadjusted counts/shares across meteorological seasons and do not prove a weather effect.

## Validation evidence

Q29 independently summed the major grouping dimensions back to the canonical table population.

| Validation check | Difference from 761,563 |
|---|---:|
| Year totals | 0 |
| Primary-category totals | 0 |
| Month totals | 0 |
| Weekday totals | 0 |
| Hour totals | 0 |
| Time-of-day totals | 0 |
| Weekday/weekend totals | 0 |
| District totals | 0 |
| Location-description totals | 0 |
| Season totals | 0 |
| Eligible plus ineligible community-area partition | 0 |

Null arrest indicators: 0. Null domestic indicators: 0. Therefore the overall arrest and domestic denominators equal all 761,563 records. The analysis transaction committed without SQL errors and did not modify database state.

## Advanced SQL extension

Milestone 6 adds [`sql/05_advanced_analysis.sql`](../sql/05_advanced_analysis.sql), executed successfully on September 26, 2026 with stop-on-error behavior. It creates seven non-materialized views: the official community-area lookup plus `vw_executive_kpis`, `vw_yearly_crime_trends`, `vw_community_area_yoy`, `vw_crime_type_trends`, `vw_temporal_patterns`, and `vw_geographic_crime_points`. The views centralize definitions for later Python and Tableau work without duplicating the raw or clean tables.

The extension uses CTEs, `LAG`, `RANK`, `DENSE_RANK`, partitioned windows, conditional aggregation, three-month rolling averages, and percentage-of-total calculations. It also distinguishes community-area ranking methods: absolute-change ranks cover all 77 areas, while percentage-change ranks require a prior-year baseline of at least 500 reported incidents. That threshold retained 75 areas in each adjacent-year comparison and bounds a one-record change to at most 0.2 percentage points at the baseline.

### Verified 2024–2025 comparisons

| Result | Previous value | Current value | Absolute change | Percentage change |
|---|---:|---:|---:|---:|
| Citywide reported incidents | 259,633 | 238,086 | -21,547 | -8.2990% |
| Forest Glen reported incidents | 545 | 409 | -136 | -24.9541% |
| Austin reported incidents | 12,958 | 11,806 | -1,152 | -8.8903% |
| Robbery reported incidents | 9,120 | 5,817 | -3,303 | -36.2171% |
| Arrest-indicator percentage | 13.8237% | 16.1139% | +2.2902 percentage points | +16.5670% relative |

Forest Glen ranked first for percentage decrease among the 75 baseline-eligible areas but 46th for absolute decrease. Austin ranked first for absolute decrease among all 77 areas but 34th for percentage decrease among eligible areas. Seventy-one areas decreased and six increased. All 12 months in 2025 were below the corresponding 2024 month. These results demonstrate why percentage, volume, and temporal consistency must be reported separately.

The supplied citywide candidate (260,381 to 237,849, described as 8.7%) was not reproduced: those candidate counts calculate to -8.6535%, while the canonical extract produced 259,633 to 238,086 (-8.2990%). The supplied Forest Glen candidate of -25.1% was also not exact: 545 to 409 calculates to -24.9541%, or -25.0% at one decimal. No filters or definitions were changed to target either candidate. Full claim-level evidence, denominators, and caveats are in [quantified findings](quantified_findings.md).

Both observed citywide adjacent-year comparisons were decreases, so the extrema query reports 2024–2025 as the largest decrease and an explicit null result for largest increase rather than implying that a positive comparison occurred.

### Advanced validation

- The official lookup returned 77 rows and 77 distinct area IDs.
- `vw_community_area_yoy` returned 154 rows: 77 areas for each of two adjacent-year comparisons, with zero prior-year denominators equal to zero.
- Annual, primary-type, and monthly view totals reconciled to the clean table with zero differences for every year.
- Community-area view totals reconciled to 259,292 eligible records in 2024 and 237,757 in 2025 with zero differences.
- `vw_geographic_crime_points` returned exactly 754,866 coordinate-mappable records.
- Raw versus clean citywide and valid-community-area annual counts differed by zero in 2023, 2024, and 2025.
- `vw_executive_kpis` returned exactly one row. The script's fail-fast validation block completed without raising an exception.

## Limitations

- Reported-crime data does not include all crime and may reflect reporting practices, administrative processes, and later revisions.
- Murder rows represent victims according to the source, so row counts and case counts can differ conceptually.
- Community-area and district results are raw reported incident counts without population or exposure denominators.
- Location descriptions and approximate coordinates do not establish exact incident locations.
- Exact incident timestamps may be estimated; no causal operational conclusion should be drawn from hourly patterns alone.
- Arrest and domestic indicators provide limited source-record attributes, not complete case histories or outcomes.
- Seasonal and temporal differences were not adjusted for month length, holidays, population movement, weather, or other contextual factors.
- This report presents verified descriptive findings only. It does not make resource-planning recommendations.
