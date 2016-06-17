fatalerrors = length(ARGS) > 0 && ARGS[1] == "-f"
quiet = length(ARGS) > 0 && ARGS[1] == "-q"
errorfound = false

using Base.Test
packages = [:DataStructures,
            :Gadfly,
            :ColorBrewer]
for package in packages
    !(isdir(Pkg.dir(string(package)))) && Pkg.add(string(package))
    eval(:(using $package))
end

load_file = joinpath("src", "simulation", "load.jl")
include(normpath(joinpath(Base.source_dir(),"..",load_file)))

println("Running tests:")
filenames = ["kdrelationships.jl",
             "qualitymetrics.jl",
             "diffcrisprtransfection.jl",
             "growth.jl",
             "selectionmethods.jl"]

for filename in filenames
    try
        include(filename)
        println("\t\033[1m\033[32mPASSED\033[0m: $(filename)")
    catch e
        errorfound = true
        println("\t\033[1m\033[31mFAILED\033[0m: $(filename)")
        if fatalerrors
            rethrow(e)
        elseif !quiet
            showerror(STDOUT, e, backtrace())
            println()
        end
    end
end

analyses_path = normpath(joinpath(Base.source_dir(),"..",joinpath("src", "exps")))
analyses = readdir(analyses_path)
analyses = analyses[find(x -> x != "common.jl", analyses)]
# load common file first
include(joinpath(analyses_path, "common.jl"))

for analysis in analyses
    try
        include(joinpath(analyses_path, analysis))
        tempfile = tempname()
        main(tempfile, debug=true, quiet=true)
        println("\t\033[1m\033[32mPASSED\033[0m: $(analysis)")
    catch e
        errorfound = true
        println("\t\033[1m\033[31mFAILED\033[0m: $(analysis)")
        if fatalerrors
            rethrow(e)
        elseif !quiet
            showerror(STDOUT, e, backtrace())
            println()
        end
    end
end

if errorfound
    throw("Tests failed")
else
    println("All tests pass")
end
