module DemandModule

using DataFrames
using Dates

export demand_analysis, priority_weight


# Demand Analysis
function demand_analysis(df::DataFrame)

    # Group data by Order_ID
    order_groups = groupby(df::DataFrame, :Order_ID)

    # Create one row per Order_ID
    df_order_level = combine(
        order_groups,
        :Product_ID => first => :Product_ID,
        :Order_Date => first => :Order_Date,
        :Order_Quantity => first => :Order_Quantity,
        :Due_Date => first => :Due_Date,
        :Priority => first => :Priority,
        :Customer_Type => first => :Customer_Type,
        :Order_Status => first => :Order_Status
    )

    # Create product-level inventory table
    df_inventory = combine(
        groupby(df::DataFrame, :Product_ID),
        :Current_Stock => first => :Current_Stock,
        :Safety_Stock => first => :Safety_Stock,
        :Reserved_Stock => first => :Reserved_Stock
    )

    # Join order-level demand with inventory information
    df_demand_inventory = leftjoin(
        df_order_level,
        df_inventory,
        on = :Product_ID
    )

    # Sort orders:
    # Priority 1 = highest priority
    # Earlier due date = higher urgency
    sort!(
        df_demand_inventory,
        [:Product_ID, :Priority, :Due_Date]
    )

    # Store remaining available inventory by product
    remaining_inventory = Dict{String, Float64}()

    for row in eachrow(df_inventory)

        available =
            row.Current_Stock -
            row.Safety_Stock -
            row.Reserved_Stock

        remaining_inventory[string(row.Product_ID)] =
            max(available, 0)

    end

    # Initialize required production quantity
    df_demand_inventory.Required_Production_Qty =
        zeros(Float64, nrow(df_demand_inventory))

    # Allocate available inventory to orders
    for i in 1:nrow(df_demand_inventory)

        product =
            string(df_demand_inventory.Product_ID[i])

        order_quantity =
            df_demand_inventory.Order_Quantity[i]

        inventory =
            get(remaining_inventory, product, 0.0)

        inventory_used =
            min(order_quantity, inventory)

        df_demand_inventory.Required_Production_Qty[i] =
            order_quantity - inventory_used

        remaining_inventory[product] =
            inventory - inventory_used

    end
    # Only keep orders that still need production
    df_demand_inventory = filter(
        row -> row.Required_Production_Qty > 0,
        df_demand_inventory
    )
    return df_demand_inventory
end


# Priority Weight
function priority_weight(df)

    # Priority score
    # Priority 1 = highest priority
    max_priority = maximum(df.Priority)

    priority_score =
        (max_priority .- df.Priority .+ 1) ./ max_priority

    # Quantity score
    max_quantity = maximum(df.Order_Quantity)

    quantity_score =
        df.Order_Quantity ./ max_quantity

    # Deadline score
    min_Due_Date = minimum(df.Due_Date)

    days_to_due =
        Dates.value.(
            df.Due_Date .- min_Due_Date
        )

    max_days = maximum(days_to_due)

    deadline_score =
        max_days == 0 ?
        ones(nrow(df)) :
        1 .- days_to_due ./ max_days

    # Final priority score
    df.Priority_Score =
        0.50 .* priority_score .+
        0.30 .* deadline_score .+
        0.20 .* quantity_score

    # Highest score first
    sort!(
        df,
        :Priority_Score,
        rev = true
    )

    return df
end

end

