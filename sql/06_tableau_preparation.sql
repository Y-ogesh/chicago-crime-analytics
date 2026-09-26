\set ON_ERROR_STOP on
\pset pager off
\pset null '[NULL]'
\timing on

-- Milestone 9A: Tableau presentation-layer views.
-- Canonical scope: public.clean_chicago_crimes, complete calendar years 2023-2025.
-- These non-materialized views preserve the metric contract established in
-- docs/metric_definitions.md. Counts are reported incidents, not rates;
-- arrest percentages are not clearance or conviction rates.

BEGIN;

CREATE OR REPLACE VIEW public.vw_tableau_executive_year AS
WITH yearly_indicators AS (
    SELECT crime_year,
           COUNT(*)::bigint AS reported_incident_count,
           COUNT(*) FILTER (WHERE arrest)::bigint AS arrest_count,
           COUNT(arrest)::bigint AS arrest_indicator_denominator,
           COUNT(*) FILTER (WHERE domestic)::bigint AS domestic_count,
           COUNT(domestic)::bigint AS domestic_indicator_denominator,
           COUNT(*) FILTER (WHERE community_area_eligible_flag)::bigint
               AS community_area_eligible_count,
           COUNT(*) FILTER (WHERE coordinate_mappable_flag)::bigint
               AS coordinate_mappable_count
    FROM public.clean_chicago_crimes
    GROUP BY crime_year
)
SELECT y.crime_year,
       make_date(y.crime_year, 1, 1) AS period_start,
       make_date(y.crime_year, 12, 31) AS period_end,
       'Complete calendar year'::text AS period_status,
       'ijzp-q8t2'::text AS source_dataset_id,
       DATE '2026-09-25' AS source_extraction_date,
       i.reported_incident_count,
       y.previous_year,
       y.previous_year_incident_count,
       y.absolute_change,
       y.percentage_change,
       y.incident_volume_rank,
       i.arrest_count,
       i.arrest_indicator_denominator,
       100.0 * i.arrest_count / NULLIF(i.arrest_indicator_denominator, 0)
           AS arrest_percentage,
       i.domestic_count,
       i.domestic_indicator_denominator,
       100.0 * i.domestic_count / NULLIF(i.domestic_indicator_denominator, 0)
           AS domestic_incident_percentage,
       i.community_area_eligible_count,
       100.0 * i.community_area_eligible_count
           / NULLIF(i.reported_incident_count, 0) AS community_area_coverage_percentage,
       i.coordinate_mappable_count,
       100.0 * i.coordinate_mappable_count
           / NULLIF(i.reported_incident_count, 0) AS geographic_coverage_percentage
FROM yearly_indicators AS i
JOIN public.vw_yearly_crime_trends AS y USING (crime_year);

COMMENT ON VIEW public.vw_tableau_executive_year IS
'Tableau executive page: one row per complete calendar year with reported incidents, adjacent-year change, arrest/domestic indicator percentages, and geographic coverage.';

CREATE OR REPLACE VIEW public.vw_tableau_community_area_year AS
WITH area_year_grid AS (
    SELECT l.community_area,
           l.community_area_name,
           y.crime_year
    FROM public.vw_community_area_lookup AS l
    CROSS JOIN (
        SELECT DISTINCT crime_year
        FROM public.clean_chicago_crimes
    ) AS y
), observed AS (
    SELECT crime_year,
           community_area,
           COUNT(*)::bigint AS reported_incident_count
    FROM public.clean_chicago_crimes
    WHERE community_area_eligible_flag
    GROUP BY crime_year, community_area
), complete_grid AS (
    SELECT g.crime_year,
           g.community_area,
           g.community_area_name,
           COALESCE(o.reported_incident_count, 0)::bigint AS reported_incident_count
    FROM area_year_grid AS g
    LEFT JOIN observed AS o
      ON o.crime_year = g.crime_year
     AND o.community_area = g.community_area
), ranked AS (
    SELECT c.*,
           SUM(reported_incident_count) OVER (PARTITION BY crime_year)::bigint
               AS yearly_eligible_incident_count,
           RANK() OVER (
               PARTITION BY crime_year
               ORDER BY reported_incident_count DESC
           ) AS yearly_incident_volume_rank
    FROM complete_grid AS c
)
SELECT r.crime_year,
       make_date(r.crime_year, 1, 1) AS period_start,
       r.community_area,
       r.community_area_name,
       r.reported_incident_count,
       r.yearly_eligible_incident_count,
       100.0 * r.reported_incident_count
           / NULLIF(r.yearly_eligible_incident_count, 0) AS percentage_of_yearly_area_eligible_total,
       r.yearly_incident_volume_rank,
       y.previous_year,
       y.previous_year_incident_count,
       y.absolute_change,
       y.percentage_change,
       y.minimum_prior_year_count,
       y.percentage_rank_eligible,
       y.percentage_change_rank,
       y.percentage_decrease_rank,
       y.absolute_change_rank,
       y.absolute_decrease_rank
FROM ranked AS r
LEFT JOIN public.vw_community_area_yoy AS y
  ON y.current_year = r.crime_year
 AND y.community_area = r.community_area;

COMMENT ON VIEW public.vw_tableau_community_area_year IS
'Tableau geographic page: complete 77-area grid by year with reported-incident shares, ranks, and canonical adjacent-year changes.';

CREATE OR REPLACE VIEW public.vw_tableau_district_year AS
WITH district_year AS (
    SELECT crime_year,
           COALESCE(district, 'UNKNOWN/UNASSIGNED') AS district,
           BOOL_AND(COALESCE(district_current_flag, FALSE)) AS district_current_flag,
           COUNT(*)::bigint AS reported_incident_count
    FROM public.clean_chicago_crimes
    GROUP BY crime_year, COALESCE(district, 'UNKNOWN/UNASSIGNED')
), with_windows AS (
    SELECT d.*,
           SUM(reported_incident_count) OVER (PARTITION BY crime_year)::bigint
               AS yearly_reported_incident_count,
           RANK() OVER (
               PARTITION BY crime_year
               ORDER BY reported_incident_count DESC
           ) AS yearly_incident_volume_rank,
           LAG(crime_year) OVER (
               PARTITION BY district ORDER BY crime_year
           ) AS previous_year,
           LAG(reported_incident_count) OVER (
               PARTITION BY district ORDER BY crime_year
           ) AS previous_year_incident_count
    FROM district_year AS d
)
SELECT crime_year,
       make_date(crime_year, 1, 1) AS period_start,
       district,
       CASE
           WHEN district = 'UNKNOWN/UNASSIGNED' THEN district
           WHEN district_current_flag THEN 'District ' || district
           ELSE 'District ' || district || ' (unmatched current reference)'
       END AS district_label,
       district_current_flag,
       reported_incident_count,
       yearly_reported_incident_count,
       100.0 * reported_incident_count
           / NULLIF(yearly_reported_incident_count, 0) AS percentage_of_yearly_total,
       yearly_incident_volume_rank,
       previous_year,
       previous_year_incident_count,
       reported_incident_count - previous_year_incident_count AS absolute_change,
       100.0 * (reported_incident_count - previous_year_incident_count)
           / NULLIF(previous_year_incident_count, 0) AS percentage_change
FROM with_windows;

COMMENT ON VIEW public.vw_tableau_district_year IS
'Tableau geographic page: source-derived district-code totals, current-reference status, yearly shares/ranks, and adjacent-year changes.';

CREATE OR REPLACE VIEW public.vw_tableau_area_category_year AS
WITH counts AS (
    SELECT c.crime_year,
           c.community_area,
           l.community_area_name,
           c.primary_type,
           COUNT(*)::bigint AS reported_incident_count
    FROM public.clean_chicago_crimes AS c
    JOIN public.vw_community_area_lookup AS l USING (community_area)
    WHERE c.community_area_eligible_flag
    GROUP BY c.crime_year, c.community_area, l.community_area_name, c.primary_type
), with_totals AS (
    SELECT c.*,
           SUM(reported_incident_count) OVER (
               PARTITION BY crime_year, community_area
           )::bigint AS area_year_incident_count,
           SUM(reported_incident_count) OVER (
               PARTITION BY crime_year, primary_type
           )::bigint AS category_year_incident_count,
           RANK() OVER (
               PARTITION BY crime_year, community_area
               ORDER BY reported_incident_count DESC
           ) AS category_rank_within_area,
           RANK() OVER (
               PARTITION BY crime_year, primary_type
               ORDER BY reported_incident_count DESC
           ) AS area_rank_within_category
    FROM counts AS c
)
SELECT crime_year,
       make_date(crime_year, 1, 1) AS period_start,
       community_area,
       community_area_name,
       primary_type,
       reported_incident_count,
       area_year_incident_count,
       100.0 * reported_incident_count
           / NULLIF(area_year_incident_count, 0) AS percentage_of_area_year_total,
       category_year_incident_count,
       100.0 * reported_incident_count
           / NULLIF(category_year_incident_count, 0) AS percentage_of_category_year_total,
       category_rank_within_area,
       area_rank_within_category
FROM with_totals;

COMMENT ON VIEW public.vw_tableau_area_category_year IS
'Tableau geographic page: community-area by source primary-type by year counts, composition shares, concentration shares, and ranks.';

CREATE OR REPLACE VIEW public.vw_tableau_monthly_patterns AS
WITH monthly AS (
    SELECT crime_year,
           crime_month,
           MIN(month_name) AS month_name,
           MIN(crime_quarter)::smallint AS crime_quarter,
           MIN(season) AS season,
           COUNT(*)::bigint AS reported_incident_count,
           COUNT(*) FILTER (WHERE arrest)::bigint AS arrest_count,
           COUNT(arrest)::bigint AS arrest_indicator_denominator,
           COUNT(*) FILTER (WHERE domestic)::bigint AS domestic_count,
           COUNT(domestic)::bigint AS domestic_indicator_denominator,
           COUNT(*) FILTER (WHERE weekend_flag)::bigint AS weekend_incident_count
    FROM public.clean_chicago_crimes
    GROUP BY crime_year, crime_month
), with_windows AS (
    SELECT m.*,
           SUM(reported_incident_count) OVER (PARTITION BY crime_year)::bigint
               AS yearly_reported_incident_count,
           AVG(reported_incident_count) OVER (
               ORDER BY crime_year, crime_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
           ) AS trailing_three_month_average,
           LAG(reported_incident_count, 12) OVER (
               ORDER BY crime_year, crime_month
           ) AS same_month_previous_year_count
    FROM monthly AS m
)
SELECT make_date(crime_year, crime_month, 1) AS month_start,
       crime_year,
       crime_month,
       month_name,
       crime_quarter,
       season,
       reported_incident_count,
       yearly_reported_incident_count,
       100.0 * reported_incident_count
           / NULLIF(yearly_reported_incident_count, 0) AS percentage_of_yearly_total,
       trailing_three_month_average,
       same_month_previous_year_count,
       reported_incident_count - same_month_previous_year_count
           AS same_month_absolute_change,
       100.0 * (reported_incident_count - same_month_previous_year_count)
           / NULLIF(same_month_previous_year_count, 0) AS same_month_percentage_change,
       arrest_count,
       arrest_indicator_denominator,
       100.0 * arrest_count / NULLIF(arrest_indicator_denominator, 0)
           AS arrest_percentage,
       domestic_count,
       domestic_indicator_denominator,
       100.0 * domestic_count / NULLIF(domestic_indicator_denominator, 0)
           AS domestic_incident_percentage,
       weekend_incident_count,
       100.0 * weekend_incident_count / NULLIF(reported_incident_count, 0)
           AS weekend_percentage
FROM with_windows;

COMMENT ON VIEW public.vw_tableau_monthly_patterns IS
'Tableau temporal page: one row per complete calendar month with reported incidents, annual share, trailing-three-month average, same-month change, and weighted indicator numerators/denominators.';

CREATE OR REPLACE VIEW public.vw_tableau_time_patterns AS
SELECT crime_year,
       day_of_week_num,
       day_of_week,
       hour_of_day,
       time_of_day,
       weekend_flag,
       COUNT(*)::bigint AS reported_incident_count,
       COUNT(*) FILTER (WHERE arrest)::bigint AS arrest_count,
       COUNT(arrest)::bigint AS arrest_indicator_denominator,
       COUNT(*) FILTER (WHERE domestic)::bigint AS domestic_count,
       COUNT(domestic)::bigint AS domestic_indicator_denominator
FROM public.clean_chicago_crimes
GROUP BY crime_year, day_of_week_num, day_of_week, hour_of_day,
         time_of_day, weekend_flag;

COMMENT ON VIEW public.vw_tableau_time_patterns IS
'Tableau temporal page: year by ISO weekday by hour counts and indicator numerators/denominators; time-of-day and weekend fields follow the documented clean-table definitions.';

CREATE OR REPLACE VIEW public.vw_tableau_location_time AS
WITH location_totals AS (
    SELECT location_description,
           COUNT(*)::bigint AS full_period_incident_count,
           ROW_NUMBER() OVER (
               ORDER BY COUNT(*) DESC, location_description
           ) AS full_period_location_rank
    FROM public.clean_chicago_crimes
    GROUP BY location_description
), selected_locations AS (
    SELECT *
    FROM location_totals
    WHERE full_period_location_rank <= 10
), time_bands(time_of_day, time_of_day_order) AS (
    VALUES ('Overnight'::text, 1), ('Morning'::text, 2),
           ('Afternoon'::text, 3), ('Evening'::text, 4)
), observed AS (
    SELECT c.location_description,
           c.time_of_day,
           COUNT(*)::bigint AS reported_incident_count
    FROM public.clean_chicago_crimes AS c
    JOIN selected_locations AS s USING (location_description)
    GROUP BY c.location_description, c.time_of_day
)
SELECT s.location_description,
       s.full_period_location_rank,
       s.full_period_incident_count,
       t.time_of_day,
       t.time_of_day_order,
       COALESCE(o.reported_incident_count, 0)::bigint AS reported_incident_count,
       100.0 * COALESCE(o.reported_incident_count, 0)
           / NULLIF(s.full_period_incident_count, 0) AS percentage_of_location_total
FROM selected_locations AS s
CROSS JOIN time_bands AS t
LEFT JOIN observed AS o
  ON o.location_description = s.location_description
 AND o.time_of_day = t.time_of_day;

COMMENT ON VIEW public.vw_tableau_location_time IS
'Tableau temporal page: fixed full-period top-ten location descriptions by four documented time-of-day bands, including within-location shares.';

CREATE OR REPLACE VIEW public.vw_tableau_crime_arrest_year AS
WITH indicators AS (
    SELECT crime_year,
           primary_type,
           COUNT(*)::bigint AS reported_incident_count,
           COUNT(*) FILTER (WHERE arrest)::bigint AS arrest_count,
           COUNT(arrest)::bigint AS arrest_indicator_denominator,
           COUNT(*) FILTER (WHERE domestic)::bigint AS domestic_count,
           COUNT(domestic)::bigint AS domestic_indicator_denominator
    FROM public.clean_chicago_crimes
    GROUP BY crime_year, primary_type
)
SELECT i.crime_year,
       make_date(i.crime_year, 1, 1) AS period_start,
       i.primary_type,
       i.reported_incident_count,
       t.yearly_reported_incident_count,
       t.percentage_of_year_total,
       t.incident_volume_rank,
       t.previous_year,
       t.previous_year_incident_count,
       t.absolute_change,
       t.percentage_change,
       i.arrest_count,
       i.arrest_indicator_denominator,
       100.0 * i.arrest_count / NULLIF(i.arrest_indicator_denominator, 0)
           AS arrest_percentage,
       i.domestic_count,
       i.domestic_indicator_denominator,
       100.0 * i.domestic_count / NULLIF(i.domestic_indicator_denominator, 0)
           AS domestic_incident_percentage
FROM indicators AS i
JOIN public.vw_crime_type_trends AS t
  ON t.crime_year = i.crime_year
 AND t.primary_type = i.primary_type;

COMMENT ON VIEW public.vw_tableau_crime_arrest_year IS
'Tableau crime/arrest page: source primary-type by year counts, annual shares/ranks, adjacent-year changes, and weighted arrest/domestic indicator metrics.';

CREATE OR REPLACE VIEW public.vw_tableau_coordinate_density AS
WITH grid_counts AS (
    SELECT crime_year,
           FLOOR(latitude * 100.0) / 100.0 AS latitude_floor,
           FLOOR(longitude * 100.0) / 100.0 AS longitude_floor,
           COUNT(*)::bigint AS reported_incident_count
    FROM public.clean_chicago_crimes
    WHERE coordinate_mappable_flag
    GROUP BY crime_year,
             FLOOR(latitude * 100.0) / 100.0,
             FLOOR(longitude * 100.0) / 100.0
)
SELECT crime_year,
       ROUND((latitude_floor + 0.005)::numeric, 3) AS cell_latitude,
       ROUND((longitude_floor + 0.005)::numeric, 3) AS cell_longitude,
       CONCAT(
           crime_year, ':',
           ROUND((latitude_floor + 0.005)::numeric, 3), ':',
           ROUND((longitude_floor + 0.005)::numeric, 3)
       ) AS density_cell_id,
       reported_incident_count
FROM grid_counts;

COMMENT ON VIEW public.vw_tableau_coordinate_density IS
'Tableau geographic page: descriptive year-by-0.01-degree coordinate-cell counts for map-eligible records. Cells are not equal-area and do not test statistical hotspot significance.';

-- Fail-fast presentation-layer validation.
DO $$
BEGIN
    IF (SELECT COUNT(*) FROM public.vw_tableau_executive_year) <> 3 THEN
        RAISE EXCEPTION 'Expected three complete-year executive rows';
    END IF;

    IF (SELECT SUM(reported_incident_count) FROM public.vw_tableau_executive_year)
       <> (SELECT COUNT(*) FROM public.clean_chicago_crimes) THEN
        RAISE EXCEPTION 'Executive totals do not reconcile';
    END IF;

    IF (SELECT COUNT(*) FROM public.vw_tableau_community_area_year) <> 231 THEN
        RAISE EXCEPTION 'Expected 77 community areas for each of three years';
    END IF;

    IF (SELECT SUM(reported_incident_count) FROM public.vw_tableau_community_area_year)
       <> (SELECT COUNT(*) FROM public.clean_chicago_crimes WHERE community_area_eligible_flag) THEN
        RAISE EXCEPTION 'Community-area totals do not reconcile';
    END IF;

    IF EXISTS (
        SELECT crime_year
        FROM public.vw_tableau_district_year
        GROUP BY crime_year
        HAVING SUM(reported_incident_count) <>
               (SELECT COUNT(*) FROM public.clean_chicago_crimes AS c
                WHERE c.crime_year = vw_tableau_district_year.crime_year)
    ) THEN
        RAISE EXCEPTION 'District-year totals do not reconcile';
    END IF;

    IF (SELECT SUM(reported_incident_count) FROM public.vw_tableau_area_category_year)
       <> (SELECT COUNT(*) FROM public.clean_chicago_crimes WHERE community_area_eligible_flag) THEN
        RAISE EXCEPTION 'Area-category totals do not reconcile';
    END IF;

    IF (SELECT COUNT(*) FROM public.vw_tableau_monthly_patterns) <> 36
       OR (SELECT SUM(reported_incident_count) FROM public.vw_tableau_monthly_patterns)
          <> (SELECT COUNT(*) FROM public.clean_chicago_crimes) THEN
        RAISE EXCEPTION 'Monthly Tableau view does not reconcile';
    END IF;

    IF (SELECT SUM(reported_incident_count) FROM public.vw_tableau_time_patterns)
       <> (SELECT COUNT(*) FROM public.clean_chicago_crimes) THEN
        RAISE EXCEPTION 'Time-pattern totals do not reconcile';
    END IF;

    IF (SELECT COUNT(*) FROM public.vw_tableau_location_time) <> 40 THEN
        RAISE EXCEPTION 'Expected ten locations by four time bands';
    END IF;

    IF (SELECT SUM(reported_incident_count) FROM public.vw_tableau_location_time)
       <> (
           SELECT COUNT(*)
           FROM public.clean_chicago_crimes
           WHERE location_description IN (
               SELECT location_description
               FROM public.clean_chicago_crimes
               GROUP BY location_description
               ORDER BY COUNT(*) DESC, location_description
               LIMIT 10
           )
       ) THEN
        RAISE EXCEPTION 'Location/time totals do not reconcile to the fixed top ten';
    END IF;

    IF (SELECT SUM(reported_incident_count) FROM public.vw_tableau_crime_arrest_year)
       <> (SELECT COUNT(*) FROM public.clean_chicago_crimes)
       OR (SELECT SUM(arrest_count) FROM public.vw_tableau_crime_arrest_year)
          <> (SELECT COUNT(*) FROM public.clean_chicago_crimes WHERE arrest)
       OR (SELECT SUM(arrest_indicator_denominator) FROM public.vw_tableau_crime_arrest_year)
          <> (SELECT COUNT(arrest) FROM public.clean_chicago_crimes)
       OR (SELECT SUM(domestic_count) FROM public.vw_tableau_crime_arrest_year)
          <> (SELECT COUNT(*) FROM public.clean_chicago_crimes WHERE domestic)
       OR (SELECT SUM(domestic_indicator_denominator) FROM public.vw_tableau_crime_arrest_year)
          <> (SELECT COUNT(domestic) FROM public.clean_chicago_crimes) THEN
        RAISE EXCEPTION 'Crime/arrest Tableau view does not reconcile';
    END IF;

    IF (SELECT SUM(reported_incident_count) FROM public.vw_tableau_coordinate_density)
       <> (SELECT COUNT(*) FROM public.clean_chicago_crimes WHERE coordinate_mappable_flag) THEN
        RAISE EXCEPTION 'Coordinate-density totals do not reconcile';
    END IF;
END
$$;

COMMIT;

-- Compact execution evidence.
SELECT view_name, row_count
FROM (
    SELECT 'vw_tableau_executive_year'::text, COUNT(*)::bigint FROM public.vw_tableau_executive_year
    UNION ALL SELECT 'vw_tableau_community_area_year', COUNT(*) FROM public.vw_tableau_community_area_year
    UNION ALL SELECT 'vw_tableau_district_year', COUNT(*) FROM public.vw_tableau_district_year
    UNION ALL SELECT 'vw_tableau_area_category_year', COUNT(*) FROM public.vw_tableau_area_category_year
    UNION ALL SELECT 'vw_tableau_monthly_patterns', COUNT(*) FROM public.vw_tableau_monthly_patterns
    UNION ALL SELECT 'vw_tableau_time_patterns', COUNT(*) FROM public.vw_tableau_time_patterns
    UNION ALL SELECT 'vw_tableau_location_time', COUNT(*) FROM public.vw_tableau_location_time
    UNION ALL SELECT 'vw_tableau_crime_arrest_year', COUNT(*) FROM public.vw_tableau_crime_arrest_year
    UNION ALL SELECT 'vw_tableau_coordinate_density', COUNT(*) FROM public.vw_tableau_coordinate_density
) AS counts(view_name, row_count)
ORDER BY view_name;

SELECT e.crime_year,
       e.reported_incident_count,
       e.arrest_count,
       e.arrest_indicator_denominator,
       e.domestic_count,
       e.domestic_indicator_denominator,
       e.coordinate_mappable_count,
       e.community_area_eligible_count
FROM public.vw_tableau_executive_year AS e
ORDER BY e.crime_year;
