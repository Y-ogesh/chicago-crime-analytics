\set ON_ERROR_STOP on
\pset pager off
\pset null '[NULL]'
\timing on

BEGIN;

-- Keep the source stable while the cleaned table is rebuilt. This lock does
-- not modify raw_chicago_crimes and permits concurrent readers.
LOCK TABLE public.raw_chicago_crimes IN SHARE MODE;

DROP TABLE IF EXISTS public.clean_chicago_crimes;

CREATE TABLE public.clean_chicago_crimes (
    source_id bigint PRIMARY KEY,
    source_case_number text NOT NULL,
    case_number text NOT NULL,
    crime_timestamp timestamp(3) without time zone NOT NULL,
    crime_date date NOT NULL,
    crime_year smallint NOT NULL,
    source_year smallint NOT NULL,
    crime_month smallint NOT NULL,
    month_name text NOT NULL,
    crime_quarter smallint NOT NULL,
    day_of_week text NOT NULL,
    day_of_week_num smallint NOT NULL,
    hour_of_day smallint NOT NULL,
    time_of_day text NOT NULL,
    season text NOT NULL,
    weekend_flag boolean NOT NULL,
    block text NOT NULL,
    source_iucr text NOT NULL,
    iucr text NOT NULL,
    source_primary_type text NOT NULL,
    primary_type text NOT NULL,
    source_description text NOT NULL,
    description text NOT NULL,
    source_location_description text,
    location_description text NOT NULL,
    arrest boolean NOT NULL,
    domestic boolean NOT NULL,
    source_beat text NOT NULL,
    beat text NOT NULL,
    source_district text NOT NULL,
    district text NOT NULL,
    district_current_flag boolean NOT NULL,
    source_ward smallint,
    ward smallint,
    ward_eligible_flag boolean NOT NULL,
    source_community_area smallint,
    community_area smallint,
    community_area_eligible_flag boolean NOT NULL,
    source_fbi_code text NOT NULL,
    fbi_code text NOT NULL,
    x_coordinate integer,
    y_coordinate integer,
    updated_on timestamp(3) without time zone NOT NULL,
    latitude numeric(12, 9),
    longitude numeric(12, 9),
    location text,
    coordinate_available_flag boolean NOT NULL,
    coordinate_valid_flag boolean,
    within_city_bounds_flag boolean,
    coordinate_mappable_flag boolean NOT NULL,
    CONSTRAINT clean_crimes_year_matches_date CHECK (
        crime_year = extract(year FROM crime_date)::smallint
    ),
    CONSTRAINT clean_crimes_date_matches_timestamp CHECK (
        crime_date = crime_timestamp::date
    ),
    CONSTRAINT clean_crimes_source_year_matches_date CHECK (
        source_year = extract(year FROM crime_date)::smallint
    ),
    CONSTRAINT clean_crimes_month_range CHECK (crime_month BETWEEN 1 AND 12),
    CONSTRAINT clean_crimes_month_matches_timestamp CHECK (
        crime_month = extract(month FROM crime_timestamp)::smallint
    ),
    CONSTRAINT clean_crimes_month_name_consistency CHECK (
        month_name = CASE crime_month
            WHEN 1 THEN 'January'
            WHEN 2 THEN 'February'
            WHEN 3 THEN 'March'
            WHEN 4 THEN 'April'
            WHEN 5 THEN 'May'
            WHEN 6 THEN 'June'
            WHEN 7 THEN 'July'
            WHEN 8 THEN 'August'
            WHEN 9 THEN 'September'
            WHEN 10 THEN 'October'
            WHEN 11 THEN 'November'
            WHEN 12 THEN 'December'
        END
    ),
    CONSTRAINT clean_crimes_quarter_range CHECK (crime_quarter BETWEEN 1 AND 4),
    CONSTRAINT clean_crimes_quarter_consistency CHECK (
        crime_quarter = extract(quarter FROM crime_timestamp)::smallint
    ),
    CONSTRAINT clean_crimes_day_number_range CHECK (day_of_week_num BETWEEN 1 AND 7),
    CONSTRAINT clean_crimes_day_number_consistency CHECK (
        day_of_week_num = extract(isodow FROM crime_timestamp)::smallint
    ),
    CONSTRAINT clean_crimes_day_name_consistency CHECK (
        day_of_week = CASE day_of_week_num
            WHEN 1 THEN 'Monday'
            WHEN 2 THEN 'Tuesday'
            WHEN 3 THEN 'Wednesday'
            WHEN 4 THEN 'Thursday'
            WHEN 5 THEN 'Friday'
            WHEN 6 THEN 'Saturday'
            WHEN 7 THEN 'Sunday'
        END
    ),
    CONSTRAINT clean_crimes_hour_range CHECK (hour_of_day BETWEEN 0 AND 23),
    CONSTRAINT clean_crimes_hour_consistency CHECK (
        hour_of_day = extract(hour FROM crime_timestamp)::smallint
    ),
    CONSTRAINT clean_crimes_month_name_domain CHECK (
        month_name IN (
            'January', 'February', 'March', 'April', 'May', 'June',
            'July', 'August', 'September', 'October', 'November', 'December'
        )
    ),
    CONSTRAINT clean_crimes_day_name_domain CHECK (
        day_of_week IN (
            'Monday', 'Tuesday', 'Wednesday', 'Thursday',
            'Friday', 'Saturday', 'Sunday'
        )
    ),
    CONSTRAINT clean_crimes_time_of_day_domain CHECK (
        time_of_day IN ('Overnight', 'Morning', 'Afternoon', 'Evening')
    ),
    CONSTRAINT clean_crimes_season_domain CHECK (
        season IN ('Winter', 'Spring', 'Summer', 'Fall')
    ),
    CONSTRAINT clean_crimes_time_of_day_consistency CHECK (
        time_of_day = CASE
            WHEN hour_of_day BETWEEN 0 AND 5 THEN 'Overnight'
            WHEN hour_of_day BETWEEN 6 AND 11 THEN 'Morning'
            WHEN hour_of_day BETWEEN 12 AND 17 THEN 'Afternoon'
            ELSE 'Evening'
        END
    ),
    CONSTRAINT clean_crimes_season_consistency CHECK (
        season = CASE
            WHEN crime_month IN (12, 1, 2) THEN 'Winter'
            WHEN crime_month IN (3, 4, 5) THEN 'Spring'
            WHEN crime_month IN (6, 7, 8) THEN 'Summer'
            ELSE 'Fall'
        END
    ),
    CONSTRAINT clean_crimes_weekend_consistency CHECK (
        weekend_flag = (day_of_week_num IN (6, 7))
    ),
    CONSTRAINT clean_crimes_ward_domain CHECK (ward IS NULL OR ward BETWEEN 1 AND 50),
    CONSTRAINT clean_crimes_ward_flag_consistency CHECK (
        ward_eligible_flag = (ward IS NOT NULL)
    ),
    CONSTRAINT clean_crimes_community_area_domain CHECK (
        community_area IS NULL OR community_area BETWEEN 1 AND 77
    ),
    CONSTRAINT clean_crimes_community_area_flag_consistency CHECK (
        community_area_eligible_flag = (community_area IS NOT NULL)
    ),
    CONSTRAINT clean_crimes_coordinate_availability_consistency CHECK (
        coordinate_available_flag = (latitude IS NOT NULL AND longitude IS NOT NULL)
    ),
    CONSTRAINT clean_crimes_coordinate_validation_consistency CHECK (
        (
            coordinate_available_flag
            AND coordinate_valid_flag IS NOT NULL
            AND within_city_bounds_flag IS NOT NULL
        )
        OR (
            NOT coordinate_available_flag
            AND coordinate_valid_flag IS NULL
            AND within_city_bounds_flag IS NULL
        )
    ),
    CONSTRAINT clean_crimes_coordinate_mappable_consistency CHECK (
        coordinate_mappable_flag = (
            coordinate_available_flag
            AND coordinate_valid_flag IS TRUE
            AND within_city_bounds_flag IS TRUE
        )
    )
);

WITH ranked_source AS (
    -- raw_chicago_crimes currently enforces one row per source ID. The full
    -- ordering makes the retained row deterministic if an upstream source
    -- later presents competing versions before that constraint is restored.
    SELECT
        raw.*,
        row_number() OVER (
            PARTITION BY raw.id
            ORDER BY
                raw.updated_on DESC,
                raw.date DESC,
                raw.case_number,
                raw.block,
                raw.iucr,
                raw.primary_type,
                raw.description,
                raw.location_description NULLS LAST,
                raw.arrest DESC,
                raw.domestic DESC,
                raw.beat,
                raw.district,
                raw.ward NULLS LAST,
                raw.community_area NULLS LAST,
                raw.fbi_code,
                raw.x_coordinate NULLS LAST,
                raw.y_coordinate NULLS LAST,
                raw.year,
                raw.latitude NULLS LAST,
                raw.longitude NULLS LAST,
                raw.location NULLS LAST
        ) AS source_id_rank
    FROM public.raw_chicago_crimes AS raw
),
prepared AS (
    SELECT
        ranked.*,
        extract(month FROM ranked.date)::smallint AS derived_month,
        extract(isodow FROM ranked.date)::smallint AS derived_isodow,
        extract(hour FROM ranked.date)::smallint AS derived_hour,
        CASE
            WHEN ranked.district ~ '^[0-9]{1,3}$'
                THEN lpad(ranked.district, 3, '0')
            ELSE upper(btrim(ranked.district))
        END AS normalized_district,
        (ranked.latitude IS NOT NULL AND ranked.longitude IS NOT NULL)
            AS coordinate_available,
        CASE
            WHEN ranked.latitude IS NULL OR ranked.longitude IS NULL THEN NULL
            ELSE ranked.latitude BETWEEN -90 AND 90
                 AND ranked.longitude BETWEEN -180 AND 180
                 AND NOT (ranked.latitude = 0 AND ranked.longitude = 0)
        END AS coordinate_valid,
        CASE
            WHEN ranked.latitude IS NULL OR ranked.longitude IS NULL THEN NULL
            ELSE ranked.latitude BETWEEN 41.64455492888845 AND 42.02303113628793
                 AND ranked.longitude BETWEEN -87.94011408343225 AND -87.52413710479193
        END AS within_city_bounds
    FROM ranked_source AS ranked
    WHERE ranked.source_id_rank = 1
)
INSERT INTO public.clean_chicago_crimes (
    source_id,
    source_case_number,
    case_number,
    crime_timestamp,
    crime_date,
    crime_year,
    source_year,
    crime_month,
    month_name,
    crime_quarter,
    day_of_week,
    day_of_week_num,
    hour_of_day,
    time_of_day,
    season,
    weekend_flag,
    block,
    source_iucr,
    iucr,
    source_primary_type,
    primary_type,
    source_description,
    description,
    source_location_description,
    location_description,
    arrest,
    domestic,
    source_beat,
    beat,
    source_district,
    district,
    district_current_flag,
    source_ward,
    ward,
    ward_eligible_flag,
    source_community_area,
    community_area,
    community_area_eligible_flag,
    source_fbi_code,
    fbi_code,
    x_coordinate,
    y_coordinate,
    updated_on,
    latitude,
    longitude,
    location,
    coordinate_available_flag,
    coordinate_valid_flag,
    within_city_bounds_flag,
    coordinate_mappable_flag
)
SELECT
    prepared.id,
    prepared.case_number,
    upper(btrim(prepared.case_number)),
    prepared.date,
    prepared.date::date,
    extract(year FROM prepared.date)::smallint,
    prepared.year,
    prepared.derived_month,
    CASE prepared.derived_month
        WHEN 1 THEN 'January'
        WHEN 2 THEN 'February'
        WHEN 3 THEN 'March'
        WHEN 4 THEN 'April'
        WHEN 5 THEN 'May'
        WHEN 6 THEN 'June'
        WHEN 7 THEN 'July'
        WHEN 8 THEN 'August'
        WHEN 9 THEN 'September'
        WHEN 10 THEN 'October'
        WHEN 11 THEN 'November'
        WHEN 12 THEN 'December'
    END,
    extract(quarter FROM prepared.date)::smallint,
    CASE prepared.derived_isodow
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
        WHEN 7 THEN 'Sunday'
    END,
    prepared.derived_isodow,
    prepared.derived_hour,
    CASE
        WHEN prepared.derived_hour BETWEEN 0 AND 5 THEN 'Overnight'
        WHEN prepared.derived_hour BETWEEN 6 AND 11 THEN 'Morning'
        WHEN prepared.derived_hour BETWEEN 12 AND 17 THEN 'Afternoon'
        ELSE 'Evening'
    END,
    CASE
        WHEN prepared.derived_month IN (12, 1, 2) THEN 'Winter'
        WHEN prepared.derived_month IN (3, 4, 5) THEN 'Spring'
        WHEN prepared.derived_month IN (6, 7, 8) THEN 'Summer'
        ELSE 'Fall'
    END,
    prepared.derived_isodow IN (6, 7),
    prepared.block,
    prepared.iucr,
    upper(btrim(prepared.iucr)),
    prepared.primary_type,
    upper(btrim(prepared.primary_type)),
    prepared.description,
    upper(btrim(prepared.description)),
    prepared.location_description,
    coalesce(nullif(upper(btrim(prepared.location_description)), ''), 'UNKNOWN / NOT REPORTED'),
    prepared.arrest,
    prepared.domestic,
    prepared.beat,
    btrim(prepared.beat),
    prepared.district,
    prepared.normalized_district,
    prepared.normalized_district IN (
        '001', '002', '003', '004', '005', '006', '007', '008',
        '009', '010', '011', '012', '014', '015', '016', '017',
        '018', '019', '020', '022', '024', '025', '031'
    ),
    prepared.ward,
    CASE WHEN prepared.ward BETWEEN 1 AND 50 THEN prepared.ward END,
    coalesce(prepared.ward BETWEEN 1 AND 50, false),
    prepared.community_area,
    CASE
        WHEN prepared.community_area BETWEEN 1 AND 77 THEN prepared.community_area
    END,
    coalesce(prepared.community_area BETWEEN 1 AND 77, false),
    prepared.fbi_code,
    upper(btrim(prepared.fbi_code)),
    prepared.x_coordinate,
    prepared.y_coordinate,
    prepared.updated_on,
    prepared.latitude,
    prepared.longitude,
    prepared.location,
    prepared.coordinate_available,
    prepared.coordinate_valid,
    prepared.within_city_bounds,
    prepared.coordinate_available
        AND prepared.coordinate_valid IS TRUE
        AND prepared.within_city_bounds IS TRUE
FROM prepared;

COMMENT ON TABLE public.clean_chicago_crimes IS
    'One row per retained source ID with preserved source identifiers/categories, validated geography, and deterministic calendar features.';
COMMENT ON COLUMN public.clean_chicago_crimes.source_id IS
    'Official City source ID and canonical record key; deterministic source-ID deduplication retains rank 1.';
COMMENT ON COLUMN public.clean_chicago_crimes.crime_timestamp IS
    'Typed source incident timestamp without an asserted timezone; source states that it can be estimated.';
COMMENT ON COLUMN public.clean_chicago_crimes.source_primary_type IS
    'Primary Type exactly as stored in raw_chicago_crimes.';
COMMENT ON COLUMN public.clean_chicago_crimes.primary_type IS
    'Uppercased and outer-trimmed source Primary Type; no broader crime grouping is applied.';
COMMENT ON COLUMN public.clean_chicago_crimes.location_description IS
    'Uppercased/trimmed source location description, with null or blank represented as UNKNOWN / NOT REPORTED.';
COMMENT ON COLUMN public.clean_chicago_crimes.day_of_week_num IS
    'ISO day number: Monday=1 through Sunday=7.';
COMMENT ON COLUMN public.clean_chicago_crimes.time_of_day IS
    'Overnight=00:00-05:59, Morning=06:00-11:59, Afternoon=12:00-17:59, Evening=18:00-23:59.';
COMMENT ON COLUMN public.clean_chicago_crimes.season IS
    'Meteorological season: Winter=Dec-Feb, Spring=Mar-May, Summer=Jun-Aug, Fall=Sep-Nov.';
COMMENT ON COLUMN public.clean_chicago_crimes.district IS
    'Derived uppercase/trimmed district join key; numeric codes are left-padded to three characters.';
COMMENT ON COLUMN public.clean_chicago_crimes.district_current_flag IS
    'True when district matches the City current-district reference verified on 2026-09-25; false does not prove source invalidity.';
COMMENT ON COLUMN public.clean_chicago_crimes.community_area IS
    'Validated source community area 1-77; null when source value is null or out of range.';
COMMENT ON COLUMN public.clean_chicago_crimes.coordinate_available_flag IS
    'True when both latitude and longitude are present.';
COMMENT ON COLUMN public.clean_chicago_crimes.coordinate_valid_flag IS
    'For present pairs, true when values pass global coordinate limits and are not (0,0); null when coordinates are unavailable.';
COMMENT ON COLUMN public.clean_chicago_crimes.within_city_bounds_flag IS
    'For present pairs, true when values fall in the documented City map rectangular envelope; not a point-in-polygon test.';
COMMENT ON COLUMN public.clean_chicago_crimes.coordinate_mappable_flag IS
    'True when a coordinate pair is present, globally valid, and within the documented City map envelope.';

-- Indexes reflect planned temporal, category, and eligible-community-area
-- filters. Boolean-only indexes are intentionally omitted as low-selectivity.
CREATE INDEX clean_crimes_crime_date_idx
    ON public.clean_chicago_crimes (crime_date);
CREATE INDEX clean_crimes_year_month_idx
    ON public.clean_chicago_crimes (crime_year, crime_month);
CREATE INDEX clean_crimes_year_primary_type_idx
    ON public.clean_chicago_crimes (crime_year, primary_type);
CREATE INDEX clean_crimes_year_community_area_idx
    ON public.clean_chicago_crimes (crime_year, community_area)
    WHERE community_area_eligible_flag;

-- Abort the rebuild if row lineage, required features, or eligibility rules
-- fail. The transaction leaves the previously committed clean table intact on
-- failure and never writes to raw_chicago_crimes.
DO $$
DECLARE
    raw_rows bigint;
    raw_distinct_ids bigint;
    clean_rows bigint;
    clean_distinct_ids bigint;
    raw_without_clean bigint;
    clean_without_raw bigint;
    invalid_features bigint;
    category_mismatches bigint;
    source_preservation_mismatches bigint;
BEGIN
    SELECT count(*), count(DISTINCT id)
    INTO raw_rows, raw_distinct_ids
    FROM public.raw_chicago_crimes;

    SELECT count(*), count(DISTINCT source_id)
    INTO clean_rows, clean_distinct_ids
    FROM public.clean_chicago_crimes;

    SELECT count(*)
    INTO raw_without_clean
    FROM public.raw_chicago_crimes AS raw
    LEFT JOIN public.clean_chicago_crimes AS clean
        ON clean.source_id = raw.id
    WHERE clean.source_id IS NULL;

    SELECT count(*)
    INTO clean_without_raw
    FROM public.clean_chicago_crimes AS clean
    LEFT JOIN public.raw_chicago_crimes AS raw
        ON raw.id = clean.source_id
    WHERE raw.id IS NULL;

    SELECT count(*)
    INTO invalid_features
    FROM public.clean_chicago_crimes
    WHERE crime_date IS NULL
       OR crime_year IS NULL
       OR crime_month NOT BETWEEN 1 AND 12
       OR crime_quarter NOT BETWEEN 1 AND 4
       OR day_of_week_num NOT BETWEEN 1 AND 7
       OR hour_of_day NOT BETWEEN 0 AND 23
       OR time_of_day NOT IN ('Overnight', 'Morning', 'Afternoon', 'Evening')
       OR season NOT IN ('Winter', 'Spring', 'Summer', 'Fall')
       OR weekend_flag <> (day_of_week_num IN (6, 7));

    SELECT count(*)
    INTO category_mismatches
    FROM public.clean_chicago_crimes
    WHERE primary_type <> upper(btrim(source_primary_type))
       OR description <> upper(btrim(source_description))
       OR iucr <> upper(btrim(source_iucr));

    SELECT count(*)
    INTO source_preservation_mismatches
    FROM public.raw_chicago_crimes AS raw
    JOIN public.clean_chicago_crimes AS clean
        ON clean.source_id = raw.id
    WHERE clean.source_case_number IS DISTINCT FROM raw.case_number
       OR clean.crime_timestamp IS DISTINCT FROM raw.date
       OR clean.block IS DISTINCT FROM raw.block
       OR clean.source_iucr IS DISTINCT FROM raw.iucr
       OR clean.source_primary_type IS DISTINCT FROM raw.primary_type
       OR clean.source_description IS DISTINCT FROM raw.description
       OR clean.source_location_description IS DISTINCT FROM raw.location_description
       OR clean.arrest IS DISTINCT FROM raw.arrest
       OR clean.domestic IS DISTINCT FROM raw.domestic
       OR clean.source_beat IS DISTINCT FROM raw.beat
       OR clean.source_district IS DISTINCT FROM raw.district
       OR clean.source_ward IS DISTINCT FROM raw.ward
       OR clean.source_community_area IS DISTINCT FROM raw.community_area
       OR clean.source_fbi_code IS DISTINCT FROM raw.fbi_code
       OR clean.x_coordinate IS DISTINCT FROM raw.x_coordinate
       OR clean.y_coordinate IS DISTINCT FROM raw.y_coordinate
       OR clean.source_year IS DISTINCT FROM raw.year
       OR clean.updated_on IS DISTINCT FROM raw.updated_on
       OR clean.latitude IS DISTINCT FROM raw.latitude
       OR clean.longitude IS DISTINCT FROM raw.longitude
       OR clean.location IS DISTINCT FROM raw.location;

    IF clean_rows <> raw_distinct_ids THEN
        RAISE EXCEPTION
            'Clean rows (%) do not equal distinct raw IDs (%)',
            clean_rows, raw_distinct_ids;
    END IF;
    IF clean_distinct_ids <> clean_rows THEN
        RAISE EXCEPTION
            'Clean source IDs (%) are not unique across % rows',
            clean_distinct_ids, clean_rows;
    END IF;
    IF raw_rows - clean_rows <> raw_rows - raw_distinct_ids THEN
        RAISE EXCEPTION 'Unexpected record loss during source-ID deduplication';
    END IF;
    IF raw_without_clean <> 0 OR clean_without_raw <> 0 THEN
        RAISE EXCEPTION
            'Source-ID lineage failure: raw without clean %, clean without raw %',
            raw_without_clean, clean_without_raw;
    END IF;
    IF invalid_features <> 0 THEN
        RAISE EXCEPTION 'Invalid or missing analytical features: % rows', invalid_features;
    END IF;
    IF category_mismatches <> 0 THEN
        RAISE EXCEPTION 'Category standardization mismatch: % rows', category_mismatches;
    END IF;
    IF source_preservation_mismatches <> 0 THEN
        RAISE EXCEPTION
            'Preserved clean fields differ from raw source fields: % rows',
            source_preservation_mismatches;
    END IF;
END
$$;

ANALYZE public.clean_chicago_crimes;

COMMIT;

\echo 'V01 — Raw versus clean counts and source-ID deduplication'
WITH raw_profile AS (
    SELECT count(*) AS raw_rows, count(DISTINCT id) AS raw_distinct_ids
    FROM public.raw_chicago_crimes
),
clean_profile AS (
    SELECT count(*) AS clean_rows, count(DISTINCT source_id) AS clean_distinct_ids
    FROM public.clean_chicago_crimes
)
SELECT
    raw_rows,
    raw_distinct_ids,
    raw_rows - raw_distinct_ids AS duplicate_source_id_excess_rows,
    clean_rows,
    clean_distinct_ids,
    raw_rows - clean_rows AS actual_row_count_difference
FROM raw_profile
CROSS JOIN clean_profile;

\echo 'V02 — Source-ID lineage and preserved repeated case numbers'
SELECT
    count(*) FILTER (WHERE clean.source_id IS NULL) AS raw_ids_missing_from_clean,
    count(*) FILTER (WHERE raw.id IS NULL) AS clean_ids_missing_from_raw
FROM public.raw_chicago_crimes AS raw
FULL JOIN public.clean_chicago_crimes AS clean
    ON clean.source_id = raw.id;

WITH repeated_cases AS (
    SELECT source_case_number, count(*) AS record_count
    FROM public.clean_chicago_crimes
    GROUP BY source_case_number
    HAVING count(*) > 1
)
SELECT
    count(*) AS repeated_case_number_values,
    coalesce(sum(record_count), 0) AS affected_rows,
    coalesce(sum(record_count - 1), 0) AS excess_rows
FROM repeated_cases;

\echo 'V03 — Date coverage and records by derived year'
SELECT
    min(crime_timestamp) AS minimum_crime_timestamp,
    max(crime_timestamp) AS maximum_crime_timestamp,
    min(crime_date) AS minimum_crime_date,
    max(crime_date) AS maximum_crime_date,
    count(*) FILTER (WHERE crime_year <> source_year) AS source_year_mismatches
FROM public.clean_chicago_crimes;

SELECT crime_year, count(*) AS record_count
FROM public.clean_chicago_crimes
GROUP BY crime_year
ORDER BY crime_year;

\echo 'V04 — Required field and feature completeness'
SELECT
    count(*) FILTER (WHERE source_id IS NULL) AS missing_source_id,
    count(*) FILTER (WHERE crime_timestamp IS NULL) AS missing_crime_timestamp,
    count(*) FILTER (WHERE crime_date IS NULL) AS missing_crime_date,
    count(*) FILTER (WHERE crime_year IS NULL) AS missing_crime_year,
    count(*) FILTER (WHERE crime_month IS NULL) AS missing_crime_month,
    count(*) FILTER (WHERE month_name IS NULL OR month_name = '') AS missing_month_name,
    count(*) FILTER (WHERE crime_quarter IS NULL) AS missing_crime_quarter,
    count(*) FILTER (WHERE day_of_week IS NULL OR day_of_week = '') AS missing_day_of_week,
    count(*) FILTER (WHERE day_of_week_num IS NULL) AS missing_day_of_week_num,
    count(*) FILTER (WHERE hour_of_day IS NULL) AS missing_hour_of_day,
    count(*) FILTER (WHERE time_of_day IS NULL OR time_of_day = '') AS missing_time_of_day,
    count(*) FILTER (WHERE season IS NULL OR season = '') AS missing_season,
    count(*) FILTER (WHERE weekend_flag IS NULL) AS missing_weekend_flag,
    count(*) FILTER (WHERE primary_type IS NULL OR primary_type = '') AS missing_primary_type,
    count(*) FILTER (WHERE location_description IS NULL OR location_description = '')
        AS missing_clean_location_description
FROM public.clean_chicago_crimes;

\echo 'V05 — Feature ranges and category domains'
SELECT
    min(crime_year) AS minimum_year,
    max(crime_year) AS maximum_year,
    min(crime_month) AS minimum_month,
    max(crime_month) AS maximum_month,
    min(crime_quarter) AS minimum_quarter,
    max(crime_quarter) AS maximum_quarter,
    min(day_of_week_num) AS minimum_day_number,
    max(day_of_week_num) AS maximum_day_number,
    min(hour_of_day) AS minimum_hour,
    max(hour_of_day) AS maximum_hour,
    count(DISTINCT month_name) AS month_name_count,
    count(DISTINCT day_of_week) AS day_name_count,
    count(DISTINCT time_of_day) AS time_of_day_count,
    count(DISTINCT season) AS season_count,
    count(*) FILTER (
        WHERE crime_date <> crime_timestamp::date
           OR crime_year <> extract(year FROM crime_timestamp)::smallint
           OR crime_month <> extract(month FROM crime_timestamp)::smallint
           OR crime_quarter <> extract(quarter FROM crime_timestamp)::smallint
           OR day_of_week_num <> extract(isodow FROM crime_timestamp)::smallint
           OR hour_of_day <> extract(hour FROM crime_timestamp)::smallint
           OR time_of_day <> CASE
                WHEN hour_of_day BETWEEN 0 AND 5 THEN 'Overnight'
                WHEN hour_of_day BETWEEN 6 AND 11 THEN 'Morning'
                WHEN hour_of_day BETWEEN 12 AND 17 THEN 'Afternoon'
                ELSE 'Evening'
              END
           OR season <> CASE
                WHEN crime_month IN (12, 1, 2) THEN 'Winter'
                WHEN crime_month IN (3, 4, 5) THEN 'Spring'
                WHEN crime_month IN (6, 7, 8) THEN 'Summer'
                ELSE 'Fall'
              END
           OR weekend_flag <> (day_of_week_num IN (6, 7))
    ) AS feature_definition_mismatches
FROM public.clean_chicago_crimes;

SELECT 'time_of_day' AS feature, time_of_day AS value, count(*) AS record_count
FROM public.clean_chicago_crimes
GROUP BY time_of_day
UNION ALL
SELECT 'season', season, count(*)
FROM public.clean_chicago_crimes
GROUP BY season
UNION ALL
SELECT 'weekend_flag', weekend_flag::text, count(*)
FROM public.clean_chicago_crimes
GROUP BY weekend_flag
ORDER BY feature, value;

\echo 'V06 — Administrative-geography treatment'
SELECT
    count(*) FILTER (WHERE source_community_area IS NULL) AS source_community_area_null,
    count(*) FILTER (WHERE source_community_area = 0) AS source_community_area_zero,
    count(*) FILTER (WHERE community_area IS NULL) AS clean_community_area_null,
    count(*) FILTER (WHERE community_area_eligible_flag) AS community_area_eligible,
    count(*) FILTER (WHERE source_ward IS NULL) AS source_ward_null,
    count(*) FILTER (WHERE source_ward = 0) AS source_ward_zero,
    count(*) FILTER (WHERE ward IS NULL) AS clean_ward_null,
    count(*) FILTER (WHERE ward_eligible_flag) AS ward_eligible,
    count(*) FILTER (WHERE source_district = '16' AND district = '016')
        AS padded_district_rows,
    count(*) FILTER (WHERE district = '061' AND NOT district_current_flag)
        AS district_061_noncurrent_rows
FROM public.clean_chicago_crimes;

\echo 'V07 — Coordinate eligibility and retention'
SELECT
    count(*) AS all_clean_records,
    count(*) FILTER (WHERE coordinate_available_flag) AS coordinate_available,
    count(*) FILTER (WHERE NOT coordinate_available_flag) AS coordinate_unavailable_retained,
    count(*) FILTER (WHERE coordinate_valid_flag IS FALSE) AS coordinate_globally_invalid,
    count(*) FILTER (WHERE within_city_bounds_flag IS FALSE) AS coordinate_outside_city_bounds,
    count(*) FILTER (WHERE coordinate_mappable_flag) AS coordinate_mappable,
    round(
        100.0 * count(*) FILTER (WHERE coordinate_mappable_flag) / nullif(count(*), 0),
        4
    ) AS geographic_coverage_pct
FROM public.clean_chicago_crimes;

\echo 'V08 — Text standardization and source-category preservation'
SELECT
    count(*) FILTER (
        WHERE source_location_description IS NULL
          AND location_description = 'UNKNOWN / NOT REPORTED'
    ) AS null_location_descriptions_labeled,
    count(*) FILTER (
        WHERE source_location_description IS NOT NULL
          AND location_description <> upper(btrim(source_location_description))
    ) AS location_description_standardization_mismatches,
    count(*) FILTER (WHERE primary_type <> upper(btrim(source_primary_type)))
        AS primary_type_standardization_mismatches,
    count(DISTINCT source_primary_type) AS source_primary_type_cardinality,
    count(DISTINCT primary_type) AS clean_primary_type_cardinality,
    count(DISTINCT source_description) AS source_description_cardinality,
    count(DISTINCT description) AS clean_description_cardinality
FROM public.clean_chicago_crimes;

\echo 'V09 — Indexes created for analytical access patterns'
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'clean_chicago_crimes'
ORDER BY indexname;

\echo 'V10 — Preserved source-field reconciliation'
SELECT
    count(*) FILTER (
        WHERE clean.source_case_number IS DISTINCT FROM raw.case_number
           OR clean.crime_timestamp IS DISTINCT FROM raw.date
           OR clean.block IS DISTINCT FROM raw.block
           OR clean.source_iucr IS DISTINCT FROM raw.iucr
           OR clean.source_primary_type IS DISTINCT FROM raw.primary_type
           OR clean.source_description IS DISTINCT FROM raw.description
           OR clean.source_location_description IS DISTINCT FROM raw.location_description
           OR clean.arrest IS DISTINCT FROM raw.arrest
           OR clean.domestic IS DISTINCT FROM raw.domestic
           OR clean.source_beat IS DISTINCT FROM raw.beat
           OR clean.source_district IS DISTINCT FROM raw.district
           OR clean.source_ward IS DISTINCT FROM raw.ward
           OR clean.source_community_area IS DISTINCT FROM raw.community_area
           OR clean.source_fbi_code IS DISTINCT FROM raw.fbi_code
           OR clean.x_coordinate IS DISTINCT FROM raw.x_coordinate
           OR clean.y_coordinate IS DISTINCT FROM raw.y_coordinate
           OR clean.source_year IS DISTINCT FROM raw.year
           OR clean.updated_on IS DISTINCT FROM raw.updated_on
           OR clean.latitude IS DISTINCT FROM raw.latitude
           OR clean.longitude IS DISTINCT FROM raw.longitude
           OR clean.location IS DISTINCT FROM raw.location
    ) AS rows_with_preserved_source_field_mismatch
FROM public.raw_chicago_crimes AS raw
JOIN public.clean_chicago_crimes AS clean
    ON clean.source_id = raw.id;
