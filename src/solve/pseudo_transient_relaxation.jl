"""
```
pseudo_transient_relaxation(stategrid::StateGrid, value_functions::NTuple{N, T}, Gs::NTuple{N, T},
    μ::AbstractArray{S}, Σ²::AbstractArray{S}, Δ::S;
    uniform::Bool = false, bc::Vector{Tuple{S, S}} = Vector{Tuple{T, T}}(undef, 0),
    Q = nothing, banded::Bool = false) where {S <: Real, T <: AbstractArray{<: Real}, N}

pseudo_transient_relaxation!(stategrid::StateGrid, new_value_functions::NTuple{N, T},
    value_functions::NTuple{N, T}, Gs::NTuple{N, T},
    μ::AbstractArray{S}, Σ²::AbstractArray{S}, Δ::S;
    uniform::Bool = false, bc::Vector{Tuple{S, S}} = Vector{Tuple{S, S}}(undef, 0),
    L₁ = nothing, L₂ = nothing, Q = nothing,
    banded::Bool = false) where {S <: Real, T <: AbstractArray{<: Real}, N}
```

The homogeneous diffusion must take the form

```
dXₜ / Xₜ = μₜ dt + Σₜ dW_t,
```

where `Σₜ` is a matrix and every component of the n-dimensional Brownian motion `Wₜ`
is assumed to be independent of the other components.

For a broad class of problems, the HJB can be represented in the form

```
0 = μᵥ - G(v)
```

where `G(v)` collects all the terms unrelated to `μᵥ` and thus contains the HJB's nonlinearities.
By Ito's lemma, this equation can be rewritten as

```
v G(v) = ∇v⋅(μₜXₜ) + ½ Tr[(ΣₜXₜ)ᵀ * (H∘v) * (ΣₜXₜ)] + ∂v / ∂t.
```

Because this PDE is derived from an HJB,
it is solved backward in time. The pseudo-transient relaxation method solves this problem
progressively by treating the nonlinear term `G(v)` as constant and solving the linear part
via an implicit Euler step.


Let `A` be the matrix approximation of the infinitessimal generator of an Ito diffusion. Then
the implicit Euler step is
```
-∂v / ∂t ≈ (vₙ₊₁ - vₙ) / dt + G(vₙ) vₙ₊₁ = A vₙ₊₁
(I / dt + diag(G(vₙ)) - A) vₙ₊₁   = vₙ / dt
(I + dt * (diag(G(vₙ)) - A)) vₙ₊₁ = vₙ
```
In general, `A` may be affine such that `A v = L v + b`, hence

```
(I + dt * (diag(G(vₙ)) - A)) vₙ₊₁ = (vₙ + b).
```

It is also convenient to transform `dt` from `(0, ∞)` to `(0, 1)` by
`Δ = dt / (1 + dt) ⇒ dt = Δ / (1 - Δ)`, hence

```
(I + Δ / (1 - Δ) * (diag(G(vₙ)) - A)) vₙ₊₁  = (vₙ + b)
(diag(1 - Δ)  + Δ * (diag(G(vₙ)) - A)) vₙ₊₁ = (1 - Δ) (vₙ + b)
```
"""
# TODO: Fix Σ² to take in a matrix and to not assume it has been squared already
function pseudo_transient_relaxation(stategrid::StateGrid,
                                     value_functions::NTuple{N, T}, Gs::NTuple{N, T},
                                     μ::AbstractArray{S}, Σ²::AbstractArray{S}, Δ::S;
                                     uniform::Bool = false, bc::Vector{Tuple{S, S}} = Vector{Tuple{T, T}}(undef, 0),
                                     Q = nothing, banded::Bool = false) where {S <: Real, T <: AbstractArray{<: Real}, N}
    new_value_functions = map(x -> similar(x), value_functions)
    _, _, err = pseudo_transient_relaxation!(stategrid, new_value_functions, value_functions, Gs, μ, Σ², Δ,
                                             uniform = uniform, bc = bc, Q = Q, banded = banded)
    return new_value_functions, err
end
function pseudo_transient_relaxation!(stategrid::StateGrid, new_value_functions::NTuple{N, T},
                                      value_functions::NTuple{N, T}, Gs::NTuple{N, T},
                                      μ::AbstractArray{S}, Σ²::AbstractArray{S}, Δ::S;
                                      uniform::Bool = false, bc::Vector{Tuple{S, S}} = Vector{Tuple{S, S}}(undef, 0),
                                      L₁ = nothing, L₂ = nothing, Q = nothing,
                                      banded::Bool = false) where {S <: Real, T <: AbstractArray{<: Real}, N}
    @assert (ndims(μ) == ndims(Σ²) && length(μ) == length(Σ²))  "The dimensions of `drift` and `volatility` must match."
    @assert length(value_functions) == length(Gs) "For each value function, we need the associated nonlinear component."
    if ndims(μ) == 1
        return _ptr_1D!(stategrid, new_value_functions, value_functions, Gs, μ, Σ², Δ;
                        uniform = uniform, bc = bc, L₁ = L₁, L₂ = L₂, Q = Q, banded = banded)
    else
        error("not implemented yet")
    end
end

function _ptr_1D!(stategrid::StateGrid, new_value_functions::NTuple{N, T},
                  value_functions::NTuple{N, T}, Gs::NTuple{N, T},
                  μ::AbstractVector{S}, Σ²::AbstractVector{S}, Δ::S; uniform::Bool = false,
                  bc::Vector{Tuple{S, S}} = Vector{Tuple{S, S}}(undef, 0), L₁ = nothing, L₂ = nothing,
                  Q = nothing, banded::Bool = false) where {S <: Real, T <: AbstractVector{<: Real}, N}

    if banded
        @warn "The BandedMatrix concretization for DiffEqOperators does not work for GhostDerivativeOperator types yet. The output is an Array."
    end

    # Set up finite differences and construct the infinitessimal generator
    x = values(stategrid.x)[1]
    n = length(stategrid)
    dx = uniform ?  x[2] - x[1] : nonuniform_grid_spacing(stategrid, bc)

    # If no DiffEqOperator objects are passed, then we assume the user wants a BandedMatrix w/first-order upwind first derivatives
    # and second order central difference second derivatives. Reflecting boundaries are assumed.
    if isnothing(Q) && isnothing(L₁) && isnothing(L₂)
        # Set up the implicit time step
        for (nvf, vf, G) in zip(new_value_functions, value_functions, Gs)
            _default_ptr_1D!(nvf, vf, G, x, dx, n, μ, Σ², Δ)
        end
    else
        if banded
            # Calculate number of diagonals for BandedMatrix representation
            L₁_n_offdiags = if isnothing(L₁)
                # first order upwinded by default
                1
            elseif typeof(L₁.parameters)[3] || L₁.approximation_order > 2
                # If upwinded, need diagonals for stencil length (minus 0th diagonal) on both sides of 0th diagonal
                # If CenteredDifference, approximation order > 2, need whole stencil length for boundaries,
                # and subtract 1 to not double count 0th diagonal
                L₁.stencil_length - 1
            elseif L₁.approximation_order == 2 # CenteredDifference, approximation order = 2
                1 # just need 1st upper and lower diagonals, plus main diagonal b/c handling boundary values
            end
            L₂_n_offdiags = if isnothing(L₂) # see CenteredDifference cases of L₁_ndiags
                1
            elseif L₂.approximation_order == 2
                1
            else
                L₂.stencil_length - 1
            end
        end

        if isnothing(Q) # Assume reflecting boundaries,
            # typical case for models where the volatility vanishes at boundaries and drift point "inward"
            Q = RobinBC((0., 1., 0.), (0., 1., 0.), dx)
        end
        if isnothing(L₁)
            # Filling coefficients inside this function can cause undefineds to be used in the concretization, reason unknown
            L₁ = UpwindDifference(1, 1, dx, n, ones(n)) # So just use 1s first
        end
        L₁.coefficients .= μ .* x
        L₁ = sparse(L₁ * Q)
        L₂ = sparse((Σ² .* x.^2 ./ 2.) * (isnothing(L₂) ? CenteredDifference(2, 2, dx, n) : L₂) * Q)

        # Set up the implicit time step
        if banded
            # Currently, BandedMatrix concretization doesn't work for GhostDerivativeOperator,
            # so form the BandedMatrix from the sparse concretization. The hope is that time is
            # saved during the left divide step.
            min_n_offdiags = min(L₁_n_offdiags, L₂_n_offdiags)
            diags_dict = Dict(i => diag(L₁[1], i) + diag(L₂[1], i) for i in 1:min_n_offdiags)
            for i in -min_n_offdiags:-1
                diags_dict[i] = -Δ * (diag(L₁[1], i) + diag(L₂[1], i)) # multiplied by -Δ here to obtain further speed up
            end
            orig_0th_diag = -Δ .* (Array(diag(L₁[1], 0)) + Array(diag(L₂[1], 0))) # Handle 0th diagonal separately b/c will add terms
            diags_dict[0] = similar(orig_0th_diag)                                # Also convert them to Array rather than SparseVector

            for (nvf, vf, G) in zip(new_value_functions, value_functions, Gs)
                diags_dict[0] .= (1 - Δ) .+ Δ .* G + orig_0th_diag # add nonlinear terms to main diagonal
                A = BandedMatrix(diags_dict...)

                # nvf .= A \ (1. - Δ) .* (vf + b)
                ldiv!(nvf, qr(A), (1. - Δ) .* (vf + b)) # Typically faster b/c fewer allocations, qr also faster than factorize/cholesky
            end
        else
            A = L₁[1] + L₂[1]
            b = L₁[2] + L₂[2]

            for (nvf, vf, G) in zip(new_value_functions, value_functions, Gs)
                nvf .= (Diagonal((1 - Δ) .+ Δ .* G) - (Δ .* A)) \ ((1 - Δ) .* (vf + b))
            end
        end
    end

    return new_value_functions, value_functions
end

function _default_ptr_1D!(nvf::T, vf::T, G::T, x::AbstractVector{S},
                          dx::AbstractVector{S}, n::Int, μ::AbstractVector{S}, Σ²::AbstractVector{S},
                          Δ::S) where {N <: Int, T <: AbstractVector{<: Real}, S <: Real}

    # Process Σ² matrix
    Σ²in = similar(Σ²)
    Σ²in[2:n - 1] .= Σ²[2:n - 1] .* x[2:n - 1].^2 ./ 2. # In non-uniform case, we utilize Fornberg weights, so just calculate
    Σ²in[1] = 0.                                        # the raw coeficients.
    Σ²in[n] = 0.

    # Populate diagonals and construct BandedMatrix
    DD, D0, DU = _centered_difference_reflecting_bc_weights(2, x, -Δ .* Σ²in) # Initialize diagonals for centered difference operator
    μx         = μ .* x
    DU       .-= Δ .* (max.( μx[1:n - 1], 0.) ./ dx[1:n - 1]) # up diagonal
    DD       .-= Δ .* (max.(-μx[2:n],     0.) ./ dx[2:n])     # down diagonal, note FD scheme makes DD negative, multiplied by negative drift ⇒ positive, then subtracted ⇒ negative

    D0          .+= (1 - Δ) .+ Δ .* G
    D0[1:n - 1] .+= Δ .* (max.( μx[1:n - 1], 0.) ./ dx[1:n - 1]) # Also have to add to the main diagonal
    D0[2:n]     .+= Δ .* (max.(-μx[2:n],     0.) ./ dx[2:n])     # for the first-order FD operator

    A             = BandedMatrix(0 => D0, 1 => DU, -1 => DD)


    # Solve linear system
    # nvf .= A \ ((1. - Δ) .* vf)
    ldiv!(nvf, qr(A), (1. - Δ) .* vf) # Typically faster b/c fewer allocations, qr also faster than factorize/cholesky
end

function _default_ptr_1D!(nvf::T, vf::T, G::T, x::AbstractVector{S},
                          dx::S, n::Int, μ::AbstractVector{S}, Σ²::AbstractVector{S},
                          Δ::S) where {N <: Int, T <: AbstractVector{<: Real}, S <: Real}

    # Process Σ² matrix
    Σ²in = similar(Σ²)                                           # In non-uniform case, for 2:n - 1, want to divide by the
    Σ²in[2:n - 1] .= Σ²[2:n - 1] .* x[2:n - 1].^2 ./ (2 .* dx^2) # forward and backward difference, but for the boundaries,
    Σ²in[1] = 0.                                                 # we impose reflecting boundaries.
    Σ²in[n] = 0.                                                 # Note that dx is length (n + 1).

    # Populate diagonals and construct BandedMatrix
    μx = μ .* x
    DU = -Δ .* (max.( μx[1:n - 1], 0.) ./ dx + Σ²in[1:n - 1]) # up diagonal
    DD = -Δ .* (max.(-μx[2:n],     0.) ./ dx + Σ²in[2:n])     # down diagonal, note FD scheme makes DD negative, multiplied by negative drift ⇒ positive, then subtracted ⇒ negative

    D0            = (1 - Δ) .+ Δ .* G
    D0[1:n - 1] .-= DU
    D0[2:n]     .-= DD

    A = BandedMatrix(0 => D0, 1 => DU, -1 => DD)

    # Solve linear system
    # nvf .= A \ ((1. - Δ) .* vf)
    ldiv!(nvf, qr(A), (1. - Δ) .* vf) # Typically faster b/c fewer allocations, qr also faster than factorize/cholesky
end
