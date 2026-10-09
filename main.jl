# Project5.jl - End-to-end manufacturing order-to-machine allocation

include(joinpath(@__DIR__, "src", "Project5.jl"))
using .Project5

input_file = joinpath(@__DIR__, "Project_Data_Final.csv")
output_dir = joinpath(@__DIR__, "output")

results = Project5.run_project(
    input_file;
    output_dir = output_dir,
    nsim = 500
)

println("\nTop scheduled operations:")
println(first(results.schedule, min(20, nrow(results.schedule))))