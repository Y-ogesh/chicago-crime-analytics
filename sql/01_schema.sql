\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS public.raw_chicago_crimes_staging (
    source_row_number bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id text,
    case_number text,
    date text,
    block text,
    iucr text,
    primary_type text,
    description text,
    location_description text,
    arrest text,
    domestic text,
    beat text,
    district text,
    ward text,
    community_area text,
    fbi_code text,
    x_coordinate text,
    y_coordinate text,
    year text,
    updated_on text,
    latitude text,
    longitude text,
    location text
);

COMMENT ON TABLE public.raw_chicago_crimes_staging IS
    'Source fields parsed from the CSV before type conversion; PostgreSQL CSV NULL semantics are retained.';
COMMENT ON COLUMN public.raw_chicago_crimes_staging.source_row_number IS
    'CSV row order assigned during import; not a source field.';

CREATE TABLE IF NOT EXISTS public.raw_chicago_crimes (
    id bigint PRIMARY KEY,
    case_number text NOT NULL,
    date timestamp(3) without time zone NOT NULL,
    block text NOT NULL,
    iucr text NOT NULL,
    primary_type text NOT NULL,
    description text NOT NULL,
    location_description text,
    arrest boolean NOT NULL,
    domestic boolean NOT NULL,
    beat text NOT NULL,
    district text NOT NULL,
    ward smallint,
    community_area smallint,
    fbi_code text NOT NULL,
    x_coordinate integer,
    y_coordinate integer,
    year smallint NOT NULL,
    updated_on timestamp(3) without time zone NOT NULL,
    latitude numeric(12, 9),
    longitude numeric(12, 9),
    location text
);

-- Keep existing installations aligned when this idempotent schema is rerun.
ALTER TABLE public.raw_chicago_crimes
    ALTER COLUMN location_description DROP NOT NULL,
    ALTER COLUMN location DROP NOT NULL;

COMMENT ON TABLE public.raw_chicago_crimes IS
    'Typed, one-row-per-source-ID representation of the acquired Chicago crimes CSV; no analytical cleaning applied.';
COMMENT ON COLUMN public.raw_chicago_crimes.id IS
    'Official City of Chicago source record identifier.';
COMMENT ON COLUMN public.raw_chicago_crimes.date IS
    'Source incident timestamp without an asserted timezone; the source states this can be an estimate.';
COMMENT ON COLUMN public.raw_chicago_crimes.arrest IS
    'Source arrest indicator; not a clearance, prosecution, or conviction measure.';
COMMENT ON COLUMN public.raw_chicago_crimes.location IS
    'Source location text preserved verbatim when present, including embedded line breaks.';

CREATE TABLE IF NOT EXISTS public.raw_chicago_crimes_load_audit (
    load_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    loaded_at_utc timestamp(0) with time zone NOT NULL DEFAULT clock_timestamp(),
    source_file_name text NOT NULL,
    source_sha256 character(64) NOT NULL,
    expected_row_count bigint NOT NULL,
    staging_row_count bigint NOT NULL,
    imported_row_count bigint NOT NULL,
    distinct_source_id_count bigint NOT NULL,
    min_incident_date timestamp(3) without time zone,
    max_incident_date timestamp(3) without time zone,
    records_by_year jsonb NOT NULL,
    CONSTRAINT raw_chicago_crimes_load_audit_nonnegative_counts CHECK (
        expected_row_count >= 0
        AND staging_row_count >= 0
        AND imported_row_count >= 0
        AND distinct_source_id_count >= 0
    )
);

COMMENT ON TABLE public.raw_chicago_crimes_load_audit IS
    'Reproducibility evidence for each successfully committed raw-table rebuild.';

COMMIT;
