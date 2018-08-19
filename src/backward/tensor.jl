
## *
function grad!(dy::TAny, ::Val{1},
               op::Call{typeof(*), Tuple{TArray{T1,N1}, TArray{T2,N2}}}) where {T1,N1,T2,N2}
    x, y = op.args
    yt = record!(dy.tape, Call, transpose, (y,))
    return record!(dy.tape, Call, *, (dy, yt))
end

function grad!(dy::TAny, ::Val{2},
               op::Call{typeof(*), Tuple{TArray{T1,N1}, TArray{T2,N2}}}) where {T1,N1,T2,N2}
    x, y = op.args
    xt = record!(dy.tape, Call, transpose, (x,))
    return record!(dy.tape, Call, *, (xt, dy))
end

## +
grad!(dy::TAny, ::Val{1}, op::Call{typeof(+), Tuple{TArray{T,N}, TArray{T,N}}}) where {T,N} = dy
grad!(dy::TAny, ::Val{2}, op::Call{typeof(+), Tuple{TArray{T,N}, TArray{T,N}}}) where {T,N} = dy

## -
grad!(dy::TAny, ::Val{1}, op::Call{typeof(-), Tuple{TArray{T,N}, TArray{T,N}}}) where {T,N} = dy
grad!(dy::TAny, ::Val{2}, op::Call{typeof(-), Tuple{TArray{T,N}, TArray{T,N}}}) where {T,N} = -dy

## sum, mean
function grad!(dy::TAny, ::Val{1}, op::Call{typeof(sum), Tuple{TArray{T,N}}}) where {T,N}
    return record!(dy.tape, Call, sum_grad, (op.args[1], dy); kwargs=op.kwargs)
end
function grad!(dy::TAny, ::Val{1}, op::Call{typeof(mean), Tuple{TArray{T,N}}}) where {T,N}
    return record!(dy.tape, Call, mean_grad, (op.args[1], dy); kwargs=op.kwargs)
end

## transpose
grad!(dy::TAny, ::Val{1}, op::Call{typeof(transpose), Tuple{TArray{T,N}}}) where {T,N} =
    transpose(dy)
# TODO: .==
# TODO: minimum, maximum


## getindex
grad!(dy::TAny, ::Val{1}, op::Call{typeof(getindex), Tuple{TArray{T,N}, TReal}}) where {T,N} =
    ungetindex(dy, op.args[1], op.args[2])
grad!(dy::TAny, ::Val{2}, op::Call{typeof(getindex), Tuple{TArray{T,N}, TReal}}) where {T,N} =
    record!(dy.tape, Constant, 0)


## BROADCASTING

getfirst(x::TAny) = first(x.val)
getfirst(x) = first(x)


function merge_bcast_as_call!(tape::Tape, minitape::Tape, collect_from::Int, var_st::Dict)
    for i=collect_from:length(minitape)
        op = minitape[i]
        if op isa Call
            tape_args = map(x -> tape[var_st[x.id]].var, op.args)
            var = record!(tape, Bcast, op.fn, tape_args)
        elseif op isa Constant
            var = record!(tape, Constant, op.var.val)
        elseif op isa Assign
            # sometimes src size and dest size are different, e.g. in rand(3,4) .+ rand(3)
            # but we handle it in specific methods of grad!
            src_id_in_tape = var_st[op.src.id]
            var = record!(tape, Assign, tape[src_id_in_tape].var)
        else
            error("Unexpected operation in gradient minitape: $op")
        end
        var_st[op.var.id] = var.id  # add to mapping of minitape IDs to tape IDs
    end
end


function grad!(dy::Any, ::Val{Idx}, op::Bcast{FnType, TT}) where {Idx,FnType,TT}
    # record derivatives of first elements onto a minitape
    minitape = Tape()
    el_args = map(arg -> record!(minitape, Input, getfirst(arg)), op.args)
    # run grad! for first elements on the minitape
    el_y = op.fn(el_args...)
    el_dy = record!(minitape, Constant, getfirst(dy))
    el_op = minitape[el_y.id]
    collect_from = length(minitape) + 1
    el_dx = grad!(el_dy, Val(Idx), el_op)
    # merge minitape into tape, replacing Calls with Bcasts and changing op ids
    # initial variable substitution table (var_st) should contain mappings from
    # minitape input vars to corresponding original vars
    var_st = Dict(el_a.id => a.id for (el_a, a) in zip(el_args, op.args))
    var_st[el_dy.id] = dy.id
    tape = dy.tape
    merge_bcast_as_call!(tape, minitape, collect_from, var_st)
    dx = tape[var_st[el_dx.id]].var
    return dx
end


# function grad!(dy::Any, ::Val{Idx},
#                op::Bcast{FnType, Tuple{TArray{T1,N1}, TArray{T2,N2}}}) where {Idx,FnType,T1,N1,T2,N2}
# ...
# end


## SPECIAL BROADCASTING

# handle the case of e.g. rand(3, 4) .+ rand(3, 1)
function grad!(dy::Any, ::Val{1},
               op::Bcast{typeof(+), Tuple{TArray{T1,2}, TArray{T2,2}}}) where {T1,T2}
    x, y = op.args
    xsz = size(x.val)
    ysz = size(y.val)
    if xsz == ysz
         return record!(dy.tape, Assign, dy)
    else
        if xsz[1] == 1 && ysz[1] != 1
            return sum(dy; dims=1)
        elseif xsz[2] == 1 && ysz[2] != 1
            return sum(dy; dims=2)
        else
            return record!(dy.tape, Assign, dy)
        end
    end
end
function grad!(dy::Any, ::Val{2},
               op::Bcast{typeof(+), Tuple{TArray{T1,2}, TArray{T2,2}}}) where {T1,T2}
    x, y = op.args
    xsz = size(x.val)
    ysz = size(y.val)
    if xsz == ysz
         return record!(dy.tape, Assign, dy)
    else
        if xsz[1] != 1 && ysz[1] == 1
            return sum(dy; dims=1)
        elseif xsz[2] != 1 && ysz[2] == 1
            return sum(dy; dims=2)
        else
            return record!(dy.tape, Assign, dy)
        end
    end
end

function grad!(dy::Any, ::Val{1},
               op::Bcast{typeof(+), Tuple{TArray{T1,1}, TArray{T2,2}}}) where {T1,T2}
    return dropdims(sum(dy; dims=2); dims=2)
end
function grad!(dy::Any, ::Val{2},
               op::Bcast{typeof(+), Tuple{TArray{T1,2}, TArray{T2,1}}}) where {T1,T2}
    return dropdims(sum(dy; dims=2); dims=2)
end

function grad!(dy::Any, ::Val{1}, op::Bcast{typeof(+), Tuple{TReal, TArray{T,N}}}) where {T,N}
    return sum(dy)
end
function grad!(dy::Any, ::Val{2}, op::Bcast{typeof(+), Tuple{TArray{T,N}, TReal}}) where {T,N}
    return sum(dy)
end

function grad!(dy::Any, ::Val{1}, op::Bcast{typeof(-), Tuple{TReal, TArray{T,N}}}) where {T,N}
    return sum(dy)
end
function grad!(dy::Any, ::Val{2}, op::Bcast{typeof(-), Tuple{TArray{T,N}, TReal}}) where {T,N}
    return -sum(dy)
end


@require CuArrays="3a865a2d-5b23-5a0f-bc46-62713ec82fae" begin
    import CUDAnative

    function grad!(dy::Any, ::Val{1}, op::Bcast{typeof(CUDAnative.exp),
                                                Tuple{TArray{T,N}}}) where {T,N}
        w = record!(dy.tape, Bcast, CUDAnative.exp, (op.args[1],))
        return record!(dy.tape, Bcast, *, (w,))
    end

    function grad!(dy::Any, ::Val{1}, op::Bcast{typeof(CUDAnative.log),
                                                Tuple{TArray{T,N}}}) where {T,N}
        return record!(dy.tape, Bcast, /, (dy, op.args[1],))
    end

    function grad!(dy::Any, ::Val{1}, op::Bcast{typeof(CUDAnative.sqrt),
                                                Tuple{TArray{T,N}}}) where {T,N}
        # 0.5 .* x .^ (-0.5) .* dy
        w = record!(dy.tape, Bcast, CUDAnative.pow, (op.args[1], constant(dy.tape, -0.5)))
        return 0.5 .* w .* dy
    end

    function grad!(dy::Any, ::Val{1}, op::Bcast{typeof(CUDAnative.pow),
                                                Tuple{TArray{T,N}, R}}) where {T,N,R<:Real}
        # y .* x .^ (y-1) .* dy
        x, y = op.args
        w1 = record!(dy.tape, Bcast, CUDAnative.pow, (x, y-1.0f0))
        w2 = record!(dy.tape, Bcast, *, (y, w1))
        w3 = record!(dy.tape, Bcast, *, (w2, dy))
        return w3
    end

end
