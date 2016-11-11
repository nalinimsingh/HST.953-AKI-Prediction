# Data Extraction

## Cohort Inclusion Criteria

1. Above age 18.
2. Developed sepsis as defined by the Angus criteria during their stay in the ICU.
3. Were not admitted to the ICU with end-stage renal disease. RIFLE criteria. 
4. Survive an ICU stay lasting at least 3 days.

## Features/Covariates to Extract

- Age
- Ethnicity
- Diagnosis on ICU Admission
- Vasopressor use during first 72 hours of ICU stay
- MAP during first 72 hours of ICU stay
- CRRT during ICU stay
- Hemodialysis during ICU stay
- Urine output
- Lactate
- Blood urea nitrogen
- Creatinine


## Extraction Details/Considerations

- Alistair mentioned to me that ESRD billing codes have changed in the past 10 years, so we may need to query for both chronic renal failure and ESRD
- Alistair is currently in the process of writing a script to extract information about CRRT that we can reuse
- I was digging around the LCP Github and think we can modify https://github.com/MIT-LCP/mimic-code/blob/9186badca6590872fa1f86647b368ac48e73db18/etc/rrt.sql to extract dialysis information. Let me know if this is not correct.
- For MAP, urine output, lactate, and BUN, I think we still need to define which specific measurements we are using more carefully, but for now we can perhaps pull all measurements.


