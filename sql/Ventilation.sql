-- ventilation events
-- It will create 'ventilation_duration' table
CREATE OR REPLACE TABLE `YOURDATABASE.ventilation_duration` AS

WITH proc AS (
    SELECT
        p.subject_id,
        p.hadm_id,
        p.stay_id,å
        p.starttime,
        p.endtime,
        p.itemid,
        d.label
    FROM physionet-data.mimiciv_3_1_icu.procedureevents p
    INNER JOIN physionet-data.mimiciv_3_1_icu.d_items d
        ON p.itemid = d.itemid
    WHERE LOWER(d.label) LIKE '%intubation%'
       OR LOWER(d.label) LIKE '%extubation%'
       OR LOWER(d.label) LIKE '%tracheostomy%'
),

-- focus on intubation events
intub AS (
    SELECT subject_id, hadm_id, stay_id,
           starttime AS intub_time,
           endtime   AS proc_end,
           label
    FROM proc
    WHERE LOWER(label) LIKE '%intubation%'
),
extub AS (
    SELECT subject_id, hadm_id, stay_id,
           starttime AS extub_time,
           label
    FROM proc
    WHERE LOWER(label) LIKE '%extubation%'
),

-- match intubation to next extubation within same stay
paired AS (
    SELECT i.subject_id, i.hadm_id, i.stay_id,
           i.intub_time,
           MIN(e.extub_time) AS extub_time
    FROM intub i
    LEFT JOIN extub e
      ON i.stay_id = e.stay_id
     AND e.extub_time > i.intub_time
    GROUP BY i.subject_id, i.hadm_id, i.stay_id, i.intub_time
),

-- bring in ICU outtime in case extubation is missing
paired_with_icu AS (
    SELECT p.subject_id, p.hadm_id, p.stay_id,
           p.intub_time,
           COALESCE(p.extub_time, i.outtime) AS extub_time
    FROM paired p
    INNER JOIN physionet-data.mimiciv_3_1_icu.icustays i
      ON p.stay_id = i.stay_id
)

SELECT
    subject_id,
    hadm_id,
    stay_id,
    intub_time,
    extub_time,
    DATETIME_DIFF(extub_time, intub_time, HOUR) AS vent_hours
FROM paired_with_icu
WHERE extub_time > intub_time
ORDER BY subject_id, intub_time;