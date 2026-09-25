#!/usr/bin/env python3
"""Download an immutable, validated slice of the Chicago crimes dataset.

The script uses keyset pagination on the source ``id`` field, preserves the
CSV values returned by Socrata, and writes a JSON sidecar with extraction and
validation evidence. It refuses to overwrite an existing raw file.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
import sys
import tempfile
import time
from collections import Counter
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

import requests


DOMAIN = "https://data.cityofchicago.org"
DEFAULT_DATASET_ID = "ijzp-q8t2"
DEFAULT_START_DATE = "2023-01-01"
DEFAULT_END_DATE_EXCLUSIVE = "2026-01-01"
DEFAULT_PAGE_SIZE = 50_000
RETRYABLE_STATUS_CODES = {429, 500, 502, 503, 504}


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def epoch_to_utc(value: Optional[int]) -> Optional[str]:
    if value is None:
        return None
    return datetime.fromtimestamp(value, timezone.utc).replace(microsecond=0).isoformat()


def validate_iso_date(value: str) -> str:
    try:
        date.fromisoformat(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"Invalid ISO date {value!r}; expected YYYY-MM-DD") from exc
    return value


def load_optional_dotenv(project_root: Path) -> None:
    """Load .env when python-dotenv is installed; public defaults need no .env."""
    try:
        from dotenv import load_dotenv
    except ImportError:
        return
    load_dotenv(project_root / ".env")


class SocrataClient:
    def __init__(
        self,
        app_token: Optional[str],
        timeout_seconds: int,
        max_retries: int,
    ) -> None:
        self.timeout_seconds = timeout_seconds
        self.max_retries = max_retries
        self.session = requests.Session()
        self.session.headers.update(
            {
                "Accept-Encoding": "gzip",
                "User-Agent": "chicago-crime-analytics/1.0 (portfolio data acquisition)",
            }
        )
        if app_token:
            self.session.headers["X-App-Token"] = app_token

    def get(self, url: str, params: Optional[Dict[str, str]] = None) -> requests.Response:
        last_error: Optional[BaseException] = None
        for attempt in range(self.max_retries + 1):
            try:
                response = self.session.get(url, params=params, timeout=self.timeout_seconds)
                if response.status_code not in RETRYABLE_STATUS_CODES:
                    if response.status_code >= 400:
                        excerpt = response.text[:500].replace("\n", " ")
                        raise RuntimeError(
                            f"Socrata request failed with HTTP {response.status_code}: {excerpt}"
                        )
                    return response

                last_error = RuntimeError(f"retryable HTTP {response.status_code}")
                retry_after = response.headers.get("Retry-After")
                delay = float(retry_after) if retry_after and retry_after.isdigit() else min(2**attempt, 30)
            except (requests.Timeout, requests.ConnectionError) as exc:
                last_error = exc
                delay = min(2**attempt, 30)

            if attempt == self.max_retries:
                break
            print(
                f"Request attempt {attempt + 1} failed; retrying in {delay:.0f} seconds...",
                file=sys.stderr,
            )
            time.sleep(delay)

        raise RuntimeError(
            f"Socrata request failed after {self.max_retries + 1} attempts"
        ) from last_error

    def get_json(self, url: str, params: Optional[Dict[str, str]] = None) -> Any:
        response = self.get(url, params=params)
        try:
            return response.json()
        except requests.JSONDecodeError as exc:
            raise RuntimeError(f"Expected JSON from {response.url}") from exc


def date_filter(start_date: str, end_date_exclusive: str) -> str:
    return (
        f"date >= '{start_date}T00:00:00.000' "
        f"AND date < '{end_date_exclusive}T00:00:00.000'"
    )


def source_summary(
    client: SocrataClient,
    json_url: str,
    where: str,
) -> Dict[str, Any]:
    overall_rows = client.get_json(
        json_url,
        params={
            "$select": (
                "count(*) as record_count,"
                "count(distinct id) as distinct_id_count,"
                "min(date) as min_date,max(date) as max_date"
            ),
            "$where": where,
        },
    )
    if len(overall_rows) != 1:
        raise RuntimeError(f"Expected one source-summary row, received {len(overall_rows)}")

    yearly_rows = client.get_json(
        json_url,
        params={
            "$select": "year,count(*) as record_count",
            "$where": where,
            "$group": "year",
            "$order": "year",
        },
    )
    return {
        "record_count": int(overall_rows[0]["record_count"]),
        "distinct_id_count": int(overall_rows[0]["distinct_id_count"]),
        "min_date": overall_rows[0].get("min_date"),
        "max_date": overall_rows[0].get("max_date"),
        "year_counts": {
            row.get("year", "<missing>"): int(row["record_count"]) for row in yearly_rows
        },
    }


def schema_from_metadata(metadata: Dict[str, Any]) -> Tuple[List[Dict[str, Any]], List[str]]:
    schema: List[Dict[str, Any]] = []
    exported_fields: List[str] = []
    for column in sorted(metadata["columns"], key=lambda item: item["position"]):
        field_name = column["fieldName"]
        is_computed = field_name.startswith(":@computed_region_")
        schema.append(
            {
                "position": column["position"],
                "name": column["name"],
                "field_name": field_name,
                "socrata_type": column["dataTypeName"],
                "description": column.get("description"),
                "is_computed_region": is_computed,
            }
        )
        if not is_computed:
            exported_fields.append(field_name)
    return schema, exported_fields


def remove_csv_header(content: bytes) -> bytes:
    _, separator, remainder = content.partition(b"\n")
    if not separator:
        raise RuntimeError("CSV response did not contain a header line terminator")
    return remainder


def parse_page(
    content: bytes,
    expected_fields: Sequence[str],
) -> Tuple[List[Dict[str, str]], List[str]]:
    text = content.decode("utf-8-sig")
    reader = csv.DictReader(io.StringIO(text, newline=""))
    fieldnames = list(reader.fieldnames or [])
    if fieldnames != list(expected_fields):
        raise RuntimeError(
            "CSV schema changed during extraction. "
            f"Expected {list(expected_fields)!r}, received {fieldnames!r}."
        )
    return list(reader), fieldnames


def acquire(
    client: SocrataClient,
    csv_url: str,
    where: str,
    exported_fields: Sequence[str],
    expected_count: int,
    page_size: int,
    destination: Path,
) -> Dict[str, Any]:
    null_counts: Counter[str] = Counter()
    year_counts: Counter[str] = Counter()
    seen_ids: set[int] = set()
    duplicate_ids = 0
    coordinate_pair_present = 0
    coordinate_pair_missing_or_incomplete = 0
    community_area_present = 0
    row_count = 0
    page_count = 0
    last_id: Optional[int] = None
    observed_min_date: Optional[str] = None
    observed_max_date: Optional[str] = None
    hasher = hashlib.sha256()

    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = tempfile.NamedTemporaryFile(
        mode="wb",
        prefix=f".{destination.name}.",
        suffix=".part",
        dir=destination.parent,
        delete=False,
    )
    temporary_path = Path(temporary.name)

    try:
        with temporary:
            while True:
                page_where = where
                if last_id is not None:
                    page_where = f"({where}) AND id > {last_id}"
                response = client.get(
                    csv_url,
                    params={
                        "$select": ",".join(exported_fields),
                        "$where": page_where,
                        "$order": "id ASC",
                        "$limit": str(page_size),
                    },
                )
                rows, _ = parse_page(response.content, exported_fields)
                if not rows:
                    break

                prior_id = last_id
                for row in rows:
                    raw_id = row.get("id", "")
                    if not raw_id:
                        raise RuntimeError("Encountered a source row with a missing id")
                    try:
                        row_id = int(raw_id)
                    except ValueError as exc:
                        raise RuntimeError(f"Encountered a non-integer source id: {raw_id!r}") from exc
                    if prior_id is not None and row_id <= prior_id:
                        raise RuntimeError(
                            f"Source ordering is not strictly increasing: {row_id} after {prior_id}"
                        )
                    prior_id = row_id

                    if row_id in seen_ids:
                        duplicate_ids += 1
                    seen_ids.add(row_id)

                    for field in exported_fields:
                        if row.get(field, "") == "":
                            null_counts[field] += 1

                    raw_year = row.get("year", "") or "<missing>"
                    year_counts[raw_year] += 1
                    raw_date = row.get("date", "")
                    if raw_date:
                        observed_min_date = (
                            raw_date if observed_min_date is None else min(observed_min_date, raw_date)
                        )
                        observed_max_date = (
                            raw_date if observed_max_date is None else max(observed_max_date, raw_date)
                        )

                    if row.get("latitude", "") != "" and row.get("longitude", "") != "":
                        coordinate_pair_present += 1
                    else:
                        coordinate_pair_missing_or_incomplete += 1
                    if row.get("community_area", "") != "":
                        community_area_present += 1

                content_to_write = response.content if page_count == 0 else remove_csv_header(response.content)
                temporary.write(content_to_write)
                hasher.update(content_to_write)

                page_count += 1
                row_count += len(rows)
                last_id = int(rows[-1]["id"])
                print(
                    f"Downloaded page {page_count}: {len(rows):,} rows "
                    f"({row_count:,}/{expected_count:,})",
                    file=sys.stderr,
                )

                if len(rows) < page_size:
                    break
                if row_count > expected_count:
                    raise RuntimeError(
                        f"Downloaded count {row_count:,} exceeded pre-download source count "
                        f"{expected_count:,}; the source may have changed during extraction"
                    )

        if row_count != expected_count:
            raise RuntimeError(
                f"Downloaded {row_count:,} rows but the pre-download source count was "
                f"{expected_count:,}"
            )
        if duplicate_ids:
            raise RuntimeError(f"Downloaded data contains {duplicate_ids:,} duplicate source IDs")
        if len(seen_ids) != row_count:
            raise RuntimeError(
                f"Unique-ID count {len(seen_ids):,} does not match row count {row_count:,}"
            )

        file_size_bytes = temporary_path.stat().st_size
        temporary_path.replace(destination)
        return {
            "row_count": row_count,
            "unique_id_count": len(seen_ids),
            "duplicate_id_count": duplicate_ids,
            "page_count": page_count,
            "page_size": page_size,
            "first_id": min(seen_ids) if seen_ids else None,
            "last_id": max(seen_ids) if seen_ids else None,
            "observed_min_date": observed_min_date,
            "observed_max_date": observed_max_date,
            "year_counts": dict(sorted(year_counts.items())),
            "null_counts_by_field": {field: null_counts[field] for field in exported_fields},
            "coordinate_pair_present_count": coordinate_pair_present,
            "coordinate_pair_missing_or_incomplete_count": coordinate_pair_missing_or_incomplete,
            "community_area_present_count": community_area_present,
            "sha256": hasher.hexdigest(),
            "file_size_bytes": file_size_bytes,
        }
    except BaseException:
        temporary.close()
        temporary_path.unlink(missing_ok=True)
        raise


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Download and validate complete-year Chicago crime records from Socrata."
    )
    parser.add_argument(
        "--dataset-id",
        default=os.getenv("CHICAGO_CRIME_DATASET_ID", DEFAULT_DATASET_ID),
    )
    parser.add_argument("--start-date", type=validate_iso_date, default=DEFAULT_START_DATE)
    parser.add_argument(
        "--end-date-exclusive",
        type=validate_iso_date,
        default=DEFAULT_END_DATE_EXCLUSIVE,
    )
    parser.add_argument("--page-size", type=int, default=DEFAULT_PAGE_SIZE)
    parser.add_argument("--timeout-seconds", type=int, default=120)
    parser.add_argument("--max-retries", type=int, default=5)
    parser.add_argument(
        "--output-dir",
        default=os.getenv("RAW_DATA_DIR", "data/raw"),
        help="Repository-relative or absolute raw-data directory.",
    )
    return parser


def main() -> int:
    project_root = Path(__file__).resolve().parents[1]
    load_optional_dotenv(project_root)
    args = build_parser().parse_args()

    start = date.fromisoformat(args.start_date)
    end_exclusive = date.fromisoformat(args.end_date_exclusive)
    if start >= end_exclusive:
        raise SystemExit("--start-date must be earlier than --end-date-exclusive")
    if args.page_size < 1 or args.page_size > 50_000:
        raise SystemExit("--page-size must be between 1 and 50000")
    if args.max_retries < 0:
        raise SystemExit("--max-retries cannot be negative")

    output_dir = Path(args.output_dir)
    if not output_dir.is_absolute():
        output_dir = project_root / output_dir
    inclusive_end = date.fromordinal(end_exclusive.toordinal() - 1)
    stem = f"chicago_crimes_{start.isoformat()}_{inclusive_end.isoformat()}"
    destination = output_dir / f"{stem}.csv"
    manifest_path = output_dir / f"{stem}.metadata.json"
    if destination.exists() or manifest_path.exists():
        raise SystemExit(
            "Refusing to overwrite immutable raw artifacts. Move or verify the existing files first: "
            f"{destination}, {manifest_path}"
        )

    app_token = os.getenv("SOCRATA_APP_TOKEN") or None
    client = SocrataClient(app_token, args.timeout_seconds, args.max_retries)
    metadata_url = f"{DOMAIN}/api/views/{args.dataset_id}"
    json_url = f"{DOMAIN}/resource/{args.dataset_id}.json"
    csv_url = f"{DOMAIN}/resource/{args.dataset_id}.csv"
    portal_url = (
        f"{DOMAIN}/Public-Safety/Crimes-2001-to-Present/{args.dataset_id}/data"
    )
    where = date_filter(args.start_date, args.end_date_exclusive)

    extraction_started_at = utc_now()
    metadata_before = client.get_json(metadata_url)
    if metadata_before.get("id") != args.dataset_id:
        raise RuntimeError(
            f"Metadata dataset ID {metadata_before.get('id')!r} did not match {args.dataset_id!r}"
        )
    schema, exported_fields = schema_from_metadata(metadata_before)
    if "id" not in exported_fields or "date" not in exported_fields:
        raise RuntimeError("Required source fields id and date were not present in metadata")

    source_before = source_summary(client, json_url, where)
    if source_before["record_count"] != source_before["distinct_id_count"]:
        raise RuntimeError(
            "Source count and distinct source-ID count differ before download: "
            f"{source_before['record_count']:,} vs {source_before['distinct_id_count']:,}"
        )

    print(
        f"Official source count before download: {source_before['record_count']:,}",
        file=sys.stderr,
    )
    download = acquire(
        client=client,
        csv_url=csv_url,
        where=where,
        exported_fields=exported_fields,
        expected_count=source_before["record_count"],
        page_size=args.page_size,
        destination=destination,
    )

    source_after = source_summary(client, json_url, where)
    if source_after != source_before:
        destination.unlink(missing_ok=True)
        raise RuntimeError(
            "Source summary changed during extraction; downloaded file was removed. "
            f"Before={source_before!r}; after={source_after!r}"
        )

    metadata_after = client.get_json(metadata_url)
    extraction_completed_at = utc_now()
    manifest = {
        "dataset": {
            "name": metadata_before.get("name"),
            "id": args.dataset_id,
            "provider": metadata_before.get("attribution"),
            "portal_url": portal_url,
            "metadata_url": metadata_url,
            "api_csv_url": csv_url,
            "api_json_url": json_url,
            "source_rows_updated_at_before_utc": epoch_to_utc(metadata_before.get("rowsUpdatedAt")),
            "source_rows_updated_at_after_utc": epoch_to_utc(metadata_after.get("rowsUpdatedAt")),
            "metadata_last_modified_at_utc": epoch_to_utc(metadata_before.get("viewLastModified")),
        },
        "extraction": {
            "started_at_utc": extraction_started_at,
            "completed_at_utc": extraction_completed_at,
            "start_date_inclusive": args.start_date,
            "end_date_exclusive": args.end_date_exclusive,
            "source_where_filter": where,
            "order": "id ASC",
            "pagination": "keyset pagination using id > last downloaded id",
            "page_size": args.page_size,
            "app_token_used": bool(app_token),
        },
        "source_schema": {
            "metadata_column_count": len(schema),
            "exported_column_count": len(exported_fields),
            "exported_fields": exported_fields,
            "columns": schema,
        },
        "source_validation_before_download": source_before,
        "source_validation_after_download": source_after,
        "download_validation": download,
        "raw_file": {
            "path_relative_to_project": str(destination.relative_to(project_root)),
            "metadata_path_relative_to_project": str(manifest_path.relative_to(project_root)),
        },
        "limitations": [
            "The source is updated daily and historical records can be revised after extraction.",
            "Records describe reported crime and do not measure unreported crime.",
            "Murder records are victim-based according to the source description.",
            "Incident dates can be estimates, addresses are block-level, and mapped locations are approximate.",
            "Missing coordinates do not make a record ineligible for non-geographic analysis.",
        ],
    }

    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        prefix=f".{manifest_path.name}.",
        suffix=".part",
        dir=manifest_path.parent,
        delete=False,
    ) as temporary_manifest:
        json.dump(manifest, temporary_manifest, indent=2, sort_keys=True)
        temporary_manifest.write("\n")
        temporary_manifest_path = Path(temporary_manifest.name)
    temporary_manifest_path.replace(manifest_path)

    print(json.dumps({"raw_file": str(destination), "manifest": str(manifest_path), **download}, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("Download interrupted.", file=sys.stderr)
        raise SystemExit(130)
