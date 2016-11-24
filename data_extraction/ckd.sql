-- Chronic kidney disease

drop materialized view if exists ckd;
create materialized view ckd as(
select distinct subject_id, icd9_code
from diagnoses_icd
where lower(icd9_code) like '585%'); -- 5417
