#!/usr/bin/env python3
"""Export validated Tableau presentation views to deterministic local CSV files."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import URL, create_engine, text


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT_DIR = PROJECT_ROOT / "data" / "processed" / "tableau"

EXPORTS = {
    "vw_tableau_executive_year": "crime_year",
    "vw_tableau_community_area_year": "crime_year, community_area",
    "vw_tableau_district_year": "crime_year, district",
    "vw_tableau_area_category_year": "crime_year, community_area, primary_type",
    "vw_tableau_monthly_patterns": "month_start",
    "vw_tableau_time_patterns": "crime_year, day_of_week_num, hour_of_day",
    "vw_tableau_location_time": "full_period_location_rank, time_of_day_order",
    "vw_tableau_crime_arrest_year": "crime_year, primary_type",
    "vw_tableau_coordinate_density": "crime_year, cell_latitude, cell_longitude",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export the validated Tableau views as Git-ignored CSV extracts."
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help="Output directory (default: data/processed/tableau).",
    )
    return parser.parse_args()


def build_read_only_engine():
    load_dotenv(PROJECT_ROOT / ".env", override=False)
    host = os.getenv("POSTGRES_HOST") or None
    user = os.getenv("POSTGRES_USER") or None
    password = os.getenv("POSTGRES_PASSWORD") or None
    database = os.getenv("POSTGRES_DB", "chicago_crime")
    port = int(os.getenv("POSTGRES_PORT", "5432")) if host else None
    url = URL.create(
        "postgresql+psycopg",
        username=user,
        password=password,
        host=host,
        port=port,
        database=database,
    )
    connect_args = {"options": "-c default_transaction_read_only=on"}
    sslmode = os.getenv("POSTGRES_SSLMODE")
    if host and sslmode:
        connect_args["sslmode"] = sslmode
    return create_engine(url, future=True, connect_args=connect_args), database


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def resolve_output_dir(requested: Path) -> Path:
    output_dir = requested if requested.is_absolute() else PROJECT_ROOT / requested
    output_dir = output_dir.resolve()
    processed_root = (PROJECT_ROOT / "data" / "processed").resolve()
    if output_dir != processed_root and processed_root not in output_dir.parents:
        raise ValueError("Output directory must be inside data/processed.")
    return output_dir


def main() -> None:
    args = parse_args()
    output_dir = resolve_output_dir(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    engine, database = build_read_only_engine()

    manifest = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "database": database,
        "source_dataset_id": "ijzp-q8t2",
        "source_extraction_date": "2026-09-25",
        "coverage": {"start": "2023-01-01", "end": "2025-12-31"},
        "exports": [],
    }

    with engine.connect() as connection:
        transaction_mode = connection.execute(
            text("SELECT current_setting('transaction_read_only')")
        ).scalar_one()
        if transaction_mode != "on":
            raise RuntimeError("Database connection is not read-only.")

        available_views = {
            row[0]
            for row in connection.execute(
                text(
                    """
                    SELECT table_name
                    FROM information_schema.views
                    WHERE table_schema = 'public'
                    """
                )
            )
        }
        missing = set(EXPORTS) - available_views
        if missing:
            raise RuntimeError(
                "Missing Tableau views; run sql/06_tableau_preparation.sql first: "
                + ", ".join(sorted(missing))
            )

        for view_name, order_by in EXPORTS.items():
            query = text(f"SELECT * FROM public.{view_name} ORDER BY {order_by}")
            frame = pd.read_sql_query(query, connection)
            destination = output_dir / f"{view_name}.csv"
            temporary = destination.with_suffix(".csv.tmp")
            frame.to_csv(temporary, index=False, lineterminator="\n")
            temporary.replace(destination)

            database_count = connection.execute(
                text(f"SELECT COUNT(*) FROM public.{view_name}")
            ).scalar_one()
            csv_count = len(pd.read_csv(destination))
            if len(frame) != database_count or csv_count != database_count:
                raise RuntimeError(f"Row-count reconciliation failed for {view_name}.")

            artifact = {
                "view": f"public.{view_name}",
                "file": destination.relative_to(PROJECT_ROOT).as_posix(),
                "rows": int(database_count),
                "columns": int(len(frame.columns)),
                "bytes": destination.stat().st_size,
                "sha256": sha256(destination),
                "order_by": order_by,
            }
            manifest["exports"].append(artifact)
            print(
                f"Exported {artifact['view']}: {artifact['rows']:,} rows, "
                f"{artifact['columns']} columns"
            )

    manifest_path = output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {manifest_path.relative_to(PROJECT_ROOT)}")
    print("All exports reconciled to their PostgreSQL view row counts.")


if __name__ == "__main__":
    main()
