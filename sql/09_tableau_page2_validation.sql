\set ON_ERROR_STOP on
\pset pager off
\pset null '[NULL]'
\timing on

BEGIN READ ONLY;

DO $$
DECLARE
    detail_rows bigint;
    detail_incidents bigint;
    clean_incidents bigint;
    detail_mappable bigint;
    clean_mappable bigint;
    detail_area_eligible bigint;
    clean_area_eligible bigint;
    duplicate_grains bigint;
    invalid_coordinate_rows bigint;
BEGIN
    SELECT COUNT(*), SUM(reported_incident_count)
      INTO detail_rows, detail_incidents
    FROM public.vw_tableau_geographic_detail;

    SELECT COUNT(*) INTO clean_incidents
    FROM public.clean_chicago_crimes;

    IF detail_incidents <> clean_incidents THEN
        RAISE EXCEPTION
            'Geographic detail total % does not match clean total %',
            detail_incidents, clean_incidents;
    END IF;

    SELECT SUM(reported_incident_count)
      INTO detail_mappable
    FROM public.vw_tableau_geographic_detail
    WHERE coordinate_mappable_flag = 1;

    SELECT COUNT(*) INTO clean_mappable
    FROM public.clean_chicago_crimes
    WHERE coordinate_mappable_flag;

    IF detail_mappable <> clean_mappable THEN
        RAISE EXCEPTION
            'Geographic detail mappable total % does not match clean total %',
            detail_mappable, clean_mappable;
    END IF;

    SELECT SUM(reported_incident_count)
      INTO detail_area_eligible
    FROM public.vw_tableau_geographic_detail
    WHERE community_area_eligible_flag = 1;

    SELECT COUNT(*) INTO clean_area_eligible
    FROM public.clean_chicago_crimes
    WHERE community_area_eligible_flag;

    IF detail_area_eligible <> clean_area_eligible THEN
        RAISE EXCEPTION
            'Geographic detail area-eligible total % does not match clean total %',
            detail_area_eligible, clean_area_eligible;
    END IF;

    SELECT COUNT(*) INTO duplicate_grains
    FROM (
        SELECT crime_year,
               primary_type,
               community_area,
               district,
               coordinate_mappable_flag,
               cell_latitude,
               cell_longitude
        FROM public.vw_tableau_geographic_detail
        GROUP BY crime_year,
                 primary_type,
                 community_area,
                 district,
                 coordinate_mappable_flag,
                 cell_latitude,
                 cell_longitude
        HAVING COUNT(*) > 1
    ) AS duplicates;

    IF duplicate_grains <> 0 THEN
        RAISE EXCEPTION 'Geographic detail contains % duplicate grains', duplicate_grains;
    END IF;

    SELECT COUNT(*) INTO invalid_coordinate_rows
    FROM public.vw_tableau_geographic_detail
        WHERE (coordinate_mappable_flag = 1 AND (
               cell_latitude IS NULL
               OR cell_longitude IS NULL
               OR cell_latitude NOT BETWEEN 41.60 AND 42.10
               OR cell_longitude NOT BETWEEN -88.00 AND -87.50
           ))
       OR (coordinate_mappable_flag = 0 AND (
               cell_latitude IS NOT NULL
               OR cell_longitude IS NOT NULL
               OR density_cell_id IS NOT NULL
           ));

    IF invalid_coordinate_rows <> 0 THEN
        RAISE EXCEPTION
            'Geographic detail contains % coordinate-validity violations',
            invalid_coordinate_rows;
    END IF;

    IF detail_rows <> 50037 THEN
        RAISE EXCEPTION 'Expected 50,037 geographic detail rows, found %', detail_rows;
    END IF;
END
$$;

-- Reconcile the Page 2 fact source to the previously validated summary views.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM (
            SELECT crime_year,
                   community_area,
                   SUM(reported_incident_count)::bigint AS incident_count
            FROM public.vw_tableau_geographic_detail
            WHERE community_area_eligible_flag = 1
            GROUP BY crime_year, community_area
        ) AS d
        FULL JOIN public.vw_tableau_community_area_year AS s
          ON s.crime_year = d.crime_year
         AND s.community_area = d.community_area
        WHERE d.incident_count IS DISTINCT FROM s.reported_incident_count
    ) THEN
        RAISE EXCEPTION 'Community-area reconciliation failed';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM (
            SELECT crime_year,
                   district,
                   SUM(reported_incident_count)::bigint AS incident_count
            FROM public.vw_tableau_geographic_detail
            GROUP BY crime_year, district
        ) AS d
        FULL JOIN public.vw_tableau_district_year AS s
          ON s.crime_year = d.crime_year
         AND s.district = d.district
        WHERE d.incident_count IS DISTINCT FROM s.reported_incident_count
    ) THEN
        RAISE EXCEPTION 'District reconciliation failed';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM (
            SELECT crime_year,
                   community_area,
                   primary_type,
                   SUM(reported_incident_count)::bigint AS incident_count
            FROM public.vw_tableau_geographic_detail
            WHERE community_area_eligible_flag = 1
            GROUP BY crime_year, community_area, primary_type
        ) AS d
        FULL JOIN public.vw_tableau_area_category_year AS s
          ON s.crime_year = d.crime_year
         AND s.community_area = d.community_area
         AND s.primary_type = d.primary_type
        WHERE d.incident_count IS DISTINCT FROM s.reported_incident_count
    ) THEN
        RAISE EXCEPTION 'Community-area/category reconciliation failed';
    END IF;
END
$$;

\echo 'Page 2 geographic source by complete calendar year'
SELECT crime_year,
       SUM(reported_incident_count)::bigint AS reported_incidents,
       SUM(reported_incident_count) FILTER (
           WHERE community_area_eligible_flag = 1
       )::bigint AS community_area_eligible_incidents,
       SUM(reported_incident_count) FILTER (
           WHERE coordinate_mappable_flag = 1
       )::bigint AS coordinate_mappable_incidents,
       ROUND(
           100.0 * SUM(reported_incident_count) FILTER (
               WHERE coordinate_mappable_flag = 1
           ) / NULLIF(SUM(reported_incident_count), 0),
           4
       ) AS coordinate_coverage_percentage
FROM public.vw_tableau_geographic_detail
GROUP BY crime_year
ORDER BY crime_year;

\echo '2025 leading community areas'
SELECT community_area,
       community_area_name,
       SUM(reported_incident_count)::bigint AS reported_incidents,
       DENSE_RANK() OVER (
           ORDER BY SUM(reported_incident_count) DESC
       ) AS incident_rank
FROM public.vw_tableau_geographic_detail
WHERE crime_year = 2025
  AND community_area_eligible_flag = 1
GROUP BY community_area, community_area_name
ORDER BY incident_rank, community_area
LIMIT 15;

\echo '2025 police-district comparison'
SELECT district,
       district_label,
       SUM(reported_incident_count)::bigint AS reported_incidents,
       DENSE_RANK() OVER (
           ORDER BY SUM(reported_incident_count) DESC
       ) AS incident_rank
FROM public.vw_tableau_geographic_detail
WHERE crime_year = 2025
GROUP BY district, district_label
ORDER BY incident_rank, district;

\echo '2025 All and Theft Page 2 KPI benchmarks'
SELECT CASE
           WHEN GROUPING(primary_type) = 1 THEN 'All Crime Types'
           ELSE primary_type
       END AS crime_type_scope,
       SUM(reported_incident_count)::bigint AS reported_incidents,
       SUM(reported_incident_count) FILTER (
           WHERE coordinate_mappable_flag = 1
       )::bigint AS coordinate_mappable_incidents,
       ROUND(
           100.0 * SUM(reported_incident_count) FILTER (
               WHERE coordinate_mappable_flag = 1
           ) / NULLIF(SUM(reported_incident_count), 0),
           4
       ) AS coordinate_coverage_percentage
FROM public.vw_tableau_geographic_detail
WHERE crime_year = 2025
  AND (primary_type = 'THEFT' OR primary_type IS NOT NULL)
GROUP BY GROUPING SETS ((), (primary_type))
HAVING GROUPING(primary_type) = 1 OR primary_type = 'THEFT'
ORDER BY GROUPING(primary_type) DESC;

ROLLBACK;
