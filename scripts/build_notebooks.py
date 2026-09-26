#!/usr/bin/env python3
"""Build the two version-controlled Milestone 7 notebooks.

Notebook source is kept here so cell order and content can be reviewed and
recreated without editing notebook JSON by hand. Execute the generated
notebooks with Jupyter after running this script.
"""

from pathlib import Path
from textwrap import dedent

import nbformat as nbf


PROJECT_ROOT = Path(__file__).resolve().parents[1]
NOTEBOOK_DIR = PROJECT_ROOT / "notebooks"
NOTEBOOK_DIR.mkdir(parents=True, exist_ok=True)


def markdown(source: str):
    return nbf.v4.new_markdown_cell(dedent(source).strip())


def code(source: str):
    return nbf.v4.new_code_cell(dedent(source).strip())


SETUP_CODE = r'''
from pathlib import Path
import os

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from dotenv import load_dotenv
from IPython.display import display
from sqlalchemy import URL, create_engine, text

%matplotlib inline


def find_project_root() -> Path:
    """Find the repository root whether execution starts there or in notebooks/."""
    candidates = [Path.cwd(), *Path.cwd().parents]
    for candidate in candidates:
        if (candidate / ".env.example").exists() and (candidate / "sql").is_dir():
            return candidate
    raise FileNotFoundError("Could not locate the project root containing .env.example and sql/.")


PROJECT_ROOT = find_project_root()
load_dotenv(PROJECT_ROOT / ".env", override=False)

pd.set_option("display.max_columns", 30)
pd.set_option("display.float_format", lambda value: f"{value:,.4f}")

print("Project root located from the current working directory.")
print(f"Pandas: {pd.__version__} | NumPy: {np.__version__} | Matplotlib: {plt.matplotlib.__version__}")
'''


CONNECTION_CODE = r'''
def build_read_only_engine():
    """Create a read-only PostgreSQL engine without printing credentials."""
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

    engine = create_engine(url, future=True, connect_args=connect_args)
    return engine, database, host


engine, database_name, database_host = build_read_only_engine()
with engine.connect() as connection:
    connection_check = pd.read_sql_query(
        text("""
            SELECT current_database() AS database_name,
                   current_setting('transaction_read_only') AS transaction_read_only
        """),
        connection,
    )

assert connection_check.loc[0, "transaction_read_only"] == "on"
print(
    f"Connected securely to {database_name} via "
    f"{'host ' + database_host if database_host else 'local PostgreSQL socket'}; "
    "transactions are read-only."
)
display(connection_check)
'''


BASE_LOAD_CODE = r'''
BASE_QUERY = text("""
    SELECT source_id,
           crime_date,
           crime_year,
           crime_month,
           month_name,
           season,
           day_of_week_num,
           day_of_week,
           hour_of_day,
           primary_type,
           arrest,
           domestic,
           community_area,
           community_area_eligible_flag
    FROM public.clean_chicago_crimes
    ORDER BY source_id
""")

records = pd.read_sql_query(BASE_QUERY, engine, parse_dates=["crime_date"])

integer_columns = [
    "source_id", "crime_year", "crime_month", "day_of_week_num", "hour_of_day"
]
for column in integer_columns:
    records[column] = pd.to_numeric(records[column], errors="raise")

print(f"Loaded {len(records):,} clean records with {records['source_id'].nunique():,} unique source IDs.")
print(f"Date coverage: {records['crime_date'].min().date()} through {records['crime_date'].max().date()}")
display(records.head(3))
'''


def build_validation_notebook():
    notebook = nbf.v4.new_notebook()
    notebook["metadata"] = {
        "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
        "language_info": {"name": "python", "version": "3.9"},
    }
    notebook["cells"] = [
        markdown('''
        # Chicago Crime Analytics — Python Data Validation

        This notebook independently aggregates record-level data from
        `public.clean_chicago_crimes` with Pandas and reconciles the results to
        the Milestone 6 PostgreSQL analytical views.

        **Metric contract:** counts are reported incident records, not
        population-normalized crime rates. Annual comparisons use the complete
        calendar years 2023–2025. Arrest percentages are not clearance or
        conviction rates. Community-area percentage ranks require at least 500
        prior-year incidents; absolute ranks include all 77 official areas.
        ''') ,
        markdown('''
        ## 1. Environment and secure database connection

        Connection values come from environment variables or a local `.env`
        file excluded by Git. Credentials and connection URLs are never printed.
        PostgreSQL sessions are forced to read-only mode.
        '''),
        code(SETUP_CODE),
        code(CONNECTION_CODE),
        markdown('''
        ## 2. Load the canonical record-level population

        The ordered query loads only fields needed for validation. No analytical
        view is used to construct the Pandas results below.
        '''),
        code(BASE_LOAD_CODE),
        code(r'''
        sql_kpis = pd.read_sql_query(text("SELECT * FROM public.vw_executive_kpis"), engine)
        sql_yearly = pd.read_sql_query(
            text("SELECT * FROM public.vw_yearly_crime_trends ORDER BY crime_year"), engine
        )
        sql_community = pd.read_sql_query(
            text("""
                SELECT *
                FROM public.vw_community_area_yoy
                ORDER BY current_year, community_area
            """),
            engine,
        )
        community_lookup = pd.read_sql_query(
            text("SELECT * FROM public.vw_community_area_lookup ORDER BY community_area"), engine
        )

        executive_validation = pd.DataFrame({
            "metric": [
                "record_count", "distinct_source_ids", "first_crime_date", "last_crime_date",
                "community_area_eligible_count"
            ],
            "python_value": [
                len(records),
                records["source_id"].nunique(),
                str(records["crime_date"].min().date()),
                str(records["crime_date"].max().date()),
                int(records["community_area_eligible_flag"].sum()),
            ],
            "sql_value": [
                int(sql_kpis.loc[0, "reported_incident_count"]),
                int(sql_kpis.loc[0, "reported_incident_count"]),
                str(sql_kpis.loc[0, "first_crime_date"]),
                str(sql_kpis.loc[0, "last_crime_date"]),
                int(sql_kpis.loc[0, "community_area_eligible_count"]),
            ],
        })
        executive_validation["matches"] = (
            executive_validation["python_value"].astype(str)
            == executive_validation["sql_value"].astype(str)
        )
        display(executive_validation)
        '''),
        markdown('''
        ## 3. Independent annual totals and year-over-year changes

        Pandas groups the record-level table by year, then applies the documented
        formula `(current - previous) / previous * 100`. SQL values are loaded
        only after the independent calculation is complete.
        '''),
        code(r'''
        py_yearly = (
            records.groupby("crime_year", as_index=False)
            .size()
            .rename(columns={"size": "python_incident_count"})
            .sort_values("crime_year")
            .reset_index(drop=True)
        )
        py_yearly["python_previous_count"] = py_yearly["python_incident_count"].shift(1)
        py_yearly["python_absolute_change"] = (
            py_yearly["python_incident_count"] - py_yearly["python_previous_count"]
        )
        py_yearly["python_percentage_change"] = np.where(
            py_yearly["python_previous_count"].eq(0),
            np.nan,
            100.0 * py_yearly["python_absolute_change"] / py_yearly["python_previous_count"],
        )

        annual_validation = py_yearly.merge(
            sql_yearly[[
                "crime_year", "reported_incident_count", "previous_year_incident_count",
                "absolute_change", "percentage_change"
            ]],
            on="crime_year",
            how="outer",
            validate="one_to_one",
        )
        numeric_sql_columns = [
            "reported_incident_count", "previous_year_incident_count",
            "absolute_change", "percentage_change"
        ]
        for column in numeric_sql_columns:
            annual_validation[column] = pd.to_numeric(annual_validation[column], errors="coerce")

        annual_validation["count_difference"] = (
            annual_validation["python_incident_count"]
            - annual_validation["reported_incident_count"]
        )
        annual_validation["yoy_percentage_difference"] = (
            annual_validation["python_percentage_change"]
            - annual_validation["percentage_change"]
        )
        display(annual_validation.round(10))
        '''),
        markdown('''
        ## 4. Independent community-area comparisons and ranks

        Pandas builds a complete year-by-area grid from the 77-area lookup,
        aggregates valid source community-area identifiers, calculates adjacent
        changes, and reproduces both ranking methods. Missing or invalid area
        identifiers remain in citywide validation but are excluded here.
        '''),
        code(r'''
        years = np.sort(records["crime_year"].unique())
        grid = pd.MultiIndex.from_product(
            [years, community_lookup["community_area"].astype(int)],
            names=["crime_year", "community_area"],
        ).to_frame(index=False)

        eligible_records = records.loc[records["community_area_eligible_flag"]].copy()
        py_area_counts = (
            eligible_records.groupby(["crime_year", "community_area"], as_index=False)
            .size()
            .rename(columns={"size": "current_year_incident_count"})
        )
        py_area = (
            grid.merge(py_area_counts, on=["crime_year", "community_area"], how="left")
            .merge(community_lookup, on="community_area", how="left", validate="many_to_one")
            .sort_values(["community_area", "crime_year"])
            .reset_index(drop=True)
        )
        py_area["current_year_incident_count"] = (
            py_area["current_year_incident_count"].fillna(0).astype("int64")
        )
        py_area["previous_year"] = py_area.groupby("community_area")["crime_year"].shift(1)
        py_area["previous_year_incident_count"] = (
            py_area.groupby("community_area")["current_year_incident_count"].shift(1)
        )
        py_area = py_area.loc[py_area["previous_year"].notna()].copy()
        py_area = py_area.rename(columns={"crime_year": "current_year"})
        py_area["previous_year"] = py_area["previous_year"].astype(int)
        py_area["absolute_change"] = (
            py_area["current_year_incident_count"] - py_area["previous_year_incident_count"]
        )
        py_area["percentage_change"] = np.where(
            py_area["previous_year_incident_count"].eq(0),
            np.nan,
            100.0 * py_area["absolute_change"] / py_area["previous_year_incident_count"],
        )
        py_area["percentage_rank_eligible"] = py_area["previous_year_incident_count"].ge(500)
        py_area["absolute_change_rank"] = (
            py_area.groupby("current_year")["absolute_change"]
            .rank(method="min", ascending=False)
        )
        py_area["absolute_decrease_rank"] = (
            py_area.groupby("current_year")["absolute_change"]
            .rank(method="min", ascending=True)
        )
        eligible_mask = py_area["percentage_rank_eligible"] & py_area["percentage_change"].notna()
        py_area.loc[eligible_mask, "percentage_change_rank"] = (
            py_area.loc[eligible_mask]
            .groupby("current_year")["percentage_change"]
            .rank(method="min", ascending=False)
        )
        py_area.loc[eligible_mask, "percentage_decrease_rank"] = (
            py_area.loc[eligible_mask]
            .groupby("current_year")["percentage_change"]
            .rank(method="min", ascending=True)
        )

        comparison_columns = [
            "community_area", "current_year", "previous_year",
            "current_year_incident_count", "previous_year_incident_count",
            "absolute_change", "percentage_change", "percentage_rank_eligible",
            "percentage_change_rank", "percentage_decrease_rank",
            "absolute_change_rank", "absolute_decrease_rank"
        ]
        area_validation = py_area[comparison_columns].merge(
            sql_community[comparison_columns],
            on=["community_area", "current_year"],
            suffixes=("_python", "_sql"),
            validate="one_to_one",
        )

        value_columns = [
            "previous_year", "current_year_incident_count", "previous_year_incident_count",
            "absolute_change", "percentage_change", "percentage_change_rank",
            "percentage_decrease_rank", "absolute_change_rank", "absolute_decrease_rank"
        ]
        for column in value_columns:
            area_validation[f"{column}_python"] = pd.to_numeric(
                area_validation[f"{column}_python"], errors="coerce"
            )
            area_validation[f"{column}_sql"] = pd.to_numeric(
                area_validation[f"{column}_sql"], errors="coerce"
            )

        area_differences = pd.DataFrame({
            "metric": value_columns,
            "max_absolute_difference": [
                np.nanmax(np.abs(
                    area_validation[f"{column}_python"].fillna(-1).to_numpy(dtype=float)
                    - area_validation[f"{column}_sql"].fillna(-1).to_numpy(dtype=float)
                ))
                for column in value_columns
            ],
        })
        display(area_differences)
        '''),
        code(r'''
        forest_glen = py_area.loc[
            (py_area["community_area"].eq(12)) & (py_area["current_year"].eq(2025)),
            [
                "community_area_name", "previous_year", "current_year",
                "previous_year_incident_count", "current_year_incident_count",
                "absolute_change", "percentage_change", "percentage_decrease_rank",
                "absolute_decrease_rank"
            ],
        ]
        austin = py_area.loc[
            (py_area["community_area"].eq(25)) & (py_area["current_year"].eq(2025)),
            [
                "community_area_name", "previous_year", "current_year",
                "previous_year_incident_count", "current_year_incident_count",
                "absolute_change", "percentage_change", "percentage_decrease_rank",
                "absolute_decrease_rank"
            ],
        ]
        display(pd.concat([forest_glen, austin], ignore_index=True).round(4))
        '''),
        markdown('''
        ## 5. Validation gate

        Every check must be true. An exception stops notebook execution if any
        SQL/Python discrepancy exceeds the stated numeric tolerance.
        '''),
        code(r'''
        annual_pct_match = np.allclose(
            annual_validation["python_percentage_change"].dropna().to_numpy(dtype=float),
            annual_validation["percentage_change"].dropna().to_numpy(dtype=float),
            rtol=0,
            atol=1e-10,
        )
        area_value_match = all(
            np.allclose(
                area_validation[f"{column}_python"].fillna(-1).to_numpy(dtype=float),
                area_validation[f"{column}_sql"].fillna(-1).to_numpy(dtype=float),
                rtol=0,
                atol=1e-10,
            )
            for column in value_columns
        )
        area_eligibility_match = (
            area_validation["percentage_rank_eligible_python"].astype(bool).to_numpy()
            == area_validation["percentage_rank_eligible_sql"].astype(bool).to_numpy()
        ).all()

        checks = {
            "Executive count/date/coverage values match": bool(executive_validation["matches"].all()),
            "Source IDs are unique in Pandas": records["source_id"].nunique() == len(records),
            "Annual counts match exactly": annual_validation["count_difference"].fillna(0).eq(0).all(),
            "Annual YoY percentages match within 1e-10": bool(annual_pct_match),
            "Community comparison row count is 154": len(area_validation) == 154,
            "Each comparison year contains 77 areas": py_area.groupby("current_year").size().eq(77).all(),
            "Community values and ranks match within 1e-10": bool(area_value_match),
            "Community percentage-rank eligibility matches": bool(area_eligibility_match),
            "Forest Glen 2025 count pair matches 545 to 409": (
                int(forest_glen.iloc[0]["previous_year_incident_count"]) == 545
                and int(forest_glen.iloc[0]["current_year_incident_count"]) == 409
            ),
            "Austin is 2025 absolute-decrease rank 1": int(austin.iloc[0]["absolute_decrease_rank"]) == 1,
        }
        validation_summary = pd.DataFrame(
            {"check": checks.keys(), "passed": checks.values()}
        )
        display(validation_summary)

        failed_checks = validation_summary.loc[~validation_summary["passed"], "check"].tolist()
        if failed_checks:
            raise AssertionError(f"Validation failed: {failed_checks}")

        print(f"PASS: all {len(validation_summary)} SQL/Python validation checks succeeded.")
        print("Maximum annual count difference: 0")
        print(f"Maximum community-area numeric difference: {area_differences['max_absolute_difference'].max():.12f}")
        '''),
        markdown('''
        ## Conclusion

        A successful final cell demonstrates that Pandas independently reproduced
        the Milestone 6 citywide and community-area results from record-level
        data. It does not prove the source is complete or causal; it confirms
        implementation consistency for the documented extract and definitions.
        '''),
        code('engine.dispose()\nprint("Database engine disposed.")'),
    ]
    return notebook


def build_eda_notebook():
    notebook = nbf.v4.new_notebook()
    notebook["metadata"] = {
        "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
        "language_info": {"name": "python", "version": "3.9"},
    }
    notebook["cells"] = [
        markdown('''
        # Chicago Crime Analytics — Exploratory Analysis

        This notebook uses Pandas, NumPy, and Matplotlib to explore temporal,
        category, indicator, and community-area patterns in 761,563 official
        reported-incident records covering the complete calendar years
        2023–2025.

        All results are descriptive. Counts are not population-normalized crime
        rates, arrest percentages are not clearance or conviction rates, source
        timestamps may be estimated, and observed patterns do not establish
        causation.
        '''),
        markdown('## 1. Environment and secure read-only database connection'),
        code(SETUP_CODE),
        code(CONNECTION_CODE),
        markdown('''
        ## 2. Load analytical fields from PostgreSQL

        The notebook reads the canonical clean table and performs its own Pandas
        aggregations rather than using SQL view totals as plotted inputs.
        '''),
        code(BASE_LOAD_CODE),
        code(r'''
        FIGURE_DIR = PROJECT_ROOT / "images" / "python"
        FIGURE_DIR.mkdir(parents=True, exist_ok=True)

        BLUE = "#1f77b4"
        ORANGE = "#ff7f0e"
        GREEN = "#2ca02c"
        RED = "#d62728"
        PURPLE = "#9467bd"
        GRAY = "#6b7280"

        plt.rcParams.update({
            "figure.dpi": 110,
            "axes.titleweight": "bold",
            "axes.grid": True,
            "grid.alpha": 0.25,
            "axes.spines.top": False,
            "axes.spines.right": False,
        })


        def save_figure(fig, filename):
            path = FIGURE_DIR / filename
            fig.text(
                0.01,
                0.01,
                "Source: City of Chicago Crimes - 2001 to Present (ijzp-q8t2); complete years 2023-2025.",
                ha="left",
                fontsize=7.5,
                color=GRAY,
            )
            fig.tight_layout(rect=[0, 0.045, 1, 1])
            fig.savefig(path, dpi=160, bbox_inches="tight", facecolor="white")
            plt.show()
            plt.close(fig)
            print(f"Saved {path.relative_to(PROJECT_ROOT)}")
        '''),
        markdown('## 3. Complete-year trend and year-over-year change'),
        code(r'''
        yearly = (
            records.groupby("crime_year", as_index=False)
            .size()
            .rename(columns={"size": "reported_incident_count"})
            .sort_values("crime_year")
        )
        yearly["previous_year_count"] = yearly["reported_incident_count"].shift(1)
        yearly["absolute_change"] = yearly["reported_incident_count"] - yearly["previous_year_count"]
        yearly["percentage_change"] = np.where(
            yearly["previous_year_count"].eq(0),
            np.nan,
            100.0 * yearly["absolute_change"] / yearly["previous_year_count"],
        )
        display(yearly.round(4))

        fig, ax = plt.subplots(figsize=(8.5, 4.8))
        bars = ax.bar(yearly["crime_year"].astype(str), yearly["reported_incident_count"], color=BLUE)
        ax.bar_label(bars, labels=[f"{value:,}" for value in yearly["reported_incident_count"]], padding=4)
        ax.set_title("Chicago Reported Incidents by Complete Calendar Year")
        ax.set_xlabel("Calendar year")
        ax.set_ylabel("Reported incident count")
        ax.set_ylim(0, yearly["reported_incident_count"].max() * 1.13)
        ax.ticklabel_format(axis="y", style="plain")
        save_figure(fig, "python_yearly_trend.png")
        '''),
        markdown('''
        **Interpretation:** Both adjacent-year comparisons declined, with the
        larger change occurring in 2025. This is a change in reported records,
        not evidence about why reporting or incident volume changed.
        '''),
        markdown('## 4. Monthly trend, rolling average, and seasonal pattern'),
        code(r'''
        monthly = (
            records.assign(month_start=records["crime_date"].dt.to_period("M").dt.to_timestamp())
            .groupby("month_start", as_index=False)
            .size()
            .rename(columns={"size": "reported_incident_count"})
            .sort_values("month_start")
        )
        monthly["three_month_rolling_average"] = (
            monthly["reported_incident_count"].rolling(window=3, min_periods=1).mean()
        )
        monthly["crime_year"] = monthly["month_start"].dt.year
        monthly["crime_month"] = monthly["month_start"].dt.month
        monthly["same_month_previous_year_count"] = (
            monthly.groupby("crime_month")["reported_incident_count"].shift(1)
        )
        monthly["same_month_change"] = (
            monthly["reported_incident_count"] - monthly["same_month_previous_year_count"]
        )

        months_lower_2025 = int(
            monthly.loc[monthly["crime_year"].eq(2025), "same_month_change"].lt(0).sum()
        )
        print(f"Months in 2025 below the corresponding 2024 month: {months_lower_2025} of 12")

        fig, ax = plt.subplots(figsize=(11, 5.2))
        ax.plot(monthly["month_start"], monthly["reported_incident_count"], color=GRAY,
                marker="o", markersize=3, linewidth=1.2, label="Monthly count")
        ax.plot(monthly["month_start"], monthly["three_month_rolling_average"], color=BLUE,
                linewidth=2.5, label="Trailing 3-month average")
        ax.set_title("Monthly Reported Incidents and Trailing Three-Month Average")
        ax.set_xlabel("Incident month")
        ax.set_ylabel("Reported incident count")
        ax.legend(frameon=False)
        save_figure(fig, "python_monthly_rolling_trend.png")
        '''),
        code(r'''
        season_order = ["Winter", "Spring", "Summer", "Fall"]
        seasonal = (
            records.groupby(["crime_year", "season"], observed=True)
            .size()
            .rename("reported_incident_count")
            .reset_index()
        )
        seasonal["season"] = pd.Categorical(seasonal["season"], categories=season_order, ordered=True)
        seasonal = seasonal.sort_values(["crime_year", "season"])
        seasonal["year_total"] = seasonal.groupby("crime_year")["reported_incident_count"].transform("sum")
        seasonal["percentage_of_year"] = 100.0 * seasonal["reported_incident_count"] / seasonal["year_total"]
        display(seasonal.round(4))

        seasonal_pivot = seasonal.pivot(index="season", columns="crime_year", values="reported_incident_count").reindex(season_order)
        fig, ax = plt.subplots(figsize=(9, 5))
        seasonal_pivot.plot(kind="bar", ax=ax, color=[BLUE, ORANGE, GREEN], width=0.78)
        ax.set_title("Reported Incidents by Meteorological Season and Year")
        ax.set_xlabel("Season")
        ax.set_ylabel("Reported incident count")
        ax.tick_params(axis="x", rotation=0)
        ax.legend(title="Calendar year", frameon=False)
        save_figure(fig, "python_seasonal_by_year.png")
        '''),
        markdown('''
        **Interpretation:** The rolling series makes the broad annual decline
        visible without hiding monthly variation. Seasonal counts remain
        unadjusted for season length, weather, mobility, or other exposure.
        '''),
        markdown('## 5. Day-of-week and hourly patterns'),
        code(r'''
        daily = (
            records.groupby(["crime_date", "day_of_week_num", "day_of_week"], as_index=False)
            .size()
            .rename(columns={"size": "daily_incident_count"})
        )
        weekday = (
            daily.groupby(["day_of_week_num", "day_of_week"], as_index=False)
            .agg(
                observed_dates=("crime_date", "nunique"),
                average_per_observed_date=("daily_incident_count", "mean"),
                reported_incident_count=("daily_incident_count", "sum"),
            )
            .sort_values("day_of_week_num")
        )
        hourly = (
            records.groupby("hour_of_day", as_index=False)
            .size()
            .rename(columns={"size": "reported_incident_count"})
        )
        hourly["percentage_of_total"] = 100.0 * hourly["reported_incident_count"] / len(records)
        display(weekday.round(2))
        display(hourly.sort_values("reported_incident_count", ascending=False).head(5).round(4))

        fig, axes = plt.subplots(1, 2, figsize=(13, 4.8))
        axes[0].bar(weekday["day_of_week"], weekday["average_per_observed_date"], color=BLUE)
        axes[0].set_title("Average Reported Incidents per Observed Date")
        axes[0].set_xlabel("Day of week (Monday–Sunday)")
        axes[0].set_ylabel("Average reported incidents")
        axes[0].tick_params(axis="x", rotation=35)

        axes[1].plot(hourly["hour_of_day"], hourly["percentage_of_total"], color=ORANGE, marker="o")
        axes[1].set_title("Share of Reported Incidents by Recorded Hour")
        axes[1].set_xlabel("Hour of day (0–23)")
        axes[1].set_ylabel("Percentage of all records")
        axes[1].set_xticks(range(0, 24, 3))
        save_figure(fig, "python_weekday_hourly_patterns.png")
        '''),
        markdown('''
        **Interpretation:** Per-date weekday averages avoid comparing five
        weekdays directly with two weekend days. Exact-hour results require
        caution because source incident times may be estimated; the midnight
        concentration may partly reflect recording practices.
        '''),
        markdown('## 6. Crime-category trends'),
        code(r'''
        category_totals = records["primary_type"].value_counts()
        top_categories = category_totals.head(8).index.tolist()
        category_year = (
            records.loc[records["primary_type"].isin(top_categories)]
            .groupby(["crime_year", "primary_type"], as_index=False)
            .size()
            .rename(columns={"size": "reported_incident_count"})
        )
        category_pivot = (
            category_year.pivot(index="crime_year", columns="primary_type", values="reported_incident_count")
            .reindex(columns=top_categories)
        )
        display(category_pivot)

        fig, ax = plt.subplots(figsize=(11, 6))
        for category in top_categories:
            ax.plot(category_pivot.index, category_pivot[category], marker="o", linewidth=2, label=category.title())
        ax.set_title("Annual Trends for the Eight Highest-Volume Source Crime Types")
        ax.set_xlabel("Complete calendar year")
        ax.set_ylabel("Reported incident count")
        ax.set_xticks(category_pivot.index)
        ax.legend(frameon=False, ncol=2, fontsize=9)
        save_figure(fig, "python_category_yearly_trends.png")
        '''),
        markdown('''
        ### Category-specific calendar-month profiles

        To move beyond repeating citywide SQL totals, the next analysis compares
        each leading category's distribution across calendar months. Each row
        sums to 100%, so the heatmap emphasizes within-category timing rather
        than category size.
        '''),
        code(r'''
        profile_categories = category_totals.head(6).index.tolist()
        category_month = (
            records.loc[records["primary_type"].isin(profile_categories)]
            .groupby(["primary_type", "crime_month"], as_index=False)
            .size()
            .rename(columns={"size": "reported_incident_count"})
        )
        category_month["category_total"] = (
            category_month.groupby("primary_type")["reported_incident_count"].transform("sum")
        )
        category_month["percentage_of_category_total"] = (
            100.0 * category_month["reported_incident_count"] / category_month["category_total"]
        )
        profile = (
            category_month.pivot(
                index="primary_type", columns="crime_month", values="percentage_of_category_total"
            )
            .reindex(profile_categories)
        )
        month_labels = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        peak_months = pd.DataFrame({
            "primary_type": profile.index,
            "peak_month": [month_labels[int(month) - 1] for month in profile.idxmax(axis=1)],
            "peak_share_pct": profile.max(axis=1).to_numpy(),
            "lowest_month": [month_labels[int(month) - 1] for month in profile.idxmin(axis=1)],
            "lowest_share_pct": profile.min(axis=1).to_numpy(),
        })
        display(peak_months.round(4))

        fig, ax = plt.subplots(figsize=(11, 5.2))
        image = ax.imshow(profile.to_numpy(), aspect="auto", cmap="Blues")
        ax.set_title("Calendar-Month Profile Within Leading Crime Types")
        ax.set_xlabel("Calendar month")
        ax.set_ylabel("Source primary type")
        ax.set_xticks(np.arange(12), labels=month_labels)
        ax.set_yticks(np.arange(len(profile.index)), labels=[label.title() for label in profile.index])
        colorbar = fig.colorbar(image, ax=ax)
        colorbar.set_label("Percentage of category's 2023–2025 records")
        save_figure(fig, "python_category_monthly_profile.png")
        '''),
        markdown('''
        **Interpretation:** Category profiles are descriptive and pooled across
        three complete years. They are not adjusted for month length and should
        not be interpreted as weather effects or forecasts.
        '''),
        markdown('## 7. Arrest and domestic indicator percentages'),
        code(r'''
        indicator_rows = []
        for crime_year, group in records.groupby("crime_year"):
            arrest_denominator = int(group["arrest"].notna().sum())
            domestic_denominator = int(group["domestic"].notna().sum())
            arrest_count = int(group["arrest"].eq(True).sum())
            domestic_count = int(group["domestic"].eq(True).sum())
            indicator_rows.append({
                "crime_year": int(crime_year),
                "arrest_count": arrest_count,
                "arrest_denominator": arrest_denominator,
                "arrest_percentage": 100.0 * arrest_count / arrest_denominator if arrest_denominator else np.nan,
                "domestic_count": domestic_count,
                "domestic_denominator": domestic_denominator,
                "domestic_percentage": 100.0 * domestic_count / domestic_denominator if domestic_denominator else np.nan,
            })
        indicators = pd.DataFrame(indicator_rows).sort_values("crime_year")
        display(indicators.round(4))

        fig, ax = plt.subplots(figsize=(8.5, 4.8))
        ax.plot(indicators["crime_year"], indicators["arrest_percentage"], marker="o", linewidth=2.5,
                color=BLUE, label="Arrest indicator")
        ax.plot(indicators["crime_year"], indicators["domestic_percentage"], marker="o", linewidth=2.5,
                color=PURPLE, label="Domestic indicator")
        ax.set_title("Annual Arrest and Domestic Indicator Percentages")
        ax.set_xlabel("Complete calendar year")
        ax.set_ylabel("Percentage of non-null indicator records")
        ax.set_xticks(indicators["crime_year"])
        ax.legend(frameon=False)
        save_figure(fig, "python_arrest_domestic_trends.png")
        '''),
        markdown('''
        **Interpretation:** The arrest indicator increased while the domestic
        indicator also represented a larger share of the smaller 2025 record
        total. Neither series establishes a case outcome or cause.
        '''),
        markdown('## 8. Community-area comparisons'),
        code(r'''
        community_lookup = pd.read_sql_query(
            text("SELECT * FROM public.vw_community_area_lookup ORDER BY community_area"), engine
        )
        area_counts = (
            records.loc[records["community_area_eligible_flag"]]
            .groupby(["crime_year", "community_area"], as_index=False)
            .size()
            .rename(columns={"size": "reported_incident_count"})
        )
        area_2024_2025 = (
            area_counts.loc[area_counts["crime_year"].isin([2024, 2025])]
            .pivot(index="community_area", columns="crime_year", values="reported_incident_count")
            .reindex(community_lookup["community_area"])
            .fillna(0)
            .rename(columns={2024: "previous_count", 2025: "current_count"})
            .reset_index()
            .merge(community_lookup, on="community_area", validate="one_to_one")
        )
        area_2024_2025["absolute_change"] = (
            area_2024_2025["current_count"] - area_2024_2025["previous_count"]
        )
        area_2024_2025["percentage_change"] = np.where(
            area_2024_2025["previous_count"].eq(0),
            np.nan,
            100.0 * area_2024_2025["absolute_change"] / area_2024_2025["previous_count"],
        )
        area_2024_2025["percentage_rank_eligible"] = area_2024_2025["previous_count"].ge(500)

        direction_summary = pd.Series({
            "areas_decreased": int(area_2024_2025["absolute_change"].lt(0).sum()),
            "areas_increased": int(area_2024_2025["absolute_change"].gt(0).sum()),
            "areas_unchanged": int(area_2024_2025["absolute_change"].eq(0).sum()),
        })
        display(direction_summary.to_frame("community_area_count"))

        largest_decreases = area_2024_2025.nsmallest(10, "absolute_change").sort_values("absolute_change")
        forest_and_austin = area_2024_2025.loc[
            area_2024_2025["community_area"].isin([12, 25]),
            ["community_area", "community_area_name", "previous_count", "current_count",
             "absolute_change", "percentage_change", "percentage_rank_eligible"],
        ]
        display(forest_and_austin.round(4))

        fig, axes = plt.subplots(1, 2, figsize=(14, 5.8))
        axes[0].barh(
            largest_decreases["community_area_name"].str.title(),
            largest_decreases["absolute_change"],
            color=RED,
        )
        axes[0].set_title("Ten Largest Absolute Area Decreases, 2024–2025")
        axes[0].set_xlabel("Change in reported incident count")
        axes[0].set_ylabel("Community area")

        eligible = area_2024_2025.loc[area_2024_2025["percentage_rank_eligible"]]
        axes[1].scatter(
            eligible["absolute_change"], eligible["percentage_change"],
            s=np.sqrt(eligible["previous_count"]) * 4,
            alpha=0.55, color=BLUE, edgecolor="white", linewidth=0.5,
        )
        for area_number, color in [(12, ORANGE), (25, RED)]:
            point = eligible.loc[eligible["community_area"].eq(area_number)].iloc[0]
            axes[1].scatter(point["absolute_change"], point["percentage_change"],
                            s=110, color=color, edgecolor="black", linewidth=0.7, zorder=3)
            axes[1].annotate(point["community_area_name"].title(),
                             (point["absolute_change"], point["percentage_change"]),
                             xytext=(6, 6), textcoords="offset points", fontsize=9)
        axes[1].axhline(0, color="black", linewidth=0.8)
        axes[1].axvline(0, color="black", linewidth=0.8)
        axes[1].set_title("Absolute versus Percentage Change (Baseline ≥500)")
        axes[1].set_xlabel("Absolute change in reported incidents")
        axes[1].set_ylabel("Percentage change")
        save_figure(fig, "python_community_area_yoy.png")
        '''),
        markdown('''
        **Interpretation:** Forest Glen's proportional decline is large relative
        to its baseline, while Austin's absolute decline represents many more
        records. Community-area counts do not measure population-normalized risk.
        '''),
        markdown('## 9. Reproducible EDA summary'),
        code(r'''
        summary = pd.Series({
            "records_analyzed": len(records),
            "complete_years": records["crime_year"].nunique(),
            "2024_to_2025_absolute_change": int(yearly.loc[yearly["crime_year"].eq(2025), "absolute_change"].iloc[0]),
            "2024_to_2025_percentage_change": float(yearly.loc[yearly["crime_year"].eq(2025), "percentage_change"].iloc[0]),
            "2025_months_below_2024": months_lower_2025,
            "2025_areas_decreased": int(direction_summary["areas_decreased"]),
            "figures_saved": len(list(FIGURE_DIR.glob("python_*.png"))),
        })
        display(summary.to_frame("value"))

        expected_figures = {
            "python_yearly_trend.png",
            "python_monthly_rolling_trend.png",
            "python_seasonal_by_year.png",
            "python_weekday_hourly_patterns.png",
            "python_category_yearly_trends.png",
            "python_category_monthly_profile.png",
            "python_arrest_domestic_trends.png",
            "python_community_area_yoy.png",
        }
        observed_figures = {path.name for path in FIGURE_DIR.glob("python_*.png")}
        missing_figures = expected_figures - observed_figures
        if missing_figures:
            raise AssertionError(f"Missing expected figures: {sorted(missing_figures)}")
        print("PASS: all eight expected figures were generated.")
        '''),
        markdown('''
        ## Limitations

        - The source measures reported incidents and can be revised after extraction.
        - Murder rows represent victims rather than incidents according to the source.
        - Community-area counts are not adjusted for population or exposure.
        - Missing coordinates do not remove records from these non-map analyses.
        - Source timestamps may be estimated, limiting precise hourly interpretation.
        - Category, temporal, and indicator relationships are descriptive and non-causal.
        '''),
        code('engine.dispose()\nprint("Database engine disposed.")'),
    ]
    return notebook


def main():
    notebooks = {
        "01_data_validation.ipynb": build_validation_notebook(),
        "02_exploratory_analysis.ipynb": build_eda_notebook(),
    }
    for filename, notebook in notebooks.items():
        destination = NOTEBOOK_DIR / filename
        nbf.write(notebook, destination)
        print(f"Wrote {destination.relative_to(PROJECT_ROOT)}")


if __name__ == "__main__":
    main()
