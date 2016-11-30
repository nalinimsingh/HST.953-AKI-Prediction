# Data Analysis

## Covariate Feature Details

- Obtain averaged hourly values of MAP in first 72h. <30 and >200 are errors. Bin the blood pressures. Final vector feature is % time MAP was in each pressure bin. Can also have another feature: lowest bin achieved in 72h. 
- Age group:
	- 18-34
	- 35-49
	- 50-64
	- 65-79
	- 80+
- Ethnicity as classification
- Vasopressors - % time patient was on pressors in first 72h
- Highest lactate in first 72h
- For use in secondary analysis: amount of time patient was hypotensive (based on different MAP thresholds)  

## Outcome Feature Details

AKI via Rifle Criteria (binary)
- Requires creatinine and urine output
- Designate patient as having AKI if they satisfy 'injury' or 'failure' criteria
- Also analyze time to AKI

## Notes and Explanation
