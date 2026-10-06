# EVALUATION MODULE — Warehouse & Performance Evaluation + "Adjust plan needed?"
# Run: julia EvaluationModule.jl cleaned_data.csv production_plan.csv

module Evaluation

using Dates, Printf

export load_data, load_plan, evaluate, adjust_needed, print_report

# ── Settings — must match the Optimisation module's calendar ─────────────────
const SHIFTS_PER_DAY = 1          # optimisation: one shift per day ...
const SHIFT_START    = 8          # ... starting 08:00, lasting Available_Hours_Shift
const WORK_WEEKENDS  = true       # optimisation schedules every day
const DUE_HOUR       = 17         # optimisation: due at 17:00 on the due date
const TARGET_ON_TIME = 0.90       # adjust plan if fewer than 90 % on time
const MAX_UTIL       = 0.95       # adjust plan if a machine is above 95 %

# Column names of start / finish times in the optimisation output
const START_COL  = "Start_Time"
const FINISH_COL = "Finish_Time"

# Dates: ISO "2026-10-02" (CSV.jl) or "02-Oct-2026" (original sheet)
parse_date(s) = occursin(r"^\d{4}-", s) ? Date(s[1:10]) : Date(s, dateformat"dd-u-yyyy")
# Times: ISO "2026-10-05T08:00:00" (CSV.jl) or "2026-10-05 08:00"
parse_time(s) = DateTime(replace(s, ' ' => 'T'))

# ── Read a CSV into a vector of Dicts (column name → value) ──────────────────
function read_csv(path)
    lines = readlines(path)
    header = strip.(split(lstrip(lines[1], '\ufeff'), ","))
    [Dict(String(header[i]) => String(strip(v[i])) for i in eachindex(header))
     for v in (split(l, ",") for l in lines[2:end] if !isempty(strip(l)))]
end

hours(p::Period) = Dates.value(Millisecond(p)) / 3_600_000   # time difference → hours

# ── 1. Load inputs ───────────────────────────────────────────────────────────
function load_data(path)
    orders, stock, machine_hours = Dict(), Dict(), Dict{String,Float64}()
    last_op = Dict{String,Tuple{Int,String}}()           # order → (Sequence, Operation_ID) of last operation
    for r in read_csv(path)
        seq = (parse(Int, r["Sequence"]), r["Operation_ID"])
        last_op[r["Order_ID"]] = max(get(last_op, r["Order_ID"], seq), seq)
        orders[r["Order_ID"]] = (product = r["Product_ID"],
                                 qty     = parse(Int, r["Order_Quantity"]),
                                 due     = parse_date(r["Due_Date"]))
        stock[r["Product_ID"]] = (current  = parse(Int, r["Current_Stock"]),
                                  reserved = parse(Int, r["Reserved_Stock"]),
                                  safety   = parse(Int, r["Safety_Stock"]))
        machine_hours[r["Machine_ID"]] = parse(Float64, r["Available_Hours_Shift"])
    end
    orders, stock, machine_hours, Dict(o => op for (o, (_, op)) in last_op)
end

function load_plan(path)
    [(order   = r["Order_ID"],
      op      = r["Operation_ID"],
      machine = r["Machine_ID"],
      qty     = parse(Int, r["Quantity"]),
      start   = parse_time(r[START_COL]),
      finish  = parse_time(r[FINISH_COL])) for r in read_csv(path)]
end

# ── Working shift hours of a machine (h hours per shift) between times a and b ─
function shift_hours(a, b, h)
    total = 0.0
    for d in (Date(a) - Day(1)):Day(1):Date(b)
        (WORK_WEEKENDS || dayofweek(d) <= 5) || continue
        for k in 0:SHIFTS_PER_DAY-1
            s = DateTime(d) + Hour(SHIFT_START + 8k)   # shift k of day d
            e = s + Minute(round(Int, 60h))
            lo, hi = max(s, a), min(e, b)
            hi > lo && (total += hours(hi - lo))
        end
    end
    total
end

# ── 2. Evaluate the plan ─────────────────────────────────────────────────────
function evaluate(plan, orders, stock, machine_hours, last_op)
    # Tardiness: order completion = finish of the last lot of its FINAL operation
    completion = Dict{String,DateTime}()
    for j in plan
        j.op == get(last_op, j.order, "") || continue
        completion[j.order] = max(get(completion, j.order, j.finish), j.finish)
    end
    tardiness = Dict{String,Float64}()
    for (id, o) in orders
        haskey(completion, id) || continue
        due_end = DateTime(o.due) + Hour(DUE_HOUR)             # same due time as optimisation
        tardiness[id] = max(0.0, hours(completion[id] - due_end))
    end
    late      = count(>(0), values(tardiness))
    unplanned = length(orders) - length(tardiness)

    # Quantity check: produced = units through the order's LAST operation (split lots summed).
    # An order only counts as on time if it is finished by the due time AND fully produced.
    produced = Dict{String,Int}()
    for j in plan
        j.op == get(last_op, j.order, "") || continue
        produced[j.order] = get(produced, j.order, 0) + j.qty
    end
    complete(id) = get(produced, id, 0) >= orders[id].qty
    short   = count(id -> !complete(id), keys(tardiness))
    on_time = count(id -> tardiness[id] == 0 && complete(id), keys(tardiness)) / length(orders)

    # Makespan
    t0 = minimum(j.start for j in plan); t1 = maximum(j.finish for j in plan)
    makespan = hours(t1 - t0)

    # Machine utilisation = busy shift hours / available shift hours
    util = Dict{String,Float64}()
    for (m, h) in machine_hours
        busy  = sum((shift_hours(j.start, j.finish, h) for j in plan if j.machine == m); init = 0.0)
        avail = shift_hours(t0, t1, h)
        util[m] = avail > 0 ? busy / avail : 0.0
    end

    # Projected inventory: available = current − reserved − safety,
    # + produced on completion date, − order quantity shipped on max(due, completion)
    inventory = Dict{String,NamedTuple}()
    for (p, s) in stock
        events = Tuple{Date,Int}[]
        for (id, o) in orders
            o.product == p || continue
            if haskey(completion, id)
                push!(events, (Date(completion[id]), get(produced, id, 0)))
                push!(events, (max(o.due, Date(completion[id])), -o.qty))
            else
                push!(events, (o.due, -o.qty))                   # unplanned: from stock
            end
        end
        start = s.current - s.reserved - s.safety
        level = lowest = start
        for (_, change) in sort(events, by = e -> (e[1], -e[2]))   # by date, production first
            level += change
            lowest = min(lowest, level)
        end
        status = lowest < -s.safety ? "STOCKOUT" : lowest < 0 ? "BELOW SAFETY" : "OK"
        inventory[p] = (start = start, final = level, lowest = lowest, status = status)
    end

    (on_time = on_time, late = late, unplanned = unplanned, short = short,
     total_tardiness = sum(values(tardiness); init = 0.0),
     max_tardiness = maximum(values(tardiness); init = 0.0),
     makespan = makespan, start = t0, finish = t1,
     utilisation = util, inventory = inventory, tardiness = tardiness)
end

# ── 3. Decision: "Adjust plan needed?" ───────────────────────────────────────
function adjust_needed(res)
    reasons = String[]
    res.on_time < TARGET_ON_TIME &&
        push!(reasons, @sprintf("on-time rate %.1f%% is below %.0f%%", 100res.on_time, 100TARGET_ON_TIME))
    for (m, u) in sort(collect(res.utilisation))
        u > MAX_UTIL && push!(reasons, @sprintf("%s is a bottleneck (%.1f%% utilised)", m, 100u))
    end
    for (p, inv) in sort(collect(res.inventory))
        inv.status == "STOCKOUT" && push!(reasons, "$p runs out of stock")
    end
    res.unplanned > 0 && push!(reasons, "$(res.unplanned) order(s) are not in the plan")
    res.short > 0 && push!(reasons, "$(res.short) order(s) are planned with less than the ordered quantity")
    (!isempty(reasons), reasons)
end

# ── 4. Report ────────────────────────────────────────────────────────────────
function print_report(res)
    println("="^60, "\n  WAREHOUSE & PERFORMANCE EVALUATION\n", "="^60)
    println("Plan: ", res.start, "  →  ", res.finish, "\n")
    @printf("Makespan           %8.1f h (%.1f days)\n", res.makespan, res.makespan / 24)
    @printf("On-time delivery   %8.1f %%  (%d late, %d unplanned, %d short)\n", 100res.on_time, res.late, res.unplanned, res.short)
    @printf("Total tardiness    %8.1f h\n", res.total_tardiness)
    @printf("Max tardiness      %8.1f h\n", res.max_tardiness)
    println("\nMachine utilisation")
    for (m, u) in sort(collect(res.utilisation))
        @printf("  %-4s %6.1f %%\n", m, 100u)
    end
    println("\nProjected inventory (available = current − reserved − safety)")
    for (p, inv) in sort(collect(res.inventory))
        @printf("  %-5s start %6d  final %6d  lowest %6d  %s\n", p, inv.start, inv.final, inv.lowest, inv.status)
    end
    needed, reasons = adjust_needed(res)
    println("\nAdjust plan needed?  ", needed ? "YES → Replan / Adjust" : "NO → Implement & Monitor")
    foreach(r -> println("  • ", r), reasons)
end

end # module

# ── Run from the command line ────────────────────────────────────────────────
if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) < 2
        println("Usage: julia EvaluationModule.jl cleaned_data.csv production_plan.csv")
        exit(1)
    end
    orders, stock, machine_hours, last_op = Evaluation.load_data(ARGS[1])
    plan = Evaluation.load_plan(ARGS[2])
    res  = Evaluation.evaluate(plan, orders, stock, machine_hours, last_op)
    Evaluation.print_report(res)
end