\set ON_ERROR_STOP on
\pset pager off

-- Latest load reconciliation.
SELECT
    load_id,
    loaded_at_utc,
    source_file_name,
    source_sha256,
    expected_row_count,
    staging_row_count,
    imported_row_count,
    distinct_source_id_count,
    min_incident_date,
    max_incident_date,
    records_by_year
FROM public.raw_chicago_crimes_load_audit
ORDER BY load_id DESC
LIMIT 1;

-- Independent table totals and source-ID uniqueness.
SELECT
    count(*) AS imported_row_count,
    count(DISTINCT id) AS distinct_source_id_count,
    min(date) AS min_incident_date,
    max(date) AS max_incident_date
FROM public.raw_chicago_crimes;

-- Complete-year record counts.
SELECT year, count(*) AS record_count
FROM public.raw_chicago_crimes
GROUP BY year
ORDER BY year;

-- Important raw-field completeness. Missing source values are represented as
-- NULL by PostgreSQL CSV parsing; present text remains unchanged.
SELECT
    count(*) FILTER (WHERE location_description IS NULL) AS null_location_description,
    count(*) FILTER (WHERE ward IS NULL) AS null_ward,
    count(*) FILTER (WHERE community_area IS NULL) AS null_community_area,
    count(*) FILTER (WHERE x_coordinate IS NULL) AS null_x_coordinate,
    count(*) FILTER (WHERE y_coordinate IS NULL) AS null_y_coordinate,
    count(*) FILTER (WHERE latitude IS NULL) AS null_latitude,
    count(*) FILTER (WHERE longitude IS NULL) AS null_longitude,
    count(*) FILTER (WHERE location IS NULL) AS null_location
FROM public.raw_chicago_crimes;

-- Representative records: first source ID, first missing-coordinate record,
-- and last source ID. Values come from the typed table after full-row staging
-- reconciliation in the loader.
WITH representative_ids AS (
    SELECT min(id) AS id FROM public.raw_chicago_crimes
    UNION
    SELECT min(id) AS id
    FROM public.raw_chicago_crimes
    WHERE latitude IS NULL OR longitude IS NULL
    UNION
    SELECT max(id) AS id FROM public.raw_chicago_crimes
)
SELECT
    crimes.id,
    crimes.case_number,
    crimes.date,
    crimes.year,
    crimes.community_area,
    crimes.latitude,
    crimes.longitude,
    crimes.location
FROM public.raw_chicago_crimes AS crimes
JOIN representative_ids USING (id)
ORDER BY crimes.id;
