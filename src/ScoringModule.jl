module ScoringModule

using DataFrames
using Distributions

export build_eligible_pairs, score_candidates

function build_eligible_pairs(df::DataFrame)
    # Eliminate Maintenance Machine
    df_clean = filter(
        row -> row.Machine_status != "Maintenance",
        df
    )
    
    my_dict = Dict()
    grouped_df = groupby(df_clean, :Order_ID)
    for group in grouped_df
        order_number = group.Order_ID[1]
        Machine_list = group.Machine_Id
        my_dict[order_number] = Machine_list
    end
    return my_dict
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

    #P50 Case
    df_scored.P50_Time = df_scored.Expected_Time

    #P90 Case
    df_scored.P90_Time = round.(df_scored.Expected_Time .+ (quantile(Normal(), 0.90) .* (df_scored.Total_Standard_Time .* 0.02)), digits = 2)

    #Scoring Function
    df_scored.Weighted_Time = α .* df_scored.P50_Time .+ (1 - α) .* df_scored.P90_Time
    df_scored.Risk_Adjusted_Time = round.(df_scored.Weighted_Time, digits = 2)
    return df_scored
end

end