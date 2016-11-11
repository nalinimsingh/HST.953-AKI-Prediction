% COHORT OF PATIENTS WITH SEPSIS - MIMIC-III (v1.3)
% Code by: Matthieu Komorowski mkomo@mit.edu

% this creates a list of icustayIDs of patients who develop sepsis at some point 
% in the ICU. records charttime for onset of sepsis.
% uses sepsis3 criteria

% STEPS:
%-------------------------------
% FLAG PRESUMED INFECTION
% PREPROCESSING
% REFORMAT in 4h time slots
% COMPUTE SOFA at each time step
% FLAG SEPSIS


% used 09 Nov 2016
%% add elix to demog
demog.Elixhauser=(NaN(size(demog,1),1));

tic
for i=1:size(elix,1)
 icustayid=elix(i,1);
 ii=find(demog.icustay_id==icustayid);   %row in table demographics
 demog.Elixhauser(ii)=elix(i,33);
    
    
end
toc


%% ########################################################################
%            some data manip for sepsis cohort definition
% ########################################################################

% ########################################################################
% import culture and microbio
% merges charttime / suppr NaNs

ii=isnan(microbio(:,3));
microbio(ii,3)=microbio(ii,4);
microbio( :,4)=[];


% ########################################################################
% Combine both tables for micro events

% Add empty col in microbio (# 3 and #5)
bacterio = [microbio ; culture];
%sort by icustay_id ascending


% ########################################################################
% fill-in missing ICUSTAY IDs in bacterio
tic

for i=1:size(bacterio,1)
if bacterio(i,3)==0   %if missing icustayid
    o=bacterio(i,4);  %charttime
    subjectid=bacterio(i,1);
   ii=find(demog.subject_id==subjectid);
    for j=1:numel(ii)
        if o>=demog.admittime(ii(j))-24*3600 & o<=demog.dischtime(ii(j))+24*3600
            bacterio(i,3)=demog.icustay_id(ii(j));
        elseif numel(ii)==1   %if we cant confirm from admission and discharge time but there is only 1 admission: it's the one!!
            bacterio(i,3)=demog.icustay_id(ii(j));
        end
        
        
    end
    
    
end   
end
toc

sum(bacterio(:,3)==0)

% ########################################################################
% fill-in missing ICUSTAY IDs in ABx

tic
for i=1:size(abx,1)
if isnan(abx(i,3))
    o=abx(i,4);  %time of event
    subjectid=abx(i,1);
    ii=find(demog.subject_id==subjectid);   %row in table demographics
    for j=1:numel(ii)
        if o>=demog.admittime(ii(j))-24*3600 & o<=demog.dischtime(ii(j))+24*3600
            abx(i,3)=demog.icustay_id(ii(j));
        elseif numel(ii)==1   %if we cant confirm from admission and discharge time but there is only 1 admission: it's the one!!
            abx(i,3)=demog.icustay_id(ii(j));
        end
    end
end   
end
toc

sum(isnan(abx(:,3)))

%% ########################################################################
%    find presumed onset of infection according to sepsis3 guidelines
% ########################################################################

% in all the various icustay_ids
% version 2 : picks earliest flag

% i loop through all the ABx given, and as soon as there is a sample present
% within the required criteria I pick this flag and break the loop.

onset=zeros(100000,3);
tic
for icustayid=1:100000

  
    ab=abx(abx(:,3)==icustayid+200000,4);   %start time of abx for this subject_id
    bact=bacterio(bacterio(:,3)==icustayid+200000,4);  %time of sample
     subj_ab=abx(abx(:,3)==icustayid+200000,1);  % record subject_ID
%      subj_bact=bacterio(bacterio(:,3)==icustayid+200000,1);
    
    if ~isempty(ab) & ~isempty(bact)
        D = pdist2(ab, bact)/3600;  %pairwise distances btw antibio and cultures, in hours
%         D=bsxfun(@minus,ab,bact);
      for i=1:size(D,1)  % looping through all rows of AB give, from early to late
        [M,I] = min(D(i,:));   %minimum distance in this row
        ab1=ab(i);       %timestamp of this value in list of antibio
        bact1=bact(I);      %timestamp in list of cultures
              
        if M<=24 & ab1<=bact1      %if ab was first and delay < 24h
            onset(icustayid,1)=subj_ab(1);
            onset(icustayid,2)=icustayid;
            onset(icustayid,3)=bact1;     %onset of infection = sample time
              icustayid
            break
        elseif M<=72 & ab1>=bact1    %elseif sample was first and delay < 72h
            onset(icustayid,1)=subj_ab(1);
            onset(icustayid,2)=icustayid;
            onset(icustayid,3)=ab1;       %onset of infection = antibio time
            break
        end
%
      end

%     delay=(ab-bact)/3600;
%     if delay >0 & delay <= 72
%         o=bact
%     elseif delay<0 & delay >-24
%         o=ab
%     end
    end
    
    
    
end
toc

%sum of records found
sum(onset(:,3)>0)

%% ########################################################################
% INITIAL REFORMAT BEFORE SAMPLE-AND-HOLD / WITH CHARTEVENTS, LABS AMD MECHVENT
% ########################################################################

% gives an array with all unique charttime (1 per row) and all items in columns.
% +/- 15-20 min for 25% of the data

reformat=NaN(2000000,68);  %final table  / NaN is better than zero because some values are actually null!!
qstime=zeros(100000,4);

% ################## ACHTUNG
% here i use -48 -> +24 because that's for sepsis3 cohort defintion!!
% I need different time period for the MDP (-24 -> +48)

winb4=49;   %lower limit for inclusion of data (48h before time flag)
winaft=25;  % upper limit (24h after)
irow=1;  %recording row for summary table
tic

for icustayid=1:100000
qst=onset(icustayid,3); %flag for presumed infection
if qst>0  % if we have a flag
   
d1=table2array(demog(demog.icustay_id==icustayid+200000,[11 5])); %age of patient + discharge time

if d1(1)>6574  % if older than 18 years old
    disp(icustayid);

% CHARTEVENTS
% ii=ce1020(:,1)==icustayid+200000; %indexes of items in CE for this icustayid
% temp=ce1020(ii,:);  %temp subtable of interest
    if icustayid<10000
    temp=ce010(ce010(:,1)==icustayid+200000,:);
    elseif icustayid>=10000 & icustayid<20000
    temp=ce1020(ce1020(:,1)==icustayid+200000,:);
    elseif icustayid>=20000 & icustayid<30000
    temp=ce2030(ce2030(:,1)==icustayid+200000,:);
    elseif icustayid>=30000 && icustayid<40000
    temp=ce3040(ce3040(:,1)==icustayid+200000,:);
    elseif icustayid>=40000 & icustayid<50000
    temp=ce4050(ce4050(:,1)==icustayid+200000,:);
    elseif icustayid>=50000 & icustayid<60000
    temp=ce5060(ce5060(:,1)==icustayid+200000,:);
    elseif icustayid>=60000 & icustayid<70000
    temp=ce6070(ce6070(:,1)==icustayid+200000,:);
    elseif icustayid>=70000 & icustayid<80000
    temp=ce7080(ce7080(:,1)==icustayid+200000,:);
    elseif icustayid>=80000 & icustayid<90000
    temp=ce8090(ce8090(:,1)==icustayid+200000,:);
    elseif icustayid>=90000
    temp=ce90100(ce90100(:,1)==icustayid+200000,:);
    end

%temp=CE(CE(:,1)==icustayid+200000,:);

ii=temp(:,2)>= qst-(winb4+4)*3600 & temp(:,2)<=qst+(winaft+4)*3600; %time period of interest -4h and +4h
temp=temp(ii,:);   %only time period of interest

%LABEVENTS
ii=labU(:,1)==icustayid+200000;
temp2=labU(ii,:);
ii=temp2(:,2)>= qst-(winb4+4)*3600 & temp2(:,2)<=qst+(winaft+4)*3600; %time period of interest -4h and +4h
temp2=temp2(ii,:);   %only time period of interest

%Mech Vent + ?extubated
ii=MV(:,1)==icustayid+200000;
temp3=MV(ii,:);
ii=temp3(:,2)>= qst-(winb4+4)*3600 & temp3(:,2)<=qst+(winaft+4)*3600; %time period of interest -4h and +4h
temp3=temp3(ii,:);   %only time period of interest

t=unique([temp(:,2);temp2(:,2); temp3(:,2)]);   %list of unique timestamps from all 3 sources / sorted in ascending order

if t
for i=1:numel(t)
    
    %CHARTEVENTS
    ii=temp(:,2)==t(i);
    itemid=temp(ii,3);
    value=temp(ii,4);
    [loca,locb]=ismember(Refvitals, itemid)   ;  %various manips to find row of itemids...
%   row=find(sum(locb')');%this will bug if I have several items in a row!
    row=find(max(locb')');%THIS works!
%   locb=sum(locb');
    locb=max(locb');
    locb(locb==0)=[];
    locb=locb';
    locb=[locb row];
    locb=sortrows(locb,1);
    row=locb(:,2);
    
    reformat(irow,1)=i; %timestep  
    reformat(irow,2)=icustayid;
    reformat(irow,3)=t(i); %charttime
    reformat(irow,3+row)=value(locb(:,1)); %store available values

      
    %LAB VALUES
    ii=temp2(:,2)==t(i);
    itemid=temp2(ii,3);
    value=temp2(ii,4);
    
    reformat(irow,31+itemid)=value; %store available values
      
    %MV  
    ii=temp3(:,2)==t(i);
    if nansum(ii)>0
    value=temp3(ii,3:4);
    reformat(irow,67:68)=value; %store available values
    else
    reformat(irow,67:68)=NaN;
    end
    
    irow=irow+1;
     
end

qstime(icustayid,1)=qst; %flag for presumed infection / this is time of sepsis if SOFA >=2 for this patient
%HERE I SAVE FIRST and LAST TIMESTAMPS, in QSTIME, for each ICUSTAYID
qstime(icustayid,2)=t(1);  %first timestamp
qstime(icustayid,3)=t(end);  %last timestamp
qstime(icustayid,4)=d1(2); %dischargetime

end

end
end
end
toc

reformat(irow:end,:)=[];


%

% SAVE clean COPY AS REFORMAT_CE
 reformat_CE=reformat;

% reformat=reformat_CE;


% ########################################################################
%                                   OUTLIERS
% ########################################################################
tic
%weight
showout(reformat,5,300)   %show outliers (distrib of variable #5 above and below a threshold)
reformat=deloutabove(reformat,5,300);  %delete outlier above a threshold (300 kg), for variable #5

%HR
showout(reformat,8,250)
reformat=deloutabove(reformat,8,250);

%BP
showout(reformat,9,300)
reformat=deloutabove(reformat,9,300);
showout(reformat,10,0)
reformat=deloutbelow(reformat,10,0);
showout(reformat,10,200)
reformat=deloutabove(reformat,10,200);

showout(reformat,11,0)
reformat=deloutbelow(reformat,11,0);
showout(reformat,11,200)
reformat=deloutabove(reformat,11,200);

%RR
showout(reformat,12,80)
reformat=deloutabove(reformat,12,80);

%SpO2
showout(reformat,13,150)
reformat=deloutabove(reformat,13,150);
ii=reformat(:,13)>100;
reformat(ii,13)=100;

%temp
showout(reformat,14,90)
ii=reformat(:,14)>90 & isnan(reformat(:,15));
reformat(ii,15)=reformat(ii,14);
reformat=deloutabove(reformat,14,90);

%interface / col 22

% FiO2
showout(reformat,23,100)
reformat=deloutabove(reformat,23,100);
showout(reformat,23,21)
ii=reformat(:,23)<1;
reformat(ii,23)=reformat(ii,23)*100;
reformat=deloutbelow(reformat,23,20);
showout(reformat,24,1)
reformat=deloutabove(reformat,24,1.5);


% O2 FLOW
showout(reformat,25,70)
reformat=deloutabove(reformat,25,70);

%PEEP
showout(reformat,26,0)
reformat=deloutbelow(reformat,26,0);
showout(reformat,26,30)
reformat=deloutabove(reformat,26,40);

%TV
showout(reformat,27,1800)
reformat=deloutabove(reformat,27,1800);

%MV
showout(reformat,28,50)
reformat=deloutabove(reformat,28,50);

%K+
showout(reformat,32,1)
reformat=deloutbelow(reformat,32,1);
showout(reformat,32,15)
reformat=deloutabove(reformat,32,15);

%Na
showout(reformat,33,95)
reformat=deloutbelow(reformat,33,95);
showout(reformat,33,178)
reformat=deloutabove(reformat,33,178);

%Cl
showout(reformat,34,70)
reformat=deloutbelow(reformat,34,70);
showout(reformat,34,150)
reformat=deloutabove(reformat,34,150);

%Glc
showout(reformat,35,1)
reformat=deloutbelow(reformat,35,1);
showout(reformat,35,1000)
reformat=deloutabove(reformat,35,1000);

%Creat
showout(reformat,37,150)
reformat=deloutabove(reformat,37,150);

%Mg
showout(reformat,38,10)
reformat=deloutabove(reformat,38,10);

%Ca
showout(reformat,39,20)
reformat=deloutabove(reformat,39,20);

%ionized Ca
showout(reformat,40,5)
reformat=deloutabove(reformat,40,5);

%CO2
showout(reformat,41,120)
reformat=deloutabove(reformat,41,120);

%SGPT/SGOT
showout(reformat,42,10000)
reformat=deloutabove(reformat,42,10000);
showout(reformat,43,10000)
reformat=deloutabove(reformat,43,10000);

%Hb/Ht
showout(reformat,50,20)
reformat=deloutabove(reformat,50,20);
showout(reformat,51,65)
reformat=deloutabove(reformat,51,65);

%WBC
showout(reformat,53,500)
reformat=deloutabove(reformat,53,500);

%plt
showout(reformat,54,2000)
reformat=deloutabove(reformat,54,2000);

%INR
showout(reformat,58,20)
reformat=deloutabove(reformat,58,20);

%pH
showout(reformat,59,6.7)
reformat=deloutbelow(reformat,59,6.7);
showout(reformat,59,8)
reformat=deloutabove(reformat,59,8);

%po2
showout(reformat,60,700)
reformat=deloutabove(reformat,60,700);

%pco2
showout(reformat,61,200)
reformat=deloutabove(reformat,61,200);

%BE
showout(reformat,62,-50)
reformat=deloutbelow(reformat,62,-50);

%lactate
showout(reformat,63,30)
reformat=deloutabove(reformat,63,30);


close ALL

toc


% some data manip / imputation from existing values / 140316

tic

% estimate GCS from RASS
%  data from Wesley JAMA 2003

ii=isnan(reformat(:,6))&reformat(:,7)>=0;
reformat(ii,6)=15;
ii=isnan(reformat(:,6))&reformat(:,7)==-1;
reformat(ii,6)=14;
ii=isnan(reformat(:,6))&reformat(:,7)==-2;
reformat(ii,6)=12;
ii=isnan(reformat(:,6))&reformat(:,7)==-3;
reformat(ii,6)=11;
ii=isnan(reformat(:,6))&reformat(:,7)==-4;
reformat(ii,6)=6;
ii=isnan(reformat(:,6))&reformat(:,7)==-5;
reformat(ii,6)=3;


% FiO2

ii=~isnan(reformat(:,23)) & isnan(reformat(:,24));
reformat(ii,24)=reformat(ii,23)./100;

ii=~isnan(reformat(:,24)) & isnan(reformat(:,23));
reformat(ii,23)=reformat(ii,24).*100;


%ESTIMATE FiO2 /// with use of interface / device (cannula, mask, ventilator....)

reformatsah=SAH(reformat,sample_and_hold);

%NO FiO2, YES O2 flow, no interface OR cannula
ii=find(isnan(reformatsah(:,23))&~isnan(reformatsah(:,25))&(reformatsah(:,22)==0|reformatsah(:,22)==2)); 
reformat(ii(reformatsah(ii,25)<=15),23)=70;
reformat(ii(reformatsah(ii,25)<=12),23)=62;
reformat(ii(reformatsah(ii,25)<=10),23)=55;
reformat(ii(reformatsah(ii,25)<=8),23)=50;
reformat(ii(reformatsah(ii,25)<=6),23)=44;
reformat(ii(reformatsah(ii,25)<=5),23)=40;
reformat(ii(reformatsah(ii,25)<=4),23)=36;
reformat(ii(reformatsah(ii,25)<=3),23)=32;
reformat(ii(reformatsah(ii,25)<=2),23)=28;
reformat(ii(reformatsah(ii,25)<=1),23)=24;

%NO FiO2, NO O2 flow, no interface OR cannula
ii=find(isnan(reformatsah(:,23))&isnan(reformatsah(:,25))&(reformatsah(:,22)==0|reformatsah(:,22)==2));  %no fio2 given and o2flow given, no interface OR cannula
reformat(ii,23)=21;

%NO FiO2, YES O2 flow, face mask OR.... OR ventilator (assume it's face mask)
ii=find(isnan(reformatsah(:,23))&~isnan(reformatsah(:,25))&(reformatsah(:,22)==NaN|reformatsah(:,22)==1|reformatsah(:,22)==3|reformatsah(:,22)==4|reformatsah(:,22)==5|reformatsah(:,22)==6|reformatsah(:,22)==9|reformatsah(:,22)==10)); 
reformat(ii(reformatsah(ii,25)<=15),23)=75;
reformat(ii(reformatsah(ii,25)<=12),23)=69;
reformat(ii(reformatsah(ii,25)<=10),23)=66;
reformat(ii(reformatsah(ii,25)<=8),23)=58;
reformat(ii(reformatsah(ii,25)<=6),23)=40;
reformat(ii(reformatsah(ii,25)<=4),23)=36;

%NO FiO2, NO O2 flow, face mask OR ....OR ventilator
ii=find(isnan(reformatsah(:,23))&isnan(reformatsah(:,25))&(reformatsah(:,22)==NaN|reformatsah(:,22)==1|reformatsah(:,22)==3|reformatsah(:,22)==4|reformatsah(:,22)==5|reformatsah(:,22)==6|reformatsah(:,22)==9|reformatsah(:,22)==10));  %no fio2 given and o2flow given, no interface OR cannula
reformat(ii,23)=NaN;

%NO FiO2, YES O2 flow, Non rebreather mask
ii=find(isnan(reformatsah(:,23))&~isnan(reformatsah(:,25))&reformatsah(:,22)==7); 
reformat(ii(reformatsah(ii,25)>=10),23)=90;
reformat(ii(reformatsah(ii,25)>=15),23)=100;
reformat(ii(reformatsah(ii,25)<10),23)=80;
reformat(ii(reformatsah(ii,25)<=8),23)=70;
reformat(ii(reformatsah(ii,25)<=6),23)=60;

%NO FiO2, NO O2 flow, NRM
ii=find(isnan(reformatsah(:,23))&isnan(reformatsah(:,25))&reformatsah(:,22)==7);  %no fio2 given and o2flow given, no interface OR cannula
reformat(ii,23)=NaN;

% update again FiO2 columns
ii=~isnan(reformat(:,23)) & isnan(reformat(:,24));
reformat(ii,24)=reformat(ii,23)./100;

ii=~isnan(reformat(:,24)) & isnan(reformat(:,23));
reformat(ii,23)=reformat(ii,24).*100;



%BP
ii=~isnan(reformat(:,9))&~isnan(reformat(:,10)) & isnan(reformat(:,11));
reformat(ii,11)=(3*reformat(ii,10)-reformat(ii,9))./2;

ii=~isnan(reformat(:,09))&~isnan(reformat(:,11)) & isnan(reformat(:,10));
reformat(ii,10)=(reformat(ii,9)+2*reformat(ii,11))./3;

ii=~isnan(reformat(:,10))&~isnan(reformat(:,11)) & isnan(reformat(:,9));
reformat(ii,9)=3*reformat(ii,10)-2*reformat(ii,11);


%TEMP
%some values recorded in the wrong column
ii=reformat(:,15)>25&reformat(:,15)<45; %tempF close to 37deg??!
reformat(ii,14)=reformat(ii,15);
reformat(ii,15)=NaN;

ii=reformat(:,14)>70;  %tempC > 70?!!! probably degF
reformat(ii,15)=reformat(ii,14);
reformat(ii,14)=NaN;

ii=~isnan(reformat(:,14)) & isnan(reformat(:,15));
reformat(ii,15)=reformat(ii,14)*1.8+32;

ii=~isnan(reformat(:,15)) & isnan(reformat(:,14));
reformat(ii,14)=(reformat(ii,15)-32)./1.8;


% Hb/Ht
ii=~isnan(reformat(:,50)) & isnan(reformat(:,51));
reformat(ii,51)=(reformat(ii,50)*2.862)+1.216;

ii=~isnan(reformat(:,51)) & isnan(reformat(:,50));
reformat(ii,50)=(reformat(ii,51)-1.216)./2.862;

%BILI
ii=~isnan(reformat(:,44)) & isnan(reformat(:,45));
reformat(ii,45)=(reformat(ii,44)*0.6934)-0.1752;

ii=~isnan(reformat(:,45)) & isnan(reformat(:,44));
reformat(ii,44)=(reformat(ii,45)+0.1752)./0.6934;

toc


%% ########################################################################
%                                SAMPLE AND HOLD
% ########################################################################

tic
reformatsah=SAH(reformat(:,1:68),sample_and_hold);
toc

% prop of missingness after SAH / not displayed - only for reference

miss=sum(isnan(reformatsah(:,1:68)))./size(reformatsah,1);
miss=[sample_and_hold(1,:) ; num2cell(miss(4:end))];

% save SAH into Reformat array
reformat=reformatsah;

% Adding 2 empty cols for future shock index=HR/SBP and P/F
reformat(:,69:70)=NaN(size(reformat,1),2);

%
%% ########################################################################
%                               DATA COMBINATION
% ########################################################################

% ACHTUNG: the time window of interest, for the data, has been selected above! 
% 230816: make sure vasoMV and vasoCV are the right versions!! (no ceiling of doses!!)
% takes 1500 sec on MIT PC


timestep=4;  %in hours
irow=1;
icustayidlist=unique(reformat(:,2));
reformat2=nan(size(reformat,1),84);  %output array
h = waitbar(0,'Initializing waitbar...');

%preadmission fluid
inputpreadm=[inputCVpreadm ; inputMVpreadm(:,[1,2,3,5])]; %dose is STAT in inputMVpreadm -> no need to bother about start and end on infusion
inputpreadm(isnan(inputpreadm(:,4)),:)=[];
npt=numel(icustayidlist);  %number of patients


tic
for i=1:npt
    
    icustayid=icustayidlist(i);  %1 to 100000, NOT 200 to 300K!
  
     
        %CHARTEVENTS AND LAB VALUES
        temp=reformat(reformat(:,2)==icustayid,:);   %subtable of interest
        beg=temp(1,3);   %timestamp of first record
    
        % IV FLUID STUFF
        iv=find(inputMV(:,1)==icustayid+200000);   %rows of interest in inputMV
        input=inputMV(iv,:);    %subset of interest
        iv=find(inputCV(:,1)==icustayid+200000);   %rows of interest in inputCV
        input2=inputCV(iv,:);    %subset of interest
        startt=input(:,2); %start of all infusions and boluses
        endt=input(:,3); %end of all infusions and boluses
        rate=input(:,6);  %rate of infusion (is NaN for boluses)
        
        pread=inputpreadm(inputpreadm(:,1)==icustayid+200000,4) ;%preadmission volume
            if ~isempty(pread)             %store the value, if available
                totvol=nansum(pread);
%                    disp(icustayid)                  %moved here to save some time
                   waitbar(i/npt,h,i/npt*100) %moved here to save some time
            else
                totvol=0;   %if not documented: it's zero
            end
       
        % compute volume of fluid given before start of record!!!
        t0=0;
        t1=beg;
        %input from MV (4 ways to compute)
        infu=  nansum(rate.*(endt-startt).*(endt<=t1&startt>=t0)/3600   +    rate.*(endt-t0).*(startt<=t0&endt<=t1&endt>=t0)/3600 +     rate.*(t1-startt).*(startt>=t0&endt>=t1&startt<=t1)/3600 +      rate.*(t1-t0).*(endt>=t1&startt<=t0)   /3600);
        %all boluses received during this timestep, from inputMV (need to check rate is NaN) and inputCV (simpler):
        bolus=nansum(input(isnan(input(:,6))& input(:,2)>=t0&input(:,2)<=t1,5)) + nansum(input2(input2(:,2)>=t0&input2(:,2)<=t1,4));  
        totvol=nansum([totvol,infu,bolus]); 
            
        %VASOPRESSORS    
        iv=find(vasoMV(:,1)==icustayid+200000);   %rows of interest in vasoMV
        vaso1=vasoMV(iv,:);    %subset of interest
        iv=find(vasoCV(:,1)==icustayid+200000);   %rows of interest in vasoCV
        vaso2=vasoCV(iv,:);    %subset of interest
        startv=vaso1(:,3); %start of VP infusion
        endv=vaso1(:,4); %end of VP infusions
        ratev=vaso1(:,5);  %rate of VP infusion
            

        %DEMOGRAPHICS / gender, age, re-admit, died in hosp?, died within
        %48h of out_time (likely in ICU or soon after), died within 90d
        %after admission?
        demogi=find(demog.icustay_id==icustayid+200000); 
        dem=[  demog.gender(demogi) ; demog.age(demogi) ; demog.Elixhauser(demogi); demog.adm_order(demogi)>1 ;  demog.expire_flag(demogi); abs(demog.dod(demogi)-demog.outtime(demogi))<(24*3600*2); (demog.dod(demogi)-demog.intime(demogi))<(24*3600*90) ; (qstime(icustayid,4)-qstime(icustayid,3))/3600];
        
        % URINE OUTPUT
        iu=find(UO(:,1)==icustayid+200000);   %rows of interest in inputMV
        output=UO(iu,:);    %subset of interest
        pread=UOpreadm(UOpreadm(:,1)==icustayid,4) ;%preadmission UO
            if ~isempty(pread)     %store the value, if available
                UOtot=nansum(pread);
            else
                UOtot=0;
            end
        % adding the volume of urine produced before start of recording!    
        UOnow=nansum(output(output(:,2)>=t0&output(:,2)<=t1,4));  %t0 and t1 defined above
        UOtot=nansum([UOtot UOnow]);
    
    
    for j=0:timestep:79 % -28 until +52 = 80 hours in total
        t0=3600*j+ beg;   %left limit of time window
        t1=3600*(j+timestep)+beg;   %right limit of time window
        ii=temp(:,3)>=t0 & temp(:,3)<=t1;  %index of items in this time period
        if sum(ii)>0
            
            
        %ICUSTAY_ID, OUTCOMES, DEMOGRAPHICS
        reformat2(irow,1)=(j/timestep)+1;   %'bloc' = timestep (1,2,3...)
        reformat2(irow,2)=icustayid;        %icustay_ID
        reformat2(irow,3)=3600*j+ beg;      %t0 = lower limit of time window
        reformat2(irow,4:11)=dem;           %demographics and outcomes
            
        
        %CHARTEVENTS and LAB VALUES (+ includes empty cols for shock index and P/F)
        value=temp(ii,:);%records all values in this timestep
        
          % #####################   DISCUSS ADDING STUFF HERE / RANGE, MIN, MAX ETC   ################
        
        if sum(ii)==1   %if only 1 row of values at this timestep
          reformat2(irow,12:78)=value(:,4:end);
        else
          reformat2(irow,12:78)=nanmean(value(:,4:end)); %mean of all available values
          
        end
        
        
        %VASOPRESSORS
        %for CV: dose at timestamps.
        % for MV: 4 possibles cases, each one needing a different way to compute the dose
        % of VP actually administered:
        %----t0---start----end-----t1----
        %----start---t0----end----t1----
        %-----t0---start---t1---end
        %----start---t0----t1---end----
        % if there are different values during the timestep, I take the
        % median.
        
        %MV
        v=(endv>=t0&endv<=t1)|(startv>=t0&endv<=t1)|(startv>=t0&startv<=t1)|(startv<=t0&endv>=t1);
        %CV
        v2=vaso2(vaso2(:,3)>=t0&vaso2(:,3)<=t1,4);

        %   if sum(v2)>0|sum(v)>0
        %   [ratev(v) ;   median(ratev(v)) ; v2; median(v2);  nanmedian([ratev(v); v2])]
        %   end
        v1=nanmedian([ratev(v); v2]);
        v2=nanmax([ratev(v); v2]);
        if ~isempty(v1)&~isnan(v1)&~isempty(v2)&~isnan(v2)
        reformat2(irow,79)=v1;    %median of dose of VP
        reformat2(irow,80)=v2;    %max dose of VP
        end
        
        %INPUT FLUID
        %input from MV (4 ways to compute)
        infu=  nansum(rate.*(endt-startt).*(endt<=t1&startt>=t0)/3600   +    rate.*(endt-t0).*(startt<=t0&endt<=t1&endt>=t0)/3600 +     rate.*(t1-startt).*(startt>=t0&endt>=t1&startt<=t1)/3600 +      rate.*(t1-t0).*(endt>=t1&startt<=t0)   /3600);
        %all boluses received during this timestep, from inputMV (need to check rate is NaN) and inputCV (simpler):
        bolus=nansum(input(isnan(input(:,6))& input(:,2)>=t0&input(:,2)<=t1,5)) + nansum(input2(input2(:,2)>=t0&input2(:,2)<=t1,4));  
        %sum fluid given
        totvol=nansum([totvol,infu,bolus]);
        reformat2(irow,81)=totvol;    %total fluid given
        reformat2(irow,82)=nansum([infu,bolus]);   %fluid given at this step
        
        %UO
        UOnow=nansum(output(output(:,2)>=t0&output(:,2)<=t1,4));  
        UOtot=nansum([UOtot UOnow]);
        reformat2(irow,83)=UOtot;    %total UO
        reformat2(irow,84)=nansum(UOnow);   %UO at this step

        %CUMULATED BALANCE
        reformat2(irow,85)=totvol-UOtot;    %cumulated balance

        irow=irow+1;
        end
    
    end
    
 
end

reformat2(irow:end,:)=[];
toc

close(h);


%% ########################################################################
%    CONVERT TO TABLE AND DELETE VARIABLES WITH EXCESSIVE MISSINGNESS
% ########################################################################

dataheaders=[sample_and_hold(1,:) {'Shock_Index' 'PaO2_FiO2'}]; 
dataheaders=regexprep(dataheaders,'['']','');
dataheaders = ['bloc','icustayid','charttime','gender','age','elixhauser','re_admission', 'died_in_hosp', 'died_within_48h_of_out_time','mortality_90d','delay_end_of_record_and_discharge_or_death',...
    dataheaders,...
    'median_dose_vaso','max_dose_vaso','input_total','input_4hourly','output_total','output_4hourly','cumulated_balance'];   %!! MAKE SURE SOFA IS MOVED BEFORE WEIGHT!!!!!!!!!!!!!!!!!!
reformat2t=array2table(reformat2);
reformat2t.Properties.VariableNames=dataheaders;
miss=sum(isnan(reformat2))./size(reformat2,1);

% if values have less than 60% missing values (over 40% of values present): I keep them
reformat3t=reformat2t(:,[true(1,11) miss(12:74)<0.70 true(1,11)]) ; 
% make sure i have fio2

%
% ########################################################################
%                          HANDLING OF MISSING VALUES
% ########################################################################

% DO NOT interpolate vasopressors or ttts!!!!
% shall I do this AFTER standardisation???? !!!!!!!!!!!!!!!!

% knnimpute doesnt work if all the rows contain some missingness. I use
% linear interpolation first to fill in the variables with less than 1%
% missingness, so I can use knnimpute
reformat3=table2array(reformat3t);
dataheaders3=reformat3t.Properties.VariableNames;
miss=sum(isnan((reformat3)))./size(reformat3,1);
ii=miss>0&miss<0.999;
% LINEAR INTERPOLATION for a few vars
reformat3(:,ii)=(fixgaps(reformat3(:,ii)));



return



% also interpolates GCS, because kNN gives weird values (zeros)...
reformat3(:,12)=(fixgaps(reformat3(:,12)));


% t=randi([1 47117],500,1);  %test of performance of values imputation: exemple du pH
% o=reformat3(t,50);
% reformat3(t,50)=NaN;

% KNN IMPUTATION
ref=[];

mechventcol=find(ismember(reformat3t.Properties.VariableNames,{'mechvent'}));

tic
for i=1:5000:size(reformat3,1)-4999   %dataset divided in 5K rows chunks (otherwise too large)
    ii=i
 ref=[ref; knnimpute(reformat3(i:i+4999,11:mechventcol-1)',10)']; % select data from weight - to MECH VENT (binary)
end

j=knnimpute(reformat3(end-4999:end,11:mechventcol-1)',10)';  %the last bit is imputed using the last 5K rows
ref=[ref ; j(ii-(size(reformat3,1)-10000):end,:)];  %adding the portion of interest from the last chunk

toc


%% Create Reformat4t

mechventcol=find(ismember(reformat3t.Properties.VariableNames,{'mechvent'}));

reformat4t=reformat3t;
% reformat4t(:,11:mechventcol-1)=array2table(ref);
reformat4t(:,11:mechventcol-1)=array2table(reformat3(:,11:mechventcol-1));
reformat4=table2array(reformat4t);
sum(sum(isnan(reformat4)))
sum(sum(isinf(reformat4))) %this is corrected below



% ########################################################################
%        COMPUTE SOME DERIVED VARIABLES: P/F, Shock Index, SOFA, SIRS
% ########################################################################

nrcol=size(reformat4,2);   %nr of variables in my data (to automate some of the stuff below...)

%CORRECT AGE > 200 yo
ii=reformat4t.age>150*365.25;
reformat4t.age(ii)=91.4*365.25;

%vasopressors / no NAN
a=find(ismember(reformat4t.Properties.VariableNames,{'median_dose_vaso'}));
ii=isnan(reformat4(:,a));
reformat4t(ii,a)=array2table(zeros(sum(ii),1));
a=find(ismember(reformat4t.Properties.VariableNames,{'max_dose_vaso'}));
ii=isnan(reformat4(:,a));
reformat4t(ii,a)=array2table(zeros(sum(ii),1));

% re-compute P/F with no missing values...
% reformat4(:,nrcol-7)=reformat4(:,46)./reformat4(:,23);   %CHECK COL NUMERS #########################################################################
p=find(ismember(reformat4t.Properties.VariableNames,{'paO2'}));
f=find(ismember(reformat4t.Properties.VariableNames,{'FiO2_1'}));
a=find(ismember(reformat4t.Properties.VariableNames,{'PaO2_FiO2'}));

reformat4t(:,a)=array2table(reformat4(:,p)./reformat4(:,f));  

%recompute SHOCK INDEX without NAN and INF
p=find(ismember(reformat4t.Properties.VariableNames,{'HR'}));
f=find(ismember(reformat4t.Properties.VariableNames,{'SysBP'}));
a=find(ismember(reformat4t.Properties.VariableNames,{'Shock_Index'}));

reformat4(:,a)=reformat4(:,p)./reformat4(:,f);  %CHECK COL NUMERS #########################################################################
reformat4(isinf(reformat4(:,a)),a)=NaN;
d=nanmean(reformat4(:,a));
reformat4(isnan(reformat4(:,a)),a)=d;  %replace NaN with average value ~ 0.8
reformat4t(:,a)=array2table(reformat4(:,a));

% SOFA - at each timepoint
% need (in this order):  P/F  MV  PLT  TOT_BILI  MAP  NORAD(max)  GCS  CR  UO
a=zeros(8,1); % indices of vars used in SOFA
a(1)=find(ismember(reformat4t.Properties.VariableNames,{'PaO2_FiO2'}));
a(2)=find(ismember(reformat4t.Properties.VariableNames,{'Platelets_count'}));
a(3)=find(ismember(reformat4t.Properties.VariableNames,{'Total_bili'}));
a(4)=find(ismember(reformat4t.Properties.VariableNames,{'MeanBP'}));
a(5)=find(ismember(reformat4t.Properties.VariableNames,{'max_dose_vaso'}));
a(6)=find(ismember(reformat4t.Properties.VariableNames,{'GCS'}));
a(7)=find(ismember(reformat4t.Properties.VariableNames,{'Creatinine'}));
a(8)=find(ismember(reformat4t.Properties.VariableNames,{'output_4hourly'}));
s=table2array(reformat4t(:,a));  

p=[0 1 2 3 4];

s1=[s(:,1)>400 s(:,1)>=300 &s(:,1)<400 s(:,1)>=200 &s(:,1)<300 s(:,1)>=100 &s(:,1)<200 s(:,1)<100 ];   %count of points for all 6 criteria of sofa
s2=[s(:,2)>150 s(:,2)>=100 &s(:,2)<150 s(:,2)>=50 &s(:,2)<100 s(:,2)>=20 &s(:,2)<50 s(:,2)<20 ];
s3=[s(:,3)<1.2 s(:,3)>=1.2 &s(:,3)<2 s(:,3)>=2 &s(:,3)<6 s(:,3)>=6 &s(:,3)<12 s(:,3)>12 ];
s4=[s(:,4)>=70 s(:,4)<70&s(:,4)>=65 s(:,4)<65 s(:,5)>0 &s(:,5)<=0.1 s(:,5)>0.1 ];
s5=[s(:,6)>14 s(:,6)>12 &s(:,6)<=14 s(:,6)>9 &s(:,6)<=12 s(:,6)>5 &s(:,6)<=9 s(:,6)<=5 ];
s6=[s(:,7)<1.2 s(:,7)>=1.2 &s(:,7)<2 s(:,7)>=2 &s(:,7)<3.5 (s(:,7)>=3.5 &s(:,7)<5)|(s(:,8)<84) (s(:,7)>5)|(s(:,8)<34) ];

reformat4(1,nrcol+1:nrcol+7)=0;  
tic
for i=1:size(reformat4,1)    %2.5 SECONDS FOR all data
    t=max(p(s1(i,:)))+max(p(s2(i,:)))+max(p(s3(i,:)))+max(p(s4(i,:)))+max(p(s5(i,:)))+max(p(s6(i,:)));  %SUM OF ALL 6 CRITERIA
    
    if t
    reformat4(i,nrcol+1:nrcol+7)=    [max(p(s1(i,:))) max(p(s2(i,:))) max(p(s3(i,:))) max(p(s4(i,:))) max(p(s5(i,:))) max(p(s6(i,:))) t];
    end
end
toc


% SIRS - at each timepoint
%  need: temp HR RR PaCO2 WBC 
a=zeros(5,1); % indices of vars used in SOFA
a(1)=find(ismember(reformat4t.Properties.VariableNames,{'Temp_C'}));
a(2)=find(ismember(reformat4t.Properties.VariableNames,{'HR'}));
a(3)=find(ismember(reformat4t.Properties.VariableNames,{'RR'}));
a(4)=find(ismember(reformat4t.Properties.VariableNames,{'paCO2'}));
a(5)=find(ismember(reformat4t.Properties.VariableNames,{'WBC_count'}));
s=table2array(reformat4t(:,a));  

s1=[s(:,1)>=38| s(:,1)<=36];   %count of points for all criteria of SIRS
s2=[s(:,2)>90 ];
s3=[s(:,3)>=20|s(:,4)<=32];
s4=[s(:,5)>=12| s(:,5)<4];
reformat4(:,nrcol+8)=s1+s2+s3+s4;

% adds 2 cols for SOFA and SIRS, if necessary
if sum(ismember(reformat4t.Properties.VariableNames,{'SIRS'}))== 0
reformat4t(:,end+1:end+2)=array2table(0);
reformat4t.Properties.VariableNames(end-1:end)= {'SOFA','SIRS'};  
end

% records values
reformat4t(:,end-1)=array2table(reformat4(:,end-1));
reformat4t(:,end)=array2table(reformat4(:,end));


%% ########################################################################
%                                CREATE REFORMAT5T
% ########################################################################

% headers I want to keep
dataheaders5 = {'bloc','icustayid','charttime','gender','age','elixhauser','re_admission', 'died_in_hosp', 'died_within_48h_of_out_time','mortality_90d','delay_end_of_record_and_discharge_or_death','SOFA','SIRS',...
    'Weight_kg','GCS','HR','SysBP','MeanBP','DiaBP','RR','SpO2','Temp_C','FiO2_1','Potassium','Sodium','Chloride','Glucose',...
    'BUN','Creatinine','Magnesium','Calcium','Ionised_Ca','CO2_mEqL','SGOT','SGPT','Total_bili','Albumin','Hb','WBC_count','Platelets_count','PTT','PT','INR',...
    'Arterial_pH','paO2','paCO2','Arterial_BE','HCO3','Arterial_lactate','mechvent','Shock_Index','PaO2_FiO2',...
    'median_dose_vaso','max_dose_vaso','input_total','input_4hourly','output_total','output_4hourly','cumulated_balance'};

ii=find(ismember(reformat4t.Properties.VariableNames,dataheaders5));

reformat5t=reformat4t(:,ii); 

%shock index had NANs : reformat5(:,48)=reformat5(:,13)./reformat5(:,14);
sum(sum(isnan(reformat5t.PaO2_FiO2)))

% check for patients with extreme UO = outliers = to be deleted (>40 litres of UO per 4h!!)
a=find(reformat5t.output_4hourly>12000);
i=unique(reformat5t.icustayid(a));
i=find(ismember(reformat5t.icustayid,i));
reformat5t(i,:)=[];

a=find(reformat5t.Total_bili>10000); % some have bili = 999999
i=unique(reformat5t.icustayid(a));
i=find(ismember(reformat5t.icustayid,i));
reformat5t(i,:)=[];


% some derived values

blocs=(reformat5t.bloc);
icustayidlist=(reformat5t.icustayid);
% hrs=reformat5(:,3);
Y90=reformat5t.mortality_90d;


% CHECK is any remaining NaNs

sum(isnan(table2array(reformat5t)))

% reformat5t(:,58)=fixgaps(reformat5t(:,58));  %what is this??

 reformat5t.mechvent=fixgaps(reformat5t.mechvent);
 reformat5t.elixhauser(isnan(reformat5t.elixhauser))=nanmedian(reformat5t.elixhauser);  %median value / only 244/252677 records

 sum(isnan(table2array(reformat5t)))
 sum(isinf(table2array(reformat5t)))

reformat5t.gender=reformat5t.gender-1; 
%% ########################################################################
%                            exclusion criteria
% ########################################################################


% delete patients who do not receive any fluid !!!!
icustayidlist=unique(reformat(:,2));

totiv=zeros(numel(icustayidlist),2);
for i=1:numel(icustayidlist)
    ii=sum(reformat5t.input_4hourly(reformat5t.icustayid==icustayidlist(i)));
if ii==0
    icustayidlist(i)
    reformat5t(reformat5t.icustayid== icustayidlist(i),:)=[];
end
    
end
 
 
%% ########################################################################
%                       CREATE SEPSIS COHORT
% ########################################################################

% create array with 1 row per icu admission
% keep only patients with sepsis (max sofa during time period of interest >= 2)

sepsis=zeros(30000,5);
irow=1;

tic
for icustayid=1:100000
    
%     ii=find(reformat5t(:,2)==icustayid);
    ii=find(ismember(reformat5t.icustayid,icustayid));
    if ii
        
         sofa=reformat5t.SOFA(ii);
         sirs=reformat5t.SIRS(ii);
         sepsis(irow,1)=icustayid+200000; 
         sepsis(irow,2)=reformat5t.mortality_90d(ii(1)); % 90-day mortality
         sepsis(irow,3)=max(sofa);
         sepsis(irow,4)=max(sirs);
         sepsis(irow,5)=qstime(icustayid);   %time of onset of sepsis
         irow=irow+1;
         
        
    end
    

    
end

toc
sepsis(irow:end,:)=[];

sepsis=array2table(sepsis);
sepsis.Properties.VariableNames={'icustayid','morta_90d','max_sofa','max_sirs','sepsis_time'};

% delete all 
sepsis(sepsis.max_sofa<2,:)=[];

writetable(sepsis,'sepsis_mimiciii.csv','Delimiter',',');

datetime('now')





