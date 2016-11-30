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
	end as outtime,
	intime as intimereal -- use this to calculate times from icu admission later
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



-- Get creatinine measurements closest to each icustay entry time. 'admission creatinines'
-- Careful not to use fuzzy admit times, but real ones. 
drop materialized view if exists admission_creatinine cascade; 
create materialized view admission_creatinine as(
with tmp as(
select c.*, extract(epoch from (c.charttime-a.admittime))/60 as min_from_admission
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
);  -- 5890 hadm_ids.




----------------------  Create final cohort.  ----------------------------------------------
--  Remove patients who have 'admission creatinines' >=1.2. 
-- Note, there are a lot of patients without 'admission creatinine' values. They will still be included. 
drop materialized view if exists cohort_final cascade;
create materialized view cohort_final as(
select *
from cohort1
where hadm_id not in(
select hadm_id
from admission_creatinine
where maxvalue>1.2)
); -- 5342 icustay.


-- Update the subset of admission and icustay fuzzy windows

drop materialized view if exists cohortadmissions_final cascade;
create materialized view cohortadmissions_final as(
select *
from cohortadmissions1
where hadm_id in (
      select hadm_id
      from cohort_final)
); -- 4946


drop materialized view if exists cohorticustays_final cascade;
create materialized view cohorticustays_final as(
select *
from cohorticustays1
where icustay_id in (
      select icustay_id
      from cohort_final)
); -- 5342
------------------------------------------------------------------------------------------



-- Keep only relevant cohort's creatinine. All rows have hadm_id. 
drop materialized view if exists creatinine_final cascade;
create materialized view creatinine_final as(
with tmp as(
select *
from creatinine1
where hadm_id in(
select hadm_id
from cohort_final)
) -- 129911
select t.*, i.icustay_id,
       extract(epoch from(t.charttime-i.intimereal))/60 as min_from_intime 
from tmp t
-- left join cohorticustays_final i -- can use this instead to keep the creatinine measurements.
inner join cohorticustays_final i
on t.subject_id = i.subject_id
and t.charttime between i.intime and i.outtime
order by t.subject_id, i.icustay_id, min_from_intime 
); -- 92433 using inner join. Lost over 30000 by excluding rows which could not be matched to an icustay fuzzy window.  


-- Keep only relevant cohort's map and fill in icustay
drop materialized view if exists map_final cascade;
create materialized view map_final as(
with tmp as(
select *
from map
where icustay_id in(
select icustay_id
from cohort_final)
), --  Removed about 2/3
tmp0 as( -- Isolate rows with icustay
   select *
   from tmp
   where icustay_id is not null
), tmp1 as( -- Isolate rows without icustay  
   select subject_id, charttime, itemid, valuenum
   from tmp
   where icustay_id is null
), tmp2 as( -- try to get icustay for missing rows 
   select t.subject_id, i.icustay_id as icustay_id, t.charttime, t.itemid, t.valuenum
   from tmp1 t
   inner join cohorticustays_final i
   on t.charttime between i.intime and i.outtime
   and t.subject_id = i.subject_id -- (with +/-12h)
), tmp3 as(
select * from tmp0 -- original with icustay
union
select * from tmp2 -- extra icustay filled. 
order by subject_id, icustay_id, charttime
)
select t.*, extract(epoch from(t.charttime-i.intimereal))/60 as min_from_intime
from tmp3 t
inner join cohorticustays_final i
on t.icustay_id = i.icustay_id
); -- 1778419. No maps were excluded due to missing icustay id!!!  


-- Keep only relevant cohort's urine and fill in missing icustay
drop materialized view if exists urine_final cascade;
create materialized view urine_final as(
with tmp as(
select *
from urine
where icustay_id in(
select icustay_id
from cohort_final)
), -- 1009884. Removed about 2/3
tmp0 as( -- Isolate rows with icustay
   select *
   from tmp
   where icustay_id is not null
), tmp1 as( -- Isolate rows without icustay  
   select subject_id, hadm_id, charttime,  value
   from tmp
   where icustay_id is null
), tmp2 as( -- try to get icustay for missing rows 
   select t.subject_id, hadm_id, i.icustay_id as icustay_id, t.charttime, t.value
   from tmp1 t
   inner join cohorticustays_final i
   on t.charttime between i.intime and i.outtime
   and t.subject_id = i.subject_id -- (with +/-12h)
), tmp3 as(
select * from tmp0 -- original with icustay
union
select * from tmp2 -- extra icustay filled. 
order by subject_id, icustay_id, charttime
)
select t.*, extract(epoch from(t.charttime-i.intimereal))/60 as min_from_intime
from tmp3 t
inner join cohorticustays_final i
on t.icustay_id = i.icustay_id
); -- 986936. Excluded about 1000 measurements due to missing icustayid. 


-- Keep only relevant cohort's lactate
drop materialized view if exists lactate_final cascade;
create materialized view lactate_final as(
select *
from lactate
where icustay_id in(
select icustay_id
from cohort_final)
); -- 4581

-- Keep only relevant cohort's vasopressor durations 
drop materialized view if exists vaso_final cascade;
create materialized view vaso_final as(
select *
from vasopressordurations
where icustay_id in(
select icustay_id
from cohort_final)
); -- 5471 

-- Every map, creatinine and urine from this point has an icustay_id.  





-------------------- Exporting Tables --------------------------
-- Creatinine
COPY(
  SELECT icustay_id, min_from_intime, valuenum as value
  FROM creatinine_final
  ORDER BY icustay_id, min_from_intime
)
TO '/home/chen/Projects/HST953-MLinCriticalCare/HST.953/data_extraction/tables/creatinine.csv' DELIMITER ',' CSV HEADER;

-- Map
COPY(
  SELECT icustay_id, min_from_intime, itemid, valuenum as value
  FROM map_final
  ORDER BY icustay_id, min_from_intime
)
TO '/home/chen/Projects/HST953-MLinCriticalCare/HST.953/data_extraction/tables/map.csv' DELIMITER ',' CSV HEADER;

-- Urine
COPY(
  SELECT icustay_id, min_from_intime, value
  FROM urine_final
  ORDER BY icustay_id, min_from_intime
)
TO '/home/chen/Projects/HST953-MLinCriticalCare/HST.953/data_extraction/tables/urine.csv' DELIMITER ',' CSV HEADER;


-- Demographics, lactate, vasopressor durations. There are commas in notes so use tab separated 
COPY(
  SELECT c.*, l.max_val as max_lactate, v.vaso_duration, v.vaso_frac 
  FROM cohort_final c
  LEFT join lactate_final l
  ON c.icustay_id = l.icustay_id
  LEFT join vaso_final v
  ON c.icustay_id = v.icustay_id
  ORDER BY subject_id, hadm_id, icustay_id
)
TO '/home/chen/Projects/HST953-MLinCriticalCare/HST.953/data_extraction/tables/cohort.tsv' DELIMITER E'\t' HEADER CSV;


-----------------------------------------------------------------
