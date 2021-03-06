
"""
    `build_blp_model(bp::BilevelLP, solver; [comp_method])`

Build a JuMP model (constraints and objective) based
on the data from bp and with a solver.

Returns a tuple `(m, x, y, λ, s)`.

An optional keyword `comp_method` can be passed for
handling complementarity constraints, default is `SOS1Complementarity`.
"""
function build_blp_model(bp::BilevelLP, optimizer; comp_method = SOS1Complementarity())
    m = JuMP.Model(optimizer)
    @variable(m, bp.xl[j] <= x[j=1:bp.nu] <= bp.xu[j])
    @variable(m, y[j=1:bp.nl])
    @constraint(m, uppercons[i=1:bp.mu],
        sum(bp.G[i,j]*x[j] for j in 1:bp.nu) +
        sum(bp.H[i,j]*y[j] for j in 1:bp.nl) <= bp.q[i])
    @objective(m, Min, sum(bp.cx .* x) + dot(bp.cy, y))
    for j in bp.Jx
        JuMP.set_integer(x[j])
    end
    # adding SOS1 constraints
    return build_blp_model(m, bp, x, y, comp_method = comp_method)
end

"""
    `build_blp_model(m::JuMP.Model, bp::BilevelLP, x, y; [comp_method])`

Adds the lower-level constraints and optimality conditions to
an existing JuMP model. This assumes the upper-level feasibility
constraints and objective have already been set.

Returns a tuple `(m, x, y, λ, s)`.

An optional keyword `comp_method` can be passed for
handling complementarity constraints, default is `SOS1Complementarity`.
"""
function build_blp_model(m::JuMP.Model, bp::BilevelLP, x, y; comp_method = SOS1Complementarity())
    @variable(m, s[1:bp.ml] >= 0) # lower-level slack variables
    @constraint(m, lowercons[i=1:bp.ml],
        sum(bp.A[i,j]*x[j] for j in 1:bp.nu) +
        sum(bp.B[i,j]*y[j] for j in 1:bp.nl) + s[i] == bp.b[i]
    )
    @variable(m, λ[1:bp.ml] >= 0)
    @variable(m, σ[1:bp.nl] >= 0) # dual of lower-level lower bound
    for j in Base.OneTo(bp.nl)
        if !bp.yl[j]
            # sigma at 0 if free variable
            @constraint(m, σ[j] == 0)
        else
            JuMP.set_lower_bound(y[j], 0)
        end
    end
    @constraint(m, [j in 1:bp.nl], bp.d[j] + dot(bp.F[:,j], x) + dot(bp.B[:,j], λ)  - σ[j] == 0)
    add_complementarity_constraint(m, comp_method, s, λ, y, σ)
    return (m, x, y, λ, s)
end

"""
    `build_blp_model(m, B, d, x, y, s, F; [comp_method])`

Build the bilevel JuMP model from the data without
grouping everything into a `BilevelLP`.
An optional keyword `comp_method` can be passed for
handling complementarity constraints, default is `SOS1Complementarity`.
"""
function build_blp_model(m::JuMP.Model, B::M, d, x, y, s, F; comp_method = SOS1Complementarity()) where {M<:MT}
    @variable(m, λ[1:bp.ml] >= 0)
    @variable(m, σ[1:bp.nl] >= 0.) # dual of lower-level lower bound
    for j in Base.OneTo(bp.nl)
        if !bp.yl[j]
            # sigma at 0 if free variable
            @constraint(m, σ[j] == 0.)
        else
            JuMP.set_lower_bound(y[j], 0.)
        end
    end
    @constraint(m, d .+ F' * x .+ B' * λ .- σ .== 0)
    add_complementarity_constraint(m, comp_method, s, λ, y, σ)
    return (m, λ, s)
end

function build_blp_model(m::JuMP.Model, B::M, d, s; comp_method = SOS1Complementarity()) where {M<:MT}
    (ml, nl) = size(B)
    @variable(m, λ[1:ml] >= 0)
    @constraint(m, kkt[j=1:nl], d[j] + dot(B[:,j], λ) == 0)
    add_complementarity_constraint(m, comp_method, s, λ, [], [])
    return (m, λ, s)
end
