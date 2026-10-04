# Production_Optimisation.jl 
<!-- DO NOT EDIT BELOW -->
[![Tests](../../actions/workflows/tests.yml/badge.svg)](../../actions/workflows/tests.yml)
[![Documentation](../../actions/workflows/docs.yml/badge.svg)](../../actions/workflows/docs.yml)
<!-- DO NOT EDIT ABOVE -->


## Overview

<!-- DESCRIBE PROJECT PURPOSE BELOW -->
Title: Demand–Production Gap Analysis and Capacity Optimization in Manufacturing

How can manufacturing demand and production data be analysed to identify shortages, excess production, and machine bottlenecks, and how can production be reallocated to reduce these mismatches and Storing in the warehouse

<!-- DESCRIBE PROJECT PURPOSE ABOVE  -->

## Getting started

<!-- DO NOT EDIT BELOW -->
Clone the repository and start Julia in the project folder:

```bash
git clone https://github.com/KLU-BADS/project-5-scientific-programming-2026.git
cd project-5-scientific-programming-2026
julia --project=.
```
<!-- DO NOT EDIT ABOVE -->


<!-- DESCRIBE THE ESSENTIAL USAGE BELOW -->
Once the package is cloned you can run:

```julia
using Project5
hello()
```
to print "Hello World" to standard output.
<!-- DESCRIBE THE ESSENTIAL USAGE ABOVE -->

## Tests

<!-- DO NOT EDIT BELOW -->
Tests are run automatically on GitHub for every push to `main` and on every pull request.

> [!TIP]
> To run the tests locally, run
> ```bash
> julia --project=. -e 'using Pkg; Pkg.test()'
> ```
 
<!-- DO NOT EDIT ABOVE -->

Project Data Sheet — README
Overview
The Project Data Sheet contains production order, manufacturing operation, machine, inventory, and machine-breakdown information used for production planning and optimisation.
This dataset intentionally contains data errors for testing and execution of the Data Module. These errors are included to verify that the Data Module can identify, validate, and handle incorrect, missing, and inconsistently formatted data during execution.
The dataset contains:
- 990 data rows
- 26 columns
This README documents the structure of the Project Data Sheet, the data errors present in it, the corrections required, and the calculations needed for production analysis.
Data Source
The Project Data Sheet was prepared using fabricated data based on the project requirements and the process defined in the project flowchart. The data was structured to represent the information required for the different stages of the production optimisation process.
AI assistance was used during the data preparation process for guidance and support in organising the data, identifying suitable attributes, and reviewing the dataset structure.
Intentional data errors were included in the Project Data Sheet to support the testing and execution of the Data Module.
Dataset Structure
1. Sr_No --- sequential record number.
2. Order_ID --- production order identifier.
3. Order_Date --- date the order was created.
4. Due_Date --- required order completion date.
5. Product_ID --- product identifier.
6. Order_Quantity --- quantity ordered.
7. Priority --- priority assigned to the order.
8. Customer_Type --- customer category.
9. Order_Status --- current order status.
10. Operation_ID --- manufacturing operation identifier.
11. Operation_Name --- manufacturing operation name.
12. Sequence --- sequence of the operation.
13. Machine_ID --- machine identifier.
14. Machine_Type --- machine category/type.
15. Eligible --- indicates whether the machine is eligible for the
    operation.
16. Standard_Cycle_Time_Min_Unit --- standard processing time in
    minutes per unit.
17. Setup_Time_Min --- machine setup time in minutes.
18. Machine_Capacity_Units_Shift --- machine capacity in units per
    shift.
19. Machine_Efficiency --- machine efficiency ratio.
20. Machine_Status --- current machine condition/status.
21. Available_Hours_Shift --- available machine hours per shift.
22. Current_Stock --- current inventory quantity.
23. Safety_Stock --- minimum stock quantity that should be maintained.
24. Reserved_Stock --- inventory quantity already reserved.
25. Breakdown_Probability --- estimated probability of machine
    breakdown.
26. Breakdown_Duration_Min --- expected machine breakdown duration in
    minutes.
Data Errors
The Project Data Sheet contains 6 individual data-value errors and a
systematic date-format issue affecting the Order_Date and Due_Date
columns.
Error 1 --- Sr_No 1
Column: Eligible
Error value: yes
Required value: Yes
Error type: inconsistent capitalization.

Error 2 --- Sr_No 2
Column: Machine_Status
Error value: maintenance
Required value: Reduced
Error type: incorrect categorical value.

Error 3 --- Sr_No 3
Column: Customer_Type
Error value: premium
Required value: Standard
Error type: incorrect categorical value.

Error 4 --- Sr_No 4
Column: Machine_Efficiency
Error value: blank/missing
Required value: 0.89
Error type: missing numeric value.

Error 5 --- Sr_No 5
Column: Breakdown_Probability
Error value: blank/missing
Required value: 4%
Error type: missing percentage value.

Error 6 --- Sr_No 6
Column: Machine_ID
Error value: blank/missing
Required value: M06
Error type: missing machine identifier.

Required Calculations
1. Available Inventory
Determines the stock available after reserved stock and safety stock are
considered.
Available_Inventory = Current_Stock - Reserved_Stock - Safety_Stock
2. Inventory Shortage
Determines whether additional inventory is required for an order.
Inventory_Shortage = max(0, Order_Quantity - Available_Inventory)
3. Effective Machine Capacity
Adjusts machine capacity according to machine efficiency.
Effective_Capacity = Machine_Capacity_Units_Shift × Machine_Efficiency
4. Basic Processing Time
Calculates the processing time required for the ordered quantity.
Basic_Processing_Time_Min = Order_Quantity × Standard_Cycle_Time_Min_Unit
5. Efficiency-Adjusted Processing Time
Adjusts processing time according to machine efficiency.
Adjusted_Processing_Time_Min = Basic_Processing_Time_Min / Machine_Efficiency
6. Total Required Machine Time
Includes both processing time and machine setup time.
Total_Required_Time_Min = Setup_Time_Min + Adjusted_Processing_Time_Min
7. Available Machine Time per Shift
Converts available machine hours into minutes.
Available_Machine_Time_Min = Available_Hours_Shift × 60
8. Required Shifts
Calculates the number of shifts needed to complete an operation.
Required_Shifts = Total_Required_Time_Min / Available_Machine_Time_Min
If whole shifts are required, the result should be rounded upward.
9. Capacity-Based Required Shifts
Provides an alternative shift calculation based on machine capacity.
Capacity_Based_Shifts = Order_Quantity / Effective_Capacity
10. Expected Breakdown Downtime
Estimates expected downtime using breakdown probability and duration.
Expected_Breakdown_Downtime_Min = Breakdown_Probability × Breakdown_Duration_Min
The percentage must first be represented as a decimal. For example:
4% = 0.04
11. Breakdown-Adjusted Required Time
Adds expected breakdown downtime to the required production time.
Breakdown_Adjusted_Time_Min = Total_Required_Time_Min + Expected_Breakdown_Downtime_Min
12. Order Lead Time
Calculates the number of days available between the order date and due
date.
Order_Lead_Time_Days = Due_Date - Order_Date
Conclusion
This dataset is used to test how the module identifies and handles data errors during execution. The intentional errors help verify that missing, incorrect, and inconsistent values are handled correctly before the data is used for calculations and production optimisation.
Note
The entire module runs through the project code and uses the Project Data Sheet as input.
If any changes are made to the Project Data Sheet or to the related code, please keep the team informed. Changes to the dataset structure, values, or code may affect the execution, calculations, and results of the entire module.


<!-- DO NOT EDIT BELOW -->
The [online documentation](https://klu-bads.github.io/project-5-scientific-programming-2026/) is automatically built and published to GitHub Pages on every push to `main`.

> [!TIP]
> To build the documentation locally, run
> ```bash
> julia --project=docs docs/make.jl
> ```
> and open `docs/build/index.html` in a browser.
>
> If building the documentation fails, run the tests locally before. 


<!-- DO NOT EDIT ABOVE -->

## Contributing

<!-- DO NOT EDIT BELOW -->
See [CONTRIBUTING.md](CONTRIBUTING.md).
<!-- DO NOT EDIT ABOVE -->

## License

<!-- DO NOT EDIT BELOW -->
MIT. See [LICENSE](LICENSE).
<!-- DO NOT EDIT ABOVE -->

