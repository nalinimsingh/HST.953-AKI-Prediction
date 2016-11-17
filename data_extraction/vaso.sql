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
  select
    icustay_id, charttime, itemid, stopped, rate, amount
  from inputevents_cv
  where itemid in
  (
    30047,30120 -- norepinephrine
    ,30044,30119,30309 -- epinephrine
    ,30127,30128 -- phenylephrine
    ,30051 -- vasopressin
    ,30043,30307,30125 -- dopamine
    ,30046 -- isuprel
  )
  and rate is not null
  and rate > 0
)
-- select only the ITEMIDs from the inputevents_mv table related to vasopressors
, io_mv as
(
  select
    icustay_id, linkorderid, starttime, endtime
  from inputevents_mv io
  -- Subselect the vasopressor ITEMIDs
  where itemid in
  (
  221906 -- norepinephrine
  ,221289 -- epinephrine
  ,221749 -- phenylephrine
  ,222315 -- vasopressin
  ,221662 -- dopamine
  ,227692 -- isuprel
  )
  and rate is not null
  and rate > 0
  and statusdescription != 'Rewritten' -- only valid orders
)
SELECT
  co.subject_id, co.hadm_id, co.icustay_id
  , io_cv.charttime, io_cv.itemid, io_cv.stopped
  , io_mv.linkorderid, io_mv.starttime, io_mv.endtime
FROM aline_cohort co
LEFT JOIN io_mv
  ON co.icustay_id = io_mv.icustay_id
LEFT JOIN io_cv
  ON co.icustay_id = io_cv.icustay_id
GROUP BY co.subject_id, co.hadm_id, co.icustay_id
	, io_cv.charttime, io_cv.itemid, io_cv.stopped
	, io_mv.linkorderid, io_mv.starttime, io_mv.endtime 
ORDER BY co.icustay_id;
