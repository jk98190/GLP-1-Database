

-- =========================================================
-- 1. Case counts by drug and seriousness
-- =========================================================
SELECT generic_name, seriousness_death, seriousness_hospitalization,
       COUNT(DISTINCT safetyreportid) AS case_count
FROM `Project 2`.adverse_events
GROUP BY generic_name, seriousness_death, seriousness_hospitalization
ORDER BY case_count DESC;

-- =========================================================
-- 2. Top reactions per drug (case-level detail)
-- =========================================================
SELECT generic_name, reaction, COUNT(*) AS reaction_count
FROM `Project 2`.adverse_events
GROUP BY generic_name, reaction
ORDER BY reaction_count DESC
LIMIT 20;

-- =========================================================
-- 3. Adverse event volume by country and drug
-- =========================================================
SELECT country, generic_name,
       COUNT(DISTINCT safetyreportid) AS reports,
       SUM(CASE WHEN serious = 1 THEN 1 ELSE 0 END) AS serious_reports
FROM `Project 2`.adverse_events
GROUP BY country, generic_name
ORDER BY reports DESC;

-- =========================================================
-- 4. Medicaid utilization by state and molecule
-- =========================================================
SELECT state_name, molecule,
       SUM(number_of_prescriptions) AS total_rx,
       SUM(total_amount_reimbursed) AS total_reimbursed
FROM `Project 2`.cleaned_combined_data
WHERE is_national_total = 0
GROUP BY state_name, molecule
ORDER BY total_reimbursed DESC;

-- =========================================================
-- 5. Serious / death rate per unique case, by drug
-- =========================================================
WITH cases AS (
  SELECT DISTINCT safetyreportid, generic_name, serious,
         seriousness_death, seriousness_hospitalization
  FROM `Project 2`.adverse_events
)
SELECT
  generic_name,
  COUNT(*) AS total_cases,
  SUM(CASE WHEN serious = 1 THEN 1 ELSE 0 END) AS serious_cases,
  SUM(CASE WHEN seriousness_death = 1 THEN 1 ELSE 0 END) AS deaths,
  SUM(CASE WHEN seriousness_hospitalization = 1 THEN 1 ELSE 0 END) AS hospitalizations,
  ROUND(100.0 * SUM(CASE WHEN serious = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS serious_rate_pct,
  ROUND(100.0 * SUM(CASE WHEN seriousness_death = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS death_rate_pct
FROM cases
GROUP BY generic_name
ORDER BY death_rate_pct DESC;

-- =========================================================
-- 6. Top reactions overall
-- =========================================================
SELECT reaction, COUNT(*) AS reaction_count
FROM `Project 2`.adverse_events
GROUP BY reaction
ORDER BY reaction_count DESC
LIMIT 10;

-- =========================================================
-- 7. Report volume by country
-- =========================================================
SELECT country, COUNT(*) AS reports
FROM `Project 2`.adverse_events
GROUP BY country
ORDER BY reports DESC
LIMIT 10;

-- =========================================================
-- 8. Age group / sex breakdown, deaths included
--    (single consistent bucket definition, explicit NULL handling,
--     applied per unique case so multi-reaction cases aren't
--     double-counted)
-- =========================================================
WITH cases AS (
  SELECT DISTINCT safetyreportid, patient_age, patient_sex, seriousness_death
  FROM `Project 2`.adverse_events
)
SELECT
  patient_sex,
  CASE
    WHEN patient_age IS NULL THEN 'Unknown'
    WHEN patient_age < 18 THEN 'Pediatric'
    WHEN patient_age < 41 THEN 'Young Adult'
    WHEN patient_age < 65 THEN 'Adult'
    ELSE 'Senior'
  END AS age_group,
  COUNT(*) AS cases,
  SUM(CASE WHEN seriousness_death = 1 THEN 1 ELSE 0 END) AS deaths
FROM cases
GROUP BY patient_sex, age_group
ORDER BY deaths DESC;

-- =========================================================
-- 9. Top states by total Medicaid reimbursement
--    (excludes the "National total" rollup row)
-- =========================================================
SELECT state_name, SUM(total_amount_reimbursed) AS total_reimbursed
FROM `Project 2`.cleaned_combined_data
WHERE is_national_total = 0
GROUP BY state_name
ORDER BY total_reimbursed DESC
LIMIT 10;

-- =========================================================
-- 10. Yearly utilization trend
-- =========================================================
SELECT year,
       SUM(number_of_prescriptions) AS total_rx,
       SUM(total_amount_reimbursed) AS total_spend
FROM `Project 2`.cleaned_combined_data
WHERE is_national_total = 0
GROUP BY year
ORDER BY year;

-- =========================================================
-- 11. High-cost, high-risk states/drugs flag (outlier detection)
-- =========================================================
SELECT state_name, brand_name,
       reimbursement_per_prescription,
       cost_per_rx_outlier, units_per_rx_outlier
FROM `Project 2`.cleaned_combined_data
WHERE cost_per_rx_outlier = 1 OR units_per_rx_outlier = 1
ORDER BY reimbursement_per_prescription DESC;

-- =========================================================
-- 12. Build the molecule+year combined table
--     (ONE definitive version — replaces the old #5 and #19,
--     which built the same table twice with conflicting schemas)
-- =========================================================
DROP TABLE IF EXISTS `Project 2`.final_combined_cleaned_data;

CREATE TABLE `Project 2`.final_combined_cleaned_data AS
WITH cases AS (
  SELECT DISTINCT
         safetyreportid,
         generic_name,
         serious,
         seriousness_death,
         EXTRACT(YEAR FROM CAST(receive_date AS DATE)) AS yr
  FROM `Project 2`.adverse_events
),
case_agg AS (
  SELECT generic_name,
         yr,
         COUNT(*) AS case_count,
         SUM(CASE WHEN serious = 1 THEN 1 ELSE 0 END) AS serious_count,
         SUM(CASE WHEN seriousness_death = 1 THEN 1 ELSE 0 END) AS death_count
  FROM cases
  GROUP BY generic_name, yr
)
SELECT *
FROM case_agg;

-- =========================================================
-- 13. Quarterly/yearly trend: prescription volume vs. reported cases
-- =========================================================
SELECT yr AS year,
       SUM(case_count) AS reported_cases
FROM `Project 2`.final_combined_cleaned_data
GROUP BY yr
ORDER BY yr;

-- =========================================================
-- 14. Correlation analysis (Pearson's r) — MySQL has no CORR(),
--     so compute it manually:
--     r = (n*Sum(xy) - Sum(x)*Sum(y))
--         / sqrt((n*Sum(x^2) - Sum(x)^2) * (n*Sum(y^2) - Sum(y)^2))
--     Computed once per molecule (was previously duplicated as
--     both a windowed version and a manual version, with the
--     windowed version referencing a column set that no longer
--     existed after the table got rebuilt).
-- =========================================================
SELECT 
    generic_name,
    (COUNT(*) * SUM(serious_count * death_count) - SUM(serious_count) * SUM(death_count)) / NULLIF(SQRT((COUNT(*) * SUM(serious_count * serious_count) - POW(SUM(serious_count), 2)) * (COUNT(*) * SUM(death_count * death_count) - POW(SUM(death_count), 2))),
            0) AS corr_serious_vs_deaths
FROM
    `Project 2`.final_combined_cleaned_data
GROUP BY generic_name
HAVING COUNT(*) > 2;  -- correlation is meaningless with <3 points
