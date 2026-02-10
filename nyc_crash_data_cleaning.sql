-- NYC Raw Crash Data Cleaning


-- create schemas for each stage of data
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS clean;
CREATE SCHEMA IF NOT EXISTS core;


-- create a cleaned and typed table from the raw crash dataset.
CREATE TABLE IF NOT EXISTS clean.nyc_crash_data AS
SELECT
  to_date("CRASH DATE", 'MM/DD/YYYY') AS crash_date,
  NULLIF("CRASH TIME", '')::time AS crash_time,

  -- standardize borough values to a known set and null out invalid entries.
  CASE
    WHEN UPPER(TRIM("BOROUGH")) IN ('MANHATTAN', 'BROOKLYN', 'BRONX', 'THE BRONX', 'QUEENS', 'STATEN ISLAND')
      THEN UPPER(TRIM("BOROUGH"))
    ELSE NULL
  END AS borough,

  -- retain zip code and geographic coordinates for mapping and aggregation.
  "ZIP CODE" AS zip_code,
  "LATITUDE" AS latitude,
  "LONGITUDE" AS longitude,
  "LOCATION" AS crash_location,

  -- normalize street names to uppercase and remove empty values.
  NULLIF(UPPER(TRIM("ON STREET NAME")), '') AS main_street_name,
  NULLIF(UPPER(TRIM("CROSS STREET NAME")), '') AS cross_street_name,
  NULLIF(UPPER(TRIM("OFF STREET NAME")), '') AS off_street_name,

  -- convert blank casualty fields to zero and cast them as integers.
  COALESCE(NULLIF("NUMBER OF PERSONS INJURED", ''), '0')::int AS persons_injured,
  COALESCE(NULLIF("NUMBER OF PERSONS KILLED", ''), '0')::int AS persons_killed,
  COALESCE(NULLIF("NUMBER OF PEDESTRIANS INJURED", ''), '0')::int AS pedestrians_injured,
  COALESCE(NULLIF("NUMBER OF PEDESTRIANS KILLED", ''), '0')::int AS pedestrians_killed,
  COALESCE(NULLIF("NUMBER OF CYCLIST INJURED", ''), '0')::int AS cyclists_injured,
  COALESCE(NULLIF("NUMBER OF CYCLIST KILLED", ''), '0')::int AS cyclists_killed,
  COALESCE(NULLIF("NUMBER OF MOTORIST INJURED", ''), '0')::int AS motorists_injured,
  COALESCE(NULLIF("NUMBER OF MOTORIST KILLED", ''), '0')::int AS motorists_killed,

  -- preserve the collision identifier as the primary key candidate.
  "COLLISION_ID" AS collision_id,

  -- retain contributing factor fields for later normalization and analysis.
  "CONTRIBUTING FACTOR VEHICLE 1" AS contributing_factor_vehicle_1,
  "CONTRIBUTING FACTOR VEHICLE 2" AS contributing_factor_vehicle_2,
  "CONTRIBUTING FACTOR VEHICLE 3" AS contributing_factor_vehicle_3,
  "CONTRIBUTING FACTOR VEHICLE 4" AS contributing_factor_vehicle_4,
  "CONTRIBUTING FACTOR VEHICLE 5" AS contributing_factor_vehicle_5,

  -- retain vehicle type fields for later categorization and modeling.
  "VEHICLE TYPE CODE 1" AS vehicle_type_code_1,
  "VEHICLE TYPE CODE 2" AS vehicle_type_code_2,
  "VEHICLE TYPE CODE 3" AS vehicle_type_code_3,
  "VEHICLE TYPE CODE 4" AS vehicle_type_code_4,
  "VEHICLE TYPE CODE 5" AS vehicle_type_code_5
FROM raw.nyc_crash_data;



-- create indexes to improve query performance on common filters.
CREATE INDEX idx_clean_crash_date ON clean.nyc_crash_data (crash_date);
CREATE INDEX idx_clean_borough ON clean.nyc_crash_data (borough);



-- enforce uniqueness of collision identifiers.
ALTER TABLE clean.nyc_crash_data
ADD CONSTRAINT nyc_crash_data_pk PRIMARY KEY (collision_id);



-- validate that no negative casualty values exist before adding constraints.
SELECT *
FROM clean.nyc_crash_data
WHERE persons_injured < 0
   OR persons_killed < 0
   OR pedestrians_injured < 0
   OR pedestrians_killed < 0
   OR cyclists_injured < 0
   OR cyclists_killed < 0
   OR motorists_injured < 0
   OR motorists_killed < 0;



-- prevent future insertion of negative casualty counts.
ALTER TABLE clean.nyc_crash_data
ADD CONSTRAINT check_no_negative_counts
CHECK (
  persons_injured >= 0
  AND persons_killed >= 0
  AND pedestrians_injured >= 0
  AND pedestrians_killed >= 0
  AND cyclists_injured >= 0
  AND cyclists_killed >= 0
  AND motorists_injured >= 0
  AND motorists_killed >= 0
);



-- confirm raw and clean tables have matching row counts after loading.
SELECT
  (SELECT COUNT(*) FROM raw.nyc_crash_data) AS raw_rows,
  (SELECT COUNT(*) FROM clean.nyc_crash_data) AS clean_rows;



-- verify that core identifiers are fully populated.
SELECT
  COUNT(*) FILTER (WHERE collision_id IS NULL) AS null_collision_id,
  COUNT(*) FILTER (WHERE crash_date IS NULL) AS null_crash_date
FROM clean.nyc_crash_data;



-- identify records where subgroup casualty totals exceed overall totals.
SELECT COUNT(*) AS bad_rows
FROM clean.nyc_crash_data
WHERE pedestrians_injured + cyclists_injured + motorists_injured > persons_injured
   OR pedestrians_killed + cyclists_killed + motorists_killed > persons_killed;



-- add a flag to mark rows with casualty total inconsistencies.
ALTER TABLE clean.nyc_crash_data
ADD COLUMN casualty_mismatch_flag BOOLEAN;



-- populate the casualty mismatch flag for inconsistent records.
UPDATE clean.nyc_crash_data
SET casualty_mismatch_flag =
  (pedestrians_injured + cyclists_injured + motorists_injured) > persons_injured
  OR (pedestrians_killed + cyclists_killed + motorists_killed) > persons_killed;



-- verify crash dates fall within a reasonable time range.
SELECT
  MIN(crash_date) AS min_date,
  MAX(crash_date) AS max_date
FROM clean.nyc_crash_data;



-- ensure crash times fall within valid daily bounds.
SELECT COUNT(*) AS bad_times
FROM clean.nyc_crash_data
WHERE crash_time IS NOT NULL
  AND (crash_time < TIME '00:00' OR crash_time > TIME '23:59');



-- detecting records with incomplete latittude/longitude data.
SELECT COUNT(*) AS mismatched_geo
FROM clean.nyc_crash_data
WHERE (latitude IS NULL AND longitude IS NOT NULL)
   OR (latitude IS NOT NULL AND longitude IS NULL);



-- summarize boroughs with missing geographic coordinates.
SELECT borough, COUNT(*)
FROM clean.nyc_crash_data
WHERE borough IS NOT NULL
  AND (latitude IS NULL OR longitude IS NULL)
GROUP BY borough;



-- add a flag to mark borough records without usable geographic data.
ALTER TABLE clean.nyc_crash_data
ADD COLUMN borough_without_geo_flag BOOLEAN;



-- populate the borough geographic completeness flag.
UPDATE clean.nyc_crash_data
SET borough_without_geo_flag =
  borough IS NOT NULL
  AND (latitude IS NULL OR longitude IS NULL);



-- inspect contributing factor frequencies to identify consolidation candidates.
SELECT
  contributing_factor_vehicle_1,
  COUNT(*) AS cnt
FROM clean.nyc_crash_data
GROUP BY contributing_factor_vehicle_1
ORDER BY cnt DESC;



-- identify contributing factor values that differ only by formatting.
SELECT
  UPPER(TRIM(contributing_factor_vehicle_1)) AS norm_factor,
  COUNT(*) AS cnt,
  COUNT(DISTINCT contributing_factor_vehicle_1) AS variants
FROM clean.nyc_crash_data
WHERE contributing_factor_vehicle_1 IS NOT NULL
GROUP BY UPPER(TRIM(contributing_factor_vehicle_1))
HAVING COUNT(DISTINCT contributing_factor_vehicle_1) > 1
ORDER BY cnt DESC;



-- inspect variants for illegal drug related contributing factors.
SELECT
  contributing_factor_vehicle_1 AS raw_value,
  COUNT(*) AS cnt
FROM clean.nyc_crash_data
WHERE UPPER(TRIM(contributing_factor_vehicle_1)) = 'DRUGS (ILLEGAL)'
GROUP BY contributing_factor_vehicle_1
ORDER BY cnt DESC;



-- inspect variants for cellphone related contributing factors.
SELECT
  contributing_factor_vehicle_1 AS raw_value,
  COUNT(*) AS cnt
FROM clean.nyc_crash_data
WHERE UPPER(TRIM(contributing_factor_vehicle_1)) = 'CELL PHONE (HAND-HELD)'
GROUP BY contributing_factor_vehicle_1
ORDER BY cnt DESC;



-- normalize contributing factor fields to remove casing and whitespace differences.
UPDATE clean.nyc_crash_data
SET
  contributing_factor_vehicle_1 = CASE
    WHEN contributing_factor_vehicle_1 IS NULL THEN NULL
    ELSE UPPER(regexp_replace(TRIM(contributing_factor_vehicle_1), '\s+', ' ', 'g'))
  END,
  contributing_factor_vehicle_2 = CASE
    WHEN contributing_factor_vehicle_2 IS NULL THEN NULL
    ELSE UPPER(regexp_replace(TRIM(contributing_factor_vehicle_2), '\s+', ' ', 'g'))
  END,
  contributing_factor_vehicle_3 = CASE
    WHEN contributing_factor_vehicle_3 IS NULL THEN NULL
    ELSE UPPER(regexp_replace(TRIM(contributing_factor_vehicle_3), '\s+', ' ', 'g'))
  END,
  contributing_factor_vehicle_4 = CASE
    WHEN contributing_factor_vehicle_4 IS NULL THEN NULL
    ELSE UPPER(regexp_replace(TRIM(contributing_factor_vehicle_4), '\s+', ' ', 'g'))
  END,
  contributing_factor_vehicle_5 = CASE
    WHEN contributing_factor_vehicle_5 IS NULL THEN NULL
    ELSE UPPER(regexp_replace(TRIM(contributing_factor_vehicle_5), '\s+', ' ', 'g'))
  END;



-- inspect vehicle type frequencies to identify redundant categories.
SELECT
  vehicle_type_code_1,
  COUNT(*) AS cnt
FROM clean.nyc_crash_data
GROUP BY vehicle_type_code_1
ORDER BY cnt DESC;



-- identify vehicle type values that differ only by formatting.
SELECT
  UPPER(TRIM(vehicle_type_code_1)) AS norm_factor,
  COUNT(*) AS cnt,
  COUNT(DISTINCT vehicle_type_code_1) AS variants
FROM clean.nyc_crash_data
WHERE vehicle_type_code_1 IS NOT NULL
GROUP BY UPPER(TRIM(vehicle_type_code_1))
HAVING COUNT(DISTINCT vehicle_type_code_1) > 1
ORDER BY cnt DESC;



-- inspect formatting variants for sedan vehicle types.
SELECT
  vehicle_type_code_1 AS raw_value,
  COUNT(*) AS cnt
FROM clean.nyc_crash_data
WHERE UPPER(TRIM(vehicle_type_code_1)) = 'SEDAN'
GROUP BY vehicle_type_code_1
ORDER BY cnt DESC;



-- normalize vehicle type fields to remove casing and whitespace differences.
UPDATE clean.nyc_crash_data
SET
  vehicle_type_code_1 = CASE
    WHEN vehicle_type_code_1 IS NULL THEN NULL
    ELSE UPPER(regexp_replace(TRIM(vehicle_type_code_1), '\s+', ' ', 'g'))
  END,
  vehicle_type_code_2 = CASE
    WHEN vehicle_type_code_2 IS NULL THEN NULL
    ELSE UPPER(regexp_replace(TRIM(vehicle_type_code_2), '\s+', ' ', 'g'))
  END,
  vehicle_type_code_3 = CASE
    WHEN vehicle_type_code_3 IS NULL THEN NULL
    ELSE UPPER(regexp_replace(TRIM(vehicle_type_code_3), '\s+', ' ', 'g'))
  END,
  vehicle_type_code_4 = CASE
    WHEN vehicle_type_code_4 IS NULL THEN NULL
    ELSE UPPER(regexp_replace(TRIM(vehicle_type_code_4), '\s+', ' ', 'g'))
  END,
  vehicle_type_code_5 = CASE
    WHEN vehicle_type_code_5 IS NULL THEN NULL
    ELSE UPPER(regexp_replace(TRIM(vehicle_type_code_5), '\s+', ' ', 'g'))
  END;



-- confirm there are no duplicate collision ids with conflicting injury counts.
SELECT
  collision_id,
  COUNT(DISTINCT persons_injured) AS distinct_injuries
FROM clean.nyc_crash_data
GROUP BY collision_id
HAVING COUNT(*) > 1
   AND COUNT(DISTINCT persons_injured) > 1;



-- identify extreme casualty values to validate plausibility.
SELECT
  MAX(persons_injured) AS max_injured,
  MAX(persons_killed) AS max_killed
FROM clean.nyc_crash_data;



-- count crashes with no injuries or fatalities for baseline analysis.
SELECT COUNT(*) AS no_injury_no_fatality
FROM clean.nyc_crash_data
WHERE persons_injured = 0
  AND persons_killed = 0;



-- standardize bronx borough naming to a single canonical value.
UPDATE clean.nyc_crash_data
SET borough = 'THE BRONX'
WHERE borough = 'BRONX';



-- remove the redundant location column since latitude and longitude are authoritative.
ALTER TABLE clean.nyc_crash_data
DROP COLUMN crash_location;