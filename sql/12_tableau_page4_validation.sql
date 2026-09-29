\set ON_ERROR_STOP on
\pset pager off
\pset null '[NULL]'
\timing on

BEGIN TRANSACTION READ ONLY;

DO $$
DECLARE
    mismatch_count bigint;
BEGIN
    IF (SELECT COUNT(*) FROM public.vw_tableau_crime_arrest_year) <> 93 THEN
        RAISE EXCEPTION 'Page 4 source must contain 93 year/category rows';
    END IF;

    SELECT COUNT(*) INTO mismatch_count
    FROM public.vw_tableau_crime_arrest_year
    WHERE reported_incident_count <= 0
       OR arrest_count NOT BETWEEN 0 AND reported_incident_count
       OR domestic_count NOT BETWEEN 0 AND reported_incident_count
       OR arrest_indicator_denominator <> reported_incident_count
       OR domestic_indicator_denominator <> reported_incident_count;

    IF mismatch_count <> 0 THEN
        RAISE EXCEPTION 'Page 4 invalid numerator/denominator rows: %', mismatch_count;
    END IF;

    SELECT COUNT(*) INTO mismatch_count
    FROM (
        VALUES
            (2025, 'All Crime Types'::text, 238086::bigint, 38365::bigint, 45319::bigint),
            (2025, 'THEFT'::text, 55198::bigint, 4991::bigint, 2830::bigint)
    ) AS expected(crime_year, crime_type_scope, incidents, arrests, domestic)
    LEFT JOIN LATERAL (
        SELECT SUM(reported_incident_count)::bigint AS incidents,
               SUM(arrest_count)::bigint AS arrests,
               SUM(domestic_count)::bigint AS domestic
        FROM public.vw_tableau_crime_arrest_year AS source
        WHERE source.crime_year = expected.crime_year
          AND (
              expected.crime_type_scope = 'All Crime Types'
              OR source.primary_type = expected.crime_type_scope
          )
    ) AS actual ON true
    WHERE actual.incidents IS DISTINCT FROM expected.incidents
       OR actual.arrests IS DISTINCT FROM expected.arrests
       OR actual.domestic IS DISTINCT FROM expected.domestic;

    IF mismatch_count <> 0 THEN
        RAISE EXCEPTION 'Page 4 2025 benchmark mismatches: %', mismatch_count;
    END IF;
END
$$;

\echo 'Page 4 source structure and complete-period reconciliation'
SELECT COUNT(*) AS source_rows,
       COUNT(DISTINCT primary_type) AS crime_types,
       MIN(crime_year) AS first_year,
       MAX(crime_year) AS last_year,
       SUM(reported_incident_count) AS reported_incidents,
       SUM(arrest_count) AS arrest_count,
       SUM(domestic_count) AS domestic_count
FROM public.vw_tableau_crime_arrest_year;

\echo 'Page 4 citywide arrest and domestic percentage trend'
SELECT crime_year,
       SUM(reported_incident_count) AS reported_incidents,
       SUM(arrest_count) AS arrest_count,
       ROUND(
           100.0 * SUM(arrest_count)
           / NULLIF(SUM(reported_incident_count), 0), 4
       ) AS arrest_percentage,
       SUM(domestic_count) AS domestic_count,
       ROUND(
           100.0 * SUM(domestic_count)
           / NULLIF(SUM(reported_incident_count), 0), 4
       ) AS domestic_incident_percentage
FROM public.vw_tableau_crime_arrest_year
GROUP BY crime_year
ORDER BY crime_year;

\echo 'Page 4 required 2025 filter-state KPI benchmarks'
WITH scopes AS (
    SELECT 'All Crime Types'::text AS crime_type_scope, *
    FROM public.vw_tableau_crime_arrest_year
    WHERE crime_year = 2025
    UNION ALL
    SELECT 'THEFT'::text AS crime_type_scope, *
    FROM public.vw_tableau_crime_arrest_year
    WHERE crime_year = 2025
      AND primary_type = 'THEFT'
)
SELECT crime_type_scope,
       SUM(reported_incident_count) AS reported_incidents,
       SUM(arrest_count) AS arrest_count,
       ROUND(
           100.0 * SUM(arrest_count)
           / NULLIF(SUM(reported_incident_count), 0), 4
       ) AS arrest_percentage,
       SUM(domestic_count) AS domestic_count,
       ROUND(
           100.0 * SUM(domestic_count)
           / NULLIF(SUM(reported_incident_count), 0), 4
       ) AS domestic_incident_percentage
FROM scopes
GROUP BY crime_type_scope
ORDER BY crime_type_scope;

\echo 'Page 4 2025 leading crime categories and weighted percentages'
SELECT primary_type,
       incident_volume_rank,
       reported_incident_count,
       arrest_count,
       ROUND(
           100.0 * arrest_count
           / NULLIF(reported_incident_count, 0), 4
       ) AS arrest_percentage,
       domestic_count,
       ROUND(
           100.0 * domestic_count
           / NULLIF(reported_incident_count, 0), 4
       ) AS domestic_incident_percentage
FROM public.vw_tableau_crime_arrest_year
WHERE crime_year = 2025
ORDER BY incident_volume_rank, primary_type
LIMIT 10;

\echo 'Page 4 THEFT arrest and domestic percentage trend'
SELECT crime_year,
       reported_incident_count,
       arrest_count,
       ROUND(
           100.0 * arrest_count
           / NULLIF(reported_incident_count, 0), 4
       ) AS arrest_percentage,
       domestic_count,
       ROUND(
           100.0 * domestic_count
           / NULLIF(reported_incident_count, 0), 4
       ) AS domestic_incident_percentage
FROM public.vw_tableau_crime_arrest_year
WHERE primary_type = 'THEFT'
ORDER BY crime_year;

ROLLBACK;
