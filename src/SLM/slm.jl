# In case more abstraction is needed
abstract type AbstractSLM{T} end

"""
```
SLM
```

is a port of Shape Language Modeling (SLM) by John D'Errico,
who implements least squares spline modeling for curve fitting.

See https://www.mathworks.com/matlabcentral/fileexchange/24443-slm-shape-language-modeling for details about the SLM toolbox.

Note that only the features described in the Keywords section have been ported for now.
Other features may be added on as-needed basis.

The main constructor has the form

```
SLM(x::AbstractVector{T}, y::AbstractVector{T}; calculate_stats::Bool = false,
    verbose::Symbol = :low, kwargs...) where {T <: Real}
```

### Inputs
- The vectors `x` and `y` are the points with which the least-squares spline will be fit.

### Keywords
- `degree::Int = 3`: Degree of the spline. A degree 3 spline is a piecewise cubic Hermite spline.
- `scaling::Bool = true`: If true, scale the `y` values and coefficients to avoid numerical issues
- `knots::Int = 6`: Number of knots for the spline
- `C2::Bool = true`: If true, enforce that the spline satisfies C2 continuity
- `λ::T = 1e-4`: Regularization parameter for how smooth the spline is (smaller λ ⇒ smoother spline)
- `left_value::T = NaN`: Controls the spline's value at the left end point. If it is a `NaN`, then the
    spline's value at the left end point is not controlled, i.e. it can be any number.
- `right_value::T = NaN`: Controls the spline's value at the right end point. If it is a `NaN`, then the
    spline's value at the right end point is not controlled, i.e. it can be any number.
- `min_value::T = NaN`: Sets the spline's global minimum value. If it is a `NaN`, then
    no minimum value is imposed.
- `max_value::T = NaN`: Set the spline's global maximum value. If it is a `NaN`, then the
    no maximum value is imposed.
- `min_max_sample_points::AbstractVector{T} =
    [.017037, .066987, .14645, .25, .37059, .5, .62941, .75, .85355, .93301, .98296]`:
    Sample points used to enforce global min/max values. The default points are Chebyshev nodes.
- `increasing::Bool = false`: If true, the spline will monotonically increase over the interpolation domain.
- `decreasing::Bool = false`: If true, the spline will monotonically decrease over the interpolation domain.
- `increasing_intervals::AbstractMatrix{T} = []`: If nonempty, each row of the n × 2 matrix `increasing_intervals` specifies
    the left and right end points of an interval over which the spline monotonically increases.
- `decreasing_intervals::AbstractMatrix{T} = []`: If nonempty, each row of the n × 2 matrix `decreasing_intervals` specifies
    the left and right end points of an interval over which the spline monotonically decreases.
- `concave_up_intervals::AbstractMatrix{T} = []`: If nonempty, each row of the n × 2 matrix `concave_up_intervals` specifies
    the left and right end points of an interval over which the spline is concave up (i.e. convex in the normal sense).
- `concave_down_intervals::AbstractMatrix{T} = []`: If nonempty, each row of the n × 2 matrix `concave_down_intervals` specifies
    the left and right end points of an interval over which the spline is concave down (i.e. concave in the normal sense).
- `init::AbstractVector{T} = []`: If nonempty, `init` is just as an initial guess for the coefficients of the spline.
- `calculate_stats::Bool = false`: If true, calculate statistics about the spline regression (e.g. R²). Currently,
    no statistics are calculated, so setting `calculate_stats` to true does nothing.
- `verbose::Symbol`: Verbosity of information printed during construction of an SLM object.
"""
mutable struct SLM{T} <: AbstractSLM{T}
    stats::NamedTuple
    type::Symbol
    x::AbstractVector{T}
    y::AbstractVector{T}
    knots::AbstractVector{T}
    coef::AbstractArray{T}
    extrapolation::Symbol
end

function Base.show(io::IO, slm::AbstractSLM{T}) where {T <: Real}
    @printf io "SLM with element type %s\n" string(T)
    @printf io "degree: %i\n" get_stats(slm)[:degree]
    @printf io "knots:  %i\n" length(get_stats(slm)[:knots])
end

# Access functions
get_stats(slm::AbstractSLM) = slm.stats
get_knots(slm::AbstractSLM) = slm.knots
get_type(slm::AbstractSLM) = slm.type
get_x(slm::AbstractSLM) = slm.x
get_y(slm::AbstractSLM) = slm.y
get_coef(slm::AbstractSLM) = slm.coef
get_extrapolation(slm::AbstractSLM) = slm.extrapolation
eltype(slm::AbstractSLM) = slm.stats

function getindex(slm::AbstractSLM, x::Symbol)
    if x == :stats
        get_stats(slm)
    elseif x == :knots
        get_knots(slm)
    elseif x == :x
        get_x(slm)
    elseif x == :y
        get_y(slm)
    elseif x == :coef
        get_coef(slm)
    elseif x == :type
        get_type(slm)
    elseif x == :extrapolation || x == :extrap
        get_extrapolation(slm)
    else
        error("type " * typeof(slm) * " has no field " * string(x))
    end
end

# Main user interface for constructing an SLM object
function SLM(x::AbstractVector{T}, y::AbstractVector{T}; calculate_stats::Bool = false,
             verbose::Symbol = :low, kwargs...) where {T <: Real}

    @assert length(x) == length(y) "x and y must be the same size"
    if verbose == :high
        calculate_stats = true # Statistics will be calculated if verbose is high
    end
    kwargs = Dict{Symbol, Any}(kwargs)

    if haskey(kwargs, :increasing_intervals)
        @assert size(kwargs[:increasing_intervals], 2) == 2 "The matrix for the keyword increasing_intervals must be n × 2."
    end
    if haskey(kwargs, :decreasing_intervals)
        @assert size(kwargs[:decreasing_intervals], 2) == 2 "The matrix for the keyword decreasing_intervals must be n × 2."
    end
    if haskey(kwargs, :concave_up_intervals)
        @assert size(kwargs[:concave_up_intervals], 2) == 2 "The matrix for the keyword concave_up_intervals must be n × 2."
    end
    if haskey(kwargs, :concave_down_intervals)
        @assert size(kwargs[:concave_down_intervals], 2) == 2 "The matrix for the keyword concave_down_intervals must be n × 2."
    end

    # Remove nans
    to_remove = isnan.(x) .| isnan.(y)
    if any(to_remove)
        x = x[to_remove]
        y = y[to_remove]

        if haskey(kwargs, :weights)
            error("Weights are not implemented currently.")
            kwargs[:weights] = kwargs[:weights][to_remove]
        end
    end

    # Additional checks
    if haskey(kwargs, :weights)
        @assert length(kwargs[:weights]) == length(x)
    end

    # Add default keyword arguments
    default_slm_kwargs!(kwargs, T)

    # Scale y. This updates the kwargs
    ŷ = scale_problem!(x, y, kwargs)

    slm = if kwargs[:degree] == 0
        error("degree 0 has not been implemented")
    elseif kwargs[:degree] == 1
        error("degree 1 has not been implemented")
    elseif kwargs[:degree] == 3
        SLM_cubic(x, ŷ, kwargs[:y_scale], kwargs[:y_shift]; init = kwargs[:init],
                  nk = kwargs[:knots], C2 = kwargs[:C2], λ = kwargs[:λ], increasing = kwargs[:increasing],
                  decreasing = kwargs[:decreasing], increasing_intervals = kwargs[:increasing_intervals],
                  decreasing_intervals = kwargs[:decreasing_intervals],
                  concave_up = kwargs[:concave_up], concave_down = kwargs[:concave_down],
                  concave_up_intervals = kwargs[:concave_up_intervals],
                  concave_down_intervals = kwargs[:concave_down_intervals],
                  left_value = kwargs[:left_value], right_value = kwargs[:right_value],
                  min_value = kwargs[:min_value], max_value = kwargs[:max_value],
                  min_max_sample_points = kwargs[:min_max_sample_points],
                  use_sparse = kwargs[:use_sparse], use_lls = kwargs[:use_lls])
    else
        error("degree $(kwargs[:degree]) has not been implemented")
    end

    if calculate_stats
        # Need to write a function that calculates stats like total df or R²
    end

    if kwargs[:scaling]
        coef = get_coef(slm)
        coef[:, 1] .-= kwargs[:y_shift]
        coef       ./= kwargs[:y_scale]
    end

    if verbose == :high
        @info "Model Statistics Report"
        println("Number of data points:      $(length(y))")
        println("Scale factor applied to y   $(y_scale)")
        println("Shift applied to y          $(y_shift)")
        # println("Total degrees of freedom:   $(get_stats(slm)[:total_df])")
        # println("Net degrees of freedom:     $(get_stats(slm)[:net_df])")
        # println("R-squared:                  $(get_stats(slm)[:R2])")
        # println("Adjusted R-squared:         $(get_stats(slm)[:R2_adj])")
        # println("RMSE:                       $(get_stats(slm)[:RMSE])")
        # println("Range of prediction errors: $(get_stats(slm)[:error_range])")
        # println("Error quartiles (25%, 75%): $(get_stats(slm)[:quartiles])")
    end

    return slm
end

function SLM_cubic(x::AbstractVector{T}, y::AbstractVector{T}, y_scale::T, y_shift::T;
                   init::AbstractVector{T} = Vector{T}(undef, 0),
                   nk::Int = 6, C2::Bool = true, λ::T = 1e-4, increasing::Bool = false, decreasing::Bool = false,
                   increasing_intervals::AbstractMatrix{T} = Matrix{T}(undef, 0, 0),
                   decreasing_intervals::AbstractMatrix{T} = Matrix{T}(undef, 0, 0),
                   concave_up::Bool = false, concave_down::Bool = false,
                   concave_up_intervals::AbstractMatrix{T} = Matrix{T}(undef, 0, 0),
                   concave_down_intervals::AbstractMatrix{T} = Matrix{T}(undef, 0, 0),
                   left_value::T = NaN, right_value::T = NaN,
                   min_value::T = NaN, max_value::T = NaN,
                   min_max_sample_points::AbstractVector{T} = [.017037, .066987, .1465, .25, .37059,
                                                               .5, .62941, .75, .85355, .93301, .98296],
                   use_sparse::Bool = false, use_lls::Bool = true) where {T <: Real}

    nₓ = length(x)

    # Choose knots
    knots = choose_knots(nk, x)
    dknots = diff(knots)
    if any(dknots .== 0.)
        error("Knots must be distinct.")
    end

    ### Calculate coefficients

    ## Set up
    nc = 2 * nk
    Mineq = zeros(0, nc)
    rhsineq = Vector{T}(undef, 0)
    Meq = zeros(0, nc)
    rhseq = Vector{T}(undef, 0)

    ## Build design matrix

    # Bin data so that xbin has nₓ and xbin specifies into which bin each x value falls
    xbin = bin_sort(x, knots)

    # design matrix
    Mdes = construct_design_matrix(x, knots, dknots, xbin, nₓ, nk, nc; use_sparse = use_sparse)
    rhs = y

    ## Regularizer
    Mreg = construct_regularizer(dknots, nk; use_sparse = use_sparse)
    rhsreg = zeros(T, nk)

    ## C2 continuity across knots
    if C2
        Meq, rhseq = C2_matrix(nk, nc, dknots, Meq, rhseq; use_sparse = use_sparse)
    end

    ## Left and right values
    if !isnan(left_value)
        Meq, rhseq = set_left_value(left_value, nc, Meq, rhseq; use_sparse = use_sparse)
    end

    if !isnan(right_value)
        Meq, rhseq = set_right_value(right_value, nc, nk, Meq, rhseq; use_sparse = use_sparse)
    end

    # Global minimum and maximum values
    if !isnan(min_value)
        Mineq, rhsineq = set_min_value(min_value, nk, nc, dknots, Mineq, rhsineq; sample_points = min_max_sample_points,
                                       use_sparse = use_sparse)
    end

    if !isnan(max_value)
        Mineq, rhsineq = set_max_value(max_value, nk, nc, dknots, Mineq, rhsineq; sample_points = min_max_sample_points,
                                       use_sparse = use_sparse)
    end

    ## Monotonicity restrictions
    @assert !(increasing && decreasing) "Only one of increasing and decreasing can be true"

    monotone_settings = Vector{NamedTuple{(:knotlist, :increasing), Tuple{Tuple{Int, Int}, Bool}}}(undef, 0)
    total_monotone_intervals = 0

    # Monotone increasing
    if increasing
        @assert isempty(increasing_intervals) && isempty(decreasing_intervals) "The spline cannot be monotone increasing and " *
            "have nonempty entries for the keywords increasing_intervals and/or decreasing_intervals"
        total_monotone_intervals += monotone_increasing!(monotone_settings, nk)
    end

    # Increasing intervals: nx2 array where each row is an interval over which we have increasing
    if !isempty(increasing_intervals)
        total_monotone_intervals += increasing_intervals_info!(monotone_settings, knots, increasing_intervals, nk)
    end

    # Monotone decreasing
    if decreasing
        @assert isempty(increasing_intervals) && isempty(decreasing_intervals) "The spline cannot be monotone decreasing and " *
            "have nonempty entries for the keywords increasing_intervals and/or decreasing_intervals"
        total_monotone_intervals += monotone_decreasing!(monotone_settings, nk)
    end

    # Decreasing intervals
    if !isempty(decreasing_intervals)
        total_monotone_intervals += decreasing_intervals_info!(monotone_settings, knots, decreasing_intervals, nk)
    end

    # Add inequalities enforcing monotonicity
    if !isempty(monotone_settings)
        Mineq, rhsineq = construct_monotonicity_matrix(monotone_settings, nc, nk, dknots, total_monotone_intervals, Mineq, rhsineq;
                                                       use_sparse = use_sparse)
    end

    ## Concavity
    @assert !(concave_up && concave_down) "Only one of concave_up and concave_down can be true"

    curvature_settings = Vector{NamedTuple{(:concave_up, :range), Tuple{Bool, Vector{T}}}}(undef, 0)

    if concave_up
        @assert isempty(concave_up_intervals) && isempty(concave_down_intervals) "The spline cannot be concave up and " *
            "have nonempty entries for the keywords concave_up_intervals and/or concave_down_intervals"
        concave_up_info!(curvature_settings)
    end

    if concave_down
        @assert isempty(concave_up_intervals) && isempty(concave_down_intervals) "The spline cannot be concave down and " *
            "have nonempty entries for the keywords concave_up_intervals and/or concave_down_intervals"
        concave_down_info!(curvature_settings)
    end

    if !isempty(concave_up_intervals)
        concave_up_intervals_info!(curvature_settings, concave_up_intervals)
    end

    if !isempty(concave_down_intervals)
        concave_down_intervals_info!(curvature_settings, concave_down_intervals)
    end

    # Add inequalities enforcing curvature
    if !isempty(curvature_settings)
        Mineq, rhsineq = construct_curvature_matrix(curvature_settings, nc, nk, knots, dknots, Mineq, rhsineq; use_sparse = use_sparse)
    end

    # scale equalities for unit absolute row sum
    if !isempty(Meq)
        rs = Diagonal(vec(1. ./ sum(abs.(Meq), dims = 2)))
        Meq = rs * Meq
        rhseq = rs * rhseq
    end

    # scale equalities for unit absolute row sum
    if !isempty(Mineq)
        rs = Diagonal(vec(1. ./ sum(abs.(Mineq), dims = 2)))
        Mineq = rs * Mineq
        rhsineq = rs * rhsineq
    end

    # Currently, we only implement the standard regularizer parameter, while
    # SLM allows matching a specified RMSE and cross-validiation, too.
    coef = solve_slm_system(Mdes, rhs, Mreg, rhsreg, λ,
                            Meq, rhseq, Mineq, rhsineq; init = init,
                            use_lls = use_lls)
    coef = reshape(coef, nk, 2)

    ## Calculate model statistics
    # Currently, we just add degree and knots to the statistics NamedTuple
    stats = (degree = 3, knots = knots,
             y_scale = y_scale, y_shift = y_shift)

    # Unpack coefficients into the result structure
    return SLM{T}(stats, :cubic, x, y, knots, coef, :none)
end
