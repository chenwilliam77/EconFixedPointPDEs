using Test, OrderedCollections
include(joinpath(dirname(@__FILE__), "../../src/includeall.jl"))

@testset "Average updating method" begin
    x_new = rand(3)
    x_old = rand(3)
    learning_rates = rand(10)
    for i in 1:10
        x_avg = average_update(x_new, x_old, learning_rates[i])
        @test x_avg == (x_new * learning_rates[i] + x_old * (1 - learning_rates[i]))
    end
end

@testset "Methods for calculating errors during functional iteration" begin
    funcvar1 = OrderedDict(:a => rand(3), :b => rand(3))
    funcvar2 = OrderedDict(:a => rand(3), :b => rand(3))

    @test calculate_func_error(funcvar1[:a], funcvar2[:a], :total_error) == sum(abs.(funcvar1[:a] - funcvar2[:a]))
    @test calculate_func_error(funcvar1[:a], funcvar2[:a], :L∞) == maximum(abs.(funcvar1[:a] - funcvar2[:a]))
    @test calculate_func_error(funcvar1[:a], funcvar2[:a], :Linf) == maximum(abs.(funcvar1[:a] - funcvar2[:a]))
    @test calculate_func_error(funcvar1[:a], funcvar2[:a], :max_abs_error) == maximum(abs.(funcvar1[:a] - funcvar2[:a]))
    @test calculate_func_error(funcvar1[:a], funcvar2[:a], :maximum_absolute_error) == maximum(abs.(funcvar1[:a] - funcvar2[:a]))
    @test calculate_func_error(funcvar1[:a], funcvar2[:a], :L²) == sum((funcvar1[:a] - funcvar2[:a]) .^ 2)
    @test calculate_func_error(funcvar1[:a], funcvar2[:a], :L2) == sum((funcvar1[:a] - funcvar2[:a]) .^ 2)
    @test calculate_func_error(funcvar1[:a], funcvar2[:a], :squared_error) == sum((funcvar1[:a] - funcvar2[:a]) .^ 2)

    @test calculate_func_error(funcvar1, funcvar2, :total_error) == sum(map(x -> sum(abs.(funcvar1[x] - funcvar2[x])), [:a, :b]))
    @test calculate_func_error(funcvar1, funcvar2, :L∞) ==
        maximum(map(x -> maximum(abs.(funcvar1[x] - funcvar2[x])), [:a, :b]))
    @test calculate_func_error(funcvar1, funcvar2, :Linf) ==
        maximum(map(x -> maximum(abs.(funcvar1[x] - funcvar2[x])), [:a, :b]))
    @test calculate_func_error(funcvar1, funcvar2, :max_abs_error) ==
        maximum(map(x -> maximum(abs.(funcvar1[x] - funcvar2[x])), [:a, :b]))
    @test calculate_func_error(funcvar1, funcvar2, :maximum_absolute_error) ==
        maximum(map(x -> maximum(abs.(funcvar1[x] - funcvar2[x])), [:a, :b]))
    @test calculate_func_error(funcvar1, funcvar2, :L²) == sum(map(x -> sum((funcvar1[x] - funcvar2[x]) .^ 2), [:a, :b]))
    @test calculate_func_error(funcvar1, funcvar2, :L2) == sum(map(x -> sum((funcvar1[x] - funcvar2[x]) .^ 2), [:a, :b]))
    @test calculate_func_error(funcvar1, funcvar2, :squared_error) == sum(map(x -> sum((funcvar1[x] - funcvar2[x]) .^ 2), [:a, :b]))

    @test calculate_func_error(funcvar1, funcvar2, :total_error; vars = [:a]) == sum(map(x -> sum(abs.(funcvar1[x] - funcvar2[x])), [:a]))
    @test calculate_func_error(funcvar1, funcvar2, :L∞; vars = [:a]) ==
        maximum(map(x -> maximum(abs.(funcvar1[x] - funcvar2[x])), [:a]))
    @test calculate_func_error(funcvar1, funcvar2, :L²; vars = [:a]) == sum(map(x -> sum((funcvar1[x] - funcvar2[x]) .^ 2), [:a]))
end


@testset "Construction of non-uniform grid spacing"  begin
    stategrid = StateGrid(OrderedDict(:x => sort(rand(10))))
    bc = [(0., 1.)]
    @test_throws AssertionError nonuniform_grid_spacing(stategrid, [(0., 1.), (0., 1.)])
    @test nonuniform_grid_spacing(stategrid) ≈ vcat(diff(stategrid[:x][1:2]), diff(stategrid[:x]), diff(stategrid[:x][end - 1:end]))
    @test nonuniform_grid_spacing(stategrid) ≈ vcat(stategrid[:x][1], diff(stategrid[:x]), 1. - stategrid[:x][end])
end
