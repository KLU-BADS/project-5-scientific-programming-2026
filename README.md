# Production_Optimisation.jl

<!-- DO NOT EDIT BELOW -->
[![Tests](../../actions/workflows/tests.yml/badge.svg)](../../actions/workflows/tests.yml)
[![Documentation](../../actions/workflows/docs.yml/badge.svg)](../../actions/workflows/docs.yml)
<!-- DO NOT EDIT ABOVE -->

## Overview

**Title:** Demand–Production Gap Analysis and Capacity Optimization in Manufacturing

This project provides an end-to-end analytical pipeline designed to optimize manufacturing operations. It addresses supply chain challenges by identifying production shortages, accounting for inventory, evaluating machine capacity, and allocating production operations to support on-time delivery.

The system is built in Julia and consists of five interconnected modules:

- **Data Module:** Cleans, preprocesses, and validates the manufacturing and inventory data.
- **Demand Module:** Calculates net production requirements and assigns priority weights to pending orders.
- **Scoring Module:** Evaluates eligible order–machine combinations and estimates risk-adjusted processing times (P50/P90).
- **Optimization Module:** Uses a Mixed-Integer Linear Programming (MILP) model with `JuMP.jl` and the `HiGHS` solver to select machine assignments, construct a production schedule, and attempt to reduce schedule lateness through replanning.
- **Evaluation Module:** Evaluates the resulting schedule using performance indicators such as makespan, on-time delivery, machine utilisation, and projected inventory.

## Getting started

<!-- DO NOT EDIT BELOW -->
Clone the repository and start Julia in the project folder:

```bash
git clone https://github.com/KLU-BADS/project-5-scientific-programming-2026.git
cd project-5-scientific-programming-2026
julia --project=.
```
<!-- DO NOT EDIT ABOVE -->
### 1. Install the required dependencies

After starting Julia with the project environment, run:

```julia
# Install the required packages
using Pkg
Pkg.instantiate()
```

This installs the dependencies specified in `Project.toml` and `Manifest.toml`. You only need to do this when setting up the environment for the first time or when the project dependencies change.

### 2. Load the project module

Run the following commands in the same Julia REPL:

```julia
# Load the Project5 module
include("src/Project5.jl")
using .Project5
```

These commands load the `Project5` module and make its exported functions available.

### 3. Run the complete production optimization pipeline

Execute:

```julia
# Run the complete pipeline
final_plan, final_schedule, evaluation_result, decision = run_project()

# Display the final machine assignments
println(final_plan)

# Display the production schedule
println(final_schedule)

# Display the evaluation results
println(evaluation_result)

#  Display the replanning decision
println(decision)
```
The pipeline runs the Data, Demand, Scoring, Optimization, and Evaluation modules. The results show the final machine assignments, production schedule, evaluation results, and replanning decision.

## Documentation

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