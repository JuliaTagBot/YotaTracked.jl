
## *
grad!(dy::TAny, ::Val{1}, op::Call{typeof(*), Tuple{TReal, TReal}}) = dy * op.args[2]
grad!(dy::TAny, ::Val{2}, op::Call{typeof(*), Tuple{TReal, TReal}}) = dy * op.args[1]

## /
grad!(dy::TAny, ::Val{1}, op::Call{typeof(*), Tuple{TReal, TReal}}) = dy / op.args[2]
grad!(dy::TAny, ::Val{2}, op::Call{typeof(*), Tuple{TReal, TReal}}) =
    begin x, y = op.args; -x * dy / (y * y) end

## +
function grad!(dy::TAny, ::Val{1}, op::Call{typeof(+), Tuple{TReal, TReal}})
    x, y = op.args
    return record!(dy.tape, Assign, dy)
end
function grad!(dy::TAny, ::Val{2}, op::Call{typeof(+), Tuple{TReal, TReal}})
    x, y = op.args
    return record!(dy.tape, Assign, dy)
end

## -
function grad!(dy::TAny, ::Val{1}, op::Call{typeof(-), Tuple{TReal, TReal}})
    x, y = op.args
    return record!(dy.tape, Assign, dy)
end
function grad!(dy::TAny, ::Val{2}, op::Call{typeof(-), Tuple{TReal, TReal}})
    x, y = op.args
    return record!(dy.tape, Call, -, (dy,))
end

## ^
function grad!(dy::TAny, ::Val{1}, op::Call{typeof(^), Tuple{TReal, TReal}})
    x, y = op.args
    return y * x ^ (y-1) * dy
end
function grad!(dy::TAny, ::Val{2}, op::Call{typeof(^), Tuple{TReal, TReal}})
    x, y = op.args
    return log(x) * x ^ y * dy  # this seems to be broken: log of negative number is undefined
end

## single arg functions
grad!(dy::TAny, ::Val{1}, op::Call{typeof(-), Tuple{TReal}}) = -dy
grad!(dy::TAny, ::Val{1}, op::Call{typeof(sin), Tuple{TReal}}) = cos(op.args[1]) * dy
grad!(dy::TAny, ::Val{1}, op::Call{typeof(cos), Tuple{TReal}}) = -sin(op.args[1]) * dy
grad!(dy::TAny, ::Val{1}, op::Call{typeof(log), Tuple{TReal}}) = dy / op.args[1]
grad!(dy::TAny, ::Val{1}, op::Call{typeof(exp), Tuple{TReal}}) = exp(op.args[1]) * dy
grad!(dy::TAny, ::Val{1}, op::Call{typeof(abs), Tuple{TReal}}) = sign(op.args[1]) * dy
grad!(dy::TAny, ::Val{1}, op::Call{typeof(abs2), Tuple{TReal}}) = 2 * op.args[1] * dy
grad!(dy::TAny, ::Val{1}, op::Call{typeof(sign), Tuple{TReal}}) = 0
grad!(dy::TAny, ::Val{1}, op::Call{typeof(tanh), Tuple{TReal}}) =
    (x = op.args[1]; t = tanh(x); (1.0 - t * t)  * dy)
grad!(dy::TAny, ::Val{1}, op::Call{typeof(sqrt), Tuple{TReal}}) = 0.5 * op.args[1] ^ (-0.5) * dy
