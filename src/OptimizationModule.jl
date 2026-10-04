module OptimizationModule

using DataFrames
using Dates
using JuMP
using HiGHS
import MathOptInterface as MOI

export optimize_allocation, build_schedule, replan_schedule

"""
    optimize_allocation(candidates, orders)

Select exactly one eligible machine for every order-operation using a MILP.
The objective rewards high candidate scores, lower P90 processing time,
lower breakdown risk, and higher priority.
"""
function optimize_allocation(candidates::DataFrame, orders::DataFrame)
    n = nrow(candidates)
    model = Model(HiGHS.Optimizer)
    set_silent(model)

    @variable(model, x[1:n], Bin)

    # Exactly one machine for each order-operation.
    for g in groupby(candidates, [:Order_ID, :Sequence])
        idx = parentindices(g)[1]
        @constraint(model, sum(x[i] for i in idx) == 1)
    end

    # Aggregate machine capacity over the planning horizon.
    horizon_days = max(
        1,
        Dates.value(maximum(orders.Due_Date) - minimum(orders.Order_Date)) + 1
    )

    for machine in unique(candidates.Machine_ID)
        idx = findall(candidates.Machine_ID .== machine)
        hours = maximum(candidates.Available_Hours_Shift[idx])
        capacity = hours * horizon_days

        @constraint(
            model,
            sum(candidates.P90_Hours[i] * x[i] for i in idx) <= capacity
        )
    end

    priority_map = Dict(string(r.Order_ID) => Float64(r.Priority_Weight)
                        for r in eachrow(orders))

    objective_terms = Float64[]
    for i in 1:n
        oid = string(candidates.Order_ID[i])
        priority = get(priority_map, oid, 1.0)

        # Larger score is better; P90 and risk are minimized.
        value = (
            1.00 * candidates.Score[i] +
            8.0 * priority -
            4.0 * candidates.P90_Hours[i] -
            2.0 * candidates.Expected_Breakdown_Hours[i]
        )
        push!(objective_terms, value)
    end

    @objective(model, Max, sum(objective_terms[i] * x[i] for i in 1:n))

    optimize!(model)

    status = termination_status(model)
    status == MOI.OPTIMAL || status == MOI.FEASIBLE ||
        error("Optimization failed. Solver status: $status")

    selected = findall(i -> value(x[i]) > 0.5, 1:n)
    plan = candidates[selected, :]

    plan.Assignment_Status = fill("Optimized", nrow(plan))
    sort!(plan, [:Sequence, :Order_ID])

    return plan, objective_value(model)
end