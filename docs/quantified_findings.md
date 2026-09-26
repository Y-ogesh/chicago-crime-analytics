# Quantified Portfolio Findings

## Scope and evidence standard

These findings were produced from `public.clean_chicago_crimes` using [`sql/05_advanced_analysis.sql`](../sql/05_advanced_analysis.sql) and independently validated from record-level data in [`01_data_validation.ipynb`](../notebooks/01_data_validation.ipynb). The canonical population is 761,563 source-ID-distinct reported incident records dated January 1, 2023 through December 31, 2025. All annual comparisons use adjacent complete calendar years and the same record scope in both periods. Counts are reported incident counts, not population-normalized crime rates, and the results do not establish causation.

The script was executed with stop-on-error behavior against PostgreSQL 14.20. It created seven non-materialized analytical views, ran all analytical outputs, and passed fail-fast reconciliation against `raw_chicago_crimes`. Raw and clean citywide counts, plus raw and clean valid-community-area counts, differed by zero in each of 2023, 2024, and 2025.

## Independent Python validation

The Milestone 7 validation notebook executed nine code cells from a fresh kernel with zero errors and passed all 10 gates. Pandas independently aggregated the canonical records rather than using view totals as inputs. Python and SQL differed by zero for all three annual counts, both year-over-year percentages within a `1e-10` tolerance, 760,496 community-area-eligible records, and all values and ranks across 154 community-area comparisons. Forest Glen and Austin reproduced exactly. The exploratory notebook executed 14 code cells with zero errors and generated eight reviewed Matplotlib figures. Full evidence is in the [Python EDA report](python_eda_report.md).

## Geographic validation and findings

[`03_geographic_analysis.ipynb`](../notebooks/03_geographic_analysis.ipynb) executed 15 code cells with zero errors and passed all 14 geographic checks. It reconciled 760,496 community-area-eligible records (99.8599% coverage), 754,866 coordinate-mappable records (99.1206% coverage), all 77 community-area totals, and all 154 adjacent-year area comparisons to SQL with zero observed difference. The 6,697 coordinate-ineligible records remained in applicable non-coordinate analyses.

The executed analysis verified that Austin had the largest three-year community-area incident volume at 37,464 records (4.9263% of valid-area records), while district `008` had the largest observed district-code volume at 49,610 records (6.5142% of all records). For the ten highest-volume source categories, Theft had the largest share concentrated in its five highest-volume community areas at 28.1744%; this is a descriptive concentration measure, not a population rate or spatial-significance result. Austin, Near North Side, Near West Side, Loop, South Shore, and West Town held the same volume ranks 1 through 6 in every year. Full methodology and limitations are in the [geographic analysis report](geographic_analysis_report.md).

## Supplied candidate claims

### Citywide 8.7% decline from 260,381 to 237,849 — not supported exactly

- **Finding statement:** The canonical extract supports a citywide decline, but not the supplied counts or percentage. Reported incident records decreased from 259,633 in 2024 to 238,086 in 2025.
- **Exact period:** January 1–December 31, 2024 versus January 1–December 31, 2025.
- **Previous value:** 259,633 reported incidents.
- **Current value:** 238,086 reported incidents.
- **Absolute change:** -21,547 reported incidents.
- **Percentage change:** -8.2990%, using `(238,086 - 259,633) / 259,633 * 100`.
- **Supporting SQL:** A01 and E01 in [`sql/05_advanced_analysis.sql`](../sql/05_advanced_analysis.sql); reusable result in `vw_yearly_crime_trends`.
- **Supporting Python:** Independent annual aggregation and validation gate in [`01_data_validation.ipynb`](../notebooks/01_data_validation.ipynb).
- **Denominator:** 259,633 reported incidents in the prior complete calendar year.
- **Caveats:** The supplied 260,381-to-237,849 values imply -8.6535%, not exactly -8.7% before display rounding. The current extract differs by -748 records in the proposed prior value and +237 in the proposed current value. No filters were changed to reproduce the candidate. Source records can be revised after extraction.

### Forest Glen 25.1% decline — direction supported, exact percentage not supported

- **Finding statement:** Forest Glen had the largest 2024–2025 percentage decrease among community areas meeting the 500-incident prior-year threshold, but its verified decline was 24.9541%, which rounds to 25.0% at one decimal rather than 25.1%.
- **Exact period:** January 1–December 31, 2024 versus January 1–December 31, 2025.
- **Previous value:** 545 reported incidents.
- **Current value:** 409 reported incidents.
- **Absolute change:** -136 reported incidents.
- **Percentage change:** -24.9541%, using `(409 - 545) / 545 * 100`.
- **Supporting SQL:** B01, B02, and E01 in [`sql/05_advanced_analysis.sql`](../sql/05_advanced_analysis.sql); reusable result in `vw_community_area_yoy` for community area 12.
- **Supporting Python:** Complete 77-area grid, adjacent-year calculation, and rank reproduction in [`01_data_validation.ipynb`](../notebooks/01_data_validation.ipynb).
- **Denominator:** 545 Forest Glen reported incidents in the prior complete calendar year.
- **Caveats:** Percentage rank 1 applies only among areas with at least 500 prior-year incidents; 75 of 77 areas qualified for the 2024–2025 percentage ranking. Forest Glen ranked 46th for absolute decrease, demonstrating that proportional and volume impacts are different. This is a count comparison, not a population-normalized rate.

## Additional verified candidate findings

### Austin had the largest absolute community-area decrease in 2025

- **Finding statement:** Austin recorded the largest absolute 2024–2025 decrease among all 77 official community areas.
- **Exact period:** January 1–December 31, 2024 versus January 1–December 31, 2025.
- **Previous value:** 12,958 reported incidents.
- **Current value:** 11,806 reported incidents.
- **Absolute change:** -1,152 reported incidents.
- **Percentage change:** -8.8903%.
- **Supporting SQL:** B01 in [`sql/05_advanced_analysis.sql`](../sql/05_advanced_analysis.sql); `absolute_decrease_rank = 1` in `vw_community_area_yoy`.
- **Supporting Python:** Community-area comparison in both executed notebooks; see [`01_data_validation.ipynb`](../notebooks/01_data_validation.ipynb).
- **Denominator:** 12,958 Austin reported incidents in 2024.
- **Caveats:** Austin ranked 34th by percentage decrease among baseline-eligible areas. Community-area counts are not adjusted for population, land area, commuting, tourism, or exposure.

### Robbery showed the largest percentage decline among the ten largest absolute category changes

- **Finding statement:** Robbery records decreased from 9,120 in 2024 to 5,817 in 2025, a decline of 3,303 records or 36.2171%. Among the ten source categories with the largest absolute changes that year, this was the largest percentage decrease.
- **Exact period:** January 1–December 31, 2024 versus January 1–December 31, 2025.
- **Previous value:** 9,120 reported incidents.
- **Current value:** 5,817 reported incidents.
- **Absolute change:** -3,303 reported incidents.
- **Percentage change:** -36.2171%.
- **Supporting SQL:** C04 in [`sql/05_advanced_analysis.sql`](../sql/05_advanced_analysis.sql); reusable result in `vw_crime_type_trends`.
- **Supporting Python:** Annual source-category trend calculation in [`02_exploratory_analysis.ipynb`](../notebooks/02_exploratory_analysis.ipynb).
- **Denominator:** 9,120 robbery records in 2024.
- **Caveats:** `primary_type` is the official source category and can be revised. The comparison does not measure prevalence among unreported crimes and does not identify a cause.

### Arrest-indicator percentage increased while reported incident volume declined

- **Finding statement:** The share of records marked `arrest = true` increased from 13.8237% in 2024 to 16.1139% in 2025.
- **Exact period:** January 1–December 31, 2024 versus January 1–December 31, 2025.
- **Previous value:** 13.8237% (35,891 arrest-flagged records / 259,633 non-null indicators).
- **Current value:** 16.1139% (38,365 arrest-flagged records / 238,086 non-null indicators).
- **Absolute change:** +2.2902 percentage points.
- **Percentage change:** +16.5670% relative to the 2024 percentage.
- **Supporting SQL:** C05 in [`sql/05_advanced_analysis.sql`](../sql/05_advanced_analysis.sql); underlying annual numerator and denominator are also documented in the [core SQL analysis report](sql_analysis_report.md).
- **Supporting Python:** Independently calculated annual numerators, denominators, and percentages in [`02_exploratory_analysis.ipynb`](../notebooks/02_exploratory_analysis.ipynb).
- **Denominator:** All records with a non-null arrest indicator in each year; the current extract has zero null arrest indicators.
- **Caveats:** This is an arrest-indicator percentage, not a clearance, prosecution, or conviction rate. It does not establish when an arrest occurred or why the percentage changed.

## Supporting advanced patterns

- Both observed citywide year-over-year comparisons were decreases: -1.5960% for 2023–2024 and -8.2990% for 2024–2025. A02 identifies 2024–2025 as the largest observed decrease and explicitly returns no observed increase.
- Seventy-one of 77 community areas had lower reported incident counts in 2025 than in 2024; six increased and none were unchanged. B01 and `vw_community_area_yoy` provide the underlying area-level results.
- Every month of 2025 had a lower reported incident count than the same calendar month of 2024. C01 and `vw_temporal_patterns` provide all 12 comparisons and trailing three-month averages.
- Austin, Near North Side, Near West Side, Loop, South Shore, West Town, Humboldt Park, North Lawndale, and Auburn Gresham ranked in the ten highest-volume community areas in all three complete years. C03 uses partitioned annual ranks; these are persistent count concentrations, not population-normalized risk rankings.
- The 2025 source-category changes with the largest absolute magnitude were Theft (-5,360), Motor Vehicle Theft (-4,455), Battery (-3,527), and Robbery (-3,303). Narcotics (+1,421) and Burglary (+1,303) increased, so the citywide decline was not uniform across categories.
- Geographic coverage is measure-specific: 99.8599% of records support named community-area analysis, while 99.1206% support coordinate-density displays. Missing coordinates do not remove records from non-coordinate analysis.
- District `008` had the largest observed three-year district-code count (49,610), and its count decreased by 2,011 records from 2024 to 2025 (-11.6317%). District counts are not population-normalized rates or workload prescriptions.
- Among leading location descriptions, Street and Alley records were most concentrated in the Evening band; the other eight leading descriptions peaked in Afternoon. Department Store had 51.0041% of its records in Afternoon. Source times may be estimated, and the result is descriptive.

## Interview-defensible portfolio statements

The following wording stays within the executed evidence:

- Analyzed 761,563 official Chicago reported-crime records across three complete calendar years and reconciled annual SQL and independent Pandas totals with zero count differences.
- Built seven reusable PostgreSQL views using CTEs, `LAG`, `RANK`, `DENSE_RANK`, partitioned windows, conditional aggregation, rolling averages, and percentage-of-total calculations.
- Verified a 21,547-record citywide decline from 2024 to 2025 (-8.2990%) and produced all 154 adjacent-year comparisons across Chicago's 77 official community areas.
- Distinguished proportional from operational-volume change: Forest Glen ranked first for percentage decrease (-24.9541%; -136 records), while Austin ranked first for absolute decrease (-1,152 records; -8.8903%).
- Validated geographic coverage and created five reproducible Tableau-ready datasets after reconciling all 77 community-area totals and 754,866 coordinate-mappable records to SQL with zero differences.

These statements describe completed SQL and independently reconciled Python/geographic work. Tableau validation, resource-planning recommendations, and final resume packaging remain future milestones.

## Limitations

- The data represents reported incidents and does not include unreported crime; murder rows represent victims according to the source.
- Source records and classifications can be updated after the project's extraction.
- Community-area results exclude 1,067 records with missing or invalid source community-area values but retain those records in citywide analysis.
- Geographic point mapping excludes 6,697 records without map-eligible coordinates, while non-geographic analyses retain them.
- Counts are not adjusted for population or exposure and must not be called crime rates.
- Observed changes are descriptive and do not demonstrate causes or intervention effects.
