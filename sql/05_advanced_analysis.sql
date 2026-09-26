\set ON_ERROR_STOP on
\pset pager off
\pset null '[NULL]'
\timing on

-- Milestone 6: Advanced SQL and quantified portfolio findings
-- Canonical scope: public.clean_chicago_crimes, complete calendar years 2023-2025.
-- Counts represent reported incident records, not population-normalized crime rates.
-- Arrest percentages are not clearance or conviction rates.

BEGIN;

-- Official City of Chicago community-area lookup.
-- Source: Boundaries - Community Areas (current), map ID cauq-8yn6,
-- underlying dataset ID igwz-8jzy; verified 2026-09-26.
CREATE OR REPLACE VIEW public.vw_community_area_lookup AS
SELECT area_number::smallint AS community_area,
       community_name::text AS community_area_name
FROM (VALUES
    (1, 'ROGERS PARK'), (2, 'WEST RIDGE'), (3, 'UPTOWN'),
    (4, 'LINCOLN SQUARE'), (5, 'NORTH CENTER'), (6, 'LAKE VIEW'),
    (7, 'LINCOLN PARK'), (8, 'NEAR NORTH SIDE'), (9, 'EDISON PARK'),
    (10, 'NORWOOD PARK'), (11, 'JEFFERSON PARK'), (12, 'FOREST GLEN'),
    (13, 'NORTH PARK'), (14, 'ALBANY PARK'), (15, 'PORTAGE PARK'),
    (16, 'IRVING PARK'), (17, 'DUNNING'), (18, 'MONTCLARE'),
    (19, 'BELMONT CRAGIN'), (20, 'HERMOSA'), (21, 'AVONDALE'),
    (22, 'LOGAN SQUARE'), (23, 'HUMBOLDT PARK'), (24, 'WEST TOWN'),
    (25, 'AUSTIN'), (26, 'WEST GARFIELD PARK'), (27, 'EAST GARFIELD PARK'),
    (28, 'NEAR WEST SIDE'), (29, 'NORTH LAWNDALE'), (30, 'SOUTH LAWNDALE'),
    (31, 'LOWER WEST SIDE'), (32, 'LOOP'), (33, 'NEAR SOUTH SIDE'),
    (34, 'ARMOUR SQUARE'), (35, 'DOUGLAS'), (36, 'OAKLAND'),
    (37, 'FULLER PARK'), (38, 'GRAND BOULEVARD'), (39, 'KENWOOD'),
    (40, 'WASHINGTON PARK'), (41, 'HYDE PARK'), (42, 'WOODLAWN'),
    (43, 'SOUTH SHORE'), (44, 'CHATHAM'), (45, 'AVALON PARK'),
    (46, 'SOUTH CHICAGO'), (47, 'BURNSIDE'), (48, 'CALUMET HEIGHTS'),
    (49, 'ROSELAND'), (50, 'PULLMAN'), (51, 'SOUTH DEERING'),
    (52, 'EAST SIDE'), (53, 'WEST PULLMAN'), (54, 'RIVERDALE'),
    (55, 'HEGEWISCH'), (56, 'GARFIELD RIDGE'), (57, 'ARCHER HEIGHTS'),
    (58, 'BRIGHTON PARK'), (59, 'MCKINLEY PARK'), (60, 'BRIDGEPORT'),
    (61, 'NEW CITY'), (62, 'WEST ELSDON'), (63, 'GAGE PARK'),
    (64, 'CLEARING'), (65, 'WEST LAWN'), (66, 'CHICAGO LAWN'),
    (67, 'WEST ENGLEWOOD'), (68, 'ENGLEWOOD'),
    (69, 'GREATER GRAND CROSSING'), (70, 'ASHBURN'),
    (71, 'AUBURN GRESHAM'), (72, 'BEVERLY'),
    (73, 'WASHINGTON HEIGHTS'), (74, 'MOUNT GREENWOOD'),
    (75, 'MORGAN PARK'), (76, 'OHARE'), (77, 'EDGEWATER')
) AS lookup(area_number, community_name);

COMMENT ON VIEW public.vw_community_area_lookup IS
'Official 77-area lookup from City of Chicago dataset igwz-8jzy (map cauq-8yn6), verified 2026-09-26.';

-- Annual citywide totals and sequential complete-year changes.
CREATE OR REPLACE VIEW public.vw_yearly_crime_trends AS
WITH yearly_counts AS (
    SELECT crime_year,
           COUNT(*)::bigint AS reported_incident_count
    FROM public.clean_chicago_crimes
    GROUP BY crime_year
), with_prior AS (
    SELECT crime_year,
           reported_incident_count,
           LAG(crime_year) OVER (ORDER BY crime_year) AS previous_year,
           LAG(reported_incident_count) OVER (ORDER BY crime_year) AS previous_year_incident_count
    FROM yearly_counts
)
SELECT crime_year,
       reported_incident_count,
       previous_year,
       previous_year_incident_count,
       reported_incident_count - previous_year_incident_count AS absolute_change,
       100.0 * (reported_incident_count - previous_year_incident_count)
           / NULLIF(previous_year_incident_count, 0) AS percentage_change,
       DENSE_RANK() OVER (ORDER BY reported_incident_count DESC) AS incident_volume_rank
FROM with_prior;

COMMENT ON VIEW public.vw_yearly_crime_trends IS
'Citywide reported incident totals and sequential complete-calendar-year changes; percentage denominator is the previous-year count.';

-- Community-area comparisons. Percentage ranks require a prior-year baseline
-- of at least 500 incidents; absolute ranks include every official area.
CREATE OR REPLACE VIEW public.vw_community_area_yoy AS
WITH parameters AS (
    SELECT 500::bigint AS minimum_prior_year_count
), years AS (
    SELECT DISTINCT crime_year
    FROM public.clean_chicago_crimes
), area_year_grid AS (
    SELECT l.community_area,
           l.community_area_name,
           y.crime_year
    FROM public.vw_community_area_lookup AS l
    CROSS JOIN years AS y
), observed AS (
    SELECT community_area,
           crime_year,
           COUNT(*)::bigint AS reported_incident_count
    FROM public.clean_chicago_crimes
    WHERE community_area_eligible_flag
    GROUP BY community_area, crime_year
), complete_grid AS (
    SELECT g.community_area,
           g.community_area_name,
           g.crime_year,
           COALESCE(o.reported_incident_count, 0)::bigint AS reported_incident_count
    FROM area_year_grid AS g
    LEFT JOIN observed AS o
      ON o.community_area = g.community_area
     AND o.crime_year = g.crime_year
), with_prior AS (
    SELECT community_area,
           community_area_name,
           crime_year,
           reported_incident_count,
           LAG(crime_year) OVER (
               PARTITION BY community_area ORDER BY crime_year
           ) AS previous_year,
           LAG(reported_incident_count) OVER (
               PARTITION BY community_area ORDER BY crime_year
           ) AS previous_year_incident_count
    FROM complete_grid
), changes AS (
    SELECT w.community_area,
           w.community_area_name,
           w.crime_year AS current_year,
           w.previous_year,
           w.reported_incident_count AS current_year_incident_count,
           w.previous_year_incident_count,
           w.reported_incident_count - w.previous_year_incident_count AS absolute_change,
           100.0 * (w.reported_incident_count - w.previous_year_incident_count)
               / NULLIF(w.previous_year_incident_count, 0) AS percentage_change,
           p.minimum_prior_year_count,
           w.previous_year_incident_count >= p.minimum_prior_year_count
               AS percentage_rank_eligible
    FROM with_prior AS w
    CROSS JOIN parameters AS p
    WHERE w.previous_year IS NOT NULL
), absolute_ranks AS (
    SELECT c.*,
           RANK() OVER (
               PARTITION BY current_year ORDER BY absolute_change DESC
           ) AS absolute_change_rank,
           RANK() OVER (
               PARTITION BY current_year ORDER BY absolute_change ASC
           ) AS absolute_decrease_rank
    FROM changes AS c
), percentage_ranks AS (
    SELECT current_year,
           community_area,
           RANK() OVER (
               PARTITION BY current_year ORDER BY percentage_change DESC
           ) AS percentage_change_rank,
           RANK() OVER (
               PARTITION BY current_year ORDER BY percentage_change ASC
           ) AS percentage_decrease_rank
    FROM changes
    WHERE percentage_rank_eligible
      AND percentage_change IS NOT NULL
)
SELECT a.community_area,
       a.community_area_name,
       a.current_year,
       a.previous_year,
       a.current_year_incident_count,
       a.previous_year_incident_count,
       a.absolute_change,
       a.percentage_change,
       a.minimum_prior_year_count,
       a.percentage_rank_eligible,
       p.percentage_change_rank,
       p.percentage_decrease_rank,
       a.absolute_change_rank,
       a.absolute_decrease_rank
FROM absolute_ranks AS a
LEFT JOIN percentage_ranks AS p
  ON p.current_year = a.current_year
 AND p.community_area = a.community_area;

COMMENT ON VIEW public.vw_community_area_yoy IS
'Year-over-year reported incident changes for all 77 official community areas. Percentage ranks require previous-year count >= 500; absolute ranks include all areas.';

-- Crime-category trends, annual shares, and within-year ranks.
CREATE OR REPLACE VIEW public.vw_crime_type_trends AS
WITH yearly_type_counts AS (
    SELECT crime_year,
           primary_type,
           COUNT(*)::bigint AS reported_incident_count
    FROM public.clean_chicago_crimes
    GROUP BY crime_year, primary_type
), with_windows AS (
    SELECT crime_year,
           primary_type,
           reported_incident_count,
           SUM(reported_incident_count) OVER (
               PARTITION BY crime_year
           ) AS yearly_reported_incident_count,
           LAG(crime_year) OVER (
               PARTITION BY primary_type ORDER BY crime_year
           ) AS previous_year,
           LAG(reported_incident_count) OVER (
               PARTITION BY primary_type ORDER BY crime_year
           ) AS previous_year_incident_count,
           DENSE_RANK() OVER (
               PARTITION BY crime_year ORDER BY reported_incident_count DESC
           ) AS incident_volume_rank
    FROM yearly_type_counts
)
SELECT crime_year,
       primary_type,
       reported_incident_count,
       yearly_reported_incident_count,
       100.0 * reported_incident_count
           / NULLIF(yearly_reported_incident_count, 0) AS percentage_of_year_total,
       previous_year,
       previous_year_incident_count,
       reported_incident_count - previous_year_incident_count AS absolute_change,
       100.0 * (reported_incident_count - previous_year_incident_count)
           / NULLIF(previous_year_incident_count, 0) AS percentage_change,
       incident_volume_rank
FROM with_windows;

COMMENT ON VIEW public.vw_crime_type_trends IS
'Annual primary-type reported incident counts, percentage of citywide yearly total, volume rank, and sequential year-over-year change.';

-- Monthly series with share of annual volume, 3-month rolling mean, and
-- same-month prior-year comparisons.
CREATE OR REPLACE VIEW public.vw_temporal_patterns AS
WITH monthly_counts AS (
    SELECT DATE_TRUNC('month', crime_date)::date AS month_start,
           crime_year,
           crime_month,
           month_name,
           COUNT(*)::bigint AS reported_incident_count
    FROM public.clean_chicago_crimes
    GROUP BY DATE_TRUNC('month', crime_date)::date,
             crime_year, crime_month, month_name
), with_windows AS (
    SELECT month_start,
           crime_year,
           crime_month,
           month_name,
           reported_incident_count,
           SUM(reported_incident_count) OVER (
               PARTITION BY crime_year
           ) AS yearly_reported_incident_count,
           AVG(reported_incident_count::numeric) OVER (
               ORDER BY month_start ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
           ) AS three_month_rolling_average,
           LAG(reported_incident_count, 12) OVER (
               ORDER BY month_start
           ) AS same_month_previous_year_count
    FROM monthly_counts
)
SELECT month_start,
       crime_year,
       crime_month,
       month_name,
       reported_incident_count,
       yearly_reported_incident_count,
       100.0 * reported_incident_count
           / NULLIF(yearly_reported_incident_count, 0) AS percentage_of_year_total,
       three_month_rolling_average,
       same_month_previous_year_count,
       reported_incident_count - same_month_previous_year_count
           AS same_month_absolute_change,
       100.0 * (reported_incident_count - same_month_previous_year_count)
           / NULLIF(same_month_previous_year_count, 0)
           AS same_month_percentage_change
FROM with_windows;

COMMENT ON VIEW public.vw_temporal_patterns IS
'Complete monthly reported incident series with annual share, trailing 3-month average, and same-month prior-year comparison.';

-- Coordinate-eligible incident view for point mapping. Non-geocoded incidents
-- remain in clean_chicago_crimes and all non-geographic views.
CREATE OR REPLACE VIEW public.vw_geographic_crime_points AS
SELECT c.source_id,
       c.case_number,
       c.crime_timestamp,
       c.crime_date,
       c.crime_year,
       c.primary_type,
       c.description,
       c.location_description,
       c.community_area,
       l.community_area_name,
       c.district,
       c.ward,
       c.beat,
       c.latitude,
       c.longitude,
       c.arrest,
       c.domestic
FROM public.clean_chicago_crimes AS c
LEFT JOIN public.vw_community_area_lookup AS l
  ON l.community_area = c.community_area
WHERE c.coordinate_mappable_flag;

COMMENT ON VIEW public.vw_geographic_crime_points IS
'Coordinate-mappable reported incident records only; excluded records remain available for non-geographic analysis in clean_chicago_crimes.';

-- One-row executive summary. Arrest/domestic denominators contain only
-- non-null indicators; neither percentage is a clearance or conviction rate.
CREATE OR REPLACE VIEW public.vw_executive_kpis AS
WITH base AS (
    SELECT COUNT(*)::bigint AS reported_incident_count,
           MIN(crime_date) AS first_crime_date,
           MAX(crime_date) AS last_crime_date,
           MIN(crime_year) AS first_complete_year,
           MAX(crime_year) AS latest_complete_year,
           COUNT(*) FILTER (WHERE coordinate_mappable_flag)::bigint
               AS coordinate_mappable_count,
           COUNT(*) FILTER (WHERE community_area_eligible_flag)::bigint
               AS community_area_eligible_count,
           COUNT(*) FILTER (WHERE arrest IS TRUE)::bigint AS arrest_count,
           COUNT(arrest)::bigint AS arrest_indicator_denominator,
           COUNT(*) FILTER (WHERE domestic IS TRUE)::bigint AS domestic_count,
           COUNT(domestic)::bigint AS domestic_indicator_denominator
    FROM public.clean_chicago_crimes
), latest AS (
    SELECT crime_year AS latest_year,
           reported_incident_count AS latest_year_incident_count,
           previous_year,
           previous_year_incident_count,
           absolute_change AS latest_year_absolute_change,
           percentage_change AS latest_year_percentage_change
    FROM public.vw_yearly_crime_trends
    ORDER BY crime_year DESC
    LIMIT 1
)
SELECT b.reported_incident_count,
       b.first_crime_date,
       b.last_crime_date,
       b.first_complete_year,
       b.latest_complete_year,
       b.coordinate_mappable_count,
       100.0 * b.coordinate_mappable_count
           / NULLIF(b.reported_incident_count, 0) AS geographic_coverage_percentage,
       b.community_area_eligible_count,
       100.0 * b.community_area_eligible_count
           / NULLIF(b.reported_incident_count, 0) AS community_area_coverage_percentage,
       b.arrest_count,
       b.arrest_indicator_denominator,
       100.0 * b.arrest_count
           / NULLIF(b.arrest_indicator_denominator, 0) AS arrest_percentage,
       b.domestic_count,
       b.domestic_indicator_denominator,
       100.0 * b.domestic_count
           / NULLIF(b.domestic_indicator_denominator, 0) AS domestic_incident_percentage,
       l.latest_year,
       l.latest_year_incident_count,
       l.previous_year,
       l.previous_year_incident_count,
       l.latest_year_absolute_change,
       l.latest_year_percentage_change
FROM base AS b
CROSS JOIN latest AS l;

COMMENT ON VIEW public.vw_executive_kpis IS
'One-row clean-dataset coverage and latest complete-year KPI summary. Percentages retain full precision for display-layer rounding.';

-- Abort the transaction if view structure, canonical totals, or source-level
-- reconciliations do not hold. These checks validate all reusable views while
-- leaving raw_chicago_crimes unchanged.
DO $$
BEGIN
    IF (SELECT COUNT(*) FROM public.vw_community_area_lookup) <> 77
       OR (SELECT COUNT(DISTINCT community_area)
           FROM public.vw_community_area_lookup) <> 77 THEN
        RAISE EXCEPTION 'Community-area lookup must contain 77 unique IDs';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM (
            SELECT crime_year, COUNT(*)::bigint AS expected_count
            FROM public.clean_chicago_crimes
            GROUP BY crime_year
        ) AS c
        FULL JOIN public.vw_yearly_crime_trends AS y USING (crime_year)
        WHERE c.expected_count IS DISTINCT FROM y.reported_incident_count
    ) THEN
        RAISE EXCEPTION 'Yearly view does not reconcile to clean table';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM (
            SELECT year::integer AS crime_year, COUNT(*)::bigint AS source_count
            FROM public.raw_chicago_crimes
            GROUP BY year
        ) AS r
        FULL JOIN public.vw_yearly_crime_trends AS y USING (crime_year)
        WHERE r.source_count IS DISTINCT FROM y.reported_incident_count
    ) THEN
        RAISE EXCEPTION 'Yearly view does not reconcile to raw source records';
    END IF;

    IF (SELECT COUNT(*) FROM public.vw_community_area_yoy) <> 154
       OR EXISTS (
           SELECT 1
           FROM public.vw_community_area_yoy
           GROUP BY current_year
           HAVING COUNT(*) <> 77
       ) THEN
        RAISE EXCEPTION 'Community-area YoY view must contain 77 rows per comparison year';
    END IF;

    IF EXISTS (
        WITH raw_area_year AS (
            SELECT year::integer AS crime_year,
                   COUNT(*) FILTER (WHERE community_area BETWEEN 1 AND 77)::bigint
                       AS source_count
            FROM public.raw_chicago_crimes
            GROUP BY year
        ), clean_area_year AS (
            SELECT crime_year,
                   COUNT(*) FILTER (WHERE community_area_eligible_flag)::bigint
                       AS clean_count
            FROM public.clean_chicago_crimes
            GROUP BY crime_year
        )
        SELECT 1
        FROM raw_area_year AS r
        FULL JOIN clean_area_year AS c USING (crime_year)
        WHERE r.source_count IS DISTINCT FROM c.clean_count
    ) THEN
        RAISE EXCEPTION 'Community-area eligibility does not reconcile to raw source records';
    END IF;

    IF (SELECT COUNT(*) FROM public.vw_geographic_crime_points)
       <> (SELECT COUNT(*) FROM public.clean_chicago_crimes
           WHERE coordinate_mappable_flag) THEN
        RAISE EXCEPTION 'Geographic point view does not reconcile to mapping eligibility';
    END IF;

    IF (SELECT COUNT(*) FROM public.vw_executive_kpis) <> 1 THEN
        RAISE EXCEPTION 'Executive KPI view must return exactly one row';
    END IF;
END
$$;

COMMIT;

BEGIN TRANSACTION READ ONLY;

-- A01. What are citywide totals and sequential changes for every complete year?
-- Metric: reported incident count; YoY denominator: immediately preceding
-- complete-year count. A zero previous count returns a null percentage.
SELECT crime_year,
       reported_incident_count,
       previous_year,
       previous_year_incident_count,
       absolute_change,
       ROUND(percentage_change, 4) AS percentage_change,
       incident_volume_rank
FROM public.vw_yearly_crime_trends
ORDER BY crime_year;

-- A02. Which observed citywide comparisons produced the largest increase and
-- decrease? Null means no comparison in the direction occurred.
WITH changes AS (
    SELECT *
    FROM public.vw_yearly_crime_trends
    WHERE previous_year IS NOT NULL
), extremes AS (
    SELECT MAX(absolute_change) FILTER (WHERE absolute_change > 0)
               AS largest_increase,
           MIN(absolute_change) FILTER (WHERE absolute_change < 0)
               AS largest_decrease
    FROM changes
), labeled_extremes AS (
    SELECT 'Largest increase'::text AS comparison_type,
           largest_increase AS extreme_change
    FROM extremes
    UNION ALL
    SELECT 'Largest decrease', largest_decrease
    FROM extremes
)
SELECT e.comparison_type,
       c.previous_year,
       c.crime_year AS current_year,
       c.previous_year_incident_count,
       c.reported_incident_count AS current_year_incident_count,
       c.absolute_change,
       ROUND(c.percentage_change, 4) AS percentage_change
FROM labeled_extremes AS e
LEFT JOIN changes AS c
  ON c.absolute_change = e.extreme_change
ORDER BY e.comparison_type;

-- B01. Which areas had the largest percentage decreases versus largest
-- absolute decreases? Percentage-decrease rank requires prior count >= 500;
-- absolute-decrease rank covers all 77 official areas.
WITH latest AS (
    SELECT MAX(current_year) AS current_year
    FROM public.vw_community_area_yoy
), ranked AS (
    SELECT y.*
    FROM public.vw_community_area_yoy AS y
    CROSS JOIN latest AS l
    WHERE y.current_year = l.current_year
)
SELECT 'Percentage decrease' AS ranking_basis,
       percentage_decrease_rank AS rank,
       community_area,
       community_area_name,
       previous_year,
       current_year,
       previous_year_incident_count,
       current_year_incident_count,
       absolute_change,
       ROUND(percentage_change, 4) AS percentage_change
FROM ranked
WHERE percentage_decrease_rank <= 10
UNION ALL
SELECT 'Absolute decrease',
       absolute_decrease_rank,
       community_area,
       community_area_name,
       previous_year,
       current_year,
       previous_year_incident_count,
       current_year_incident_count,
       absolute_change,
       ROUND(percentage_change, 4)
FROM ranked
WHERE absolute_decrease_rank <= 10
ORDER BY ranking_basis, rank, community_area;

-- B02. Does Forest Glen support the proposed 25.1% decline claim?
-- Denominator: Forest Glen's immediately preceding complete-year count.
SELECT community_area,
       community_area_name,
       previous_year,
       current_year,
       previous_year_incident_count,
       current_year_incident_count,
       absolute_change,
       ROUND(percentage_change, 4) AS percentage_change,
       percentage_rank_eligible,
       percentage_decrease_rank,
       absolute_decrease_rank
FROM public.vw_community_area_yoy
WHERE community_area = 12
ORDER BY current_year;

-- C01. What monthly patterns and trailing 3-month averages appear?
-- The rolling average spans the current and two preceding calendar months.
SELECT month_start,
       crime_year,
       crime_month,
       month_name,
       reported_incident_count,
       ROUND(percentage_of_year_total, 4) AS percentage_of_year_total,
       ROUND(three_month_rolling_average, 2) AS three_month_rolling_average,
       same_month_previous_year_count,
       same_month_absolute_change,
       ROUND(same_month_percentage_change, 4) AS same_month_percentage_change
FROM public.vw_temporal_patterns
ORDER BY month_start;

-- C02. What was each area's leading source crime type over the full period?
-- Denominator for share: all community-area-eligible incidents in the area.
WITH area_type_counts AS (
    SELECT c.community_area,
           l.community_area_name,
           c.primary_type,
           COUNT(*)::bigint AS reported_incident_count
    FROM public.clean_chicago_crimes AS c
    JOIN public.vw_community_area_lookup AS l
      ON l.community_area = c.community_area
    WHERE c.community_area_eligible_flag
    GROUP BY c.community_area, l.community_area_name, c.primary_type
), ranked AS (
    SELECT *,
           SUM(reported_incident_count) OVER (
               PARTITION BY community_area
           ) AS area_reported_incident_count,
           DENSE_RANK() OVER (
               PARTITION BY community_area
               ORDER BY reported_incident_count DESC
           ) AS crime_type_rank
    FROM area_type_counts
)
SELECT community_area,
       community_area_name,
       primary_type,
       reported_incident_count,
       area_reported_incident_count,
       ROUND(100.0 * reported_incident_count
           / NULLIF(area_reported_incident_count, 0), 4) AS percentage_of_area_total
FROM ranked
WHERE crime_type_rank = 1
ORDER BY community_area, primary_type;

-- C03. Which areas persistently ranked among the highest-volume areas?
-- Ranks use community-area-eligible reported incident counts by year.
WITH yearly_area_counts AS (
    SELECT c.crime_year,
           c.community_area,
           l.community_area_name,
           COUNT(*)::bigint AS reported_incident_count
    FROM public.clean_chicago_crimes AS c
    JOIN public.vw_community_area_lookup AS l
      ON l.community_area = c.community_area
    WHERE c.community_area_eligible_flag
    GROUP BY c.crime_year, c.community_area, l.community_area_name
), yearly_ranks AS (
    SELECT *,
           RANK() OVER (
               PARTITION BY crime_year ORDER BY reported_incident_count DESC
           ) AS yearly_volume_rank
    FROM yearly_area_counts
)
SELECT community_area,
       community_area_name,
       COUNT(*) FILTER (WHERE yearly_volume_rank <= 10) AS years_in_top_10,
       COUNT(*) FILTER (WHERE yearly_volume_rank <= 20) AS years_in_top_20,
       ROUND(AVG(yearly_volume_rank), 2) AS average_annual_rank,
       SUM(reported_incident_count)::bigint AS reported_incident_count
FROM yearly_ranks
GROUP BY community_area, community_area_name
ORDER BY years_in_top_10 DESC,
         years_in_top_20 DESC,
         reported_incident_count DESC,
         community_area
LIMIT 20;

-- C04. Which source crime categories had the largest absolute annual changes?
-- Percentage denominator: the category's previous complete-year count.
WITH ranked AS (
    SELECT *,
           RANK() OVER (
               PARTITION BY crime_year ORDER BY ABS(absolute_change) DESC
           ) AS absolute_change_magnitude_rank
    FROM public.vw_crime_type_trends
    WHERE previous_year IS NOT NULL
)
SELECT crime_year,
       primary_type,
       previous_year_incident_count,
       reported_incident_count,
       absolute_change,
       ROUND(percentage_change, 4) AS percentage_change,
       ROUND(percentage_of_year_total, 4) AS percentage_of_year_total,
       absolute_change_magnitude_rank
FROM ranked
WHERE absolute_change_magnitude_rank <= 10
ORDER BY crime_year, absolute_change_magnitude_rank, primary_type;

-- C05. How did annual arrest percentages change?
-- Denominator: records with a non-null arrest indicator. This is not a
-- clearance, prosecution, or conviction rate.
WITH yearly AS (
    SELECT crime_year,
           COUNT(*) FILTER (WHERE arrest IS TRUE)::bigint AS arrest_count,
           COUNT(arrest)::bigint AS arrest_indicator_denominator
    FROM public.clean_chicago_crimes
    GROUP BY crime_year
), percentages AS (
    SELECT crime_year,
           arrest_count,
           arrest_indicator_denominator,
           100.0 * arrest_count
               / NULLIF(arrest_indicator_denominator, 0) AS arrest_percentage
    FROM yearly
)
SELECT crime_year,
       arrest_count,
       arrest_indicator_denominator,
       ROUND(arrest_percentage, 4) AS arrest_percentage,
       ROUND(arrest_percentage - LAG(arrest_percentage) OVER (
           ORDER BY crime_year
       ), 4) AS percentage_point_change
FROM percentages
ORDER BY crime_year;

-- C06. Which season led for each source crime category?
-- Denominator: all incidents of that source crime category over the period.
WITH seasonal_counts AS (
    SELECT primary_type,
           season,
           COUNT(*)::bigint AS reported_incident_count
    FROM public.clean_chicago_crimes
    GROUP BY primary_type, season
), ranked AS (
    SELECT *,
           SUM(reported_incident_count) OVER (
               PARTITION BY primary_type
           ) AS crime_type_total,
           DENSE_RANK() OVER (
               PARTITION BY primary_type ORDER BY reported_incident_count DESC
           ) AS seasonal_rank
    FROM seasonal_counts
)
SELECT primary_type,
       season,
       reported_incident_count,
       crime_type_total,
       ROUND(100.0 * reported_incident_count
           / NULLIF(crime_type_total, 0), 4) AS percentage_of_crime_type_total
FROM ranked
WHERE seasonal_rank = 1
ORDER BY primary_type, season;

-- E01. Compare the two supplied candidate claims with this extract's canonical
-- results. Candidate values are tested, not treated as accepted findings.
WITH latest_city AS (
    SELECT *
    FROM public.vw_yearly_crime_trends
    ORDER BY crime_year DESC
    LIMIT 1
), forest_glen AS (
    SELECT *
    FROM public.vw_community_area_yoy
    WHERE community_area = 12
    ORDER BY current_year DESC
    LIMIT 1
)
SELECT 'Citywide supplied count claim' AS candidate,
       '2024 to 2025' AS period,
       260381::numeric AS candidate_previous_value,
       237849::numeric AS candidate_current_value,
       ROUND(100.0 * (237849 - 260381) / 260381, 4)
           AS candidate_percentage_change,
       c.previous_year_incident_count::numeric AS actual_previous_value,
       c.reported_incident_count::numeric AS actual_current_value,
       c.absolute_change::numeric AS actual_absolute_change,
       ROUND(c.percentage_change, 4) AS actual_percentage_change
FROM latest_city AS c
UNION ALL
SELECT 'Forest Glen supplied percentage claim',
       '2024 to 2025',
       NULL,
       NULL,
       -25.1,
       f.previous_year_incident_count,
       f.current_year_incident_count,
       f.absolute_change,
       ROUND(f.percentage_change, 4)
FROM forest_glen AS f;

-- V01. Structural and denominator validation for reusable views.
SELECT 'lookup rows' AS check_name,
       COUNT(*)::bigint AS observed_value,
       77::bigint AS expected_value,
       COUNT(*) = 77 AS passed
FROM public.vw_community_area_lookup
UNION ALL
SELECT 'lookup distinct area numbers', COUNT(DISTINCT community_area), 77,
       COUNT(DISTINCT community_area) = 77
FROM public.vw_community_area_lookup
UNION ALL
SELECT 'community YoY rows', COUNT(*), 154, COUNT(*) = 154
FROM public.vw_community_area_yoy
UNION ALL
SELECT 'community YoY named rows', COUNT(community_area_name), 154,
       COUNT(community_area_name) = 154
FROM public.vw_community_area_yoy
UNION ALL
SELECT 'percentage-rank-eligible rows',
       COUNT(*) FILTER (WHERE percentage_rank_eligible), 150,
       COUNT(*) FILTER (WHERE percentage_rank_eligible) = 150
FROM public.vw_community_area_yoy
UNION ALL
SELECT 'zero prior-year denominators',
       COUNT(*) FILTER (WHERE previous_year_incident_count = 0), 0,
       COUNT(*) FILTER (WHERE previous_year_incident_count = 0) = 0
FROM public.vw_community_area_yoy
UNION ALL
SELECT 'executive KPI rows', COUNT(*), 1, COUNT(*) = 1
FROM public.vw_executive_kpis;

-- V02. Reconcile every analytical aggregation to the canonical clean table.
WITH clean_yearly AS (
    SELECT crime_year, COUNT(*)::bigint AS expected_count
    FROM public.clean_chicago_crimes
    GROUP BY crime_year
), eligible_yearly AS (
    SELECT crime_year,
           COUNT(*) FILTER (WHERE community_area_eligible_flag)::bigint
               AS expected_count
    FROM public.clean_chicago_crimes
    GROUP BY crime_year
), reconciliations AS (
    SELECT 'yearly view'::text AS check_name,
           y.crime_year,
           c.expected_count,
           y.reported_incident_count AS observed_count
    FROM clean_yearly AS c
    JOIN public.vw_yearly_crime_trends AS y USING (crime_year)
    UNION ALL
    SELECT 'crime-type view', c.crime_year, c.expected_count,
           SUM(t.reported_incident_count)::bigint
    FROM clean_yearly AS c
    JOIN public.vw_crime_type_trends AS t USING (crime_year)
    GROUP BY c.crime_year, c.expected_count
    UNION ALL
    SELECT 'temporal view', c.crime_year, c.expected_count,
           SUM(t.reported_incident_count)::bigint
    FROM clean_yearly AS c
    JOIN public.vw_temporal_patterns AS t USING (crime_year)
    GROUP BY c.crime_year, c.expected_count
    UNION ALL
    SELECT 'community-area view', c.crime_year,
           c.expected_count,
           SUM(y.current_year_incident_count)::bigint
    FROM eligible_yearly AS c
    JOIN public.vw_community_area_yoy AS y
      ON y.current_year = c.crime_year
    GROUP BY c.crime_year, c.expected_count
)
SELECT check_name,
       crime_year,
       expected_count,
       observed_count,
       observed_count - expected_count AS difference,
       observed_count = expected_count AS passed
FROM reconciliations
ORDER BY check_name, crime_year;

-- V03. Reconcile the geographic point view and expose the executive KPI row.
SELECT 'geographic point rows' AS check_name,
       COUNT(*) FILTER (WHERE coordinate_mappable_flag)::bigint AS expected_count,
       (SELECT COUNT(*) FROM public.vw_geographic_crime_points)::bigint
           AS observed_count,
       COUNT(*) FILTER (WHERE coordinate_mappable_flag)
           = (SELECT COUNT(*) FROM public.vw_geographic_crime_points) AS passed
FROM public.clean_chicago_crimes;

SELECT *
FROM public.vw_executive_kpis;

-- V04. Cross-check annual citywide and geography-eligible counts directly
-- against the immutable typed source table.
WITH raw_yearly AS (
    SELECT year::integer AS crime_year,
           COUNT(*)::bigint AS raw_reported_incident_count,
           COUNT(*) FILTER (WHERE community_area BETWEEN 1 AND 77)::bigint
               AS raw_community_area_eligible_count
    FROM public.raw_chicago_crimes
    GROUP BY year
), clean_yearly AS (
    SELECT crime_year,
           COUNT(*)::bigint AS clean_reported_incident_count,
           COUNT(*) FILTER (WHERE community_area_eligible_flag)::bigint
               AS clean_community_area_eligible_count
    FROM public.clean_chicago_crimes
    GROUP BY crime_year
)
SELECT COALESCE(r.crime_year, c.crime_year) AS crime_year,
       r.raw_reported_incident_count,
       c.clean_reported_incident_count,
       c.clean_reported_incident_count - r.raw_reported_incident_count
           AS citywide_difference,
       r.raw_community_area_eligible_count,
       c.clean_community_area_eligible_count,
       c.clean_community_area_eligible_count
           - r.raw_community_area_eligible_count AS community_area_difference,
       r.raw_reported_incident_count = c.clean_reported_incident_count
       AND r.raw_community_area_eligible_count
           = c.clean_community_area_eligible_count AS passed
FROM raw_yearly AS r
FULL JOIN clean_yearly AS c USING (crime_year)
ORDER BY crime_year;

COMMIT;
