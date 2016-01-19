module HFB

using Gadfly
using Formatting
using Hafta

export hfb

"""
`HFBState` stores a Bogoliubov transformation.

The transformation is defined by the `U` and `V` matrices. The object also stores
the `rho` and `kappa` matrices that are calculated from the `U` and `V`.
Calculations should use the `rho` and `kappa` directly and `U`/`V` are stored
only for debugging purposes.

Sometimes it might be that the the `rho`/`kappa` are defined directly, and then
`U`/`V` will be undefined.
"""
type HFBState{T <: Hafta.ManyBodySystem}
    # The many body system related to this state
    system::T

    # Intermediate objects constructed from the transformations
    rho::Matrix{Float64}
    kappa::Matrix{Float64}

    # The defining matrices of the Bogoliubov transformation
    U::Matrix{Float64}
    V::Matrix{Float64}

    """Constructs a `HFBState` from the `U` and `V` matrices."""
    function HFBState(system::T, U::Matrix{Float64}, V::Matrix{Float64})
        N = size(system)
        @assert (N,N) == size(U) && (N,N) == size(V)

        VT = transpose(V)
        rho = V*VT
        kappa = -U*VT
        new(system,rho,kappa,U,V)
    end
end
# TODO: this weird hack is necessary to append to the documentation of a type.
@doc Docs.catdoc((@doc HFBState), Docs.typesummary(HFBState)) HFBState

HFBState{T<:Hafta.ManyBodySystem}(system::T, U, V) = HFBState{T}(system, U, V)

import Base: size
function size(state::HFBState)
    size(state.system)
end

import Base: writemime
function writemime(io, ::MIME"text/html", state::HFBState)
    width,height = 10cm,8cm

    write(io, "<table>")
    write(io, "<tr><th colspan=\"2\" style=\"text-align: center;\">HFBState $(size(state.U))</th></tr>")

    # Table of energies and other values
    E, Ek, Ei, Ep = energy(state)
    Aest = trace(state.rho)
    html = """
    <tr><td colspan="2">
    <table style="width: 100%; border: 1px solid gray;">
    <tr>
        <th>Energy</th>
        <th>Free particles E</th>
        <th>Interaction energy (Γ)</th>
        <th>Pairing energy (Δ)</th>
        <th>Particle number</th>
    </tr>
    <tr>
        <td>{:.5f}</td>
        <td>{:.5f}</td>
        <td>{:.5f}</td>
        <td>{:.5f}</td>
        <td>{:.5f}</td>
    </tr>
    </table>
    """
    write(io,format(html, E, Ek, Ei, Ep, Aest))

    # rho and kappa matrices
    rho,kappa = abs(state.rho), abs(state.kappa)
    maxz = max(maximum(rho), maximum(kappa))
    scale = Scale.color_continuous(minvalue=0, maxvalue=maxz)

    write(io, "<tr>")
    write(io, "<td>")
    p = spy(rho, Guide.title("rho matrix"), scale)
    draw(SVG(io,width,height,false), p)
    write(io, "</td>")
    write(io, "<td>")
    p = spy(kappa, Guide.title("kappa matrix"), scale)
    draw(SVG(io,width,height,false), p)
    write(io, "</td>")
    write(io, "</tr>")

    # U and V matrices
    U,V = abs(state.U), abs(state.V)
    maxz = max(maximum(U), maximum(V))
    scale = Scale.color_continuous(minvalue=0, maxvalue=maxz)

    write(io, "<tr>")
    write(io, "<td>")
    p = spy(abs(state.U), Guide.title("U matrix"), scale)
    draw(SVG(io,width,height,false), p)
    write(io, "</td>")
    write(io, "<td>")
    p = spy(abs(state.V), Guide.title("V matrix"), scale)
    draw(SVG(io,width,height,false), p)
    write(io, "</td>")
    write(io, "</tr>")

    # the end
    write(io, "</table>")
end


"""
The `HFBIterator` is what stores the state of the iteration.

A `HFBIterator` object is the basis, which then can be iterated to solve
the equations. The object should be constructed with `HFB.hfb`.
"""
type HFBIterator{T <: Hafta.ManyBodySystem}
    # setup
    system::T
    A::Int64
    # iteration variables
    states::Vector{HFBState{T}}
    lambdas::Vector{Float64}
    es::Vector{Float64}
    eigenvalues::Vector{Vector{Float64}}
end
# TODO: this weird hack is necessary to append to the documentation of a type.
@doc Docs.catdoc((@doc HFBIterator), Docs.typesummary(HFBIterator)) HFBIterator

import Base: length
length(hfbi::HFBIterator) = length(hfbi.es)

import Base: writemime
function writemime(io, ::MIME"text/html", hfbi::HFBIterator)
    width,height = 20cm,6cm

    write(io, "<table>")
    write(io, """
    <tr>
        <th style="text-align: center;">
            HFBIterator ($(length(hfbi)) iterations)
        </th>
    </tr>""")

    write(io, "<tr><td>")
    logdiffs = log10(abs(diff(hfbi.es)))
    p = plot(
        x=1:length(logdiffs), y=logdiffs,
        yintercept=[-13, -14, -15], Geom.hline(color="red"),
        Geom.line,# Geom.point,
        Guide.title("Convergence for energy"),
        Guide.xlabel("n"), Guide.ylabel("log10(ΔE)")
    )
    draw(SVG(io,width, 1.5*height,false), p)
    write(io, "</td></tr>")

    # Output the first and the last state
    if length(hfbi.states) > 1
        write(io, """
        <tr>
        <th style="text-align: center; border-top: 3px solid black;">
        Final state
            </th>
        </tr>""")
        write(io, "<tr><td>")
        writemime(io, "text/html", hfbi.states[end])
        write(io, "</td></tr>")
    end

    if false
        write(io, """
        <tr>
            <th style="text-align: center; border-top: 3px solid black;">
                Initial state
            </th>
        </tr>""")
        write(io, "<tr><td>")
        writemime(io, "text/html", hfbi.states[1])
        write(io, "</td></tr>")
    end

    write(io, "</table>")
end

"""
`hfb(system, A; maxkappa)` constructs a `HFBIterator` object.

Arguments:

- `system` is the quantum many-body system (`<: ManyBodySystem`)
- `A` is the number of particles
"""
function hfb(system, A; maxkappa=1)
    N = size(system)
    hfb = HFBIterator{typeof(system)}(system, A, [],[],[],[])

    state = HFBState(system, zeros(Float64, (N,N)), zeros(Float64, (N,N)))
    for i=1:A
        state.rho[i,i] = 1.0
    end

    for d=2:1+maxkappa, i=1:div(N,d)
        m = d*(i-1)+1
        n = m+d-1
        state.kappa[m,n] = 0.2
        state.kappa[n,m] = -0.2
    end

    push!(hfb.states, state)
    push!(hfb.es, energy(state)[1])

    hfb
end
@doc Docs.functionsummary(hfb) hfb

"""
`gamma_delta(system, rho, kappa)` calculates the `gamma` and `delta`
matrices from the `rho` and `kappa`. It also needs a system, since
the `gamma` and `delta` also include the interaction `V(i,j,k,l)`.
"""
function gamma_delta(system, rho, kappa)
    N = size(system)
    delta = zeros(Float64, (N,N))
    gamma = zeros(Float64, (N,N))
    for i=1:N,j=1:N,k=1:N,l=1:N
        gamma[i,j] += rho[k,l]*( V(system, i,k,j,l)-V(system, i,k,l,j) )
        delta[i,j] += 0.5*kappa[k,l]*( V(system, i,j,k,l)-V(system, i,j,l,k) )
    end
    gamma,delta
end

"""`gamma_delta(::HFBState)` is a convenience wrapper it directly from a `HFBState`"""
gamma_delta(state::HFBState) = gamma_delta(state.system, state.rho, state.kappa)

import Hafta: energy
function energy(state::HFBState)
    N = size(state.system)
    gamma,delta = gamma_delta(state)

    T = zeros(Float64, (N,N))
    for i=1:N, j=1:N
        T[i,j] = H0(state.system, i,j)
    end

    Ef = trace(T*state.rho)
    Ei = 0.5*trace(gamma*state.rho)
    Ep = -0.5*trace(delta*state.kappa)
    #trace( T*state.rho + 0.5*gamma*state.rho - 0.5*delta*state.kappa )
    Ef+Ei+Ep, Ef, Ei, Ep
end

function solve_state(system,N,lambda,T,gamma,delta)
    h = T + gamma - lambda*eye(N)
    equation = zeros(Float64, (2*N, 2*N))
    equation[1:N, 1:N] = h
    equation[N+1:2N, N+1:2N] = -h
    equation[1:N, N+1:2N] = delta
    equation[N+1:2N, 1:N] = -delta

    if !ishermitian(equation)
        maxdiff = maximum(abs(equation-transpose(equation)))
        if maxdiff > 1e-14
            warn("Equation not hermitian (|diff| = $maxdiff)")
        end
        equation = 0.5*(equation+transpose(equation))
    end

    efact = eigfact(equation)
    perms = sortperm(efact[:values], rev=true)[1:N]
    U = efact[:vectors][1:N, perms]
    V = efact[:vectors][N+1:2N, perms]

    state = HFBState(system,U,V)
    state, trace(state.rho), efact
end

import Hafta: iterate!
function iterate!(hfbi::HFBIterator; mixing=0.0, maxiters=100, nepsilon=1e-10, lambdaepsilon=1e-10, verbose=false)
    lambdaepsilon = min(nepsilon, lambdaepsilon)

    if !(0.0 <= mixing < 1.0)
        error("Invalid value for mixing in iterate!() ($mixing). Must be 0.0 <= mixing < 1.0.")
    end

    A,N = hfbi.A, size(hfbi.system)

    T = zeros(Float64, (N,N))
    for i=1:N, j=1:N
        T[i,j] = H0(hfbi.system, i,j)
    end

    rho,kappa = if mixing != 0.0 && length(hfbi.states) > 1
        state = hfbi.states[end]
        oldstate = hfbi.states[end-1]
        rho = (1.0 - mixing)*state.rho + mixing*oldstate.rho
        kappa = (1.0 - mixing)*state.kappa + mixing*oldstate.kappa
        rho, kappa
    else
        state = hfbi.states[end]
        state.rho, state.kappa
    end

    gamma,delta = gamma_delta(hfbi.system, rho, kappa)

    n0::Float64
    lambda::Float64 = 0.0
    nextstate::HFBState

    nextstate,n0,efact = solve_state(hfbi.system,N,0.0,T,gamma,delta)
    if verbose
        println("lambdascan[initial]: 0.0 => $(n0)")
    end

    lambdas = 0.0, (n0 < A ? 1.0 : -1.0)
    states = nextstate, nothing
    n0s = n0, nothing

    go_higher = (n0 < A)
    nextstate,n0,efact = solve_state(hfbi.system,N,lambdas[2],T,gamma,delta)
    if verbose
        println("lambdascan[up/down]: $(lambdas[1]) - $(lambdas[2]) => $(n0)")
    end
    states = states[1], nextstate
    n0s = n0s[1], n0

    while go_higher && n0 < A || !go_higher && n0 > A
        lambdas = lambdas[2], 2*lambdas[2]
        nextstate,n0,efact = solve_state(hfbi.system,N,lambdas[2],T,gamma,delta)
        states = states[2], nextstate
        n0s = n0s[2], n0
        if verbose
            println("lambdascan[double ]: $(lambdas[1]) - $(lambdas[2]) => $(n0)")
        end

        maxiters -= 1
        if maxiters == 0
            error("Max iterations reached (doubling)")
            return nothing
        end
    end

    #lambdas = minimum(lambdas), maximum(lambdas)
    if lambdas[1] > lambdas[2]
        lambdas = lambdas[2], lambdas[1]
        states = states[2], states[1]
        n0s = n0s[2], n0s[1]
    end

    while abs(n0-A) > nepsilon
        lambda = (lambdas[1]+lambdas[2])/2
        nextstate,n0,efact = solve_state(hfbi.system,N,lambda,T,gamma,delta)
        if verbose
            println("lambdascan[binary ]: $(lambda) ($(lambdas[1]) - $(lambdas[2])) => $(n0)")
        end
        if n0 > A
            lambdas = lambdas[1], lambda
            states = states[1], nextstate
            n0s = n0s[1], n0
        else
            lambdas = lambda, lambdas[2]
            states = nextstate, states[2]
            n0s = n0, n0s[2]
        end

        if abs(lambdas[2]-lambdas[1]) < lambdaepsilon
            warn("No lambda convergence ($(lambdas) => $(n0s))")
            #nextstate.U = zeros(Float64, (N,N))
            #nextstate.V = zeros(Float64, (N,N))
            w = (A-n0s[1])/(n0s[2]-n0s[1])
            #info("Mixing: w = $w")
            #lambda = (1-w)*lambdas[1] + w*lambdas[2]
            #nextstate.rho = (1-w)*states[1].rho + w*states[2].rho
            #nextstate.kappa = (1-w)*states[1].kappa + w*states[2].kappa
            break
        end

        maxiters -= 1
        if maxiters == 0
            error("Max iterations reached (binary)")
            return nothing
        end
    end

    E,_ = energy(nextstate)
    push!(hfbi.states, nextstate)
    push!(hfbi.lambdas, lambda)
    push!(hfbi.es, E)

    #@show E
    hfbi, efact
end

function issolved(hfbi::HFBIterator, epsilon)
    const mindeltas = 5
    if length(hfbi.es) < mindeltas+1
        false
    else
        maximum(abs(diff(hfbi.es[end-mindeltas:end]))) < epsilon
    end
end

import Hafta: solve!
function solve!(hfbi::HFBIterator; epsilon=1e-10, maxiters=20, lambdaiters=50, args...)
    #args = Dict{Symbol, Any}(args)
    efact = nothing
    while !issolved(hfbi, epsilon)
        _,efact = iterate!(hfbi; maxiters=lambdaiters, nepsilon=epsilon/10, args...)

        maxiters -= 1
        if maxiters == 0
            error("Max iterations reached")
            return nothing
        end
    end
    hfbi.es[end], efact
end

end