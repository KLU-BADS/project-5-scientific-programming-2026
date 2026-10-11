module ScoringModule

using DataFrames
using Distributions
using Statistics
using Random

export build_eligible_pairs, score_candidates

# =============================================================================
# HELPER FUNCTION
# =============================================================================

"""
    normalized_score(x::AbstractVector; higher_is_better::Bool=false) -> Vector{Float64}

Applies Min-Max normalization to scale an array of values into the range `[0.0, 1.0]`.

# Arguments
- `x`: A vector of numeric values to be normalized.
- `higher_is_better`: 
    - `false` (default): Smaller original values receive higher scores (closer to 1.0).
      Useful for metrics where lower is better (e.g., processing time, breakdown probability).
    - `true`: Larger original values receive higher scores (closer to 1.0).
      Useful for metrics where higher is better (e.g., machine efficiency).

# Returns
A vector of the same length as `x` with values scaled to `[0.0, 1.0]`.
If all values in `x` are identical, returns a vector of ones.
"""
function normalized_score(x::AbstractVector; higher_is_better::Bool=false)
    min_val = minimum(x)
    max_val = maximum(x)
    range_val = max_val - min_val

    if range_val == 0
        return ones(length(x))
    end

    if higher_is_better
        return (x .- min_val) ./ range_val
    else
        return 1.0 .- ((x .- min_val) ./ range_val)
    end
end

# =============================================================================
# MAIN FUNCTIONS
# =============================================================================

"""
    build_eligible_pairs(df::DataFrame) -> Dict

Filters out machines that are under maintenance or cannot handle the required production quantity,
then builds a dictionary that maps each order-operation combination to its list of eligible machines.

# Filtering Rules
A machine is considered eligible only if **all** of the following conditions are true:
1. `Eligible == "YES"`
2. `Machine_Status != "MAINTENANCE"`
3. The required quantity does not exceed the machine's capacity per shift
4. The total processing time (setup + cycle time × quantity) fits within the available hours of the shift

# Arguments
- `df`: Input DataFrame containing order, machine, and routing information.
  Expected columns include: `Order_ID`, `Operation_ID`, `Operation_Name`, `Sequence`,
  `Machine_ID`, `Eligible`, `Machine_Status`, `Order_Quantity` (or `Required_Production_Qty`),
  `Machine_Capacity_Units_Shift`, `Setup_time_min`, `Standard_Cycle_Time_Min_Unit`,
  `Available_Hours_Shift`.

# Returns
A `Dict` where:
- **Key**   = `(Order_ID, Operation_ID, Operation_Name, Sequence)`
- **Value** = `Vector` of eligible `Machine_ID`s

# Notes
- If the column `Required_Production_Qty` exists (produced by DemandModule), it is preferred
  over `Order_Quantity`.
- Orders that end up with zero eligible machines are reported via `@warn`.
"""
function build_eligible_pairs(df::DataFrame)
    # Prefer Required_Production_Qty if DemandModule has already filtered the data
    if hasproperty(df, :Required_Production_Qty)
        df = filter(row -> row.Required_Production_Qty > 0, df)
    end

    original_orders = unique(df.Order_ID)
    qty_col = hasproperty(df, :Required_Production_Qty) ? :Required_Production_Qty : :Order_Quantity

    df_clean = filter(
        row ->
            uppercase(strip(string(row.Eligible))) == "YES" &&
            uppercase(strip(string(row.Machine_Status))) != "MAINTENANCE" &&
            row[qty_col] <= row.Machine_Capacity_Units_Shift &&
            (row.Setup_time_min + row.Standard_Cycle_Time_Min_Unit * row[qty_col]) <= (row.Available_Hours_Shift * 60.0),
        df
    )

    my_dict = Dict()
    grouped_df = groupby(df_clean, [:Order_ID, :Operation_ID, :Operation_Name, :Sequence])

    for group in grouped_df
        route_key = (group.Order_ID[1], group.Operation_ID[1], group.Operation_Name[1], group.Sequence[1])
        machine_list = collect(group.Machine_ID)
        my_dict[route_key] = machine_list
    end

    surviving_orders = unique([k[1] for k in keys(my_dict)])
    lost = setdiff(original_orders, surviving_orders)
    if !isempty(lost)
        @warn "Orders with no eligible machine: $lost"
    end

    return my_dict
end

"""
    simulate_times(T, p, D, rng; n=10_000) -> Vector{Float64}

Performs a Monte Carlo simulation of the completion time for a single (order, machine) pair.

The simulation accounts for two sources of uncertainty:
1. **Normal process variation**: processing time is drawn from a distribution centered at `1.02 * T`
   with a small standard deviation (`0.02 * T`).
2. **Machine breakdown**: with probability `p` an additional repair time `D` is added.

# Arguments
- `T`: Total standard processing time (setup + cycle time × quantity), in minutes.
- `p`: Probability that the machine breaks down during the job.
- `D`: Duration of a breakdown (repair time), in minutes.
- `rng`: Random number generator (for reproducibility).
- `n`: Number of simulation replications (default = 10 000).

# Returns
A vector of `n` simulated completion times (in minutes).
"""
function simulate_times(T, p, D, rng; n = 10_000)
    times = zeros(n)
    for i in 1:n
        # Process variation around the nominal time
        t = T * (1.02 + 0.02 * randn(rng))

        # Possible breakdown
        if rand(rng) < p
            t += D
        end

        times[i] = t
    end
    return times
end

"""
    score_candidates(df::DataFrame, α::Real=0.7, seed::Int=42) -> DataFrame

Scores every feasible (order, machine) candidate pair and returns a richly annotated DataFrame.

# Pipeline Overview
1. Keep only orders that still require production (`Required_Production_Qty > 0`).
2. Filter machines by eligibility, capacity and available shift time.
3. Compute a risk-adjusted processing time via Monte Carlo simulation (blend of P50 and P90).
4. Normalize three performance metrics **locally** within each operation step:
   - Time (lower is better)
   - Breakdown probability (lower is better)
   - Machine efficiency (higher is better)
5. Optionally incorporate `Priority_Score` coming from DemandModule.
6. Produce a final `Candidate_Score` (higher = better) and the corresponding
   `Assignment_Penalty` (lower = better) used by the downstream optimizer.

# Arguments
- `df`: Input DataFrame that already contains order, machine and routing information.
  When DemandModule has been run, it should also contain `Required_Production_Qty`
  and optionally `Priority_Score`.
- `α`: Confidence weight between the median (P50) and the conservative percentile (P90).
  Default `0.7` means 70 % weight on the median and 30 % on the P90.
- `seed`: Random seed for reproducible Monte Carlo results.

# Returns
A DataFrame containing all original columns plus the following new columns:
- `Total_Standard_Time`, `P50_Time`, `P90_Time`, `Risk_Adjusted_Time`
- `Time_Score`, `Breakdown_Score`, `Efficiency_Score`
- `Time_Contribution`, `Breakdown_Contribution`, `Efficiency_Contribution`
  (and `Priority_Contribution` when available)
- `Candidate_Score` (higher is better)
- `Assignment_Penalty` (lower is better – used by the MILP optimizer)
"""
function score_candidates(df::DataFrame, α::Real = 0.7, seed::Int = 42)
    rng = MersenneTwister(seed)

    ROUTE_COLS     = [:Order_ID, :Operation_ID, :Operation_Name, :Sequence]
    efficiency_col = :Machine_Efficiency
    time_col       = :Risk_Adjusted_Time

    # ------------------------------------------------------------------
    # 1. Keep only orders that still need production
    # ------------------------------------------------------------------
    if hasproperty(df, :Required_Production_Qty)
        df = filter(row -> row.Required_Production_Qty > 0, df)
    end

    # ------------------------------------------------------------------
    # 2. Select quantity column and filter eligible machines
    # ------------------------------------------------------------------
    qty_col = hasproperty(df, :Required_Production_Qty) ? :Required_Production_Qty : :Order_Quantity

    df_scored = filter(
        row ->
            uppercase(strip(string(row.Eligible))) == "YES" &&
            uppercase(strip(string(row.Machine_Status))) != "MAINTENANCE" &&
            row[qty_col] <= row.Machine_Capacity_Units_Shift &&
            (row.Setup_time_min + row.Standard_Cycle_Time_Min_Unit * row[qty_col]) <= (row.Available_Hours_Shift * 60.0),
        df
    )

    # ------------------------------------------------------------------
    # 3. Nominal processing time
    # ------------------------------------------------------------------
    df_scored.Total_Standard_Time =
        df_scored.Setup_time_min .+ (df_scored.Standard_Cycle_Time_Min_Unit .* df_scored[!, qty_col])

    # ------------------------------------------------------------------
    # 4. Monte Carlo → P50 & P90
    # ------------------------------------------------------------------
    n_rows = nrow(df_scored)
    p50 = zeros(n_rows)
    p90 = zeros(n_rows)

    for i in 1:n_rows
        times = simulate_times(
            df_scored.Total_Standard_Time[i],
            df_scored.Breakdown_Probability[i],
            df_scored.Breakdown_Duration_Min[i],
            rng
        )
        p50[i] = quantile(times, 0.5)
        p90[i] = quantile(times, 0.9)
    end

    df_scored.P50_Time = round.(p50, digits = 2)
    df_scored.P90_Time = round.(p90, digits = 2)

    # Risk-adjusted time = weighted combination of median and conservative percentile
    df_scored.Weighted_Time      = α .* df_scored.P50_Time .+ (1 - α) .* df_scored.P90_Time
    df_scored.Risk_Adjusted_Time = round.(df_scored.Weighted_Time, digits = 2)

    # ------------------------------------------------------------------
    # 5. Local normalization within each operation step
    # ------------------------------------------------------------------
    for col in (:Time_Score, :Breakdown_Score, :Efficiency_Score)
        df_scored[!, col] = zeros(n_rows)
    end

    for group in groupby(df_scored, ROUTE_COLS)
        group[!, :Time_Score]       .= normalized_score(group[!, time_col])
        group[!, :Breakdown_Score]  .= normalized_score(group.Breakdown_Probability)
        group[!, :Efficiency_Score] .= normalized_score(group[!, efficiency_col]; higher_is_better = true)
    end

    # ------------------------------------------------------------------
    # 6. Weighted score (with optional Priority_Score from DemandModule)
    # ------------------------------------------------------------------
    if hasproperty(df_scored, :Priority_Score)
        # Priority_Score is assumed to be already higher-is-better
        priority_norm = normalized_score(df_scored.Priority_Score; higher_is_better = true)

        weights = (
            time       = 0.45,
            breakdown  = 0.15,
            efficiency = 0.25,
            priority   = 0.15
        )

        df_scored.Time_Contribution       = weights.time       .* df_scored.Time_Score
        df_scored.Breakdown_Contribution  = weights.breakdown  .* df_scored.Breakdown_Score
        df_scored.Efficiency_Contribution = weights.efficiency .* df_scored.Efficiency_Score
        df_scored.Priority_Contribution   = weights.priority   .* priority_norm

        df_scored.Candidate_Score =
            df_scored.Time_Contribution .+
            df_scored.Breakdown_Contribution .+
            df_scored.Efficiency_Contribution .+
            df_scored.Priority_Contribution
    else
        # Fallback weights when Priority_Score is not available
        weights = (
            time       = 0.50,
            breakdown  = 0.20,
            efficiency = 0.30
        )

        df_scored.Time_Contribution       = weights.time       .* df_scored.Time_Score
        df_scored.Breakdown_Contribution  = weights.breakdown  .* df_scored.Breakdown_Score
        df_scored.Efficiency_Contribution = weights.efficiency .* df_scored.Efficiency_Score

        df_scored.Candidate_Score =
            df_scored.Time_Contribution .+
            df_scored.Breakdown_Contribution .+
            df_scored.Efficiency_Contribution
    end

    # Lower penalty = better candidate for the optimizer
    df_scored.Assignment_Penalty = 1.0 .- df_scored.Candidate_Score

    return df_scored
end

end # module