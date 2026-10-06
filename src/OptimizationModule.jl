module OptimizationModule

using DataFrames
using Dates
using JuMP
using HiGHS
using CSV
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

function _add_work_hours(start_dt::DateTime, hours::Float64, daily_hours::Int)
    remaining = max(0.0, hours)
    current = start_dt

    while remaining > 1e-8
        day_start = DateTime(Date(current), Time(8, 0))
        day_end = day_start + Minute(daily_hours * 60)

        if current < day_start
            current = day_start
        elseif current >= day_end
            current = DateTime(Date(current) + Day(1), Time(8, 0))
            continue
        end

        available = Dates.value(day_end - current) / 3600000
        use = min(remaining, available)
        current += Minute(round(Int, use * 60))
        remaining -= use

        if remaining > 1e-8
            current = DateTime(Date(current) + Day(1), Time(8, 0))
        end
    end

    return current
end

function _schedule_once(plan::DataFrame, orders::DataFrame)
    order_info = Dict(
        string(r.Order_ID) => (
            Due_Date = r.Due_Date,
            Order_Date = r.Order_Date,
            Priority = r.Priority,
            Product_ID = r.Product_ID
        )
        for r in eachrow(orders)
    )

    # Machine availability clocks.
    planning_date = minimum(orders.Order_Date)
    machine_next = Dict(
        string(m) => DateTime(planning_date, Time(8, 0))
        for m in unique(plan.Machine_ID)
    )

    # Predecessor completion time by order.
    predecessor_finish = Dict{String, DateTime}()

    result_rows = NamedTuple[]

    for seq in sort(unique(plan.Sequence))
        layer = plan[plan.Sequence .== seq, :]
        idx = collect(1:nrow(layer))

        # Orders whose predecessor is ready earlier are considered first;
        # then priority and due date break ties.
        ready_time = [
            seq == 1 ?
            DateTime(order_info[string(layer.Order_ID[i])].Order_Date, Time(8, 0)) :
            get(predecessor_finish, string(layer.Order_ID[i]),
                DateTime(order_info[string(layer.Order_ID[i])].Order_Date, Time(8, 0)))
            for i in idx
        ]

        ord_idx = sortperm(
            idx,
            by = i -> (
                ready_time[i],
                -order_info[string(layer.Order_ID[i])].Priority,
                order_info[string(layer.Order_ID[i])].Due_Date
            )
        )

        for i in ord_idx
            r = layer[i, :]
            oid = string(r.Order_ID)
            machine = string(r.Machine_ID)

            earliest = max(
                ready_time[i],
                get(machine_next, machine, DateTime(planning_date, Time(8, 0)))
            )

            finish = _add_work_hours(
                earliest,
                r.P90_Hours,
                Int(r.Available_Hours_Shift)
            )

            machine_next[machine] = finish
            predecessor_finish[oid] = finish

            info = order_info[oid]
            due_dt = DateTime(info.Due_Date, Time(17, 0))
            lateness_h = max(0.0, Dates.value(finish - due_dt) / 3600000)

            push!(result_rows, (
                Order_ID = oid,
                Product_ID = string(r.Product_ID),
                Sequence = Int(r.Sequence),
                Operation_ID = string(r.Operation_ID),
                Operation_Name = string(r.Operation_Name),
                Machine_ID = machine,
                Machine_Type = string(r.Machine_Type),
                Quantity = Int(r.Quantity),
                Machine_Status = string(r.Machine_Status),
                Start_Time = earliest,
                Finish_Time = finish,
                Due_Date = info.Due_Date,
                Due_DateTime = due_dt,
                P50_Hours = r.P50_Hours,
                P90_Hours = r.P90_Hours,
                Score = r.Score,
                Expected_Breakdown_Hours = r.Expected_Breakdown_Hours,
                Lateness_Hours = lateness_h,
                On_Time = lateness_h <= 1e-8,
                Priority = Int(info.Priority)
            ))
        end
    end

    return DataFrame(result_rows)
end

"""
    build_schedule(plan, orders)

Build an operation-level schedule. Operations are sequenced in the order
defined by `Sequence`, while machine availability and predecessor completion
are respected.
"""
function build_schedule(plan::DataFrame, orders::DataFrame)
    isempty(plan) && error("Cannot schedule an empty plan.")
    schedule = _schedule_once(plan, orders)
    sort!(schedule, [:Order_ID, :Sequence])
    save && CSV.write("production_plan.csv", schedule)
    return schedule
end

"""
    replan_schedule(plan, candidates, orders; iterations=2)

Try local machine reassignment for late operations. A candidate swap is kept
when it reduces total schedule lateness while preserving one assignment per
order-operation.
"""
function replan_schedule(plan::DataFrame, candidates::DataFrame,
                         orders::DataFrame; iterations::Int=2)
    current_plan = copy(plan)
    current_schedule = build_schedule(current_plan, orders)

    for _ in 1:iterations
        late = current_schedule[current_schedule.Lateness_Hours .> 0, :]
        isempty(late) && break

        improved = false

        # Try the most late operations first.
        sort!(late, :Lateness_Hours, rev=true)

        for lr in eachrow(late)
            oid = string(lr.Order_ID)
            seq = Int(lr.Sequence)
            current_machine = string(lr.Machine_ID)

            alternatives = candidates[
                (string.(candidates.Order_ID) .== oid) .&
                (candidates.Sequence .== seq) .&
                (string.(candidates.Machine_ID) .!= current_machine),
                :
            ]

            isempty(alternatives) && continue

            base_total = sum(current_schedule.Lateness_Hours)
            best_total = base_total
            best_plan = nothing

            for ar in eachrow(alternatives)
                trial = copy(current_plan)
                row_idx = findfirst(
                    (string.(trial.Order_ID) .== oid) .&
                    (trial.Sequence .== seq)
                )

                row_idx === nothing && continue
                trial[row_idx, :] = ar

                sched = build_schedule(trial, orders)
                total = sum(sched.Lateness_Hours)

                if total + 1e-8 < best_total
                    best_total = total
                    best_plan = trial
                end
            end

            if best_plan !== nothing
                current_plan = best_plan
                current_schedule = build_schedule(current_plan, orders)
                current_plan.Assignment_Status = fill("Replanned", nrow(current_plan))
                improved = true
                break
            end
        end

        improved || break
    end

    return current_plan, current_schedule
    CSV.write("production_plan.csv", current_schedule)
end

end
