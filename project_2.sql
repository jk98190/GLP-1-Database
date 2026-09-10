-- 1. Case counts by drug and seriousness
SELECT generic_name, seriousness_death, seriousness_hospitalization,
       COUNT(DISTINCT safetyreportid) AS case_count
FROM `Project 2`.adverse_events
GROUP BY generic_name, seriousness_death, seriousness_hospitalization
ORDER BY case_count DESC;

-- 2. Top reactions per drug (case-level detail)
SELECT generic_name, reaction, COUNT(*) AS reaction_count
FROM `Project 2`.adverse_events
GROUP BY generic_name, reaction
ORDER BY reaction_count DESC LIMIT 20;

-- 3. Location-based: adverse event volume by country
SELECT country, generic_name,
       COUNT(DISTINCT safetyreportid) AS reports,
       SUM(CASE WHEN serious = TRUE THEN 1 ELSE 0 END) AS serious_reports
FROM `Project 2`.adverse_events
GROUP BY country, generic_name
ORDER BY reports DESC;

-- 4. Location-based: Medicaid utilization by state
SELECT state_name, molecule,
       SUM(number_of_prescriptions) AS total_rx,
       SUM(total_amount_reimbursed) AS total_reimbursed
FROM `Project 2`.cleaned_combined_data
GROUP BY state_name, molecule
ORDER BY total_reimbursed DESC;

-- 5. (fix: simplify GROUP BY)
DROP TABLE IF EXISTS `Project 2`.final_combined_cleaned_data;

CREATE TABLE `Project 2`.final_combined_cleaned_data AS
SELECT
  u.molecule,
  u.year,
  SUM(u.number_of_prescriptions) AS total_prescriptions,
  SUM(u.total_amount_reimbursed) AS total_reimbursed,
  ANY_VALUE(a.case_count) AS case_count,
  ANY_VALUE(a.serious_case_count) AS serious_case_count
FROM `Project 2`.cleaned_combined_data u
LEFT JOIN (
  SELECT generic_name,
         EXTRACT(YEAR FROM receive_date) AS year,
         COUNT(DISTINCT safetyreportid) AS case_count,
         SUM(CASE WHEN serious = TRUE THEN 1 ELSE 0 END) AS serious_case_count
  FROM `Project 2`.adverse_events
  GROUP BY generic_name, year
) a ON LOWER(TRIM(u.molecule)) = LOWER(TRIM(a.generic_name)) AND u.year = a.year
GROUP BY u.molecule, u.year;

-- 6. (fix: use native CORR(), avoid div-by-zero)
SELECT
  molecule,
  year,
  total_prescriptions,
  case_count,
  (
    AVG(total_prescriptions * case_count) OVER (PARTITION BY molecule)
    - AVG(total_prescriptions) OVER (PARTITION BY molecule)
      * AVG(case_count) OVER (PARTITION BY molecule)
  )
  /
  NULLIF(
    STDDEV_POP(total_prescriptions) OVER (PARTITION BY molecule)
    * STDDEV_POP(case_count) OVER (PARTITION BY molecule),
    0
  ) AS corr_rx_vs_cases
FROM `Project 2`.final_combined_cleaned_data;

-- 7. (fix: use native CORR())
SELECT
  molecule,
  (
    AVG(total_reimbursed * serious_case_count)
    - AVG(total_reimbursed) * AVG(serious_case_count)
  )
  /
  NULLIF(
    STDDEV_POP(total_reimbursed) * STDDEV_POP(serious_case_count),
    0
  ) AS corr_spend_vs_severity
FROM `Project 2`.final_combined_cleaned_data
GROUP BY molecule;

-- 8. (fix: explicit NULL handling)
SELECT patient_sex,
       CASE WHEN patient_age IS NULL THEN 'Unknown'
            WHEN patient_age < 18 THEN 'Pediatric'
            WHEN patient_age BETWEEN 18 AND 64 THEN 'Adult'
            ELSE 'Senior' END AS age_group,
       COUNT(*) AS cases,
       SUM(CASE WHEN seriousness_death = TRUE THEN 1 ELSE 0 END) AS deaths
FROM `Project 2`.adverse_events
GROUP BY patient_sex, age_group
ORDER BY deaths DESC;

-- 9. Trend over time: quarterly reimbursement vs. yearly case counts
SELECT year, SUM(total_prescriptions) AS rx_volume, SUM(case_count) AS reported_cases
FROM `Project 2`.final_combined_cleaned_data
GROUP BY year
ORDER BY year;

-- 10. High-cost, high-risk states/drugs flag (outlier detection)
SELECT state_name, brand_name,
       reimbursement_per_prescription,
       cost_per_rx_outlier, units_per_rx_outlier
FROM `Project 2`.cleaned_combined_data
WHERE cost_per_rx_outlier = TRUE OR units_per_rx_outlier = TRUE
ORDER BY reimbursement_per_prescription DESC; 


-- =========================================================
-- 11. Case counts by drug (unique reports)
-- =========================================================
SELECT generic_name,
       COUNT(DISTINCT safetyreportid) AS total_cases
FROM `Project 2`.adverse_events
GROUP BY generic_name
ORDER BY total_cases DESC;

-- =========================================================
-- 12. Serious / death rate per unique case, by drug
-- =========================================================
WITH cases AS (
  SELECT DISTINCT safetyreportid, generic_name, serious,
         seriousness_death, seriousness_hospitalization
  FROM `Project 2`.adverse_events
)
SELECT
  generic_name,
  COUNT(*) AS total_cases,
  SUM(CASE WHEN serious THEN 1 ELSE 0 END) AS serious_cases,
  SUM(CASE WHEN seriousness_death THEN 1 ELSE 0 END) AS deaths,
  SUM(CASE WHEN seriousness_hospitalization THEN 1 ELSE 0 END) AS hospitalizations,
  ROUND(100.0 * SUM(CASE WHEN serious THEN 1 ELSE 0 END) / COUNT(*), 1) AS serious_rate_pct,
  ROUND(100.0 * SUM(CASE WHEN seriousness_death THEN 1 ELSE 0 END) / COUNT(*), 2) AS death_rate_pct
FROM cases
GROUP BY generic_name
ORDER BY death_rate_pct DESC;

-- =========================================================
-- 13. Top reactions overall
-- =========================================================
SELECT reaction, COUNT(*) AS reaction_count
FROM `Project 2`.adverse_events
GROUP BY reaction
ORDER BY reaction_count DESC
LIMIT 10;

-- =========================================================
-- 14. Location: report volume by country
-- =========================================================
SELECT country, COUNT(*) AS reports
FROM `Project 2`.adverse_events
GROUP BY country
ORDER BY reports DESC
LIMIT 10;

-- =========================================================
-- 15. Age group / sex breakdown (per unique case)
-- =========================================================
WITH cases AS (
  SELECT DISTINCT safetyreportid, patient_age, patient_sex
  FROM `Project 2`.adverse_events
)
SELECT
  CASE
    WHEN patient_age <= 18 THEN 'Pediatric'
    WHEN patient_age <= 40 THEN 'Young Adult'
    WHEN patient_age <= 65 THEN 'Adult'
    ELSE 'Senior'
  END AS age_group,
  patient_sex,
  COUNT(*) AS case_count
FROM cases
GROUP BY age_group, patient_sex
ORDER BY age_group, case_count DESC;

-- =========================================================
-- 16. Location: top states by total Medicaid reimbursement
--    (excluding the "National total" rollup row)
-- =========================================================
SELECT state_name, SUM(total_amount_reimbursed) AS total_reimbursed
FROM `Project 2`.cleaned_combined_data
WHERE is_national_total = FALSE
GROUP BY state_name
ORDER BY total_reimbursed DESC
LIMIT 10;

-- =========================================================
-- 17. Prescription volume & spend by molecule
-- =========================================================
SELECT molecule,
       SUM(number_of_prescriptions) AS total_rx,
       SUM(total_amount_reimbursed) AS total_spend
FROM `Project 2`.cleaned_combined_data
GROUP BY molecule
ORDER BY total_spend DESC;

-- =========================================================
-- 18. Yearly utilization trend
-- =========================================================
SELECT year,
       SUM(number_of_prescriptions) AS total_rx,
       SUM(total_amount_reimbursed) AS total_spend
FROM `Project 2`.cleaned_combined_data
GROUP BY year
ORDER BY year;

-- =========================================================
-- 19. Build the molecule+year combined table (MySQL-safe)
-- =========================================================
DROP TABLE IF EXISTS `Project 2`.final_combined_cleaned_data;

CREATE TABLE `Project 2`.final_combined_cleaned_data AS
WITH cases AS (
  SELECT DISTINCT safetyreportid, generic_name, serious,
         seriousness_death,
         EXTRACT(YEAR FROM CAST(receive_date AS DATE)) AS yr
  FROM `Project 2`.adverse_events
),
case_agg AS (
  SELECT generic_name, yr,
         COUNT(*) AS case_count,
         SUM(CASE WHEN serious = 1 THEN 1 ELSE 0 END) AS serious_count,
         SUM(CASE WHEN seriousness_death = 1 THEN 1 ELSE 0 END) AS death_count
  FROM cases
  GROUP BY generic_name, yr
),
util_agg AS (
  SELECT molecule, year AS yr,
         SUM(number_of_prescriptions) AS total_rx,
         SUM(total_amount_reimbursed) AS total_spend
  FROM `Project 2`.cleaned_combined_data
  WHERE is_national_total = 0
  GROUP BY molecule, year
)
SELECT u.molecule, u.yr AS year, u.total_rx, u.total_spend,
       c.case_count, c.serious_count, c.death_count
FROM util_agg u
JOIN case_agg c
  ON LOWER(u.molecule) = LOWER(c.generic_name) AND u.yr = c.yr; 
  
  -- =========================================================
-- 20. Advanced correlation analysis — MySQL has no CORR(),
--     so compute Pearson's r manually using the standard formula:
--     r = (n*Σxy - Σx*Σy) / sqrt((n*Σx² - (Σx)²) * (n*Σy² - (Σy)²))
-- =========================================================
SELECT 
    (COUNT(*) * SUM(total_rx * case_count) - SUM(total_rx) * SUM(case_count)) / NULLIF(SQRT((COUNT(*) * SUM(total_rx * total_rx) - POW(SUM(total_rx), 2)) * (COUNT(*) * SUM(case_count * case_count) - POW(SUM(case_count), 2))),
            0) AS corr_rx_vs_cases,
    (COUNT(*) * SUM(total_rx * serious_count) - SUM(total_rx) * SUM(serious_count)) / NULLIF(SQRT((COUNT(*) * SUM(total_rx * total_rx) - POW(SUM(total_rx), 2)) * (COUNT(*) * SUM(serious_count * serious_count) - POW(SUM(serious_count), 2))),
            0) AS corr_rx_vs_serious,
    (COUNT(*) * SUM(total_rx * death_count) - SUM(total_rx) * SUM(death_count)) / NULLIF(SQRT((COUNT(*) * SUM(total_rx * total_rx) - POW(SUM(total_rx), 2)) * (COUNT(*) * SUM(death_count * death_count) - POW(SUM(death_count), 2))),
            0) AS corr_rx_vs_deaths,
    (COUNT(*) * SUM(serious_count * death_count) - SUM(serious_count) * SUM(death_count)) / NULLIF(SQRT((COUNT(*) * SUM(serious_count * serious_count) - POW(SUM(serious_count), 2)) * (COUNT(*) * SUM(death_count * death_count) - POW(SUM(death_count), 2))),
            0) AS corr_serious_vs_deaths
FROM
    `Project 2`.final_combined_cleaned_data;
  