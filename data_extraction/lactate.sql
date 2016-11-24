-- Create a table with max lactate measurement within first 72 hours 
-- of admission to ICU for each patient

DROP MATERIALIZED VIEW IF EXISTS lactate CASCADE;
CREATE MATERIALIZED VIEW lactate AS

-- select lactate from chartevents
WITH ce_l AS
(
	SELECT DISTINCT ce.icustay_id, intime, EXTRACT(epoch FROM charttime) as charttime, itemid, valuenum
	FROM chartevents ce
	LEFT JOIN icustays ic
	  ON ce.icustay_id = ic.icustay_id
	WHERE valuenum IS NOT NULL AND itemid IN (225668,1531) 
	ORDER BY ce.icustay_id, charttime, itemid 
)

-- select lactate from labevents
, le_l as
(
	SELECT xx.icustay_id, xx.intime, EXTRACT(epoch FROM f.charttime) AS charttime, f.itemid, f.valuenum
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

-- select max lactate value within first 72 hours after admission to ICU
SELECT subject_id, hadm_id, icustay_id, MAX(valuenum) AS max_val
FROM 
(
	SELECT
	  ic.subject_id, ic.hadm_id, ic.icustay_id
	  , ce_l.intime AS intime, ce_l.charttime AS charttime, ce_l.itemid AS itemid, ce_l.valuenum AS valuenum
	FROM icustays ic
	INNER JOIN ce_l
	  ON ic.icustay_id = ce_l.icustay_id

	UNION ALL

	SELECT
	  ic.subject_id, ic.hadm_id, ic.icustay_id
	  , le_l.intime AS intime, le_l.charttime AS charttime, le_l.itemid AS itemid, le_l.valuenum AS valuenum
	FROM icustays ic
	LEFT JOIN le_l
	  ON ic.icustay_id = le_l.icustay_id
) AS all_l
WHERE charttime < EXTRACT(epoch FROM intime) + 72*60*60
GROUP BY subject_id, hadm_id, icustay_id
ORDER BY subject_id, hadm_id, icustay_id, max_val
