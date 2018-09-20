using DSGE, JLD2
using Base.Test

path = dirname(@__FILE__)

# Set up arguments
m = AnSchorfheide(testing = true)

system = jldopen("$path/../reference/forecast_args.jld","r") do file
    read(file, "system")
end

# Run impulse responses
states, obs, pseudo = impulse_responses(m, system)

# Compare to expected output
exp_states, exp_obs, exp_pseudo =
    jldopen("$path/../reference/impulse_responses_out.jld", "r") do file
        read(file, "exp_states"), read(file, "exp_obs"), read(file, "exp_pseudo")
    end

@testset "Compare irfs to expected output" begin
    @test @test_matrix_approx_eq exp_states states
    @test @test_matrix_approx_eq exp_obs    obs
    @test @test_matrix_approx_eq exp_pseudo pseudo
end

nothing
