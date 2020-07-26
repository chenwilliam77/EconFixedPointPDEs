"""
```
```

The homogeneous diffusion must take the form

```
dXₜ / Xₜ = μₜ dt + Σₜ⋅dW_t,
```

where `Σₜ` is a column vector and every component of the n-dimensional Brownian motion `Wₜ`
is assumed to be independent of the other components. This assumption can be relaxed but
involves additional computation from calculating the covariance matrix.

For a broad class of problems, the HJB can be represented in the form

```
0 = μᵥ - G(v)
```

where `G(v)` collects all the terms unrelated to `μᵥ` and thus contains the HJB's nonlinearities.
By Ito's lemma, this equation can be rewritten as

```
v G(v) = ∇v⋅(μₜXₜ) + ½ Tr[diag(ΣₜXₜ) * (H∘v) * diag(ΣₜXₜ)] + ∂v / ∂t.
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
    dx = uniform ?  x[2] - x[1] : nonuniform_ghost_node_grid(stategrid, bc)
    if isnothing(Q) # Assume reflecting boundaries,
                    # typical case for models where the volatility vanishes at boundaries and drift point "inward"
        Q = RobinBC((0., 1., 0.), (0., 1., 0.), dx)
    end
    concretization = banded ? BandedMatrix : sparse
    if isnothing(L₁)
        L₁ = UpwindDifference(1, 1, dx, n, fill(1., n)) # Filling coefficients can cause undefineds to be used in the concretization, reason unknown
    end
    L₁.coefficients .= μ .* x
    L₁ = concretization(L₁ * Q)
    L₂ = concretization((Σ² .* x.^2 ./ 2.) * (isnothing(L₂) ? CenteredDifference(2, 2, dx, n) : L₂) * Q)

    A = L₁[1] + L₂[1]
    b = L₁[2] + L₂[2]

    # Set up the implicit time step
    for (nvf, vf, G) in zip(new_value_functions, value_functions, Gs)
        nvf .= (Diagonal((1 - Δ) .+ Δ .* G) - (Δ .* A)) \ ((1 - Δ) .* (vf + b))
    end

    return new_value_functions, value_functions
end

# Translation of code from Yuliy Sannikov, payoff_policy_growth, with the modification that instead of S, we plug in S²
function upwind_parabolic_pde(X, R, μ, Σ², G, V, dt_div_1pdt)
    N = length(X)
    dX = diff(X)

    # Perform upwind scheme w/centered difference on diffusion term
    Σ²0 = zeros(N)
    Σ²0[2:N-1] .= Σ²[2:N-1] ./ (dX[1:N-2] + dX[2:N-1]) # approx Σ² / (2 * dx): this term is the Σ²/2 coefficient
    DU = -(max.(μ[1:N-1], 0.) + Σ²0[1:N-1]) ./ dX .* dt_div_1pdt # up diagonal, μ divided by dX, Σ²0 is Σ² / (2 * dx^2), th
    DD = -(max.(-μ[2:N], 0.) + Σ²0[2:N]) ./ dX .* dt_div_1pdt # down diagonal, note should be negative b/c FD scheme makes DD negative, multiplied by negative drift ⇒ positive, then subtracted ⇒ negative
    # observe: Σ² and μ are zero at endpoints, hence Σ²0 zero at endpts too ->
    # boundary conditions for our PDE

    D0 = (1 - dt_div_1pdt) .* ones(N) + dt_div_1pdt .* R # diagonal
    D0[1:N-1] = D0[1:N-1] - DU
    D0[2:N] = D0[2:N] - DD # subtract twice b/c centered diff
    A = spdiagm(0 => D0, 1 => DU, -1 => DD) # + spdiagm(DU,1,N,N) + spdiagm(DD[1:N-1],-1,N,N)
    F = A \ (G .* dt_div_1pdt + V .* (1 - dt_div_1pdt)) # solve linear system

#=    # Equivalent to this code, which constructs the first and second finite difference matrices separately
    DU1 = zeros(N)
    DU2 = zeros(N)
    DD1 = zeros(N)
    DD2 = zeros(N)
    D01 = zeros(N)
    D02 = zeros(N)
    DU1[2:N] = max.(μ[1:N - 1], 0.) ./ dX
    DU2[2:N] = Σ²0[1:N - 1] ./ dX
    DD1[1:N - 1] = max.(-μ[2:N], 0.) ./ dX
    DD2[1:N - 1] = Σ²0[2:N] ./ dX
    D01[1:N - 1] .= -DU1[2:N]
    D01[2:N] .-= DD1[1:N - 1]
    D02[1:N - 1] .= -DU2[2:N]
    D02[2:N] .-= DD2[1:N - 1]
    L1 = spdiagm(0 => D01, -1 => DD1[1:N - 1], 1 => DU1[2:N])
    L2 = spdiagm(0 => D02, -1 => DD2[1:N - 1], 1 => DU2[2:N])
    Acheck = spdiagm(0 => (1 - dt_div_1pdt) .* ones(N) + dt_div_1pdt .* R) - dt_div_1pdt .* (L1 + L2)=#

    return F
end