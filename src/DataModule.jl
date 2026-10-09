"""
    module DataModule

This module loads, cleans, standardizes, and validates manufacturing
production data stored in a CSV file.

The dataset contains information about customer orders, production
operations, machine characteristics, inventory levels, and machine
breakdown risks.

The main workflow is:

1. Read the CSV file into a DataFrame.
2. Rename source columns to standardized internal names.
3. Check whether all required columns exist.
4. Normalize string values and convert numeric and date columns.
5. Remove rows with missing critical identifiers or dates.
6. Standardize categorical values.
7. Replace missing numeric values with column medians.
8. Remove exact duplicate rows.
9. Restore integer types for integer-like columns.
10. Validate the cleaned dataset.
11. Sort the records and return the resulting DataFrame.

Public functions:

- `load_and_clean_data(path)`: Load, clean, validate, sort, and return
  the manufacturing dataset.
- `validate_data(df)`: Check the structure and consistency of a
  cleaned manufacturing DataFrame.

Required packages: DataFrames, CSV, Dates, and Statistics.

Common errors include missing input files, incorrect CSV column names,
invalid numeric values, unsupported date formats, missing usable numeric
values, and invalid machine or eligibility categories.
"""
module DataModule

using DataFrames
using CSV 
using Dates
using Statistics

export load_and_clean_data, validate_data

"""
A list of all columns that must exist in the manufacturing dataset after
the original CSV column names have been normalized.

Each element is a Julia `Symbol`, which is the standard representation
used by DataFrames for column names.

If a required column is absent, `load_and_clean_data` stops with an error
instead of continuing with an incomplete dataset.

When the source CSV introduces a new column name or changes an existing
one, update `COLUMN_MAP` or this list as appropriate.
"""
const REQUIRED_COLUMNS = Symbol[
    :Sr_No, :Order_ID, :Order_Date, :Due_Date, :Product_ID,
    :Order_Quantity, :Priority, :Customer_Type, :Order_Status,
    :Operation_ID, :Operation_Name, :Sequence, :Machine_ID, :Machine_Type,
    :Eligible, :Standard_Cycle_Time_Min_Unit, :Setup_Time_Min,
    :Machine_Capacity_Units_Shift, :Machine_Efficiency, :Machine_Status,
    :Available_Hours_Shift, :Current_Stock, :Safety_Stock, :Reserved_Stock,
    :Breakdown_Probability, :Breakdown_Duration_Min
]

"""
Lists the columns that must be converted into numeric values.

The conversion helper `_to_float` handles numbers, numeric strings,
percentage strings, and missing values.

Percentage strings are converted into decimal proportions.

Missing numeric values are filled with the median of the corresponding
column later in the cleaning process.

Important:
Date columns are deliberately excluded because they are converted
separately using `_to_date`.
"""
const NUMERIC_COLUMNS = Symbol[
    :Sr_No, :Order_Quantity, :Priority, :Sequence,
    :Standard_Cycle_Time_Min_Unit, :Setup_Time_Min,
    :Machine_Capacity_Units_Shift, :Machine_Efficiency,
    :Available_Hours_Shift, :Current_Stock, :Safety_Stock,
    :Reserved_Stock, :Breakdown_Probability, :Breakdown_Duration_Min
]

"""
Lists the columns that should contain text rather than numeric values.

The cleaning process converts non-missing values to strings and removes
leading and trailing whitespace.

This is particularly important for identifiers such as `Order_ID`,
`Product_ID`, and `Machine_ID`, which should generally remain text even
when their values contain only digits.

Missing values are preserved by `_clean_string` and are handled later
according to the cleaning rules for each column.
"""
const STRING_COLUMNS = Symbol[
    :Order_ID, :Product_ID, :Customer_Type, :Order_Status,
    :Operation_ID, :Operation_Name, :Machine_ID, :Machine_Type,
    :Eligible, :Machine_Status
]

"""
Maps the original column names in the CSV file to standardized internal
column names represented by Julia Symbols.

The mapping also accommodates spelling and capitalization variations
in the source dataset.

If the CSV uses different column headings, update this dictionary.
A source column that does not match any mapping will retain its original
name and may subsequently trigger a missing-required-columns error.

The mapping assumes that source headings are unique and do not create
conflicting destination column names.
"""
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

""" Convert a value into a trimmed string while preserving missing values. """
_clean_string(x) = ismissing(x) ? missing : strip(string(x))

"""
Convert an input value into a Float64 number.

Supported inputs:
- Existing numeric values, including integers and floating-point values.
- Strings representing valid numbers, such as "25" or "12.5".
- Percentage strings, such as "85%", which become 0.85.
- Missing values and empty strings, which become `missing`.

The function raises an error if a non-empty value cannot be parsed as
a valid floating-point number.

Examples:
    _to_float(10)       # Returns 10.0
    _to_float("12.5")   # Returns 12.5
    _to_float("85%")    # Returns 0.85
    _to_float("")       # Returns missing

Important:
The percentage conversion assumes that every string ending in "%"
represents a percentage that should be divided by 100. Do not use this
rule for data that already stores percentages as decimal proportions
while also appending a percent sign.
"""
function _to_float(x)
    ismissing(x) && return missing
    x isa Number && return Float64(x)
    s = strip(string(x))
    isempty(s) && return missing
    if endswith(s, "%")
        s = s[1:end-1]                  
        y = tryparse(Float64, s)
        y === nothing && error("Cannot convert '$s%' to Float64.")
        return y / 100
    end
    y = tryparse(Float64, s)
    y === nothing && error("Cannot convert '$s' to Float64.")
    return y
end

"""
Convert an input value into a Julia Date.

Supported inputs:
- `Date` values, returned without modification.
- `DateTime` values, converted to their calendar date.
- Numeric values representing Excel serial dates.
- Strings matching one of the explicitly supported date formats.
- Integer strings representing Excel serial dates.

The Excel conversion uses the Windows 1900 date system, with
1899-12-30 as the base date.

The `u` format code is used for month names as supported by Julia's
Dates formatting system.

Returns `missing` for missing values or empty strings.

Raises an error if no supported format can parse the input.

Troubleshooting:
- Check whether the source uses an unsupported date format.
- Check whether Excel serial dates were imported as strings or numbers.
- Add the appropriate date format if the source contains another
  consistent date representation.

Ambiguous dates, such as 03/04/2026, are interpreted according to the
configured format. Verify the source convention before relying on them.
"""
function _to_date(x)
    ismissing(x) && return missing
    x isa Date && return x
    x isa DateTime && return Date(x)

    if x isa Number
        """ Excel serial date (Windows 1900 date system). """
        return Date(1899, 12, 30) + Day(round(Int, x))
    end

    s = strip(string(x))
    isempty(s) && return missing

    """ Try common ISO/date-time representations. """
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
Validate the structure and selected consistency rules of a cleaned
manufacturing dataset.

The function checks:
- All columns listed in `REQUIRED_COLUMNS` exist.
- Order quantities are non-negative.
- Standard cycle times and machine capacities are positive.
- Setup times and breakdown durations are non-negative.
- Available machine hours are positive.
- Machine efficiency lies in the interval (0, 1].
- Breakdown probability lies in the interval [0, 1].
- Due dates are not earlier than order dates.
- Machine status values belong to the approved category set.
- Eligibility values are either YES or NO.

Returns `true` if all checks pass.

Raises an error describing the failed check when an invalid condition
is found.

Important:
This function expects a cleaned DataFrame. In particular, the current
checks do not explicitly reject every missing value or verify every
possible business rule. Additional checks may be needed if the dataset
contains missing categorical values, invalid identifiers, inconsistent
stock quantities, or other domain-specific constraints.

If validation fails, inspect the relevant column and the error message
before changing the validation rules. Do not remove a check merely to
make the dataset pass unless the underlying business rule is incorrect.
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
    load_and_clean_data(path)

Load the new manufacturing CSV dataset, normalize its column names,
convert data types, standardize categorical values, remove duplicate rows,
and validate the result.
"""
function load_and_clean_data(path::AbstractString)
    isfile(path) || error("Input file not found: $path")

    raw = CSV.read(path, DataFrame)
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

    """ Drop rows missing critical identifiers/dates. """
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

    """ Standardize categorical values. """
    df.Eligible = uppercase.(string.(df.Eligible))
    df.Machine_Status = [titlecase(lowercase(string(x))) for x in df.Machine_Status]
    df.Order_Status = [titlecase(lowercase(string(x))) for x in df.Order_Status]
    df.Customer_Type = [titlecase(lowercase(string(x))) for x in df.Customer_Type]

    """ Fill non-critical numeric gaps using the column median. """
    for c in NUMERIC_COLUMNS
        if any(ismissing, df[!, c])
            _fill_numeric_missing!(df, c)
        end
    end

    """ Remove exact duplicate candidate records. """
    unique!(df)

    """ Restore integer-like columns. """
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
