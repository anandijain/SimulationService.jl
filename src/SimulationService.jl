module SimulationService

using AlgebraicPetri, Catlab, JSON, JSON3, JSONTables, CSV, DataFrames, Oxygen, HTTP
using Catlab.CategoricalAlgebra
using Catlab.CategoricalAlgebra.FinSets
using Bijections
using ModelingToolkit, OrdinaryDiffEq, DifferentialEquations
using OrderedCollections, NamedTupleTools

"i very much dislike this way of storing, but it is a quick way to get something working.
id appreciate comments on how we should be storing these models."
b = Bijection{Int,LabelledPetriNet}()
b2 = Bijection{Int,ODESystem}()
b3 = Bijection{Int,ODEProblem}()

function bij_id!(b, m)
    if m ∉ b.range
        id = length(b) + 1
        b[id] = m
    end
    b(m)
end

petri_id(r) = bij_id!(b, parse_json_acset(AlgebraicPetri.LabelledPetriNet, String(r.body)))
"here we're assuming that we don't post ODESystems but only get them by posting petrinets"
system_id(r) = bij_id!(b2, ODESystem(parse_json_acset(AlgebraicPetri.LabelledPetriNet, String(r.body))))

# this wont work without posting args/kws, and would be finnicky either way
# problem_id(r) = bij_id!(b3, ODESystem(parse_json_acset(AlgebraicPetri.LabelledPetriNet, String(r.body))))

function parse_args_kws(b)
    j = JSON3.read(b)
    args = JSON3.read(JSON3.write(j["args"])) #@anandijain check why im roundtripping these 
    args = keys(args) .=> collect.(values(args)) # otherwise all the arrays are Any and `solve` fails
    kws = JSON3.read(JSON3.write(j["kws"]))
    namedtuple(args), namedtuple(kws)
end

# function _to_post(f, b)
#     args, kws = parse_args_kws(b)
#     (id, args) = args
#     f(d[id], values(args)...; kws...)
# end

# macro to_post(ex)
#     @assert ex.head == :call
#     Expr(:macrocall, Symbol("@post"), f, :(r::HTTP.Request)) => :(r -> _to_post($f, r.body))
# end

"solve an ODEProblem, but given a JSON body with args/kws (from a POST)"
function oxygen_solve(prob, j)
    solve(remake(prob; merge(parse_args_kws(j)...)...))
end

# in both of these solve wrappers we make the call impure by "knowing" to `getindex(b3, model_id)`
function json_solve(r, i)
    arraytable(DataFrame(oxygen_solve(b3[parse(Int, i)], r.body)))
end

csv_solve(r, i) = csv_response(oxygen_solve(b3[parse(Int, i)], r.body))

# doing this we can take the outer product of the EMA functions that return dataframes and the content-type serializations for the output type (DataFrame)
function csv_response(sol)
    io = IOBuffer()
    CSV.write(io, DataFrame(sol))
    HTTP.Response(200, ["Content-Type" => "text/csv"]; body=take!(io))
end

# simple examples of sol->content-type repsonse serialization
arraytable_response(sol) = arraytable(DataFrame(sol))
objecttable_response(sol) = objecttable(DataFrame(sol))
function svg_response(sol; kws...)
    io = IOBuffer()
    show(io, MIME"image/svg+xml"(), plot(sol; kws...))
    HTTP.Response(200, ["Content-Type" => "image/svg+xml"]; body=take!(io))
end

# these taken from the original sim-service package
function register!()
    @post "/petri_id" petri_id
    @post "/sys_id" system_id
    # @post "/prob_id" 
    @post "/solve/{i}" json_solve
    @post "/solve/{i}/CSV" csv_solve
end

function run!()
    # resetstate() # i couldn't find where this was defined
    register!()
    #document()
    # TODO(five)!: Stop SciML from slowing the server down. (Try `serveparallel`?)
    serve(host="0.0.0.0") # adding back in 0.0.0.0 for Docker
end

# clean up these egregious exports
export bij_id!, petri_id, system_id, parse_args_kws, json_solve, csv_solve, b, b2, b3
export register!, oxygen_solve

end # module SimulationService
