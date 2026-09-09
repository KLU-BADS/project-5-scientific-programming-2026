using Project5
using Test

# Every @testset that fails will be reported individually, so give them
# names that tell you what broke.

@testset "Project5.jl" begin

    @testset "hello" begin
        # hello() prints, so it returns nothing. What it prints is checked by
        # the jldoctest in its docstring, which runs when the docs are built.
        @test hello() === nothing
    end

    # Add a @testset for each function you write.

end
