-- Create a table with lactate measurements for each patient

DROP MATERIALIZED VIEW IF EXISTS lactate CASCADE;
CREATE MATERIALIZED VIEW lactate AS

-- select lactate from chartevents
WITH ce_l AS
(
	SELECT DISTINCT icustay_id, EXTRACT(epoch FROM charttime) as charttime, itemid, valuenum
	FROM chartevents
	WHERE valuenum IS NOT NULL AND itemid IN (225668,1531) 
	ORDER BY icustay_id, charttime, itemid 
)
-- select lactate from labevents
, le_l as
(
	SELECT xx.icustay_id, EXTRACT(epoch FROM f.charttime) AS charttime, f.itemid, f.valuenum
	FROM
	(
		SELECT subject_id, hadm_id, icustay_id, intime, outtime
		FROM icustays
		GROUP BY subject_id, hadm_id, icustay_id, intime, outtime
	) 
	AS xx INNER JOIN  labevents AS f ON f.hadm_id=xx.hadm_id AND f.charttime>=xx.intime-interval '1 day' AND f.charttime<=xx.outtime+interval '1 day'  
		AND f.itemid IN  (50813) AND valuenum IS NOT NULL
	ORDER BY f.hadm_id, charttime, f.itemid

)

SELECT
  co.subject_id, co.hadm_id, co.icustay_id
  , ce_l.charttime AS charttime, ce_l.itemid AS itemid, ce_l.valuenum AS valuenum
FROM aline_cohort co
INNER JOIN ce_l
  ON co.icustay_id = ce_l.icustay_id

UNION ALL

SELECT
  co.subject_id, co.hadm_id, co.icustay_id
  , le_l.charttime AS charttime, le_l.itemid AS itemid, le_l.valuenum AS valuenum
FROM aline_cohort co
LEFT JOIN le_l
  ON co.icustay_id = le_l.icustay_id


GROUP BY co.subject_id, co.hadm_id, co.icustay_id
  ,charttime, itemid, valuenum 

ORDER BY icustay_id, charttime, itemid, valuenum;