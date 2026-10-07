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
normalized_score(x; higher_is_better=false)
Applies Min-Max normalization to scale values into the range [0.0, 1.0].
- If `higher_is_better = false` (default): smaller values receive higher scores (closer to 1.0).
- If `higher_is_better = true`: larger values receive higher scores (closer to 1.0).
- If all values are identical, returns a vector of ones.
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
    build_eligible_pairs(df::DataFrame)

Filters out machines that are under maintenance or cannot handle the required quantity,
then creates a dictionary mapping each (Order_ID, Operation) to its list of eligible Machine_IDs.

Returns:
- A Dict with keys = (Order_ID, Operation_ID, Operation_Name, Sequence)
- Values = Vector of eligible Machine_IDs
"""
function build_eligible_pairs(df::DataFrame)
    # Only keep orders that still need to be produced (filtered by DemandModule).
    if hasproperty(df, :Required_Production_Qty)
        df = filter(row -> row.Required_Production_Qty > 0, df)
    end

    # Keep track of original orders to detect those with no eligible machines
    original_orders = unique(df.Order_ID)

    # Decide which quantity column to use
    qty_col = hasproperty(df, :Required_Production_Qty) ? :Required_Production_Qty : :Order_Quantity

    # Filter machines that are eligible and have enough capacity/time
    df_clean = filter(
        row ->
            uppercase(strip(string(row.Eligible))) == "YES" &&
            uppercase(strip(string(row.Machine_Status))) != "MAINTENANCE" &&
            row[qty_col] <= row.Machine_Capacity_Units_Shift &&  
            (row.Setup_time_min + row.Standard_Cycle_Time_Min_Unit * row[qty_col]) <= (row.Available_Hours_Shift * 60.0),
        df 
    )   
    
    # Build dictionary of eligible machines per operation step
    my_dict = Dict()
    grouped_df = groupby(df_clean, [:Order_ID, :Operation_ID, :Operation_Name, :Sequence])
    
    for group in grouped_df
        route_key = (group.Order_ID[1], group.Operation_ID[1], group.Operation_Name[1], group.Sequence[1])
        machine_list = collect(group.Machine_ID)
        my_dict[route_key] = machine_list
    end
    
    # Warn about orders that lost all eligible machines
    lost = []
    surviving_orders = unique([k[1] for k in keys(my_dict)])
    lost = setdiff(original_orders, surviving_orders)
    if !isempty(lost)
       @warn "Orders with no eligible machine: $lost"
    end
    return my_dict
end

"""
    simulate_times(T, p, D, rng; n=10_000)

Simulates the completion time of one (order, machine) pair `n` times using Monte Carlo.

Parameters:
- T : Total standard processing time
- p : Breakdown probability
- D : Breakdown duration (minutes)
- rng: Random number generator

Returns a vector of `n` simulated completion times.
"""
function simulate_times(T, p, D, rng; n = 10_000)
    times = zeros(n)
    for i in 1:n
        # Normal variation around standard time (mean ≈ 1.02*T)
        t = T * (1.02 + 0.02 * randn(rng))

        # Add breakdown time if the machine fails
        if rand(rng) < p
            t += D
        end

        times[i] = t
    end
    return times
end

"""
    score_candidates(df::DataFrame, α=0.7, seed=42)

Scores every feasible (order, machine) pair.

Steps:
1. Keep only orders that still need production (Required_Production_Qty > 0).
2. Filter machines by eligibility, capacity and available time.
3. Calculate risk-adjusted processing time using Monte Carlo (P50 + P90).
4. Normalize scores locally within each operation step.
5. Optionally integrate Priority_Score from DemandModule.
6. Compute final Candidate_Score and Assignment_Penalty.

Returns a DataFrame with detailed scoring columns.
"""
function score_candidates(df::DataFrame, α::Real =0.7, seed::Int = 42)
    rng = MersenneTwister(seed)
    
    # Define column names used for scoring
    ROUTE_COLS = [:Order_ID, :Operation_ID, :Operation_Name, :Sequence]
    efficiency_col = :Machine_Efficiency             
    time_col = :Risk_Adjusted_Time
    
    # Keep only orders that still require production
    if hasproperty(df, :Required_Production_Qty)
        df = filter(row -> row.Required_Production_Qty > 0, df)
    end
    # Decide quantity column & filter eligible machines
    qty_col = hasproperty(df, :Required_Production_Qty) ? :Required_Production_Qty : :Order_Quantity
    
    df_scored = filter(
        row ->
            uppercase(strip(string(row.Eligible))) == "YES" &&
            uppercase(strip(string(row.Machine_Status))) != "MAINTENANCE" &&
            row[qty_col] <= row.Machine_Capacity_Units_Shift &&  
            (row.Setup_time_min + row.Standard_Cycle_Time_Min_Unit * row[qty_col]) <= (row.Available_Hours_Shift * 60.0),
        df
    )

    # Calculate standard processing time
    df_scored.Total_Standard_Time = df_scored.Setup_time_min .+ (df_scored.Standard_Cycle_Time_Min_Unit .* df_scored[!, qty_col])
    
    # Perform Monte Carlo simulation to extract median (P50) and safe worst-case (P90) times
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
   
    # Blend P50 and P90 into a single Risk-Adjusted Time using the confidence factor α
    df_scored.Weighted_Time = α .* df_scored.P50_Time .+ (1 - α) .* df_scored.P90_Time
    df_scored.Risk_Adjusted_Time = round.(df_scored.Weighted_Time, digits = 2)

    # Initialize columns for normalized scores
    for col in (:Time_Score, :Breakdown_Score, :Efficiency_Score)
        df_scored[!, col] = zeros(n_rows)
    end

    # Local Optimization: Compare and normalize machines strictly within the same operation step
    for group in groupby(df_scored, ROUTE_COLS)
        group[!, :Time_Score] .= normalized_score(group[!, time_col])
        group[!, :Breakdown_Score] .= normalized_score(group.Breakdown_Probability)
        group[!, :Efficiency_Score] .= normalized_score(group[!, efficiency_col]; higher_is_better = true)
    end

    # Integrate Priority_Score (from DemandModule) if available
    if hasproperty(df_scored, :Priority_Score)
        # Normalize Priority_Score to [0, 1]
    priority_norm = normalized_score(df_scored.Priority_Score; higher_is_better = true)
    weights = (
        time = 0.45,
        breakdown = 0.15,
        efficiency = 0.25,
        priority = 0.15
    )
    df_scored.Time_Contribution = weights.time .* df_scored.Time_Score
    df_scored.Breakdown_Contribution = weights.breakdown .* df_scored.Breakdown_Score
    df_scored.Efficiency_Contribution = weights.efficiency .* df_scored.Efficiency_Score
    df_scored.Priority_Contribution   = weights.priority .* priority_norm
    # Convert Score to Penalty
    df_scored.Candidate_Score = df_scored.Time_Contribution .+
                                df_scored.Breakdown_Contribution .+
                                df_scored.Efficiency_Contribution .+
                                df_scored.Priority_Contribution                            
    else
    # Fallback weights when Priority_Score is not present
    weights = (
        time = 0.50,
        breakdown = 0.20,
        efficiency = 0.30
    )

    df_scored.Time_Contribution       = weights.time       .* df_scored.Time_Score
    df_scored.Breakdown_Contribution  = weights.breakdown  .* df_scored.Breakdown_Score
    df_scored.Efficiency_Contribution = weights.efficiency .* df_scored.Efficiency_Score

    df_scored.Candidate_Score = df_scored.Time_Contribution .+
                                df_scored.Breakdown_Contribution .+
                                df_scored.Efficiency_Contribution
    end
    # Convert score to penalty (lower penalty = better assignment)   
    df_scored.Assignment_Penalty = 1.0 .- df_scored.Candidate_Score
    
    return df_scored
end

end