
"""
Obtain a dataframe of ephemerides 

# Arguments
- `targ`   : Target body name
- `ets`    : AbstractVetor of observer epoch
- `ref`    : Reference frame of output position vector
- `abcorr` : Aberration correction flag
- `obs`    : Observing body name
"""
function spkpos_df(targ, ets::AbstractVector, ref, abcorr, obs)
    df = DataFrame(et=Float64[], x=Float64[], y=Float64[], z=Float64[], lt=Float64[])
    for et in ets
        pos, lt = SPICE.spkpos(targ, et, ref, abcorr, obs)  # pos [km], lt [s]
        pos = SPICE.convrt.(pos, "km", "m")
        push!(df, (et, pos..., lt))
    end
    df
end


"""
Obtain a vector of position 

# Arguments
- `targ`   : Target body name
- `ets`    : AbstractVetor of observer epoch
- `ref`    : Reference frame of output position vector
- `abcorr` : Aberration correction flag
- `obs`    : Observing body name
"""
function spkpos(targ, ets::AbstractVector, ref, abcorr, obs)
    positions = Vector{Float64}[]
    for et in ets
        pos, lt = SPICE.spkpos(targ, et, ref, abcorr, obs)  # pos [km], lt [s]
        pos = SPICE.convrt.(pos, "km", "m")
        push!(positions, collect(pos))
    end
    positions
end


"""
# Arguments
- `from` : Name of the frame to transform from
- `to`   : Name of the frame to transform to
- `ets`  : Epoch of the rotation matrix

# Return
- `rotate` : A rotation matrix
"""
pxform(from, to, ets) = [SPICE.pxform(from, to, et) for et in ets]

