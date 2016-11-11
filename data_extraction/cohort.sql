/* Patients over 18 with icustay lengths over 3 days */

DROP MATERIALIZED view if exists age18survive3;
CREATE materialized view age18survive3 as(
WITH tmp as(
SELECT a.subject_id, p.gender, a.ethnicity, 
	EXTRACT(EPOCH FROM(a.admittime-p.dob))/(365.25*24*3600) as age,
	a.hadm_id, a.admittime, a.dischtime, 
	a.admission_type, a.admission_location, 
	a.discharge_location, a.edregtime, a.edouttime, 
	a.diagnosis, p.dod, p.dod_hosp, a.has_chartevents_data
FROM admissions a
INNER JOIN patients p
      ON a.subject_id = p.subject_id -- 50765 hospital admissions 
)
SELECT t.*, i.icustay_id, i.dbsource, i.intime, i.outtime, i.los
FROM tmp t
INNER JOIN icustays i
ON t.hadm_id = i.hadm_id
   WHERE age>=18
   AND los>=3
ORDER BY subject_id, admittime, intime
); /* 19534 icustays. Does not include readmissions in same hadm_id combining to make longer icustay. select count(distinct(icustay_id)) from age18survive3; matches*/




/* Sepsis. Taken from https://github.com/MIT-LCP/mimic-code/blob/master/sepsis/angus.sql */

-- Appendix 1: ICD9-codes (infection)
DROP MATERIALIZED view if exists angus_sepsis;
CREATE MATERIALIZED VIEW angus_sepsis as

WITH infection_group AS (
	SELECT subject_id, hadm_id,
	CASE
		WHEN substring(icd9_code,1,3) IN ('001','002','003','004','005','008',
			   '009','010','011','012','013','014','015','016','017','018',
			   '020','021','022','023','024','025','026','027','030','031',
			   '032','033','034','035','036','037','038','039','040','041',
			   '090','091','092','093','094','095','096','097','098','100',
			   '101','102','103','104','110','111','112','114','115','116',
			   '117','118','320','322','324','325','420','421','451','461',
			   '462','463','464','465','481','482','485','486','494','510',
			   '513','540','541','542','566','567','590','597','601','614',
			   '615','616','681','682','683','686','730') THEN 1
		WHEN substring(icd9_code,1,4) IN ('5695','5720','5721','5750','5990','7110',
				'7907','9966','9985','9993') THEN 1
		WHEN substring(icd9_code,1,5) IN ('49121','56201','56203','56211','56213',
				'56983') THEN 1
		ELSE 0 END AS infection
	FROM MIMICIII.DIAGNOSES_ICD),
-- Appendix 2: ICD9-codes (organ dysfunction)
	organ_diag_group as (
	SELECT subject_id, hadm_id,
		CASE
		-- Acute Organ Dysfunction Diagnosis Codes
		WHEN substring(icd9_code,1,3) IN ('458','293','570','584') THEN 1
		WHEN substring(icd9_code,1,4) IN ('7855','3483','3481',
				'2874','2875','2869','2866','5734')  THEN 1
		ELSE 0 END AS organ_dysfunction,
		-- Explicit diagnosis of severe sepsis or septic shock
		CASE
		WHEN substring(icd9_code,1,5) IN ('99592','78552')  THEN 1
		ELSE 0 END AS explicit_sepsis
	FROM MIMICIII.DIAGNOSES_ICD),

-- Mechanical ventilation
	organ_proc_group as (
	SELECT subject_id, hadm_id,
		CASE
		WHEN substring(icd9_code,1,4) IN ('9670','9671','9672') THEN 1
		ELSE 0 END AS mech_vent
	FROM MIMICIII.PROCEDURES_ICD),

-- Aggregate
	aggregate as (
	SELECT subject_id, hadm_id,
		CASE
		WHEN hadm_id in (SELECT DISTINCT hadm_id
				FROM infection_group
				WHERE infection = 1) THEN 1
			ELSE 0 END AS infection,
		CASE
		WHEN hadm_id in (SELECT DISTINCT hadm_id
				FROM organ_diag_group
				WHERE explicit_sepsis = 1) THEN 1
			ELSE 0 END AS explicit_sepsis,
		CASE
		WHEN hadm_id in (SELECT DISTINCT hadm_id
				FROM organ_diag_group
				WHERE organ_dysfunction = 1) THEN 1
			ELSE 0 END AS organ_dysfunction,
		CASE
		WHEN hadm_id in (SELECT DISTINCT hadm_id
				FROM organ_proc_group
				WHERE mech_vent = 1) THEN 1
			ELSE 0 END AS mech_vent
	FROM MIMICIII.ADMISSIONS)
-- List angus score for each admission
SELECT subject_id, hadm_id, infection,
	   explicit_sepsis, organ_dysfunction, mech_vent,
	CASE
	WHEN explicit_sepsis = 1 THEN 1
	WHEN infection = 1 AND organ_dysfunction = 1 THEN 1
	WHEN infection = 1 AND mech_vent = 1 THEN 1
	ELSE 0 END AS Angus
FROM aggregate;






/* All urine events from outputevents. Adapted from https://github.com/MIT-LCP/mimic-code/blob/master/etc/firstday/urine-output-first-day.sql */

drop materialized view if exists urineevents;
create materialized view urineevents as(
select hadm_id, icustay_id, charttime, value, valueuom
from outputevents
where itemid in
(
-- these are the most frequently occurring urine output observations in CareVue
40055, -- "Urine Out Foley"
43175, -- "Urine ."
40069, -- "Urine Out Void"
40094, -- "Urine Out Condom Cath"
40715, -- "Urine Out Suprapubic"
40473, -- "Urine Out IleoConduit"
40085, -- "Urine Out Incontinent"
40057, -- "Urine Out Rt Nephrostomy"
40056, -- "Urine Out Lt Nephrostomy"
40405, -- "Urine Out Other"
40428, -- "Urine Out Straight Cath"
40086,--	Urine Out Incontinent
40096, -- "Urine Out Ureteral Stent #1"
40651, -- "Urine Out Ureteral Stent #2"

-- these are the most frequently occurring urine output observations in CareVue
226559, -- "Foley"
226560, -- "Void"
227510, -- "TF Residual"
226561, -- "Condom Cath"
226584, -- "Ileoconduit"
226563, -- "Suprapubic"
226564, -- "R Nephrostomy"
226565, -- "L Nephrostomy"
226567, --	Straight Cath
226557, -- "R Ureteral Stent"
226558  -- "L Ureteral Stent"
)
order by hadm_id, icustay_id
); -- 3420280     3.5M

-- mimic=# select count(*) from urineevents where lower(valueuom) like '%ml%'; -- 3412546
-- select count(*) from urineevents where valueuom is null; -- 7734. Sum of the 2 match. 
-- select max(*) from urineevents; -- 4555555. Need to get rid of outliers. 
