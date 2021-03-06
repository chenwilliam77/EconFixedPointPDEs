"""
```
initialize_stategrid(method::Symbol, dims::Vector{Int})
```
constructs a state grid (using the implementation in EconPDEs)
using various methods, such as Chebyshev points.
"""
function initialize_stategrid(method::Symbol, grid_info::OrderedDict{Symbol, Tuple{T, T, Int}};
                              get_stategrid::Bool = true) where {T <: Real}
    stategrid_init = OrderedDict{Symbol, Vector{T}}()
    if method == :uniform
        for (k, v) in grid_info
            stategrid_init[k] = range(v[1], stop = v[2], length = v[3])
        end
    elseif method == :chebyshev
        for (k, v) in grid_info
            stategrid_init[k] = v[1] .+ 1. / 2. * (v[2] - v[1]) .* (1. .- cos(pi * (0:(v[3] - 1))' / (v[3] - 1)))
        end
    elseif method == :exponential
        for (k, v) in grid_info
            stategrid_init[k] = exp.(range(log(v[1]), stop = log(v[2]), length = v[3]))
        end
    elseif method == :smolyak
        error("Construction of a Smolyak interpolation grid has not been implemented yet.")
        # This should make a call to BasisMatrices from QuantEcon, as they have a nice user-friendly implementation of Smolyak.
        # Alternatively, we can try SmolyakApprox, tho QuantEcon seems more likely to be well-maintained.
    else
        error("Grid construction method $method has not been implemented.")
    end

    if get_stategrid
        return StateGrid(stategrid_init)
    else
        return stategrid_init
    end
end
