# Dataset Acquisition

## Acquisition summary

Milestone 1 acquired an immutable raw extract from the official City of Chicago **Crimes - 2001 to Present** dataset. No source value was cleaned, recoded, imputed, or otherwise transformed during acquisition.

| Item | Verified value |
|---|---|
| Dataset provider | Chicago Police Department via the City of Chicago Data Portal |
| Dataset ID | `ijzp-q8t2` |
| Official portal URL | [Crimes - 2001 to Present](https://data.cityofchicago.org/Public-Safety/Crimes-2001-to-Present/ijzp-q8t2/data) |
| Metadata URL | `https://data.cityofchicago.org/api/views/ijzp-q8t2` |
| CSV API URL | `https://data.cityofchicago.org/resource/ijzp-q8t2.csv` |
| Extraction date | September 25, 2026 |
| Extraction window (UTC) | `2026-09-25T18:35:06+00:00` to `2026-09-25T18:38:28+00:00` |
| Selected incident period | January 1, 2023 through December 31, 2025 |
| Source rows last updated (UTC) | `2026-09-25T10:55:18+00:00` before and after extraction |
| Metadata last modified (UTC) | `2026-09-08T18:32:36+00:00` |

## Period selection

The selected period contains three adjacent, recent, complete calendar years: 2023, 2024, and 2025. It provides more than 500,000 reported-incident records while preserving valid adjacent-year comparisons. The open 2026 calendar year was intentionally excluded from full-year scope.

The exact half-open Socrata filter was:

```text
date >= '2023-01-01T00:00:00.000' AND date < '2026-01-01T00:00:00.000'
```

Using an inclusive lower bound and exclusive upper bound prevents overlap or ambiguity at year boundaries. Source rows were ordered by `id ASC`.

## Reproducible acquisition

From the repository root:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python scripts/download_crimes.py
```

An optional Socrata application token can be supplied without committing it:

```bash
SOCRATA_APP_TOKEN="your-token" python scripts/download_crimes.py
```

The executed acquisition used the public API without an application token:

```bash
python3 scripts/download_crimes.py
```

The script:

- retrieves and records official metadata before acquisition;
- queries the official source count, distinct-ID count, date range, and yearly counts;
- requests at most 50,000 rows per page;
- uses keyset pagination with `id > last downloaded id` rather than assuming one request is complete;
- requests explicit current core fields and orders every page by `id ASC`;
- retries timeouts, connection failures, HTTP 429, and retryable server errors;
- verifies strictly increasing IDs and rejects duplicate or missing IDs;
- requires the downloaded count to match both pre-download and post-download source counts;
- assembles the source CSV pages without altering field values;
- writes through temporary files and refuses to overwrite existing raw artifacts; and
- records a SHA-256 checksum, file size, schema, empty-field counts, and geographic-field presence in a JSON sidecar.

Default output files are:

```text
data/raw/chicago_crimes_2023-01-01_2025-12-31.csv
data/raw/chicago_crimes_2023-01-01_2025-12-31.metadata.json
```

Both files are intentionally excluded from Git. The JSON sidecar is the local machine-readable evidence record for the immutable CSV.

## Record-count and integrity validation

| Check | Result |
|---|---:|
| Official source count before download | 761,563 |
| Official distinct source IDs before download | 761,563 |
| Downloaded CSV rows | 761,563 |
| Downloaded unique IDs | 761,563 |
| Duplicate downloaded IDs | 0 |
| Official source count after download | 761,563 |
| API pages | 16 |
| Raw CSV size | 219,747,521 bytes (209.57 MiB) |
| SHA-256 | `8b74425af7936af7b88226664b1b1cafe6c8805fe95ff1ca6ac4d75d364c4757` |

An independent post-download scan reread all CSV records and reproduced the row count, unique-ID count, yearly counts, minimum and maximum timestamps, 22-field header, file size, and SHA-256 checksum.

### Calendar-year coverage

| Year | Reported source rows |
|---:|---:|
| 2023 | 263,844 |
| 2024 | 259,633 |
| 2025 | 238,086 |
| **Total** | **761,563** |

Observed incident timestamps range from `2023-01-01T00:00:00.000` through `2025-12-31T23:58:00.000`. These bounds support period coverage but do not prove that every incident was reported or that closed-year records will never be revised.

## Source schema

The official metadata contained 31 columns. The explicit CSV export preserved the 22 core published fields below; the remaining nine fields were portal-computed geographic metadata fields and are documented separately in the [data dictionary](data_dictionary.md).

| API field | Socrata type |
|---|---|
| `id` | `number` |
| `case_number` | `text` |
| `date` | `calendar_date` |
| `block` | `text` |
| `iucr` | `text` |
| `primary_type` | `text` |
| `description` | `text` |
| `location_description` | `text` |
| `arrest` | `checkbox` |
| `domestic` | `checkbox` |
| `beat` | `text` |
| `district` | `text` |
| `ward` | `number` |
| `community_area` | `text` |
| `fbi_code` | `text` |
| `x_coordinate` | `number` |
| `y_coordinate` | `number` |
| `year` | `number` |
| `updated_on` | `calendar_date` |
| `latitude` | `number` |
| `longitude` | `number` |
| `location` | `location` |

## Expected geographic fields and presence

The core source provides `x_coordinate`, `y_coordinate`, `latitude`, `longitude`, `location`, `community_area`, `ward`, `district`, and `beat`. The official metadata also lists nine computed-region fields, including portal-derived community areas, census tracts, wards, ZIP-code boundaries, police districts, and police beats; those computed fields were not included in the explicit 22-field raw export.

| Acquisition-level presence check | Records | Share of all rows |
|---|---:|---:|
| Both latitude and longitude present | 754,866 | 99.1206% |
| Latitude/longitude missing or incomplete | 6,697 | 0.8794% |
| Source `community_area` present | 761,528 | 99.9954% |
| Source `community_area` empty | 35 | 0.0046% |

These are raw presence checks, not validated geographic coverage metrics. No coordinate range, projection, boundary, or community-area domain validation was performed. Missing-coordinate records remain part of the raw dataset and remain eligible for applicable non-geographic analysis.

## Data limitations

- The dataset reflects reported incidents and cannot measure unreported crime.
- The source states that murder records are victim-based, unlike the general incident-row convention.
- Records can contain preliminary information, mechanical or human errors, revised classifications, and later historical updates.
- Incident dates can be estimates.
- Addresses are shown only at the block level for privacy.
- Coordinates and map displays are approximate and must not be used to infer exact addresses.
- Geographic presence does not establish coordinate validity or correct geographic assignment.
- Counts are not population-normalized crime rates.
- The extract supports descriptive analysis only and cannot establish causation.
- Source counts and checksums represent the September 25, 2026 extraction snapshot; a later reproducible run can differ if the official source revises historical records.

No database loading, cleaning, derived fields, crime-pattern analysis, or Tableau work was performed in this milestone.
