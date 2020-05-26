"""
```
AnSchorfheide{T} <: AbstractRepModel{T}
```

The `AnSchorfheide` type defines the structure of the simple New Keynesian DSGE
model described in 'Bayesian Estimation of DSGE Models' by Sungbae An and Frank
Schorfheide.

### Fields

#### Parameters and Steady-States
* `parameters::Vector{AbstractParameter}`: Vector of all time-invariant model
  parameters.

* `keys::OrderedDict{Symbol,Int}`: Maps human-readable names for all model
  parameters to their indices in `parameters`.

#### Inputs to Measurement and Equilibrium Condition Equations

The following fields are dictionaries that map human-readable names to row and
column indices in the matrix representations of of the measurement equation and
equilibrium conditions.

* `endogenous_states::OrderedDict{Symbol,Int}`: Maps each state to a column in
  the measurement and equilibrium condition matrices.

* `exogenous_shocks::OrderedDict{Symbol,Int}`: Maps each shock to a column in
  the measurement and equilibrium condition matrices.

* `endogenous_states_augmented::OrderedDict{Symbol,Int}`: Maps lagged states to
  their columns in the measurement and equilibrium condition equations. These
  are added after `gensys` solves the model.

* `observables::OrderedDict{Symbol,Int}`: Maps each observable to a row in the
  model's measurement equation matrices.

* `pseudo_observables::OrderedDict{Symbol,Int}`: Maps each pseudo-observable to
  a row in the model's pseudo-measurement equation matrices.

#### Model Specifications and Settings

* `spec::String`: The model specification identifier, \"an_schorfheide\", cached
  here for filepath computation.

* `subspec::String`: The model subspecification number, indicating that some
  parameters from the original model spec (\"ss0\") are initialized
  differently. Cached here for filepath computation.

* `settings::Dict{Symbol,Setting}`: Settings/flags that affect computation
  without changing the economic or mathematical setup of the model.

* `test_settings::Dict{Symbol,Setting}`: Settings/flags for testing mode

#### Other Fields

* `rng::MersenneTwister`: Random number generator. Can be is seeded to ensure
  reproducibility in algorithms that involve randomness (such as
  Metropolis-Hastings).

* `testing::Bool`: Indicates whether the model is in testing mode. If `true`,
  settings from `m.test_settings` are used in place of those in `m.settings`.

* `observable_mappings::OrderedDict{Symbol,Observable}`: A dictionary that
  stores data sources, series mnemonics, and transformations to/from model units.
  DSGE.jl will fetch data from the Federal Reserve Bank of
  St. Louis's FRED database; all other data must be downloaded by the
  user. See `load_data` and `Observable` for further details.

* `pseudo_observable_mappings::OrderedDict{Symbol,PseudoObservable}`: A
  dictionary that stores names and transformations to/from model units. See
  `PseudoObservable` for further details.
"""
mutable struct Li2020{T} <: AbstractNLCTModel{T}
    parameters::ParameterVector{T}                         # vector of all time-invariant model parameters
    keys::OrderedDict{Symbol,Int}                          # human-readable names for all the model
                                                           # parameters and steady-states

    endogenous_states::OrderedDict{Symbol,Int}             # these fields used to create matrices in the
    exogenous_shocks::OrderedDict{Symbol,Int}              # measurement and equilibrium condition equations.
    endogenous_states_augmented::OrderedDict{Symbol,Int}   #
    observables::OrderedDict{Symbol,Int}                   #
    pseudo_observables::OrderedDict{Symbol,Int}            #

    spec::String                                           # Model specification number (eg "m990")
    subspec::String                                        # Model subspecification (eg "ss0")
    settings::Dict{Symbol,Setting}                         # Settings/flags for computation
    test_settings::Dict{Symbol,Setting}                    # Settings/flags for testing mode
    rng::MersenneTwister                                   # Random number generator
    testing::Bool                                          # Whether we are in testing mode or not

    observable_mappings::OrderedDict{Symbol, Observable}
    pseudo_observable_mappings::OrderedDict{Symbol, PseudoObservable}
end

description(m::Li2020) = "Julia implementation of model defined in 'Public Liquidity and Financial Crises' (2020) by Wenhao Li: Li2020, $(m.subspec)"

"""
`init_model_indices!(m::Li2020)`

Arguments:
`m:: Li2020`: a model object

Description:
Initializes indices for all of `m`'s states, shocks, and observables.
"""
function init_model_indices!(m::AnSchorfheide)
    # Endogenous states
    endogenous_states = collect([:w])

    # Exogenous shocks
    exogenous_shocks = collect([:K_sh, :N_sh]) # capital shock K, liquidity shock N

    # Additional states that can be calculated after a model's solution
    endogenous_states_augmented = []

    # Observables
    observables = keys(m.observable_mappings)

    # Pseudo-observables
    pseudo_observables = keys(m.pseudo_observable_mappings)

    for (i,k) in enumerate(endogenous_states);           m.endogenous_states[k]           = i end
    for (i,k) in enumerate(exogenous_shocks);            m.exogenous_shocks[k]            = i end
    for (i,k) in enumerate(endogenous_states_augmented); m.endogenous_states_augmented[k] = i+length(endogenous_states) end
    for (i,k) in enumerate(observables);                 m.observables[k]                 = i end
    for (i,k) in enumerate(pseudo_observables);          m.pseudo_observables[k]          = i end
end

function Li2020(subspec::String = "ss0";
                custom_settings::Dict{Symbol, Setting} = Dict{Symbol, Setting}(),
                testing = false)

    # Model-specific specifications
    spec               = split(basename(@__FILE__),'.')[1]
    subspec            = subspec
    settings           = Dict{Symbol,Setting}()
    test_settings      = Dict{Symbol,Setting}()
    rng                = MersenneTwister(0)

    # initialize empty model
    m = Li2020{Float64}(
            # model parameters and steady state values
            Vector{AbstractParameter{Float64}}(), Vector{Float64}(),

            # model indices
            OrderedDict{Symbol,Int}(), OrderedDict{Symbol,Int}(), OrderedDict{Symbol,Int}(), OrderedDict{Symbol,Int}(),
            OrderedDict{Symbol,Int}(),

            spec,
            subspec,
            settings,
            test_settings,
            rng,
            testing,
            OrderedDict{Symbol,Observable}(),
            OrderedDict{Symbol,PseudoObservable}())

    # Set settings
    model_settings!(m)
    # default_test_settings!(m)
    for custom_setting in values(custom_settings)
        m <= custom_setting
    end

    # Set observable and pseudo-observable transformations
    # init_observable_mappings!(m)
    # init_pseudo_observable_mappings!(m)

    # Initialize parameters
    init_parameters!(m)

    init_model_indices!(m)
    init_subspec!(m)

    return m
end


"""
```
init_parameters!(m::Li2020)
```
Initializes the model's parameters.
"""
function init_parameters(m::Li2020)
    # Productivity
    m <= parameter(:aH, 0.15, (0., Inf), (0., 1e3), ModelConstructors.Untransformed(), Uniform(0., 1e3), fixed = false, "Banker's productivity")
    m <= parameter(:aL, 0.15, (0., Inf), (0., 1e3), ModelConstructors.Untransformed(), Uniform(0., 1e3), fixed = false, "Household's productivity")

    # Bank run and fire sales
    m <= parameter(:λ, 0.15, (0., 1.), (0., 1.), ModelConstructors.Untransformed(), Uniform(0., 1.), fixed = false, "Probability of liquidity shock")
    m <= parameter(:β, 0.15, (0., 1.), (0., 1.), ModelConstructors.Untransformed(), Uniform(0., 1.), fixed = false,
                   "Probability of running on a deposit account")
    m <= parameter(:α, 0.15, (0., 1.), (0., 1.), ModelConstructors.Untransformed(), Uniform(0., 1.), fixed = false,
                   "Illiquidity discount on capital during fire sale")
    m <= parameter(:ϵ, 1e-3, (0., 1.), (0., 1.), ModelConstructors.Untransformed(), Uniform(0., 1.), fixed = false,
                   "Fraction of remaining wealth for bankers after bankruptcy")
    m <= parameter(:θ, 1e-5, (0., 1.), (0., 1.), ModelConstructors.Untransformed(), Uniform(0., 1.), fixed = false,
                   "Probability of non-zero exposure to liquidity shock")

    # Shadow value of liquidity
    m <= parameter(:π, 0.19, (0., 1.), (0., 1.), ModelConstructors.Untransformed(), Uniform(0., 1.), fixed = false,
                   "Illiquidity discount on illiquid safe asset")

    # Macro parameters
    m <= parameter(:δ, 0.1, (0., 1.), (0., 1.), ModelConstructors.Untransformed(), Uniform(0., 1.), fixed = false, "Depreciation rate of capital")
    m <= parameter(:ρ, 0.04, (0., Inf), (0., 1e3.), ModelConstructors.Untransformed(), Uniform(0., 1e3), fixed = false, "Discount rate")
    m <= parameter(:σK, 0.033, (0., Inf), (0., 1e3.), ModelConstructors.Untransformed(), Uniform(0., 1e3), fixed = false,
                   "Volatility of capital shocks")
    m <= parameter(:χ, 3., (0., Inf), (0., 1e3.), ModelConstructors.Untransformed(), Uniform(0., 1e3), fixed = false,
                   "Adjustment cost of internal investment function")

    # Stationary distribution
    m <= parameter(:η, 0.05, (0., 1.), (0., 1.), ModelConstructors.Untransformed(), Uniform(0., 1.), fixed = false,
                   "Rate of retirement for bankers")
end



"""
```
model_settings!(m::Li2020)
```
creates the model's settings.
"""
function model_settings!(m::Li2020)

    # Numerical settings
    m <= Setting(:v₀, 3e-8, "Parameter for damping function")
    m <= Setting(:vp_function, x -> get_setting(m, :v₀) ./ x, "Dampling function to avoid corners")
    m <= Setting(:N, 100, "Grid size")
    m <= Setting(:max_iterations, 12, "Maximum number of fixed point iterations")

    # Calibration targets
    m <= Setting(:avg_gdp, 0.145, "Average GDP")
    m <= Setting(:liq_gdp_ratio, 0.39, "Average Liquidity/GDP ratio in the data")

    # Simulation settings
    m <= Setting(:dt, 1. / 12., "Simulation interval as a fraction of a 1 year")

    # ODE integrator
    m <= Setting(:ode_integrator, Tsit5(), "Numerical ODE integrator for no-jump solution")
end