"""
EVALUATION MODULE — Warehouse & Performance Evaluation + "Adjust plan needed?"

Checks the production plan from the Optimisation module and decides whether it
is good enough or needs to be adjusted.

Inputs (passed directly as tables, or as CSV files for testing):
- cleaned data from the Data module: orders, stock and machine data
- schedule from the Optimisation module: order, operation, machine, quantity,
  start and finish time

Calculates: on-time rate, tardiness, makespan, machine utilisation and projected inventory.

Decision — "Adjust plan needed?":
- Yes → replan: fewer than 90 % of orders on time, a machine above 95 % utilisation,
  a product out of stock, or orders missing or short.
- No  → no replan needed: the plan is ready to implement.

Use from another module:
    results, decision = Evaluation.run_evaluation(cleaned_data, schedule)

Run from the command line (testing with files):
    julia EvaluationModule.jl cleaned_data.csv production_plan.csv
"""
module Evaluation

using Dates, Printf

export run_evaluation, load_data, load_plan, evaluate, check_adjust_needed, print_report

# ── Settings — must match the Optimisation module's calendar ─────────────────
"""Number of shifts per day (one shift, same as optimisation)."""
const SHIFTS_PER_DAY = 1
"""Shift start hour (08:00). Each shift lasts Available_Hours_Shift hours."""
const SHIFT_START = 8
"""Hours between the start of one shift and the next (used when SHIFTS_PER_DAY > 1)."""
const SHIFT_LENGTH_HOURS = 8
"""Whether weekends are working days (true = every day)."""
const WORK_WEEKENDS = true
"""Hour on the due date by which an order must be finished (17:00)."""
const DUE_HOUR = 17
"""Target on-time rate (90 %). Below this → replan needed."""
const TARGET_ON_TIME = 0.90
"""Maximum machine utilisation (95 %). Above this → replan needed."""
const MAX_UTIL = 0.95
"""Column name of the start time in the optimisation output."""
const START_COL = "Start_Time"
"""Column name of the finish time in the optimisation output."""
const FINISH_COL = "Finish_Time"

# ── Units and fixed values ───────────────────────────────────────────────────
"""Number of milliseconds in one hour."""
const MS_PER_HOUR = 3_600_000
"""Number of minutes in one hour."""
const MINUTES_PER_HOUR = 60
"""Number of hours in one day."""
const HOURS_PER_DAY = 24
"""Factor to turn a share (0.9) into a percentage (90)."""
const PERCENT = 100
"""Number of characters in an ISO date such as "2026-10-02"."""
const ISO_DATE_LENGTH = 10
"""Invisible marker that Excel sometimes adds at the start of a CSV file."""
const BYTE_ORDER_MARK = '﻿'
"""Width of the separator line in the printed report."""
const REPORT_WIDTH = 60
"""Inventory status: stock falls below the reserved amount."""
const STATUS_STOCKOUT = "STOCKOUT"
"""Inventory status: stock falls below the safety stock."""
const STATUS_BELOW_SAFETY = "BELOW SAFETY"
"""Inventory status: stock stays above the safety stock."""
const STATUS_OK = "OK"

# ── Small helpers ────────────────────────────────────────────────────────────
"""Convert a date text ("2026-10-02" or "02-Oct-2026") into a Date."""
function parse_date(date_text)
    is_iso = occursin(r"^\d{4}-", date_text)
    is_iso ? Date(date_text[1:ISO_DATE_LENGTH]) : Date(date_text, dateformat"dd-u-yyyy")
end

"""Convert a time text ("2026-10-05T08:00:00" or "2026-10-05 08:00") into a DateTime."""
parse_time(time_text) = DateTime(replace(time_text, ' ' => 'T'))

"""Convert a time difference (Period) into hours."""
to_hours(period::Period) = Dates.value(Millisecond(period)) / MS_PER_HOUR

"""Convert a share (for example 0.9) into a percentage (90)."""
to_percent(share) = PERCENT * share

"""Read one column from a CSV row (a Dict) or from a table row of another module."""
column_value(row::AbstractDict, column::Symbol) = row[String(column)]
column_value(row, column::Symbol) = getproperty(row, column)

"""Turn a number or a text into a number of type `T` (Int or Float64)."""
to_number(T, value) = value isa Number ? T(value) : parse(T, string(value))

"""Turn a Date (from the Data module) or a date text (from a CSV file) into a Date."""
to_date(value) = value isa Date ? value : parse_date(string(value))

"""Turn a DateTime (from the Optimisation module) or a time text (from a CSV file) into a DateTime."""
to_time(value) = value isa DateTime ? value : parse_time(string(value))

"""The rows of a table from another module, or of a CSV file when `source` is a path."""
rows_of(source) = source isa AbstractString ? read_csv(source) : eachrow(source)

# ── 1. Load inputs ───────────────────────────────────────────────────────────
"""Read a CSV file into a list of rows (one Dict per row: column name → text). Empty lines are skipped."""
function read_csv(path)
    lines = readlines(path)
    header = strip.(split(lstrip(lines[1], BYTE_ORDER_MARK), ","))
    [Dict(String(header[i]) => String(strip(fields[i])) for i in eachindex(header))
     for fields in (split(line, ",") for line in lines[2:end] if !isempty(strip(line)))]
end

"""
    load_data(source) -> (orders, stock, machine_hours, last_op)

Load the cleaned data.

# Arguments
- `source`: the cleaned table from the Data module, or the path to a CSV file.

# Returns
- `orders`: product, quantity and due date for each order.
- `stock`: current, reserved and safety stock for each product.
- `machine_hours`: available hours per shift for each machine.
- `last_op`: the last operation of each order.
"""
function load_data(source)
    orders, stock, machine_hours = Dict(), Dict(), Dict{String,Float64}()
    last_op = Dict{String,Tuple{Int,String}}()   # order → (Sequence, Operation_ID) of last operation
    for row in rows_of(source)
        order_id   = string(column_value(row, :Order_ID))
        product_id = string(column_value(row, :Product_ID))
        sequence   = (to_number(Int, column_value(row, :Sequence)), string(column_value(row, :Operation_ID)))
        last_op[order_id] = max(get(last_op, order_id, sequence), sequence)
        orders[order_id] = (product = product_id,
                            qty     = to_number(Int, column_value(row, :Order_Quantity)),
                            due     = to_date(column_value(row, :Due_Date)))
        stock[product_id] = (current  = to_number(Int, column_value(row, :Current_Stock)),
                             reserved = to_number(Int, column_value(row, :Reserved_Stock)),
                             safety   = to_number(Int, column_value(row, :Safety_Stock)))
        machine_hours[string(column_value(row, :Machine_ID))] =
            to_number(Float64, column_value(row, :Available_Hours_Shift))
    end
    orders, stock, machine_hours, Dict(order_id => operation for (order_id, (_, operation)) in last_op)
end

"""
    load_plan(source) -> Vector{NamedTuple}

Load the production plan (schedule) from the Optimisation module.

# Arguments
- `source`: the schedule table from the Optimisation module, or the path to a CSV file (testing).

# Returns
- One entry per job with order, operation, machine, quantity, start and finish time.
"""
load_plan(source) = [(order   = string(column_value(row, :Order_ID)),
                      op      = string(column_value(row, :Operation_ID)),
                      machine = string(column_value(row, :Machine_ID)),
                      qty     = to_number(Int, column_value(row, :Quantity)),
                      start   = to_time(column_value(row, Symbol(START_COL))),
                      finish  = to_time(column_value(row, Symbol(FINISH_COL)))) for row in rows_of(source)]

# ── 2. Evaluate the plan ─────────────────────────────────────────────────────
"""Count the working shift hours between `start_time` and `end_time` for a machine with `hours_per_shift`."""
function compute_shift_hours(start_time, end_time, hours_per_shift)
    total = 0.0
    for day in (Date(start_time) - Day(1)):Day(1):Date(end_time)
        (WORK_WEEKENDS || dayofweek(day) <= Dates.Friday) || continue
        for k in 0:SHIFTS_PER_DAY-1
            shift_begin = DateTime(day) + Hour(SHIFT_START + SHIFT_LENGTH_HOURS * k)   # shift k of this day
            shift_end   = shift_begin + Minute(round(Int, MINUTES_PER_HOUR * hours_per_shift))
            overlap_start, overlap_end = max(shift_begin, start_time), min(shift_end, end_time)
            overlap_end > overlap_start && (total += to_hours(overlap_end - overlap_start))
        end
    end
    total
end

"""True if `job` is the last production step of its order."""
is_final_operation(job, last_op) = job.op == get(last_op, job.order, "")

"""Completion time of each order = finish of the last lot of its final operation."""
function compute_completion(plan, last_op)
    completion = Dict{String,DateTime}()
    for job in plan
        is_final_operation(job, last_op) || continue
        completion[job.order] = max(get(completion, job.order, job.finish), job.finish)
    end
    completion
end

"""Hours each planned order finishes after its due time (0 if on time)."""
function compute_tardiness(orders, completion)
    tardiness = Dict{String,Float64}()
    for (order_id, order) in orders
        haskey(completion, order_id) || continue
        due_end = DateTime(order.due) + Hour(DUE_HOUR)          # same due time as optimisation
        tardiness[order_id] = max(0.0, to_hours(completion[order_id] - due_end))
    end
    tardiness
end

"""Units produced per order, counted at its final operation (split lots summed)."""
function compute_produced(plan, last_op)
    produced = Dict{String,Int}()
    for job in plan
        is_final_operation(job, last_op) || continue
        produced[job.order] = get(produced, job.order, 0) + job.qty
    end
    produced
end

"""On-time rate and counts of late, unplanned and short orders (on time = finished by the due time AND fully produced)."""
function compute_delivery(orders, tardiness, produced)
    is_complete(order_id) = get(produced, order_id, 0) >= orders[order_id].qty
    on_time_count = count(order_id -> tardiness[order_id] == 0 && is_complete(order_id), keys(tardiness))
    (on_time   = on_time_count / length(orders),
     late      = count(>(0), values(tardiness)),
     unplanned = length(orders) - length(tardiness),
     short     = count(order_id -> !is_complete(order_id), keys(tardiness)))
end

"""Machine utilisation = busy shift hours / available shift hours."""
function compute_utilisation(plan, machine_hours, plan_start, plan_finish)
    utilisation = Dict{String,Float64}()
    for (machine, hours_per_shift) in machine_hours
        busy_hours = sum((compute_shift_hours(job.start, job.finish, hours_per_shift)
                          for job in plan if job.machine == machine); init = 0.0)
        available_hours = compute_shift_hours(plan_start, plan_finish, hours_per_shift)
        utilisation[machine] = available_hours > 0 ? busy_hours / available_hours : 0.0
    end
    utilisation
end

"""Stock changes for one product: + produced on the completion date, − ordered quantity shipped on max(due, completion)."""
function stock_events(product, orders, completion, produced)
    events = Tuple{Date,Int}[]
    for (order_id, order) in orders
        order.product == product || continue
        if haskey(completion, order_id)
            finished_on = Date(completion[order_id])
            push!(events, (finished_on, get(produced, order_id, 0)))
            push!(events, (max(order.due, finished_on), -order.qty))
        else
            push!(events, (order.due, -order.qty))              # unplanned: shipped from stock
        end
    end
    events
end

"""Projected stock per product (available = current − reserved − safety): start, final and lowest level and a status."""
function project_inventory(stock, orders, completion, produced)
    inventory = Dict{String,NamedTuple}()
    for (product, product_stock) in stock
        start_level = product_stock.current - product_stock.reserved - product_stock.safety
        level = lowest = start_level
        events = stock_events(product, orders, completion, produced)
        for (_, change) in sort(events, by = event -> (event[1], -event[2]))   # by date, production first
            level += change
            lowest = min(lowest, level)
        end
        status = lowest < -product_stock.safety ? STATUS_STOCKOUT : (lowest < 0 ? STATUS_BELOW_SAFETY : STATUS_OK)
        inventory[product] = (start = start_level, final = level, lowest = lowest, status = status)
    end
    inventory
end

"""
    evaluate(plan, orders, stock, machine_hours, last_op) -> NamedTuple

Calculate all KPIs of a production plan.

# Arguments
- `plan`: jobs from `load_plan`.
- `orders`, `stock`, `machine_hours`, `last_op`: results of `load_data`.

# Returns
- On-time rate, late / unplanned / short counts, tardiness, makespan,
  machine utilisation and projected inventory.
"""
function evaluate(plan, orders, stock, machine_hours, last_op)
    completion  = compute_completion(plan, last_op)
    tardiness   = compute_tardiness(orders, completion)
    produced    = compute_produced(plan, last_op)
    delivery    = compute_delivery(orders, tardiness, produced)
    plan_start  = minimum(job.start for job in plan)
    plan_finish = maximum(job.finish for job in plan)
    (on_time = delivery.on_time, late = delivery.late, unplanned = delivery.unplanned, short = delivery.short,
     total_tardiness = sum(values(tardiness); init = 0.0),
     max_tardiness   = maximum(values(tardiness); init = 0.0),
     makespan = to_hours(plan_finish - plan_start), start = plan_start, finish = plan_finish,
     utilisation = compute_utilisation(plan, machine_hours, plan_start, plan_finish),
     inventory   = project_inventory(stock, orders, completion, produced),
     tardiness   = tardiness)
end

# ── 3. Decision: "Adjust plan needed?" ───────────────────────────────────────
"""
    check_adjust_needed(results) -> (Bool, Vector{String})

Decide "Adjust plan needed?" from the KPIs of `evaluate`.

# Returns
- `true` and the reasons when a replan is needed; `false` and no reasons when the plan is ready.
"""
function check_adjust_needed(results)
    reasons = String[]
    results.on_time < TARGET_ON_TIME && push!(reasons,
        @sprintf("on-time rate %.1f%% is below %.0f%%", to_percent(results.on_time), to_percent(TARGET_ON_TIME)))
    for (machine, utilisation) in sort(collect(results.utilisation))
        utilisation > MAX_UTIL && push!(reasons,
            @sprintf("%s is a bottleneck (%.1f%% utilised)", machine, to_percent(utilisation)))
    end
    for (product, product_inventory) in sort(collect(results.inventory))
        product_inventory.status == STATUS_STOCKOUT && push!(reasons, "$product runs out of stock")
    end
    results.unplanned > 0 && push!(reasons, "$(results.unplanned) order(s) are not in the plan")
    results.short > 0 && push!(reasons, "$(results.short) order(s) are planned with less than the ordered quantity")
    (!isempty(reasons), reasons)
end

# ── 4. Report ────────────────────────────────────────────────────────────────
"""Print the evaluation report: KPIs, machine utilisation, projected inventory and the decision."""
function print_report(results; decision = check_adjust_needed(results))
    println("="^REPORT_WIDTH, "\n  WAREHOUSE & PERFORMANCE EVALUATION\n", "="^REPORT_WIDTH)
    println("Plan: ", results.start, "  →  ", results.finish, "\n")
    @printf("Makespan           %8.1f h (%.1f days)\n", results.makespan, results.makespan / HOURS_PER_DAY)
    @printf("On-time delivery   %8.1f %%  (%d late, %d unplanned, %d short)\n",
            to_percent(results.on_time), results.late, results.unplanned, results.short)
    @printf("Total tardiness    %8.1f h\n", results.total_tardiness)
    @printf("Max tardiness      %8.1f h\n", results.max_tardiness)
    println("\nMachine utilisation")
    for (machine, utilisation) in sort(collect(results.utilisation))
        @printf("  %-4s %6.1f %%\n", machine, to_percent(utilisation))
    end
    println("\nProjected inventory (available = current − reserved − safety)")
    for (product, level) in sort(collect(results.inventory))
        @printf("  %-5s start %6d  final %6d  lowest %6d  %s\n", product, level.start, level.final, level.lowest, level.status)
    end
    is_adjust_needed, reasons = decision
    println("\nAdjust plan needed?  ", is_adjust_needed ? "YES → Replan / Adjust" : "NO → Implement & Monitor")
    foreach(reason -> println("  • ", reason), reasons)
end

# ── 5. Run everything ────────────────────────────────────────────────────────
"""
    run_evaluation(cleaned_data, schedule) -> (results, decision)

Load the inputs, calculate the KPIs, decide "Adjust plan needed?" and print the report.

# Arguments
- `cleaned_data`: the cleaned table from the Data module (or a CSV path for testing).
- `schedule`: the schedule table from the Optimisation module (or a CSV path for testing).
"""
function run_evaluation(cleaned_data, schedule)
    orders, stock, machine_hours, last_op = load_data(cleaned_data)
    results  = evaluate(load_plan(schedule), orders, stock, machine_hours, last_op)
    decision = check_adjust_needed(results)
    print_report(results; decision = decision)
    return results, decision
end

end # module

# ── Run from the command line ────────────────────────────────────────────────
if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) < 2 && (println("Usage: julia EvaluationModule.jl cleaned_data.csv production_plan.csv"); exit(1))
    Evaluation.run_evaluation(ARGS[1], ARGS[2])
end