"""
    Project5

A minimal Julia package to start a project from.
"""
module Project5

# Files to be included
include("DataModule.jl")

# Functions to be exported
export load_and_clean_data, validate_data

end # module Project5

