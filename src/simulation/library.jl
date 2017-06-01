using Compat

"""
Given value(s) `x` apply the sigmoidal function with maximum
value `l`, a steepness `k`, and an inflection point `p`.
"""
function sigmoid(x::Float64, l, k, p)
    k = min(p, min(1-p, k))
    (x <= p-k) && return 0
    (x >= p+k) && return l
    x = (x-p)/k
    l/2*(sign(x).*21abs(x)./(20*abs(x)+1)+1)
end

function sigmoid(xs::AbstractArray{Float64}, l, k, p)
    result = Array{Float64}(size(xs))
    @inbounds @fastmath for i in eachindex(xs)
        result[i] = sigmoid(xs[i], l, k, p)
    end
    result
end

"""
Given value(s) `x` apply a simple linear function with maximum value `l`
"""
linear(x, l) = clamp(l.*x, min(0, l), max(0, l))

@compat abstract type KDPhenotypeRelationship end

type Linear <: KDPhenotypeRelationship end

type Sigmoidal <: KDPhenotypeRelationship
    "Slopes of the sigmoid are pulled from this distribution"
    width_dist::Distribution

    "Inflection points are pulled from this distribution"
    inflection_dist::Distribution

    function Sigmoidal()
        # width of sigmoidal region
        width = Normal(0.1, 0.05)
        # inflections are centered at high KD
        inflections = TruncatedNormal(0.8, 0.2, 0, 1)
        new(width, inflections)
    end
end

response(::Linear) = linear
function response(sig::Sigmoidal)
    width, inflection = rand(sig.width_dist), rand(sig.inflection_dist)
    (x, l) -> sigmoid(x, l, width, inflection)
end

@compat abstract type Cas9Behavior end

type CRISPRi <: Cas9Behavior end

type CRISPRn <: Cas9Behavior
    knockout_dist::Categorical

    CRISPRn(dist::Categorical) = new(dist)
end
CRISPRn() = CRISPRn(Categorical([1/9, 4/9, 4/9]))

"""
Wrapper containing all library construction parameters
"""
type Library
    "Distribution of guide knockdown efficiencies"
    knockdown_dist::Dict{Int, Tuple{Symbol, Sampleable}}
    knockdown_probs::Categorical

    """
    Maximum phenotype categories mapped to their probability of being
    selected and the distribution to draw from if they are selected
    """
    max_phenotype_dists::Dict{Int, Tuple{Symbol, Sampleable}}
    phenotype_probs::Categorical

    """
    Knockdown-phenotype relationships mapped to their probability of
    being selected and their respective KDPhenotypeRelationship
    """
    kd_phenotype_relationships::Dict{Int, Tuple{Symbol, KDPhenotypeRelationship}}
    relationship_probs::Categorical

    """
    Whether this library is CRISPRi or CRISPR cutting.
    """
    cas9_behavior::Cas9Behavior

    function Library(knockdown_dist::Dict{Symbol, Tuple{Float64, Sampleable}},
                     max_phenotype_dists::Dict{Symbol, Tuple{Float64, Sampleable}},
                     kd_phenotype_relationships::Dict{Symbol, Tuple{Float64, KDPhenotypeRelationship}},
                     cas9_behavior::Cas9Behavior)

        kd = unroll(knockdown_dist)
        max_p = unroll(max_phenotype_dists)
        rela = unroll(kd_phenotype_relationships)
        new(kd[1], kd[2], max_p[1], max_p[2], rela[1], rela[2], cas9_behavior)
    end
end

function Library(cas9_behavior::Cas9Behavior)
    max_phenotype_dists = Dict{Symbol, Tuple{Float64, Sampleable}}(
        :inactive => (0.75, Delta(0.0)),
        :negcontrol => (0.05, Delta(0.0)),
        :increasing => (0.1, TruncatedNormal(0.55, 0.2, 0.1, 1)),
        :decreasing => (0.1, TruncatedNormal(-0.55, 0.2, -1, -0.1))
    )
    Library(max_phenotype_dists, cas9_behavior)
end

function Library(max_phenotype_dists::Dict{Symbol, Tuple{Float64, Sampleable}},
                 cas9_behavior::CRISPRi)
    # Assuming a high quality library has mostly good guides with some bad ones
    knockdown_dist = Dict{Symbol, Tuple{Float64, Sampleable}}(
        :high => (0.9, TruncatedNormal(0.90, 0.1, 0, 1)),
        :low => (0.1, TruncatedNormal(0.05, 0.07, 0, 1))
    )
    Library(max_phenotype_dists, knockdown_dist, cas9_behavior)
end

function Library(max_phenotype_dists::Dict{Symbol, Tuple{Float64, Sampleable}},
                 cas9_behavior::CRISPRn)
    # For CRISPR KO assume that if guide is "high quality" than it will a
    # maximum knockdown of 100%
    knockdown_dist = Dict{Symbol, Tuple{Float64, Sampleable}}(
        :high => (0.9, Delta(1.0)),
        :low => (0.1, TruncatedNormal(0.05, 0.07, 0, 1))
    )
    Library(max_phenotype_dists, knockdown_dist, cas9_behavior)
end

function Library(max_phenotype_dists::Dict{Symbol, Tuple{Float64, Sampleable}},
                 knockdown_dist::Dict{Symbol, Tuple{Float64, Sampleable}},
                 cas9_behavior::Cas9Behavior)

    kd_phenotype_relationships = Dict{Symbol, Tuple{Float64, KDPhenotypeRelationship}}(
        :linear => (0.75, Linear()),
        :sigmoidal => (0.25, Sigmoidal())
    )
    Library(knockdown_dist, max_phenotype_dists, kd_phenotype_relationships, cas9_behavior)
end

function as_array(lib::Library)
    cas9_behavior = typeof(lib.cas9_behavior)
    frac_hq = 0.0
    mean_hq_kd = 0.0
    for (id, (quality, dist)) in lib.knockdown_dist
        if quality == :high
            mean_hq_kd = cas9_behavior == CRISPRi ? mean(dist.untruncated) : NaN
            frac_hq = lib.knockdown_probs.p[id]
        end
    end

    relationships = Symbol(sort([behavior for (mapping, (behavior, dist)) in
                                 lib.kd_phenotype_relationships])...)

    frac_inc_genes, frac_dec_genes = 0.0, 0.0
    cent_inc_phenotype = 0.0
    for (id, (quality, dist)) in lib.max_phenotype_dists
        if quality == :increasing
            frac_inc_genes = lib.phenotype_probs.p[id]
            cent_inc_phenotype = mean(dist.untruncated)
        end
        (quality == :decreasing) && (frac_dec_genes = lib.phenotype_probs.p[id])
    end
    [frac_hq, mean_hq_kd, frac_inc_genes, frac_dec_genes, cent_inc_phenotype, relationships, cas9_behavior]
end

array_names(::Type{Library}) = [:frac_hq, :mean_hq_kd, :frac_inc, :frac_dec, :cent_inc_phenotype, :relationships, :crisprtype]

function unroll{T}(data::Dict{Symbol, Tuple{Float64, T}})
    probs = Float64[]
    results = Dict{Int, Tuple{Symbol, T}}()
    count = 0
    for (key, value) in data
        push!(probs, value[1])
        results[count+=1] = (key, value[2])
    end
    results, Categorical(probs)
end

function rand_gene(lib::Library)
    class, dist = lib.max_phenotype_dists[rand(lib.phenotype_probs)]
    max_phenotype = rand(dist)
    behavior, relationship = lib.kd_phenotype_relationships[rand(lib.relationship_probs)]
    class, max_phenotype, behavior, relationship
end

"""
Constructs the guide library for `N` genes with `coverage` number of guides per
gene. Returns a tuple of guides and their relative frequencies (assigned randomly).
"""
function construct_library(setup::ScreenSetup, lib::Library)
    barcodes = Barcode[]
    N = setup.num_genes
    coverage = setup.coverage

    for gene in 1:N

        gene_class, max_phenotype, gene_behavior, relationship = rand_gene(lib)
        # get this gene's KD-phenotype relationship
        kd_response = response(relationship)

        for i in 1:coverage
            barcode_quality, barcode_knockdown_dist = lib.knockdown_dist[rand(lib.knockdown_probs)]
            barcode_knockdown = rand(barcode_knockdown_dist)
            # phenotype of barcode given its knockdown efficiency
            barcode_phenotype = kd_response(barcode_knockdown, max_phenotype)
            push!(barcodes, Barcode(gene, barcode_knockdown, barcode_phenotype,
                  gene_behavior, gene_class))
        end
    end

    # the expected z-score for a 90% confidence interval is 2x1.645=3.29
    # construct a normal distribution with a σ = 1/3.29 so that there is
    # a 10-fold difference between the 95th/5th percentiles
    vals = 10.^rand(Normal(0, 1/3.29), N*coverage)
    guide_freqs = vals/sum(vals)
    barcodes, Categorical(guide_freqs)
end

"""
Constructs a delta function at a given δ value
"""
type Delta <: Distributions.Sampleable{Univariate, Discrete}
    δ::Float64
end

Base.rand(d::Delta) = d.δ
