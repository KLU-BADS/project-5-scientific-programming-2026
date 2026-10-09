module Project5

include("DataModule.jl")
include("DemandModule.jl")
include("ScoringModule.jl")
include("OptimizationModule.jl")
include("EvaluationModule.jl")

using .DataModule
using .DemandModule
using .ScoringModule
using .OptimizationModule
using .Evaluation

export run_project

"""
    run_project(input_file; output_dir="output", nsim=500)

Run the complete manufacturing order-to-machine allocation workflow.
"""
function run_project(input_file::AbstractString; output_dir::AbstractString="output",
                     nsim::Int=500)
    println("\n=== PROJECT5: MANUFACTURING OPTIMIZATION ===")

    println("\n[1/9] Loading and cleaning data...")
    df = DataModule.load_and_clean_data(input_file)
    println("Loaded $(nrow(df)) candidate rows.")

    println("\n[2/9] Demand and inventory analysis...")
    orders = DemandModule.demand_analysis(df)
    println("Prepared $(nrow(orders)) orders.")

    println("\n[3/9] Building eligible order-operation-machine pairs...")
    candidates = ScoringModule.build_eligible_pairs(df, orders)
    println("Found $(nrow(candidates)) feasible candidates.")

    println("\n[4/9] Monte Carlo scoring...")
    candidates = ScoringModule.score_candidates(candidates, orders; nsim=nsim)
    println("Scored all candidates.")

    println("\n[5/9] MILP optimization...")
    plan, objective = OptimizationModule.optimize_allocation(candidates, orders)
    println("Selected $(nrow(plan)) assignments.")
    println("Optimization objective: $(round(objective, digits=2))")

    println("\n[6/9] Building production schedule...")
    schedule = OptimizationModule.build_schedule(plan, orders)

    println("\n[7/9] Replanning...")
    plan, schedule = OptimizationModule.replan_schedule(
        plan, candidates, orders; iterations=2
    )

    println("\n[8/9] Evaluating...")
    kpis = EvaluationModule.evaluate_plan(schedule, orders, candidates)

    println("\n[9/9] Exporting results...")
    EvaluationModule.export_results(schedule, kpis, output_dir)
    EvaluationModule.make_charts(schedule, kpis.machine_kpis, output_dir)

    println("\n=== SUMMARY ===")
    println(kpis.summary)
    println("\nResults written to: $output_dir")

    return (
        raw = df,
        orders = orders,
        candidates = candidates,
        plan = plan,
        schedule = schedule,
        kpis = kpis
    )
end

end
