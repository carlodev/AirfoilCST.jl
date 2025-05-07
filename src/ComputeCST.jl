"""
    read_airfoil(filename::String)

Read .csv file where the airfoil coordinates are stored
"""
function read_airfoil(filename::String)
    df = DataFrame(CSV.File(filename))
    return df.x, df.y
end

"""
    find_lower_upper(x::Vector{Float64},y::Vector{Float64})

Distinguish the upper and lower coordinates of the airfoil
"""
function find_lower_upper(x::Vector{Float64},y::Vector{Float64})
    _,origin_idx = findmin(abs.(x) )

    # origin_idx = findall(isapprox.(x,0.0))[1]
    n = length(x)
    if y[origin_idx+1]<y[origin_idx-1]
        idx_upper = 1:origin_idx
        idx_lower = origin_idx+1:n
    else
        idx_upper = origin_idx+1:n
        idx_lower = 1:origin_idx 
    end
    return x[idx_upper],x[idx_lower],y[idx_upper],y[idx_lower]
end




"""
    get_airfoil_coordinates(filename::String)
Get the airfoil points coordinates form .csv file. It distinguish the top and bottom side
"""
function get_airfoil_coordinates(filename::String)
    x,y = read_airfoil(filename)
    xu, xl, yu, yl = find_lower_upper(x,y)
    return xu, xl, yu, yl
end


"""
    get_airfoil_coordinates_(filename::String)
Get the airfoil points coordinates form .csv file. It concatenes upper and bottom side
"""
function get_airfoil_coordinates_(filename::String)
    xu, xl, yu, yl = get_airfoil_coordinates(filename)
    return [xu;xl], [yu; yl]
end

"""
    compute_error(y0,y)
Compute the error of approximation. y0 are the original points, y are the new ones.
"""
function compute_error(y0,y)
    n = length(y0)
    return sqrt(sum((y0-y).^2)/n)
end

"""
    compute_wuwl(w::Vector{Float64},split_idx::Int64)

Creates 2 vector, one for wu and one for wl
"""
function compute_wuwl(w::Vector{Float64},split_idx::Int64)
    wu = w[1:split_idx]
    wl = w[split_idx+1:end]

    return wu,wl
end

"""
    compute_cst_error(w,p)
Compute the error of approximation
"""
function compute_cst_error(w,params)
    split_idx,N1,N2, xu,xl,dz,y0 = params
    wu,wl = compute_wuwl(w,split_idx)
    (_,_), (yu,yl) = CST_airfoil(wu,wl,dz,xu,xl;  N1 = N1, N2 = N2)
    
    y = [yu;yl]

    err = compute_error(y0,y)
        return err
end

"""
    write_csv_cst(x::Vector{Float64},y::Vector{Float64},filename::String)

Write .csv file where are stored the coordinates obtained with the cst method
"""
function write_csv_cst(x::Vector{Float64},y::Vector{Float64},filename::String)
    airfoil_name = get_airfoil_name(filename::String)
    z = zeros(length(x))
    df_cst = DataFrame(x= x,y=y,z=z)
    CSV.write("$(airfoil_name)_CST.csv", df_cst)
end

"""
    cst2csv(wl,wu,dz,N; aifoil_name="Airfoil")

Write .csv file where are stored the coordinates obtained with the cst method
"""
function cst2csv(wl,wu,dz,N; airfoil_name="Airfoil")
    x,y = CST_airfoil(wl,wu,dz,N)
    z = zeros(length(x))
    df_cst = DataFrame(x= x, y=y,z=z)
    CSV.write("$(airfoil_name)_CST.csv", df_cst)
    return x,y
end

"""
    increase_resolution_airfoil(xu::Vector{Float64},xl::Vector{Float64},yu::Vector{Float64},yl::Vector{Float64}, N::Int64; dz = 0.0, w0 = [-0.1294, -0.0036, -0.0666, -0.01, 0.206, 0.2728, 0.2292, 0.1, 0.1,0.1], maxiters = 100.0, maxtime=100.0)

From a .csv file specified in ´filename´ it increase the points which define the airfoil surface, creating a total of ´N´ points. 
´dz´ is the half height of the trailing edge.
Internally solve a minimization problem to find the best set of ´w0´ that allows the CST to describe the input profile.
Finally it writes .csv file where are stored the coordinates obtained with the cst method.
```julia
using Plots
x,y,wl,wu = increase_resolution_airfoil("e1098.csv",500)
x0,y0 = get_airfoil_coordinates_("e1098.csv")

scatter(x,y, markersize=2.5, label = "CST")
scatter!(x0,y0,markersize=2.5, markercolor= :red, label = "Original")
plot!(xlims =(0.0,1.0), ylims =(-0.2,0.65))
plot!(xlabel = "x", ylabel = "y")
```
"""
function increase_resolution_airfoil(xu::Vector{Float64},xl::Vector{Float64},yu::Vector{Float64},yl::Vector{Float64}, N::Int64; dz = 0.0, w0 = [0.1,0.1,0.1,-0.1,-0.1,-0.1], maxiters = 100.0, maxtime=100.0, write_cst=false)

    y0 = [yu;yl]

    error_function = OptimizationFunction(compute_cst_error)

    split_idx = count(w0.>0)
    
    ub = vcat(zeros(Int64, count(w0.<0)),    ones(Int64,count(w0.>0)))
    lb = ub .- 1
    params = ( split_idx, xl,xu,dz,y0)
    prob = Optimization.OptimizationProblem(error_function, w0, params, lb =lb, ub = ub)
    sol = solve(prob, BBO_adaptive_de_rand_1_bin_radiuslimited(), maxiters = maxiters,  maxtime = maxtime)
    sol = collect(sol)
    wu, wl = compute_wuwl(sol, split_idx)
   
    #Using wl,wu the new coordinates x,y are computed
    x,y = CST_airfoil(wu,wl,dz,N)
    write_cst && write_csv_cst(x,y,filename)
   
    return x,y,wl,wu
end


function get_CST_weights(xu::Vector{Float64},xl::Vector{Float64},yu::Vector{Float64},yl::Vector{Float64}; w0=0.1.*[ones(3); -ones(3)], maxiters=100,maxtime=10,  N1 = 0.5, N2 = 1)
    y0 = [yu;yl]
    dz = yu[1] - yl[end]

    error_function = OptimizationFunction(compute_cst_error)
    split_idx = count(w0.>0)
    ub = vcat( ones(Int64,count(w0.>0)),ones(Int64,count(w0.>0))  )
    lb = -1 .* ub
    params = ( split_idx,N1,N2, xu,xl,dz,y0)
    prob = Optimization.OptimizationProblem(error_function, w0, params, lb =lb, ub = ub)
    sol = solve(prob, BBO_adaptive_de_rand_1_bin_radiuslimited(), maxiters = maxiters,  maxtime = maxtime)
    sol = collect(sol)
    wu, wl = compute_wuwl(sol, split_idx)

    return wu,wl

end