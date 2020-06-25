using Test, OrderedCollections
include(joinpath(dirname(@__FILE__), "../../src/includeall.jl"))

## Check direct implementation of functional iteration loop matches output from solve
# COPY THIS SOLVE TEST TO THE TEST FOR LI 2020 AS WELL THAT IT ACTUALLY SOLVES
# ALSO NOW CHECK THAT SOLVE CREATES THE SAME RESULT AS THE DIRECT IMPLEMENTATION
# Initialize
m = Li2020()
stategrid, funcvar, derivs, endo = initialize!(m)
func_iter = eqcond(m)
θ = parameters_to_named_tuple(get_parameters(m))

# Get settings for the loop
max_iter     = get_setting(m, :max_iter)        # maximpum number of functional loops
verbose      = :high
func_tol     = get_setting(m, :tol)             # convergence tolerance
error_method = get_setting(m, :error_method)    # method for calculating error at end of each loop
func_errors  = Vector{Float64}(undef, max_iter) # track error for each iteration
proposal_funcvar = deepcopy(funcvar)            # so we can calculate difference between proposal and current values

# Set update method
um = (new, old) -> average_update(new, old, get_setting(m, :learning_rate))

# Start loop
total_time = 0.
error_vars = Vector{Symbol}(undef, 2)
error_vars[1] = :p
error_vars[2] = :Q̂

for iter in 1:max_iter
    begin_time = time_ns()

    # Get a new guess
    new_funcvar = func_iter(stategrid, funcvar, derivs, endo, θ; verbose = verbose)

    # Update the guess
    for (k, v) in proposal_funcvar
        proposal_funcvar[k] = um(new_funcvar[funcvar_dict[k]], v) # um = update_method
    end

    # Calculate errors
    func_errors[iter] = calculate_func_error(proposal_funcvar, funcvar, error_method;
                                             vars = error_vars)

    spaces1, spaces2, spaces3 = if iter < 10
        repeat(" ", 16), repeat(" ", 14), repeat(" ", 5)
    elseif iter < 100
        repeat(" ", 17), repeat(" ", 15), repeat(" ", 6)
    else
        repeat(" ", 18), repeat(" ", 16), repeat(" ", 7)
    end

    println("Iteration $(iter), current error:            $(func_errors[iter])")
    if verbose == :high
        for k in error_vars
            indiv_funcvar_err = calculate_func_error(proposal_funcvar[k], funcvar[k], error_method)
            indiv_space = " " ^ (27 - length(string(k)) + 1)
            println("Error for $(k):" * indiv_space * string(indiv_funcvar_err))
        end
    else
        println("")
    end

    loop_time = (time_ns() - begin_time) / 6e10 # 60 * 1e9 = 6e10
    global total_time += loop_time
    expected_time_remaining = (max_iter - iter) * loop_time
    println(verbose, :high, "Duration of loop (min):" * spaces1 * "$(round(loop_time, digits = 5))")
    println("Total elapsed time (min):" * spaces2 * "$(round(total_time, digits = 5))")
    println(verbose, :high, "Expected max remaining time (min):" * spaces3 * "$(round(expected_time_remaining, digits = 5))")
    println("\n")

    # Convergence?
    for (k, v) in proposal_funcvar
        funcvar[k] .= v
    end

    if func_errors[iter] < func_tol
        if verbose != :none
            println("Convergence achieved! Final round error: $(func_errors[iter])")
        end
        break
    end
end

println("Calculating remaining variables . . .")
aug_time = time_ns()
augment_variables!(m, stategrid, funcvar, derivs, endo)
total_time += (time_ns() - aug_time) / 6e10
println("Total elapsed time (min): $(round(total_time, digits = 35))")
