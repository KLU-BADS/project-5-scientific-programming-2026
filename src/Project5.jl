"""
    Project5

A minimal Julia package to start a project from.
"""
module Project5

# Files to be included
include("hello.jl")
include("EvaluationModule.jl")

using .Evaluation

# Functions to be exported
export hello, run_my_module

"""Folder with the example data files (in the `test` folder next to `src`)."""
const EXAMPLE_FOLDER = joinpath(@__DIR__, "..", "test")

"""
    run_my_module()

Run the Evaluation module with the example files
`cleaned_data_test.csv` and `production_plan_test.csv`.
"""
function run_my_module()
    cleaned_data = joinpath(EXAMPLE_FOLDER, "cleaned_data_test.csv")
    schedule     = joinpath(EXAMPLE_FOLDER, "production_plan_test.csv")
    return Evaluation.run_evaluation(cleaned_data, schedule)
end

end # module Project5