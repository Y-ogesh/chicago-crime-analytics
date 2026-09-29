\set ON_ERROR_STOP on

BEGIN;

DROP VIEW IF EXISTS public.vw_tableau_temporal_detail;
DROP VIEW IF EXISTS public.vw_tableau_temporal_kpis;

CREATE VIEW public.vw_tableau_temporal_detail AS
WITH annual_category AS (
    SELECT crime_year,
           primary_type,
           COUNT(*)::bigint AS annual_category_incident_count,
           DENSE_RANK() OVER (
               PARTITION BY crime_year
               ORDER BY COUNT(*) DESC, primary_type ASC
           )::integer AS annual_category_rank
    FROM public.clean_chicago_crimes
    GROUP BY crime_year, primary_type
), temporal_detail AS (
    SELECT make_date(c.crime_year, c.crime_month, 1) AS month_start,
           c.crime_year,
           c.crime_month,
           MIN(c.month_name) AS month_name,
           MIN(c.crime_quarter)::smallint AS crime_quarter,
           MIN(c.season) AS season,
           CASE MIN(c.season)
               WHEN 'Winter' THEN 1
               WHEN 'Spring' THEN 2
               WHEN 'Summer' THEN 3
               WHEN 'Fall' THEN 4
           END::smallint AS season_order,
           c.primary_type,
           c.day_of_week_num,
           MIN(c.day_of_week) AS day_of_week,
           c.hour_of_day,
           MIN(c.time_of_day) AS time_of_day,
           CASE MIN(c.time_of_day)
               WHEN 'Overnight' THEN 'Night'
               ELSE MIN(c.time_of_day)
           END AS time_of_day_display,
           CASE MIN(c.time_of_day)
               WHEN 'Overnight' THEN 1
               WHEN 'Morning' THEN 2
               WHEN 'Afternoon' THEN 3
               WHEN 'Evening' THEN 4
           END::smallint AS time_of_day_order,
           c.weekend_flag::integer AS weekend_flag,
           COUNT(*)::bigint AS reported_incident_count,
           COUNT(*) FILTER (WHERE c.arrest)::bigint AS arrest_count,
           COUNT(c.arrest)::bigint AS arrest_indicator_denominator,
           COUNT(*) FILTER (WHERE c.domestic)::bigint AS domestic_count,
           COUNT(c.domestic)::bigint AS domestic_indicator_denominator
    FROM public.clean_chicago_crimes AS c
    GROUP BY c.crime_year,
             c.crime_month,
             c.primary_type,
             c.day_of_week_num,
             c.hour_of_day,
             c.weekend_flag
)
SELECT t.month_start,
       t.crime_year,
       t.crime_month,
       t.month_name,
       t.crime_quarter,
       t.season,
       t.season_order,
       t.primary_type,
       a.annual_category_rank,
       t.day_of_week_num,
       t.day_of_week,
       t.hour_of_day,
       t.time_of_day,
       t.time_of_day_display,
       t.time_of_day_order,
       t.weekend_flag,
       t.reported_incident_count,
       t.arrest_count,
       t.arrest_indicator_denominator,
       t.domestic_count,
       t.domestic_indicator_denominator
FROM temporal_detail AS t
JOIN annual_category AS a
  ON a.crime_year = t.crime_year
 AND a.primary_type = t.primary_type;

COMMENT ON VIEW public.vw_tableau_temporal_detail IS
'Tableau Page 3 source at complete calendar month, source primary type, ISO weekday, and recorded hour grain. Every clean incident contributes once. Canonical season and time-of-day definitions are preserved; timestamps may be estimated.';

CREATE VIEW public.vw_tableau_temporal_kpis AS
WITH scoped_incidents AS (
    SELECT c.crime_year,
           'All Crime Types'::text AS primary_type_scope,
           c.crime_month,
           c.month_name,
           c.day_of_week_num,
           c.day_of_week,
           c.hour_of_day
    FROM public.clean_chicago_crimes AS c
    UNION ALL
    SELECT c.crime_year,
           c.primary_type AS primary_type_scope,
           c.crime_month,
           c.month_name,
           c.day_of_week_num,
           c.day_of_week,
           c.hour_of_day
    FROM public.clean_chicago_crimes AS c
), totals AS (
    SELECT crime_year,
           primary_type_scope,
           COUNT(*)::bigint AS reported_incident_count
    FROM scoped_incidents
    GROUP BY crime_year, primary_type_scope
), hour_ranked AS (
    SELECT crime_year,
           primary_type_scope,
           hour_of_day,
           COUNT(*)::bigint AS incident_count,
           ROW_NUMBER() OVER (
               PARTITION BY crime_year, primary_type_scope
               ORDER BY COUNT(*) DESC, hour_of_day ASC
           ) AS peak_rank
    FROM scoped_incidents
    GROUP BY crime_year, primary_type_scope, hour_of_day
), day_ranked AS (
    SELECT crime_year,
           primary_type_scope,
           day_of_week_num,
           day_of_week,
           COUNT(*)::bigint AS incident_count,
           ROW_NUMBER() OVER (
               PARTITION BY crime_year, primary_type_scope
               ORDER BY COUNT(*) DESC, day_of_week_num ASC
           ) AS peak_rank
    FROM scoped_incidents
    GROUP BY crime_year, primary_type_scope, day_of_week_num, day_of_week
), month_ranked AS (
    SELECT crime_year,
           primary_type_scope,
           crime_month,
           month_name,
           COUNT(*)::bigint AS incident_count,
           ROW_NUMBER() OVER (
               PARTITION BY crime_year, primary_type_scope
               ORDER BY COUNT(*) DESC, crime_month ASC
           ) AS peak_rank
    FROM scoped_incidents
    GROUP BY crime_year, primary_type_scope, crime_month, month_name
)
SELECT t.crime_year,
       t.primary_type_scope,
       t.reported_incident_count,
       h.hour_of_day AS peak_hour,
       LPAD(h.hour_of_day::text, 2, '0') || ':00' AS peak_hour_label,
       h.incident_count AS peak_hour_incident_count,
       d.day_of_week_num AS peak_day_num,
       d.day_of_week AS peak_day,
       d.incident_count AS peak_day_incident_count,
       m.crime_month AS peak_month_num,
       m.month_name AS peak_month,
       m.incident_count AS peak_month_incident_count
FROM totals AS t
JOIN hour_ranked AS h
  ON h.crime_year = t.crime_year
 AND h.primary_type_scope = t.primary_type_scope
 AND h.peak_rank = 1
JOIN day_ranked AS d
  ON d.crime_year = t.crime_year
 AND d.primary_type_scope = t.primary_type_scope
 AND d.peak_rank = 1
JOIN month_ranked AS m
  ON m.crime_year = t.crime_year
 AND m.primary_type_scope = t.primary_type_scope
 AND m.peak_rank = 1;

COMMENT ON VIEW public.vw_tableau_temporal_kpis IS
'Tableau Page 3 KPI source at complete year and selected crime-type scope grain. All Crime Types is materialized explicitly so peak hour, weekday, and month do not depend on Tableau table-calculation addressing.';

COMMIT;
