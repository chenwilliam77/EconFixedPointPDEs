# This file holds different types of investment functions
function quadratic_investment(p::S, χ::S, δ::S) where {S <: Real}
    return (p - 1.) .^ 2 ./ (2. * χ) + (p - 1.) + δ
end

function derivative_quadratic_investment(p::S, χ::S) where {S <: Real}
    return p / χ + 1. / χ
end