# Production_Optimisation.jl 
<!-- DO NOT EDIT BELOW -->
[![Tests](../../actions/workflows/tests.yml/badge.svg)](../../actions/workflows/tests.yml)
[![Documentation](../../actions/workflows/docs.yml/badge.svg)](../../actions/workflows/docs.yml)
<!-- DO NOT EDIT ABOVE -->


## Overview

<!-- DESCRIBE PROJECT PURPOSE BELOW -->
**Title:** Demand–Production Gap Analysis and Capacity Optimization in Manufacturing

This project provides an end-to-end analytical pipeline designed to optimize manufacturing operations. It addresses critical supply chain challenges by identifying production shortages, mitigating excess inventory, uncovering machine bottlenecks, and intelligently reallocating production capacity to ensure on-time delivery.

The system is built entirely in Julia and is composed of five automated, interconnected modules:
*   **Data Module:** Cleans, preprocesses, and structures raw manufacturing and inventory data.
*   **Demand Module:** Analyzes net requirements and assigns priority weights to pending orders based on urgency.
*   **Scoring Module:** Evaluates machine-order compatibility and estimates risk-adjusted processing times (P50/P90 probabilities).
*   **Optimization Module:** Formulates and solves a Mixed-Integer Linear Programming (MILP) model using `JuMP.jl` and the `HiGHS` solver to minimize tardiness and optimize machine allocation.
*   **Evaluation Module:** Simulates the generated schedule to report Key Performance Indicators (KPIs) including makespan, on-time delivery rates, machine utilization, and projected inventory stockouts.
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
Once the package is cloned and the environment is set up, you can run the full production optimization pipeline with a single command.
Open the Julia REPL in the project folder and run:
```julia
# Execute the complete pipeline: Data → Demand → Scoring → Optimization → Evaluation
final_plan, final_schedule, evaluation_result, decision = Project5.run_project("Project_Data_Final.csv")
```
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

