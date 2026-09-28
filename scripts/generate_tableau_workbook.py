#!/usr/bin/env python3
"""Generate and structurally validate the Chicago Crime Analytics Tableau workbook.

Each dashboard page uses independent sources at documented grains. Workbook parameters
apply equivalent filters without relationships, joins, blends, or cross-grain fan-out.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PAGE1_CSV_DIR = PROJECT_ROOT / "data" / "processed" / "tableau" / "page1"
DEFAULT_PAGE2_CSV_DIR = PROJECT_ROOT / "data" / "processed" / "tableau" / "page2"
DEFAULT_OUTPUT = PROJECT_ROOT / "tableau" / "chicago_crime_analytics.twb"
ANNUAL_FILE = "vw_tableau_crime_arrest_year.csv"
MONTHLY_FILE = "vw_tableau_month_category.csv"
GEOGRAPHIC_FILE = "vw_tableau_geographic_detail.csv"
TABLEAU_VERSION = "18.1"
TABLEAU_SOURCE_BUILD = "20262.26.0912.1023"

FIELD_CAPTIONS = {
    "reported_incident_count": "Reported Incidents",
    "cell_latitude": "Latitude",
    "cell_longitude": "Longitude",
}

FIELD_SEMANTIC_ROLES = {
    "cell_latitude": "[Geographical].[Latitude]",
    "cell_longitude": "[Geographical].[Longitude]",
}

ANNUAL_FIELDS = [
    ("crime_year", "integer"),
    ("period_start", "date"),
    ("primary_type", "string"),
    ("reported_incident_count", "integer"),
    ("yearly_reported_incident_count", "integer"),
    ("percentage_of_year_total", "real"),
    ("incident_volume_rank", "integer"),
    ("previous_year", "integer"),
    ("previous_year_incident_count", "integer"),
    ("absolute_change", "integer"),
    ("percentage_change", "real"),
    ("arrest_count", "integer"),
    ("arrest_indicator_denominator", "integer"),
    ("arrest_percentage", "real"),
    ("domestic_count", "integer"),
    ("domestic_indicator_denominator", "integer"),
    ("domestic_incident_percentage", "real"),
]

MONTHLY_FIELDS = [
    ("month_start", "date"),
    ("crime_year", "integer"),
    ("crime_month", "integer"),
    ("month_name", "string"),
    ("crime_quarter", "integer"),
    ("season", "string"),
    ("primary_type", "string"),
    ("reported_incident_count", "integer"),
    ("yearly_reported_incident_count", "integer"),
    ("percentage_of_yearly_total", "real"),
    ("yearly_category_incident_count", "integer"),
    ("percentage_of_category_year_total", "real"),
    ("trailing_three_month_average", "real"),
    ("same_month_previous_year_count", "integer"),
    ("same_month_absolute_change", "integer"),
    ("same_month_percentage_change", "real"),
    ("arrest_count", "integer"),
    ("arrest_indicator_denominator", "integer"),
    ("arrest_percentage", "real"),
    ("domestic_count", "integer"),
    ("domestic_indicator_denominator", "integer"),
    ("domestic_incident_percentage", "real"),
]

GEOGRAPHIC_FIELDS = [
    ("crime_year", "integer"),
    ("period_start", "date"),
    ("primary_type", "string"),
    ("community_area", "integer"),
    ("community_area_name", "string"),
    ("community_area_eligible_flag", "integer"),
    ("district", "string"),
    ("district_label", "string"),
    ("district_current_flag", "integer"),
    ("coordinate_mappable_flag", "integer"),
    ("cell_latitude", "real"),
    ("cell_longitude", "real"),
    ("density_cell_id", "string"),
    ("reported_incident_count", "integer"),
]

PAGE1_SHEETS = [
    "Total Reported Crimes",
    "Arrest Percentage",
    "Domestic Incident Percentage",
    "Yearly Crime Trend",
    "Crime Category Distribution",
    "Monthly Crime Trend",
]

PAGE2_SHEETS = [
    "Geographic Selected Incidents",
    "Geographic Coverage Percentage",
    "Chicago Geographic Crime Map",
    "Community Area Ranking",
    "District Comparison",
    "Geographic Crime Category Analysis",
]

SHEETS = PAGE1_SHEETS + PAGE2_SHEETS


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--page1-csv-dir", type=Path, default=DEFAULT_PAGE1_CSV_DIR)
    parser.add_argument("--page2-csv-dir", type=Path, default=DEFAULT_PAGE2_CSV_DIR)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="Validate an existing workbook and its referenced CSV files.",
    )
    return parser.parse_args()


def q(value: str) -> str:
    return f'"{value}"'


def add_format(parent: ET.Element, **attrs: str) -> ET.Element:
    return ET.SubElement(parent, "format", attrs)


def add_column(parent: ET.Element, name: str, datatype: str) -> ET.Element:
    if datatype in {"integer", "real"}:
        role, field_type = "measure", "quantitative"
    elif datatype == "date":
        role, field_type = "dimension", "ordinal"
    else:
        role, field_type = "dimension", "nominal"
    attrs = {"datatype": datatype, "name": f"[{name}]", "role": role, "type": field_type}
    if name in FIELD_CAPTIONS:
        attrs["caption"] = FIELD_CAPTIONS[name]
    if name in FIELD_SEMANTIC_ROLES:
        attrs["semantic-role"] = FIELD_SEMANTIC_ROLES[name]
        attrs["aggregation"] = "Avg"
    return ET.SubElement(parent, "column", attrs)


def add_textscan_datasource(
    parent: ET.Element,
    *,
    name: str,
    caption: str,
    filename: str,
    directory: str,
    fields: list[tuple[str, str]],
) -> None:
    ds = ET.SubElement(
        parent,
        "datasource",
        {"caption": caption, "inline": "true", "name": name, "version": TABLEAU_VERSION},
    )
    connection = ET.SubElement(ds, "connection", {"class": "federated"})
    named = ET.SubElement(ET.SubElement(connection, "named-connections"), "named-connection", {"caption": caption, "name": f"{name}Leaf"})
    ET.SubElement(
        named,
        "connection",
        {
            "character-set": "UTF-8",
            "class": "textscan",
            "directory": directory,
            "filename": filename,
            "force-character-set": "no",
            "force-header": "no",
            "force-separator": "no",
            "header": "yes",
            "password": "",
            "separator": ",",
            "server": "",
            "text-qualifier": '"',
        },
    )
    relation = ET.SubElement(
        connection,
        "relation",
        {"connection": f"{name}Leaf", "name": filename, "table": f"[{filename.replace('.', '#')}]", "type": "table"},
    )
    columns = ET.SubElement(
        relation,
        "columns",
        {"character-set": "UTF-8", "header": "yes", "locale": "en_US", "separator": ",", "text-qualifier": '"'},
    )
    for ordinal, (field_name, datatype) in enumerate(fields):
        ET.SubElement(columns, "column", {"datatype": datatype, "name": field_name, "ordinal": str(ordinal)})

    metadata = ET.SubElement(connection, "metadata-records")
    remote_type = {"integer": "20", "real": "5", "date": "7", "string": "129", "boolean": "11"}
    aggregation = {"integer": "Sum", "real": "Sum", "date": "Year", "string": "Count", "boolean": "Count"}
    for ordinal, (field_name, datatype) in enumerate(fields):
        record = ET.SubElement(metadata, "metadata-record", {"class": "column"})
        ET.SubElement(record, "remote-name").text = field_name
        ET.SubElement(record, "remote-type").text = remote_type[datatype]
        ET.SubElement(record, "local-name").text = f"[{field_name}]"
        ET.SubElement(record, "parent-name").text = f"[{filename.replace('.', '#')}]"
        ET.SubElement(record, "remote-alias").text = field_name
        ET.SubElement(record, "ordinal").text = str(ordinal)
        ET.SubElement(record, "local-type").text = datatype
        ET.SubElement(record, "aggregation").text = (
            "Avg" if field_name in FIELD_SEMANTIC_ROLES else aggregation[datatype]
        )
        ET.SubElement(record, "contains-null").text = "true"

    ET.SubElement(ds, "aliases", {"enabled": "yes"})
    for field_name, datatype in fields:
        add_column(ds, field_name, datatype)

    calculated = [
        (
            "Calculation_SelectedYear",
            "Selected Year Filter",
            "boolean",
            "STR([crime_year]) = [Parameters].[pSelectedYear]",
            None,
        ),
        (
            "Calculation_SelectedCrimeType",
            "Selected Crime Type Filter",
            "boolean",
            '[Parameters].[pCrimeType] = "All Crime Types" OR [primary_type] = [Parameters].[pCrimeType]',
            None,
        ),
    ]
    if name == "AnnualDS":
        calculated.extend(
            [
                (
                    "Calculation_CategoryDisplay",
                    "Show Category in Distribution",
                    "boolean",
                    '[Parameters].[pCrimeType] <> "All Crime Types" OR [incident_volume_rank] <= 10',
                    None,
                ),
                (
                    "Calculation_ArrestPercentage",
                    "Weighted Arrest Percentage",
                    "real",
                    "IF SUM([arrest_indicator_denominator]) = 0 THEN NULL ELSE 100.0 * SUM([arrest_count]) / SUM([arrest_indicator_denominator]) END",
                    'n#,##0.0"%";-#,##0.0"%"',
                ),
                (
                    "Calculation_DomesticPercentage",
                    "Weighted Domestic Incident Percentage",
                    "real",
                    "IF SUM([domestic_indicator_denominator]) = 0 THEN NULL ELSE 100.0 * SUM([domestic_count]) / SUM([domestic_indicator_denominator]) END",
                    'n#,##0.0"%";-#,##0.0"%"',
                ),
            ]
        )
    if name == "GeographicDS":
        calculated.extend(
            [
                (
                    "Calculation_SelectedCommunityArea",
                    "Selected Community Area Filter",
                    "boolean",
                    '[Parameters].[pCommunityArea] = "All Community Areas" OR [community_area_name] = [Parameters].[pCommunityArea]',
                    None,
                ),
                (
                    "Calculation_SelectedDistrict",
                    "Selected Police District Filter",
                    "boolean",
                    '[Parameters].[pDistrict] = "All Police Districts" OR [district_label] = [Parameters].[pDistrict]',
                    None,
                ),
                (
                    "Calculation_MapCoveragePercentage",
                    "Coordinate Coverage Percentage",
                    "real",
                    "IF SUM([reported_incident_count]) = 0 THEN NULL ELSE 100.0 * SUM(IF [coordinate_mappable_flag] = 1 THEN [reported_incident_count] ELSE 0 END) / SUM([reported_incident_count]) END",
                    'n#,##0.0"%";-#,##0.0"%"',
                ),
                (
                    "Calculation_MappableRecord",
                    "Coordinate-Mappable Record",
                    "boolean",
                    "[coordinate_mappable_flag] = 1",
                    None,
                ),
                (
                    "Calculation_CommunityAreaEligible",
                    "Community-Area Eligible Record",
                    "boolean",
                    "[community_area_eligible_flag] = 1",
                    None,
                ),
            ]
        )
    for calc_name, caption_value, datatype, formula, default_format in calculated:
        attrs = {
            "caption": caption_value,
            "datatype": datatype,
            "name": f"[{calc_name}]",
            "role": "dimension" if datatype == "boolean" else "measure",
            "type": "nominal" if datatype == "boolean" else "quantitative",
        }
        if default_format:
            attrs["default-format"] = default_format
        column = ET.SubElement(ds, "column", attrs)
        ET.SubElement(column, "calculation", {"class": "tableau", "formula": formula})


def add_parameters(
    parent: ET.Element,
    crime_types: list[str],
    community_areas: list[str],
    districts: list[str],
) -> None:
    ds = ET.SubElement(parent, "datasource", {"hasconnection": "false", "inline": "true", "name": "Parameters", "version": TABLEAU_VERSION})
    ET.SubElement(ds, "aliases", {"enabled": "yes"})
    year = ET.SubElement(
        ds,
        "column",
        {"caption": "Year", "datatype": "string", "name": "[pSelectedYear]", "param-domain-type": "list", "role": "measure", "type": "nominal", "value": q("2025")},
    )
    ET.SubElement(year, "calculation", {"class": "tableau", "formula": q("2025")})
    members = ET.SubElement(year, "members")
    for value in (2023, 2024, 2025):
        ET.SubElement(members, "member", {"value": q(str(value))})

    crime = ET.SubElement(
        ds,
        "column",
        {"caption": "Crime Type", "datatype": "string", "name": "[pCrimeType]", "param-domain-type": "list", "role": "measure", "type": "nominal", "value": q("All Crime Types")},
    )
    ET.SubElement(crime, "calculation", {"class": "tableau", "formula": q("All Crime Types")})
    members = ET.SubElement(crime, "members")
    for value in ["All Crime Types", *crime_types]:
        ET.SubElement(members, "member", {"value": q(value)})

    area = ET.SubElement(
        ds,
        "column",
        {"caption": "Community Area", "datatype": "string", "name": "[pCommunityArea]", "param-domain-type": "list", "role": "measure", "type": "nominal", "value": q("All Community Areas")},
    )
    ET.SubElement(area, "calculation", {"class": "tableau", "formula": q("All Community Areas")})
    members = ET.SubElement(area, "members")
    for value in ["All Community Areas", *community_areas]:
        ET.SubElement(members, "member", {"value": q(value)})

    district = ET.SubElement(
        ds,
        "column",
        {"caption": "Police District", "datatype": "string", "name": "[pDistrict]", "param-domain-type": "list", "role": "measure", "type": "nominal", "value": q("All Police Districts")},
    )
    ET.SubElement(district, "calculation", {"class": "tableau", "formula": q("All Police Districts")})
    members = ET.SubElement(district, "members")
    for value in ["All Police Districts", *districts]:
        ET.SubElement(members, "member", {"value": q(value)})


def add_dependencies(view: ET.Element, datasource: str, fields: list[tuple[str, str]], calculations: list[str], instances: list[tuple[str, str, str, str]]) -> None:
    deps = ET.SubElement(view, "datasource-dependencies", {"datasource": datasource})
    for field_name, datatype in fields:
        add_column(deps, field_name, datatype)
    calc_specs = {
        "Calculation_SelectedYear": ("Selected Year Filter", "boolean", "dimension", "nominal", "STR([crime_year]) = [Parameters].[pSelectedYear]", None),
        "Calculation_SelectedCrimeType": ("Selected Crime Type Filter", "boolean", "dimension", "nominal", '[Parameters].[pCrimeType] = "All Crime Types" OR [primary_type] = [Parameters].[pCrimeType]', None),
        "Calculation_CategoryDisplay": ("Show Category in Distribution", "boolean", "dimension", "nominal", '[Parameters].[pCrimeType] <> "All Crime Types" OR [incident_volume_rank] <= 10', None),
        "Calculation_ArrestPercentage": ("Weighted Arrest Percentage", "real", "measure", "quantitative", "IF SUM([arrest_indicator_denominator]) = 0 THEN NULL ELSE 100.0 * SUM([arrest_count]) / SUM([arrest_indicator_denominator]) END", 'n#,##0.0"%";-#,##0.0"%"'),
        "Calculation_DomesticPercentage": ("Weighted Domestic Incident Percentage", "real", "measure", "quantitative", "IF SUM([domestic_indicator_denominator]) = 0 THEN NULL ELSE 100.0 * SUM([domestic_count]) / SUM([domestic_indicator_denominator]) END", 'n#,##0.0"%";-#,##0.0"%"'),
        "Calculation_SelectedCommunityArea": ("Selected Community Area Filter", "boolean", "dimension", "nominal", '[Parameters].[pCommunityArea] = "All Community Areas" OR [community_area_name] = [Parameters].[pCommunityArea]', None),
        "Calculation_SelectedDistrict": ("Selected Police District Filter", "boolean", "dimension", "nominal", '[Parameters].[pDistrict] = "All Police Districts" OR [district_label] = [Parameters].[pDistrict]', None),
        "Calculation_MapCoveragePercentage": ("Coordinate Coverage Percentage", "real", "measure", "quantitative", "IF SUM([reported_incident_count]) = 0 THEN NULL ELSE 100.0 * SUM(IF [coordinate_mappable_flag] = 1 THEN [reported_incident_count] ELSE 0 END) / SUM([reported_incident_count]) END", 'n#,##0.0"%";-#,##0.0"%"'),
        "Calculation_MappableRecord": ("Coordinate-Mappable Record", "boolean", "dimension", "nominal", "[coordinate_mappable_flag] = 1", None),
        "Calculation_CommunityAreaEligible": ("Community-Area Eligible Record", "boolean", "dimension", "nominal", "[community_area_eligible_flag] = 1", None),
    }
    for calc_name in calculations:
        caption, datatype, role, kind, formula, default_format = calc_specs[calc_name]
        attrs = {"caption": caption, "datatype": datatype, "name": f"[{calc_name}]", "role": role, "type": kind}
        if default_format:
            attrs["default-format"] = default_format
        calc = ET.SubElement(deps, "column", attrs)
        ET.SubElement(calc, "calculation", {"class": "tableau", "formula": formula})
    for source_column, derivation, instance_name, kind in instances:
        ET.SubElement(
            deps,
            "column-instance",
            {"column": f"[{source_column}]", "derivation": derivation, "name": f"[{instance_name}]", "pivot": "key", "type": kind},
        )


def add_parameter_dependencies(view: ET.Element) -> None:
    deps = ET.SubElement(view, "datasource-dependencies", {"datasource": "Parameters"})
    year = ET.SubElement(deps, "column", {"caption": "Year", "datatype": "string", "name": "[pSelectedYear]", "param-domain-type": "list", "role": "measure", "type": "nominal", "value": q("2025")})
    ET.SubElement(year, "calculation", {"class": "tableau", "formula": q("2025")})
    crime = ET.SubElement(deps, "column", {"caption": "Crime Type", "datatype": "string", "name": "[pCrimeType]", "param-domain-type": "list", "role": "measure", "type": "nominal", "value": q("All Crime Types")})
    ET.SubElement(crime, "calculation", {"class": "tableau", "formula": q("All Crime Types")})
    area = ET.SubElement(deps, "column", {"caption": "Community Area", "datatype": "string", "name": "[pCommunityArea]", "param-domain-type": "list", "role": "measure", "type": "nominal", "value": q("All Community Areas")})
    ET.SubElement(area, "calculation", {"class": "tableau", "formula": q("All Community Areas")})
    district = ET.SubElement(deps, "column", {"caption": "Police District", "datatype": "string", "name": "[pDistrict]", "param-domain-type": "list", "role": "measure", "type": "nominal", "value": q("All Police Districts")})
    ET.SubElement(district, "calculation", {"class": "tableau", "formula": q("All Police Districts")})


def add_true_filter(view: ET.Element, datasource: str, calc_name: str) -> None:
    full = f"[{datasource}].[{calc_name}]"
    filt = ET.SubElement(view, "filter", {"class": "categorical", "column": full})
    ET.SubElement(
        filt,
        "groupfilter",
        {"function": "member", "level": f"[{calc_name}]", "member": "true", "user:ui-domain": "database", "user:ui-enumeration": "inclusive", "user:ui-marker": "enumerate"},
    )


def add_title(worksheet: ET.Element, title: str) -> None:
    layout = ET.SubElement(worksheet, "layout-options")
    formatted = ET.SubElement(ET.SubElement(layout, "title"), "formatted-text")
    run = ET.SubElement(formatted, "run", {"bold": "true", "fontcolor": "#243447", "fontname": "Tableau Semibold", "fontsize": "12"})
    run.text = title


def add_sheet_style(table: ET.Element, *, hide_headers: bool = False, percent: bool = False, kpi: bool = False) -> None:
    style = ET.SubElement(table, "style")
    worksheet_rule = ET.SubElement(style, "style-rule", {"element": "worksheet"})
    add_format(worksheet_rule, attr="font-family", value="Tableau Book")
    add_format(worksheet_rule, attr="color", value="#243447")
    add_format(worksheet_rule, attr="display-field-labels", scope="rows", value="false")
    add_format(worksheet_rule, attr="display-field-labels", scope="cols", value="false")
    grid = ET.SubElement(style, "style-rule", {"element": "gridline"})
    add_format(grid, attr="line-visibility", scope="rows", value="off")
    add_format(grid, attr="line-visibility", scope="cols", value="off")
    if hide_headers:
        axis = ET.SubElement(style, "style-rule", {"element": "axis"})
        add_format(axis, attr="line-visibility", scope="rows", value="off")
        add_format(axis, attr="line-visibility", scope="cols", value="off")
    if percent or kpi:
        cell = ET.SubElement(style, "style-rule", {"element": "cell"})
        if percent:
            add_format(cell, attr="text-format", value='n#,##0.0"%";-#,##0.0"%"')
        if kpi:
            add_format(cell, attr="font-family", value="Tableau Semibold")
            add_format(cell, attr="font-size", value="26")
            add_format(cell, attr="font-weight", value="bold")
            add_format(cell, attr="color", value="#17324D")
            add_format(cell, attr="text-align", value="center")
            add_format(cell, attr="vertical-align", value="middle")


def add_mark(
    table: ET.Element,
    mark_class: str,
    encodings: list[tuple[str, str]],
    tooltip_runs: list[tuple[str, dict[str, str]]] | None = None,
    labels: bool = False,
    label_font_size: int | None = None,
) -> None:
    panes = ET.SubElement(table, "panes")
    pane = ET.SubElement(panes, "pane", {"selection-relaxation-option": "selection-relaxation-disallow"})
    ET.SubElement(ET.SubElement(pane, "view"), "breakdown", {"value": "auto"})
    ET.SubElement(pane, "mark", {"class": mark_class})
    enc = ET.SubElement(pane, "encodings")
    for encoding, column in encodings:
        ET.SubElement(enc, encoding, {"column": column})
    if tooltip_runs is not None:
        formatted = ET.SubElement(ET.SubElement(pane, "customized-tooltip"), "formatted-text")
        for text_value, attrs in tooltip_runs:
            run = ET.SubElement(formatted, "run", attrs)
            run.text = text_value
    style = ET.SubElement(pane, "style")
    rule = ET.SubElement(style, "style-rule", {"element": "mark"})
    add_format(rule, attr="mark-labels-show", value="true" if labels else "false")
    add_format(rule, attr="mark-labels-cull", value="true")
    if label_font_size is not None:
        label_rule = ET.SubElement(style, "style-rule", {"element": "datalabel"})
        add_format(label_rule, attr="font-family", value="Tableau Semibold")
        add_format(label_rule, attr="font-size", value=str(label_font_size))
        add_format(label_rule, attr="color", value="#17324D")


def add_kpi(worksheets: ET.Element, name: str, field_ref: str, calc_name: str | None, tooltip_text: str, percent: bool = False) -> None:
    ws = ET.SubElement(worksheets, "worksheet", {"name": name})
    add_title(ws, name)
    table = ET.SubElement(ws, "table")
    view = ET.SubElement(table, "view")
    sources = ET.SubElement(view, "datasources")
    ET.SubElement(sources, "datasource", {"caption": "Executive Category Year", "name": "AnnualDS"})
    ET.SubElement(sources, "datasource", {"name": "Parameters"})
    calculations = ["Calculation_SelectedYear", "Calculation_SelectedCrimeType"]
    fields = [("crime_year", "integer"), ("primary_type", "string")]
    instances: list[tuple[str, str, str, str]] = []
    if calc_name:
        calculations.append(calc_name)
        instances.append((calc_name, "User", f"usr:{calc_name}:qk", "quantitative"))
    else:
        fields.append(("reported_incident_count", "integer"))
        instances.append(("reported_incident_count", "Sum", "sum:reported_incident_count:qk", "quantitative"))
    add_dependencies(view, "AnnualDS", fields, calculations, instances)
    add_parameter_dependencies(view)
    add_true_filter(view, "AnnualDS", "Calculation_SelectedYear")
    add_true_filter(view, "AnnualDS", "Calculation_SelectedCrimeType")
    slices = ET.SubElement(view, "slices")
    ET.SubElement(slices, "column").text = "[AnnualDS].[Calculation_SelectedYear]"
    ET.SubElement(slices, "column").text = "[AnnualDS].[Calculation_SelectedCrimeType]"
    ET.SubElement(view, "aggregation", {"value": "true"})
    add_sheet_style(table, hide_headers=True, percent=percent, kpi=True)
    add_mark(
        table,
        "Text",
        [("text", field_ref)],
        [(tooltip_text, {"fontname": "Tableau Medium"})],
        labels=True,
        label_font_size=26,
    )
    ET.SubElement(table, "rows")
    ET.SubElement(table, "cols")
    ET.SubElement(table, "tooltip-style", {"tooltip-mode": "none"})


def add_yearly_trend(worksheets: ET.Element) -> None:
    name = "Yearly Crime Trend"
    ws = ET.SubElement(worksheets, "worksheet", {"name": name})
    add_title(ws, "Reported Incidents by Year")
    table = ET.SubElement(ws, "table")
    view = ET.SubElement(table, "view")
    sources = ET.SubElement(view, "datasources")
    ET.SubElement(sources, "datasource", {"caption": "Executive Category Year", "name": "AnnualDS"})
    ET.SubElement(sources, "datasource", {"name": "Parameters"})
    add_dependencies(
        view,
        "AnnualDS",
        [("crime_year", "integer"), ("primary_type", "string"), ("reported_incident_count", "integer")],
        ["Calculation_SelectedCrimeType"],
        [("crime_year", "None", "none:crime_year:ok", "ordinal"), ("reported_incident_count", "Sum", "sum:reported_incident_count:qk", "quantitative")],
    )
    add_parameter_dependencies(view)
    add_true_filter(view, "AnnualDS", "Calculation_SelectedCrimeType")
    slices = ET.SubElement(view, "slices")
    ET.SubElement(slices, "column").text = "[AnnualDS].[Calculation_SelectedCrimeType]"
    ET.SubElement(view, "aggregation", {"value": "true"})
    add_sheet_style(table)
    add_mark(
        table,
        "Line",
        [("text", "[AnnualDS].[sum:reported_incident_count:qk]")],
        [("Year: ", {"fontcolor": "#666666"}), ("<[AnnualDS].[none:crime_year:ok]>", {"bold": "true"}), ("\nReported incidents: ", {"fontcolor": "#666666"}), ("<[AnnualDS].[sum:reported_incident_count:qk]>", {"bold": "true"})],
        labels=True,
        label_font_size=9,
    )
    ET.SubElement(table, "rows").text = "[AnnualDS].[sum:reported_incident_count:qk]"
    ET.SubElement(table, "cols").text = "[AnnualDS].[none:crime_year:ok]"


def add_category_distribution(worksheets: ET.Element) -> None:
    name = "Crime Category Distribution"
    ws = ET.SubElement(worksheets, "worksheet", {"name": name})
    add_title(ws, "Top Crime Categories by Reported Incidents")
    table = ET.SubElement(ws, "table")
    view = ET.SubElement(table, "view")
    sources = ET.SubElement(view, "datasources")
    ET.SubElement(sources, "datasource", {"caption": "Executive Category Year", "name": "AnnualDS"})
    ET.SubElement(sources, "datasource", {"name": "Parameters"})
    add_dependencies(
        view,
        "AnnualDS",
        [("crime_year", "integer"), ("primary_type", "string"), ("reported_incident_count", "integer"), ("incident_volume_rank", "integer")],
        ["Calculation_SelectedYear", "Calculation_SelectedCrimeType", "Calculation_CategoryDisplay"],
        [("primary_type", "None", "none:primary_type:nk", "nominal"), ("reported_incident_count", "Sum", "sum:reported_incident_count:qk", "quantitative")],
    )
    add_parameter_dependencies(view)
    add_true_filter(view, "AnnualDS", "Calculation_SelectedYear")
    add_true_filter(view, "AnnualDS", "Calculation_SelectedCrimeType")
    add_true_filter(view, "AnnualDS", "Calculation_CategoryDisplay")
    ET.SubElement(view, "sort", {"class": "computed", "column": "[AnnualDS].[none:primary_type:nk]", "direction": "DESC", "using": "[AnnualDS].[sum:reported_incident_count:qk]"})
    slices = ET.SubElement(view, "slices")
    ET.SubElement(slices, "column").text = "[AnnualDS].[Calculation_SelectedYear]"
    ET.SubElement(slices, "column").text = "[AnnualDS].[Calculation_SelectedCrimeType]"
    ET.SubElement(slices, "column").text = "[AnnualDS].[Calculation_CategoryDisplay]"
    ET.SubElement(view, "aggregation", {"value": "true"})
    add_sheet_style(table)
    add_mark(
        table,
        "Bar",
        [("text", "[AnnualDS].[sum:reported_incident_count:qk]")],
        [("Crime type: ", {"fontcolor": "#666666"}), ("<[AnnualDS].[none:primary_type:nk]>", {"bold": "true"}), ("\nReported incidents: ", {"fontcolor": "#666666"}), ("<[AnnualDS].[sum:reported_incident_count:qk]>", {"bold": "true"})],
        labels=True,
    )
    ET.SubElement(table, "rows").text = "[AnnualDS].[none:primary_type:nk]"
    ET.SubElement(table, "cols").text = "[AnnualDS].[sum:reported_incident_count:qk]"


def add_monthly_trend(worksheets: ET.Element) -> None:
    name = "Monthly Crime Trend"
    ws = ET.SubElement(worksheets, "worksheet", {"name": name})
    add_title(ws, "Monthly Reported-Incident Trend")
    table = ET.SubElement(ws, "table")
    view = ET.SubElement(table, "view")
    sources = ET.SubElement(view, "datasources")
    ET.SubElement(sources, "datasource", {"caption": "Executive Month Category", "name": "MonthlyDS"})
    ET.SubElement(sources, "datasource", {"name": "Parameters"})
    add_dependencies(
        view,
        "MonthlyDS",
        [("month_start", "date"), ("crime_year", "integer"), ("primary_type", "string"), ("reported_incident_count", "integer"), ("trailing_three_month_average", "real")],
        ["Calculation_SelectedYear", "Calculation_SelectedCrimeType"],
        [("month_start", "Month-Trunc", "tmn:month_start:ok", "ordinal"), ("reported_incident_count", "Sum", "sum:reported_incident_count:qk", "quantitative"), ("trailing_three_month_average", "Sum", "sum:trailing_three_month_average:qk", "quantitative")],
    )
    add_parameter_dependencies(view)
    add_true_filter(view, "MonthlyDS", "Calculation_SelectedYear")
    add_true_filter(view, "MonthlyDS", "Calculation_SelectedCrimeType")
    slices = ET.SubElement(view, "slices")
    ET.SubElement(slices, "column").text = "[MonthlyDS].[Calculation_SelectedYear]"
    ET.SubElement(slices, "column").text = "[MonthlyDS].[Calculation_SelectedCrimeType]"
    ET.SubElement(view, "aggregation", {"value": "true"})
    add_sheet_style(table)
    add_mark(
        table,
        "Line",
        [],
        [("Month: ", {"fontcolor": "#666666"}), ("<[MonthlyDS].[tmn:month_start:ok]>", {"bold": "true"}), ("\nReported incidents: ", {"fontcolor": "#666666"}), ("<[MonthlyDS].[sum:reported_incident_count:qk]>", {"bold": "true"}), ("\nTrailing 3-month average: ", {"fontcolor": "#666666"}), ("<[MonthlyDS].[sum:trailing_three_month_average:qk]>", {"bold": "true"})],
        labels=False,
    )
    ET.SubElement(table, "rows").text = "[MonthlyDS].[sum:reported_incident_count:qk]"
    ET.SubElement(table, "cols").text = "[MonthlyDS].[tmn:month_start:ok]"


GEOGRAPHIC_FILTER_CALCULATIONS = [
    "Calculation_SelectedYear",
    "Calculation_SelectedCrimeType",
    "Calculation_SelectedCommunityArea",
    "Calculation_SelectedDistrict",
]


def add_geographic_filter_state(
    view: ET.Element,
    extra_filters: list[str] | None = None,
    *,
    include_slices: bool = True,
) -> list[str]:
    filter_names = [*GEOGRAPHIC_FILTER_CALCULATIONS, *(extra_filters or [])]
    for filter_name in filter_names:
        add_true_filter(view, "GeographicDS", filter_name)
    if include_slices:
        slices = ET.SubElement(view, "slices")
        for filter_name in filter_names:
            ET.SubElement(slices, "column").text = f"[GeographicDS].[{filter_name}]"
    return filter_names


def add_geographic_slices(view: ET.Element, filter_names: list[str]) -> None:
    slices = ET.SubElement(view, "slices")
    for filter_name in filter_names:
        ET.SubElement(slices, "column").text = f"[GeographicDS].[{filter_name}]"


def add_geographic_kpi(
    worksheets: ET.Element,
    *,
    name: str,
    title: str,
    field_ref: str,
    calculation: str | None,
    tooltip_text: str,
    percent: bool = False,
) -> None:
    ws = ET.SubElement(worksheets, "worksheet", {"name": name})
    add_title(ws, title)
    table = ET.SubElement(ws, "table")
    view = ET.SubElement(table, "view")
    sources = ET.SubElement(view, "datasources")
    ET.SubElement(sources, "datasource", {"caption": "Geographic Detail", "name": "GeographicDS"})
    ET.SubElement(sources, "datasource", {"name": "Parameters"})
    fields = [
        ("crime_year", "integer"),
        ("primary_type", "string"),
        ("community_area_name", "string"),
        ("district_label", "string"),
    ]
    calculations = list(GEOGRAPHIC_FILTER_CALCULATIONS)
    instances: list[tuple[str, str, str, str]] = []
    if calculation:
        calculations.append(calculation)
        fields.extend(
            [
                ("coordinate_mappable_flag", "integer"),
                ("reported_incident_count", "integer"),
            ]
        )
        instances.append((calculation, "User", f"usr:{calculation}:qk", "quantitative"))
    else:
        fields.append(("reported_incident_count", "integer"))
        instances.append(("reported_incident_count", "Sum", "sum:reported_incident_count:qk", "quantitative"))
    add_dependencies(view, "GeographicDS", fields, calculations, instances)
    add_parameter_dependencies(view)
    add_geographic_filter_state(view)
    ET.SubElement(view, "aggregation", {"value": "true"})
    add_sheet_style(table, hide_headers=True, percent=percent, kpi=True)
    add_mark(
        table,
        "Text",
        [("text", field_ref)],
        [(tooltip_text, {"fontname": "Tableau Medium"})],
        labels=True,
        label_font_size=18,
    )
    ET.SubElement(table, "rows")
    ET.SubElement(table, "cols")
    ET.SubElement(table, "tooltip-style", {"tooltip-mode": "none"})


def add_geographic_map(worksheets: ET.Element) -> None:
    name = "Chicago Geographic Crime Map"
    ws = ET.SubElement(worksheets, "worksheet", {"name": name})
    add_title(ws, "Descriptive Incident Density — 0.01° Coordinate Cells")
    table = ET.SubElement(ws, "table")
    view = ET.SubElement(table, "view")
    sources = ET.SubElement(view, "datasources")
    ET.SubElement(sources, "datasource", {"caption": "Geographic Detail", "name": "GeographicDS"})
    ET.SubElement(sources, "datasource", {"name": "Parameters"})
    fields = [
        ("crime_year", "integer"),
        ("primary_type", "string"),
        ("community_area_name", "string"),
        ("district_label", "string"),
        ("coordinate_mappable_flag", "integer"),
        ("cell_latitude", "real"),
        ("cell_longitude", "real"),
        ("density_cell_id", "string"),
        ("reported_incident_count", "integer"),
    ]
    instances = [
        ("cell_latitude", "Avg", "avg:cell_latitude:qk", "quantitative"),
        ("cell_longitude", "Avg", "avg:cell_longitude:qk", "quantitative"),
        ("density_cell_id", "None", "none:density_cell_id:nk", "nominal"),
        ("reported_incident_count", "Sum", "sum:reported_incident_count:qk", "quantitative"),
    ]
    add_dependencies(
        view,
        "GeographicDS",
        fields,
        [*GEOGRAPHIC_FILTER_CALCULATIONS, "Calculation_MappableRecord"],
        instances,
    )
    add_parameter_dependencies(view)
    add_geographic_filter_state(view, ["Calculation_MappableRecord"])
    ET.SubElement(view, "aggregation", {"value": "true"})
    add_sheet_style(table)
    add_mark(
        table,
        "Circle",
        [
            ("color", "[GeographicDS].[sum:reported_incident_count:qk]"),
            ("size", "[GeographicDS].[sum:reported_incident_count:qk]"),
            ("lod", "[GeographicDS].[none:density_cell_id:nk]"),
        ],
        [
            ("Coordinate cell: ", {"fontcolor": "#666666"}),
            ("<[GeographicDS].[none:density_cell_id:nk]>", {"bold": "true"}),
            ("\nReported incidents: ", {"fontcolor": "#666666"}),
            ("<[GeographicDS].[sum:reported_incident_count:qk]>", {"bold": "true"}),
            ("\nDescriptive 0.01-degree cell; not a statistical hotspot test.", {"fontcolor": "#666666"}),
        ],
    )
    ET.SubElement(table, "rows").text = "[GeographicDS].[avg:cell_latitude:qk]"
    ET.SubElement(table, "cols").text = "[GeographicDS].[avg:cell_longitude:qk]"


def add_community_area_ranking(worksheets: ET.Element) -> None:
    name = "Community Area Ranking"
    ws = ET.SubElement(worksheets, "worksheet", {"name": name})
    add_title(ws, "Community Areas Ranked by Reported Incidents")
    table = ET.SubElement(ws, "table")
    view = ET.SubElement(table, "view")
    sources = ET.SubElement(view, "datasources")
    ET.SubElement(sources, "datasource", {"caption": "Geographic Detail", "name": "GeographicDS"})
    ET.SubElement(sources, "datasource", {"name": "Parameters"})
    fields = [
        ("crime_year", "integer"),
        ("primary_type", "string"),
        ("community_area_name", "string"),
        ("district_label", "string"),
        ("community_area_eligible_flag", "integer"),
        ("reported_incident_count", "integer"),
    ]
    calculations = [*GEOGRAPHIC_FILTER_CALCULATIONS, "Calculation_CommunityAreaEligible"]
    instances = [
        ("community_area_name", "None", "none:community_area_name:nk", "nominal"),
        ("reported_incident_count", "Sum", "sum:reported_incident_count:qk", "quantitative"),
    ]
    add_dependencies(view, "GeographicDS", fields, calculations, instances)
    add_parameter_dependencies(view)
    filter_names = add_geographic_filter_state(
        view,
        ["Calculation_CommunityAreaEligible"],
        include_slices=False,
    )
    ET.SubElement(view, "sort", {"class": "computed", "column": "[GeographicDS].[none:community_area_name:nk]", "direction": "DESC", "using": "[GeographicDS].[sum:reported_incident_count:qk]"})
    add_geographic_slices(view, filter_names)
    ET.SubElement(view, "aggregation", {"value": "true"})
    add_sheet_style(table)
    add_mark(
        table,
        "Bar",
        [("text", "[GeographicDS].[sum:reported_incident_count:qk]")],
        [
            ("Community area: ", {"fontcolor": "#666666"}),
            ("<[GeographicDS].[none:community_area_name:nk]>", {"bold": "true"}),
            ("\nReported incidents: ", {"fontcolor": "#666666"}),
            ("<[GeographicDS].[sum:reported_incident_count:qk]>", {"bold": "true"}),
        ],
        labels=True,
    )
    ET.SubElement(table, "rows").text = "[GeographicDS].[none:community_area_name:nk]"
    ET.SubElement(table, "cols").text = "[GeographicDS].[sum:reported_incident_count:qk]"


def add_district_comparison(worksheets: ET.Element) -> None:
    name = "District Comparison"
    ws = ET.SubElement(worksheets, "worksheet", {"name": name})
    add_title(ws, "Police District Comparison")
    table = ET.SubElement(ws, "table")
    view = ET.SubElement(table, "view")
    sources = ET.SubElement(view, "datasources")
    ET.SubElement(sources, "datasource", {"caption": "Geographic Detail", "name": "GeographicDS"})
    ET.SubElement(sources, "datasource", {"name": "Parameters"})
    fields = [
        ("crime_year", "integer"),
        ("primary_type", "string"),
        ("community_area_name", "string"),
        ("district_label", "string"),
        ("reported_incident_count", "integer"),
    ]
    instances = [
        ("district_label", "None", "none:district_label:nk", "nominal"),
        ("reported_incident_count", "Sum", "sum:reported_incident_count:qk", "quantitative"),
    ]
    add_dependencies(view, "GeographicDS", fields, GEOGRAPHIC_FILTER_CALCULATIONS, instances)
    add_parameter_dependencies(view)
    filter_names = add_geographic_filter_state(view, include_slices=False)
    ET.SubElement(view, "sort", {"class": "computed", "column": "[GeographicDS].[none:district_label:nk]", "direction": "DESC", "using": "[GeographicDS].[sum:reported_incident_count:qk]"})
    add_geographic_slices(view, filter_names)
    ET.SubElement(view, "aggregation", {"value": "true"})
    add_sheet_style(table)
    add_mark(
        table,
        "Bar",
        [("text", "[GeographicDS].[sum:reported_incident_count:qk]")],
        [
            ("Police district: ", {"fontcolor": "#666666"}),
            ("<[GeographicDS].[none:district_label:nk]>", {"bold": "true"}),
            ("\nReported incidents: ", {"fontcolor": "#666666"}),
            ("<[GeographicDS].[sum:reported_incident_count:qk]>", {"bold": "true"}),
        ],
        labels=True,
    )
    ET.SubElement(table, "rows").text = "[GeographicDS].[none:district_label:nk]"
    ET.SubElement(table, "cols").text = "[GeographicDS].[sum:reported_incident_count:qk]"


def add_geographic_category_analysis(worksheets: ET.Element) -> None:
    name = "Geographic Crime Category Analysis"
    ws = ET.SubElement(worksheets, "worksheet", {"name": name})
    add_title(ws, "Crime Categories Ranked in Selected Geography")
    table = ET.SubElement(ws, "table")
    view = ET.SubElement(table, "view")
    sources = ET.SubElement(view, "datasources")
    ET.SubElement(sources, "datasource", {"caption": "Geographic Detail", "name": "GeographicDS"})
    ET.SubElement(sources, "datasource", {"name": "Parameters"})
    fields = [
        ("crime_year", "integer"),
        ("primary_type", "string"),
        ("community_area_name", "string"),
        ("district_label", "string"),
        ("reported_incident_count", "integer"),
    ]
    calculations = list(GEOGRAPHIC_FILTER_CALCULATIONS)
    instances = [
        ("primary_type", "None", "none:primary_type:nk", "nominal"),
        ("reported_incident_count", "Sum", "sum:reported_incident_count:qk", "quantitative"),
    ]
    add_dependencies(view, "GeographicDS", fields, calculations, instances)
    add_parameter_dependencies(view)
    filter_names = add_geographic_filter_state(view, include_slices=False)
    ET.SubElement(view, "sort", {"class": "computed", "column": "[GeographicDS].[none:primary_type:nk]", "direction": "DESC", "using": "[GeographicDS].[sum:reported_incident_count:qk]"})
    add_geographic_slices(view, filter_names)
    ET.SubElement(view, "aggregation", {"value": "true"})
    add_sheet_style(table)
    add_mark(
        table,
        "Bar",
        [("text", "[GeographicDS].[sum:reported_incident_count:qk]")],
        [
            ("Crime type: ", {"fontcolor": "#666666"}),
            ("<[GeographicDS].[none:primary_type:nk]>", {"bold": "true"}),
            ("\nReported incidents: ", {"fontcolor": "#666666"}),
            ("<[GeographicDS].[sum:reported_incident_count:qk]>", {"bold": "true"}),
        ],
        labels=True,
    )
    ET.SubElement(table, "rows").text = "[GeographicDS].[none:primary_type:nk]"
    ET.SubElement(table, "cols").text = "[GeographicDS].[sum:reported_incident_count:qk]"


def add_dashboard(root: ET.Element) -> None:
    dashboards = ET.SubElement(root, "dashboards")
    dashboard = ET.SubElement(dashboards, "dashboard", {"name": "Executive Overview"})
    layout = ET.SubElement(dashboard, "layout-options")
    formatted = ET.SubElement(ET.SubElement(layout, "title"), "formatted-text")
    title_run = ET.SubElement(formatted, "run", {"bold": "true", "fontcolor": "#17324D", "fontname": "Tableau Semibold", "fontsize": "22"})
    title_run.text = "Chicago Crime Analytics — Executive Overview"
    style = ET.SubElement(dashboard, "style")
    rule = ET.SubElement(style, "style-rule", {"element": "dashboard"})
    add_format(rule, attr="background-color", value="#F5F7FA")
    ET.SubElement(dashboard, "size", {"maxheight": "850", "maxwidth": "1360", "minheight": "850", "minwidth": "1360", "sizing-mode": "fixed"})
    sources = ET.SubElement(dashboard, "datasources")
    ET.SubElement(sources, "datasource", {"name": "Parameters"})
    add_parameter_dependencies(dashboard)
    zones = ET.SubElement(dashboard, "zones")
    root_zone = ET.SubElement(zones, "zone", {"h": "100000", "id": "1", "type-v2": "layout-basic", "w": "100000", "x": "0", "y": "0"})

    ET.SubElement(root_zone, "zone", {"h": "7200", "id": "2", "type-v2": "title", "w": "71000", "x": "1800", "y": "1200"})
    subtitle = ET.SubElement(root_zone, "zone", {"h": "3600", "id": "3", "type-v2": "text", "w": "71000", "x": "1800", "y": "7800"})
    sub_text = ET.SubElement(subtitle, "formatted-text")
    sub_run = ET.SubElement(sub_text, "run", {"fontcolor": "#5B6B7C", "fontname": "Tableau Book", "fontsize": "10"})
    sub_run.text = "Complete calendar years 2023–2025 | Official City of Chicago Crimes dataset (ijzp-q8t2)"

    year_zone = ET.SubElement(root_zone, "zone", {"custom-title": "true", "h": "5200", "id": "4", "mode": "compact", "param": "[Parameters].[pSelectedYear]", "type-v2": "paramctrl", "w": "11500", "x": "74500", "y": "2200"})
    year_text = ET.SubElement(year_zone, "formatted-text")
    ET.SubElement(year_text, "run", {"bold": "true", "fontcolor": "#243447", "fontsize": "10"}).text = "Year"
    type_zone = ET.SubElement(root_zone, "zone", {"custom-title": "true", "h": "5200", "id": "5", "mode": "compact", "param": "[Parameters].[pCrimeType]", "type-v2": "paramctrl", "w": "12500", "x": "86500", "y": "2200"})
    type_text = ET.SubElement(type_zone, "formatted-text")
    ET.SubElement(type_text, "run", {"bold": "true", "fontcolor": "#243447", "fontsize": "10"}).text = "Crime Type"

    sheet_zones = [
        ("Total Reported Crimes", 6, 1800, 13000, 31200, 15000),
        ("Arrest Percentage", 7, 34400, 13000, 31200, 15000),
        ("Domestic Incident Percentage", 8, 67000, 13000, 31200, 15000),
        ("Yearly Crime Trend", 9, 1800, 30000, 47000, 29000),
        ("Crime Category Distribution", 10, 50400, 30000, 48200, 29000),
        ("Monthly Crime Trend", 11, 1800, 61000, 96800, 28000),
    ]
    for sheet_name, zone_id, x, y, w, h in sheet_zones:
        zone = ET.SubElement(root_zone, "zone", {"h": str(h), "id": str(zone_id), "name": sheet_name, "show-title": "true", "w": str(w), "x": str(x), "y": str(y)})
        zone_style = ET.SubElement(zone, "zone-style")
        add_format(zone_style, attr="background-color", value="#FFFFFF")
        add_format(zone_style, attr="border-color", value="#D9E1E8")
        add_format(zone_style, attr="border-style", value="solid")
        add_format(zone_style, attr="border-width", value="1")
        add_format(zone_style, attr="margin", value="6")

    footer = ET.SubElement(root_zone, "zone", {"h": "7800", "id": "12", "type-v2": "text", "w": "96800", "x": "1800", "y": "91000"})
    footer_text = ET.SubElement(footer, "formatted-text")
    ET.SubElement(footer_text, "run", {"fontcolor": "#4D5F70", "fontsize": "9"}).text = (
        "Source extract: Sep 25, 2026 | Incident dates: Jan 1, 2023–Dec 31, 2025 | Complete years\n"
        "Reported incident counts are not population-normalized crime rates. Results are descriptive and do not establish causation. "
        "Arrest percentage is the share of records marked arrest=true; it is not a clearance or conviction rate."
    )

    geo_dashboard = ET.SubElement(dashboards, "dashboard", {"name": "Geographic Crime Patterns"})
    geo_layout = ET.SubElement(geo_dashboard, "layout-options")
    geo_formatted = ET.SubElement(ET.SubElement(geo_layout, "title"), "formatted-text")
    geo_title_run = ET.SubElement(
        geo_formatted,
        "run",
        {"bold": "true", "fontcolor": "#17324D", "fontname": "Tableau Semibold", "fontsize": "22"},
    )
    geo_title_run.text = "Chicago Crime Analytics — Geographic Crime Patterns"
    geo_style = ET.SubElement(geo_dashboard, "style")
    geo_rule = ET.SubElement(geo_style, "style-rule", {"element": "dashboard"})
    add_format(geo_rule, attr="background-color", value="#F5F7FA")
    ET.SubElement(
        geo_dashboard,
        "size",
        {"maxheight": "850", "maxwidth": "1360", "minheight": "850", "minwidth": "1360", "sizing-mode": "fixed"},
    )
    geo_sources = ET.SubElement(geo_dashboard, "datasources")
    ET.SubElement(geo_sources, "datasource", {"name": "Parameters"})
    add_parameter_dependencies(geo_dashboard)
    geo_zones = ET.SubElement(geo_dashboard, "zones")
    geo_root = ET.SubElement(
        geo_zones,
        "zone",
        {"h": "100000", "id": "101", "type-v2": "layout-basic", "w": "100000", "x": "0", "y": "0"},
    )
    ET.SubElement(geo_root, "zone", {"h": "7200", "id": "102", "type-v2": "title", "w": "70000", "x": "1800", "y": "1200"})
    geo_subtitle = ET.SubElement(
        geo_root,
        "zone",
        {"h": "3600", "id": "103", "type-v2": "text", "w": "70000", "x": "1800", "y": "7800"},
    )
    geo_sub_text = ET.SubElement(geo_subtitle, "formatted-text")
    ET.SubElement(
        geo_sub_text,
        "run",
        {"fontcolor": "#5B6B7C", "fontname": "Tableau Book", "fontsize": "10"},
    ).text = "Complete calendar years 2023–2025 | Descriptive incident concentration; not a statistical hotspot test"

    controls = [
        (104, "[Parameters].[pSelectedYear]", "Year", 71000, 2200, 8500),
        (105, "[Parameters].[pCrimeType]", "Crime Type", 79700, 2200, 10500),
        (106, "[Parameters].[pCommunityArea]", "Community Area", 71000, 7800, 14000),
        (107, "[Parameters].[pDistrict]", "Police District", 85200, 7800, 14000),
    ]
    for zone_id, parameter, label, x, y, width in controls:
        control = ET.SubElement(
            geo_root,
            "zone",
            {
                "custom-title": "true",
                "h": "5200",
                "id": str(zone_id),
                "mode": "compact",
                "param": parameter,
                "type-v2": "paramctrl",
                "w": str(width),
                "x": str(x),
                "y": str(y),
            },
        )
        control_text = ET.SubElement(control, "formatted-text")
        ET.SubElement(
            control_text,
            "run",
            {"bold": "true", "fontcolor": "#243447", "fontsize": "10"},
        ).text = label

    geo_sheet_zones = [
        ("Geographic Selected Incidents", 108, 1800, 13000, 31500, 12000),
        ("Geographic Coverage Percentage", 109, 34500, 13000, 31500, 12000),
        ("Chicago Geographic Crime Map", 110, 1800, 27000, 59000, 40000),
        ("Community Area Ranking", 111, 62500, 27000, 36000, 26000),
        ("District Comparison", 112, 62500, 55000, 36000, 25000),
        ("Geographic Crime Category Analysis", 113, 1800, 69000, 59000, 19000),
    ]
    for sheet_name, zone_id, x, y, w, h in geo_sheet_zones:
        zone = ET.SubElement(
            geo_root,
            "zone",
            {
                "h": str(h),
                "id": str(zone_id),
                "name": sheet_name,
                "show-title": "true",
                "w": str(w),
                "x": str(x),
                "y": str(y),
            },
        )
        zone_style = ET.SubElement(zone, "zone-style")
        add_format(zone_style, attr="background-color", value="#FFFFFF")
        add_format(zone_style, attr="border-color", value="#D9E1E8")
        add_format(zone_style, attr="border-style", value="solid")
        add_format(zone_style, attr="border-width", value="1")
        add_format(zone_style, attr="margin", value="6")

    geo_footer = ET.SubElement(
        geo_root,
        "zone",
        {"h": "8500", "id": "114", "type-v2": "text", "w": "96800", "x": "1800", "y": "90000"},
    )
    geo_footer_text = ET.SubElement(geo_footer, "formatted-text")
    ET.SubElement(geo_footer_text, "run", {"fontcolor": "#4D5F70", "fontsize": "9"}).text = (
        "Source extract: Sep 25, 2026 | Incident dates: Jan 1, 2023–Dec 31, 2025 | Complete years\n"
        "Counts are reported incidents, not population-normalized crime rates or individual risk. Incidents without valid coordinates remain in KPI and ranking totals but do not appear on the map. "
        "Map cells summarize observed coordinates descriptively and do not establish statistical significance or causation."
    )


def add_windows(root: ET.Element) -> None:
    windows = ET.SubElement(root, "windows", {"source-height": "32"})
    window = ET.SubElement(windows, "window", {"class": "dashboard", "maximized": "true", "name": "Executive Overview"})
    viewpoints = ET.SubElement(window, "viewpoints")
    for sheet in SHEETS:
        point = ET.SubElement(viewpoints, "viewpoint", {"name": sheet})
        ET.SubElement(point, "zoom", {"type": "entire-view"})
    ET.SubElement(window, "active", {"id": "-1"})


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def validate_page1_source_data(csv_dir: Path) -> tuple[list[str], dict[str, object]]:
    annual_path = csv_dir / ANNUAL_FILE
    monthly_path = csv_dir / MONTHLY_FILE
    manifest_path = csv_dir / "manifest.json"
    for path in (annual_path, monthly_path, manifest_path):
        if not path.is_file():
            raise FileNotFoundError(f"Required Tableau source is missing: {path}")

    annual = read_rows(annual_path)
    monthly = read_rows(monthly_path)
    if len(annual) != 93 or len(monthly) != 1116:
        raise ValueError(f"Unexpected Page 1 source row counts: annual={len(annual)}, monthly={len(monthly)}")
    crime_types = sorted({row["primary_type"] for row in annual})
    if len(crime_types) != 31:
        raise ValueError(f"Expected 31 crime types, found {len(crime_types)}")

    annual_rollup: dict[tuple[int, str], dict[str, int]] = defaultdict(lambda: {"incidents": 0, "arrests": 0, "arrest_den": 0, "domestic": 0, "domestic_den": 0})
    for row in annual:
        key = (int(row["crime_year"]), row["primary_type"])
        annual_rollup[key] = {
            "incidents": int(row["reported_incident_count"]),
            "arrests": int(row["arrest_count"]),
            "arrest_den": int(row["arrest_indicator_denominator"]),
            "domestic": int(row["domestic_count"]),
            "domestic_den": int(row["domestic_indicator_denominator"]),
        }
    monthly_rollup: dict[tuple[int, str], dict[str, int]] = defaultdict(lambda: {"incidents": 0, "arrests": 0, "arrest_den": 0, "domestic": 0, "domestic_den": 0})
    month_counts: dict[tuple[int, str], int] = defaultdict(int)
    for row in monthly:
        key = (int(row["crime_year"]), row["primary_type"])
        monthly_rollup[key]["incidents"] += int(row["reported_incident_count"])
        monthly_rollup[key]["arrests"] += int(row["arrest_count"])
        monthly_rollup[key]["arrest_den"] += int(row["arrest_indicator_denominator"])
        monthly_rollup[key]["domestic"] += int(row["domestic_count"])
        monthly_rollup[key]["domestic_den"] += int(row["domestic_indicator_denominator"])
        month_counts[key] += 1
    if annual_rollup != monthly_rollup or set(month_counts.values()) != {12}:
        raise ValueError("Annual/category and monthly/category source reconciliation failed.")

    def scope(year: int, crime_type: str | None) -> dict[str, int]:
        records = [values for (record_year, record_type), values in annual_rollup.items() if record_year == year and (crime_type is None or record_type == crime_type)]
        return {field: sum(record[field] for record in records) for field in ("incidents", "arrests", "arrest_den", "domestic", "domestic_den")}

    expected = {
        (2025, None): {"incidents": 238086, "arrests": 38365, "arrest_den": 238086, "domestic": 45319, "domestic_den": 238086},
        (2025, "THEFT"): {"incidents": 55198, "arrests": 4991, "arrest_den": 55198, "domestic": 2830, "domestic_den": 55198},
    }
    for key, benchmark in expected.items():
        actual = scope(*key)
        if actual != benchmark:
            raise ValueError(f"Validated benchmark mismatch for {key}: expected {benchmark}, got {actual}")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest_exports = {Path(item["file"]).name: item for item in manifest["exports"]}
    for path in (annual_path, monthly_path):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        item = manifest_exports.get(path.name)
        if not item or item["sha256"] != digest:
            raise ValueError(f"Manifest checksum mismatch for {path.name}")

    evidence = {
        "annual_rows": len(annual),
        "monthly_rows": len(monthly),
        "crime_types": len(crime_types),
        "all_2025": scope(2025, None),
        "theft_2025": scope(2025, "THEFT"),
        "manifest_generated_at_utc": manifest["generated_at_utc"],
    }
    return crime_types, evidence


def validate_page2_source_data(csv_dir: Path) -> tuple[list[str], list[str], dict[str, object]]:
    geographic_path = csv_dir / GEOGRAPHIC_FILE
    manifest_path = csv_dir / "manifest.json"
    for path in (geographic_path, manifest_path):
        if not path.is_file():
            raise FileNotFoundError(f"Required Tableau source is missing: {path}")

    rows = read_rows(geographic_path)
    if not rows:
        raise ValueError("The Page 2 geographic source is empty.")
    expected_columns = [name for name, _ in GEOGRAPHIC_FIELDS]
    if list(rows[0]) != expected_columns:
        raise ValueError(f"Unexpected Page 2 columns: {list(rows[0])}")

    community_areas = sorted(
        {row["community_area_name"] for row in rows if row["community_area_eligible_flag"] == "1"}
    )
    districts = sorted({row["district_label"] for row in rows})
    crime_types = sorted({row["primary_type"] for row in rows})
    if len(community_areas) != 77:
        raise ValueError(f"Expected 77 eligible community areas, found {len(community_areas)}")
    if len(crime_types) != 31:
        raise ValueError(f"Expected 31 crime types, found {len(crime_types)}")

    totals: dict[tuple[int, str | None], dict[str, int]] = defaultdict(
        lambda: {"incidents": 0, "mapped": 0, "area_eligible": 0}
    )
    grain: set[tuple[str, ...]] = set()
    for row in rows:
        count = int(row["reported_incident_count"])
        year = int(row["crime_year"])
        crime_type = row["primary_type"]
        key = tuple(row[column] for column in expected_columns[:-1])
        if key in grain:
            raise ValueError(f"Duplicate Page 2 grain detected: {key}")
        grain.add(key)
        for scope in ((year, None), (year, crime_type)):
            totals[scope]["incidents"] += count
            if row["coordinate_mappable_flag"] == "1":
                totals[scope]["mapped"] += count
            if row["community_area_eligible_flag"] == "1":
                totals[scope]["area_eligible"] += count
        if row["coordinate_mappable_flag"] == "1":
            latitude = float(row["cell_latitude"])
            longitude = float(row["cell_longitude"])
            if not (41.0 <= latitude <= 43.0 and -88.5 <= longitude <= -87.0):
                raise ValueError(f"Invalid mapped coordinate cell: {latitude}, {longitude}")
        elif row["cell_latitude"] or row["cell_longitude"] or row["density_cell_id"]:
            raise ValueError("Unmappable records must not contain derived map-cell coordinates.")

    all_years = {
        "incidents": sum(totals[(year, None)]["incidents"] for year in (2023, 2024, 2025)),
        "mapped": sum(totals[(year, None)]["mapped"] for year in (2023, 2024, 2025)),
        "area_eligible": sum(totals[(year, None)]["area_eligible"] for year in (2023, 2024, 2025)),
    }
    expected_all_years = {"incidents": 761563, "mapped": 754866, "area_eligible": 760496}
    if all_years != expected_all_years:
        raise ValueError(f"Page 2 validated total mismatch: expected {expected_all_years}, got {all_years}")
    expected_year_counts = {2023: 263844, 2024: 259633, 2025: 238086}
    for year, expected in expected_year_counts.items():
        if totals[(year, None)]["incidents"] != expected:
            raise ValueError(f"Page 2 {year} count mismatch: expected {expected}, got {totals[(year, None)]}")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    item = next((item for item in manifest["exports"] if Path(item["file"]).name == GEOGRAPHIC_FILE), None)
    digest = hashlib.sha256(geographic_path.read_bytes()).hexdigest()
    if not item or item["sha256"] != digest or int(item["rows"]) != len(rows):
        raise ValueError(f"Manifest validation failed for {GEOGRAPHIC_FILE}")

    evidence = {
        "rows": len(rows),
        "crime_types": len(crime_types),
        "community_areas": len(community_areas),
        "districts": len(districts),
        "all_years": all_years,
        "all_2025": totals[(2025, None)],
        "theft_2025": totals[(2025, "THEFT")],
        "manifest_generated_at_utc": manifest["generated_at_utc"],
    }
    return community_areas, districts, evidence


def build_workbook(crime_types: list[str], community_areas: list[str], districts: list[str]) -> ET.ElementTree:
    ET.register_namespace("user", "http://www.tableausoftware.com/xml/user")
    root = ET.Element(
        "workbook",
        {
            "locale": "en_US",
            "source-build": TABLEAU_SOURCE_BUILD,
            "source-platform": "mac",
            "version": TABLEAU_VERSION,
            "xmlns:user": "http://www.tableausoftware.com/xml/user",
        },
    )
    preferences = ET.SubElement(root, "preferences")
    ET.SubElement(preferences, "preference", {"name": "ui.encoding.shelf.height", "value": "24"})
    ET.SubElement(preferences, "preference", {"name": "ui.shelf.height", "value": "26"})
    ET.SubElement(root, "style-theme", {"name": "smooth"})
    datasources = ET.SubElement(root, "datasources")
    add_parameters(datasources, crime_types, community_areas, districts)
    add_textscan_datasource(
        datasources,
        name="AnnualDS",
        caption="Executive Category Year",
        filename=ANNUAL_FILE,
        directory="../data/processed/tableau/page1",
        fields=ANNUAL_FIELDS,
    )
    add_textscan_datasource(
        datasources,
        name="MonthlyDS",
        caption="Executive Month Category",
        filename=MONTHLY_FILE,
        directory="../data/processed/tableau/page1",
        fields=MONTHLY_FIELDS,
    )
    add_textscan_datasource(
        datasources,
        name="GeographicDS",
        caption="Geographic Detail",
        filename=GEOGRAPHIC_FILE,
        directory="../data/processed/tableau/page2",
        fields=GEOGRAPHIC_FIELDS,
    )

    worksheets = ET.SubElement(root, "worksheets")
    add_kpi(worksheets, "Total Reported Crimes", "[AnnualDS].[sum:reported_incident_count:qk]", None, "Reported incident count for the selected complete calendar year and crime-type scope.")
    add_kpi(worksheets, "Arrest Percentage", "[AnnualDS].[usr:Calculation_ArrestPercentage:qk]", "Calculation_ArrestPercentage", "Share of records marked arrest=true. This is not a clearance or conviction rate.", percent=True)
    add_kpi(worksheets, "Domestic Incident Percentage", "[AnnualDS].[usr:Calculation_DomesticPercentage:qk]", "Calculation_DomesticPercentage", "Share of reported incidents marked domestic=true for the selected scope.", percent=True)
    add_yearly_trend(worksheets)
    add_category_distribution(worksheets)
    add_monthly_trend(worksheets)
    add_geographic_kpi(
        worksheets,
        name="Geographic Selected Incidents",
        title="Incidents",
        field_ref="[GeographicDS].[sum:reported_incident_count:qk]",
        calculation=None,
        tooltip_text="Reported incident count for the selected year, crime type, community area, and police district.",
    )
    add_geographic_kpi(
        worksheets,
        name="Geographic Coverage Percentage",
        title="Coverage",
        field_ref="[GeographicDS].[usr:Calculation_MapCoveragePercentage:qk]",
        calculation="Calculation_MapCoveragePercentage",
        tooltip_text="Share of selected reported incidents with valid coordinates eligible for the map.",
        percent=True,
    )
    add_geographic_map(worksheets)
    add_community_area_ranking(worksheets)
    add_district_comparison(worksheets)
    add_geographic_category_analysis(worksheets)
    add_dashboard(root)
    add_windows(root)
    return ET.ElementTree(root)


def validate_workbook(
    output: Path,
    page1_csv_dir: Path,
    page2_csv_dir: Path,
    page1_evidence: dict[str, object],
    page2_evidence: dict[str, object],
) -> None:
    tree = ET.parse(output)
    root = tree.getroot()
    if root.tag != "workbook" or root.attrib.get("version") != TABLEAU_VERSION:
        raise ValueError("Unexpected workbook root or Tableau workbook version.")
    sources = {item.attrib.get("name"): item for item in root.findall("./datasources/datasource")}
    if set(sources) != {"Parameters", "AnnualDS", "MonthlyDS", "GeographicDS"}:
        raise ValueError(f"Unexpected workbook data sources: {sorted(sources)}")
    worksheet_names = [item.attrib["name"] for item in root.findall("./worksheets/worksheet")]
    if worksheet_names != SHEETS:
        raise ValueError(f"Worksheet definitions differ from specification: {worksheet_names}")
    dashboards = root.findall("./dashboards/dashboard")
    if [item.attrib.get("name") for item in dashboards] != ["Executive Overview", "Geographic Crime Patterns"]:
        raise ValueError("Expected dashboard definitions are missing or out of order.")
    page1_zones = {zone.attrib.get("name") for zone in dashboards[0].findall(".//zone") if zone.attrib.get("name")}
    page2_zones = {zone.attrib.get("name") for zone in dashboards[1].findall(".//zone") if zone.attrib.get("name")}
    if not set(PAGE1_SHEETS).issubset(page1_zones) or not set(PAGE2_SHEETS).issubset(page2_zones):
        raise ValueError("One or more worksheets are not placed on the correct dashboard.")
    params = {column.attrib.get("name"): column for column in sources["Parameters"].findall("column")}
    expected_defaults = {
        "[pSelectedYear]": q("2025"),
        "[pCrimeType]": q("All Crime Types"),
        "[pCommunityArea]": q("All Community Areas"),
        "[pDistrict]": q("All Police Districts"),
    }
    if any(params[name].attrib.get("value") != value for name, value in expected_defaults.items()):
        raise ValueError("Default Tableau parameter values are incorrect.")
    connections = root.findall(".//connection[@class='textscan']")
    expected_files = {ANNUAL_FILE, MONTHLY_FILE, GEOGRAPHIC_FILE}
    if {connection.attrib.get("filename") for connection in connections} != expected_files:
        raise ValueError("Text-file connection references are incomplete.")
    for connection in connections:
        referenced = (output.parent / connection.attrib["directory"] / connection.attrib["filename"]).resolve()
        expected_dir = page2_csv_dir if connection.attrib["filename"] == GEOGRAPHIC_FILE else page1_csv_dir
        expected = (expected_dir / connection.attrib["filename"]).resolve()
        if referenced != expected or not referenced.is_file():
            raise ValueError(f"Workbook reference does not resolve to the validated CSV: {referenced}")
    formulas = {calc.attrib.get("formula") for calc in root.findall(".//calculation")}
    required_formulas = {
        "STR([crime_year]) = [Parameters].[pSelectedYear]",
        '[Parameters].[pCrimeType] = "All Crime Types" OR [primary_type] = [Parameters].[pCrimeType]',
        '[Parameters].[pCrimeType] <> "All Crime Types" OR [incident_volume_rank] <= 10',
        "IF SUM([arrest_indicator_denominator]) = 0 THEN NULL ELSE 100.0 * SUM([arrest_count]) / SUM([arrest_indicator_denominator]) END",
        "IF SUM([domestic_indicator_denominator]) = 0 THEN NULL ELSE 100.0 * SUM([domestic_count]) / SUM([domestic_indicator_denominator]) END",
        '[Parameters].[pCommunityArea] = "All Community Areas" OR [community_area_name] = [Parameters].[pCommunityArea]',
        '[Parameters].[pDistrict] = "All Police Districts" OR [district_label] = [Parameters].[pDistrict]',
        "IF SUM([reported_incident_count]) = 0 THEN NULL ELSE 100.0 * SUM(IF [coordinate_mappable_flag] = 1 THEN [reported_incident_count] ELSE 0 END) / SUM([reported_incident_count]) END",
    }
    if not required_formulas.issubset(formulas):
        raise ValueError("One or more canonical Tableau calculations are missing.")
    yearly = root.find("./worksheets/worksheet[@name='Yearly Crime Trend']/table/view")
    yearly_filters = {item.attrib.get("column") for item in yearly.findall("filter")}
    if "[AnnualDS].[Calculation_SelectedYear]" in yearly_filters or "[AnnualDS].[Calculation_SelectedCrimeType]" not in yearly_filters:
        raise ValueError("Yearly trend filter scope is incorrect.")
    category = root.find("./worksheets/worksheet[@name='Crime Category Distribution']/table/view")
    category_filters = {item.attrib.get("column") for item in category.findall("filter")}
    if "[AnnualDS].[Calculation_CategoryDisplay]" not in category_filters:
        raise ValueError("Crime category distribution is missing its parameter-aware top-10 filter.")
    for dashboard in dashboards:
        size = dashboard.find("size")
        if size is None or (size.attrib.get("minwidth"), size.attrib.get("minheight")) != ("1360", "850"):
            raise ValueError(f"Dashboard {dashboard.attrib['name']} fixed size is not 1360 x 850.")
    map_sheet = root.find("./worksheets/worksheet[@name='Chicago Geographic Crime Map']/table")
    if map_sheet is None or map_sheet.findtext("rows") != "[GeographicDS].[avg:cell_latitude:qk]" or map_sheet.findtext("cols") != "[GeographicDS].[avg:cell_longitude:qk]":
        raise ValueError("Geographic map latitude/longitude shelves are missing.")
    if page1_evidence["all_2025"]["incidents"] != 238086 or page1_evidence["theft_2025"]["incidents"] != 55198:
        raise ValueError("Source KPI evidence changed during workbook validation.")
    if page2_evidence["all_2025"]["incidents"] != page1_evidence["all_2025"]["incidents"]:
        raise ValueError("Page 2 and Page 1 2025 incident totals do not reconcile.")


def main() -> None:
    args = parse_args()
    page1_csv_dir = args.page1_csv_dir.resolve()
    page2_csv_dir = args.page2_csv_dir.resolve()
    output = args.output.resolve()
    crime_types, page1_evidence = validate_page1_source_data(page1_csv_dir)
    community_areas, districts, page2_evidence = validate_page2_source_data(page2_csv_dir)
    if not args.validate_only:
        if output.parent != (PROJECT_ROOT / "tableau").resolve():
            raise ValueError("Default generation is restricted to the repository tableau directory.")
        output.parent.mkdir(parents=True, exist_ok=True)
        tree = build_workbook(crime_types, community_areas, districts)
        ET.indent(tree, space="  ")
        temporary = output.with_suffix(".twb.tmp")
        tree.write(temporary, encoding="utf-8", xml_declaration=True)
        temporary.replace(output)
    if not output.is_file():
        raise FileNotFoundError(f"Workbook does not exist: {output}")
    validate_workbook(output, page1_csv_dir, page2_csv_dir, page1_evidence, page2_evidence)
    print(f"Validated workbook XML: {output.relative_to(PROJECT_ROOT)}")
    print(f"Worksheets: {len(SHEETS)}; dashboards: 2; data sources: 3 plus Parameters")
    print(f"Page 1 CSV rows: annual/category={page1_evidence['annual_rows']:,}; month/category={page1_evidence['monthly_rows']:,}")
    print(
        f"Page 2 CSV rows: {page2_evidence['rows']:,}; community areas={page2_evidence['community_areas']}; "
        f"district labels={page2_evidence['districts']}"
    )
    all_scope = page1_evidence["all_2025"]
    theft_scope = page1_evidence["theft_2025"]
    print(
        "2025 All Crime Types: "
        f"{all_scope['incidents']:,} incidents; "
        f"{100 * all_scope['arrests'] / all_scope['arrest_den']:.4f}% arrest; "
        f"{100 * all_scope['domestic'] / all_scope['domestic_den']:.4f}% domestic"
    )
    print(
        "2025 THEFT: "
        f"{theft_scope['incidents']:,} incidents; "
        f"{100 * theft_scope['arrests'] / theft_scope['arrest_den']:.4f}% arrest; "
        f"{100 * theft_scope['domestic'] / theft_scope['domestic_den']:.4f}% domestic"
    )
    geo_all = page2_evidence["all_2025"]
    geo_theft = page2_evidence["theft_2025"]
    print(
        f"2025 geographic source: {geo_all['incidents']:,} incidents; {geo_all['mapped']:,} mapped "
        f"({100 * geo_all['mapped'] / geo_all['incidents']:.4f}% coverage)"
    )
    print(
        f"2025 THEFT geographic source: {geo_theft['incidents']:,} incidents; {geo_theft['mapped']:,} mapped "
        f"({100 * geo_theft['mapped'] / geo_theft['incidents']:.4f}% coverage)"
    )
    print("Structural validation passed; Tableau Desktop rendering still requires manual confirmation.")


if __name__ == "__main__":
    main()
