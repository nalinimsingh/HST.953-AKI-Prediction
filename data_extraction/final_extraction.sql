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
drop materialized view if exists cohort1 cascade;
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



-- Keep only relevant cohort's creatinine
-- Also try to fill in missing hadm using admissions fuzzy time windows.
-- Discard missing hadm values that lie outside fuzzy windows. 
drop materialized view if exists creatinine1 cascade;
create materialized view creatinine1 as(
with tmp as( -- cohort subset measurements only, via subject and hadm id. 
     select *
     from creatinine
     where subject_id in(
     	   select distinct(subject_id)
     	   from cohort1)
     and hadm_id in(
     	 select distinct(hadm_id)
	 from cohort1) 
), tmp0 as( -- Isolate rows with hadm
   select *
   from tmp
   where hadm_id is not null
), tmp1 as( -- Isolate rows without hadm to do fewer calculations.  
   select subject_id, charttime, valuenum
   from tmp
   where hadm_id is null
), tmp2 as( -- try to get hadm_id for missing rows 
   select t.subject_id, a.hadm_id as hadm_id, t.charttime, t.valuenum
   from tmp1 t
   inner join cohortadmissions1 a
   on t.charttime between a.admittime and a.dischtime
   and t.subject_id = a.subject_id -- (with +/-12h)
)
select * from tmp0 -- original with hadm
union
select * from tmp2 -- extra hadm filled. 
order by subject_id, hadm_id, charttime
); -- 184000 using union. Use union rather than union all because the duplicate rows indicate that the same info was probably input twice. 

-- Note that there are actually a bunch of creatinine measurements which lie out of any hadm_ids by several days. We will toss out creatinine measurements that lie too far out of the hadm window.  


/*
select count(distinct(subject_id)) from cohort1; -- 6463
select count(distinct(subject_id)) from tmp; -- 
select count(distinct(subject_id)) from tmp0; --
select count(distinct(subject_id)) from tmp1; --
select count(distinct(subject_id)) from tmp2; -- 
select count(distinct(subject_id)) from creatinine1; -- 6443

select count(distinct(hadm_id)) from cohort1; -- 7135
select count(distinct(hadm_id)) from tmp; -- 7103.  
select count(distinct(hadm_id)) from tmp0;
select count(distinct(hadm_id)) from tmp1;
select count(distinct(hadm_id)) from tmp2;
select count(distinct(hadm_id)) from creatinine1; -- 7103
*/


-- Get creatinine measurements closest to each icustay entry time. 'admission creatinines'
-- Careful not to use fuzzy admit times, but real ones. 
drop materialized view if exists admission_creatinine; 
create materialized view admission_creatinine as(
with tmp as(
select c.*, extract(epoch from (c.charttime-a.admittime))/36 as min_from_admission
       --,row_number() over(partition by c.hadm_id order by c.charttime) as r
from creatinine1 c
inner join admissions a
on c.hadm_id=a.hadm_id
order by subject_id, hadm_id, charttime
), tmp0 as(
select *
from tmp
where min_from_admission<120 -- Get all measurements before admission and a bit after. 
) -- select count(hadm_id) from tmp0; -- 6512.  
select hadm_id, avg(valuenum) as meanvalue, max(valuenum) as maxvalue 
from tmp0
group by hadm_id
);  -- 5624 hadm_ids.


-- Create final cohort. Remove patients who have 'admission creatinines' >=1.2. 
-- Note, there are a lot of patients without 'admission creatinine' values. They will still be included. 
drop materialized view if exists cohort_final cascade;
create materialized view cohort_final as(
select *
from cohort1
where hadm_id not in(
select hadm_id
from admission_creatinine
where maxvalue>1.2)
); -- 5471 icustay. 5065 hadm, 4665 subject


-- Keep only relevant cohort's creatinine
drop materialized view if exists creatinine_final cascade;
create materialized view creatinine_final as(
select *
from creatinine1
where hadm_id in(
select hadm_id
from cohort_final)
); -- 129911

-- Keep only relevant cohort's map and fill in missing icustay
drop materialized view if exists map_final cascade;
create materialized view map_final as(
with tmp as(
select *
from map
where icustay_id in(
select icustay_id
from cohort_final)
) -- 1823033. Removed about 2/3




);




-- Keep only relevant cohort's urine and fill in missing hadm+icustay
drop materialized view if exists urine_final cascade;
create materialized view urine_final as(
select *
from urine
where hadm_id in(
select hadm_id
from cohort_final)
); -- 1021665. Removed about 2/3. 

-- Keep only relevant cohort's lactate and fill in missing hadm+icustay
drop materialized view if exists lactate_final cascade;
create materialized view lactate_final as(
select *
from lactate
where icustay_id in(
select icustay_id
from cohort_final)
);







-- Joining and Processing Views

SELECT d.*, v.vaso_frac, l.max_val, m.itemid, m.valuenum
FROM demographics d
LEFT JOIN vasopressordurations v
  ON cohort.icustay_id = v.icustay_id
LEFT JOIN lactate l
  ON cohort.icustay_id = l.icustay_id
LEFT JOIN map m
  ON cohort.icustay_id = m.icustay_id

