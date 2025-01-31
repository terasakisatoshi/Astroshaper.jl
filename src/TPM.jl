


# ****************************************************************
#                   Initialize temperatures
# ****************************************************************

"""
    init_temps_zero!(shape::ShapeModel, params)
    init_temps_zero!(shape::ShapeModel, Nz::AbstractVector)
    init_temps_zero!(shape::ShapeModel, Nz::Integer)
    init_temps_zero!(facet::Facet,      Nz::Integer)

Initialize temperature profile in depth on every facet.
All elements are intialized as 0 K.
"""
init_temps_zero!(shape::ShapeModel, params) = init_temps_zero!(shape, params.Nz)

function init_temps_zero!(shape::ShapeModel, Nz::AbstractVector)
    for (i, facet) in enumerate(shape.facets)
        init_temps_zero!(facet, Nz[i])
    end
end

function init_temps_zero!(shape::ShapeModel, Nz::Integer)
    for facet in shape.facets
        init_temps_zero!(facet, Nz)
    end
end

function init_temps_zero!(facet::Facet, Nz::Integer)
    isempty(facet.temps)   ? append!(facet.temps,   zeros(Nz)) : facet.temps   .= 0
    isempty(facet._temps_) ? append!(facet._temps_, zeros(Nz)) : facet._temps_ .= 0
end


# ****************************************************************
#                    Thermophysical modeling
# ****************************************************************

"""
"""
function run_TPM!(shape::ShapeModel, orbit::OrbitalElements, spin::SpinParams, thermo_params::ThermoParams, savepath="tmp.jld2")
    @unpack P, Δt, t_bgn, t_end = thermo_params
    
    init_temps_zero!(shape, thermo_params)

    ts = (t_bgn:Δt:t_end) * P
    timestamp = prep_timestamp(ts)
    # surf_temp_table = zeros(shape.num_face, Int(1/thermo_params.Δt)-1)

    for (i, t) in enumerate(ts)
        update_orbit!(orbit, t)
        update_spin!(spin, t)
            
        r̂☉ = normalize(orbit.r) * -1  # Shift the origin from the sun to the body
        r̂☉ = orbit_to_body(r̂☉, spin)
        
        update_flux_sun!(shape, orbit.F☉, r̂☉)
        update_flux_scat_single!(shape, thermo_params)
        update_flux_rad_single!(shape, thermo_params)
        
        update_force!(shape, thermo_params)
        sum_force_torque!(shape)
        
        f = SVector{3}(shape.force)   # Body-fixed frame
        τ = SVector{3}(shape.torque)  # Body-fixed frame

        f = body_to_orbit(f, spin)  # Orbital plane frame
        τ = body_to_orbit(τ, spin)  # Orbital plane frame

        E_in, E_out, E_cons = energy_io(shape, thermo_params)

        save_timestamp!(timestamp, i, orbit.u, orbit.ν, spin.ϕ, f..., τ..., E_in, E_out, E_cons)
        
        update_temps!(shape, thermo_params)
    end
    mean_energy_cons_frac!(timestamp, spin)
    jldsave(savepath; shape, orbit, spin, thermo_params, timestamp)

    timestamp
end

"""
- `shape`         : Shape model
- `et_range`      : Range of ephemeris times to run
- `sun`           : Sun's position in the body-fixed frame at epochs (Not normalized)
- `thermo_params` : Thermophysical parametes
- `savepath`      : Path to save data file
- `save_range`    : Indices in `et_range` to be saved

"""
function run_TPM!(shape::ShapeModel, et_range, sun, thermo_params::ThermoParams, savepath, save_range)
 
    init_temps_zero!(shape, thermo_params)
    
    surf_temps = zeros(shape.num_face, length(save_range))
    forces  = [zeros(3) for _ in eachindex(save_range)]
    torques = [zeros(3) for _ in eachindex(save_range)]
    
    idx = 1  # Index to save data

    for (et, r☉) in zip(et_range, sun)

        r̂☉ = SVector{3}(normalize(r☉))
        F☉ = SOLAR_CONST / SPICE.convrt(norm(r☉), "m", "au")^2

        update_flux_sun!(shape, F☉, r̂☉)
        update_flux_scat_single!(shape, thermo_params)
        update_flux_rad_single!(shape, thermo_params)

        update_temps!(shape, thermo_params)

        if et_range[save_range[begin]] ≤ et ≤ et_range[save_range[end]]
            update_force!(shape, thermo_params)
            sum_force_torque!(shape)

            surf_temps[:, idx] .= surface_temperature(shape)
            forces[idx]  .= shape.force   # Body-fixed frame
            torques[idx] .= shape.torque  # Body-fixed frame
    
            idx += 1
        end

        E_in, E_out, E_cons = energy_io(shape, thermo_params)
        println(E_cons)
    end
    
    jldsave(savepath; shape, et_range=et_range[save_range], sun=sun[save_range], thermo_params, surf_temps, forces, torques)
end

## torques = data["torques"]
## RYUGU_TO_J2000 = data["RYUGU_TO_J2000"]

## τs = [R * τ for (τ, R) in zip(torques, RYUGU_TO_J2000)]
## τ̄ = sum(τs) / length(τs)
## ŝ = RYUGU_TO_J2000[1] * [0,0,1]

## τ̄ = [-7.401430254063619, -4.461572023742755, -2.1021523476586275]
## ŝ = [-0.04486511842721075, 0.3980298096670074, -0.9162747359634872]


"""
    run_TPM!

Run TPM for a binary asteroid.

- shapes
- ephemerides
- thermo_params
- savepath
- savevalues
"""
function run_TPM!(shapes::Tuple, et_range, suns, S2P, d2_d1, thermo_params::ThermoParams, savepath, savevalues)

    surf_temps = zeros(shapes[1].num_face, length(et_range)), zeros(shapes[2].num_face, length(et_range))
    forces  = [zeros(3) for _ in eachindex(et_range)], [zeros(3) for _ in eachindex(et_range)]
    torques = [zeros(3) for _ in eachindex(et_range)], [zeros(3) for _ in eachindex(et_range)]
    
    ## ProgressMeter setting
    # p = Progress(length(et_range); dt=1, desc="Running TPM...", showspeed=true)
    # ProgressMeter.ijulia_behavior(:clear)

    for (i, et) in enumerate(et_range)
        r☉₁ = suns[1][i]
        r☉₂ = suns[2][i]
        sec_from_pri = d2_d1[i]
        R₂₁ = S2P[i]

        ## Update enegey flux
        update_flux!(shapes[1], r☉₁, thermo_params)
        update_flux!(shapes[2], r☉₂, thermo_params)
        find_eclipse!(shapes, r☉₁, sec_from_pri, R₂₁)  # Mutual-shadowing

        ## Mutual-heating
        #
        #

        for (idx_shape, shape) in enumerate(shapes)
            update_force!(shape, thermo_params)
            sum_force_torque!(shape)

            surf_temps[idx_shape][:, i] .= surface_temperature(shape)
            forces[idx_shape][i]  .= shape.force   # Body-fixed frame
            torques[idx_shape][i] .= shape.torque  # Body-fixed frame
        end
    
        ## Energy input/output
        E_io_pri = energy_io(shapes[1], thermo_params)
        E_io_sec = energy_io(shapes[2], thermo_params)
        println(E_io_pri[3], ", ",  E_io_sec[3])

        ## Update the progress meter
        # showvalues = [(:i, i), (:E_cons_pri, E_io_pri[3]), (:E_cons_sec, E_io_sec[3])]
        # ProgressMeter.next!(p; showvalues)
        
        ## Update temperature distribution
        et == et_range[end] && break  # Stop to update the temperature at the final step
        update_temps!(shapes[1], thermo_params)
        update_temps!(shapes[2], thermo_params)
    end
    
    # jldsave(savepath; shapes, et_range, suns, S2P, thermo_params)
    jldsave(savepath; shapes, et_range, suns, S2P, thermo_params, surf_temps, forces, torques)
end


# ****************************************************************
#                      Data input/output
# ****************************************************************

"""
"""
function prep_timestamp(ts; dtype=Float64)
    Nt = length(ts)
    df = DataFrame(
        t      = ts,
        u      = Vector{dtype}(undef, Nt),
        ν      = Vector{dtype}(undef, Nt),
        ϕ      = Vector{dtype}(undef, Nt),
        f_x    = Vector{dtype}(undef, Nt),
        f_y    = Vector{dtype}(undef, Nt),
        f_z    = Vector{dtype}(undef, Nt),
        τ_x    = Vector{dtype}(undef, Nt),
        τ_y    = Vector{dtype}(undef, Nt),
        τ_z    = Vector{dtype}(undef, Nt),
        E_in   = Vector{dtype}(undef, Nt),
        E_out  = Vector{dtype}(undef, Nt),
        E_cons = Vector{dtype}(undef, Nt),
        Ē_cons = Vector{dtype}(undef, Nt),
    )
end

"""
"""
function save_timestamp!(df, i::Integer, u, ν, ϕ, f_x, f_y, f_z, τ_x, τ_y, τ_z, E_in, E_out, E_cons)
    df.u[i]      = u
    df.ν[i]      = ν
    df.ϕ[i]      = ϕ
    df.f_x[i]    = f_x
    df.f_y[i]    = f_y
    df.f_z[i]    = f_z
    df.τ_x[i]    = τ_x
    df.τ_y[i]    = τ_y
    df.τ_z[i]    = τ_z
    df.E_in[i]   = E_in
    df.E_out[i]  = E_out
    df.E_cons[i] = E_cons
end


# ****************************************************************
#                     Convergence decision
# ****************************************************************

"""
    mean_energy_cons_frac!(df, spin::SpinParams)
    mean_energy_cons_frac!(df, P::Real)

Average energy conservation fraction over a rotational cycle
"""
mean_energy_cons_frac!(df, spin::SpinParams) = mean_energy_cons_frac!(df, spin.P)

function mean_energy_cons_frac!(df, P::Real)
    for row in eachrow(df)
        row.Ē_cons = mean(df.E_cons[@. row.t - P ≤ df.t ≤ row.t])
    end
end


"""
    energy_io(shape::ShapeModel, params::ThermoParams) -> E_in, E_out, E_cons

Input and output energy per second at a certain time

# Returns
- `E_in`   : Input energy per second at a certain time [W]
- `E_out`  : Output enegey per second at a certain time [W]
- `E_cons` : Output-input energy ratio (`E_out / E_in`)
"""
function energy_io(shape::ShapeModel, params::ThermoParams)
    E_in   = energy_in(shape, params)
    E_out  = energy_out(shape, params)
    E_cons = E_out / E_in

    E_in, E_out, E_cons
end


"""
    energy_in(shape::ShapeModel, params::ThermoParams) -> E_in
    energy_in(shape::ShapeModel, A_B::AbstractVector ) -> E_in
    energy_in(shape::ShapeModel, A_B::Real           ) -> E_in
    energy_in(facet::Facet,      A_B::Real           ) -> E_in

Input energy per second at a certain time [W]
"""
energy_in(shape::ShapeModel, params::ThermoParams) = energy_in(shape, params.A_B)
energy_in(shape::ShapeModel, A_B::AbstractVector) = sum(energy_in(facet, A_B[i]) for (i, facet) in enumerate(shape.facets))
energy_in(shape::ShapeModel, A_B::Real) = sum(energy_in(facet, A_B) for facet in shape.facets)
energy_in(facet::Facet, A_B::Real) = (1 - A_B) * (facet.flux.sun + facet.flux.scat) * facet.area


"""
    energy_out(shape::ShapeModel, params::ThermoParams                   ) -> E_out
    energy_out(shape::ShapeModel, ϵ::AbstractVector, A_TH::AbstractVector) -> E_out
    energy_out(shape::ShapeModel, ϵ::Real,           A_TH::Real          ) -> E_out
    energy_out(facet::Facet,      ϵ::Real,           A_TH::Real          ) -> E_out

Output enegey per second at a certain time [W]
"""
energy_out(shape::ShapeModel, params::ThermoParams) = energy_out(shape, params.ϵ, params.A_TH)
energy_out(shape::ShapeModel, ϵ::AbstractVector, A_TH::AbstractVector) = sum(energy_out(facet, ϵ[i], A_TH[i]) for (i, facet) in enumerate(shape.facets))
energy_out(shape::ShapeModel, ϵ::Real, A_TH::Real) = sum(energy_out(facet, ϵ, A_TH) for facet in shape.facets)
energy_out(facet::Facet, ϵ::Real, A_TH::Real) = ( ϵ*σ_SB*facet.temps[begin]^4 - (1 - A_TH)*facet.flux.rad ) * facet.area


# ****************************************************************
#        Energy flux of sunlight, scattering, and radiation
# ****************************************************************


"""
    update_flux!(shape, F☉, r̂☉, thermo_params)

Update energy flux to every facet by solar radiation, scattering, and re-absorption of radiation
"""
function update_flux!(shape, F☉::Real, r̂☉::AbstractVector, thermo_params)
    update_flux_sun!(shape, F☉, r̂☉)
    update_flux_scat_single!(shape, thermo_params)
    update_flux_rad_single!(shape, thermo_params)
end

function update_flux!(shape, r☉::AbstractVector, thermo_params)
    update_flux_sun!(shape, r☉)
    update_flux_scat_single!(shape, thermo_params)
    update_flux_rad_single!(shape, thermo_params)
end

"""
    update_flux_sun!(shape, F☉, r̂☉)

Update solar radiation flux on every facet of a shape model.

- `shape` : Shape model
- `F☉`    : Solar radiation flux
- `r̂☉`    : Unit vector indicating the direction of the sun in the body-fixed frame
"""
function update_flux_sun!(shape, F☉, r̂☉)
    for facet in shape.facets
        if isIlluminated(facet, r̂☉, shape)
            facet.flux.sun = F☉ * (facet.normal ⋅ r̂☉)
        else
            facet.flux.sun = 0
        end
    end
end

"""
    update_flux_sun!(shape, r☉::AbstractVector)

Update solar radiation flux on every facet of a shape model.

- `shape` : Shape model
- `r☉`    : Position of the sun in the body-fixed frame, which is not normalized.
"""
function update_flux_sun!(shape, r☉::AbstractVector)
    r̂☉ = SVector{3}(normalize(r☉))
    F☉ = SOLAR_CONST / SPICE.convrt(norm(r☉), "m", "au")^2

    update_flux_sun!(shape, F☉, r̂☉)
end


"""
The secondary is within the critical angle to detect an eclipse event.
"""
function eclipse_is_possible(shapes, sun_from_pri, sec_from_pri)

    R₁ = shapes[1].RADIUS_MAX
    R₂ = shapes[2].RADIUS_MAX
    θ_crit = asin((R₁ + R₂) / norm(sec_from_pri))

    r̂☉ = SVector{3}(normalize(sun_from_pri))
    r̂ₛ = SVector{3}(normalize(sec_from_pri))
    θ = acos(r̂☉ ⋅ r̂ₛ)  # Angle of Sun-Primary-Secondary

    θ_crit < θ < π - θ_crit ? false : true
end


"""
    find_eclipse!(shapes, sun_from_pri, sec_from_pri, R₂₁)

- `shapes`
- `sun_from_pri`
- `sec_from_pri` : Position of the secondary relative to primary
- `R₂₁`          : Rotation matrix from secondary to primary
"""
function find_eclipse!(shapes, sun_from_pri, sec_from_pri, R₂₁)

    r̂☉ = SVector{3}(normalize(sun_from_pri))
    # r̂ₛ = SVector{3}(normalize(sec_from_pri))
    rₛ = SVector{3}(sec_from_pri)

    # cosθ = r̂☉ ⋅ r̂ₛ  # Cosine of angle of Sun-Primary-Secondary

    eclipse_is_possible(shapes, r̂☉, rₛ) == false && return

    for facet1 in shapes[1].facets
        facet1.flux.sun == 0 && continue
        for facet2 in shapes[2].facets
            facet2.flux.sun == 0 && continue
        
            ## Facet ABC of the secondary in the primary-fixed frame
            A = rₛ + R₂₁ * facet2.A
            B = rₛ + R₂₁ * facet2.B
            C = rₛ + R₂₁ * facet2.C
            center2 = rₛ + R₂₁ * facet2.center

            raycast(A, B, C, r̂☉, facet1) && (facet1.flux.sun = 0)
            raycast(facet1, r̂☉, center2) && (facet2.flux.sun = 0)
        end
    end
end


"""
    update_flux_scat_single!(shape, params)
    update_flux_scat_single!(shape, A_B::Real)
    update_flux_scat_single!(shape, A_B::AbstractVector)

Single scattering of sunlight is considered.
"""
update_flux_scat_single!(shape, params::ThermoParams) = update_flux_scat_single!(shape, params.A_B)

function update_flux_scat_single!(shape, A_B::Real)
    for facet in shape.facets
        facet.flux.scat = 0
        for (id, f) in zip(facet.visiblefacets.id, facet.visiblefacets.f)
            facet.flux.scat += f * A_B * shape.facets[id].flux.sun
        end
    end
end

function update_flux_scat_single!(shape, A_B::AbstractVector)
    for facet in shape.facets
        facet.flux.scat = 0
        for (id, f) in zip(facet.visiblefacets.id, facet.visiblefacets.f)
            facet.flux.scat += f * A_B[id] * shape.facets[id].flux.sun
        end
    end
end

"""
    update_flux_scat_mult!(shape, params)

Multiple scattering of sunlight is considered.
"""
# update_flux_scat_mult!(shape, params::ThermoParams) = update_flux_scat_mult!(shape, params.A_B)

# function update_flux_scat_mult!(shape, A_B::Real)
#     for facet in shape.facets
#         facet.flux.scat = 0
#         for (id, f) in zip(facet.visiblefacets.id, facet.visiblefacets.f)
#             facet.flux.scat += f * A_B * shape.facets[id].flux.sun
#         end
#     end
# end

# function update_flux_scat_mult!(shape, A_B::AbstractVector)
#     for facet in shape.facets
#         facet.flux.scat = 0
#         for (id, f) in zip(facet.visiblefacets.id, facet.visiblefacets.f)
#             facet.flux.scat += f * A_B[id] * shape.facets[id].flux.sun
#         end
#     end
# end

"""
    update_flux_rad_single!(shape, params)
    update_flux_rad_single!(shape, ϵ::Real)
    update_flux_rad_single!(shape, ϵ::AbstractVector)

Single radiation-reabsorption is considered,
assuming albedo is close to zero at thermal infrared wavelength.
"""
update_flux_rad_single!(shape, params::ThermoParams) = update_flux_rad_single!(shape, params.ϵ)

function update_flux_rad_single!(shape, ϵ::Real)
    for facet in shape.facets
        facet.flux.rad = 0
        for (id, f) in zip(facet.visiblefacets.id, facet.visiblefacets.f)
            T = shape.facets[id].temps[begin]
            facet.flux.rad += f * ϵ * σ_SB * T^4
        end
    end
end

function update_flux_rad_single!(shape, ϵ::AbstractVector)
    for facet in shape.facets
        facet.flux.rad = 0
        for (id, f) in zip(facet.visiblefacets.id, facet.visiblefacets.f)
            T = shape.facets[id].temps[begin]
            facet.flux.rad += f * ϵ[id] * σ_SB * T^4
        end
    end
end

