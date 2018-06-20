"""
```
decompose_forecast(m_new, m_old, df_new, df_old, input_type, cond_new, cond_old,
    classes, hs; verbose = :low, kwargs...)

decompose_forecast(m_new, m_old, df_new, df_old, params_new, params_old,
    cond_new, cond_old, classes, hs; individual_shocks = false,
    check = false, atol = 1e-8)
```

### Inputs

- `m_new::M` and `m_old::M` where `M<:AbstractModel`
- `df_new::DataFrame` and `df_old::DataFrame`
- `cond_new::Symbol` and `cond_old::Symbol`
- `classes::Vector{Symbol}`: some subset of `[:states, :obs, :pseudo]`
- `hs::UnitRange{Int}`: horizons at which to calculate the forecast
  decomposition *in terms of the old forecast*. That is, if the old forecast
  uses data up to time T-k and the new forecast up to time T, this function
  computes the decomposition for periods T-k+hs. All elements of `hs` must be
  positive

**Method 1 only:**

- `input_type::Symbol`: estimation type to use. Parameters will be loaded using
  `load_draws(m_new, input_type)` and `load_draws(m_old, input_type)` in this
  method

**Method 2 only:**

- `params_new::Vector{Float64}` and `params_old::Vector{Float64}`: single
  parameter draws to use

### Keyword Arguments

- `check::Bool`: whether to check that the individual components add up to the
  correct total difference in forecasts. This roughly doubles the runtime
- `atol::Float64`: absolute tolerance used if `check = true`

**Method 1 only:**

- `verbose::Symbol`

**Method 2 only:**

- `individual_shocks::Bool`: whether to decompose the shock component into
  individual shocks

### Outputs

The first method returns nothing. The second method returns
`decomp::Dict{Symbol, Matrix{Float64}}`, which has keys of the form
`:decomp<component><class>` and values of size `Ny` x `length(hs)` (where `Ny`
is the number of variables in the given class).
"""
function decompose_forecast(m_new::M, m_old::M, df_new::DataFrame, df_old::DataFrame,
                            input_type::Symbol, cond_new::Symbol, cond_old::Symbol,
                            classes::Vector{Symbol}, hs::UnitRange{Int};
                            verbose::Symbol = :low, kwargs...) where M<:AbstractModel
    # Get output file names
    decomp_output_files = get_decomp_output_files(m_new, m_old, input_type, cond_new, cond_old, classes, hs)

    info(verbose, :low, "Decomposing forecast...")
    println(verbose, :low, "Start time: $(now())")

    # Single-draw forecasts
    if input_type in [:mode, :mean, :init]

        params_new = load_draws(m_new, input_type, verbose = verbose)
        params_old = load_draws(m_old, input_type, verbose = verbose)

        decomps = decompose_forecast(m_new, m_old, df_new, df_old, params_new, params_old,
                                     cond_new, cond_old, classes, hs; kwargs...)
        write_forecast_decomposition(m_new, m_old, input_type, classes, hs, decomp_output_files, decomps,
                                     verbose = verbose)

    # Multiple-draw forecasts
    elseif input_type == :full

        block_inds, block_inds_thin = forecast_block_inds(m_new, input_type)
        nblocks = length(block_inds)
        total_forecast_time = 0.0

        for block = 1:nblocks
            println(verbose, :low)
            info(verbose, :low, "Decomposing block $block of $nblocks...")
            tic()

            # Get to work!
            params_new = load_draws(m_new, input_type, block_inds[block], verbose = verbose)
            params_old = load_draws(m_old, input_type, block_inds[block], verbose = verbose)

            mapfcn = use_parallel_workers(m_new) ? pmap : map
            decomps = mapfcn((param_new, param_old) ->
                             decompose_forecast(m_new, m_old, df_new, df_old, param_new, param_old,
                                                cond_new, cond_old, classes, hs; kwargs...),
                             params_new, params_old)

            # Assemble outputs from this block and write to file
            decomps = convert(Vector{Dict{Symbol, Array{Float64}}}, decomps)
            decomps = assemble_block_outputs(decomps)
            write_forecast_decomposition(m_new, m_old, input_type, classes, hs, decomp_output_files, decomps,
                                         block_number = Nullable(block), block_inds = block_inds_thin[block],
                                         verbose = verbose)
            gc()

            # Calculate time to complete this block, average block time, and
            # expected time to completion
            block_time = toq()
            total_forecast_time += block_time
            total_forecast_time_min     = total_forecast_time/60
            expected_time_remaining     = (total_forecast_time/block)*(nblocks - block)
            expected_time_remaining_min = expected_time_remaining/60

            println(verbose, :low, "\nCompleted $block of $nblocks blocks.")
            println(verbose, :low, "Total time elapsed: $total_forecast_time_min minutes")
            println(verbose, :low, "Expected time remaining: $expected_time_remaining_min minutes")
        end # of loop through blocks

    else
        error("Invalid input_type: $input_type. Must be in [:mode, :mean, :init, :full]")
    end

    println(verbose, :low, "\nForecast decomposition complete: $(now())")
end

function decompose_forecast(m_new::M, m_old::M, df_new::DataFrame, df_old::DataFrame,
                            params_new::Vector{Float64}, params_old::Vector{Float64},
                            cond_new::Symbol, cond_old::Symbol, classes::Vector{Symbol},
                            hs::UnitRange{Int};
                            individual_shocks::Bool = false,
                            check::Bool = false, atol::Float64 = 1e-8) where M<:AbstractModel

    # Compute numbers of periods
    # k_cond is h adjusted for (differences in) conditioning
    T0, T, k, T1_new, T1_old, k_cond =
        decomposition_periods(m_new, m_old, cond_new, cond_old)

    @assert size(df_new, 1) == T0 + T + T1_new
    @assert size(df_old, 1) == T0 + T + T1_old - k

    # Update parameters, filter, and smooth
    sys_new, sys_old, s_new_new_tgt, s_new_new_tgT, ϵ_new_new_tgT, s_old_new_Tmk_Tmk, s_old_old_Tmk_Tmk =
        prepare_decomposition!(m_new, m_old, df_new, df_old, params_new, params_old,
                               cond_new, cond_old, k_cond; atol = atol)

    s_new_new_Tmk_Tmk = s_new_new_tgt[:, end-k_cond]
    s_new_new_Tmk_T   = s_new_new_tgT[:, end-k_cond]

    # Initialize output dictionary
    decomp = Dict{Symbol, Array{Float64}}()

    for class in classes
        # Initialize output matrix
        ZZ, _ = class_measurement_matrices(sys_new, class)
        Ny    = size(ZZ, 1)
        Ne    = size(sys_new[:RRR], 2)
        Nh    = length(hs)
        for comp in [:state, :shock, :data, :param, :total]
            output_var = Symbol(:decomp, comp, class)
            decomp[output_var] = zeros(Ny, Nh)
        end
        decomp[Symbol(:decompindshock, class)] = if individual_shocks
            zeros(Ny, Nh, Ne)
        else
            zeros(0, 0, 0)
        end

        for (i, h) in enumerate(hs)
            # Adjust h for (differences in) conditioning
            h_cond = h - T1_old
            @assert h_cond >= 0

            # Decompose into components
            state_comp = decompose_states_reest(sys_new, s_new_new_Tmk_Tmk, s_new_new_Tmk_T,
                                                class, k_cond, h_cond)
            shock_comp, indshock_comps = decompose_shocks_observed(sys_new, ϵ_new_new_tgT,
                                                                   class, k_cond, h_cond,
                                                                   individual_shocks = individual_shocks)
            if check
                @assert check_states_shocks_decomp(sys_new, s_new_new_tgt, s_new_new_tgT, class,
                                                   k_cond, h_cond, state_comp, shock_comp, atol = atol)
            end

            data_comp = decompose_data_revisions(sys_new, s_new_new_Tmk_Tmk, s_old_new_Tmk_Tmk,
                                                 class, k_cond, h_cond)
            param_comp = decompose_param_reest(sys_new, sys_old, s_old_new_Tmk_Tmk, s_old_old_Tmk_Tmk,
                                               class, k_cond, h_cond)

            decomp[Symbol(:decompstate, class)][:, i] = state_comp
            decomp[Symbol(:decompshock, class)][:, i] = shock_comp
            decomp[Symbol(:decompdata,  class)][:, i] = data_comp
            decomp[Symbol(:decompparam, class)][:, i] = param_comp
            if individual_shocks
                decomp[Symbol(:decompindshock, class)][:, i, :] = indshock_comps
            end

            # Compute total difference
            decomp[Symbol(:decomptotal, class)][:, i] = state_comp + shock_comp + data_comp + param_comp
        end
    end

    check && @assert check_total_decomp(m_new, m_old, df_new, df_old, sys_new, sys_old,
                                        cond_new, cond_old, classes, decomp,
                                        T, k, hs; atol = atol)

    return decomp
end

"""
```
decomposition_periods(m_new, m_old, cond_new, cond_old)
```

Compute and return numbers of periods.

### Outputs

- `T0::Int`: number of presample periods. Must be the same for `m_new` and `m_old`
- `T::Int`: number of main-sample periods for `m_new`
- `k::Int`: difference in number of main-sample periods between `m_old` and
  `m_new`. `m_old` has `T-k`
- `T1_new::Int` and `T1_old::Int`: number of conditional periods for each model
- `k_cond::Int`: difference in number of main-sample + conditional periods
"""
function decomposition_periods(m_new::M, m_old::M,
                               cond_new::Symbol, cond_old::Symbol) where M<:AbstractModel
    # Number of presample periods T0 must be the same
    T0 = n_presample_periods(m_new)
    @assert n_presample_periods(m_old) == T0

    # New model has T main-sample periods
    # Old model has T-k main-sample periods
    T = n_mainsample_periods(m_new)
    k = subtract_quarters(date_forecast_start(m_new), date_forecast_start(m_old))
    @assert k >= 0

    # Number of conditional periods T1 may differ
    T1_new = cond_new == :none ? 0 : n_conditional_periods(m_new)
    T1_old = cond_old == :none ? 0 : n_conditional_periods(m_old)

    # Adjust k for (differences in) conditioning
    k_cond = k + T1_new - T1_old

    return T0, T, k, T1_new, T1_old, k_cond
end

"""
```
prepare_decomposition!(m_new, m_old, df_new, df_old, params_new, params_old,
    cond_new, cond_old, k; atol = 1e-8)
```

Update `m_new` and `m_old` with `params_new` and `params_old`,
respectively. Compute state-space matrices, filter, and smooth.

### Outputs

- `sys_new::System` and `sys_old::System`
- `s_new_new_tgt::Matrix{Float64}`: filtered states using `df_new` and `params_new`
- `s_new_new_tgT::Matrix{Float64}`: smoothed states using `df_new` and `params_new`
- `ϵ_new_new_tgT::Matrix{Float64}`: smoothed shocks using `df_new` and `params_new`
- `s_old_new_Tmk_Tmk::Vector{Float64}`: s_{T-k|T-k} from filtering using `df_old` and `params_new`
- `s_old_old_Tmk_Tmk::Vector{Float64}`: s_{T-k|T-k} from filtering using `df_old` and `params_old`
"""
function prepare_decomposition!(m_new::M, m_old::M, df_new::DataFrame, df_old::DataFrame,
                                params_new::Vector{Float64}, params_old::Vector{Float64},
                                cond_new::Symbol, cond_old::Symbol,
                                k::Int; atol::Float64 = 1e-8) where M<:AbstractModel
    # Update parameters
    update!(m_new, params_new)
    update!(m_old, params_old)
    sys_new = compute_system(m_new)
    sys_old = compute_system(m_old)

    # Filter and smooth
    s_new_new_tgt = filter(m_new, df_new, sys_new, cond_type = cond_new, outputs = [:filt],
                                include_presample = false)[:s_filt]
    s_new_new_tgT, ϵ_new_new_tgT = smooth(m_new, df_new, sys_new, cond_type = cond_new, draw_states = false)

    s_old_new_Tmk_Tmk = filter(m_new, df_old, sys_new, cond_type = cond_old, outputs = Symbol[],
                                    include_presample = false)[:s_T]
    s_old_old_Tmk_Tmk = filter(m_old, df_old, sys_old, cond_type = cond_old, outputs = Symbol[],
                                    include_presample = false)[:s_T]

    # Check sizes
    T = size(s_new_new_tgt, 2)
    @assert size(s_new_new_tgT, 2) == size(ϵ_new_new_tgT, 2) == T
    @assert isapprox(s_new_new_tgt[:, end], s_new_new_tgT[:, end], atol = atol)

    return sys_new, sys_old, s_new_new_tgt, s_new_new_tgT, ϵ_new_new_tgT, s_old_new_Tmk_Tmk, s_old_old_Tmk_Tmk
end

"""
```
decompose_states_reest(sys_new, s_Tmk_Tmk, s_Tmk_T, class, k, h)
```

Compute the difference in forecasts attributable to changes in estimates of the
state s_{T-k}.

### Inputs

- `sys_new::System`: state-space matrices under new parameters
- `s_Tmk_Tmk::Vector{Float64}`: s_{T-k|T-k} from filtering using `df_new` and `params_new`
- `s_Tmk_T::Vector{Float64}`: s_{T-k|T} from smoothing using `df_new` and `params_new`
- `class::Symbol
- `k::Int`
- `h::Int`

### Outputs

- `state_comp::Vector{Float64}`
"""
function decompose_states_reest(sys_new::System, s_Tmk_Tmk::Vector{Float64},
                                s_Tmk_T::Vector{Float64}, class::Symbol, k::Int, h::Int)
    # New parameters, new data
    TTT = sys_new[:TTT]
    ZZ, _ = class_measurement_matrices(sys_new, class)

    # State component = Z T^h (s_{T-k|T} - s_{T-k|T-k})
    state_comp = ZZ * TTT^h * (s_Tmk_T - s_Tmk_Tmk)
    return state_comp
end

"""
```
decompose_shocks_observed(sys_new, ϵ_tgT, class, k, h; individual_shocks = false)
```

Compute the difference in forecasts attributable to observing the shock sequence
ϵ_{T-k+1:min(T-k+h,T)}. (If h <= k, then T-k+h <= T and we observe shocks up to
T-k+h. If h > k, then T-k+h > T and we observe shocks up to T.)

### Inputs

- `sys_new::System`: state-space matrices under new parameters
- `ϵ_tgT::Matrix{Float64}`: ϵ_{t|T}, t = 1:T from smoothing using `df_new` and `params_new`
- `classes::Vector{Symbol}
- `k::Int`
- `h::Int`

### Keyword Arguments

- `individual_shocks::Bool` whether to decompose into the contributions of
  observing each individual shock (like in a shock decomposition)

### Outputs

- `shock_comp::Vector{Float64}`: size `nobs` x 1
- `indshock_comps::Matrix{Float64}`: either size `nobs` x `nshocks` (if
  `individual_shocks = true`) or an empty matrix
"""
function decompose_shocks_observed(sys_new::System, ϵ_tgT::Matrix{Float64},
                                   class::Symbol, k::Int, h::Int;
                                   individual_shocks::Bool = false)
    # New parameters, new data
    TTT, RRR, CCC = sys_new[:TTT], sys_new[:RRR], sys_new[:CCC]
    ZZ, _ = class_measurement_matrices(sys_new, class)
    Ns = size(TTT, 1)
    Ne = size(RRR, 2)
    Nt = size(ϵ_tgT, 2)

    # Shock component = Z sum_{j=1}^(min(k,h)) ( T^(h-j) R ϵ_{T-k+j|T} )
    shock_sum = zeros(Ns)
    for j = 1:min(k, h)
        shock_sum .+= TTT^(h-j) * RRR * ϵ_tgT[:, end-k+j]
    end
    shock_comp = ZZ * shock_sum

    # Component for shock i = Z sum_{j=1}^(min(k,h)) ( T^(h-j) R ϵ^i_{T-k+j|T} )
    indshock_comps = if individual_shocks
        shock_sum = zeros(Ns, Ne)
        for i = 1:Ne
            ϵ_i_tgT = zeros(Ne, Nt)
            ϵ_i_tgT[i, :] = ϵ_tgT[i, :]
            for j = 1:min(k, h)
                shock_sum[:, i] .+= TTT^(h-j) * RRR * ϵ_i_tgT[:, end-k+j]
            end
        end
        ZZ * shock_sum
    else
        Matrix{Float64}(0, 0)
    end
    return shock_comp, indshock_comps
end

"""
```
decompose_data_revision(sys_new, s_new_Tmk_Tmk, s_old_Tmk_Tmk, class, k, h)
```

Compute y^{d_new,θ_new}_{T-k+h|T-k} - y^{d_old,θ_new}_{T-k+h|T-k}, the
difference in forecasts attributable to data revisions.

### Inputs

- `sys_new::System`: state-space matrices under new parameters
- `s_new_Tmk_Tmk::Vector{Float64}`: s_{T-k|T-k} from filtering using `df_new` and `params_new`
- `s_old_Tmk_Tmk::Vector{Float64}`: s_{T-k|T-k} from filtering using `df_old` and `params_new`
- `class::Symbol`
- `k::Int`
- `h::Int`

### Outputs

- `data_comp::Vector{Float64}`
"""
function decompose_data_revisions(sys_new::System, s_new_Tmk_Tmk::Vector{Float64},
                                  s_old_Tmk_Tmk::Vector{Float64}, class::Symbol,
                                  k::Int, h::Int)
    # New parameters, new and old data
    TTT = sys_new[:TTT]
    ZZ, _ = class_measurement_matrices(sys_new, class)

    # Data revision component = y^new_{T-k+h|T-k} - y^old_{T-k+h|T-k}
    #     = Z T^h ( s^new_{T-k|T-k} - s^old_{T-k|T-k} )
    data_comp = ZZ * TTT^h * (s_new_Tmk_Tmk - s_old_Tmk_Tmk)
    return data_comp
end

"""
```
decompose_param_reest(sys_new, sys_old, s_new_Tmk_Tmk, s_old_Tmk_Tmk, class, k, h)
```

Compute y^{d_old,θ_new}_{T-k+h|T-k} - y^{d_old,θ_old}_{T-k+h|T-k}, the
difference in forecasts attributable to parameter re-estimation.

### Inputs

- `sys_new::System`: state-space matrices under new parameters
- `sys_old::System`: state-space matrices under old parameters
- `s_new_Tmk_Tmk::Vector{Float64}`: s_{T-k|T-k} from filtering using `df_old` and `params_new`
- `s_old_Tmk_Tmk::Vector{Float64}`: s_{T-k|T-k} from filtering using `df_old` and `params_old`
- `class::Symbol`
- `k::Int`
- `h::Int`

### Outputs

- `param_comp::Vector{Float64}`
"""
function decompose_param_reest(sys_new::System, sys_old::System,
                               s_new_Tmk_Tmk::Vector{Float64}, s_old_Tmk_Tmk::Vector{Float64},
                               class::Symbol, k::Int, h::Int)
    # New and old parameters, old data
    ZZ_new, DD_new = class_measurement_matrices(sys_new, class)
    ZZ_old, DD_old = class_measurement_matrices(sys_old, class)

    function forecast(system::System, s_0::Vector{Float64}, h::Int)
        TTT, CCC = system[:TTT], system[:CCC]
        s_h = TTT^h * s_0
        for j = 1:h
            s_h .+= TTT^(j-1) * CCC
        end
        return s_h
    end

    # y^new_{T-k+h|T-k} = Z^new (T^new^h s^new_{T-k|T-k} + \sum_{j=1}^h (T^new)^(j-1) C^new) + D^new
    s_new_Tmkph_Tmk = forecast(sys_new, s_new_Tmk_Tmk, h)
    y_new_Tmkph_Tmk = ZZ_new * s_new_Tmkph_Tmk + DD_new

    # y^old_{T-k+h|T-k} = Z^old (T^old^h s^old_{T-k|T-k} + \sum_{j=1}^h (T^old)^(j-1) C^old) + D^old
    s_old_Tmkph_Tmk = forecast(sys_old, s_old_Tmk_Tmk, h)
    y_old_Tmkph_Tmk = ZZ_old * s_old_Tmkph_Tmk + DD_old

    # Parameter re-estimation component = y^new_{T-k+h|T-k} - y^old_{T-k+h|T-k}
    param_comp = y_new_Tmkph_Tmk - y_old_Tmkph_Tmk
    return param_comp
end