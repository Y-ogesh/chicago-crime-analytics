#!/usr/bin/env python3
"""Transactionally rebuild and validate PostgreSQL raw crime tables.

The loader delegates CSV parsing to psql's client-side ``\copy`` command. It
first preserves every source field as text in a staging table, then casts all
rows into ``raw_chicago_crimes`` in the same transaction. Any count, ID,
conversion, or reconciliation failure rolls back the rebuild.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional


SOURCE_FIELDS = [
    "id",
    "case_number",
    "date",
    "block",
    "iucr",
    "primary_type",
    "description",
    "location_description",
    "arrest",
    "domestic",
    "beat",
    "district",
    "ward",
    "community_area",
    "fbi_code",
    "x_coordinate",
    "y_coordinate",
    "year",
    "updated_on",
    "latitude",
    "longitude",
    "location",
]
DEFAULT_RAW_FILE = "data/raw/chicago_crimes_2023-01-01_2025-12-31.csv"
DEFAULT_MANIFEST = "data/raw/chicago_crimes_2023-01-01_2025-12-31.metadata.json"
DEFAULT_SCHEMA = "sql/01_schema.sql"
DEFAULT_VALIDATION_OUTPUT = "data/processed/raw_import_validation.json"


def load_optional_dotenv(project_root: Path) -> None:
    try:
        from dotenv import load_dotenv
    except ImportError:
        return
    load_dotenv(project_root / ".env")


def resolve_project_path(project_root: Path, value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else project_root / path


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def psql_copy_path(path: Path) -> str:
    value = str(path.resolve())
    if "\n" in value or "\r" in value:
        raise ValueError("Raw CSV path cannot contain a line break")
    return sql_literal(value)


def psql_environment() -> Dict[str, str]:
    environment = os.environ.copy()
    aliases = {
        "PGHOST": "POSTGRES_HOST",
        "PGPORT": "POSTGRES_PORT",
        "PGDATABASE": "POSTGRES_DB",
        "PGUSER": "POSTGRES_USER",
        "PGPASSWORD": "POSTGRES_PASSWORD",
        "PGSSLMODE": "POSTGRES_SSLMODE",
    }
    for pg_name, project_name in aliases.items():
        if not environment.get(pg_name) and environment.get(project_name):
            environment[pg_name] = environment[project_name]
    return environment


def run_psql(
    database: str,
    environment: Dict[str, str],
    *,
    sql: Optional[str] = None,
    file_path: Optional[Path] = None,
    tuples_only: bool = False,
) -> str:
    command: List[str] = [
        "psql",
        "--no-psqlrc",
        "--dbname",
        database,
        "--set",
        "ON_ERROR_STOP=1",
    ]
    if tuples_only:
        command.extend(["--tuples-only", "--no-align", "--quiet"])
    input_sql: Optional[str] = None
    if file_path is not None:
        command.extend(["--file", str(file_path)])
    elif sql is not None:
        input_sql = sql
    else:
        raise ValueError("sql or file_path is required")

    completed = subprocess.run(
        command,
        cwd=file_path.parent if file_path is not None else None,
        env=environment,
        input=input_sql,
        text=True,
        capture_output=True,
    )
    if completed.returncode != 0:
        message = completed.stderr.strip() or completed.stdout.strip()
        raise RuntimeError(f"psql failed with exit code {completed.returncode}: {message}")
    if completed.stderr.strip():
        print(completed.stderr.strip(), file=sys.stderr)
    return completed.stdout.strip()


def load_sql(
    raw_file: Path,
    expected_count: int,
    source_sha256: str,
) -> str:
    columns = ", ".join(SOURCE_FIELDS)
    file_name = raw_file.name
    return f"""\
\\set ON_ERROR_STOP on
BEGIN;
SELECT pg_advisory_xact_lock(hashtext('chicago-crime-analytics:raw-load'));

TRUNCATE TABLE public.raw_chicago_crimes_staging RESTART IDENTITY;
TRUNCATE TABLE public.raw_chicago_crimes;

\\copy public.raw_chicago_crimes_staging ({columns}) FROM {psql_copy_path(raw_file)} WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

DO $load_validation$
DECLARE
    actual_rows bigint;
    distinct_ids bigint;
    missing_ids bigint;
BEGIN
    SELECT
        count(*),
        count(DISTINCT id),
        count(*) FILTER (WHERE id IS NULL OR id = '')
    INTO actual_rows, distinct_ids, missing_ids
    FROM public.raw_chicago_crimes_staging;

    IF actual_rows <> {expected_count} THEN
        RAISE EXCEPTION 'Staging row count % does not equal expected count {expected_count}', actual_rows;
    END IF;
    IF distinct_ids <> {expected_count} OR missing_ids <> 0 THEN
        RAISE EXCEPTION 'Staging ID validation failed: distinct %, missing %', distinct_ids, missing_ids;
    END IF;
END
$load_validation$;

INSERT INTO public.raw_chicago_crimes (
    id,
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
    updated_on,
    latitude,
    longitude,
    location
)
SELECT
    id::bigint,
    case_number,
    date::timestamp(3) without time zone,
    block,
    iucr,
    primary_type,
    description,
    location_description,
    arrest::boolean,
    domestic::boolean,
    beat,
    district,
    NULLIF(ward, '')::smallint,
    NULLIF(community_area, '')::smallint,
    fbi_code,
    NULLIF(x_coordinate, '')::integer,
    NULLIF(y_coordinate, '')::integer,
    year::smallint,
    updated_on::timestamp(3) without time zone,
    NULLIF(latitude, '')::numeric(12, 9),
    NULLIF(longitude, '')::numeric(12, 9),
    location
FROM public.raw_chicago_crimes_staging
ORDER BY source_row_number;

DO $typed_validation$
DECLARE
    imported_rows bigint;
    distinct_ids bigint;
    mismatched_rows bigint;
BEGIN
    SELECT count(*), count(DISTINCT id)
    INTO imported_rows, distinct_ids
    FROM public.raw_chicago_crimes;

    IF imported_rows <> {expected_count} OR distinct_ids <> {expected_count} THEN
        RAISE EXCEPTION 'Typed-table validation failed: rows %, distinct IDs %', imported_rows, distinct_ids;
    END IF;

    SELECT count(*)
    INTO mismatched_rows
    FROM public.raw_chicago_crimes_staging AS staging
    JOIN public.raw_chicago_crimes AS typed
        ON typed.id = staging.id::bigint
    WHERE typed.id::text IS DISTINCT FROM staging.id
       OR typed.case_number IS DISTINCT FROM staging.case_number
       OR to_char(typed.date, 'YYYY-MM-DD"T"HH24:MI:SS.MS') IS DISTINCT FROM staging.date
       OR typed.block IS DISTINCT FROM staging.block
       OR typed.iucr IS DISTINCT FROM staging.iucr
       OR typed.primary_type IS DISTINCT FROM staging.primary_type
       OR typed.description IS DISTINCT FROM staging.description
       OR typed.location_description IS DISTINCT FROM staging.location_description
       OR typed.arrest::text IS DISTINCT FROM staging.arrest
       OR typed.domestic::text IS DISTINCT FROM staging.domestic
       OR typed.beat IS DISTINCT FROM staging.beat
       OR typed.district IS DISTINCT FROM staging.district
       OR typed.ward::text IS DISTINCT FROM NULLIF(staging.ward, '')
       OR typed.community_area::text IS DISTINCT FROM NULLIF(staging.community_area, '')
       OR typed.fbi_code IS DISTINCT FROM staging.fbi_code
       OR typed.x_coordinate::text IS DISTINCT FROM NULLIF(staging.x_coordinate, '')
       OR typed.y_coordinate::text IS DISTINCT FROM NULLIF(staging.y_coordinate, '')
       OR typed.year::text IS DISTINCT FROM staging.year
       OR to_char(typed.updated_on, 'YYYY-MM-DD"T"HH24:MI:SS.MS') IS DISTINCT FROM staging.updated_on
       OR typed.latitude IS DISTINCT FROM NULLIF(staging.latitude, '')::numeric(12, 9)
       OR typed.longitude IS DISTINCT FROM NULLIF(staging.longitude, '')::numeric(12, 9)
       OR typed.location IS DISTINCT FROM staging.location;

    IF mismatched_rows <> 0 THEN
        RAISE EXCEPTION 'Typed-to-staging reconciliation found % mismatched rows', mismatched_rows;
    END IF;
END
$typed_validation$;

INSERT INTO public.raw_chicago_crimes_load_audit (
    source_file_name,
    source_sha256,
    expected_row_count,
    staging_row_count,
    imported_row_count,
    distinct_source_id_count,
    min_incident_date,
    max_incident_date,
    records_by_year
)
SELECT
    {sql_literal(file_name)},
    {sql_literal(source_sha256)},
    {expected_count},
    (SELECT count(*) FROM public.raw_chicago_crimes_staging),
    count(*),
    count(DISTINCT id),
    min(date),
    max(date),
    (
        SELECT jsonb_object_agg(year::text, record_count ORDER BY year)
        FROM (
            SELECT year, count(*) AS record_count
            FROM public.raw_chicago_crimes
            GROUP BY year
        ) AS annual_counts
    )
FROM public.raw_chicago_crimes;

COMMIT;
"""


def validation_query() -> str:
    return """
WITH latest_audit AS (
    SELECT *
    FROM public.raw_chicago_crimes_load_audit
    ORDER BY load_id DESC
    LIMIT 1
),
completeness AS (
    SELECT
        count(*) FILTER (WHERE location_description IS NULL) AS null_location_description,
        count(*) FILTER (WHERE ward IS NULL) AS null_ward,
        count(*) FILTER (WHERE community_area IS NULL) AS null_community_area,
        count(*) FILTER (WHERE x_coordinate IS NULL) AS null_x_coordinate,
        count(*) FILTER (WHERE y_coordinate IS NULL) AS null_y_coordinate,
        count(*) FILTER (WHERE latitude IS NULL) AS null_latitude,
        count(*) FILTER (WHERE longitude IS NULL) AS null_longitude,
        count(*) FILTER (WHERE location IS NULL) AS null_location
    FROM public.raw_chicago_crimes
),
representative_ids AS (
    SELECT min(id) AS id FROM public.raw_chicago_crimes
    UNION
    SELECT min(id) AS id FROM public.raw_chicago_crimes WHERE latitude IS NULL OR longitude IS NULL
    UNION
    SELECT max(id) AS id FROM public.raw_chicago_crimes
),
representatives AS (
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', crimes.id,
            'case_number', crimes.case_number,
            'date', to_char(crimes.date, 'YYYY-MM-DD"T"HH24:MI:SS.MS'),
            'year', crimes.year,
            'community_area', crimes.community_area,
            'latitude', crimes.latitude,
            'longitude', crimes.longitude,
            'location', crimes.location
        ) ORDER BY crimes.id
    ) AS records
    FROM public.raw_chicago_crimes AS crimes
    JOIN representative_ids USING (id)
)
SELECT jsonb_build_object(
    'database', current_database(),
    'database_user', current_user,
    'postgresql_version', current_setting('server_version'),
    'load_id', audit.load_id,
    'loaded_at_utc', to_char(
        audit.loaded_at_utc AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS"Z"'
    ),
    'source_file_name', audit.source_file_name,
    'source_sha256', audit.source_sha256,
    'expected_row_count', audit.expected_row_count,
    'staging_row_count', audit.staging_row_count,
    'imported_row_count', audit.imported_row_count,
    'distinct_source_id_count', audit.distinct_source_id_count,
    'min_incident_date', to_char(audit.min_incident_date, 'YYYY-MM-DD"T"HH24:MI:SS.MS'),
    'max_incident_date', to_char(audit.max_incident_date, 'YYYY-MM-DD"T"HH24:MI:SS.MS'),
    'records_by_year', audit.records_by_year,
    'important_column_completeness', to_jsonb(completeness),
    'representative_records', representatives.records
)
FROM latest_audit AS audit
CROSS JOIN completeness
CROSS JOIN representatives;
"""


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Transactionally rebuild and validate raw Chicago crime tables in PostgreSQL."
    )
    parser.add_argument("--database", help="Database name; defaults to PGDATABASE, POSTGRES_DB, or chicago_crime.")
    parser.add_argument("--raw-file", default=DEFAULT_RAW_FILE)
    parser.add_argument("--manifest", default=DEFAULT_MANIFEST)
    parser.add_argument("--schema-file", default=DEFAULT_SCHEMA)
    parser.add_argument("--validation-output", default=DEFAULT_VALIDATION_OUTPUT)
    return parser


def main() -> int:
    if shutil.which("psql") is None:
        raise SystemExit("psql is required but was not found on PATH")

    project_root = Path(__file__).resolve().parents[1]
    load_optional_dotenv(project_root)
    args = build_parser().parse_args()
    environment = psql_environment()
    database = (
        args.database
        or environment.get("PGDATABASE")
        or environment.get("POSTGRES_DB")
        or "chicago_crime"
    )

    raw_file = resolve_project_path(project_root, args.raw_file)
    manifest_path = resolve_project_path(project_root, args.manifest)
    schema_file = resolve_project_path(project_root, args.schema_file)
    validation_output = resolve_project_path(project_root, args.validation_output)
    for required in (raw_file, manifest_path, schema_file):
        if not required.is_file():
            raise SystemExit(f"Required file not found: {required}")

    manifest: Dict[str, Any] = json.loads(manifest_path.read_text(encoding="utf-8"))
    expected_count = int(manifest["download_validation"]["row_count"])
    expected_sha256 = manifest["download_validation"]["sha256"]
    actual_sha256 = sha256_file(raw_file)
    if actual_sha256 != expected_sha256:
        raise SystemExit(
            f"Raw CSV SHA-256 mismatch: expected {expected_sha256}, found {actual_sha256}"
        )

    with raw_file.open(encoding="utf-8", newline="") as source:
        header = next(csv.reader(source))
    if header != SOURCE_FIELDS:
        raise SystemExit(f"Raw CSV header mismatch: expected {SOURCE_FIELDS!r}, found {header!r}")

    database_workflow_started = time.monotonic()
    print(f"Applying schema to database {database!r}...", file=sys.stderr)
    run_psql(database, environment, file_path=schema_file)

    print(
        f"Rebuilding raw tables from {raw_file.name} ({expected_count:,} expected rows)...",
        file=sys.stderr,
    )
    run_psql(
        database,
        environment,
        sql=load_sql(raw_file, expected_count, expected_sha256),
    )

    raw_validation = run_psql(
        database,
        environment,
        sql=validation_query(),
        tuples_only=True,
    )
    try:
        validation = json.loads(raw_validation)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Could not parse validation JSON returned by PostgreSQL: {raw_validation}") from exc

    if validation["expected_row_count"] != expected_count:
        raise RuntimeError("Database audit expected count does not match acquisition manifest")
    for key in ("staging_row_count", "imported_row_count", "distinct_source_id_count"):
        if validation[key] != expected_count:
            raise RuntimeError(f"Database validation mismatch for {key}: {validation[key]}")
    if validation["source_sha256"] != expected_sha256:
        raise RuntimeError("Database audit SHA-256 does not match acquisition manifest")

    validation["database_workflow_duration_seconds"] = round(
        time.monotonic() - database_workflow_started,
        3,
    )
    validation["validation_generated_at_utc"] = datetime.now(timezone.utc).replace(
        microsecond=0
    ).isoformat()
    validation["raw_file_path_relative_to_project"] = str(raw_file.relative_to(project_root))
    validation["manifest_path_relative_to_project"] = str(manifest_path.relative_to(project_root))

    validation_output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        prefix=f".{validation_output.name}.",
        suffix=".part",
        dir=validation_output.parent,
        delete=False,
    ) as temporary:
        json.dump(validation, temporary, indent=2, sort_keys=True)
        temporary.write("\n")
        temporary_path = Path(temporary.name)
    temporary_path.replace(validation_output)

    print(json.dumps(validation, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
