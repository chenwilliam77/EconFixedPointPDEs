# Extend later to multiple dimensions by using multple dispatch, probably we'll now use a Vector of Tuples of Ints
function init_derivatives!(m::AbstractNLCTModel, instructions::Dict{Symbol, Vector{Int}}), statevars::Vector{Symbol})

    derivs = get_derivatives(m)
    state = statevars[1]

    for (k, v) in instructions
        for i in v
            if i == 1
                derivs[Symbol(:∂, k, :_∂, state)]
            elseif i == 2
                derivs[Symbol(:∂², k, :_∂, state, :²)]
            end
        end
    end
end

function init_derivatives!(m::AbstractNLCTModel, instructions::Dict{Symbol, Vector{Tuple{Int, Int}}}), statevars::Vector{Symbol})

    derivs = get_derivatives(m)
    state1 = statevars[1]
    state2 = statevars[2]

    for (k, v) in instructions
        for i in v
            if i == (1, 0)
                derivs[Symbol(:∂, k, :_∂, state1)]
            elseif i == (2, 0)
                derivs[Symbol(:∂², k, :_∂, state1, :²)]
            elseif i == (0, 1)
                derivs[Symbol(:∂, k, :_∂, state2)]
            elseif i == (0, 2)
                derivs[Symbol(:∂², k, :_∂, state2, :²)]
            elseif i == (1, 1)
                derivs[Symbol(:∂², k, :_∂, state1, :∂, state2)]
            end
        end
    end
end


"""
```
function standard_derivs(dims::Int)
```

returns instructions for which derivatives
to calculate for standard continuous time models,
depending on the dimension `dims` of the state space.

For a one-dimensional model, we request the first and second derivatives.

For a multi-dimensional model, we request the first, second,
and (first) mixed partial derivatives, e.g.
for a 2D model, we want ∂f_∂x, ∂f²_∂x2, ∂f²_∂x∂y, ∂f_∂y, ∂f²_∂y2.

The instructions are returned as a Vector of Ints or Vector of Tuples of Ints.
"""
function standard_derivs(dims::Int)
    if dims == 1
        return Vector{Int}[1, 2]
    elseif dims == 2
        return Vector{Tuple{Int, Int}}[(1, 0), (0, 1), (2, 0), (1, 1), (0, 2)]
    end
end