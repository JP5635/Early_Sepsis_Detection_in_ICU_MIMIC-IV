-- Hourly SOFA Score per ICU stay

-- It will create 'SOFA_Score_ALL' table
CREATE OR REPLACE TABLE `YOURDATABASE.SOFA_Score_ALL` AS
WITH icustays AS (
  SELECT
    stay_id,
    hadm_id,
    intime,
    outtime,
    TIMESTAMP_DIFF(outtime, intime, HOUR) AS n_hours
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

hour_bins AS (
  SELECT
    stay_id,
    hadm_id,
    TIMESTAMP_ADD(intime, INTERVAL hr HOUR) AS sofa_start,
    TIMESTAMP_ADD(intime, INTERVAL hr+1 HOUR) AS sofa_end
  FROM icustays,
  UNNEST(GENERATE_ARRAY(0, n_hours-1)) AS hr
),

-------------------------------
-- 1) Respiratory: PaO2/FiO2 + Ventilation
respiration_hourly AS (
  SELECT
    ce.stay_id,
    TIMESTAMP_TRUNC(ce.charttime, HOUR) AS chart_hour,
    MIN(CASE WHEN ce.itemid IN (220224,220227) THEN ce.valuenum END) AS pao2,
    MIN(CASE WHEN ce.itemid IN (223835,223836) THEN ce.valuenum END) AS fio2,
    -- Compute PaO2/FiO2 if both exist (FiO2 in % → divide by 100)
    SAFE_DIVIDE(
      MIN(CASE WHEN ce.itemid IN (220224,220227) THEN ce.valuenum END),
      MIN(CASE WHEN ce.itemid IN (223835,223836) THEN ce.valuenum END)/100.0
    ) AS pao2fio2,
    MAX(CASE WHEN vd.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS is_vent
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  LEFT JOIN `YOURDATABASE.ventilation_duration` vd
    ON ce.stay_id = vd.stay_id
       AND ce.charttime BETWEEN vd.intub_time AND vd.extub_time
  WHERE ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id, chart_hour
),

-------------------------------
-- 2) Coagulation: Platelets
coagulation_hourly AS (
  SELECT
    lb.hadm_id,
    TIMESTAMP_TRUNC(lb.charttime, HOUR) AS chart_hour,
    MIN(lb.valuenum) AS platelets_min
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` lb
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON lb.itemid = d.itemid
  WHERE LOWER(d.label) LIKE '%platelet%'
    AND lb.valuenum IS NOT NULL
  GROUP BY lb.hadm_id, chart_hour
),

-------------------------------
-- 3) Liver: Bilirubin
liver_hourly AS (
  SELECT
    lb.hadm_id,
    TIMESTAMP_TRUNC(lb.charttime, HOUR) AS chart_hour,
    MAX(lb.valuenum) AS bilirubin_max
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` lb
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON lb.itemid = d.itemid
  WHERE LOWER(d.label) LIKE '%bilirubin%'
    AND lb.valuenum IS NOT NULL
  GROUP BY lb.hadm_id, chart_hour
),

-------------------------------
-- 4) Cardiovascular: MAP + vasopressors
cardio_hourly AS (
  SELECT
    ie.stay_id,
    TIMESTAMP_TRUNC(v.charttime, HOUR) AS chart_hour,
    MIN(v.valuenum) AS mbp_min,
    MAX(CASE WHEN i.itemid IN (30047,30120) THEN i.rate ELSE 0 END) AS norepi_rate,
    MAX(CASE WHEN i.itemid IN (30044,30119,30309) THEN i.rate ELSE 0 END) AS epi_rate,
    MAX(CASE WHEN i.itemid IN (30043,30307) THEN i.rate ELSE 0 END) AS dopamine_rate,
    MAX(CASE WHEN i.itemid IN (30042,30306) THEN i.rate ELSE 0 END) AS dobutamine_rate
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` v
    ON ie.stay_id = v.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` i
    ON ie.stay_id = i.stay_id
  GROUP BY ie.stay_id, chart_hour
),

-------------------------------
-- 5) CNS: GCS
cns_hourly AS (
  SELECT
    ce.stay_id,
    TIMESTAMP_TRUNC(ce.charttime, HOUR) AS chart_hour,
    MIN(ce.valuenum) AS gcs_min
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON ce.itemid = d.itemid
  WHERE LOWER(d.label) LIKE '%gcs%'
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id, chart_hour
),

-------------------------------
-- 6) Renal: Creatinine + Urine Output
renal_hourly AS (
  SELECT
    lb.hadm_id,
    TIMESTAMP_TRUNC(lb.charttime, HOUR) AS chart_hour,
    MAX(lb.valuenum) AS creatinine_max
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` lb
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON lb.itemid = d.itemid
  WHERE LOWER(d.label) LIKE '%creatinine%'
  GROUP BY lb.hadm_id, chart_hour
),

urine_hourly AS (
  SELECT
    oe.stay_id,
    TIMESTAMP_TRUNC(oe.charttime, HOUR) AS chart_hour,
    SUM(oe.value) AS urine_output_hour
  FROM `physionet-data.mimiciv_3_1_icu.outputevents` oe
  GROUP BY oe.stay_id, chart_hour
)



-------------------------------
-- Combine all hourly components
SELECT
  h.hadm_id,
  h.stay_id,
  h.sofa_start,
  h.sofa_end,

  -- Respiratory SOFA
  CASE
    WHEN r.pao2fio2 IS NULL THEN NULL
    WHEN r.is_vent = 1 AND r.pao2fio2 < 100 THEN 4
    WHEN r.is_vent = 1 AND r.pao2fio2 < 200 THEN 3
    WHEN r.pao2fio2 < 300 THEN 2
    WHEN r.pao2fio2 < 400 THEN 1
    ELSE 0
  END AS sofa_resp,

  -- Coagulation SOFA
  CASE
    WHEN c.platelets_min IS NULL THEN NULL
    WHEN c.platelets_min < 20 THEN 4
    WHEN c.platelets_min < 50 THEN 3
    WHEN c.platelets_min < 100 THEN 2
    WHEN c.platelets_min < 150 THEN 1
    ELSE 0
  END AS sofa_coag,

  -- Liver SOFA
  CASE
    WHEN l.bilirubin_max IS NULL THEN NULL
    WHEN l.bilirubin_max >= 12 THEN 4
    WHEN l.bilirubin_max >= 6 THEN 3
    WHEN l.bilirubin_max >= 2 THEN 2
    WHEN l.bilirubin_max >= 1.2 THEN 1
    ELSE 0
  END AS sofa_liver,

  -- Cardiovascular SOFA
 
  CASE
    WHEN cv.mbp_min IS NULL AND cv.dopamine_rate IS NULL AND cv.epi_rate IS NULL AND cv.norepi_rate IS NULL AND cv.dobutamine_rate IS NULL THEN NULL
    WHEN cv.dopamine_rate > 15 OR cv.epi_rate > 0.1 OR cv.norepi_rate > 0.1 THEN 4
    WHEN cv.dopamine_rate > 5 OR cv.epi_rate <= 0.1 OR cv.norepi_rate <= 0.1 THEN 3
    WHEN cv.dopamine_rate <= 5 OR cv.dobutamine_rate > 0 THEN 2
    WHEN cv.mbp_min < 70 THEN 1
    ELSE 0
  END AS sofa_cardio,

  -- CNS SOFA
  CASE
    WHEN g.gcs_min IS NULL THEN NULL
    WHEN g.gcs_min >= 15 THEN 0
    WHEN g.gcs_min >= 13 THEN 1
    WHEN g.gcs_min >= 10 THEN 2
    WHEN g.gcs_min >= 6 THEN 3
    WHEN g.gcs_min < 6 THEN 4
    ELSE 0
  END AS sofa_cns,

  -- Renal SOFA
  CASE
    WHEN re.creatinine_max IS NULL AND u.urine_output_hour IS NULL THEN NULL
    WHEN re.creatinine_max >= 5 OR u.urine_output_hour < 200 THEN 4
    WHEN re.creatinine_max >= 3.5 OR u.urine_output_hour < 500 THEN 3
    WHEN re.creatinine_max >= 2 THEN 2
    WHEN re.creatinine_max >= 1.2 THEN 1
    ELSE 0
  END AS sofa_renal

FROM hour_bins h
LEFT JOIN respiration_hourly r
  ON h.stay_id = r.stay_id
 AND r.chart_hour >= h.sofa_start
 AND r.chart_hour < h.sofa_end
LEFT JOIN coagulation_hourly c
  ON h.hadm_id = c.hadm_id
 AND c.chart_hour >= h.sofa_start
 AND c.chart_hour < h.sofa_end
LEFT JOIN liver_hourly l
  ON h.hadm_id = l.hadm_id
LEFT JOIN cardio_hourly cv 
  ON h.stay_id = cv.stay_id 
  AND cv.chart_hour >= h.sofa_start
  AND cv.chart_hour < h.sofa_end
LEFT JOIN cns_hourly g
  ON h.stay_id = g.stay_id 
  AND g.chart_hour >= h.sofa_start
  AND g.chart_hour < h.sofa_end
LEFT JOIN renal_hourly re
  ON h.hadm_id = re.hadm_id
  AND re.chart_hour >= h.sofa_start
  AND re.chart_hour < h.sofa_end
LEFT JOIN urine_hourly u
  ON h.stay_id = u.stay_id
  AND u.chart_hour >= h.sofa_start
  AND u.chart_hour < h.sofa_end



