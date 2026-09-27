\set ON_ERROR_STOP on
\pset pager off
\pset null '[NULL]'
\timing on

-- Milestone 9B preparation: read-only validation for the planned
-- Executive Overview page. This script validates data sources and benchmarks;
-- it does not validate a Tableau workbook or any dashboard interaction.

BEGIN TRANSACTION READ ONLY;

DO $$
BEGIN
    IF (SELECT COUNT(*) FROM public.vw_tableau_executive_year) <> 3 THEN
        RAISE EXCEPTION 'Expected three executive-year rows';
    END IF;

    IF (SELECT COUNT(*) FROM public.vw_tableau_crime_arrest_year) <> 93 THEN
        RAISE EXCEPTION 'Expected 93 crime-type/year rows';
    END IF;

    IF (SELECT COUNT(*) FROM public.vw_tableau_month_category)
       <> 36 * (SELECT COUNT(DISTINCT primary_type)
                FROM public.clean_chicago_crimes) THEN
        RAISE EXCEPTION 'Month/category export does not contain the complete grid';
    END IF;

    IF EXISTS (
        WITH category_rollup AS (
            SELECT crime_year,
                   SUM(reported_incident_count)::bigint AS reported_incident_count,
                   SUM(arrest_count)::bigint AS arrest_count,
                   SUM(arrest_indicator_denominator)::bigint AS arrest_denominator,
                   SUM(domestic_count)::bigint AS domestic_count,
                   SUM(domestic_indicator_denominator)::bigint AS domestic_denominator
            FROM public.vw_tableau_crime_arrest_year
            GROUP BY crime_year
        )
        SELECT 1
        FROM category_rollup AS c
        JOIN public.vw_tableau_executive_year AS e USING (crime_year)
        WHERE c.reported_incident_count <> e.reported_incident_count
           OR c.arrest_count <> e.arrest_count
           OR c.arrest_denominator <> e.arrest_indicator_denominator
           OR c.domestic_count <> e.domestic_count
           OR c.domestic_denominator <> e.domestic_indicator_denominator
    ) THEN
        RAISE EXCEPTION 'Crime-type rollups do not reconcile to executive KPIs';
    END IF;

    IF EXISTS (
        SELECT m.crime_year
        FROM public.vw_tableau_month_category AS m
        JOIN public.vw_tableau_executive_year AS e USING (crime_year)
        GROUP BY m.crime_year, e.reported_incident_count
        HAVING COUNT(DISTINCT m.month_start) <> 12
            OR SUM(m.reported_incident_count) <> e.reported_incident_count
    ) THEN
        RAISE EXCEPTION 'Month/category rows do not reconcile to executive yearly totals';
    END IF;

    IF EXISTS (
        SELECT y.crime_year, y.primary_type
        FROM public.vw_tableau_crime_arrest_year AS y
        JOIN (
            SELECT crime_year,
                   primary_type,
                   COUNT(*) AS month_count,
                   SUM(reported_incident_count)::bigint AS reported_incident_count,
                   SUM(arrest_count)::bigint AS arrest_count,
                   SUM(arrest_indicator_denominator)::bigint AS arrest_denominator,
                   SUM(domestic_count)::bigint AS domestic_count,
                   SUM(domestic_indicator_denominator)::bigint AS domestic_denominator
            FROM public.vw_tableau_month_category
            GROUP BY crime_year, primary_type
        ) AS m USING (crime_year, primary_type)
        WHERE m.month_count <> 12
           OR m.reported_incident_count <> y.reported_incident_count
           OR m.arrest_count <> y.arrest_count
           OR m.arrest_denominator <> y.arrest_indicator_denominator
           OR m.domestic_count <> y.domestic_count
           OR m.domestic_denominator <> y.domestic_indicator_denominator
    ) THEN
        RAISE EXCEPTION 'The two Page 1 sources do not reconcile by year and type';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.vw_tableau_executive_year
        WHERE crime_year = 2025
          AND reported_incident_count = 238086
          AND arrest_count = 38365
          AND arrest_indicator_denominator = 238086
          AND domestic_count = 45319
          AND domestic_indicator_denominator = 238086
    ) THEN
        RAISE EXCEPTION '2025 citywide KPI benchmark mismatch';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.vw_tableau_crime_arrest_year
        WHERE crime_year = 2025
          AND primary_type = 'THEFT'
          AND reported_incident_count = 55198
          AND arrest_count = 4991
          AND arrest_indicator_denominator = 55198
          AND domestic_count = 2830
          AND domestic_indicator_denominator = 55198
    ) THEN
        RAISE EXCEPTION '2025 Theft filter benchmark mismatch';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.vw_tableau_month_category
        WHERE crime_year = 2025
          AND primary_type = 'THEFT'
        GROUP BY crime_year, primary_type
        HAVING COUNT(*) = 12
           AND SUM(reported_incident_count) = 55198
           AND SUM(arrest_count) = 4991
           AND SUM(domestic_count) = 2830
    ) THEN
        RAISE EXCEPTION '2025 monthly Theft filter benchmark mismatch';
    END IF;
END
$$;

\echo 'Page 1 source reconciliation by complete calendar year'
WITH category_rollup AS (
    SELECT crime_year,
           SUM(reported_incident_count)::bigint AS reported_incident_count,
           SUM(arrest_count)::bigint AS arrest_count,
           SUM(arrest_indicator_denominator)::bigint AS arrest_denominator,
           SUM(domestic_count)::bigint AS domestic_count,
           SUM(domestic_indicator_denominator)::bigint AS domestic_denominator
    FROM public.vw_tableau_crime_arrest_year
    GROUP BY crime_year
), monthly_rollup AS (
    SELECT crime_year,
           SUM(reported_incident_count)::bigint AS monthly_incident_count
    FROM public.vw_tableau_month_category
    GROUP BY crime_year
)
SELECT e.crime_year,
       e.reported_incident_count AS executive_incidents,
       c.reported_incident_count AS category_incidents,
       m.monthly_incident_count,
       c.arrest_count,
       c.arrest_denominator,
       ROUND(100.0 * c.arrest_count / NULLIF(c.arrest_denominator, 0), 4)
           AS arrest_percentage,
       c.domestic_count,
       c.domestic_denominator,
       ROUND(100.0 * c.domestic_count / NULLIF(c.domestic_denominator, 0), 4)
           AS domestic_percentage
FROM public.vw_tableau_executive_year AS e
JOIN category_rollup AS c USING (crime_year)
JOIN monthly_rollup AS m USING (crime_year)
ORDER BY e.crime_year;

\echo 'Leading 2025 primary types'
SELECT primary_type,
       reported_incident_count,
       ROUND(percentage_of_year_total, 4) AS percentage_of_year_total,
       incident_volume_rank
FROM public.vw_tableau_crime_arrest_year
WHERE crime_year = 2025
ORDER BY reported_incident_count DESC, primary_type
LIMIT 10;

\echo '2025 monthly reported-incident trend'
SELECT month_start,
       MIN(month_name) AS month_name,
       SUM(reported_incident_count)::bigint AS reported_incident_count
FROM public.vw_tableau_month_category
WHERE crime_year = 2025
GROUP BY month_start
ORDER BY month_start;

\echo 'Theft filter benchmark across complete years'
SELECT crime_year,
       reported_incident_count,
       arrest_count,
       arrest_indicator_denominator,
       ROUND(arrest_percentage, 4) AS arrest_percentage,
       domestic_count,
       domestic_indicator_denominator,
       ROUND(domestic_incident_percentage, 4) AS domestic_incident_percentage
FROM public.vw_tableau_crime_arrest_year
WHERE primary_type = 'THEFT'
ORDER BY crime_year;

\echo '2025 monthly Theft trend'
SELECT month_start,
       month_name,
       reported_incident_count,
       ROUND(trailing_three_month_average, 2) AS trailing_three_month_average
FROM public.vw_tableau_month_category
WHERE crime_year = 2025
  AND primary_type = 'THEFT'
ORDER BY month_start;

ROLLBACK;
