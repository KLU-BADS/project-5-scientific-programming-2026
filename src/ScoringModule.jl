module ScoringModule

using DataFrames
using Distributions
using Statistics
using Random

export build_eligible_pairs, score_candidates

#Filters out machines under maintenance and creates a dictionary mapping each Order_ID to its list of eligible Machine_IDs.
function build_eligible_pairs(df::DataFrame)
    # Exclude machines that are currently under maintenance to ensure operational validity
    df_clean = filter(
        row -> row.Machine_status != "Maintenance",
        df
    )
   
    my_dict = Dict()
    # Group the remaining eligible records by Order_ID
    grouped_df = groupby(df_clean, :Order_ID)
    for group in grouped_df
        order_number = group.Order_ID[1]
        Machine_list = group.Machine_Id
        my_dict[order_number] = Machine_list
    end
    
    # Warn about orders with no eligible machine left
    lost = []
    for order in unique(df.Order_ID)
        if !(order in keys(my_dict))
            push!(lost, order)
        end
    end
    if length(lost) > 0
        @warn "Orders with no eligible machine" orders = lost 
    end

    return my_dict
end

# Simulate the completion time of one (order, machine) pair n times.
#   T = Total_Standard_Time, p = Breakdown_Probability, D = Breakdown_Duration_Min
# Returns a vector with n simulated completion times.
function simulate_times(T, p, D; n = 100_000)
    times = zeros(n)
    for i in 1:n
        # Step 1: normal run time, mean = 1.02*T, standard deviation = 0.02*T
        t = T * (1.02 + 0.02 * randn())

        # Step 2: does the machine break down? If yes, add the repair time D
        if rand() < p
            t += D
        end

        times[i] = t
    end
    return times
end

function score_candidates(df::DataFrame, α::Real =0.7)
    # Eliminate Maintenance Machine
    df_clean = filter(
        row -> row.Machine_status != "Maintenance",
        df
    )

    # Create a copy of the cleaned DataFrame to store the scored results
    df_scored = copy(df_clean)

    # Calculate ideal baseline duration
    df_scored.Total_Standard_Time = df_scored.Setup_time_min .+ (df_scored.Standard_Cycle_Time_Min_Unit .* df_scored.Order_Quantity)

    # Calculate the simulated real duration using a normal distribution
    df_scored.Simulated_Time = round.(df_scored.Total_Standard_Time .* rand(Normal(1.02, 0.02), nrow(df_scored)), digits = 2)

    # Calculate broken machine event
    df_scored.Is_Broken = rand(nrow(df_scored)) .< df_scored.Breakdown_Probability

    # Calculate the final duration based on whether the machine is broken or not
    df_scored.Final_Operation_Time = df_scored.Simulated_Time .+ (df_scored.Is_Broken .* df_scored.Breakdown_Duration_Min)

    # Expected time
    df_scored.Expected_Time = df_scored.Total_Standard_Time .+ (df_scored.Breakdown_Probability .* df_scored.Breakdown_Duration_Min)

    # P50 and P90 from Monte Carlo simulation, row by row
    n_rows = nrow(df_scored)
    p50 = zeros(n_rows)
    p90 = zeros(n_rows)
    for i in 1:n_rows
        times = simulate_times(
            df_scored.Total_Standard_Time[i],
            df_scored.Breakdown_Probability[i],
            df_scored.Breakdown_Duration_Min[i]
        )
        p50[i] = quantile(times, 0.5)   # median completion time
        p90[i] = quantile(times, 0.9)   # safe worst-case completion time
    end
    df_scored.P50_Time = round.(p50, digits = 2)
    df_scored.P90_Time = round.(p90, digits = 2)   
   
    #Scoring Function
    df_scored.Weighted_Time = α .* df_scored.P50_Time .+ (1 - α) .* df_scored.P90_Time
    df_scored.Risk_Adjusted_Time = round.(df_scored.Weighted_Time, digits = 2)
    return df_scored
end 
end # module ScoringModule