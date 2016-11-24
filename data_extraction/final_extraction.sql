/* The top level script that generates and uses the individual tables to extract the final cohort and features */

set search_path to mimiciii;



\ir ckd.sql
\ir creatinine.sql
\ir demographics.sql
\ir lactate.sql
\ir map.sql
-- \ir sepsis.sql
\ir urine.sql
\ir vaso.sql




/*
SELECT cohort.*,v.vaso_frac,l.max_val,m.itemid,m.valuenum
FROM age18survive3 cohort
LEFT JOIN vasopressordurations v
  ON cohort.icustay_id = v.icustay_id
LEFT JOIN lactate l
  ON cohort.icustay_id = l.icustay_id
LEFT JOIN map m
  ON cohort.icustay_id = m.icustay_id
*/
