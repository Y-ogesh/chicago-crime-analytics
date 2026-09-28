# Tableau Page 2 Build and Validation Guide

## Status

Milestone 9C is **Complete**. Geographic Crime Patterns Page 2 was generated programmatically, opened in Tableau Desktop Free Edition 2026.2.3 on Apple silicon, rendered successfully, and tested with the required filters. Executive Overview Page 1 remained intact. Pages 3–4 are not implemented.

## Reproducible build

From the repository root, with the documented PostgreSQL environment configured:

```bash
psql -d "${PGDATABASE:-chicago_crime}" -X -v ON_ERROR_STOP=1 -P pager=off \
  -f sql/08_tableau_geographic_page.sql
psql -d "${PGDATABASE:-chicago_crime}" -X -v ON_ERROR_STOP=1 -P pager=off \
  -f sql/09_tableau_page2_validation.sql
python scripts/export_tableau_data.py --profile page2
python scripts/generate_tableau_workbook.py
```

The generated files are:

- `data/processed/tableau/page2/vw_tableau_geographic_detail.csv` — Git-ignored Tableau source.
- `data/processed/tableau/page2/manifest.json` — Git-ignored row, column, size, ordering, and checksum evidence.
- `tableau/chicago_crime_analytics.twb` — version-controlled workbook containing Pages 1–2.

## Geographic source and grain

`vw_tableau_geographic_detail` contains 50,037 aggregate rows at year × source primary type × community area × district × coordinate-eligibility × 0.01-degree coordinate-cell grain. Every clean incident contributes to exactly one row. No Page 2 source is joined, related, unioned, or blended with another source, preventing cross-grain measure multiplication.

Valid source coordinates are floored to 0.01-degree cells; the exported latitude and longitude are the deterministic cell centers. These cells summarize observed coordinates descriptively. They are not official boundaries, population-normalized rates, individual-risk measures, or statistically significant hotspots. Records without valid coordinates retain null cell coordinates and remain in KPI and ranking totals, but the map filters them out.

## Implemented worksheets

1. `Geographic Selected Incidents` — selected-scope reported-incident count.
2. `Geographic Coverage Percentage` — selected-scope coordinate-mappable percentage.
3. `Chicago Geographic Crime Map` — descriptive 0.01-degree coordinate-cell map.
4. `Community Area Ranking` — eligible official community areas ranked by reported incidents.
5. `District Comparison` — observed district labels ranked by reported incidents.
6. `Geographic Crime Category Analysis` — source primary types ranked within the selected geography.

The `Geographic Crime Patterns` dashboard uses a fixed 1,360 × 850 layout and controls for Year, Crime Type, Community Area, and Police District. All six worksheets use the same source and the same parameter calculations, so every control has consistent scope.

## Validation evidence

The SQL validation completed with `ON_ERROR_STOP=1` and passed:

- 50,037 view rows with zero duplicate rows at the declared analytical grain.
- 761,563 represented clean incidents.
- 760,496 community-area-eligible incidents across all 77 official areas.
- 754,866 coordinate-mappable incidents; 6,697 retained but excluded from the map.
- Zero invalid non-null coordinate-cell combinations.
- Exact reconciliation to the existing clean, community-area, district, and area/category analytical totals.

The workbook generator validated well-formed XML, three relative CSV references, 12 worksheets, two dashboards, four Page 2 parameter controls, map latitude/longitude shelves, source row counts, and benchmark totals.

Tableau Desktop rendered and filtered the workbook without a workbook error:

| Tableau state | Reported incidents | Mappable incidents | Coordinate coverage |
|---|---:|---:|---:|
| 2025 / All Crime Types | 238,086 | 236,099 | 99.1654% (99.2% displayed) |
| 2025 / THEFT | 55,198 | 54,849 | 99.3677% (99.4% displayed) |
| 2025 / THEFT / Austin | 1,967 | 1,954 | 99.3391% (99.3% displayed) |
| 2025 / THEFT / District 008 | 3,112 | 3,087 | 99.1967% (99.2% displayed) |

Community-area and district controls narrowed the map and all rankings to the selected scope. The Austin and District 008 displayed totals matched direct read-only PostgreSQL queries. The final screenshots are:

- `images/tableau/geographic_crime_patterns_2025_all.png`
- `images/tableau/geographic_crime_patterns_2025_theft.png`

## Open the workbook

No additional manual work is required to complete Milestone 9C. To inspect the result:

1. Confirm the Page 1 and Page 2 CSV exports exist under `data/processed/tableau/`.
2. Open `tableau/chicago_crime_analytics.twb` in Tableau Desktop 2026.2.3 or a compatible version.
3. Choose **Window → Geographic Crime Patterns** if Page 1 opens first.
4. Use the four controls in the upper-right corner. The default state is Year 2025 with all crime types, community areas, and police districts.

## Limitations

- Reported incidents do not measure all crime and can be revised after extraction.
- Counts are not population- or exposure-normalized rates.
- Coordinates are approximate, missing for 6,697 records, and summarized in resolution-dependent cells.
- The community-area and district dimensions come from incident records; the map does not display official area or district polygons.
- No formal spatial cluster or hotspot-significance test was performed.
- The dashboard is descriptive and does not establish causation or individual risk.
