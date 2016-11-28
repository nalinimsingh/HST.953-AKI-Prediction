-- Create a table with MAP measurements for each patient

DROP MATERIALIZED VIEW IF EXISTS map cascade;
CREATE MATERIALIZED VIEW map AS

SELECT DISTINCT subject_id, icustay_id, charttime, itemid, valuenum
FROM chartevents
WHERE valuenum IS NOT NULL AND itemid IN (220181, 220052, 225312, 224322, 6702, 443, 52, 456)
  AND 30 < valuenum AND valuenum < 200
ORDER BY valuenum, icustay_id, charttime, itemid

