module ScoringModule

using DataFrames
using Distributions
using Statistics
using Random

export build_eligible_pairs, score_candidates

# HELPER FUNCTIONS 
    #= Applies Min-Max normalization to scale an array of values into a [0.0, 1.0] range.
    - If `higher_is_better` is false (default), smaller original values get scores closer to 1.0.
    - If `higher_is_better` is true, larger original values get scores closer to 1.0.
    =#
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

# MAIN FUNCTIONS
    #Filters out machines under maintenance and creates a dictionary mapping each Order_ID to its list of eligible Machine_IDs.
function build_eligible_pairs(df::DataFrame)
    # Store the original list of orders BEFORE filtering to accurately track lost orders
    original_orders = unique(df.Order_ID)
    # Exclude machines that are currently under maintenance to ensure operational validity
    df_clean = filter(
        row ->
            uppercase(strip(string(row.Eligible))) == "YES" &&
            uppercase(strip(string(row.Machine_Status))) != "MAINTENANCE" &&
            row.Order_Quantity <= row.Machine_Capacity_Units_Shift &&  
            (row.Setup_time_min + row.Standard_Cycle_Time_Min_Unit * row.Order_Quantity) <= (row.Available_Hours_Shift * 60.0),
        df 
    )
    
    # Group to create Eligible Pairs AND preserve Routing/Operation information
    my_dict = Dict()
    grouped_df = groupby(df_clean, [:Order_ID, :Operation_ID, :Operation_Name, :Sequence])
    
    for group in grouped_df
        route_key = (group.Order_ID[1], group.Operation_ID[1], group.Operation_Name[1], group.Sequence[1])
        machine_list = collect(group.Machine_ID)
        my_dict[route_key] = machine_list
    end
    
    # Warn about orders with no eligible machine left
    lost = []
    surviving_orders = unique([k[1] for k in keys(my_dict)])
    lost = setdiff(original_orders, surviving_orders)
    if !isempty(lost)
       @warn "Orders with no eligible machine: $lost"
    end
    return my_dict
end

# Simulate the completion time of one (order, machine) pair n times.
#   T = Total_Standard_Time, p = Breakdown_Probability, D = Breakdown_Duration_Min
# Returns a vector with n simulated completion times.
function simulate_times(T, p, D, rng; n = 10_000)
    times = zeros(n)
    for i in 1:n
        # Step 1: normal run time, mean = 1.02*T, standard deviation = 0.02*T
        t = T * (1.02 + 0.02 * randn(rng))

        # Step 2: does the machine break down? If yes, add the repair time D
        if rand(rng) < p
            t += D
        end

        times[i] = t
    end
    return times
end

function score_candidates(df::DataFrame, α::Real =0.7, seed::Int = 42)
    rng = MersenneTwister(seed)
    # Define column names used for scoring
    ROUTE_COLS = [:Order_ID, :Operation_ID, :Operation_Name, :Sequence]
    efficiency_col = :Machine_Efficiency             
    time_col = :Risk_Adjusted_Time

    # Eliminate unavailable machines
    df_scored = filter(
        row ->
            uppercase(strip(string(row.Eligible))) == "YES" &&
            uppercase(strip(string(row.Machine_Status))) != "MAINTENANCE" &&
            row.Order_Quantity <= row.Machine_Capacity_Units_Shift &&  
            (row.Setup_time_min + row.Standard_Cycle_Time_Min_Unit * row.Order_Quantity) <= (row.Available_Hours_Shift * 60.0),
        df
    )

    # Calculate the ideal baseline duration before applying risks
    df_scored.Total_Standard_Time = df_scored.Setup_time_min .+ (df_scored.Standard_Cycle_Time_Min_Unit .* df_scored.Order_Quantity)

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

    # Apply weighted contributions to ensure the final score is fully transparent and auditable
    weights = (
        time = 0.50,
        breakdown = 0.20,
        efficiency = 0.30
    )
    
    df_scored.Time_Contribution = weights.time .* df_scored.Time_Score
    df_scored.Breakdown_Contribution = weights.breakdown .* df_scored.Breakdown_Score
    df_scored.Efficiency_Contribution = weights.efficiency .* df_scored.Efficiency_Score

    # Convert Score to Penalty
    df_scored.Candidate_Score = df_scored.Time_Contribution .+
                                df_scored.Breakdown_Contribution .+
                                df_scored.Efficiency_Contribution

    df_scored.Assignment_Penalty = 1.0 .- df_scored.Candidate_Score
    
    return df_scored
end

end 