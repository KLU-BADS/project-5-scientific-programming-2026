using Project5
using Test

@testset "Project5.jl" begin
    results, decision = Project5.run_my_module()
    @test results.on_time == 1.0       # all example orders on time
    @test decision[1] == false         # "NO → Implement & Monitor"
end

@testset "Every order-operation is scheduled" begin
    df = Project5.DataModule.load_and_clean_data(Project5.DEFAULT_DATA_FILE)
    to_produce = Set(string.(Project5.DemandModule.demand_analysis(df).Order_ID))
    needed = Set((string(r.Order_ID), r.Sequence) for r in eachrow(df) if string(r.Order_ID) in to_produce)

    # run in a temporary folder: run_project writes its CSV and report files to the current folder
    _, schedule, _, _ = mktempdir(dir -> cd(run_project, dir))
    scheduled = collect(zip(schedule.Order_ID, schedule.Sequence))

    @test Set(scheduled) == needed                    # no operation is dropped
    @test length(scheduled) == length(needed)         # and none is scheduled twice
end
