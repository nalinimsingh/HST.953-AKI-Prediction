/* The top level script that generates and uses the individual views to extract the final cohort and features */

set search_path to mimiciii;


-- Generating Views from individual scripts
\ir ckd.sql -- 5417 subject ids 
\ir creatinine.sql -- 797389 measurements with subject_id and hadm_id. Missing some hadm_ids. 
\ir demographics.sql -- 19534 icustays with subject_id, hadm_id, and icustay_id. Patients over 18 with icustay>=3 days. 
\ir lactate.sql -- 34272 measurements with subject_id, hadm_id, and icustay_id. 
\ir map.sql -- 6178780 measurements with icustay_id. 
\ir sepsis.sql -- 58976 subject_ids with hadm_id. 
\ir urine.sql -- 3394431 measurements with hadm_id, and icustay_id. Missing some hadm_id and icustay_id. 
\ir vaso.sql -- 61532 subject_ids with icustay_id. 




-- Start with icustays>3 days for age 18+ patients

-- Keep only septic patients. 
drop materialized view if exists cohort0 cascade;
create materialized view cohort0 as(
select d.*
from demographics d
inner join angus_sepsis s
on d.hadm_id=s.hadm_id
where s.angus=1); -- 10097

-- Remove patients with CKD according to icd9
drop materialized view if exists cohort1;
create materialized view cohort1 as(
select *
from cohort0
where subject_id not in(
select subject_id
from ckd)
); -- 7681 rows/icustays. 7135 distinct hadm, 6463 distinct subject 


----------- Tables used to save computation time -----------------
-- Compute windows hospital or icu stay limits based on either +/- N hours or the midpoint of the current and the neighboring window if the time difference is less than 2*N hours.  

-- Table of fuzzy admission times used to fill in missing values
drop materialized view if exists cohortadmissions1 cascade;
create materialized view cohortadmissions1 as(
with tmp as(
     select subject_id, hadm_id, admittime, dischtime,
     lag (dischtime) over (partition by subject_id order by admittime) as dischtime_lag,
     lead (admittime) over (partition by subject_id order by admittime) as admittime_lead
     from admissions
     where hadm_id in (
     	   select distinct(hadm_id) from cohort1
     )
)
select subject_id, hadm_id,
       case
	when dischtime_lag is not null
       	and dischtime_lag > (admittime - interval '24' hour)
      	then admittime - ( (admittime - dischtime_lag) / 2 )
	else admittime - interval '12' hour
	end as admittime,
	case
	when admittime_lead is not null
	and admittime_lead < (dischtime + interval '24' hour)
	then dischtime + ( (admittime_lead - dischtime) / 2 )
	else (dischtime + interval '12' hour)
	end as dischtime
from tmp
); -- 7135

-- Table of fuzzy icustay times used to fill in missing values
drop materialized view if exists cohorticustays1 cascade;
create materialized view cohorticustays1 as(
with tmp as(
     select subject_id, icustay_id, intime, outtime,
     lag (outtime) over (partition by subject_id order by intime) as outtime_lag,
     lead (intime) over (partition by subject_id order by intime) as intime_lead
     from icustays
     where icustay_id in (
     	   select distinct(icustay_id) from cohort1
     )
)
select subject_id, icustay_id,
       case
	when outtime_lag is not null
       	and outtime_lag > (intime - interval '24' hour)
      	then intime - ( (intime - outtime_lag) / 2 )
	else intime - interval '12' hour
	end as intime,
	case
	when intime_lead is not null
	and intime_lead < (outtime + interval '24' hour)
	then outtime + ( (intime_lead - outtime) / 2 )
	else (outtime + interval '12' hour)
	end as outtime
from tmp
); -- 7681
------------------------------------------------------------------



-- Keep only relevant cohort's creatinine and fill in missing hadm
drop materialized view if exists creatinineC;
create materialized view creatinineC as(
with tmp as( -- cohort subset measurements
     select *
     from creatinine
     where subject_id in(
     select subject_id
     from cohort1)
), tmp0 as( -- Isolate rows with hadm
   select *
   from tmp
   where subject_id is not null
), tmp1 as( -- Isolate rows without hadm to do fewer calculations.  
   select subject_id, charttime, valuenum
   from tmp
   where subject_id is null
), tmp2 as( -- get hadm_id for missing rows 
   select t.subject_id, a.hadm_id as hadm_id, t.charttime, t.valuenum
   from tmp1 t
   inner join cohortadmissions1 a
   on t.charttime between a.admittime and a.dischtime
)
select * from tmp0
union
select * from tmp2
order by subject_id, hadm_id, charttime
); -- 246075 
-- There are actually a bunch of creatinine measurements which lie out of any hadm_ids by several days. 




-- Sanity check for above ^^
select count(*) from(
select * from creatinine cr
inner join cohortadmissions1 c1
on cr.subject_id = c1.subject_id
) as tmp;
-- 362550 using cohortadmissions1. Why is this not matching above???




-- Get creatinine measurements closest to each icustay entry time 





-- Remove patients who have 'admission creatinines' above 1.2. Final cohort. 







-- Keep only relevant cohort's urine and fill in missing hadm+icustay


-- Keep only relevant cohort's map and fill in missing icustay


-- Keep only relevant cohort's lactate and fill in missing hadm+icustay








-- Joining and Processing Views

SELECT d.*, v.vaso_frac, l.max_val, m.itemid, m.valuenum
FROM demographics d
LEFT JOIN vasopressordurations v
  ON cohort.icustay_id = v.icustay_id
LEFT JOIN lactate l
  ON cohort.icustay_id = l.icustay_id
LEFT JOIN map m
  ON cohort.icustay_id = m.icustay_id




--drop materialized view cohort0;
--drop materialized view cohort1;


