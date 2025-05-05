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

#------------------------------------------
# Parameters
#------------------------------------------
param operating_cost{GENERATORS,ZONES};
param capacity_cost_gen{GENERATORS,ZONES};
param power_viol_penalty = 10000;

param capacity_cost_stor{STORAGE} >= 0, default 60000;
param storage_duration{STORAGE} >= 0, default 4;
param discharge_eff{STORAGE} >= 0, <= 1, default .93;
param charge_eff{STORAGE} >= 0, <= 1, default .93;

# DCOPF parameters
param line_reactance{LINES} > 0;  # Line reactance (X)
param line_capacity{LINES} >= 0;  # Line thermal limits
param line_from{LINES} symbolic in ZONES;  # "From" bus for each line
param line_to{LINES} symbolic in ZONES;    # "To" bus for each line
param base_MVA default 100;       # Base MVA for per unit calculations

# Reference bus (slack bus)
param ref_bus symbolic in ZONES;

param fixed_demand{TIME_PERIODS,ZONES};
param wind_avail{TIME_PERIODS,ZONES};
param solar_avail{TIME_PERIODS,ZONES};

param max_load_shed_fraction default 0.2;
#------------------------------------------
# Variables
#------------------------------------------
# --- Generator variables
var capacity_installed_gen{g in GENERATORS, n in ZONES} >= 0;
var capacity_installed_stor{b in STORAGE, n in ZONES} >= 0;
var Prod_generator{g in GENERATORS, t in TIME_PERIODS, n in ZONES} >= 0;

# --- Storage variables
var SOC{b in STORAGE, t in TIME_PERIODS, n in ZONES} >= 0;
var Charge{b in STORAGE, t in TIME_PERIODS, n in ZONES} >= 0; # Amount to charge battery
var Discharge{b in STORAGE, t in TIME_PERIODS, n in ZONES} >= 0; # Amount discharged by the battery

# --- Power flow variables
var theta{t in TIME_PERIODS, n in ZONES};  # Voltage angles at each bus
var flow{l in LINES, t in TIME_PERIODS};   # Line flows (can be positive or negative)

# --- System balance variables
var load_shed{t in TIME_PERIODS, n in ZONES} >= 0; # Amount of load shed at each zone

##########################################################################
# Objective function
# minimize total_load_shed:

minimize total_cost:
sum{g in GENERATORS, n in ZONES} capacity_cost_gen[g,n] * capacity_installed_gen[g,n]
+ sum{b in STORAGE, n in ZONES} capacity_cost_stor[b] * capacity_installed_stor[b,n]
+ sum{g in GENERATORS, t in TIME_PERIODS, n in ZONES} operating_cost[g,n] * Prod_generator[g,t,n]
+ sum{n in ZONES, t in TIME_PERIODS} power_viol_penalty * load_shed[t,n]
;

#------------------------------------------
# Constraints
#------------------------------------------

# Optional: Maximum Load Shedding Constraint
subject to MaxLoadShed{t in TIME_PERIODS, n in ZONES}:
    load_shed[t,n] <= max_load_shed_fraction * fixed_demand[t,n];

# Reference bus angle constraint
subject to RefBusAngle{t in TIME_PERIODS}:
    theta[t,ref_bus] = 0;

# DC power flow constraint
#the voltage phase angle at bus  relative to the slack or reference bus
#fix theta["H"] = 0 (slack bus)
subject to DCPowerFlow{l in LINES, t in TIME_PERIODS}:
    flow[l,t] = (theta[t,line_from[l]] - theta[t,line_to[l]]) / line_reactance[l] * base_MVA;

# Line capacity constraints
subject to LineCapacityPos{l in LINES, t in TIME_PERIODS}:
    flow[l,t] <= line_capacity[l];

subject to LineCapacityNeg{l in LINES, t in TIME_PERIODS}:
    -flow[l,t] <= line_capacity[l];

# System power balance (nodal balance)
subject to NodeBalance{t in TIME_PERIODS, n in ZONES}:
    sum{g in GENERATORS} Prod_generator[g,t,n]
    + sum{b in STORAGE} (Discharge[b,t,n] - Charge[b,t,n])
    - (fixed_demand[t,n] - load_shed[t,n])
    = sum{l in LINES: line_from[l] = n} flow[l,t] - sum{l in LINES: line_to[l] = n} flow[l,t];

# Can't produce more than installed capacity
subject to MaxGen{g in GENERATORS, t in TIME_PERIODS, n in ZONES}:
    Prod_generator[g,t,n] <= capacity_installed_gen[g,n];

# Variable SOLAR limits
subject to LimitSolar{t in TIME_PERIODS, n in ZONES}:
    Prod_generator['SOLAR',t,n] <= solar_avail[t,n] * capacity_installed_gen['SOLAR',n];

# Variable WIND limits
subject to LimitWind{t in TIME_PERIODS, n in ZONES}:
    Prod_generator['WIND',t,n] <= wind_avail[t,n] * capacity_installed_gen['WIND',n];

# Storage SOC consistency
subject to SOCConsistency{b in STORAGE, t in TIME_PERIODS, n in ZONES}:
    SOC[b,t,n] - SOC[b,prev(t),n] + Discharge[b,t,n]/discharge_eff[b] - Charge[b,t,n]*charge_eff[b] = 0;

# Enforce maximum storage
subject to SOCMax{b in STORAGE, t in TIME_PERIODS, n in ZONES}:
    SOC[b,t,n] <= storage_duration[b] * capacity_installed_stor[b,n];

# Enforce maximum storage charge
subject to MaxCharge{b in STORAGE, t in TIME_PERIODS, n in ZONES}:
    Charge[b,t,n] <= capacity_installed_stor[b,n];

# Enforce maximum storage discharge
subject to MaxDischarge{b in STORAGE, t in TIME_PERIODS, n in ZONES}:
    Discharge[b,t,n] <= capacity_installed_stor[b,n];