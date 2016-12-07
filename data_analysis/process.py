import pandas as pd
pd.options.mode.chained_assignment = None
import numpy as np
import statsmodels.api as sm

def interpolateweights(cohort):
    
    weightcovariates = cohort[['age','gender','height', 'weight']]
    weightcovariates['agesquared'] = weightcovariates['age']**2
    #weightcovariates = weightcovariates.dropna(subset=['weight'])
    weightcovariates['gender'] = pd.Categorical(weightcovariates['gender'])
    weightcovariates['gender'] = weightcovariates.gender.cat.codes

    # Split into training (no weight) and testing. 
    wc_train = weightcovariates.loc[weightcovariates['weight'].notnull()]
    wc_test = weightcovariates.loc[weightcovariates['weight'].isnull()]

    # Split training data into subsets with and without height. Train 2 models. 
    c_with_height = wc_train.loc[wc_train['height'].notnull()][['age','agesquared', 'gender','height']]
    c_without_height = wc_train.loc[wc_train['height'].isnull()][['age', 'agesquared', 'gender']]

    w_with_height = wc_train.loc[wc_train['height'].notnull()]['weight']
    w_without_height= wc_train.loc[wc_train['height'].isnull()]['weight']

    # Split testing data into subsets with and without height. 
    c_with_height_test = wc_test.loc[wc_test['height'].notnull()][['age','agesquared','gender','height']]
    c_without_height_test = wc_test.loc[wc_test['height'].isnull()][['age','agesquared','gender']]

    # Train the model using the training sets
    model_with_height = sm.OLS(w_with_height, c_with_height)
    model_without_height = sm.OLS(w_without_height, c_without_height)
    results_with_height = model_with_height.fit()
    results_without_height = model_without_height.fit()

    # Predict the missing weights 
    w_with_height_predict = results_with_height.predict(c_with_height_test) # 56 to 93kg
    w_without_height_predict = results_without_height.predict(c_without_height_test) # 42 to 88kg. Seems reasonable. 
    
    # Fill in the missing weights
    for i in range(0, len(w_with_height_predict)):
        icu = c_with_height_test.iloc[[i]].index[0]
        cohort.ix[cohort.index == icu, 'weight'] = w_with_height_predict[i]
        #print(cohort.ix[cohort.index == icu, ['height', 'weight']])
    for i in range(0, len(w_without_height_predict)):
        icu = c_without_height_test.iloc[[i]].index[0]
        cohort.ix[cohort.index == icu, 'weight'] = w_without_height_predict[i]    
        
    return cohort


def calculateurineaki(urine, cohort):
    
    icustays = np.unique(urine['icustay_id'])

    # For each icustay key, the array of urine output volumes in 4h windows
    urine_4h = {}
    # Binary outcome of aki or not for each icustay, and starting time of 4h window aki was identified in  
    aki_urine = np.zeros([len(icustays), 3], dtype='int') 


    for icuind in range(0, len(icustays)):
        icustay = icustays[icuind]
        aki_urine[icuind,0]=icustay

        # Get all the urine values and times for the icustay_id 
        u= np.array(urine.loc[urine['icustay_id'] == icustay]['value']) 
        t = np.array(urine.loc[urine['icustay_id'] == icustay]['min_from_intime'])

        # Keep the time of first urine measurement, and get relative times. 
        t0=t[0]
        t=t-t0

        # Calculate urine output in 4 hour blocks starting from the time of first urine measurement. 
        # Hence the first urine measurement will not be used.

        # Urine volumes for four hour blocks, starting from the first measurement extending to or before the last urine measurement. 
        # Urine output for the block before the first measurement is not calculated.
        nblocks = int(np.ceil(t[-1]/ 240))
        urine_blocks = np.zeros(nblocks)

        # For every urine measurement, add the proportionate volume to the appropriate 4h windows. 
        for ind in range(1, len(u)):

            
            
            # Which 4h block index the measurement falls in 
            blocknum = int(t[ind]/ 240 )
            if blocknum == nblocks:
                blocknum = blocknum-1
            
            # Getting some cases of this. 
            if t[ind] == t[ind-1]:
                if u[ind] != u[ind-1]:
                    urine_blocks[blocknum] += u[ind]
                continue
            
            # Left time limit of the rectangle to calculate urine volume proportion that fits into block. 
            leftlimit_t = max(t[ind-1], int(t[ind]/240)*240)
            # The proportion of urine volume that belongs to the current 4h block
            propcurrent = (t[ind]-leftlimit_t)/(t[ind]-t[ind-1])
            urine_blocks[blocknum] += u[ind]*propcurrent

            # Add the proportion of urine volume to previous 4h blocks
            while (leftlimit_t!=t[ind-1]):
                blocknum= blocknum - 1
                leftlimit_t = max(t[ind-1], blocknum*240)
                propcurrent = ((blocknum+1)*240-leftlimit_t)/(t[ind]-t[ind-1])
                urine_blocks[blocknum] += u[ind]*propcurrent

        # Get the patient weight to calculate RIFLE criteria. 
        patientweight = cohort.loc[cohort.index == icustay]['weight'].values                       

        # Whether the urine block meets the I criteria
        urine_blocks_I = urine_blocks < (2 * patientweight)      

        # Find 3 consecutive 4h blocks that satisfy the I kidney injury criteria   
        aki_urine[icuind, 1]=0
        b=0
        while (b<nblocks-2) & (aki_urine[icuind, 1] == 0):
            if np.array_equal(urine_blocks_I[b:(b+3)], [True, True, True]):
                aki_urine[icuind, 1]=1
                # The starting time of the aki onset window
                aki_urine[icuind, 2] = int(b*240+t0)
            b+=1

        #  ----------  Optional: Save the 4h urine volumes. Very slow ------------- #   
        #urine_4h[icustay]=urine_blocks


    # Convert to pandas dataframe
    #aki_urine_frame = pd.DataFrame(aki_urine[:,1:], index=aki_urine[:,0], columns=['aki_result', 'aki_onset_t'])
    aki_urine_frame = pd.DataFrame(aki_urine, columns=['icustay_id', 'aki_urine', 'aki_onset_t'])
    aki_urine_frame['aki_urine'] = aki_urine_frame['aki_urine'].astype(bool)
    aki_urine_frame.set_index('icustay_id', inplace=True)
    return aki_urine_frame


def geteth(cohort):
    eth = cohort['ethnicity'].astype('category')

    # grouping based on the standards at: http://grants.nih.gov/grants/guide/notice-files/NOT-OD-15-089.html
    eth = eth.cat.add_categories(['HISPANIC/LATINO','MULTI/OTHER','UNKNOWN'])

    eth[np.array([('HISPANIC' in i or
                   'PORTUGUESE' in i) for i in eth],dtype=bool)]='HISPANIC/LATINO'
    eth[np.array([('ASIAN' in i) for i in eth],dtype=bool)]='ASIAN'
    eth[np.array([('BLACK' in i or
                   'AFRICAN' in i) for i in eth],dtype=bool)]='BLACK/AFRICAN AMERICAN'
    eth[np.array([('WHITE' in i or
                   'MIDDLE EAST' in i) for i in eth],dtype=bool)]='WHITE'
    eth[np.array([('MULTI' in i or
                   'OTHER' in i) for i in eth],dtype=bool)]='MULTI/OTHER'
    eth[np.array([('DECLINE' in i or
                   'UNABLE' in i or
                   'UNKNOWN' in i) for i in eth],dtype=bool)]='UNKNOWN'

    eth = eth.cat.remove_unused_categories()
    
    return eth 


def getmapfeatures(maps,map_cutoffs):
    # convert raw MAP readings to MAP features
    interval = 60

    # average MAP for every hour
    maps.set_index('icustay_id')
    maps['hour'] = pd.Series((maps.min_from_intime/interval).astype(int), index=maps.index)

    # get means for every hour
    mean_maps = maps.groupby(['icustay_id', 'hour'])['value'].mean()
    mean_maps = mean_maps.to_frame().reset_index().set_index(['icustay_id'])

    # interpolate MAPs for missing values
    min_hours = mean_maps.groupby([mean_maps.index.get_level_values(0)])['hour'].min()
    max_hours = mean_maps.groupby([mean_maps.index.get_level_values(0)])['hour'].max()

    interp_index = []
    for this_icustay in min_hours.index:
        min_hour = min_hours.loc[this_icustay]
        max_hour = max_hours.loc[this_icustay]
        interp_index += [(this_icustay, hour) for hour in np.arange(min_hour,max_hour+1)]

    mean_maps = mean_maps.set_index(['hour'],append=True)
    interp_mean_maps = mean_maps.reindex(pd.MultiIndex.from_tuples(interp_index,names=['icustay_id','hour']))
    interp_mean_maps = interp_mean_maps['value'].interpolate(method='linear')
    interp_mean_maps = interp_mean_maps.to_frame().reset_index()

    # get percent of hours missing a MAP value
    missing_map = len(interp_mean_maps.index) - len(mean_maps.index)

    frac_missing = missing_map/float(len(interp_mean_maps.index))
    print "Fraction of hours missing MAP values:", frac_missing

    # bin MAP values for first 72 hours
    map_72 = interp_mean_maps.loc[(0<interp_mean_maps['hour']) & (interp_mean_maps['hour']<72)]

    # get minimum MAP value per patient
    min_ind = map_72.groupby('icustay_id')['value'].idxmin(skipna=True)
    min_maps = map_72.loc[min_ind]

    
    map_72['bin'] = pd.cut(map_72['value'], map_cutoffs)
    min_maps['bin'] = pd.cut(min_maps['value'], map_cutoffs)

    map_fracs = map_72.groupby('icustay_id')['bin'].value_counts(normalize=True)
    map_fracs.index.set_names(['icustay_id','bin'], inplace=True)
    map_fracs = map_fracs.unstack('bin')

    # reformat features to be used in final dataset
    min_maps = min_maps.set_index('icustay_id')
    
    return (mean_maps, min_maps, map_fracs)


def analyzecreatinine(creatinine, admission_creatinine):
    # use creatinine measurements to determine AKI onset
    creatinine = creatinine.dropna()

    # only consider creatinine measurements after admission
    creatinine = creatinine.loc[creatinine['min_from_intime']>0]

    # calculate time and first creatinine measurement from admission
    creatinine = creatinine.merge(admission_creatinine,suffixes=('','_ref'),on=['icustay_id'],how='left')

    # RIFLE Creatinine Criteria: Creatinine doubles
    creatinine['I'] = creatinine['value']>=2*creatinine['value_ref']
    creatinine['F'] = creatinine['value']>=3*creatinine['value_ref']

    # Group creatinine measurements by icustay_id
    icustay_creat = creatinine.groupby(['icustay_id'])

    # Find the first time the patient meets the RIFLE creatinine criteria 
    i_creat_ind = icustay_creat['I'].apply(lambda x: x[x].index[0] if len(x[x])>0 else None)
    f_creat_ind = icustay_creat['F'].apply(lambda x: x[x].index[0] if len(x[x])>0 else None)

    i_creat = creatinine[['icustay_id','min_from_intime','value']].ix[i_creat_ind.dropna().tolist()]
    i_creat = i_creat.set_index('icustay_id')
    i_creat.rename(columns={'value':'i_val','min_from_intime':'i_time'},inplace=True)

    f_creat = creatinine[['icustay_id','min_from_intime','value']].ix[f_creat_ind.dropna().tolist()]
    f_creat = f_creat.set_index('icustay_id')
    f_creat.rename(columns={'value':'f_val','min_from_intime':'f_time'},inplace=True)

    # also get max creatinine value within time window
    max_creat = creatinine.loc[icustay_creat['value'].idxmax(skipna=True)]

    # nicely summarize creatinine data
    d = {'icustay_id':max_creat['icustay_id'],
         'ref_value':max_creat['value_ref'],
         'ref_time':max_creat['min_from_intime_ref'],
         'max_value':max_creat['value'],
         'max_time':max_creat['min_from_intime']}
    creat_summary = pd.DataFrame(d)
    creat_summary = creat_summary.set_index('icustay_id')

    creat_summary = creat_summary.join(i_creat,how='left')
    creat_summary = creat_summary.join(f_creat,how='left')
    creat_summary['creat_aki']=pd.notnull(creat_summary['i_val'])
    
    return creat_summary


def getlrdata(cohort, eth, min_maps, map_fracs, creat_summary, aki_urine):
    lr_data = cohort[['icustay_id','age','los','max_lactate','vaso_frac','gender']]
    lr_data['eth'] = eth
    lr_data = lr_data.set_index('icustay_id')

    lr_data = lr_data.join(min_maps,how='inner')
    lr_data.rename(columns={'value':'min_map','bin':'min_map_bin'},inplace=True)

    lr_data = lr_data.join(map_fracs,how='inner')

    lr_data = lr_data.join(creat_summary['creat_aki'],how='left')

    lr_data = lr_data.join(aki_urine['aki_urine'].astype(bool), how='left')

    lr_data['aki'] = (lr_data['aki_urine'] | creat_summary['creat_aki'])

    aki_dataset = lr_data.loc[lr_data['aki']==True]
    non_aki_dataset = lr_data.loc[lr_data['aki']==False]
    
    return (lr_data, aki_dataset, non_aki_dataset)

# get summaries of each dataset
def get_summary(dataset):
    print dataset[['age','los','max_lactate','vaso_frac','min_map']].describe()
    print ""
    
    print "gender:"
    print pd.value_counts(dataset['gender'].values)
    print ""
    print pd.value_counts(dataset['gender'].values,normalize=True)
    print ""
    
    print "ethnicity:"
    print pd.value_counts(dataset['eth'].values)
    print ""
    print pd.value_counts(dataset['eth'].values,normalize=True)
    print ""

