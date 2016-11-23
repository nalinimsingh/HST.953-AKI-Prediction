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








