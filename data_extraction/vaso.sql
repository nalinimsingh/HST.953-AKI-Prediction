-- Create a table which indicates percent of time for which 
-- a patient was on a vasopressor during their ICU stay

-- List of vasopressors used:
-- norepinephrine - 30047,30120,221906
-- epinephrine - 30044,30119,30309,221289
-- phenylephrine - 30127,30128,221749
-- vasopressin - 30051,222315
-- dopamine - 30043,30307,221662
-- Isuprel - 30046,227692

DROP MATERIALIZED VIEW IF EXISTS vaso CASCADE;
CREATE MATERIALIZED VIEW vaso AS

WITH io_cv AS
(
  SELECT
    ie.icustay_id, EXTRACT(epoch FROM icu.outtime) - EXTRACT(epoch FROM icu.intime) AS icu_los_c,
    EXTRACT(epoch FROM ie.charttime) AS charttime, ie.itemid, ie.stopped, ie.rate, ie.amount
  FROM inputevents_cv ie
  LEFT JOIN icustays icu
    ON ie.icustay_id = icu.icustay_id
    
  WHERE itemid in
  (
    30047,30120 -- norepinephrine
    ,30044,30119,30309 -- epinephrine
    ,30127,30128 -- phenylephrine
    ,30051 -- vasopressin
    ,30043,30307,30125 -- dopamine
    ,30046 -- isuprel
  )
  AND rate IS NOT NULL
  AND rate > 0
)
-- select only the ITEMIDs from the inputevents_mv table related to vasopressors
, io_mv AS
(
  SELECT DISTINCT
    io.icustay_id,
    (SUM(EXTRACT(epoch FROM endtime)-EXTRACT(epoch FROM starttime)) OVER (PARTITION BY io.icustay_id)) /(EXTRACT(epoch FROM outtime) - EXTRACT(epoch FROM intime)) AS vaso_frac
  FROM inputevents_mv io
  LEFT JOIN icustays icu
    ON io.icustay_id = icu.icustay_id
  -- Subselect the vasopressor ITEMIDs
  WHERE itemid IN
  (
  221906 -- norepinephrine
  ,221289 -- epinephrine
  ,221749 -- phenylephrine
  ,222315 -- vasopressin
  ,221662 -- dopamine
  ,227692 -- isuprel
  )
  AND rate IS NOT NULL
  AND rate > 0
  AND statusdescription != 'Rewritten' -- only valid orders
)
SELECT
  co.subject_id, co.hadm_id, co.icustay_id
  , io_cv.icu_los_c, io_cv.charttime, io_cv.itemid, io_cv.stopped
  , io_mv.vaso_frac
FROM aline_cohort co
LEFT JOIN io_mv
  ON co.icustay_id = io_mv.icustay_id
LEFT JOIN io_cv
  ON co.icustay_id = io_cv.icustay_id
GROUP BY co.subject_id, co.hadm_id, co.icustay_id
	, io_cv.icu_los_c, io_cv.charttime, io_cv.itemid, io_cv.stopped
	, io_mv.vaso_frac
ORDER BY co.icustay_id;
