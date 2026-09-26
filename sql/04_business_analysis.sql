\set ON_ERROR_STOP on
\pset pager off
\pset null '[NULL]'
\timing on

BEGIN TRANSACTION READ ONLY;

\echo 'Q01 — Dataset overview and analytical coverage'
/*
Business question: What is the validated analytical scope and geographic coverage?
Metric definition: Reported incident count is COUNT(*) on clean_chicago_crimes;
  coverage percentages are eligible rows divided by all in-scope rows.
Assumptions: The clean table is canonical and 2023-2025 are complete calendar years.
Denominator: All 761,563 clean records for both coverage percentages.
*/
SELECT
    count(*) AS reported_incidents,
    count(DISTINCT source_id) AS distinct_source_ids,
    min(crime_date) AS minimum_crime_date,
    max(crime_date) AS maximum_crime_date,
    count(DISTINCT crime_year) AS complete_years,
    count(DISTINCT primary_type) AS primary_type_count,
    count(*) FILTER (WHERE community_area_eligible_flag) AS community_area_eligible,
    round(
        100.0 * count(*) FILTER (WHERE community_area_eligible_flag) / count(*),
        4
    ) AS community_area_coverage_pct,
    count(*) FILTER (WHERE coordinate_mappable_flag) AS coordinate_mappable,
    round(
        100.0 * count(*) FILTER (WHERE coordinate_mappable_flag) / count(*),
        4
    ) AS coordinate_coverage_pct
FROM public.clean_chicago_crimes;

\echo 'Q02 — Reported incidents by complete calendar year'
/*
Business question: How many reported incidents occurred in each complete year?
Metric definition: COUNT(*) grouped by crime_year; share is each year divided by
  the full three-year record count.
Assumptions: 2023, 2024, and 2025 passed the documented complete-year rule.
Denominator: All 761,563 clean records for record_share_pct.
*/
WITH totals AS (
    SELECT count(*)::numeric AS all_records
    FROM public.clean_chicago_crimes
)
SELECT
    crime_year,
    count(*) AS reported_incidents,
    round(100.0 * count(*) / totals.all_records, 4) AS record_share_pct
FROM public.clean_chicago_crimes
CROSS JOIN totals
GROUP BY crime_year, totals.all_records
ORDER BY crime_year;

\echo 'Q03 — Citywide year-over-year change'
/*
Business question: How did citywide reported incident counts change between
  adjacent complete calendar years?
Metric definition: 100 * (current count - prior count) / prior count; absolute
  change is current count minus prior count.
Assumptions: Only adjacent complete years with identical citywide scope are used;
  the result is descriptive and does not imply causation.
Denominator: The immediately preceding complete-year count; null for the first year
  or a zero prior-year count.
*/
WITH yearly AS (
    SELECT crime_year, count(*) AS reported_incidents
    FROM public.clean_chicago_crimes
    GROUP BY crime_year
),
with_prior AS (
    SELECT
        crime_year,
        reported_incidents,
        lag(reported_incidents) OVER (ORDER BY crime_year) AS prior_year_incidents
    FROM yearly
)
SELECT
    crime_year,
    reported_incidents,
    prior_year_incidents,
    reported_incidents - prior_year_incidents AS absolute_change,
    round(
        100.0 * (reported_incidents - prior_year_incidents)
            / nullif(prior_year_incidents, 0),
        4
    ) AS year_over_year_pct_change
FROM with_prior
ORDER BY crime_year;

\echo 'Q04 — Primary crime-category distribution'
/*
Business question: Which source primary crime categories account for the most
  reported incidents across the full period?
Metric definition: COUNT(*) grouped by preserved/standardized primary_type.
Assumptions: No broader category mapping is applied; City/IUCR primary types are used.
Denominator: All 761,563 clean records for incident_share_pct.
*/
WITH totals AS (
    SELECT count(*)::numeric AS all_records
    FROM public.clean_chicago_crimes
)
SELECT
    primary_type,
    count(*) AS reported_incidents,
    round(100.0 * count(*) / totals.all_records, 4) AS incident_share_pct
FROM public.clean_chicago_crimes
CROSS JOIN totals
GROUP BY primary_type, totals.all_records
ORDER BY reported_incidents DESC, primary_type;

\echo 'Q05 — Major crime categories by year'
/*
Business question: How do annual counts vary for the ten largest primary categories?
Metric definition: The major-category set is the top ten primary types by full-period
  COUNT(*); annual count and within-year share are then calculated for that fixed set.
Assumptions: Ties are resolved deterministically by primary_type after total count.
Denominator: All records in the corresponding crime_year for within_year_share_pct.
*/
WITH category_totals AS (
    SELECT primary_type, count(*) AS category_records
    FROM public.clean_chicago_crimes
    GROUP BY primary_type
),
major_categories AS (
    SELECT primary_type
    FROM category_totals
    ORDER BY category_records DESC, primary_type
    LIMIT 10
),
year_totals AS (
    SELECT crime_year, count(*)::numeric AS year_records
    FROM public.clean_chicago_crimes
    GROUP BY crime_year
)
SELECT
    crimes.crime_year,
    crimes.primary_type,
    count(*) AS reported_incidents,
    round(100.0 * count(*) / year_totals.year_records, 4) AS within_year_share_pct
FROM public.clean_chicago_crimes AS crimes
JOIN major_categories USING (primary_type)
JOIN year_totals USING (crime_year)
GROUP BY crimes.crime_year, crimes.primary_type, year_totals.year_records
ORDER BY crimes.crime_year, reported_incidents DESC, crimes.primary_type;

\echo 'Q06 — Major crime descriptions'
/*
Business question: Which primary-type/description combinations are most frequent?
Metric definition: COUNT(*) grouped by primary_type and description, limited to the
  top 20 combinations.
Assumptions: Description is interpreted only with its primary type; no descriptions
  are merged across categories.
Denominator: All 761,563 clean records for incident_share_pct.
*/
WITH totals AS (
    SELECT count(*)::numeric AS all_records
    FROM public.clean_chicago_crimes
)
SELECT
    primary_type,
    description,
    count(*) AS reported_incidents,
    round(100.0 * count(*) / totals.all_records, 4) AS incident_share_pct
FROM public.clean_chicago_crimes
CROSS JOIN totals
GROUP BY primary_type, description, totals.all_records
ORDER BY reported_incidents DESC, primary_type, description
LIMIT 20;

\echo 'Q07 — Leading descriptions within each major crime category'
/*
Business question: What are the three leading descriptions within each of the ten
  largest primary crime categories?
Metric definition: Description count and share within its primary type; top three are
  selected by count with description as deterministic tie-breaker.
Assumptions: Major categories use the fixed full-period top-ten definition from Q05.
Denominator: All records in the corresponding primary_type.
*/
WITH category_totals AS (
    SELECT primary_type, count(*) AS category_records
    FROM public.clean_chicago_crimes
    GROUP BY primary_type
),
major_categories AS (
    SELECT primary_type, category_records
    FROM category_totals
    ORDER BY category_records DESC, primary_type
    LIMIT 10
),
description_counts AS (
    SELECT
        crimes.primary_type,
        crimes.description,
        count(*) AS reported_incidents,
        major.category_records,
        row_number() OVER (
            PARTITION BY crimes.primary_type
            ORDER BY count(*) DESC, crimes.description
        ) AS description_rank
    FROM public.clean_chicago_crimes AS crimes
    JOIN major_categories AS major USING (primary_type)
    GROUP BY crimes.primary_type, crimes.description, major.category_records
)
SELECT
    primary_type,
    description_rank,
    description,
    reported_incidents,
    round(100.0 * reported_incidents / category_records, 4) AS category_share_pct
FROM description_counts
WHERE description_rank <= 3
ORDER BY primary_type, description_rank;

\echo 'Q08 — Calendar-month pattern across complete years'
/*
Business question: Which calendar months contain the most reported incidents when
  the three complete years are combined?
Metric definition: COUNT(*) by crime_month/month_name, full-period share, and average
  count per complete year.
Assumptions: Each month is present in all three complete years; this is a count pattern,
  not a population-normalized or days-adjusted rate.
Denominator: All 761,563 clean records for incident_share_pct; three years for average.
*/
WITH totals AS (
    SELECT count(*)::numeric AS all_records, count(DISTINCT crime_year)::numeric AS years
    FROM public.clean_chicago_crimes
)
SELECT
    crime_month,
    month_name,
    count(*) AS reported_incidents,
    round(count(*) / totals.years, 2) AS average_incidents_per_year,
    round(100.0 * count(*) / totals.all_records, 4) AS incident_share_pct
FROM public.clean_chicago_crimes
CROSS JOIN totals
GROUP BY crime_month, month_name, totals.all_records, totals.years
ORDER BY crime_month;

\echo 'Q09 — Year-month trend'
/*
Business question: How do reported incident counts move month by month within each year?
Metric definition: COUNT(*) grouped by crime_year and crime_month.
Assumptions: All displayed months are complete; no moving average or causal inference.
Denominator: Not applicable to the reported incident count.
*/
SELECT
    crime_year,
    crime_month,
    month_name,
    count(*) AS reported_incidents
FROM public.clean_chicago_crimes
GROUP BY crime_year, crime_month, month_name
ORDER BY crime_year, crime_month;

\echo 'Q10 — Day-of-week pattern'
/*
Business question: How are reported incidents distributed across ISO weekdays?
Metric definition: COUNT(*) by weekday, full-period share, and count divided by the
  number of distinct observed calendar dates for that weekday.
Assumptions: The daily average is per observed calendar date, not a crime or population rate.
Denominator: All records for share; distinct calendar dates within each weekday for average.
*/
WITH totals AS (
    SELECT count(*)::numeric AS all_records
    FROM public.clean_chicago_crimes
)
SELECT
    day_of_week_num,
    day_of_week,
    count(*) AS reported_incidents,
    count(DISTINCT crime_date) AS observed_dates,
    round(count(*)::numeric / count(DISTINCT crime_date), 2) AS average_per_observed_date,
    round(100.0 * count(*) / totals.all_records, 4) AS incident_share_pct
FROM public.clean_chicago_crimes
CROSS JOIN totals
GROUP BY day_of_week_num, day_of_week, totals.all_records
ORDER BY day_of_week_num;

\echo 'Q11 — Hourly pattern'
/*
Business question: At which hours are reported incidents most frequently timestamped?
Metric definition: COUNT(*) grouped by hour_of_day and share of all records.
Assumptions: Source incident times may be estimated; hour reflects the source timestamp.
Denominator: All 761,563 clean records.
*/
WITH totals AS (
    SELECT count(*)::numeric AS all_records
    FROM public.clean_chicago_crimes
)
SELECT
    hour_of_day,
    count(*) AS reported_incidents,
    round(100.0 * count(*) / totals.all_records, 4) AS incident_share_pct
FROM public.clean_chicago_crimes
CROSS JOIN totals
GROUP BY hour_of_day, totals.all_records
ORDER BY hour_of_day;

\echo 'Q12 — Time-of-day pattern'
/*
Business question: How are reported incidents distributed across the four defined
  six-hour time-of-day bands?
Metric definition: COUNT(*) grouped by documented time_of_day and share of all records.
Assumptions: Bands are Overnight 00-05, Morning 06-11, Afternoon 12-17, Evening 18-23.
Denominator: All 761,563 clean records.
*/
WITH totals AS (
    SELECT count(*)::numeric AS all_records
    FROM public.clean_chicago_crimes
)
SELECT
    time_of_day,
    count(*) AS reported_incidents,
    round(100.0 * count(*) / totals.all_records, 4) AS incident_share_pct
FROM public.clean_chicago_crimes
CROSS JOIN totals
GROUP BY time_of_day, totals.all_records
ORDER BY CASE time_of_day
    WHEN 'Overnight' THEN 1
    WHEN 'Morning' THEN 2
    WHEN 'Afternoon' THEN 3
    WHEN 'Evening' THEN 4
END;

\echo 'Q13 — Weekday versus weekend'
/*
Business question: How do weekday and weekend reported incident counts compare?
Metric definition: COUNT(*) by weekend_flag, full-period share, and count divided by
  distinct observed dates in the corresponding group.
Assumptions: Weekend is Saturday/Sunday. Raw totals reflect two weekend days versus five
  weekdays; average_per_observed_date supports a like-for-like daily comparison.
Denominator: All records for share; distinct weekend or weekday dates for daily average.
*/
WITH totals AS (
    SELECT count(*)::numeric AS all_records
    FROM public.clean_chicago_crimes
)
SELECT
    CASE WHEN weekend_flag THEN 'Weekend' ELSE 'Weekday' END AS day_group,
    count(*) AS reported_incidents,
    count(DISTINCT crime_date) AS observed_dates,
    round(count(*)::numeric / count(DISTINCT crime_date), 2) AS average_per_observed_date,
    round(100.0 * count(*) / totals.all_records, 4) AS incident_share_pct
FROM public.clean_chicago_crimes
CROSS JOIN totals
GROUP BY weekend_flag, totals.all_records
ORDER BY weekend_flag;

\echo 'Q14 — Community-area reported incident counts'
/*
Business question: How do reported incident counts compare across eligible community areas?
Metric definition: COUNT(*) for valid community_area 1-77, ranked by count; shares use
  eligible-area records and all citywide records separately.
Assumptions: Counts are not population-normalized crime rates; unknown area records are
  excluded from area ranking but retained citywide.
Denominator: 760,496 eligible-area records for eligible_share_pct; 761,563 for citywide_share_pct.
*/
WITH area_counts AS (
    SELECT community_area, count(*) AS reported_incidents
    FROM public.clean_chicago_crimes
    WHERE community_area_eligible_flag
    GROUP BY community_area
),
totals AS (
    SELECT
        count(*)::numeric AS all_records,
        count(*) FILTER (WHERE community_area_eligible_flag)::numeric AS eligible_records
    FROM public.clean_chicago_crimes
)
SELECT
    rank() OVER (ORDER BY area_counts.reported_incidents DESC) AS incident_count_rank,
    area_counts.community_area,
    area_counts.reported_incidents,
    round(100.0 * area_counts.reported_incidents / totals.eligible_records, 4)
        AS eligible_share_pct,
    round(100.0 * area_counts.reported_incidents / totals.all_records, 4)
        AS citywide_share_pct
FROM area_counts
CROSS JOIN totals
ORDER BY incident_count_rank, area_counts.community_area;

\echo 'Q15 — Community-area eligibility by year'
/*
Business question: Is community-area analytical coverage consistent across years?
Metric definition: Eligible and unknown/unassigned counts plus eligible percentage by year.
Assumptions: Eligibility requires cleaned community_area 1-77; no spatial imputation.
Denominator: All records within the corresponding crime_year.
*/
SELECT
    crime_year,
    count(*) AS reported_incidents,
    count(*) FILTER (WHERE community_area_eligible_flag) AS eligible_area_records,
    count(*) FILTER (WHERE NOT community_area_eligible_flag) AS unknown_area_records,
    round(
        100.0 * count(*) FILTER (WHERE community_area_eligible_flag) / count(*),
        4
    ) AS community_area_coverage_pct
FROM public.clean_chicago_crimes
GROUP BY crime_year
ORDER BY crime_year;

\echo 'Q16 — Community-area year-over-year change'
/*
Business question: How did reported incident counts change in every eligible community
  area between adjacent complete calendar years?
Metric definition: For each area, 100 * (current count - prior count) / prior count;
  absolute change is current count minus prior count.
Assumptions: Areas must have a valid 1-77 identifier and be represented in both adjacent
  complete years; identical eligibility is used in both periods. Counts are not rates.
Denominator: Prior-year area count; a zero prior count returns null percentage while
  retaining both counts and the absolute change.
*/
WITH area_year_counts AS (
    SELECT
        community_area,
        crime_year,
        count(*) AS reported_incidents
    FROM public.clean_chicago_crimes
    WHERE community_area_eligible_flag
    GROUP BY community_area, crime_year
),
comparisons AS (
    SELECT
        current.community_area,
        prior.crime_year AS prior_year,
        current.crime_year AS current_year,
        prior.reported_incidents AS prior_year_incidents,
        current.reported_incidents AS current_year_incidents
    FROM area_year_counts AS current
    JOIN area_year_counts AS prior
      ON prior.community_area = current.community_area
     AND prior.crime_year = current.crime_year - 1
)
SELECT
    community_area,
    prior_year,
    current_year,
    prior_year_incidents,
    current_year_incidents,
    current_year_incidents - prior_year_incidents AS absolute_change,
    round(
        100.0 * (current_year_incidents - prior_year_incidents)
            / nullif(prior_year_incidents, 0),
        4
    ) AS year_over_year_pct_change
FROM comparisons
ORDER BY current_year, community_area;

\echo 'Q17 — Current-reference police district comparison'
/*
Business question: How do reported incident counts compare across districts that match
  the current official district reference?
Metric definition: COUNT(*) by normalized district where district_current_flag is true.
Assumptions: This is an administrative count comparison, not a population-normalized rate;
  unmatched code 061 is excluded here and reported in Q18.
Denominator: All records matching the current district reference for current_reference_share_pct.
*/
WITH current_total AS (
    SELECT count(*)::numeric AS current_records
    FROM public.clean_chicago_crimes
    WHERE district_current_flag
)
SELECT
    district,
    count(*) AS reported_incidents,
    round(100.0 * count(*) / current_total.current_records, 4)
        AS current_reference_share_pct
FROM public.clean_chicago_crimes
CROSS JOIN current_total
WHERE district_current_flag
GROUP BY district, current_total.current_records
ORDER BY reported_incidents DESC, district;

\echo 'Q18 — District reference-status coverage'
/*
Business question: How many records use districts matched or unmatched to the current reference?
Metric definition: COUNT(*) by district and district_current_flag with citywide share.
Assumptions: A false flag means unmatched to the current reference, not proven invalidity.
Denominator: All 761,563 clean records.
*/
WITH totals AS (
    SELECT count(*)::numeric AS all_records
    FROM public.clean_chicago_crimes
)
SELECT
    district_current_flag,
    district,
    count(*) AS reported_incidents,
    round(100.0 * count(*) / totals.all_records, 4) AS citywide_share_pct
FROM public.clean_chicago_crimes
CROSS JOIN totals
GROUP BY district_current_flag, district, totals.all_records
ORDER BY district_current_flag, reported_incidents DESC, district;

\echo 'Q19 — Leading location descriptions'
/*
Business question: Which reported location descriptions occur most frequently?
Metric definition: COUNT(*) by cleaned location_description, limited to the top 20.
Assumptions: Missing source values are labeled UNKNOWN / NOT REPORTED and remain included.
Denominator: All 761,563 clean records for incident_share_pct.
*/
WITH totals AS (
    SELECT count(*)::numeric AS all_records
    FROM public.clean_chicago_crimes
)
SELECT
    location_description,
    count(*) AS reported_incidents,
    round(100.0 * count(*) / totals.all_records, 4) AS incident_share_pct
FROM public.clean_chicago_crimes
CROSS JOIN totals
GROUP BY location_description, totals.all_records
ORDER BY reported_incidents DESC, location_description
LIMIT 20;

\echo 'Q20 — Unknown location-description coverage by year'
/*
Business question: How often is the source location description unavailable by year?
Metric definition: Count and percentage where location_description is the documented
  UNKNOWN / NOT REPORTED analytical label.
Assumptions: The label represents source null/blank values, not an inferred location.
Denominator: All records within the corresponding crime_year.
*/
SELECT
    crime_year,
    count(*) AS reported_incidents,
    count(*) FILTER (
        WHERE location_description = 'UNKNOWN / NOT REPORTED'
    ) AS unknown_location_records,
    round(
        100.0 * count(*) FILTER (
            WHERE location_description = 'UNKNOWN / NOT REPORTED'
        ) / count(*),
        4
    ) AS unknown_location_pct
FROM public.clean_chicago_crimes
GROUP BY crime_year
ORDER BY crime_year;

\echo 'Q21 — Arrest percentage overall and by year'
/*
Business question: What percentage of reported incidents have arrest=true overall and by year?
Metric definition: 100 * count(arrest=true) / count(non-null arrest indicator).
Assumptions: Arrest is a source indicator and is not a clearance, prosecution, or conviction rate.
Denominator: All non-null arrest indicators in each displayed scope; current clean data has no nulls.
*/
SELECT
    CASE WHEN grouping(crime_year) = 1 THEN 'All years' ELSE crime_year::text END AS scope,
    count(*) AS reported_incidents,
    count(*) FILTER (WHERE arrest) AS arrest_true_records,
    count(arrest) AS arrest_denominator,
    round(
        100.0 * count(*) FILTER (WHERE arrest) / nullif(count(arrest), 0),
        4
    ) AS arrest_pct
FROM public.clean_chicago_crimes
GROUP BY GROUPING SETS ((crime_year), ())
ORDER BY grouping(crime_year) DESC, crime_year;

\echo 'Q22 — Arrest percentage by primary crime category'
/*
Business question: How does the source arrest indicator vary by primary category?
Metric definition: 100 * arrest=true records / non-null arrest indicators within category.
Assumptions: Categories retain City/IUCR definitions; arrest percentage is not clearance or conviction.
Denominator: Non-null arrest indicators within each primary_type.
*/
SELECT
    primary_type,
    count(*) AS reported_incidents,
    count(*) FILTER (WHERE arrest) AS arrest_true_records,
    count(arrest) AS arrest_denominator,
    round(
        100.0 * count(*) FILTER (WHERE arrest) / nullif(count(arrest), 0),
        4
    ) AS arrest_pct
FROM public.clean_chicago_crimes
GROUP BY primary_type
ORDER BY arrest_pct DESC, reported_incidents DESC, primary_type;

\echo 'Q23 — Arrest percentage by year for major crime categories'
/*
Business question: How does arrest percentage change by year within the ten largest categories?
Metric definition: Fixed full-period top-ten categories; annual arrest percentage uses
  arrest=true divided by non-null arrest indicators for the category-year.
Assumptions: Descriptive source indicator only; no claim about clearance, prosecution, or conviction.
Denominator: Non-null arrest indicators in each primary_type/crime_year group.
*/
WITH major_categories AS (
    SELECT primary_type
    FROM public.clean_chicago_crimes
    GROUP BY primary_type
    ORDER BY count(*) DESC, primary_type
    LIMIT 10
)
SELECT
    crimes.crime_year,
    crimes.primary_type,
    count(*) AS reported_incidents,
    count(*) FILTER (WHERE crimes.arrest) AS arrest_true_records,
    count(crimes.arrest) AS arrest_denominator,
    round(
        100.0 * count(*) FILTER (WHERE crimes.arrest)
            / nullif(count(crimes.arrest), 0),
        4
    ) AS arrest_pct
FROM public.clean_chicago_crimes AS crimes
JOIN major_categories USING (primary_type)
GROUP BY crimes.crime_year, crimes.primary_type
ORDER BY crimes.primary_type, crimes.crime_year;

\echo 'Q24 — Domestic incident percentage overall and by year'
/*
Business question: What percentage of reported incidents are marked domestic overall and by year?
Metric definition: 100 * count(domestic=true) / count(non-null domestic indicator).
Assumptions: The metric describes the source domestic indicator and not unreported incidents.
Denominator: All non-null domestic indicators in each displayed scope; current data has no nulls.
*/
SELECT
    CASE WHEN grouping(crime_year) = 1 THEN 'All years' ELSE crime_year::text END AS scope,
    count(*) AS reported_incidents,
    count(*) FILTER (WHERE domestic) AS domestic_true_records,
    count(domestic) AS domestic_denominator,
    round(
        100.0 * count(*) FILTER (WHERE domestic) / nullif(count(domestic), 0),
        4
    ) AS domestic_incident_pct
FROM public.clean_chicago_crimes
GROUP BY GROUPING SETS ((crime_year), ())
ORDER BY grouping(crime_year) DESC, crime_year;

\echo 'Q25 — Domestic incident percentage by primary crime category'
/*
Business question: Which primary categories have the largest domestic-incident percentages?
Metric definition: 100 * domestic=true records / non-null domestic indicators within category.
Assumptions: The source domestic flag is used without inferring unreported domestic violence.
Denominator: Non-null domestic indicators within each primary_type.
*/
SELECT
    primary_type,
    count(*) AS reported_incidents,
    count(*) FILTER (WHERE domestic) AS domestic_true_records,
    count(domestic) AS domestic_denominator,
    round(
        100.0 * count(*) FILTER (WHERE domestic) / nullif(count(domestic), 0),
        4
    ) AS domestic_incident_pct
FROM public.clean_chicago_crimes
GROUP BY primary_type
ORDER BY domestic_incident_pct DESC, reported_incidents DESC, primary_type;

\echo 'Q26 — Domestic incident percentage by time of day'
/*
Business question: How does the domestic indicator vary across defined time-of-day bands?
Metric definition: Reported incident count and 100 * domestic=true / non-null domestic
  indicators within each six-hour band.
Assumptions: Source incident times can be estimated; time bands use the documented definitions.
Denominator: Non-null domestic indicators within each time_of_day.
*/
SELECT
    time_of_day,
    count(*) AS reported_incidents,
    count(*) FILTER (WHERE domestic) AS domestic_true_records,
    count(domestic) AS domestic_denominator,
    round(
        100.0 * count(*) FILTER (WHERE domestic) / nullif(count(domestic), 0),
        4
    ) AS domestic_incident_pct
FROM public.clean_chicago_crimes
GROUP BY time_of_day
ORDER BY CASE time_of_day
    WHEN 'Overnight' THEN 1
    WHEN 'Morning' THEN 2
    WHEN 'Afternoon' THEN 3
    WHEN 'Evening' THEN 4
END;

\echo 'Q27 — Seasonal pattern'
/*
Business question: How are reported incidents distributed across meteorological seasons?
Metric definition: COUNT(*) by season and share of all records.
Assumptions: Winter=Dec-Feb, Spring=Mar-May, Summer=Jun-Aug, Fall=Sep-Nov; this is
  not adjusted for unequal month lengths or population.
Denominator: All 761,563 clean records.
*/
WITH totals AS (
    SELECT count(*)::numeric AS all_records
    FROM public.clean_chicago_crimes
)
SELECT
    season,
    count(*) AS reported_incidents,
    round(100.0 * count(*) / totals.all_records, 4) AS incident_share_pct
FROM public.clean_chicago_crimes
CROSS JOIN totals
GROUP BY season, totals.all_records
ORDER BY CASE season
    WHEN 'Winter' THEN 1
    WHEN 'Spring' THEN 2
    WHEN 'Summer' THEN 3
    WHEN 'Fall' THEN 4
END;

\echo 'Q28 — Seasonal pattern by major crime category'
/*
Business question: How is each major category distributed across seasons?
Metric definition: Fixed full-period top-ten categories; seasonal count and share within
  each primary category.
Assumptions: Source categories are not regrouped; season definitions match Q27.
Denominator: All records within the corresponding primary_type for category_season_share_pct.
*/
WITH category_totals AS (
    SELECT primary_type, count(*) AS category_records
    FROM public.clean_chicago_crimes
    GROUP BY primary_type
),
major_categories AS (
    SELECT primary_type, category_records
    FROM category_totals
    ORDER BY category_records DESC, primary_type
    LIMIT 10
)
SELECT
    crimes.primary_type,
    crimes.season,
    count(*) AS reported_incidents,
    round(100.0 * count(*) / major.category_records, 4)
        AS category_season_share_pct
FROM public.clean_chicago_crimes AS crimes
JOIN major_categories AS major USING (primary_type)
GROUP BY crimes.primary_type, crimes.season, major.category_records
ORDER BY crimes.primary_type,
    CASE crimes.season
        WHEN 'Winter' THEN 1
        WHEN 'Spring' THEN 2
        WHEN 'Summer' THEN 3
        WHEN 'Fall' THEN 4
    END;

\echo 'Q29 — Cross-query reconciliation and denominator validation'
/*
Business question: Do the main analysis dimensions reconcile to the canonical population?
Metric definition: Each mismatch is the grouped-dimension sum minus canonical COUNT(*);
  valid community-area plus ineligible-area rows must also equal the canonical total.
Assumptions: Complete dimensions are non-null by clean-table constraints; geographic
  eligibility is intentionally partitioned into eligible and ineligible records.
Denominator: Canonical COUNT(*) of clean_chicago_crimes; every mismatch must equal zero.
*/
WITH canonical AS (
    SELECT
        count(*) AS all_records,
        count(*) FILTER (WHERE community_area_eligible_flag) AS eligible_area_records,
        count(*) FILTER (WHERE NOT community_area_eligible_flag) AS ineligible_area_records,
        count(*) FILTER (WHERE arrest IS NULL) AS null_arrest_records,
        count(*) FILTER (WHERE domestic IS NULL) AS null_domestic_records
    FROM public.clean_chicago_crimes
),
year_sum AS (
    SELECT sum(record_count) AS records FROM (
        SELECT crime_year, count(*) AS record_count
        FROM public.clean_chicago_crimes GROUP BY crime_year
    ) AS grouped
),
category_sum AS (
    SELECT sum(record_count) AS records FROM (
        SELECT primary_type, count(*) AS record_count
        FROM public.clean_chicago_crimes GROUP BY primary_type
    ) AS grouped
),
month_sum AS (
    SELECT sum(record_count) AS records FROM (
        SELECT crime_month, count(*) AS record_count
        FROM public.clean_chicago_crimes GROUP BY crime_month
    ) AS grouped
),
day_sum AS (
    SELECT sum(record_count) AS records FROM (
        SELECT day_of_week_num, count(*) AS record_count
        FROM public.clean_chicago_crimes GROUP BY day_of_week_num
    ) AS grouped
),
hour_sum AS (
    SELECT sum(record_count) AS records FROM (
        SELECT hour_of_day, count(*) AS record_count
        FROM public.clean_chicago_crimes GROUP BY hour_of_day
    ) AS grouped
),
time_sum AS (
    SELECT sum(record_count) AS records FROM (
        SELECT time_of_day, count(*) AS record_count
        FROM public.clean_chicago_crimes GROUP BY time_of_day
    ) AS grouped
),
weekend_sum AS (
    SELECT sum(record_count) AS records FROM (
        SELECT weekend_flag, count(*) AS record_count
        FROM public.clean_chicago_crimes GROUP BY weekend_flag
    ) AS grouped
),
district_sum AS (
    SELECT sum(record_count) AS records FROM (
        SELECT district, count(*) AS record_count
        FROM public.clean_chicago_crimes GROUP BY district
    ) AS grouped
),
location_sum AS (
    SELECT sum(record_count) AS records FROM (
        SELECT location_description, count(*) AS record_count
        FROM public.clean_chicago_crimes GROUP BY location_description
    ) AS grouped
),
season_sum AS (
    SELECT sum(record_count) AS records FROM (
        SELECT season, count(*) AS record_count
        FROM public.clean_chicago_crimes GROUP BY season
    ) AS grouped
)
SELECT
    canonical.all_records AS canonical_records,
    year_sum.records - canonical.all_records AS year_mismatch,
    category_sum.records - canonical.all_records AS category_mismatch,
    month_sum.records - canonical.all_records AS month_mismatch,
    day_sum.records - canonical.all_records AS weekday_mismatch,
    hour_sum.records - canonical.all_records AS hour_mismatch,
    time_sum.records - canonical.all_records AS time_of_day_mismatch,
    weekend_sum.records - canonical.all_records AS weekend_mismatch,
    district_sum.records - canonical.all_records AS district_mismatch,
    location_sum.records - canonical.all_records AS location_mismatch,
    season_sum.records - canonical.all_records AS season_mismatch,
    canonical.eligible_area_records + canonical.ineligible_area_records
        - canonical.all_records AS community_area_partition_mismatch,
    canonical.null_arrest_records,
    canonical.null_domestic_records
FROM canonical
CROSS JOIN year_sum
CROSS JOIN category_sum
CROSS JOIN month_sum
CROSS JOIN day_sum
CROSS JOIN hour_sum
CROSS JOIN time_sum
CROSS JOIN weekend_sum
CROSS JOIN district_sum
CROSS JOIN location_sum
CROSS JOIN season_sum;

COMMIT;
