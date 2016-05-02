using DataFrames
using Distributions
using Gadfly
using HypothesisTests

include("common.jl")
include("utils.jl")
include("library.jl")
include("transfection.jl")
include("selection.jl")
include("sequencing.jl")
include("analysis.jl")

const N = 500 # number of target genes
const coverage = 5 # number of guides per gene
const representation = 1000 # Number of cells with each guide
const moi = 0.25 # multiplicity of infection
const σ = 1.0 # std dev expected for cells during facs sorting (in phenotype units)

function run_exp()

    guides, guide_freqs = construct_library(N, coverage)

    cell_count = N*coverage*representation
    guide_freqs_dist = Categorical(guide_freqs)

    cells = transfect(guides, guide_freqs_dist, cell_count, moi)

    bin_info = Dict(:bin1 => (0.0, 1/3), :bin2 => (2/3, 1.0))
    bin_cells = facs_sort(cells, guides, bin_info, σ)

    freqs = counts_to_freqs(bin_cells)
    raw_data = sequencing(Dict(:bin1=>10^7,:bin2=>10^7), guides, freqs)

    auroc = analyze(raw_data, gen_plots=false)

    auroc
end

@time run_exp()
