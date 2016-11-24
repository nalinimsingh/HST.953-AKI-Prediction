

/* All urine events from outputevents. Adapted from https://github.com/MIT-LCP/mimic-code/blob/master/etc/firstday/urine-output-first-day.sql */

drop materialized view if exists urine;
create materialized view urine as(
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

-- mimic=# select count(*) from urine where lower(valueuom) like '%ml%'; -- 3412546
-- select count(*) from urine where valueuom is null; -- 7734. Sum of the 2 match. 
-- select max(*) from urine; -- 4555555. Need to get rid of outliers. 
