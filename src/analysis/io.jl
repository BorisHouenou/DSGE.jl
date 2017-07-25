################################################################
## I/O to create MeansBands objects
################################################################

"""
```
get_meansbands_input_files(m, input_type, cond_type, output_vars;
    forecast_string = "", fileformat = :jld)
```

```
get_meansbands_input_files(directory, filestring_base, input_type, cond_type, output_vars;
    forecast_string = "", fileformat = :jld)
```

Returns a dictionary of raw forecast output files to read in to compute means
and bands.

### Inputs

**Method 1:**

- `m::AbstractModel`

**Method 2:**

- `directory::String`: directory location of input files to read
- `filestring_base::Vector{String}`: a vector of strings to be added as
  a suffix. These usually come from model settings for which `print = true`. It
  should *not* include entries for `cond_type` and `input_type` (these will be
  added automatically).

**Both methods:**

- `input_type::Symbol`: See `?forecast_one`
- `cond_type::Symbol`: See `?forecast_one`
- `output_vars::Symbol`: See `?forecast_one`
- `forecast_string::String`: See `?forecast_one`
- `fileformat`: file extension of saved files
"""
function get_meansbands_input_files(m::AbstractModel, input_type::Symbol,
                                    cond_type::Symbol, output_vars::Vector{Symbol};
                                    forecast_string::String = "", fileformat = :jld)

    directory = rawpath(m, "forecast")
    base = filestring_base(m)
    get_meansbands_input_files(directory, base, input_type, cond_type, output_vars;
                               forecast_string = forecast_string,
                               fileformat = fileformat)
end

function get_meansbands_input_files(directory::String, filestring_base::Vector{String},
                                    input_type::Symbol, cond_type::Symbol, output_vars::Vector{Symbol};
                                    forecast_string::String = "", fileformat::Symbol = :jld)

    input_files = Dict{Symbol, String}()
    for var in output_vars
        input_files[var] = get_forecast_filename(directory, filestring_base,
                                                 input_type, cond_type, var,
                                                 forecast_string = forecast_string,
                                                 fileformat = fileformat)
        if contains(string(var), "forecast4q")
            input_files[var] = replace(input_files[var], "forecast4q", "forecast")
        elseif contains(string(var), "hist4q")
            input_files[var] = replace(input_files[var], "hist4q", "hist")
        end
    end

    return input_files
end


################################################################
## I/O for actual MeansBands objects
################################################################

"""
```
get_meansbands_output_files(m, input_type, cond_type, output_vars;
    forecast_string = "", fileformat = :jld)
```

```
get_meansbands_output_files(directory, filestring_base, input_type, cond_type, output_vars;
    forecast_string = "", fileformat = :jld)
```

Returns a dictionary of raw forecast output files in which to save
computed means and bands.

### Inputs

**Method 1:**

- `m::AbstractModel`: Model object

**Method 2:**

- `directory::String`: directory location of input files to read
- `filestring_base::Vector{String}`: a vector of strings to be
  added as a suffix. These usually come from model settings for which
  print=true. It should *not* include entries for `cond_type` and
  `input_type` (these will be added automatically).

**Both methods:**

- `input_type::Symbol`: See `?forecast_one`
- `cond_type::Symbol`: See `?forecast_one`
- `output_vars::Symbol`: See `?forecast_one`
- `forecast_string::String`: See `?forecast_one`
- `fileformat`: file extension of saved files
"""
function get_meansbands_output_files(m::AbstractModel, input_type::Symbol,
                                     cond_type::Symbol, output_vars::Vector{Symbol};
                                     forecast_string::String = "",
                                     fileformat::Symbol = :jld)

    directory = workpath(m, "forecast")
    base = filestring_base(m)
    get_meansbands_output_files(directory, base, input_type, cond_type, output_vars;
                                forecast_string = forecast_string, fileformat = fileformat)
end

function get_meansbands_output_files(directory::String,
                                     filestring_base::Vector{String},
                                     input_type::Symbol, cond_type::Symbol, output_vars::Vector{Symbol};
                                     forecast_string::String = "", fileformat = :jld)

    mb_output_vars = [Symbol("mb$x") for x in output_vars]
    output_files = Dict{Symbol, String}()
    for var in output_vars
        output_files[var] = get_forecast_filename(directory, filestring_base,
                                                  input_type, cond_type, Symbol("mb$var");
                                                  forecast_string = forecast_string,
                                                  fileformat = fileformat)
    end
    return output_files
end

"""
```
read_mb(fn::String)

read_mb(m, input_type, cond_type, output_var; forecast
```

Read in a `MeansBands` object saved in `fn`, or use the model object `m` to
determine the file location.
"""
function read_mb(fn::String)
    @assert isfile(fn) "File $fn could not be found"
    jldopen(fn, "r") do f
        read(f, "mb")
    end
end

function read_mb(m::AbstractModel, input_type::Symbol, cond_type::Symbol,
                 output_var::Symbol; forecast_string::String = "")

    files = get_meansbands_output_files(m, input_type, cond_type, [output_var];
                                        forecast_string = forecast_string,
                                        fileformat = :jld)
    read_mb(files[output_var])
end


################################################################
## I/O for human-readable csvs
################################################################

"""
```
write_meansbands_tables(dirname, mb, tablevar, [forecast_string = ""],
           [mb_trend = MeansBands()], [mb_dettrend = MeansBands()], [columnvars = []])

write_meansbands_tables(m, mb, [tablevars = tablevars], [forecast_string = forecast_string],
              [mb_trend = MeansBands()], [mb_dettrend = MeansBands()], [columnvars = []])
```

Write means and bands (ordered) to a csv file in `tablespath(m, "forecast")`.

To produce results that can be printed to a flat csv file, we must
choose exactly which dimensions we want to print to each file. For
instance, when we print a shock decomposition, we would like to print
one table for each economic variable in question, with columns
representing the response of that variable to a particular
shock. However, when printing irfs, we would like to group first by
the shock in question, and then print tables for variables responding
to that shock (note, however, that because we print bands for irfs,
each file will represent a particular shock-variable pair). This
function groups first by the elements of `tablevar`, and then by the
elements of `columnvars`.

### Inputs

- `m::AbstractModel`
- `mb::MeansBands`

### Keyword arguments
- `tablevars`: a `Symbol` or `Vector{Symbol}` indicating which
  variable in `mb` you want to print means and bands for. For
  shockdecs, histories, and forecasts, this should be a vector of
  economic variable names (either pseudoobservables or
  observables). For irfs, this should be names of shocks. If left out or
  empty, means and bands for all variables in `mb` will be printed.
- `forecast_string::String`: See `?forecast_one`
- `mb_trend::MeansBands`: a `MeansBands` object for a trend
  product. This is required when `mb` contains means and bands for
  a shock decomposition.
- `mb_dettrend::MeansBands`: a `MeansBands` object for a deterministic trend
  product. This is required when `mb` contains means and bands for
  a shock decomposition.
- `columnvars::Vector{Symbol}`: If `mb` is a shock decomposition, this is
  an optional list of shocks to print to the table. If omitted, all
  shocks will be printed. For irfs, this is an optional list of variables to print to separate tables.
"""
function write_meansbands_tables(m::AbstractModel, mb::MeansBands, tablevar::Symbol;
                                 forecast_string::String = "",
                                 mb_trend::MeansBands = MeansBands(),
                                 mb_dettrend::MeansBands = MeansBands(),
                                 mb_forecast::MeansBands = MeansBands(),
                                 mb_hist::MeansBands = MeansBands(),
                                 columnvars::Vector{Symbol} = Vector{Symbol}())

    # Use model object to compute output directory and settings suffix
    dir = tablespath(m, "forecast")
    base = DSGE.filestring_base(m)

    # Call lower-level function
    write_meansbands_tables(dir, mb, tablevar, columnvars = columnvars, filestring_base = base,
                            forecast_string = forecast_string,
                            mb_trend = mb_trend, mb_dettrend = mb_dettrend,
                            mb_forecast = mb_forecast, mb_hist = mb_hist)
end

function write_meansbands_tables(m::AbstractModel, mb::MeansBands;
                                 tablevars::Vector{Symbol} = Vector{Symbol}(),
                                 mb_trend::MeansBands = MeansBands(),
                                 mb_dettrend::MeansBands = MeansBands(),
                                 mb_forecast::MeansBands = MeansBands(),
                                 mb_hist::MeansBands = MeansBands(),
                                 columnvars::Vector{Symbol} = Vector{Symbol}())

    # Use all vars by default
    if isempty(tablevars)
        tablevars = if get_product(mb) in [:irf, :shockdec]
            get_variables(mb)
        else
            get_vars_means(mb)
        end
    end

    # Write table for each var
    for tablevar in tablevars
        write_meansbands_tables(m, mb, tablevar,
                                mb_trend = mb_trend, mb_dettrend = mb_dettrend,
                                mb_forecast = mb_forecast, mb_hist = mb_hist, columnvars = columnvars)
    end
end

function write_meansbands_tables(dirname::String, mb::MeansBands;
                                 tablevars::Vector{Symbol} = Vector{Symbol}(),
                                 filestring_base::Vector{String} = Vector{String}(),
                                 forecast_string::String = "",
                                 mb_trend::MeansBands = MeansBands(),
                                 mb_dettrend::MeansBands = MeansBands(),
                                 mb_forecast::MeansBands = MeansBands(),
                                 mb_hist::MeansBands = MeansBands(),
                                 columnvars::Vector{Symbol} = Vector{Symbol}())
    # Use all vars by default
    if isempty(tablevars)
        tablevars = get_variables(mb)
    end

    # Write table for each var
    for var in tablevars
        write_meansbands_tables(dirname, mb, var, filestring_base = filestring_base,
                                forecast_string = forecast_string,
                                mb_trend = mb_trend, mb_dettrend = mb_dettrend,
                                columnvars = columnvars, mb_forecast = mb_forecast, mb_hist = mb_hist)
    end
end

function write_meansbands_tables(dirname::String, mb::MeansBands, tablevar::Symbol;
                                 filestring_base::Vector{String} = Vector{String}(),
                                 forecast_string::String = "",
                                 mb_trend::MeansBands = MeansBands(),
                                 mb_dettrend::MeansBands = MeansBands(),
                                 mb_forecast::MeansBands = MeansBands(),
                                 mb_hist::MeansBands = MeansBands(),
                                 columnvars::Vector{Symbol} = Vector{Symbol}())

    # What product are we making here?
    prod = get_product(mb)

    # Compute output filename
    filename = detexify("$prod" * "$tablevar.csv")
    filestring_addl = DSGE.get_forecast_filestring_addl(get_para(mb), get_cond_type(mb), forecast_string = forecast_string)
    fullfilename = DSGE.savepath(dirname, filename, filestring_base, filestring_addl)

    # Extract dataframe
    if prod in [:hist, :forecast, :hist4q, :forecast4q, :bddforecast, :bddforecast4q, :trend, :dettrend]
        df = prepare_meansbands_table_timeseries(mb, tablevar)

        # Write to file
        writetable(fullfilename, df)
        println(" * Wrote means and bands for $tablevar to $fullfilename")

    elseif prod in [:shockdec]
        @assert !isempty(mb_trend)    "Please pass in mb_trend"
        @assert !isempty(mb_dettrend) "Please pass in mb_dettrend"

        df = prepare_means_table_shockdec(mb, mb_trend, mb_dettrend, tablevar, shocks = columnvars,
                                     mb_forecast = mb_forecast, mb_hist = mb_hist)

        # Write to file
        writetable(fullfilename, df)
        println(" * Wrote means and bands for $tablevar to $fullfilename")
    elseif prod in [:irf]
        # for irfs, we group first by shock, then by variable
        for columnvar in columnvars
            df = prepare_meansbands_table_irf(mb, tablevar, columnvar)

            # Write to file
            writetable(fullfilename, df)
            println(" * Wrote means and bands for $tablevar, $columnvar to $fullfilename")
        end
    end


    return df
end

"""
```
write_meansbands_tables_all(m, input_type, cond_type, output_vars;
    forecast_string = "", vars = [], shocks = shocks)
```

Writes all `output_vars` corresponding to model `m` to tables in `tablespath(m, \"forecast\")`.

### Inputs

- `m::AbstractModel`
- `input_type::Symbol`: See `?forecast_one`
- `cond_type::Symbol`: See `?forecast_one`
- `output_vars::Symbol`: See `?forecast_one`

### Keyword Arguments

- `forecast_string::String`: See `?forecast_one`
- `vars`::Vector{Symbol}: Vector of economic variables for which to
  print `output_vars` to tables. If omitted, all shocks will be
  printed.
- `shocks::Vector{Symbol}`: Vector of shocks to print if `output_vars`
  contains a shock decomposition. If omitted, all shocks will be
  printed.
"""
function write_meansbands_tables_all(m::AbstractModel, input_type::Symbol, cond_type::Symbol,
                                     output_vars::Vector{Symbol};
                                     forecast_string = "",
                                     vars::Vector{Symbol} = Vector{Symbol}(),
                                     shocks::Vector{Symbol} = Vector{Symbol}())

    # Create a dictionary of all means and bands
    mbs = Dict{Symbol, MeansBands}()

    # # Figure out stuff for filename
    filestring_addl = DSGE.get_forecast_filestring_addl(input_type, cond_type,
                                                        forecast_string = forecast_string)

    # Read in appropriate means and bands
    my_output_vars = add_requisite_output_vars_meansbands(output_vars)

    for class in [:pseudo, :obs]
        if !isempty(intersect(my_output_vars, [Symbol("hist$class"), Symbol("histforecast$class")]))
            mbs[Symbol("hist$class")] =
                read_mb(workpath(m, "forecast", "mbhist$class.jld", filestring_addl))
        end
        if !isempty(intersect(my_output_vars, [Symbol("forecast$class"), Symbol("histforecast$class")]))
            mbs[Symbol("forecast$class")] =
                read_mb(workpath(m, "forecast", "mbforecast$class.jld", filestring_addl))
        end
        if !isempty(intersect(my_output_vars, [Symbol("bddforecast$class"), Symbol("bddhistforecast$class")]))
            mbs[Symbol("bddforecast$class")] =
                read_mb(workpath(m, "forecast", "mbbddforecast$class.jld", filestring_addl))
        end
        if !isempty(intersect(my_output_vars, [Symbol("hist4q$class"), Symbol("histforecast4q$class")]))
            mbs[Symbol("hist4q$class")] =
                read_mb(workpath(m, "forecast", "mbhist4q$class.jld", filestring_addl))
        end
        if !isempty(intersect(my_output_vars, [Symbol("forecast4q$class"), Symbol("histforecast4q$class")]))
            mbs[Symbol("forecast4q$class")] =
                read_mb(workpath(m, "forecast", "mbforecast4q$class.jld", filestring_addl))
        end
        if !isempty(intersect(my_output_vars, [Symbol("bddforecast4q$class"), Symbol("bddhistforecast4q$class")]))
            mbs[Symbol("bddforecast4q$class")] =
                read_mb(workpath(m, "forecast", "mbbddforecast4q$class.jld", filestring_addl))
        end
        if Symbol("shockdec$class") in my_output_vars
            mbs[Symbol("shockdec$class")] =
                read_mb(workpath(m, "forecast", "mbshockdec$class.jld", filestring_addl))
        end
        if Symbol("dettrend$class") in my_output_vars
            mbs[Symbol("dettrend$class")] =
                read_mb(workpath(m, "forecast", "mbdettrend$class.jld", filestring_addl))
        end
        if Symbol("trend$class") in my_output_vars
            mbs[Symbol("trend$class")] =
                read_mb(workpath(m, "forecast", "mbtrend$class.jld", filestring_addl))
        end
        if Symbol("irf$class") in my_output_vars
            mbs[Symbol("irf$class")] =
                read_mb(workpath(m, "forecast", "mbirf$class.jld", filestring_addl))
        end

    end

    # write each output to CSV
    for output in output_vars

        class = get_class(output)

        df = if output in [:histpseudo, :histobs, :forecastpseudo, :forecastobs,
                           :trendpseudo, :trendobs, :dettrendpseudo, :dettrendobs]

            write_meansbands_tables(m, mbs[output], tablevars = vars)

        elseif output in [:histforecastpseudo, :histforecastobs]

            mb_histforecast = cat(mb[Symbol("hist$(class)")], mb[Symbol("forecast$class")])
            write_meansbands_tables(m, mb_histforecast, tablevars = vars)

        elseif output in [:histforecast4qpseudo, :histforecast4qobs]

            mb_histforecast = cat(mb[Symbol("hist4q$(class)")], mb[Symbol("forecast4q$class")])
            write_meansbands_tables(m, mb_histforecast, tablevars = vars)

        elseif output in [:shockdecpseudo, :shockdecobs]

            mb_shockdec = mbs[Symbol("shockdec$(class)")]
            mb_trend    = mbs[Symbol("trend$(class)")]
            mb_dettrend = mbs[Symbol("dettrend$(class)")]
            mb_forecast = mbs[Symbol("forecast$(class)")]
            mb_hist     = mbs[Symbol("hist$(class)")]

            write_meansbands_tables(m, mb_shockdec, mb_trend = mb_trend, mb_dettrend = mb_dettrend,
                                    mb_hist = mb_hist, mb_forecast = mb_forecast,
                                    tablevars = vars, columnvars = shocks)
        elseif output in [:irfpseudo, :irfobs]

            write_meansbands_tables(m, mbs[output], tablevars = shocks, columnvars = vars)
        end
    end
end

function add_requisite_output_vars_meansbands(output_vars)

    all_output_vars = add_requisite_output_vars(output_vars)

    if :shockdecpseudo in all_output_vars
        push!(all_output_vars, :histforecastpseudo)
    end
    if :shockdecobs in all_output_vars
        push!(all_output_vars, :histforecastobs)
    end

    return all_output_vars
end