Description of the dataset is below. Code will need some tweaking, as dataset includes data around the time of sepsis, and NOT during the first 72h.

Out of all 61,532 ICU admissions in MIMIC, the initial cohort of adult patients fulfilling the sepsis-3 criteria was 20,834 admissions. Sepsis is defined as suspected infection (sample for culture + administration of antibiotics, also respecting the temporal criteria from the original paper) as well as SOFA >=2 at least once in the period 48h before until 24h after the time of suspected infection. In the dataset provided, I have included the data from 24h before until 48h after the onset of sepsis (up to 72h per patient). I have excluded the patients who did not receive any fluid at all during their ICU stay, those who were already on vasopressors at the time of admission (during the first or second hour) and those who died within the first 72h after admission. This leaves me with 17,676 patients. I have not excluded the patients who did not receive any vasopressor.
 
Then, I have identified:
 

    the patients who developed hypotension (MAP < 65 for at least 2 consecutive time steps)
    and those who were subsequently started on vasopressors (within 6h of onset of hypotension).

 
Here are some results: I have found:
 

    33671 hypotensive episodes occurring in 11322 different patients.
    3317 initiations of vasopressor (about 10% of the hypotensive episodes). These 3317 events occur in 2766 different patients.

 
So it means that we could include 2766 hypotensive episodes in the model, if we decide to keep only the first hypotensive episode for each patient.
 
Please have a look at the data (link to csv file below – 305 MB). I have left the headers and most variables are self-explanatory but please let me know if you have any question about what they mean or how the data was generated. I have included most of the variables that we discussed, plus a few extra (Elixhauser etc). I use sample-and-hold (carry forward last observation) and interpolation for missing values. Charttime is in posix time and age is in days. The values of fluid administered, urine output and fluid balance are “since admission”, not “since beginning of hypotensive episode”. Pre-admission fluid is documented in MIMIC for 11970/61532 admissions, and pre-admission urine output for 8800/61532 admissions. When not documented, I assumed it was zero…
 
The flags for hypotension and vasopressors are in the last 2 columns. Here is what they mean:
 

    For hypotension: the numbers (1, 2, 3…) correspond to the duration of hypotension since it started. 99 means ‘end of hypotensive episode’
    For vasopressors: 1 is initiation of vasopressors, 2 is continuation of infusion, 3 is end of infusion.

 
The patient starting row 486 is a good example of what the flags look like.

Clean dataset:​

 TMLE_091116.csv
​
 
Code for building sepsis cohort:
​

 work091116_cohort.m
​
Code for building clean dataset:​

 work091116_dataset.m
​
Most of the raw data is in here:
​
 data raw before preproc 081116.mat
​
 

Enjoy.

Matthieu
