\set ON_ERROR_STOP on
\pset pager off
\pset null '[NULL]'

BEGIN TRANSACTION READ ONLY;

\echo 'Q01 — Dataset baseline'
SELECT
    count(*) AS total_records,
    count(DISTINCT id) AS distinct_source_ids,
    min(date) AS minimum_incident_date,
    max(date) AS maximum_incident_date,
    count(DISTINCT year) AS distinct_source_years
FROM public.raw_chicago_crimes;

\echo 'Q02 — Duplicate source IDs and repeated case numbers'
WITH totals AS (
    SELECT count(*)::numeric AS total_records
    FROM public.raw_chicago_crimes
),
duplicate_ids AS (
    SELECT id, count(*) AS record_count
    FROM public.raw_chicago_crimes
    GROUP BY id
    HAVING count(*) > 1
),
duplicate_cases AS (
    SELECT case_number, count(*) AS record_count
    FROM public.raw_chicago_crimes
    GROUP BY case_number
    HAVING count(*) > 1
),
duplicate_id_summary AS (
    SELECT
        count(*) AS duplicated_values,
        coalesce(sum(record_count), 0) AS affected_rows,
        coalesce(sum(record_count - 1), 0) AS excess_rows,
        coalesce(max(record_count), 0) AS maximum_multiplicity
    FROM duplicate_ids
),
duplicate_case_summary AS (
    SELECT
        count(*) AS duplicated_values,
        coalesce(sum(record_count), 0) AS affected_rows,
        coalesce(sum(record_count - 1), 0) AS excess_rows,
        coalesce(max(record_count), 0) AS maximum_multiplicity
    FROM duplicate_cases
)
SELECT
    'duplicate source IDs' AS check_name,
    duplicated_values,
    affected_rows,
    round(100 * affected_rows / totals.total_records, 4) AS affected_pct,
    excess_rows,
    maximum_multiplicity
FROM duplicate_id_summary
CROSS JOIN totals
UNION ALL
SELECT
    'repeated case numbers',
    duplicated_values,
    affected_rows,
    round(100 * affected_rows / totals.total_records, 4),
    excess_rows,
    maximum_multiplicity
FROM duplicate_case_summary
CROSS JOIN totals
ORDER BY check_name;

\echo 'Q02b — Structure of repeated case-number groups'
WITH duplicated AS (
    SELECT case_number
    FROM public.raw_chicago_crimes
    GROUP BY case_number
    HAVING count(*) > 1
),
profiled AS (
    SELECT
        crimes.case_number,
        count(*) AS record_count,
        count(DISTINCT crimes.date) AS date_variants,
        count(DISTINCT crimes.primary_type) AS primary_type_variants,
        count(DISTINCT crimes.description) AS description_variants,
        count(DISTINCT crimes.block) AS block_variants,
        count(DISTINCT ROW(
            crimes.case_number,
            crimes.date,
            crimes.block,
            crimes.iucr,
            crimes.primary_type,
            crimes.description,
            crimes.location_description,
            crimes.arrest,
            crimes.domestic,
            crimes.beat,
            crimes.district,
            crimes.ward,
            crimes.community_area,
            crimes.fbi_code,
            crimes.x_coordinate,
            crimes.y_coordinate,
            crimes.year,
            crimes.latitude,
            crimes.longitude,
            crimes.location
        )) AS substantive_variants
    FROM public.raw_chicago_crimes AS crimes
    JOIN duplicated USING (case_number)
    GROUP BY crimes.case_number
)
SELECT
    count(*) AS repeated_case_number_groups,
    count(*) FILTER (WHERE date_variants > 1) AS groups_with_multiple_dates,
    count(*) FILTER (WHERE primary_type_variants > 1) AS groups_with_multiple_primary_types,
    count(*) FILTER (WHERE description_variants > 1) AS groups_with_multiple_descriptions,
    count(*) FILTER (WHERE block_variants > 1) AS groups_with_multiple_blocks,
    count(*) FILTER (WHERE substantive_variants < record_count) AS groups_with_repeated_substantive_rows,
    coalesce(sum(record_count - substantive_variants), 0) AS repeated_substantive_excess_rows
FROM profiled;

\echo 'Q02c — Repeated substantive records by primary type'
WITH totals AS (
    SELECT count(*)::numeric AS total_records
    FROM public.raw_chicago_crimes
),
duplicate_fingerprints AS (
    SELECT
        case_number,
        date,
        block,
        iucr,
        primary_type,
        description,
        location_description,
        arrest,
        domestic,
        beat,
        district,
        ward,
        community_area,
        fbi_code,
        x_coordinate,
        y_coordinate,
        year,
        latitude,
        longitude,
        location,
        count(*) AS record_count
    FROM public.raw_chicago_crimes
    GROUP BY
        case_number,
        date,
        block,
        iucr,
        primary_type,
        description,
        location_description,
        arrest,
        domestic,
        beat,
        district,
        ward,
        community_area,
        fbi_code,
        x_coordinate,
        y_coordinate,
        year,
        latitude,
        longitude,
        location
    HAVING count(*) > 1
)
SELECT
    primary_type,
    count(*) AS repeated_fingerprint_groups,
    sum(record_count) AS affected_rows,
    round(100 * sum(record_count) / totals.total_records, 4) AS affected_pct,
    sum(record_count - 1) AS excess_rows
FROM duplicate_fingerprints
CROSS JOIN totals
GROUP BY primary_type, totals.total_records
ORDER BY excess_rows DESC, primary_type;

\echo 'Q03 — Missing, malformed, and inconsistent dates'
WITH totals AS (
    SELECT count(*)::numeric AS total_records
    FROM public.raw_chicago_crimes
),
checks AS (
    SELECT
        (SELECT count(*) FROM public.raw_chicago_crimes_staging WHERE date IS NULL OR date = '') AS missing_source_dates,
        (
            SELECT count(*)
            FROM public.raw_chicago_crimes_staging
            WHERE date IS NOT NULL
              AND date <> ''
              AND date !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{3}$'
        ) AS nonstandard_source_date_formats,
        count(*) FILTER (WHERE date IS NULL) AS missing_typed_dates,
        count(*) FILTER (WHERE extract(year FROM date)::integer <> year) AS date_year_mismatches,
        count(*) FILTER (WHERE updated_on IS NULL) AS missing_update_dates
    FROM public.raw_chicago_crimes
)
SELECT check_name, affected_rows,
       round(100 * affected_rows / totals.total_records, 4) AS affected_pct
FROM checks
CROSS JOIN totals
CROSS JOIN LATERAL (
    VALUES
        ('missing source dates', missing_source_dates),
        ('nonstandard source date formats', nonstandard_source_date_formats),
        ('missing typed dates', missing_typed_dates),
        ('date/year mismatches', date_year_mismatches),
        ('missing update dates', missing_update_dates)
) AS results(check_name, affected_rows)
ORDER BY check_name;

\echo 'Q04 — Missing crime types and categorical formatting consistency'
WITH totals AS (
    SELECT count(*)::numeric AS total_records
    FROM public.raw_chicago_crimes
),
checks AS (
    SELECT
        count(*) FILTER (WHERE primary_type IS NULL OR btrim(primary_type) = '') AS missing_primary_type,
        count(*) FILTER (WHERE primary_type IS DISTINCT FROM btrim(primary_type)) AS primary_type_outer_whitespace,
        count(*) FILTER (WHERE description IS DISTINCT FROM btrim(description)) AS description_outer_whitespace,
        count(*) FILTER (
            WHERE location_description IS NOT NULL
              AND location_description IS DISTINCT FROM btrim(location_description)
        ) AS location_description_outer_whitespace,
        count(*) FILTER (WHERE iucr IS DISTINCT FROM btrim(iucr)) AS iucr_outer_whitespace,
        count(*) FILTER (WHERE fbi_code IS DISTINCT FROM btrim(fbi_code)) AS fbi_code_outer_whitespace,
        count(*) FILTER (WHERE district IS DISTINCT FROM btrim(district)) AS district_outer_whitespace,
        count(*) FILTER (WHERE beat IS DISTINCT FROM btrim(beat)) AS beat_outer_whitespace
    FROM public.raw_chicago_crimes
)
SELECT check_name, affected_rows,
       round(100 * affected_rows / totals.total_records, 4) AS affected_pct
FROM checks
CROSS JOIN totals
CROSS JOIN LATERAL (
    VALUES
        ('missing primary type', missing_primary_type),
        ('primary type outer whitespace', primary_type_outer_whitespace),
        ('description outer whitespace', description_outer_whitespace),
        ('location description outer whitespace', location_description_outer_whitespace),
        ('IUCR outer whitespace', iucr_outer_whitespace),
        ('FBI code outer whitespace', fbi_code_outer_whitespace),
        ('district outer whitespace', district_outer_whitespace),
        ('beat outer whitespace', beat_outer_whitespace)
) AS results(check_name, affected_rows)
ORDER BY check_name;

\echo 'Q04b — Normalized category cardinality and IUCR mapping consistency'
WITH iucr_conflicts AS (
    SELECT iucr, count(*) AS affected_rows
    FROM public.raw_chicago_crimes
    GROUP BY iucr
    HAVING count(DISTINCT primary_type) > 1
)
SELECT
    count(DISTINCT primary_type) AS raw_primary_type_cardinality,
    count(DISTINCT upper(btrim(primary_type))) AS normalized_primary_type_cardinality,
    count(DISTINCT location_description) AS raw_location_description_cardinality,
    count(DISTINCT upper(btrim(location_description))) AS normalized_location_description_cardinality,
    (SELECT count(*) FROM iucr_conflicts) AS conflicting_iucr_codes,
    (SELECT coalesce(sum(affected_rows), 0) FROM iucr_conflicts) AS rows_with_conflicting_iucr_mapping
FROM public.raw_chicago_crimes;

\echo 'Q04c — Code-format and official current district-reference checks'
-- Official current district reference: City of Chicago dataset 24zt-jpfn,
-- reached from the documented district-boundary view fthy-xz3r and verified
-- on 2026-09-25. Codes are padded to the three-character crime-data format.
WITH totals AS (
    SELECT count(*)::numeric AS total_records
    FROM public.raw_chicago_crimes
),
official_districts(district) AS (
    VALUES
        ('001'), ('002'), ('003'), ('004'), ('005'), ('006'), ('007'),
        ('008'), ('009'), ('010'), ('011'), ('012'), ('014'), ('015'),
        ('016'), ('017'), ('018'), ('019'), ('020'), ('022'), ('024'),
        ('025'), ('031')
),
checks AS (
    SELECT
        count(*) FILTER (WHERE district !~ '^[0-9]{3}$') AS nonstandard_district_format,
        count(*) FILTER (
            WHERE CASE
                WHEN district ~ '^[0-9]{1,3}$' THEN lpad(district, 3, '0')
                ELSE district
            END NOT IN (SELECT district FROM official_districts)
        ) AS district_not_in_current_reference,
        count(*) FILTER (WHERE beat !~ '^[0-9]{4}$') AS nonstandard_beat_format,
        count(*) FILTER (WHERE iucr !~ '^[0-9A-Z]{4}$') AS nonstandard_iucr_format
    FROM public.raw_chicago_crimes
)
SELECT check_name, affected_rows,
       round(100 * affected_rows / totals.total_records, 4) AS affected_pct
FROM checks
CROSS JOIN totals
CROSS JOIN LATERAL (
    VALUES
        ('nonstandard district format', nonstandard_district_format),
        ('district not in current official reference after padding', district_not_in_current_reference),
        ('nonstandard beat format', nonstandard_beat_format),
        ('nonstandard IUCR format', nonstandard_iucr_format)
) AS results(check_name, affected_rows)
ORDER BY check_name;

\echo 'Q04d — Values behind district-reference issues'
WITH official_districts(district) AS (
    VALUES
        ('001'), ('002'), ('003'), ('004'), ('005'), ('006'), ('007'),
        ('008'), ('009'), ('010'), ('011'), ('012'), ('014'), ('015'),
        ('016'), ('017'), ('018'), ('019'), ('020'), ('022'), ('024'),
        ('025'), ('031')
)
SELECT
    district,
    CASE
        WHEN district ~ '^[0-9]{1,3}$' THEN lpad(district, 3, '0')
        ELSE district
    END AS padded_district,
    count(*) AS affected_rows
FROM public.raw_chicago_crimes
WHERE district !~ '^[0-9]{3}$'
   OR CASE
        WHEN district ~ '^[0-9]{1,3}$' THEN lpad(district, 3, '0')
        ELSE district
      END NOT IN (SELECT district FROM official_districts)
GROUP BY district
ORDER BY affected_rows DESC, district;

\echo 'Q05 — Missing and out-of-range administrative geography'
WITH totals AS (
    SELECT count(*)::numeric AS total_records
    FROM public.raw_chicago_crimes
),
checks AS (
    SELECT
        count(*) FILTER (WHERE community_area IS NULL) AS missing_community_area,
        count(*) FILTER (WHERE community_area IS NOT NULL AND community_area NOT BETWEEN 1 AND 77) AS out_of_range_community_area,
        count(*) FILTER (WHERE district IS NULL OR btrim(district) = '') AS missing_district,
        count(*) FILTER (WHERE ward IS NULL) AS missing_ward,
        count(*) FILTER (WHERE ward IS NOT NULL AND ward NOT BETWEEN 1 AND 50) AS out_of_range_ward,
        count(*) FILTER (WHERE beat IS NULL OR btrim(beat) = '') AS missing_beat
    FROM public.raw_chicago_crimes
)
SELECT check_name, affected_rows,
       round(100 * affected_rows / totals.total_records, 4) AS affected_pct
FROM checks
CROSS JOIN totals
CROSS JOIN LATERAL (
    VALUES
        ('missing community area', missing_community_area),
        ('out-of-range community area', out_of_range_community_area),
        ('missing district', missing_district),
        ('missing ward', missing_ward),
        ('out-of-range ward', out_of_range_ward),
        ('missing beat', missing_beat)
) AS results(check_name, affected_rows)
ORDER BY check_name;

\echo 'Q05b — Missing or out-of-range community-area and ward values'
SELECT
    'community_area' AS field_name,
    community_area::text AS source_value,
    count(*) AS affected_rows
FROM public.raw_chicago_crimes
WHERE community_area IS NULL OR community_area NOT BETWEEN 1 AND 77
GROUP BY community_area
UNION ALL
SELECT
    'ward',
    ward::text,
    count(*)
FROM public.raw_chicago_crimes
WHERE ward IS NULL OR ward NOT BETWEEN 1 AND 50
GROUP BY ward
ORDER BY field_name, source_value NULLS FIRST;

\echo 'Q06 — Coordinate completeness and validity'
-- Global bounds identify impossible latitude/longitude. The City map envelope
-- is a rectangular plausibility screen, not a point-in-boundary test.
WITH totals AS (
    SELECT count(*)::numeric AS total_records
    FROM public.raw_chicago_crimes
),
checks AS (
    SELECT
        count(*) FILTER (WHERE latitude IS NULL AND longitude IS NULL) AS missing_coordinate_pair,
        count(*) FILTER (WHERE (latitude IS NULL) <> (longitude IS NULL)) AS partial_coordinate_pair,
        count(*) FILTER (
            WHERE latitude IS NOT NULL
              AND longitude IS NOT NULL
              AND (
                  latitude NOT BETWEEN -90 AND 90
                  OR longitude NOT BETWEEN -180 AND 180
                  OR (latitude = 0 AND longitude = 0)
              )
        ) AS globally_invalid_or_zero_coordinates,
        count(*) FILTER (
            WHERE latitude IS NOT NULL
              AND longitude IS NOT NULL
              AND (
                  latitude NOT BETWEEN 41.64455492888845 AND 42.02303113628793
                  OR longitude NOT BETWEEN -87.94011408343225 AND -87.52413710479193
              )
        ) AS outside_city_map_bounding_box,
        count(*) FILTER (WHERE x_coordinate IS NULL AND y_coordinate IS NULL) AS missing_projected_coordinate_pair,
        count(*) FILTER (WHERE (x_coordinate IS NULL) <> (y_coordinate IS NULL)) AS partial_projected_coordinate_pair,
        count(*) FILTER (
            WHERE (latitude IS NULL) <> (x_coordinate IS NULL)
               OR (longitude IS NULL) <> (y_coordinate IS NULL)
        ) AS coordinate_system_presence_mismatch,
        count(*) FILTER (WHERE location IS NULL) AS missing_location_point
    FROM public.raw_chicago_crimes
)
SELECT check_name, affected_rows,
       round(100 * affected_rows / totals.total_records, 4) AS affected_pct
FROM checks
CROSS JOIN totals
CROSS JOIN LATERAL (
    VALUES
        ('missing latitude/longitude pair', missing_coordinate_pair),
        ('partial latitude/longitude pair', partial_coordinate_pair),
        ('globally invalid or zero coordinates', globally_invalid_or_zero_coordinates),
        ('outside City map bounding box', outside_city_map_bounding_box),
        ('missing projected coordinate pair', missing_projected_coordinate_pair),
        ('partial projected coordinate pair', partial_projected_coordinate_pair),
        ('coordinate-system presence mismatch', coordinate_system_presence_mismatch),
        ('missing location point', missing_location_point)
) AS results(check_name, affected_rows)
ORDER BY check_name;

\echo 'Q06b — Observed coordinate ranges'
SELECT
    min(latitude) AS minimum_latitude,
    max(latitude) AS maximum_latitude,
    min(longitude) AS minimum_longitude,
    max(longitude) AS maximum_longitude,
    min(x_coordinate) AS minimum_x_coordinate,
    max(x_coordinate) AS maximum_x_coordinate,
    min(y_coordinate) AS minimum_y_coordinate,
    max(y_coordinate) AS maximum_y_coordinate
FROM public.raw_chicago_crimes;

\echo 'Q07 — Arrest and domestic indicator distributions'
WITH totals AS (
    SELECT count(*)::numeric AS total_records
    FROM public.raw_chicago_crimes
)
SELECT
    indicator,
    value,
    record_count,
    round(100 * record_count / totals.total_records, 4) AS record_pct
FROM totals
CROSS JOIN LATERAL (
    SELECT 'arrest' AS indicator, arrest::text AS value, count(*) AS record_count
    FROM public.raw_chicago_crimes
    GROUP BY arrest
    UNION ALL
    SELECT 'domestic', domestic::text, count(*)
    FROM public.raw_chicago_crimes
    GROUP BY domestic
) AS distributions
ORDER BY indicator, value;

\echo 'Q08 — Unexpected NULL or blank values across all source fields'
WITH profile AS (
    SELECT
        count(*)::numeric AS total_records,
        count(*) FILTER (WHERE id IS NULL) AS id_missing,
        count(*) FILTER (WHERE case_number IS NULL OR btrim(case_number) = '') AS case_number_missing,
        count(*) FILTER (WHERE date IS NULL) AS date_missing,
        count(*) FILTER (WHERE block IS NULL OR btrim(block) = '') AS block_missing,
        count(*) FILTER (WHERE iucr IS NULL OR btrim(iucr) = '') AS iucr_missing,
        count(*) FILTER (WHERE primary_type IS NULL OR btrim(primary_type) = '') AS primary_type_missing,
        count(*) FILTER (WHERE description IS NULL OR btrim(description) = '') AS description_missing,
        count(*) FILTER (WHERE location_description IS NULL OR btrim(location_description) = '') AS location_description_missing,
        count(*) FILTER (WHERE arrest IS NULL) AS arrest_missing,
        count(*) FILTER (WHERE domestic IS NULL) AS domestic_missing,
        count(*) FILTER (WHERE beat IS NULL OR btrim(beat) = '') AS beat_missing,
        count(*) FILTER (WHERE district IS NULL OR btrim(district) = '') AS district_missing,
        count(*) FILTER (WHERE ward IS NULL) AS ward_missing,
        count(*) FILTER (WHERE community_area IS NULL) AS community_area_missing,
        count(*) FILTER (WHERE fbi_code IS NULL OR btrim(fbi_code) = '') AS fbi_code_missing,
        count(*) FILTER (WHERE x_coordinate IS NULL) AS x_coordinate_missing,
        count(*) FILTER (WHERE y_coordinate IS NULL) AS y_coordinate_missing,
        count(*) FILTER (WHERE year IS NULL) AS year_missing,
        count(*) FILTER (WHERE updated_on IS NULL) AS updated_on_missing,
        count(*) FILTER (WHERE latitude IS NULL) AS latitude_missing,
        count(*) FILTER (WHERE longitude IS NULL) AS longitude_missing,
        count(*) FILTER (WHERE location IS NULL OR btrim(location) = '') AS location_missing
    FROM public.raw_chicago_crimes
)
SELECT
    column_name,
    affected_rows,
    round(100 * affected_rows / profile.total_records, 4) AS affected_pct
FROM profile
CROSS JOIN LATERAL (
    VALUES
        ('id', id_missing),
        ('case_number', case_number_missing),
        ('date', date_missing),
        ('block', block_missing),
        ('iucr', iucr_missing),
        ('primary_type', primary_type_missing),
        ('description', description_missing),
        ('location_description', location_description_missing),
        ('arrest', arrest_missing),
        ('domestic', domestic_missing),
        ('beat', beat_missing),
        ('district', district_missing),
        ('ward', ward_missing),
        ('community_area', community_area_missing),
        ('fbi_code', fbi_code_missing),
        ('x_coordinate', x_coordinate_missing),
        ('y_coordinate', y_coordinate_missing),
        ('year', year_missing),
        ('updated_on', updated_on_missing),
        ('latitude', latitude_missing),
        ('longitude', longitude_missing),
        ('location', location_missing)
) AS results(column_name, affected_rows)
ORDER BY column_name;

\echo 'Q09 — Records by complete calendar year'
WITH totals AS (
    SELECT count(*)::numeric AS total_records
    FROM public.raw_chicago_crimes
)
SELECT
    year,
    count(*) AS record_count,
    round(100 * count(*) / totals.total_records, 4) AS record_pct
FROM public.raw_chicago_crimes
CROSS JOIN totals
GROUP BY year, totals.total_records
ORDER BY year;

\echo 'Q10 — Category cardinality'
SELECT
    count(DISTINCT primary_type) AS primary_type_cardinality,
    count(DISTINCT description) AS description_cardinality,
    count(DISTINCT location_description) AS nonnull_location_description_cardinality,
    count(DISTINCT iucr) AS iucr_cardinality,
    count(DISTINCT fbi_code) AS fbi_code_cardinality,
    count(DISTINCT district) AS district_cardinality,
    count(DISTINCT beat) AS beat_cardinality,
    count(DISTINCT ward) AS nonnull_ward_cardinality,
    count(DISTINCT community_area) AS nonnull_community_area_cardinality
FROM public.raw_chicago_crimes;

\echo 'Q11 — Primary crime-type distribution'
WITH totals AS (
    SELECT count(*)::numeric AS total_records
    FROM public.raw_chicago_crimes
)
SELECT
    primary_type,
    count(*) AS record_count,
    round(100 * count(*) / totals.total_records, 4) AS record_pct
FROM public.raw_chicago_crimes
CROSS JOIN totals
GROUP BY primary_type, totals.total_records
ORDER BY record_count DESC, primary_type;

COMMIT;
