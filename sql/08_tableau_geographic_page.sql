\set ON_ERROR_STOP on

BEGIN;

DROP VIEW IF EXISTS public.vw_tableau_geographic_detail;

CREATE VIEW public.vw_tableau_geographic_detail AS
WITH geographic_detail AS (
    SELECT c.crime_year,
           c.primary_type,
           c.community_area,
           COALESCE(l.community_area_name, 'UNKNOWN / UNASSIGNED')
               AS community_area_name,
           c.community_area_eligible_flag,
           COALESCE(c.district, 'UNKNOWN/UNASSIGNED') AS district,
           CASE
               WHEN c.district IS NULL THEN 'UNKNOWN / UNASSIGNED'
               WHEN c.district_current_flag THEN 'District ' || c.district
               ELSE 'District ' || c.district || ' (unmatched current reference)'
           END AS district_label,
           COALESCE(c.district_current_flag, FALSE) AS district_current_flag,
           c.coordinate_mappable_flag,
           CASE
               WHEN c.coordinate_mappable_flag
                   THEN FLOOR(c.latitude * 100.0) / 100.0
           END AS latitude_floor,
           CASE
               WHEN c.coordinate_mappable_flag
                   THEN FLOOR(c.longitude * 100.0) / 100.0
           END AS longitude_floor,
           COUNT(*)::bigint AS reported_incident_count
    FROM public.clean_chicago_crimes AS c
    LEFT JOIN public.vw_community_area_lookup AS l
      ON l.community_area = c.community_area
    GROUP BY c.crime_year,
             c.primary_type,
             c.community_area,
             COALESCE(l.community_area_name, 'UNKNOWN / UNASSIGNED'),
             c.community_area_eligible_flag,
             COALESCE(c.district, 'UNKNOWN/UNASSIGNED'),
             CASE
                 WHEN c.district IS NULL THEN 'UNKNOWN / UNASSIGNED'
                 WHEN c.district_current_flag THEN 'District ' || c.district
                 ELSE 'District ' || c.district || ' (unmatched current reference)'
             END,
             COALESCE(c.district_current_flag, FALSE),
             c.coordinate_mappable_flag,
             CASE
                 WHEN c.coordinate_mappable_flag
                     THEN FLOOR(c.latitude * 100.0) / 100.0
             END,
             CASE
                 WHEN c.coordinate_mappable_flag
                     THEN FLOOR(c.longitude * 100.0) / 100.0
             END
)
SELECT crime_year,
       make_date(crime_year, 1, 1) AS period_start,
       primary_type,
       community_area,
       community_area_name,
       community_area_eligible_flag::integer AS community_area_eligible_flag,
       district,
       district_label,
       district_current_flag::integer AS district_current_flag,
       coordinate_mappable_flag::integer AS coordinate_mappable_flag,
       CASE
           WHEN coordinate_mappable_flag
               THEN ROUND((latitude_floor + 0.005)::numeric, 3)
       END AS cell_latitude,
       CASE
           WHEN coordinate_mappable_flag
               THEN ROUND((longitude_floor + 0.005)::numeric, 3)
       END AS cell_longitude,
       CASE
           WHEN coordinate_mappable_flag THEN CONCAT(
               ROUND((latitude_floor + 0.005)::numeric, 3), ':',
               ROUND((longitude_floor + 0.005)::numeric, 3)
           )
       END AS density_cell_id,
       reported_incident_count
FROM geographic_detail;

COMMENT ON VIEW public.vw_tableau_geographic_detail IS
'Tableau Page 2 fact source at year, source primary type, community area, district code, coordinate-eligibility, and 0.01-degree coordinate-cell grain. Every clean incident contributes once. Non-mappable records remain for non-map visuals; coordinate cells are descriptive and do not test hotspot significance.';

COMMIT;
