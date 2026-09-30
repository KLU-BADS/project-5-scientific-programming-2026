module DataModule

using DataFrames
using XLSX
using Dates
using Statistics

export load_and_clean_data, validate_data

const REQUIRED_COLUMNS = Symbol[
    :Sr_No, :Order_ID, :Order_Date, :Due_Date, :Product_ID,
    :Order_Quantity, :Priority, :Customer_Type, :Order_Status,
    :Operation_ID, :Operation_Name, :Sequence, :Machine_ID, :Machine_Type,
    :Eligible, :Standard_Cycle_Time_Min_Unit, :Setup_Time_Min,
    :Machine_Capacity_Units_Shift, :Machine_Efficiency, :Machine_Status,
    :Available_Hours_Shift, :Current_Stock, :Safety_Stock, :Reserved_Stock,
    :Breakdown_Probability, :Breakdown_Duration_Min
]

const NUMERIC_COLUMNS = Symbol[
    :Sr_No, :Order_Quantity, :Priority, :Sequence,
    :Standard_Cycle_Time_Min_Unit, :Setup_Time_Min,
    :Machine_Capacity_Units_Shift, :Machine_Efficiency,
    :Available_Hours_Shift, :Current_Stock, :Safety_Stock,
    :Reserved_Stock, :Breakdown_Probability, :Breakdown_Duration_Min
]

const STRING_COLUMNS = Symbol[
    :Order_ID, :Product_ID, :Customer_Type, :Order_Status,
    :Operation_ID, :Operation_Name, :Machine_ID, :Machine_Type,
    :Eligible, :Machine_Status
]

const COLUMN_MAP = Dict(
    "Sr No" => :Sr_No,
    "Order ID" => :Order_ID,
    "Order Date" => :Order_Date,
    "Due date" => :Due_Date,
    "Product ID" => :Product_ID,
    "Order Quantity" => :Order_Quantity,
    "Priority" => :Priority,
    "Customer Type" => :Customer_Type,
    "Order Status" => :Order_Status,
    "Operation Id" => :Operation_ID,
    "Operation Name" => :Operation_Name,
    "Sequence" => :Sequence,
    "Machine Id" => :Machine_ID,
    "Machine Type" => :Machine_Type,
    "Eligible" => :Eligible,
    "Standard Cycle Time Min Unit" => :Standard_Cycle_Time_Min_Unit,
    "Setup time min" => :Setup_Time_Min,
    "Machine Capacity Units Shift" => :Machine_Capacity_Units_Shift,
    "machine_Efficiency" => :Machine_Efficiency,
    "Machine status" => :Machine_Status,
    "Available Hours Shift" => :Available_Hours_Shift,
    "Current Stock" => :Current_Stock,
    "Safety Stock" => :Safety_Stock,
    "Reserved Stock" => :Reserved_Stock,
    "Breakdown Propability" => :Breakdown_Probability,
    "Breakdown Duration Min" => :Breakdown_Duration_Min
)

_clean_string(x) = ismissing(x) ? missing : strip(string(x))

function _to_float(x)
    ismissing(x) && return missing
    x isa Number && return Float64(x)
    s = strip(string(x))
    isempty(s) && return missing
    y = tryparse(Float64, s)
    y === nothing && error("Cannot convert '$s' to Float64.")
    return y
end

function _to_date(x)
    ismissing(x) && return missing
    x isa Date && return x
    x isa DateTime && return Date(x)

    if x isa Number
        # Excel serial date (Windows 1900 date system).
        return Date(1899, 12, 30) + Day(round(Int, x))
    end

    s = strip(string(x))
    isempty(s) && return missing

    # Try common ISO/date-time representations.
    for fmt in (dateformat"yyyy-mm-dd", dateformat"yyyy-mm-dd HH:MM:SS",
                dateformat"yyyy-mm-ddTHH:MM:SS")
        try
            return Date(DateTime(s, fmt))
        catch
        end
    end

    y = tryparse(Int, s)
    if y !== nothing
        return Date(1899, 12, 30) + Day(y)
    end

    error("Cannot convert '$s' to Date.")
end

function _rename_columns!(df)
    for (old, new) in COLUMN_MAP
        oldsym = Symbol(old)
        if oldsym in Symbol.(names(df))
            rename!(df, oldsym => new)
        end
    end
    return df
end

function _fill_numeric_missing!(df, col)
    vals = [_to_float(x) for x in df[!, col]]
    good = collect(skipmissing(vals))
    if isempty(good)
        error("Column $col contains no usable numeric values.")
    end
    replacement = median(good)
    df[!, col] = [ismissing(x) ? replacement : x for x in vals]
end

"""
    validate_data(df)

Validate the cleaned manufacturing dataset and return `true` if all
critical consistency checks pass.
"""
function validate_data(df::DataFrame)
    missing_cols = setdiff(REQUIRED_COLUMNS, names(df))
    isempty(missing_cols) || error("Missing required columns: $(missing_cols)")

    any(df.Order_Quantity .< 0) && error("Order_Quantity cannot be negative.")
    any(df.Standard_Cycle_Time_Min_Unit .<= 0) &&
        error("Standard cycle time must be greater than zero.")
    any(df.Setup_Time_Min .< 0) && error("Setup time cannot be negative.")
    any(df.Machine_Capacity_Units_Shift .<= 0) &&
        error("Machine capacity must be greater than zero.")
    any(df.Available_Hours_Shift .<= 0) &&
        error("Available machine hours must be greater than zero.")
    any((df.Machine_Efficiency .<= 0) .| (df.Machine_Efficiency .> 1)) &&
        error("Machine efficiency must be in (0, 1].")
    any((df.Breakdown_Probability .< 0) .| (df.Breakdown_Probability .> 1)) &&
        error("Breakdown probability must be in [0, 1].")
    any(df.Breakdown_Duration_Min .< 0) &&
        error("Breakdown duration cannot be negative.")
    any(df.Due_Date .< df.Order_Date) &&
        error("Due dates cannot be earlier than order dates.")

    valid_status = Set(["Available", "Reduced", "Maintenance"])
    bad_status = setdiff(Set(df.Machine_Status), valid_status)
    isempty(bad_status) || error("Unknown machine status values: $bad_status")

    valid_eligible = Set(["YES", "NO"])
    bad_eligible = setdiff(Set(df.Eligible), valid_eligible)
    isempty(bad_eligible) || error("Unknown Eligible values: $bad_eligible")

    return true
end

"""
    load_and_clean_data(path; sheet="Sheet1")

Load the new manufacturing Excel dataset, normalize its column names,
convert data types, standardize categorical values, remove duplicate rows,
and validate the result.
"""
function load_and_clean_data(path::AbstractString; sheet::AbstractString="Sheet1")
    isfile(path) || error("Input file not found: $path")

    raw = DataFrame(XLSX.readtable(path, sheet))
    _rename_columns!(raw)

    missing_cols = setdiff(REQUIRED_COLUMNS, names(raw))
    isempty(missing_cols) || error("Missing required columns: $(missing_cols)")

    for c in STRING_COLUMNS
        raw[!, c] = [_clean_string(x) for x in raw[!, c]]
    end

    for c in NUMERIC_COLUMNS
        raw[!, c] = [_to_float(x) for x in raw[!, c]]
    end

    raw.Order_Date = [_to_date(x) for x in raw.Order_Date]
    raw.Due_Date = [_to_date(x) for x in raw.Due_Date]

    # Drop rows missing critical identifiers/dates.
    critical = [:Order_ID, :Order_Date, :Due_Date, :Operation_ID, :Machine_ID]
    keep = trues(nrow(raw))
    for i in 1:nrow(raw)
        for c in critical
            if ismissing(raw[i, c])
                keep[i] = false
                break
            end
        end
    end
    df = raw[keep, :]

    # Standardize categorical values.
    df.Eligible = uppercase.(string.(df.Eligible))
    df.Machine_Status = [titlecase(lowercase(string(x))) for x in df.Machine_Status]
    df.Order_Status = [titlecase(lowercase(string(x))) for x in df.Order_Status]
    df.Customer_Type = [titlecase(lowercase(string(x))) for x in df.Customer_Type]

    # Fill non-critical numeric gaps using the column median.
    for c in NUMERIC_COLUMNS
        if any(ismissing, df[!, c])
            _fill_numeric_missing!(df, c)
        end
    end

    # Remove exact duplicate candidate records.
    unique!(df)

    # Restore integer-like columns.
    for c in [:Sr_No, :Order_Quantity, :Priority, :Sequence,
              :Setup_Time_Min, :Machine_Capacity_Units_Shift,
              :Available_Hours_Shift, :Current_Stock, :Safety_Stock,
              :Reserved_Stock, :Breakdown_Duration_Min]
        df[!, c] = round.(Int, df[!, c])
    end

    validate_data(df)
    sort!(df, [:Order_ID, :Sequence, :Machine_ID])

    return df
end

end