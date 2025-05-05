##########################################################################
# Parameters
param nPeriods >= 1;                     # Number of time periods

#------------------------------------------
#   Sets
#------------------------------------------
set TIME_PERIODS = {1..nPeriods} circular;
set ZONES;
set LINES;
set GENERATORS;
set STORAGE;

#------------------------------------------
#   Parameters
#------------------------------------------
param operating_cost{GENERATORS,ZONES};
param capacity_cost_gen{GENERATORS,ZONES};
param power_viol_penalty = 10000;

param capacity_cost_stor{STORAGE} >= 0, default 60000;
param storage_duration{STORAGE} >= 0, default 4;
param discharge_eff{STORAGE} >= 0, <= 1, default .93;
param charge_eff{STORAGE} >= 0, <= 1, default .93;


param line_incidence{LINES,ZONES};
param line_capacity{LINES};

param fixed_demand{TIME_PERIODS,ZONES};
param wind_avail{TIME_PERIODS,ZONES};
param solar_avail{TIME_PERIODS,ZONES};

#------------------------------------------
#   Variables
#------------------------------------------
# --- set GENERATOR installed capacity
var capacity_installed_ger{g in GENERATORS,n in ZONES} >= 0;
var capacity_installed_stor{b in STORAGE,n in ZONES} >= 0;
var Prod_generator{g in GENERATORS, t in TIME_PERIODS, n in ZONES} >= 0;

# --- set STORAGE variables
var SOC{b in STORAGE,t in TIME_PERIODS, n in ZONES} >= 0;
var Charge {b in STORAGE,t in TIME_PERIODS, n in ZONES} >= 0; #Ammount to charge battery
var Discharge {b in STORAGE,t in TIME_PERIODS, n in ZONES} >= 0; #Ammount discharged by the battery


var Curtailment{t in TIME_PERIODS,n in ZONES} >= 0; # System balance deficit variable

var flow{l in LINES, t in TIME_PERIODS};



##########################################################################
# Objective function

minimize total_cost:
    sum{g in GENERATORS,n in ZONES} capacity_cost_gen[g,n] * capacity_installed_ger[g,n]
	+ sum{b in STORAGE,n in ZONES} capacity_cost_stor[b] * capacity_installed_stor[b,n]
	+ sum{g in GENERATORS, t in TIME_PERIODS,n in ZONES} operating_cost[g,n] * Prod_generator[g,t,n] 
	+ sum{n in ZONES, t in TIME_PERIODS} power_viol_penalty*Curtailment[t,n]
	;

#------------------------------------------
#   Constraints
#------------------------------------------

# System power balance
subject to SystemBalance{t in TIME_PERIODS, n in ZONES}:
	sum{g in GENERATORS} Prod_generator[g,t,n] 
	+ sum{b in STORAGE} (Discharge[b,t,n] - Charge[b,t,n])
	+ Curtailment[t,n] 
	= fixed_demand[t,n] 
	+ sum{l in LINES} line_incidence[l,n] * flow[l,t]
	;
	
#Can't produce more than installed capacity
subject to MaxGen{g in GENERATORS,t in TIME_PERIODS,n in ZONES}:
	Prod_generator[g,t,n] 
	<= capacity_installed_ger[g,n]
	;

# Variable SOLAR limits
subject to LimitSolar{t in TIME_PERIODS, n in ZONES}:
	Prod_generator['SOLAR',t,n] 
	<= solar_avail[t,n] * capacity_installed_ger['SOLAR',n]
	;
	
# Variable WIND limits
subject to LimitWind{t in TIME_PERIODS, n in ZONES}:
	Prod_generator['WIND',t,n] 
	<= wind_avail[t,n] * capacity_installed_ger['WIND',n]
	;

# Storage SOC consistency	
subject to SOCConsistency{b in STORAGE, t in TIME_PERIODS,n in ZONES}:
	SOC[b,t,n] 
	- SOC[b,prev(t),n] 
	+ Discharge[b,t,n]/discharge_eff[b] 
	- Charge[b,t,n]*charge_eff[b] 
	= 0
	;
	
# Enforce maximum storage
subject to SOCMax{b in STORAGE, t in TIME_PERIODS, n in ZONES}:
	SOC[b,t,n] 
	<= storage_duration[b]*capacity_installed_stor[b,n]
	;

# Enforce maximum storage charge
subject to MinStor{b in STORAGE, t in TIME_PERIODS, n in ZONES}:
    Charge[b,t,n] 
    - capacity_installed_stor[b,n] 
    <= 0
    ;

# Enforce maximum storage discharge
subject to MaxStor{b in STORAGE, t in TIME_PERIODS, n in ZONES}:
    Discharge[b,t,n] 
    -  capacity_installed_stor[b,n] 
    <= 0
    ;
    
    
subject to LineCapacityPos{l in LINES, t in TIME_PERIODS}:
    flow[l,t] <= line_capacity[l];


subject to LineCapacityNeg{l in LINES, t in TIME_PERIODS}:
    -flow[l,t] <= line_capacity[l];
    