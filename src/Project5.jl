"""
    Project5

A minimal Julia package to start a project from.
"""
module Project5

# Files to be included
include("ScoringModule.jl")

# Functions to be exported
export build_eligible_pairs, score_candidates

end # module Project5

