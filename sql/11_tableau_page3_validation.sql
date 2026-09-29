\set ON_ERROR_STOP on
\pset pager off
\pset null '[NULL]'
\timing on

BEGIN TRANSACTION READ ONLY;

DO $$
DECLARE
    clean_count bigint;
    view_count bigint;
    duplicate_grain_rows bigint;
    invalid_rows bigint;
BEGIN
    SELECT COUNT(*) INTO clean_count
    FROM public.clean_chicago_crimes;

    SELECT SUM(reported_incident_count) INTO view_count
    FROM public.vw_tableau_temporal_detail;

    IF view_count <> clean_count THEN
        RAISE EXCEPTION
            'Page 3 total mismatch: view %, clean %', view_count, clean_count;
    END IF;

    SELECT COUNT(*) INTO duplicate_grain_rows
    FROM (
        SELECT month_start,
               primary_type,
               day_of_week_num,
               hour_of_day,
               weekend_flag
        FROM public.vw_tableau_temporal_detail
        GROUP BY month_start,
                 primary_type,
                 day_of_week_num,
                 hour_of_day,
                 weekend_flag
        HAVING COUNT(*) > 1
    ) AS duplicates;

    IF duplicate_grain_rows <> 0 THEN
        RAISE EXCEPTION
            'Page 3 duplicate analytical-grain rows: %', duplicate_grain_rows;
    END IF;

    SELECT COUNT(*) INTO invalid_rows
    FROM public.vw_tableau_temporal_detail
    WHERE crime_year NOT BETWEEN 2023 AND 2025
       OR crime_month NOT BETWEEN 1 AND 12
       OR crime_month <> EXTRACT(MONTH FROM month_start)::integer
       OR crime_year <> EXTRACT(YEAR FROM month_start)::integer
       OR day_of_week_num NOT BETWEEN 1 AND 7
       OR hour_of_day NOT BETWEEN 0 AND 23
       OR season_order NOT BETWEEN 1 AND 4
       OR time_of_day_order NOT BETWEEN 1 AND 4
       OR weekend_flag NOT IN (0, 1)
       OR reported_incident_count <= 0
       OR arrest_count NOT BETWEEN 0 AND arrest_indicator_denominator
       OR domestic_count NOT BETWEEN 0 AND domestic_indicator_denominator
       OR arrest_indicator_denominator <> reported_incident_count
       OR domestic_indicator_denominator <> reported_incident_count;

    IF invalid_rows <> 0 THEN
        RAISE EXCEPTION 'Page 3 invalid field/measure rows: %', invalid_rows;
    END IF;
END
$$;

DO $$
DECLARE
    mismatch_count bigint;
BEGIN
    SELECT COUNT(*) INTO mismatch_count
    FROM public.vw_tableau_temporal_detail
    WHERE month_name <> CASE crime_month
            WHEN 1 THEN 'January' WHEN 2 THEN 'February'
            WHEN 3 THEN 'March' WHEN 4 THEN 'April'
            WHEN 5 THEN 'May' WHEN 6 THEN 'June'
            WHEN 7 THEN 'July' WHEN 8 THEN 'August'
            WHEN 9 THEN 'September' WHEN 10 THEN 'October'
            WHEN 11 THEN 'November' WHEN 12 THEN 'December'
        END
       OR day_of_week <> CASE day_of_week_num
            WHEN 1 THEN 'Monday' WHEN 2 THEN 'Tuesday'
            WHEN 3 THEN 'Wednesday' WHEN 4 THEN 'Thursday'
            WHEN 5 THEN 'Friday' WHEN 6 THEN 'Saturday'
            WHEN 7 THEN 'Sunday'
        END
       OR season <> CASE
            WHEN crime_month IN (12, 1, 2) THEN 'Winter'
            WHEN crime_month IN (3, 4, 5) THEN 'Spring'
            WHEN crime_month IN (6, 7, 8) THEN 'Summer'
            WHEN crime_month IN (9, 10, 11) THEN 'Fall'
        END
       OR season_order <> CASE
            WHEN crime_month IN (12, 1, 2) THEN 1
            WHEN crime_month IN (3, 4, 5) THEN 2
            WHEN crime_month IN (6, 7, 8) THEN 3
            WHEN crime_month IN (9, 10, 11) THEN 4
        END
       OR time_of_day <> CASE
            WHEN hour_of_day BETWEEN 0 AND 5 THEN 'Overnight'
            WHEN hour_of_day BETWEEN 6 AND 11 THEN 'Morning'
            WHEN hour_of_day BETWEEN 12 AND 17 THEN 'Afternoon'
            WHEN hour_of_day BETWEEN 18 AND 23 THEN 'Evening'
        END
       OR time_of_day_order <> CASE
            WHEN hour_of_day BETWEEN 0 AND 5 THEN 1
            WHEN hour_of_day BETWEEN 6 AND 11 THEN 2
            WHEN hour_of_day BETWEEN 12 AND 17 THEN 3
            WHEN hour_of_day BETWEEN 18 AND 23 THEN 4
        END
       OR time_of_day_display <> CASE
            WHEN hour_of_day BETWEEN 0 AND 5 THEN 'Night'
            WHEN hour_of_day BETWEEN 6 AND 11 THEN 'Morning'
            WHEN hour_of_day BETWEEN 12 AND 17 THEN 'Afternoon'
            WHEN hour_of_day BETWEEN 18 AND 23 THEN 'Evening'
        END
       OR weekend_flag <> CASE
            WHEN day_of_week_num IN (6, 7) THEN 1 ELSE 0
        END;

    IF mismatch_count <> 0 THEN
        RAISE EXCEPTION 'Page 3 temporal-definition mismatches: %', mismatch_count;
    END IF;

    SELECT COUNT(*) INTO mismatch_count
    FROM (
        SELECT COALESCE(v.crime_year, c.crime_year) AS crime_year,
               COALESCE(v.primary_type, c.primary_type) AS primary_type
        FROM (
            SELECT crime_year,
                   primary_type,
                   SUM(reported_incident_count) AS incident_count
            FROM public.vw_tableau_temporal_detail
            GROUP BY crime_year, primary_type
        ) AS v
        FULL OUTER JOIN (
            SELECT crime_year,
                   primary_type,
                   COUNT(*) AS incident_count
            FROM public.clean_chicago_crimes
            GROUP BY crime_year, primary_type
        ) AS c
          ON c.crime_year = v.crime_year
         AND c.primary_type = v.primary_type
        WHERE v.incident_count IS DISTINCT FROM c.incident_count
    ) AS differences;

    IF mismatch_count <> 0 THEN
        RAISE EXCEPTION 'Page 3 year/category reconciliation mismatches: %', mismatch_count;
    END IF;
END
$$;

DO $$
DECLARE
    kpi_row_count bigint;
    mismatch_count bigint;
BEGIN
    SELECT COUNT(*) INTO kpi_row_count
    FROM public.vw_tableau_temporal_kpis;

    IF kpi_row_count <> 96 THEN
        RAISE EXCEPTION 'Page 3 KPI source row count: expected 96, got %', kpi_row_count;
    END IF;

    SELECT COUNT(*) INTO mismatch_count
    FROM (
        VALUES
            (2025, 'All Crime Types'::text, 238086::bigint, '00:00'::text, 16749::bigint, 'Friday'::text, 35445::bigint, 'July'::text, 22710::bigint),
            (2025, 'THEFT'::text, 55198::bigint, '12:00'::text, 3748::bigint, 'Friday'::text, 8421::bigint, 'July'::text, 5404::bigint)
    ) AS expected(
        crime_year, primary_type_scope, reported_incident_count,
        peak_hour_label, peak_hour_incident_count,
        peak_day, peak_day_incident_count,
        peak_month, peak_month_incident_count
    )
    LEFT JOIN public.vw_tableau_temporal_kpis AS actual
      USING (crime_year, primary_type_scope)
    WHERE actual.reported_incident_count IS DISTINCT FROM expected.reported_incident_count
       OR actual.peak_hour_label IS DISTINCT FROM expected.peak_hour_label
       OR actual.peak_hour_incident_count IS DISTINCT FROM expected.peak_hour_incident_count
       OR actual.peak_day IS DISTINCT FROM expected.peak_day
       OR actual.peak_day_incident_count IS DISTINCT FROM expected.peak_day_incident_count
       OR actual.peak_month IS DISTINCT FROM expected.peak_month
       OR actual.peak_month_incident_count IS DISTINCT FROM expected.peak_month_incident_count;

    IF mismatch_count <> 0 THEN
        RAISE EXCEPTION 'Page 3 materialized KPI benchmark mismatches: %', mismatch_count;
    END IF;
END
$$;

\echo 'Page 3 source structure and complete-year totals'
SELECT COUNT(*) AS source_rows,
       COUNT(DISTINCT primary_type) AS crime_types,
       MIN(month_start) AS first_month,
       MAX(month_start) AS last_month,
       SUM(reported_incident_count) AS reported_incidents
FROM public.vw_tableau_temporal_detail;

SELECT crime_year,
       SUM(reported_incident_count) AS reported_incidents,
       SUM(arrest_count) AS arrest_count,
       ROUND(
           100.0 * SUM(arrest_count)
           / NULLIF(SUM(arrest_indicator_denominator), 0), 4
       ) AS arrest_percentage,
       SUM(domestic_count) AS domestic_count,
       ROUND(
           100.0 * SUM(domestic_count)
           / NULLIF(SUM(domestic_indicator_denominator), 0), 4
       ) AS domestic_incident_percentage
FROM public.vw_tableau_temporal_detail
GROUP BY crime_year
ORDER BY crime_year;

\echo 'Page 3 required filter-state KPI benchmarks'
WITH scopes AS (
    SELECT '2025 / All Crime Types'::text AS scope,
           *
    FROM public.vw_tableau_temporal_detail
    WHERE crime_year = 2025

    UNION ALL

    SELECT '2025 / THEFT'::text AS scope,
           *
    FROM public.vw_tableau_temporal_detail
    WHERE crime_year = 2025
      AND primary_type = 'THEFT'
), totals AS (
    SELECT scope,
           SUM(reported_incident_count) AS reported_incidents,
           SUM(arrest_count) AS arrest_count,
           SUM(domestic_count) AS domestic_count
    FROM scopes
    GROUP BY scope
), hour_counts AS (
    SELECT scope,
           hour_of_day,
           SUM(reported_incident_count) AS incident_count,
           ROW_NUMBER() OVER (
               PARTITION BY scope
               ORDER BY SUM(reported_incident_count) DESC, hour_of_day ASC
           ) AS row_num
    FROM scopes
    GROUP BY scope, hour_of_day
), day_counts AS (
    SELECT scope,
           day_of_week_num,
           day_of_week,
           SUM(reported_incident_count) AS incident_count,
           ROW_NUMBER() OVER (
               PARTITION BY scope
               ORDER BY SUM(reported_incident_count) DESC, day_of_week_num ASC
           ) AS row_num
    FROM scopes
    GROUP BY scope, day_of_week_num, day_of_week
), month_counts AS (
    SELECT scope,
           month_start,
           month_name,
           SUM(reported_incident_count) AS incident_count,
           ROW_NUMBER() OVER (
               PARTITION BY scope
               ORDER BY SUM(reported_incident_count) DESC, month_start ASC
           ) AS row_num
    FROM scopes
    GROUP BY scope, month_start, month_name
), season_counts AS (
    SELECT scope,
           season_order,
           season,
           SUM(reported_incident_count) AS incident_count,
           ROW_NUMBER() OVER (
               PARTITION BY scope
               ORDER BY SUM(reported_incident_count) DESC, season_order ASC
           ) AS row_num
    FROM scopes
    GROUP BY scope, season_order, season
)
SELECT t.scope,
       t.reported_incidents,
       t.arrest_count,
       t.domestic_count,
       h.hour_of_day AS peak_hour,
       h.incident_count AS peak_hour_incidents,
       d.day_of_week AS peak_day,
       d.incident_count AS peak_day_incidents,
       m.month_name AS peak_month,
       m.incident_count AS peak_month_incidents,
       s.season AS peak_season,
       s.incident_count AS peak_season_incidents
FROM totals AS t
JOIN hour_counts AS h ON h.scope = t.scope AND h.row_num = 1
JOIN day_counts AS d ON d.scope = t.scope AND d.row_num = 1
JOIN month_counts AS m ON m.scope = t.scope AND m.row_num = 1
JOIN season_counts AS s ON s.scope = t.scope AND s.row_num = 1
ORDER BY t.scope;

\echo '2025 seasonal totals for manual Tableau validation'
WITH scopes AS (
    SELECT 'All Crime Types'::text AS crime_type_scope, *
    FROM public.vw_tableau_temporal_detail
    WHERE crime_year = 2025
    UNION ALL
    SELECT 'THEFT'::text AS crime_type_scope, *
    FROM public.vw_tableau_temporal_detail
    WHERE crime_year = 2025 AND primary_type = 'THEFT'
)
SELECT crime_type_scope,
       season_order,
       season,
       SUM(reported_incident_count) AS reported_incidents
FROM scopes
GROUP BY crime_type_scope, season_order, season
ORDER BY crime_type_scope, season_order;

\echo '2025 time-of-day totals for manual Tableau validation'
WITH scopes AS (
    SELECT 'All Crime Types'::text AS crime_type_scope, *
    FROM public.vw_tableau_temporal_detail
    WHERE crime_year = 2025
    UNION ALL
    SELECT 'THEFT'::text AS crime_type_scope, *
    FROM public.vw_tableau_temporal_detail
    WHERE crime_year = 2025 AND primary_type = 'THEFT'
)
SELECT crime_type_scope,
       time_of_day_order,
       time_of_day,
       SUM(reported_incident_count) AS reported_incidents
FROM scopes
GROUP BY crime_type_scope, time_of_day_order, time_of_day
ORDER BY crime_type_scope, time_of_day_order;

\echo '2025 monthly totals for manual Tableau validation'
WITH scopes AS (
    SELECT 'All Crime Types'::text AS crime_type_scope, *
    FROM public.vw_tableau_temporal_detail
    WHERE crime_year = 2025
    UNION ALL
    SELECT 'THEFT'::text AS crime_type_scope, *
    FROM public.vw_tableau_temporal_detail
    WHERE crime_year = 2025 AND primary_type = 'THEFT'
)
SELECT crime_type_scope,
       month_start,
       MIN(month_name) AS month_name,
       SUM(reported_incident_count) AS reported_incidents
FROM scopes
GROUP BY crime_type_scope, month_start
ORDER BY crime_type_scope, month_start;

\echo '2025 peak weekday-hour heatmap cells'
WITH scopes AS (
    SELECT 'All Crime Types'::text AS crime_type_scope, *
    FROM public.vw_tableau_temporal_detail
    WHERE crime_year = 2025
    UNION ALL
    SELECT 'THEFT'::text AS crime_type_scope, *
    FROM public.vw_tableau_temporal_detail
    WHERE crime_year = 2025 AND primary_type = 'THEFT'
), cells AS (
    SELECT crime_type_scope,
           day_of_week_num,
           day_of_week,
           hour_of_day,
           SUM(reported_incident_count) AS reported_incidents,
           ROW_NUMBER() OVER (
               PARTITION BY crime_type_scope
               ORDER BY SUM(reported_incident_count) DESC,
                        day_of_week_num ASC,
                        hour_of_day ASC
           ) AS row_num
    FROM scopes
    GROUP BY crime_type_scope, day_of_week_num, day_of_week, hour_of_day
)
SELECT crime_type_scope,
       day_of_week_num,
       day_of_week,
       hour_of_day,
       reported_incidents
FROM cells
WHERE row_num = 1
ORDER BY crime_type_scope;

\echo '2025 leading crime categories for the temporal comparison'
SELECT primary_type,
       MIN(annual_category_rank) AS annual_category_rank,
       SUM(reported_incident_count) AS reported_incidents
FROM public.vw_tableau_temporal_detail
WHERE crime_year = 2025
GROUP BY primary_type
ORDER BY annual_category_rank, primary_type
LIMIT 5;

ROLLBACK;
