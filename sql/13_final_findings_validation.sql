\set ON_ERROR_STOP on
\pset pager off
\pset null '[NULL]'
\timing on

BEGIN TRANSACTION READ ONLY;

DO $$
DECLARE
    v_count bigint;
BEGIN
    SELECT COUNT(*) INTO v_count FROM public.clean_chicago_crimes;
    IF v_count <> 761563 THEN
        RAISE EXCEPTION 'Unexpected clean record count: %', v_count;
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM public.clean_chicago_crimes
    WHERE crime_year = 2025;
    IF v_count <> 238086 THEN
        RAISE EXCEPTION 'Unexpected 2025 count: %', v_count;
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM public.vw_community_area_yoy
    WHERE previous_year = 2024 AND current_year = 2025;
    IF v_count <> 77 THEN
        RAISE EXCEPTION 'Unexpected 2024-2025 community-area rows: %', v_count;
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM (
        SELECT crime_month
        FROM public.clean_chicago_crimes
        WHERE crime_year IN (2024, 2025)
        GROUP BY crime_month
        HAVING COUNT(*) FILTER (WHERE crime_year = 2025)
             < COUNT(*) FILTER (WHERE crime_year = 2024)
    ) AS lower_months;
    IF v_count <> 12 THEN
        RAISE EXCEPTION 'Expected all 12 months to decline; observed %', v_count;
    END IF;
END
$$;

\echo 'F01 dataset scope and annual citywide trend'
SELECT
    crime_year,
    COUNT(*) AS reported_incidents,
    LAG(COUNT(*)) OVER (ORDER BY crime_year) AS previous_year_incidents,
    COUNT(*) - LAG(COUNT(*)) OVER (ORDER BY crime_year) AS absolute_change,
    ROUND(
        100.0 * (COUNT(*) - LAG(COUNT(*)) OVER (ORDER BY crime_year))
        / NULLIF(LAG(COUNT(*)) OVER (ORDER BY crime_year), 0),
        4
    ) AS percentage_change
FROM public.clean_chicago_crimes
GROUP BY crime_year
ORDER BY crime_year;

\echo 'F02 selected 2024-2025 source-category changes'
WITH category_year AS (
    SELECT crime_year, primary_type, COUNT(*) AS incidents
    FROM public.clean_chicago_crimes
    WHERE crime_year IN (2024, 2025)
      AND primary_type IN (
          'THEFT', 'MOTOR VEHICLE THEFT', 'BATTERY',
          'ROBBERY', 'NARCOTICS', 'BURGLARY'
      )
    GROUP BY crime_year, primary_type
)
SELECT
    primary_type,
    MAX(incidents) FILTER (WHERE crime_year = 2024) AS incidents_2024,
    MAX(incidents) FILTER (WHERE crime_year = 2025) AS incidents_2025,
    MAX(incidents) FILTER (WHERE crime_year = 2025)
        - MAX(incidents) FILTER (WHERE crime_year = 2024) AS absolute_change,
    ROUND(
        100.0 * (
            MAX(incidents) FILTER (WHERE crime_year = 2025)
            - MAX(incidents) FILTER (WHERE crime_year = 2024)
        ) / NULLIF(MAX(incidents) FILTER (WHERE crime_year = 2024), 0),
        4
    ) AS percentage_change
FROM category_year
GROUP BY primary_type
ORDER BY ABS(
    MAX(incidents) FILTER (WHERE crime_year = 2025)
    - MAX(incidents) FILTER (WHERE crime_year = 2024)
) DESC;

\echo 'F03 community-area percentage and absolute change leaders'
SELECT
    community_area,
    community_area_name,
    previous_year_incident_count,
    current_year_incident_count,
    absolute_change,
    ROUND(percentage_change, 4) AS percentage_change,
    percentage_decrease_rank,
    absolute_decrease_rank,
    percentage_rank_eligible
FROM public.vw_community_area_yoy
WHERE previous_year = 2024
  AND current_year = 2025
  AND community_area IN (12, 25)
ORDER BY community_area;

SELECT
    COUNT(*) FILTER (WHERE absolute_change < 0) AS areas_decreased,
    COUNT(*) FILTER (WHERE absolute_change > 0) AS areas_increased,
    COUNT(*) FILTER (WHERE absolute_change = 0) AS areas_unchanged,
    COUNT(*) FILTER (WHERE percentage_rank_eligible) AS percentage_rank_eligible_areas
FROM public.vw_community_area_yoy
WHERE previous_year = 2024 AND current_year = 2025;

\echo 'F04 temporal and seasonal evidence'
SELECT
    COUNT(*) AS months_lower_in_2025
FROM (
    SELECT crime_month
    FROM public.clean_chicago_crimes
    WHERE crime_year IN (2024, 2025)
    GROUP BY crime_month
    HAVING COUNT(*) FILTER (WHERE crime_year = 2025)
         < COUNT(*) FILTER (WHERE crime_year = 2024)
) AS lower_months;

SELECT
    crime_year,
    COUNT(*) FILTER (WHERE season = 'Summer') AS summer_incidents,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE season = 'Summer') / COUNT(*),
        4
    ) AS summer_share
FROM public.clean_chicago_crimes
GROUP BY crime_year
ORDER BY crime_year;

SELECT
    time_of_day,
    COUNT(*) AS reported_incidents,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 4) AS share_of_records
FROM public.clean_chicago_crimes
GROUP BY time_of_day
ORDER BY MIN(hour_of_day);

\echo 'F05 geographic coverage and concentration evidence'
SELECT
    COUNT(*) AS reported_incidents,
    COUNT(*) FILTER (WHERE community_area_eligible_flag) AS community_area_eligible,
    ROUND(100.0 * COUNT(*) FILTER (WHERE community_area_eligible_flag) / COUNT(*), 4)
        AS community_area_coverage,
    COUNT(*) FILTER (WHERE coordinate_mappable_flag) AS coordinate_mappable,
    ROUND(100.0 * COUNT(*) FILTER (WHERE coordinate_mappable_flag) / COUNT(*), 4)
        AS coordinate_coverage
FROM public.clean_chicago_crimes;

SELECT 'Community Area' AS geography, 'Austin' AS geography_name, COUNT(*) AS incidents
FROM public.clean_chicago_crimes
WHERE community_area_eligible_flag AND community_area = 25
UNION ALL
SELECT 'Police District', '008', COUNT(*)
FROM public.clean_chicago_crimes
WHERE district = '008';

\echo 'F06 arrest and domestic indicator trends'
SELECT
    crime_year,
    COUNT(*) AS reported_incidents,
    COUNT(*) FILTER (WHERE arrest) AS arrest_count,
    ROUND(100.0 * COUNT(*) FILTER (WHERE arrest) / COUNT(*), 4) AS arrest_percentage,
    COUNT(*) FILTER (WHERE domestic) AS domestic_count,
    ROUND(100.0 * COUNT(*) FILTER (WHERE domestic) / COUNT(*), 4)
        AS domestic_percentage
FROM public.clean_chicago_crimes
GROUP BY crime_year
ORDER BY crime_year;

SELECT
    time_of_day,
    COUNT(*) AS reported_incidents,
    COUNT(*) FILTER (WHERE domestic) AS domestic_count,
    ROUND(100.0 * COUNT(*) FILTER (WHERE domestic) / COUNT(*), 4)
        AS domestic_percentage
FROM public.clean_chicago_crimes
GROUP BY time_of_day
ORDER BY MIN(hour_of_day);

ROLLBACK;
