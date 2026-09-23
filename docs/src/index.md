# Production_Optimisation.jl

## Manufacturing Order-to-Machine Allocation

Production_Optimisation.jl is a Julia-based manufacturing planning and optimization project that
allocates production orders to suitable machines while considering production
requirements, machine capabilities, processing time, production cost, machine
capacity, efficiency, yield rate, priorities, and due dates.

The project follows an end-to-end workflow:

1. Data Loading
2. Data Cleaning and Validation
3. Demand and Inventory Analysis
4. Processing-Time Estimation and Scoring
5. Optimization and Scheduling
6. Production Plan Generation
7. Warehouse and Performance Evaluation
8. Implementation and Monitoring
9. Replanning

The main objective is to transform manufacturing data into a feasible and
optimized production plan.

---

## Project Overview

Manufacturing companies often receive multiple orders that must be produced
using a limited number of machines. Different machines may have different
capabilities, processing speeds, costs, availability, efficiencies, and yields.

Therefore, assigning every order to an arbitrary machine may result in:

- machine overload,
- unnecessary production cost,
- delayed orders,
- poor machine utilization,
- or production quantities that do not satisfy inventory requirements.

Production_Optimisation.jl addresses this problem by combining data analysis, machine
eligibility, processing-time estimation, scoring, mathematical optimization,
scheduling, and performance evaluation.

## Module Responsibilities

## DataModule.jl:
Input:
    Excel dataset

Functions:
    load_and_clean_data()
    validate_data()

Output:
    Clean DataFrame

## DemandModule.jl
Input:
    Clean DataFrame

Functions:
    demand_analysis()
    priority_weight()

Output:
    Order-level production requirements

## ScoringModule.jl
Input:
    Orders + machine data

Functions:
    build_eligible_pairs()
    score_candidates()

Output:
    Feasible order-machine pairs
    Expected processing times
    P50/P90 estimates
    Scores

## OptimizationModule.jl
Input:
    Feasible/scored pairs

Functions:
    optimize_allocation()
    build_schedule()
    replan_schedule()

Output:
    Optimized machine allocation
    Production schedule
    Replanned schedule

## EvaluationModule.jl
Input:
    Production schedule

Functions:
    evaluate_plan()
    export_results()
    make_charts()

Output:
    KPIs
    CSV files
    Reports
    Charts  