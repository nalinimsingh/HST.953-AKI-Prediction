-- Extract all serum creatinine labs
-- Reference: https://github.com/MIT-LCP/mimic-code/blob/3f004bc0d7f3e7c858228f7a06c37736e954580f/etc/firstday/labs-first-day.sql


-- select * from d_labitems where label~*'creatinine';  Only itemid=50912 is from blood


drop materialized view if exists creatinine;
-- Not all creatinine measurements come with a hadm_id. Need to get from admissions. 
create materialized view creatinine as(
with tmp as(
select subject_id, charttime, valuenum
from labevents
where itemid=50912)
select t.*, a.hadm_id
from tmp t
inner join admissions a
on t.charttime between a.admittime and a.dischtime
order by subject_id, charttime); -- 797389








-- Sanity check for matching hadms 
drop materialized view if exists creatinine;

create materialized view creatinine as(
with tmp as(
select subject_id, hadm_id as lhadm, charttime, valuenum
from labevents
where itemid=50912)
select t.*, a.hadm_id as ahadm
from tmp t
inner join admissions a
on t.charttime between a.admittime and a.dischtime
order by subject_id, charttime); -- 797389



-- Checking that all units are mg/dl
/*  
create materialized view creatinine as(
select subject_id, hadm_id, charttime, valuenum, valueuom
from labevents
where itemid=50912
order by subject_id, charttime); -- 797389

-- select count(*) from creatinine where valueuom~*'mg/dl';  797369
-- select count(*) from creatinine where valueuom is null; 20. Adds up. 0.4 <= These values <= 1.9

*/ 
