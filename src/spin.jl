

"""
    SpinParams{T1, T2}

Spin parameters of an asteroid

# Fields

## Spin pole @ equatorial coordinate
- `α`  # Right ascension (RA)
- `δ`  # Declination (Dec)

## Spin pole @ ecliptic coordinate
- `λ`  # Ecliptic longitude
- `β`  # Ecliptic latitude

## Other parameters
- `P`  # Spin period [sec]
- `ω`  # Angular velocity [rad/sec]
- `ŝ`  # Spin pole direction (normalized)
- `ε`  # Obliquity
- `γ`  # Vernal equinox lon. from the direction of perihelion
"""
struct SpinParams{T1, T2}
    α::T1
    δ::T1

    λ::T1
    β::T1

    P::T1
    ω::T1
    ŝ::T2
    ε::T1

    γ::T1
end


function Base.show(io::IO, spin::Spin)
    println(io, "Spin parameters")
    println(io, "---------------")

    println("Right ascension (RA) : α = ", rad2deg(spin.α), " [deg]")
    println("Declination (Dec)    : δ = ", rad2deg(spin.δ), " [deg]")
    println("Ecliptic longitude   : λ = ", rad2deg(spin.λ), " [deg]")
    println("Ecliptic latitude    : β = ", rad2deg(spin.β), " [deg]")
    println("Obliquity            : ε = ", rad2deg(spin.ε), " [deg]")
    println("Spin period          : P = ", spin.P / 3600,   " [hours]")
    println("Spin rate            : ω = ", spin.ω,          " [rad/sec]")
    println("Vernal equinox lon.  : γ = ", rad2deg(spin.γ), " [deg]")
    println("                           (longitude from the periheion direction)")
end


function Spin(params, orbit::OrbitalElements)

    if haskey(params, :α) && haskey(params, :δ)
        α = deg2rad(params[:α])
        δ = deg2rad(params[:δ])
        λ, β = eq2ec(α, δ)
    elseif haskey(params, :λ) && haskey(params, :β)
        λ = deg2rad(params[:λ])
        β = deg2rad(params[:β])
        α, δ = ec2eq(λ, β)
    else
        println("Give spin pole direction.")
    end
    
    ŝ = spin_normal(λ, β, orbit)  # Orbital plane frame
    ε = acos(ŝ[3])
    γ = vernal_equinox_lon(ŝ)

    P = params[:P] * 3600
    ω = 2π / P

    return Spin(α, δ, λ, β, P, ω, ŝ, ε, γ)
end


function Spin(P::AbstractFloat, ŝ::AbstractVector, orbit)
    
    P *= 3600
    ω = 2π / P
    ε = acos(ŝ[3])
    γ = vernal_equinox_lon(ŝ)
    
    λ = - atan(ŝ[2], ŝ[1])
    β = asin(ŝ[3])
    α, δ = ec2eq(λ, β)

    return Spin(α, δ, λ, β, P, ω, ŝ, ε, γ) 
end


##############################################################################
##############################################################################


"""
Get a spin pole direction in the orbital plane frame

# Paramters
- λ : ecliptic longitude
- β : ecliptic latitude
- orbit : orbital elements
# Return
- ŝ : spin pole direction (normalized)
"""
function spin_normal(λ, β, orbit)
    ŝ = SA_F64[cos(β) * cos(λ), - cos(β) * sin(λ), sin(β)]  # inertial frame
    ŝ = inertia_to_orbit(ŝ, orbit)                          # orbital plane frame
end


"""
    spin_perp_units(spin::Spin) -> ê1, ê2

Get a unit vector ê⟂1 and ê⟂2, perpendicular to spin pole
"""
function spin_perp_units(spin::Spin)
    N̂ = SA_F64[0, 0, 1]
    ê1 = (spin.ŝ * cos(spin.ε) - N̂) / sin(spin.ε)
    ê2 = (spin.ŝ × N̂) / sin(spin.ε)
    
    ê1, ê2
end


"""
    spin_perp_unit1(spin::Spin) -> ê1

Get a unit vector ê⟂1
"""
function spin_perp_unit1(spin::Spin)
    N̂ = SA_F64[0, 0, 1]
    ê1 = (spin.ŝ * cos(spin.ε) - N̂) / sin(spin.ε)
end


"""
    spin_perp_unit2(spin::Spin) -> ê2

Get a unit vector ê⟂2
"""
function spin_perp_unit2(spin::Spin)
    N̂ = SA_F64[0, 0, 1]
    ê2 = (spin.ŝ × N̂) / sin(spin.ε)
end


"""
    vernal_equinox_lon(spin::Spin)        -> γ
    vernal_equinox_lon(ŝ::AbstractVector) -> γ

Get a longitude of the vernal equinox with respect to the perihelion
"""
function vernal_equinox_lon(spin::Spin)
    ê2 = spin_perp_unit2(spin)
    γ = atan(ê2[2], ê2[1]) + π
end

function vernal_equinox_lon(ŝ::AbstractVector)
    N̂ = SA_F64[0, 0, 1]
    ê2 = ŝ × N̂
    γ = atan(ê2[2], ê2[1]) + π
end


"""
    autumnal_equinox_lon(spin::Spin) -> γ_autum

Get a longitude of the autumnal equinox with respect to the perihelion
"""
function autumnal_equinox_lon(spin::Spin)
    ê2 = spin_perp_unit2(spin)
    γ_autum = atan(ê2[2], ê2[1])
    γ_autum < 0 && (γ_autum += 2π)
    γ_autum
end
