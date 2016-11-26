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
); -- 7681


----------- Tables used to save computation time -----------------

-- Table of admission times used to fill in missing values
drop materialized view if exists cohortadmissions1;
create materialized view cohortadmissions1 as(
select c.subject_id, c.hadm_id, a.admittime, a.dischtime
from cohort1 c
inner join admissions a
on c.hadm_id = a.hadm_id
); -- 7681

-- Table of icustay times used to fill in missing values
drop materialized view if exists cohorticustays1;
create materialized view cohorticustays1 as(
select c.subject_id, c.icustay_id, i.intime, i.outtime
from cohort1 c
inner join icustays i
on c.icustay_id = i.icustay_id
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


-- Sanity check
select count(*) from(
select * from creatinine cr
inner join cohortadmissions1 c1
on cr.subject_id = c1.subject_id
) as tmp;
-- 362550 using cohort1 and cohortadmissions1





-- Get creatinine measurements closest to each icustay entry time 











-- Filling in missing hadm/icustay for urine


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






-- Testing

create materialized view test1 as(
select subject_id, hadm_id
from admissions
where subject_id<30
order by subject_id
);


create materialized view test2 as(
select subject_id, hadm_id
from admissions
where subject_id<60
and subject_id>30
order by subject_id
);

drop materialized view if exists test1;
drop materialized view if exists test2;

select *
from test1
union
select *
from test2
order by subject_id;
