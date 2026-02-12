/* ============================================================
   VIEW: core.nyc_crashes_analysis
   Purpose: “One-stop” crash-level table with derived time fields,
            severity label, and standardized location fields for
            hotspot grouping (street vs intersection).
   ============================================================ */
CREATE OR REPLACE VIEW core.nyc_crashes_analysis AS
SELECT
	-- Time breakdowns used for trend charts + time-of-day drilldowns
  EXTRACT(YEAR FROM crash_date)::INT AS crash_year,
  EXTRACT(HOUR FROM crash_time)::INT AS crash_hour,
  EXTRACT(DOW  FROM crash_date)::INT AS crash_dow,
  date_trunc('month', crash_date)::DATE AS crash_month,

  -- Severity bucket for quick slicing (crash-level severity label)
  CASE
    WHEN persons_killed > 0 THEN 'Fatal'
    WHEN persons_injured > 0 THEN 'Injury'
    ELSE 'Property Damage Only'
  END AS severity,

  -- Location type: distinguishes intersections vs street segments
  CASE
    WHEN main_street_name IS NOT NULL
         AND cross_street_name IS NOT NULL
      THEN 'Intersection'
    WHEN main_street_name IS NOT NULL
      THEN 'Street Segment'
    ELSE 'Other'
  END AS location_type,

  -- Location label used for grouping in “top streets/intersections”
  CASE
    WHEN main_street_name IS NOT NULL
         AND cross_street_name IS NOT NULL
      -- Concatenates "MAIN ST" + " & " + "CROSS ST" for a readable intersection key
      THEN main_street_name || ' & ' || cross_street_name
    WHEN main_street_name IS NOT NULL
      THEN main_street_name
    ELSE NULL
  END AS location_label

FROM clean.nyc_crash_data;



/* ============================================================
   VIEW: core.nyc_factors
   Purpose: Normalize 5 contributing-factor columns into a single
            row-per-factor “long” table for clean counting/ranking.
   ============================================================ */
CREATE OR REPLACE VIEW core.nyc_factors AS
SELECT
  collision_id,
  borough,
  crash_date,
  severity,
  factor
FROM core.nyc_crashes_analysis

-- CROSS JOIN LATERAL + VALUES “unpivots” factor_1..factor_5 into rows
CROSS JOIN LATERAL (
  VALUES
    (contributing_factor_vehicle_1),
    (contributing_factor_vehicle_2),
    (contributing_factor_vehicle_3),
    (contributing_factor_vehicle_4),
    (contributing_factor_vehicle_5)
) f(factor)
WHERE factor IS NOT NULL;



/* ============================================================
   VIEW: core.nyc_vehicles
   Purpose: Normalize 5 vehicle type columns into a single row-per-
            vehicle “long” table for counting and grouping.
   ============================================================ */
CREATE OR REPLACE VIEW core.nyc_vehicles AS
SELECT
  collision_id,
  borough,
  crash_date,
  severity,
  vehicle_type
FROM core.nyc_crashes_analysis

-- Unpivots vehicle_type_code_1..5 into rows
CROSS JOIN LATERAL (
  VALUES
    (vehicle_type_code_1),
    (vehicle_type_code_2),
    (vehicle_type_code_3),
    (vehicle_type_code_4),
    (vehicle_type_code_5)
) v(vehicle_type)
WHERE vehicle_type IS NOT NULL;



/* ============================================================
   VIEW: core.nyc_vehicles_grouped
   Purpose: Roll messy vehicle_type strings into consistent
            categories (Passenger, SUV/Pickup, Truck, etc.).
   ============================================================ */
CREATE OR REPLACE VIEW core.nyc_vehicles_grouped AS
SELECT
  *,
  CASE
    -- Passenger vehicles (sedans/coupes/etc. with lots of string variants)
    WHEN vehicle_type ILIKE ANY (ARRAY[
      '%SEDAN%', '%PASSENGER%', '%CONVERTIBLE%', '%COUPE%', '%SUBN%', '%CARRY ALL%', '%2 DR%', '%4 DR%'
    ]) THEN 'Passenger Vehicle'

    -- SUVs / pickups
    WHEN vehicle_type ILIKE ANY (ARRAY[
      '%SUV%', '%SPORT UTILITY%', '%STATION WAGON%', '%PICK%', '%PK%'
    ]) THEN 'SUV / Pickup'

    -- Trucks (commercial & heavy)
    WHEN vehicle_type ILIKE ANY (ARRAY[
      '%TRUCK%', '%TRACTOR%', '%DUMP%', '%TANKER%', '%FLAT%', '%BOX%', '%REFRIGERATED%',
      '%STAKE%', '%GARBAGE%', '%COMMERCIAL%', '%LARGE COM%', '%SMALL COM%'
    ]) THEN 'Truck / Commercial Vehicle'

    -- Buses
    WHEN vehicle_type ILIKE ANY (ARRAY[
      '%BUS%', '%SCHOOL BUS%'
    ]) THEN 'Bus'

    -- Motorcycles & mopeds
    WHEN vehicle_type ILIKE ANY (ARRAY[
      '%MOTORCYCLE%', '%MOTORBIKE%', '%MOPED%', '%MOTORSCOOTER%', '%MINIBIKE%'
    ]) THEN 'Motorcycle / Moped'

    -- Bicycles & micromobility (e-bikes, scooters, pedicabs)
    WHEN vehicle_type ILIKE ANY (ARRAY[
      '%BICYCLE%', '%BIKE%', '%E-BIKE%', '%E-BIK%', '%E-SCOOT%', '%SCOOTER%', '%PEDICAB%'
    ]) THEN 'Bicycle / Micromobility'

    -- Emergency vehicles
    WHEN vehicle_type ILIKE ANY (ARRAY[
      '%AMBUL%', '%FIRE%', '%FDNY%', '%POLICE%'
    ]) THEN 'Emergency Vehicle'

    ELSE 'Other / Unknown'
  END AS vehicle_group
FROM core.nyc_vehicles;



/* ============================================================
   VIEW: core.nyc_factors_grouped
   Purpose: Clean up factor strings (fix typos, merge duplicates,
            drop numeric junk) into a normalized factor_group.
   ============================================================ */
CREATE OR REPLACE VIEW core.nyc_factors_grouped AS
SELECT
  collision_id,
  borough,
  crash_date,
  severity,
  factor,
  CASE
    -- Drops garbage numeric-only “factors” like "1", "80", etc.
    WHEN factor ~ '^\d+$' THEN NULL

    -- Fixes a known typo
    WHEN factor = 'ILLNES' THEN 'ILLNESS'

    -- Collapses near-duplicate labels into one canonical value
    WHEN factor IN ('REACTION TO OTHER UNINVOLVED VEHICLE', 'REACTION TO UNINVOLVED VEHICLE')
      THEN 'REACTION TO UNINVOLVED VEHICLE'

    ELSE factor
  END AS factor_group
FROM core.nyc_factors;



/* ============================================================
   COLLISION TRENDS
   ============================================================ */


-- Yearly crash totals (answers: crashes per year / trend direction)
SELECT
  crash_year,
  COUNT(collision_id) AS crash_count
FROM core.nyc_crashes_analysis
GROUP BY crash_year
ORDER BY crash_year;



-- Monthly crash totals (answers: month-over-month trend)
SELECT 
  crash_month,
  COUNT(collision_id) AS crash_count
FROM core.nyc_crashes_analysis
GROUP BY crash_month
ORDER BY crash_month;



-- Crash totals by borough + percent of total (answers: which boroughs have most crashes)
SELECT
  borough,
  COUNT(*) AS crashes,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) AS pct
FROM core.nyc_crashes_analysis
WHERE borough IS NOT NULL
GROUP BY borough
ORDER BY crashes DESC;



-- Top 10 intersection hotspots by total collisions (answers: top 10 intersections)
SELECT
  location_label AS intersection,
  borough,
  COUNT(*) AS collisions
FROM core.nyc_crashes_analysis
WHERE location_type = 'Intersection'
  AND location_label IS NOT NULL
  AND borough IS NOT NULL
GROUP BY location_label, borough
ORDER BY collisions DESC
LIMIT 10;



-- Top 10 street segment hotspots by total collisions (answers: top 10 streets/segments)
SELECT
  location_label AS street,
  borough,
  COUNT(*) AS collisions
FROM core.nyc_crashes_analysis
WHERE location_type = 'Street Segment'
  AND location_label IS NOT NULL
  AND borough IS NOT NULL
GROUP BY location_label, borough
ORDER BY collisions DESC
LIMIT 10;



-- Top 10 intersections by harmful collisions (Injury/Fatal) with a minimum volume threshold
-- HAVING COUNT(*) >= 50 avoids “one-off” intersections looking severe due to tiny sample size
SELECT
  location_label AS intersection,
  borough,
  COUNT(*) AS total_collisions,
  COUNT(*) FILTER (WHERE severity IN ('Injury','Fatal')) AS harmful_collisions,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE severity IN ('Injury','Fatal')) / COUNT(*),
    2
  ) AS severe_pct
FROM core.nyc_crashes_analysis
WHERE location_type = 'Intersection'
  AND location_label IS NOT NULL
  AND borough IS NOT NULL
GROUP BY location_label, borough
HAVING COUNT(*) >= 50
ORDER BY severe_collisions DESC
LIMIT 10;



-- Overall severity distribution (high-level context: what share are PDO vs Injury vs Fatal)
SELECT
  severity,
  COUNT(*) AS crashes,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM core.nyc_crashes_analysis
GROUP BY severity
ORDER BY crashes DESC;



-- Borough-normalized fatality rate (fatal crashes per 10,000 crashes in that borough)
-- Useful to compare “risk” even when total crash volumes differ by borough.
SELECT
  borough,
  COUNT(*) AS total_crashes,
  COUNT(*) FILTER (WHERE severity = 'Fatal') AS fatal_crashes,
  ROUND(
    10000.0 * COUNT(*) FILTER (WHERE severity = 'Fatal') / COUNT(*),
    2
  ) AS fatal_rate_per_10k
FROM core.nyc_crashes_analysis
WHERE borough IS NOT NULL
GROUP BY borough
ORDER BY fatal_rate_per_10k DESC;



/* ============================================================
   CONTRIBUTING FACTORS
   ============================================================ */
   

-- Raw factor frequency (top 10) using original factor strings (for quick “top mentions”)
-- Note: this is factor-level, not crash-level (a crash can contribute multiple factor rows).
SELECT
  factor,
  COUNT(*) AS appearances
FROM core.nyc_factors
GROUP BY factor
ORDER BY appearances DESC
LIMIT 10;



-- Top 5 contributing causes (cleaned factor_group; excludes UNSPECIFIED and NULL cleanups)
SELECT 
  factor_group,
  COUNT(*) AS appearances
FROM core.nyc_factors_grouped
WHERE factor_group IS NOT NULL
  AND factor_group <> 'UNSPECIFIED'
GROUP BY factor_group
ORDER BY appearances DESC
LIMIT 5;



-- Borough-level top 5 factor groups (per-borough ranking)
WITH counts AS (
  -- Step 1: count factor_group appearances within each borough
  SELECT
    borough,
    factor_group,
    COUNT(*) AS appearances
  FROM core.nyc_factors_grouped
  WHERE borough IS NOT NULL
  GROUP BY borough, factor_group
),
ranked AS (
  -- Step 2: rank factor groups within each borough (1 = most common)
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY borough ORDER BY appearances DESC) AS count_rank
  FROM counts
)
-- Step 3: keep top 5 per borough
SELECT
  borough,
  factor_group,
  appearances
FROM ranked
WHERE count_rank <= 5
ORDER BY borough, appearances DESC;



-- Compare a specific factor across boroughs (example: SPEEDING)
-- Produces both raw count and share of all factor appearances in each borough.
WITH borough_totals AS (
  SELECT
    borough,
    COUNT(*) AS total_factor_appearances
  FROM core.nyc_factors_grouped
  WHERE borough IS NOT NULL
    AND factor_group IS NOT NULL
    AND factor_group <> 'UNSPECIFIED'
  GROUP BY borough
),
factor_counts AS (
  SELECT
    borough,
    COUNT(*) AS factor_appearances
  FROM core.nyc_factors_grouped
  WHERE borough IS NOT NULL
    AND factor_group = 'SPEEDING'
  GROUP BY borough
)
SELECT
  bt.borough,
  COALESCE(fc.factor_appearances, 0) AS speeding_appearances, -- COALESCE converts NULL → 0
  bt.total_factor_appearances,
  ROUND(
    100.0 * COALESCE(fc.factor_appearances, 0) / NULLIF(bt.total_factor_appearances, 0),
    2
  ) AS speeding_share_pct
FROM borough_totals AS bt
LEFT JOIN factor_counts AS fc USING (borough)
ORDER BY speeding_appearances DESC;



/* ============================================================
   CASUALTY ANALYSIS
   ============================================================ */
   

-- Total people injured and killed by borough (answers: injuries/fatalities by borough)
-- casualty_mismatch_flag excluded to avoid inconsistent row totals.
SELECT
  borough,
  SUM(persons_injured) AS total_injuries,
  SUM(persons_killed) AS total_fatalities
FROM core.nyc_crashes_analysis
WHERE borough IS NOT NULL
  AND NOT casualty_mismatch_flag
GROUP BY borough
ORDER BY total_fatalities DESC, total_injuries DESC;



-- Crash counts by borough split into fatal vs injury vs total (crash-level severity counts)
SELECT
  borough,
  COUNT(*) FILTER (WHERE severity = 'Fatal') AS fatal,
  COUNT(*) FILTER (WHERE severity = 'Injury') AS injury,
  COUNT(*) AS total
FROM core.nyc_crashes_analysis
WHERE borough IS NOT NULL
GROUP BY borough
ORDER BY fatal DESC;



-- Citywide totals by road-user type (answers: pedestrians vs cyclists vs motorists affected overall)
SELECT
  SUM(pedestrians_injured) AS ped_injured,
  SUM(cyclists_injured) AS cyc_injured,
  SUM(motorists_injured) AS mot_injured,
  SUM(pedestrians_killed) AS ped_killed,
  SUM(cyclists_killed) AS cyc_killed,
  SUM(motorists_killed) AS mot_killed
FROM core.nyc_crashes_analysis
WHERE NOT casualty_mismatch_flag;



-- Borough totals by road-user type (answers: which groups are most affected by borough)
SELECT
  borough,
  SUM(pedestrians_injured) AS ped_injured,
  SUM(cyclists_injured) AS cyc_injured,
  SUM(motorists_injured) AS mot_injured,
  SUM(pedestrians_killed) AS ped_killed,
  SUM(cyclists_killed) AS cyc_killed,
  SUM(motorists_killed) AS mot_killed
FROM core.nyc_crashes_analysis
WHERE borough IS NOT NULL
  AND NOT casualty_mismatch_flag
GROUP BY borough
ORDER BY ped_killed DESC, cyc_killed DESC, mot_killed DESC;



-- Yearly casualty trends (for injuries/fatalities over time chart)
SELECT
  crash_year,
  SUM(persons_injured) AS injured,
  SUM(persons_killed) AS killed
FROM core.nyc_crashes_analysis
WHERE NOT casualty_mismatch_flag
GROUP BY crash_year
ORDER BY crash_year;



-- Monthly casualty trends (more granular trend chart)
SELECT
  crash_month,
  SUM(persons_injured) AS injured,
  SUM(persons_killed) AS killed
FROM core.nyc_crashes_analysis
WHERE NOT casualty_mismatch_flag
GROUP BY crash_month
ORDER BY crash_month;



-- Time-of-day crash volume (DOW x hour grid for a heatmap)
SELECT
  crash_dow,
  crash_hour,
  COUNT(*) AS crashes
FROM core.nyc_crashes_analysis
WHERE crash_hour IS NOT NULL
GROUP BY crash_dow, crash_hour
ORDER BY crash_dow, crash_hour;



-- Time-of-day severity (DOW x hour grid split into fatal vs injury counts)
SELECT
  crash_dow,
  crash_hour,
  COUNT(*) FILTER (WHERE severity = 'Fatal') AS fatal_crashes,
  COUNT(*) FILTER (WHERE severity = 'Injury') AS injury_crashes
FROM core.nyc_crashes_analysis
WHERE crash_hour IS NOT NULL
GROUP BY crash_dow, crash_hour
ORDER BY crash_dow, crash_hour;



/* ============================================================
   VEHICLE TYPES
   ============================================================ */
   

-- Top 15 raw vehicle_type strings (ungrouped)
SELECT
  vehicle_type,
  COUNT(*) AS appearances
FROM core.nyc_vehicles_grouped
GROUP BY vehicle_type
ORDER BY appearances DESC
LIMIT 15;



-- Vehicle group frequency (which categories show up most often)
SELECT 
  vehicle_group, 
  COUNT(*) AS appearances
FROM core.nyc_vehicles_grouped
GROUP BY vehicle_group
ORDER BY appearances DESC;



-- Severity association by vehicle group (crash-level, avoids multi-vehicle inflation)
WITH crash_vehicle_group AS (
  -- DISTINCT ensures each (collision_id, vehicle_group) contributes once
  -- so a 4-vehicle crash doesn’t inflate counts 4x for the same group.
  SELECT DISTINCT
    collision_id,
    vehicle_group,
    severity
  FROM core.nyc_vehicles_grouped
  WHERE vehicle_group IS NOT NULL
)
SELECT
  vehicle_group,
  COUNT(*) FILTER (WHERE severity = 'Fatal') AS fatal_crashes,
  COUNT(*) FILTER (WHERE severity = 'Injury') AS injury_crashes,
  COUNT(*) AS crashes_involving_group,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE severity = 'Fatal') / NULLIF(COUNT(*), 0),
    2
  ) AS fatal_pct
FROM crash_vehicle_group
GROUP BY vehicle_group
HAVING COUNT(*) >= 100 -- stability threshold: avoids tiny-sample “fake” rates
ORDER BY fatal_crashes DESC, injury_crashes DESC;
