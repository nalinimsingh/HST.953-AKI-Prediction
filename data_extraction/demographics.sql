/* Demographics of patients over 18 with icustay lengths over 3 days */

DROP MATERIALIZED view if exists demographics cascade;
CREATE materialized view demographics as(
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
SELECT t.*,
       case when t.age >= 18 and t.age < 35 then 1
       when t.age >= 35 and t.age < 50 then 2
       when t.age >= 50 and t.age < 65 then 3
       when t.age >= 65 and t.age < 80 then 4
       when t.age >= 80 then 5
       end as agebin,
       i.icustay_id, i.dbsource, i.intime, i.outtime, i.los
FROM tmp t
INNER JOIN icustays i
ON t.hadm_id = i.hadm_id
   WHERE age>=18
   AND los>=3
ORDER BY subject_id, admittime, intime
); /* 19534 icustays. Does not include readmissions in same hadm_id combining to make longer icustay.*/



-- select count(icustay_id) from demographics;  -- 19534
-- select count(distinct(icustay_id)) from demographics ;  --19534






