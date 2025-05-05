##########################################################################
# Parameters
param nPeriods >= 1; # Number of time periods

#------------------------------------------
# Sets
#------------------------------------------
set TIME_PERIODS = {1..nPeriods} circular;
set ZONES;
set LINES;
set GENERATORS;
set STORAGE;
set ISOS;
#------------------------------------------
# Parameters
#------------------------------------------
param capacity_cost_gen{GENERATORS,ZONES};
param capacity_cost_stor{STORAGE} >= 0, default 60000;
param operating_cost_stor{STORAGE};
param operating_cost{GENERATORS,ZONES};

param max_installed_capacity_gen{g in GENERATORS, n in ZONES} >= 0;

param max_installed_capacity_stor{b in STORAGE, n in ZONES} >= 0;
param existing_installed_capacity_gen{g in GENERATORS, n in ZONES} >= 0;
param existing_installed_capacity_stor{b in STORAGE, n in ZONES} >= 0;

param power_viol_penalty = 10000;

param storage_duration{STORAGE} >= 0, default 4;
param discharge_eff{STORAGE} >= 0, <= 1, default .93;
param charge_eff{STORAGE} >= 0, <= 1, default .93;

param line_capacity{LINES} >= 0;  
param line_from{LINES} symbolic in ZONES;
param line_to{LINES} symbolic in ZONES;


param fixed_demand{TIME_PERIODS,ZONES};
param wind_avail{TIME_PERIODS,ZONES};
param solar_avail{TIME_PERIODS,ZONES};

# Parameter for annual fixed maintenance cost of gas plants ($/MW)
param fixed_maintenance_cost default 10;

param iso_connections{w in ISOS,n in ZONES};
param price_iso{w in ISOS};

#------------------------------------------
# Variables
#------------------------------------------
# --- Generator variables

var new_capacity_installed_gen{g in GENERATORS,n in ZONES} >= 0;
var new_capacity_installed_stor{b in STORAGE,n in ZONES} >= 0;
var retired_capacity_gen{g in GENERATORS,n in ZONES} >= 0;

var Prod_generator{g in GENERATORS, t in TIME_PERIODS, n in ZONES} >= 0;

# --- Storage variables
var SOC{b in STORAGE, t in TIME_PERIODS, n in ZONES} >= 0;
var Charge{b in STORAGE, t in TIME_PERIODS, n in ZONES} >= 0; # Amount to charge battery
var Discharge{b in STORAGE, t in TIME_PERIODS, n in ZONES} >= 0; # Amount discharged by the battery

# --- Power flow variables
var flow{l in LINES, t in TIME_PERIODS};  

# --- System balance variables
var Load_shed{t in TIME_PERIODS, n in ZONES} >= 0; # Load curtailment variable

var imports{n in ZONES, t in TIME_PERIODS, w in ISOS} >= 0;

##########################################################################
# Objective function

minimize Total_cost:
  sum{t in TIME_PERIODS, n in ZONES} power_viol_penalty * Load_shed[t,n]
+ sum{b in STORAGE, n in ZONES} capacity_cost_stor[b] * new_capacity_installed_stor[b,n]
#+ sum{b in STORAGE, t in TIME_PERIODS,n in ZONES} operating_cost_stor[b] * Discharge[b,t,n]
+ sum{g in GENERATORS, n in ZONES} capacity_cost_gen[g,n] * new_capacity_installed_gen[g,n]
+ sum{g in GENERATORS, t in TIME_PERIODS, n in ZONES} operating_cost[g,n] * Prod_generator[g,t,n]
+ sum{g in GENERATORS, n in ZONES: g = "GAS"} fixed_maintenance_cost * (existing_installed_capacity_gen[g,n] - retired_capacity_gen[g,n])
+ sum{g in GENERATORS, n in ZONES: g = "NUCLEAR"} fixed_maintenance_cost * (existing_installed_capacity_gen[g,n] - retired_capacity_gen[g,n])
+ sum{n in ZONES, t in TIME_PERIODS, w in ISOS} imports[n,t,w] * price_iso[w];
;
#------------------------------------------
# Constraints
#------------------------------------------

# System power balance (nodal balance)
subject to NodeBalance{t in TIME_PERIODS, n in ZONES}:
    sum{g in GENERATORS} Prod_generator[g,t,n]
    + sum{b in STORAGE} (Discharge[b,t,n] - Charge[b,t,n])
    - fixed_demand[t,n]
    + Load_shed[t,n]
    - sum{l in LINES: line_from[l] == n} flow[l,t]
    + sum{l in LINES: line_to[l] == n} flow[l,t]
    + sum{w in ISOS} imports[n,t,w]
    =  0
    ;

# Line capacity constraints
subject to LineCapacityPos{l in LINES, t in TIME_PERIODS}:
    flow[l,t] <= line_capacity[l];

subject to LineCapacityNeg{l in LINES, t in TIME_PERIODS}:
    -flow[l,t] <= line_capacity[l];

# Can't produce more than installed capacity
subject to MaxGen{g in GENERATORS, t in TIME_PERIODS, n in ZONES}:
    Prod_generator[g,t,n]  <= existing_installed_capacity_gen[g,n] 
    +  new_capacity_installed_gen[g,n];

subject to MaxGenGas{t in TIME_PERIODS, n in ZONES}:
    Prod_generator["GAS",t,n] 
    <= existing_installed_capacity_gen["GAS",n] 
	+ new_capacity_installed_gen["GAS",n] 
	- retired_capacity_gen["GAS",n];

subject to MaxGenNucler{t in TIME_PERIODS, n in ZONES}:
    Prod_generator["NUCLEAR",t,n] 
    <= existing_installed_capacity_gen["NUCLEAR",n] 
	+ new_capacity_installed_gen["NUCLEAR",n] 
	- retired_capacity_gen["NUCLEAR",n];

subject to MaxStorage{b in STORAGE, n in ZONES}:
    (existing_installed_capacity_stor[b,n] 
    + new_capacity_installed_stor[b,n])  <= max_installed_capacity_stor[b,n] 
;

subject to MaxWind{g in GENERATORS, n in ZONES}:
    (existing_installed_capacity_gen['WIND',n] 
    + new_capacity_installed_gen['WIND',n])  <= max_installed_capacity_gen['WIND',n] 
;

subject to MaxSolar{g in GENERATORS, n in ZONES}:
    (existing_installed_capacity_gen['SOLAR',n] 
    + new_capacity_installed_gen['SOLAR',n])  <= max_installed_capacity_gen['SOLAR',n] 
;


subject to ImportLimit{n in ZONES,t in TIME_PERIODS, w in ISOS}:
	imports[n,t,w] <= iso_connections[w,n];
	
# Variable SOLAR limits
subject to LimitSolar{t in TIME_PERIODS, n in ZONES}:
    Prod_generator['SOLAR',t,n]  <= solar_avail[t,n] * (new_capacity_installed_gen['SOLAR',n]+ existing_installed_capacity_gen['SOLAR',n]);

# Variable WIND limits
subject to LimitWind{t in TIME_PERIODS, n in ZONES}:
    Prod_generator['WIND',t,n]  <= wind_avail[t,n] * (new_capacity_installed_gen['WIND',n]+ existing_installed_capacity_gen['WIND',n]);

# Storage SOC consistency
subject to SOCConsistency{b in STORAGE, t in TIME_PERIODS, n in ZONES}:
    SOC[b,t,n] - SOC[b,prev(t),n] + Discharge[b,t,n]/discharge_eff[b] - Charge[b,t,n]*charge_eff[b] = 0;

# Enforce maximum storage
subject to SOCMax{b in STORAGE, t in TIME_PERIODS, n in ZONES}:
    SOC[b,t,n] <= storage_duration[b] * (existing_installed_capacity_stor[b,n] + new_capacity_installed_stor[b,n]);

# Enforce maximum storage charge
subject to MaxCharge{b in STORAGE, t in TIME_PERIODS, n in ZONES}:
    Charge[b,t,n] <= (existing_installed_capacity_stor[b,n] + new_capacity_installed_stor[b,n]);

# Enforce maximum storage discharge
subject to MaxDischarge{b in STORAGE, t in TIME_PERIODS, n in ZONES}:
    Discharge[b,t,n] <= (existing_installed_capacity_stor[b,n] + new_capacity_installed_stor[b,n]);

#subject to MaxLoadShed{t in TIME_PERIODS,n in ZONES}:
#	Load_shed[t,n] <= fixed_demand[t,n];

#HYDRO full generation always
#subject to MaxHydro{t in TIME_PERIODS,n in ZONES}:
#	Prod_generator['HYDRO',t,n] = existing_installed_capacity_gen['HYDRO',n];