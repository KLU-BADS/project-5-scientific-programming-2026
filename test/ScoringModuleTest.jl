using Test
using DataFrames
using Random
using Statistics

# =========================================================================
# 1. TEST SIMULATE_TIMES (Monte Carlo simulation with local RNG)
# =========================================================================
@testset "simulate_times (ScoringModule)" begin
    rng = MersenneTwister(42)

    # Never breaks down (p = 0.0)
    t0 = ScoringModule.simulate_times(100.0, 0.0, 50.0, rng; n = 10_000)
    @test length(t0) == 10_000
    @test abs(mean(t0) - 102.0) < 0.5   # mean ~ 1.02 * T

    # Always breaks down (p = 1.0)
    t1 = ScoringModule.simulate_times(100.0, 1.0, 50.0, rng; n = 10_000)
    @test abs(mean(t1) - 152.0) < 0.5   # mean ~ 1.02 * T + D
end

# =========================================================================
# 2. BUILD MOCK DATA FOR THE FOLLOWING TESTS
# =========================================================================
df_test = DataFrame(
    Order_ID = [1, 1, 2, 2, 3],
    Operation_ID = ["OP10", "OP20", "OP10", "OP20", "OP10"],
    Operation_Name = ["Cutting", "Assembly", "Cutting", "Assembly", "Cutting"],
    Sequence = [1, 2, 1, 2, 1],
    Machine_ID = ["M_A", "M_B", "M_A", "M_B", "M_C"],
    Eligible = ["Yes", "Yes", "Yes", "Yes", "Yes"],
    Machine_Status = ["Active", "Active", "Active", "MAINTENANCE", "Active"],

    Setup_time_min = [10.0, 15.0, 10.0, 10.0, 10.0],
    Standard_Cycle_Time_Min_Unit = [1.0, 2.0, 1.0, 1.0, 1.0],
    Order_Quantity = [100, 100, 100, 100, 5000],

    Breakdown_Probability = [0.05, 0.02, 0.05, 0.05, 0.05],
    Breakdown_Duration_Min = [30.0, 20.0, 30.0, 30.0, 30.0],
    machine_Efficiency = [0.95, 0.90, 0.95, 0.90, 0.90],  # must match the column name in the module

    Machine_Capacity_Units_Shift = [1000, 1000, 1000, 1000, 500],
    Available_Hours_Shift = [8.0, 8.0, 8.0, 8.0, 8.0]
)
df_before = copy(df_test)

# =========================================================================
# 3. TEST BUILD_ELIGIBLE_PAIRS
# =========================================================================
@testset "Test 2: build_eligible_pairs" begin
    # Separate, minimal dataset for this function only
    df_build = DataFrame(
        Order_ID = [1, 1, 2],
        Operation_ID = ["OP10", "OP20", "OP10"],
        Operation_Name = ["Cutting", "Machining", "Cutting"],
        Sequence = [1, 2, 1],
        Machine_ID = ["M01", "M03", "M02"],
        Eligible = ["Yes", "Yes", "Yes"],
        Machine_Status = ["Active", "Active", "MAINTENANCE"],  # M02 under maintenance
        Setup_time_min = [10.0, 10.0, 10.0],
        Standard_Cycle_Time_Min_Unit = [1.0, 1.0, 1.0],
        Order_Quantity = [100, 100, 100],
        Machine_Capacity_Units_Shift = [1000, 1000, 1000],
        Available_Hours_Shift = [24.0, 24.0, 24.0]
    )

    df_before_build = copy(df_build)

    d = ScoringModule.build_eligible_pairs(df_build)

    @test isa(d, AbstractDict)
    @test haskey(d, (1, "OP10", "Cutting", 1))
    @test isequal(df_build, df_before_build)  # input must not be modified

    println(">>> Test build_eligible_pairs PASSED")
end

# =========================================================================
# 4. TEST SCORE_CANDIDATES
# =========================================================================
@testset "Test 3: score_candidates (Debug)" begin
    df_score = DataFrame(
        Order_ID = [1, 1],
        Operation_ID = ["OP10", "OP10"],
        Operation_Name = ["Cutting", "Cutting"],
        Sequence = [1, 1],
        Machine_ID = ["M01", "M02"],
        Eligible = ["Yes", "Yes"],
        Machine_Status = ["Available", "Available"],
        Setup_time_min = [10.0, 15.0],
        Standard_Cycle_Time_Min_Unit = [1.0, 1.5],
        Order_Quantity = [100, 100],
        Breakdown_Probability = [0.05, 0.10],
        Breakdown_Duration_Min = [30.0, 60.0],
        Machine_Efficiency = [0.90, 0.85],          # ← sửa tên cột ở đây
        Machine_Capacity_Units_Shift = [1000, 1000],
        Available_Hours_Shift = [8.0, 8.0]
    )

    # seed is POSITIONAL: (df, α, seed)
    df_scored = ScoringModule.score_candidates(df_score, 0.7, 42)

    println("Columns: ", names(df_scored))
    println("nrow: ", nrow(df_scored))

    @test nrow(df_scored) == 2
    @test "Risk_Adjusted_Time" in names(df_scored)
    @test "Candidate_Score" in names(df_scored)

    # Test reproducibility with the same seed
    df_scored_retry = ScoringModule.score_candidates(df_score, 0.7, 42)
    @test df_scored.Risk_Adjusted_Time == df_scored_retry.Risk_Adjusted_Time
end