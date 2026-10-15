"""
    Project5

Production optimisation system: Data → Demand → Scoring → Optimisation → Evaluation.

- `run_project()` runs all five modules on `Project_Data_Final.csv`.
- `run_my_module()` runs only the Evaluation module on the small example files.
"""
module Project5

using DataFrames

# Files to be included (one file per module)

# Data module (step 1): loads the input CSV file and cleans the data.
# Renames columns, fixes data types, fills missing values and validates the result.
include("DataModule.jl")

# Demand module (step 2): calculates how much of each order still needs to be produced.
# Uses order quantity and stock levels, and gives each order a priority score.
include("Demandmodule.jl")

# Scoring module (step 3): scores every possible order-machine combination.
# Uses processing times (P50/P90), machine data and order priority.
include("ScoringModule.jl")

# Optimisation module (step 4): assigns operations to machines using a MILP model.
# Then builds and replans the final production schedule.
include("OptimizationModule.jl")

# Evaluation module (step 5): checks the schedule with warehouse and performance KPIs.
# Writes the evaluation report and decides "Adjust plan needed?" (YES = replan, NO = implement).
include("EvaluationModule.jl")

using .DataModule
using .DemandModule
using .ScoringModule
using .OptimizationModule
using .Evaluation

# Functions to be exported
export run_project, run_my_module

"""Input data file: `Project_Data_Final.csv` in the main project folder (one level above `src`)."""
const DEFAULT_DATA_FILE = joinpath(@__DIR__, "..", "Project_Data_Final.csv")

"""Folder with the example data files (in the `test` folder next to `src`)."""
const EXAMPLE_FOLDER = joinpath(@__DIR__, "..", "test")

"""Number of minutes in one hour (Scoring gives minutes, Optimisation needs hours)."""
const MINUTES_PER_HOUR = 60

"""Number of local replanning rounds in the Optimisation module."""
const REPLAN_ITERATIONS = 2

"""Maximum number of rounds through the full loop (Data -> ... -> Evaluation -> back to Data)."""
const MAX_LOOP_ROUNDS = 3

"""Name of the report file written by the Evaluation module (printed at the end of `run_project`)."""
const REPORT_FILE = "evaluation_report.txt"

"""
    run_project(data_file = DEFAULT_DATA_FILE)

Run the whole production optimisation pipeline and print the evaluation report.

# Arguments
- `data_file`: path to the input CSV file.

# Returns
- `final_plan`, `final_schedule`, `evaluation_result` and `decision` ("Adjust plan needed?").
"""
function run_project(data_file::AbstractString = DEFAULT_DATA_FILE)
    # 1. Data module: load and clean the input data
    df_clean = DataModule.load_and_clean_data(data_file)
    
    final_plan, final_schedule, evaluation_result, decision = nothing, nothing, nothing, nothing
    for round_no in 1:MAX_LOOP_ROUNDS
        println("\n----- Planning round ", round_no, " -----")
        df_clean = DataModule.apply_adjustments!(df_clean)   # use feedback from the last evaluation

    # 2. Demand module: net requirement and priority of each order
    df_demand = DemandModule.demand_analysis(df_clean)
    df_demand = DemandModule.priority_weight(df_demand)

    # 3. Scoring module: only orders that still need production (innerjoin)
    df_for_scoring = innerjoin(
        df_clean,
        df_demand[!, [:Order_ID, :Product_ID, :Required_Production_Qty, :Priority_Score]],
        on = [:Order_ID, :Product_ID]
    )
    scored = ScoringModule.score_candidates(df_for_scoring)

    # Columns the Optimisation module expects
    scored.P50_Hours                = scored.P50_Time ./ MINUTES_PER_HOUR
    scored.P90_Hours                = scored.P90_Time ./ MINUTES_PER_HOUR
    scored.Score                    = scored.Candidate_Score
    scored.Expected_Breakdown_Hours = scored.Breakdown_Probability .* scored.Breakdown_Duration_Min ./ MINUTES_PER_HOUR
    scored.Quantity                 = round.(Int, scored.Required_Production_Qty)
    scored.Assignment_Status        = fill("Candidate", nrow(scored))
    df_demand.Priority_Weight       = df_demand.Priority_Score

    # 4. Optimisation module: assigjun machines and build the schedule
    plan, objective = OptimizationModule.optimize_allocation(scored, df_demand)
    println("MILP solved. Objective value: ", round(objective, digits = 2))
    final_plan, final_schedule = OptimizationModule.replan_schedule(
        plan, scored, df_demand; iterations = REPLAN_ITERATIONS)
    println("Schedule built. Late operations: ", sum(final_schedule.Lateness_Hours .> 0))

    # 5. Evaluation module: KPIs, report and "Adjust plan needed?"
    df_eval = leftjoin(df_clean, df_demand[!, [:Order_ID, :Required_Production_Qty]], on = :Order_ID)
    df_eval.Required_Production_Qty = coalesce.(df_eval.Required_Production_Qty, 0)
    evaluation_result, decision = Evaluation.run_evaluation(df_eval, final_schedule)
            adjust_needed = decision[1]
        println("Round ", round_no, " - Adjust plan needed? ",
                adjust_needed ? "YES -> back to the Data module" : "NO -> implement")
        adjust_needed || break      # NO  -> stop the loop
    end                             # YES -> next round starts again at the Data module
    
    # 6. Print the evaluation report in the terminal
    if isfile(REPORT_FILE)
        println("\n========== EVALUATION REPORT ==========")
        print(read(REPORT_FILE, String))
        println("=======================================")
    else
        println("Report file not found: ", REPORT_FILE)
    end

    return final_plan, final_schedule, evaluation_result, decision
end

"""
    run_my_module()

Run only the Evaluation module with the example files
`cleaned_data_test.csv` and `production_plan_test.csv`.
"""
function run_my_module()
    cleaned_data = joinpath(EXAMPLE_FOLDER, "cleaned_data_test.csv")
    schedule     = joinpath(EXAMPLE_FOLDER, "production_plan_test.csv")
    return Evaluation.run_evaluation(cleaned_data, schedule)
end

end # module Project5