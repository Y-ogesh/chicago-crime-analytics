#!/usr/bin/env python3
"""Generate and structurally validate the Tableau Executive Overview workbook.

The workbook intentionally keeps the annual/category and month/category CSV files as
independent Tableau data sources. Workbook parameters apply identical filters to both
sources, avoiding relationships, joins, blends, and cross-grain double counting.
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
DEFAULT_CSV_DIR = PROJECT_ROOT / "data" / "processed" / "tableau" / "page1"
DEFAULT_OUTPUT = PROJECT_ROOT / "tableau" / "chicago_crime_analytics.twb"
ANNUAL_FILE = "vw_tableau_crime_arrest_year.csv"
MONTHLY_FILE = "vw_tableau_month_category.csv"
TABLEAU_VERSION = "18.1"
TABLEAU_SOURCE_BUILD = "20262.26.0912.1023"

FIELD_CAPTIONS = {
    "reported_incident_count": "Reported Incidents",
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

SHEETS = [
    "Total Reported Crimes",
    "Arrest Percentage",
    "Domestic Incident Percentage",
    "Yearly Crime Trend",
    "Crime Category Distribution",
    "Monthly Crime Trend",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv-dir", type=Path, default=DEFAULT_CSV_DIR)
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
    return ET.SubElement(parent, "column", attrs)


def add_textscan_datasource(
    parent: ET.Element,
    *,
    name: str,
    caption: str,
    filename: str,
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
            "directory": "../data/processed/tableau/page1",
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
    remote_type = {"integer": "20", "real": "5", "date": "7", "string": "129"}
    aggregation = {"integer": "Sum", "real": "Sum", "date": "Year", "string": "Count"}
    for ordinal, (field_name, datatype) in enumerate(fields):
        record = ET.SubElement(metadata, "metadata-record", {"class": "column"})
        ET.SubElement(record, "remote-name").text = field_name
        ET.SubElement(record, "remote-type").text = remote_type[datatype]
        ET.SubElement(record, "local-name").text = f"[{field_name}]"
        ET.SubElement(record, "parent-name").text = f"[{filename.replace('.', '#')}]"
        ET.SubElement(record, "remote-alias").text = field_name
        ET.SubElement(record, "ordinal").text = str(ordinal)
        ET.SubElement(record, "local-type").text = datatype
        ET.SubElement(record, "aggregation").text = aggregation[datatype]
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


def add_parameters(parent: ET.Element, crime_types: list[str]) -> None:
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


def validate_source_data(csv_dir: Path) -> tuple[list[str], dict[str, object]]:
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


def build_workbook(crime_types: list[str]) -> ET.ElementTree:
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
    add_parameters(datasources, crime_types)
    add_textscan_datasource(datasources, name="AnnualDS", caption="Executive Category Year", filename=ANNUAL_FILE, fields=ANNUAL_FIELDS)
    add_textscan_datasource(datasources, name="MonthlyDS", caption="Executive Month Category", filename=MONTHLY_FILE, fields=MONTHLY_FIELDS)

    worksheets = ET.SubElement(root, "worksheets")
    add_kpi(worksheets, "Total Reported Crimes", "[AnnualDS].[sum:reported_incident_count:qk]", None, "Reported incident count for the selected complete calendar year and crime-type scope.")
    add_kpi(worksheets, "Arrest Percentage", "[AnnualDS].[usr:Calculation_ArrestPercentage:qk]", "Calculation_ArrestPercentage", "Share of records marked arrest=true. This is not a clearance or conviction rate.", percent=True)
    add_kpi(worksheets, "Domestic Incident Percentage", "[AnnualDS].[usr:Calculation_DomesticPercentage:qk]", "Calculation_DomesticPercentage", "Share of reported incidents marked domestic=true for the selected scope.", percent=True)
    add_yearly_trend(worksheets)
    add_category_distribution(worksheets)
    add_monthly_trend(worksheets)
    add_dashboard(root)
    add_windows(root)
    return ET.ElementTree(root)


def validate_workbook(output: Path, csv_dir: Path, evidence: dict[str, object]) -> None:
    tree = ET.parse(output)
    root = tree.getroot()
    if root.tag != "workbook" or root.attrib.get("version") != TABLEAU_VERSION:
        raise ValueError("Unexpected workbook root or Tableau workbook version.")
    sources = {item.attrib.get("name"): item for item in root.findall("./datasources/datasource")}
    if set(sources) != {"Parameters", "AnnualDS", "MonthlyDS"}:
        raise ValueError(f"Unexpected workbook data sources: {sorted(sources)}")
    worksheet_names = [item.attrib["name"] for item in root.findall("./worksheets/worksheet")]
    if worksheet_names != SHEETS:
        raise ValueError(f"Worksheet definitions differ from specification: {worksheet_names}")
    dashboards = root.findall("./dashboards/dashboard")
    if len(dashboards) != 1 or dashboards[0].attrib.get("name") != "Executive Overview":
        raise ValueError("Executive Overview dashboard definition is missing.")
    zone_names = {zone.attrib.get("name") for zone in dashboards[0].findall(".//zone") if zone.attrib.get("name")}
    if not set(SHEETS).issubset(zone_names):
        raise ValueError("One or more worksheets are not placed on the dashboard.")
    params = {column.attrib.get("name"): column for column in sources["Parameters"].findall("column")}
    if params["[pSelectedYear]"].attrib.get("value") != q("2025") or params["[pCrimeType]"].attrib.get("value") != q("All Crime Types"):
        raise ValueError("Default Tableau parameter values are incorrect.")
    connections = root.findall(".//connection[@class='textscan']")
    expected_files = {ANNUAL_FILE, MONTHLY_FILE}
    if {connection.attrib.get("filename") for connection in connections} != expected_files:
        raise ValueError("Text-file connection references are incomplete.")
    for connection in connections:
        referenced = (output.parent / connection.attrib["directory"] / connection.attrib["filename"]).resolve()
        expected = (csv_dir / connection.attrib["filename"]).resolve()
        if referenced != expected or not referenced.is_file():
            raise ValueError(f"Workbook reference does not resolve to the validated CSV: {referenced}")
    formulas = {calc.attrib.get("formula") for calc in root.findall(".//calculation")}
    required_formulas = {
        "STR([crime_year]) = [Parameters].[pSelectedYear]",
        '[Parameters].[pCrimeType] = "All Crime Types" OR [primary_type] = [Parameters].[pCrimeType]',
        '[Parameters].[pCrimeType] <> "All Crime Types" OR [incident_volume_rank] <= 10',
        "IF SUM([arrest_indicator_denominator]) = 0 THEN NULL ELSE 100.0 * SUM([arrest_count]) / SUM([arrest_indicator_denominator]) END",
        "IF SUM([domestic_indicator_denominator]) = 0 THEN NULL ELSE 100.0 * SUM([domestic_count]) / SUM([domestic_indicator_denominator]) END",
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
    dashboard = dashboards[0]
    size = dashboard.find("size")
    if size is None or (size.attrib.get("minwidth"), size.attrib.get("minheight")) != ("1360", "850"):
        raise ValueError("Dashboard fixed size is not 1360 x 850.")
    if evidence["all_2025"]["incidents"] != 238086 or evidence["theft_2025"]["incidents"] != 55198:
        raise ValueError("Source KPI evidence changed during workbook validation.")


def main() -> None:
    args = parse_args()
    csv_dir = args.csv_dir.resolve()
    output = args.output.resolve()
    crime_types, evidence = validate_source_data(csv_dir)
    if not args.validate_only:
        if output.parent != (PROJECT_ROOT / "tableau").resolve():
            raise ValueError("Default generation is restricted to the repository tableau directory.")
        output.parent.mkdir(parents=True, exist_ok=True)
        tree = build_workbook(crime_types)
        ET.indent(tree, space="  ")
        temporary = output.with_suffix(".twb.tmp")
        tree.write(temporary, encoding="utf-8", xml_declaration=True)
        temporary.replace(output)
    if not output.is_file():
        raise FileNotFoundError(f"Workbook does not exist: {output}")
    validate_workbook(output, csv_dir, evidence)
    print(f"Validated workbook XML: {output.relative_to(PROJECT_ROOT)}")
    print(f"Worksheets: {len(SHEETS)}; dashboards: 1; data sources: 2 plus Parameters")
    print(f"CSV rows: annual/category={evidence['annual_rows']:,}; month/category={evidence['monthly_rows']:,}")
    all_scope = evidence["all_2025"]
    theft_scope = evidence["theft_2025"]
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
    print("Structural validation passed; Tableau Desktop rendering still requires manual confirmation.")


if __name__ == "__main__":
    main()
