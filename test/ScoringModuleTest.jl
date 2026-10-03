# Test suite for ScoringModule (build_eligible_pairs, score_candidates, normalized_score)
#
# How to run (put this file next to ScoringModule.jl, then in a terminal):
#     julia test_scoring_module.jl
# Packages needed: DataFrames, Distributions (Test, Random, Statistics, Logging are built in)

using Test, DataFrames, Random, Statistics, Distributions, Logging

include(joinpath(@__DIR__, "ScoringModule.jl"))   # change the file name here if yours is different
using .ScoringModule

near(a, b) = isapprox(a, b; atol = 1e-9)

# ---------------------------------------------------------------------------
# Fake data: 11 rows, built to exercise every branch
#   Order 1: Cutting has M01, M02 (ok) + M08 (Maintenance); Machining has M03 only
#   Order 2: Cutting has M01 (ok) + M02 (Eligible = "No"); Machining has M03, M04
#   Order 3: its only machine is under maintenance (" maintenance " -> tests strip/uppercase)
#   Order 4: Cutting has M01 (ok); Machining has M03 only and it is under maintenance
# ---------------------------------------------------------------------------
df = DataFrame(
    Order_ID                     = [1, 1, 1, 1, 2, 2, 2, 2, 3, 4, 4],
    Operation_Id                 = ["OP10", "OP10", "OP10", "OP20", "OP10", "OP10", "OP20", "OP20", "OP10", "OP10", "OP20"],
    Operation_Name               = ["Cutting", "Cutting", "Cutting", "Machining", "Cutting", "Cutting", "Machining", "Machining", "Cutting", "Cutting", "Machining"],
    Sequence                     = [1, 1, 1, 2, 1, 1, 2, 2, 1, 1, 2],
    Machine_Id                   = ["M01", "M02", "M08", "M03", "M01", "M02", "M03", "M04", "M08", "M01", "M03"],
    Eligible                     = ["Yes", "yes", "Yes", "Yes", "Yes", "No", "Yes", "Yes", "Yes", "Yes", "Yes"],
    Machine_status               = ["Available", "Reduced", "Maintenance", "Available", "Available", "Available",
                                    "Available", "Available", " maintenance ", "Available", "Maintenance"],
    Setup_time_min               = [20.0, 25.0, 30.0, 30.0, 20.0, 25.0, 30.0, 35.0, 30.0, 20.0, 30.0],
    Standard_Cycle_Time_Min_Unit = [2.0, 2.2, 1.9, 3.0, 2.0, 1.8, 3.0, 2.7, 1.9, 2.0, 3.0],
    Order_Quantity               = [100, 100, 100, 100, 50, 50, 50, 50, 20, 80, 80],
    Breakdown_Probability        = [0.05, 0.03, 0.04, 0.05, 0.05, 0.03, 0.05, 0.04, 0.04, 0.05, 0.05],
    Breakdown_Duration_Min       = [60.0, 45.0, 120.0, 50.0, 60.0, 45.0, 50.0, 40.0, 120.0, 60.0, 50.0],
    machine_Efficiency           = [0.94, 0.91, 0.88, 0.95, 0.94, 0.91, 0.95, 0.92, 0.88, 0.94, 0.95],
)
df_before = copy(df)

# Pick the scored row of one candidate (order, operation, machine)
pick(s, o, op, m) = first(s[(s.Order_ID .== o) .& (s.Operation_Id .== op) .& (s.Machine_Id .== m), :])

# ---------------------------------------------------------------------------
@testset "normalized_score (min-max helper)" begin
    ns = ScoringModule.normalized_score

    @test ns([10, 20, 30]) ≈ [1.0, 0.5, 0.0]                           # smaller is better (default)
    @test ns([10, 20, 30]; higher_is_better = true) ≈ [0.0, 0.5, 1.0]  # larger is better
    @test ns([5.0, 5.0, 5.0]) == ones(3)                               # all equal -> all 1.0
    @test ns([7.0]) == [1.0]                                           # one element -> 1.0
    @test ns([3.0, 1.0, 2.0]) ≈ [0.0, 1.0, 0.5]                        # order of input is kept
    @test all(0 .<= ns(rand(50)) .<= 1)
end

@testset "simulate_times" begin
    Random.seed!(11)
    t0 = ScoringModule.simulate_times(100.0, 0.0, 50.0; n = 20_000)    # never breaks down
    @test length(t0) == 20_000
    @test abs(mean(t0) - 102.0) < 0.5                                  # mean ~ 1.02 * T
    t1 = ScoringModule.simulate_times(100.0, 1.0, 50.0; n = 20_000)    # always breaks down
    @test abs(mean(t1) - 152.0) < 0.5                                  # mean ~ 1.02 * T + D
end

# ---------------------------------------------------------------------------
@testset "build_eligible_pairs" begin
    # Order 3 has no machine left -> exactly one warning that mentions it
    d = @test_logs (:warn, r"Orders with no eligible machine") build_eligible_pairs(df)

    # Keys are the 4-part route keys, one per surviving operation
    @test Set(keys(d)) == Set([
        (1, "OP10", "Cutting", 1),
        (1, "OP20", "Machining", 2),
        (2, "OP10", "Cutting", 1),
        (2, "OP20", "Machining", 2),
        (4, "OP10", "Cutting", 1),
    ])

    @test sort(d[(1, "OP10", "Cutting", 1)])   == ["M01", "M02"]   # M08 removed (Maintenance), "yes" accepted
    @test sort(d[(1, "OP20", "Machining", 2)]) == ["M03"]
    @test sort(d[(2, "OP10", "Cutting", 1)])   == ["M01"]          # M02 removed (Eligible = "No")
    @test sort(d[(2, "OP20", "Machining", 2)]) == ["M03", "M04"]
    @test sum(length, values(d)) == 7

    @test !any(k -> k[1] == 3, keys(d))                            # order 3 fully lost
    @test !haskey(d, (4, "OP20", "Machining", 2))                  # operation lost, order 4 survives
    @test isequal(df, df_before)                                   # input is not modified

    # No problems in the data -> no warning at all
    df_ok = filter(:Order_ID => in([1, 2]), df)
    d_ok = @test_logs build_eligible_pairs(df_ok)
    @test length(d_ok) == 4
end

@testset "build_eligible_pairs: lost operation warning" begin
    logger = Test.TestLogger()
    with_logger(logger) do
        build_eligible_pairs(df)
    end
    msgs = join([string(l.message) for l in logger.logs], " ")

    @test occursin("3", msgs)                    # order 3 (all machines lost) is reported
    # Order 4 loses operation OP20 but keeps OP10, so it is NOT in the current warning.
    # The Optimization module cannot schedule such an order, so a warning would help.
    # @test_broken = known gap. If you add an operation-level warning, this line will
    # report "Unexpected Pass": then change it to a normal @test.
    @test_broken occursin("OP20", msgs)
end

# ---------------------------------------------------------------------------
@testset "score_candidates: structure and filtering" begin
    Random.seed!(1)
    s = score_candidates(df)

    @test nrow(s) == 7                                              # 11 rows - 4 not eligible/maintenance
    for col in (:Total_Standard_Time, :P50_Time, :P90_Time, :Weighted_Time, :Risk_Adjusted_Time,
                :Time_Score, :Breakdown_Score, :Efficiency_Score,
                :Time_Contribution, :Breakdown_Contribution, :Efficiency_Contribution,
                :Candidate_Score, :Assignment_Penalty)
        @test hasproperty(s, col)
        @test all(!ismissing, s[!, col])
        @test all(isfinite, s[!, col])
    end

    @test !any((s.Order_ID .== 1) .& (s.Machine_Id .== "M08"))     # maintenance removed
    @test !any((s.Order_ID .== 2) .& (s.Machine_Id .== "M02"))     # Eligible = "No" removed
    @test !(3 in s.Order_ID)                                       # " maintenance " (spaces/lowercase) removed
    @test !any((s.Order_ID .== 4) .& (s.Operation_Id .== "OP20"))
    @test isequal(df, df_before)                                   # input is not modified

    # Baseline duration formula
    @test s.Total_Standard_Time ≈ s.Setup_time_min .+ s.Standard_Cycle_Time_Min_Unit .* s.Order_Quantity
    @test near(pick(s, 1, "OP10", "M01").Total_Standard_Time, 220.0)

    # P50 <= Risk_Adjusted <= P90 (default α = 0.7)
    @test all(s.P90_Time .>= s.P50_Time)
    @test all(s.P50_Time .- 1e-9 .<= s.Risk_Adjusted_Time .<= s.P90_Time .+ 1e-9)
end

@testset "score_candidates: scores are valid and transparent" begin
    Random.seed!(1)
    s = score_candidates(df)

    for col in (:Time_Score, :Breakdown_Score, :Efficiency_Score, :Candidate_Score, :Assignment_Penalty)
        @test all(0 .- 1e-9 .<= s[!, col] .<= 1 .+ 1e-9)
    end

    # Weights used by the module: time 0.5, breakdown 0.2, efficiency 0.3
    @test s.Time_Contribution       ≈ 0.5 .* s.Time_Score
    @test s.Breakdown_Contribution  ≈ 0.2 .* s.Breakdown_Score
    @test s.Efficiency_Contribution ≈ 0.3 .* s.Efficiency_Score
    @test s.Candidate_Score         ≈ s.Time_Contribution .+ s.Breakdown_Contribution .+ s.Efficiency_Contribution
    @test s.Assignment_Penalty      ≈ 1.0 .- s.Candidate_Score
end

@testset "score_candidates: scores inside each operation group" begin
    Random.seed!(1)
    s = score_candidates(df)

    # Group (1, OP10): M01 is faster and more efficient, M02 is less likely to break down
    a = pick(s, 1, "OP10", "M01"); b = pick(s, 1, "OP10", "M02")
    @test near(a.Time_Score, 1.0);       @test near(b.Time_Score, 0.0)
    @test near(a.Breakdown_Score, 0.0);  @test near(b.Breakdown_Score, 1.0)
    @test near(a.Efficiency_Score, 1.0); @test near(b.Efficiency_Score, 0.0)
    @test near(a.Candidate_Score, 0.8);  @test near(b.Candidate_Score, 0.2)
    @test near(a.Assignment_Penalty, 0.2); @test near(b.Assignment_Penalty, 0.8)

    # Group (2, OP20): M04 is faster and safer, M03 is more efficient
    c = pick(s, 2, "OP20", "M03"); e = pick(s, 2, "OP20", "M04")
    @test near(e.Time_Score, 1.0);       @test near(c.Time_Score, 0.0)
    @test near(e.Breakdown_Score, 1.0);  @test near(c.Breakdown_Score, 0.0)
    @test near(c.Efficiency_Score, 1.0); @test near(e.Efficiency_Score, 0.0)
    @test near(e.Candidate_Score, 0.7);  @test near(c.Candidate_Score, 0.3)

    # Single-machine groups: nothing to compare -> every score is 1.0, penalty 0.0
    for (o, op, m) in ((1, "OP20", "M03"), (2, "OP10", "M01"), (4, "OP10", "M01"))
        r = pick(s, o, op, m)
        @test near(r.Time_Score, 1.0)
        @test near(r.Breakdown_Score, 1.0)
        @test near(r.Efficiency_Score, 1.0)
        @test near(r.Candidate_Score, 1.0)
        @test near(r.Assignment_Penalty, 0.0)
    end
end

@testset "score_candidates: alpha and reproducibility" begin
    Random.seed!(5); s_default = score_candidates(df)             # α = 0.7
    Random.seed!(5); s_one     = score_candidates(df, 1)          # Int α must work
    Random.seed!(5); s_zero    = score_candidates(df, 0.0)

    @test s_one.Risk_Adjusted_Time  ≈ s_one.P50_Time              # α = 1 -> only P50
    @test s_zero.Risk_Adjusted_Time ≈ s_zero.P90_Time             # α = 0 -> only P90
    @test s_one.P50_Time == s_default.P50_Time                    # same seed -> same simulation
    @test s_zero.P90_Time == s_default.P90_Time

    Random.seed!(9); x = score_candidates(df)
    Random.seed!(9); y = score_candidates(df)
    @test x.Risk_Adjusted_Time == y.Risk_Adjusted_Time
    @test x.Candidate_Score == y.Candidate_Score
end

@testset "score_candidates: P50/P90 close to the exact answer" begin
    # Exact quantiles of the two-scenario model (no breakdown / breakdown),
    # compared with the Monte Carlo result. Probabilities here are 0.03-0.05;
    # near p = 0.10 the P90 is naturally noisy, so it is not tested on purpose.
    Random.seed!(2026)
    s = score_candidates(df)
    for r in eachrow(s)
        T, p, D = r.Total_Standard_Time, r.Breakdown_Probability, r.Breakdown_Duration_Min
        mix = MixtureModel([Normal(1.02T, 0.02T), Normal(1.02T + D, 0.02T)], [1 - p, p])
        @test abs(r.P50_Time - quantile(mix, 0.5)) < 0.002T + 0.1
        @test abs(r.P90_Time - quantile(mix, 0.9)) < 0.005T + 0.1
    end
end

# ---------------------------------------------------------------------------
@testset "Edge cases" begin
    # Missing a required column -> an error (the module has no friendlier check yet)
    @test_throws Exception score_candidates(select(df, Not(:machine_Efficiency)))
    @test_throws Exception score_candidates(select(df, Not(:Eligible)))
    @test_throws Exception build_eligible_pairs(select(df, Not(:Operation_Id)))

    # α of the wrong type
    @test_throws MethodError score_candidates(df, "0.7")

    # Every machine unavailable -> empty result, no crash
    df_none = copy(df)
    df_none.Machine_status .= "Maintenance"
    @test nrow(score_candidates(df_none)) == 0
    @test isempty(@test_logs (:warn, r"Orders with no eligible machine") build_eligible_pairs(df_none))
end

# ---------------------------------------------------------------------------
# OPTIONAL: run on the real project data once DataModule has cleaned it.
# In the Julia REPL:   include("test_scoring_module.jl");  check_real_data(df_clean)
# Expected numbers below are for project_data.xlsx (990 rows, 165 orders, 3 Maintenance rows).
# ---------------------------------------------------------------------------
function check_real_data(df_real::DataFrame)
    required = [:Order_ID, :Operation_Id, :Operation_Name, :Sequence, :Machine_Id, :Eligible,
                :Machine_status, :Setup_time_min, :Standard_Cycle_Time_Min_Unit, :Order_Quantity,
                :Breakdown_Probability, :Breakdown_Duration_Min, :machine_Efficiency]
    absent = setdiff(required, Symbol.(names(df_real)))
    if !isempty(absent)
        @warn "The data is missing columns that ScoringModule needs (check spelling and capitals)" absent
        return
    end

    @testset "Real data" begin
        Random.seed!(1)
        d = @test_logs build_eligible_pairs(df_real)               # no warning expected
        s = score_candidates(df_real)

        lens = [length(v) for v in values(d)]
        @test length(d) == 495                                      # 165 orders x 3 operations
        @test sum(lens) == 987                                      # 990 - 3 maintenance rows
        @test (count(==(1), lens), count(==(2), lens), count(==(3), lens)) == (70, 358, 67)
        @test haskey(d, ("O0021", "OP10", "Cutting", 1)) &&
              d[("O0021", "OP10", "Cutting", 1)] == ["M01"]

        @test nrow(s) == 987
        @test all(!isnan, s.Candidate_Score)
        @test all(0 .- 1e-9 .<= s.Candidate_Score .<= 1 .+ 1e-9)

        per_op = combine(groupby(s, [:Order_ID, :Operation_Id]), nrow => :n)
        @test nrow(per_op) == 495
        @test count(==(1), per_op.n) == 70                          # single-machine groups
        singles = innerjoin(s, per_op[per_op.n .== 1, [:Order_ID, :Operation_Id]], on = [:Order_ID, :Operation_Id])
        @test all(near.(singles.Candidate_Score, 1.0))
    end
end