using Project5
using Test

@testset "Project5.jl" begin
    results, decision = Project5.run_my_module()
    @test results.on_time == 1.0       # all example orders on time
    @test decision[1] == false         # "NO → Implement & Monitor"
end