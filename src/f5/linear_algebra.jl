function echelonize!(matrix::MacaulayMatrix,
                     char::Val{Char},
                     shift::Val{Shift}) where {Char, Shift}

    pivots = matrix.pivots
    hash2col = matrix.hash2col
    buffer = zeros(Cbuf, matrix.ncols)
    pivrow = Vector{ColIdx}(undef, matrix.ncols)
    col2hash = Vector{MonIdx}(undef, matrix.ncols)

    # TODO: rethink the whole hash2col, col2hash business
    hash2col_start = 0 
    @inbounds for i in hash2col
        !iszero(i) && break
        hash2col_start += 1
    end
    @inbounds for i in 1:matrix.ncols
        col2hash[hash2col[i+hash2col_start]] = MonIdx(i)
    end

    @inbounds for i in 2:matrix.nrows
        row_ind = matrix.sig_order[i]
        row_cols = matrix.rows[row_ind]

        # check if the row can be reduced
        does_red = false
        for m_idx in row_cols
            colidx = hash2col[m_idx]
            pividx = pivots[colidx]
            does_red = !iszero(pividx) && pividx != i
            does_red && break
        end
        !does_red && continue

        # buffer the row
        # TODO: might not be happy with enumerate
        row_coeffs = matrix.coeffs[row_ind]
        @inbounds for (k, j) in enumerate(row_cols)
            col_idx = matrix.hash2col[j]
            buffer[col_idx] = row_coeffs[k]
        end

        # do the reduction
        @inbounds for j in 1:matrix.ncols
            buffer[j] = buffer[j] % Char
            iszero(buffer[j]) && continue
            if iszero(pivots[j])
                continue
            end

            # subtract m*rows[pivots[j]] from buffer
            a = buffer[j]
            pivcoeffs = matrix.coeffs[pivots[j]]
            b = inv(pivcoeffs[1], char)
            m = mul(a, b, char)

            nops = 0
            pivmons = matrix.rows[pivots[j]]
            @inbounds for (k, m_idx) in enumerate(pivmons)
                pivrow[k] = hash2col[m_idx]
                if !isone(k)
                    nops += 1
                end
            end

            buffer[j] = zero(Cbuf)
            @inbounds for k in 1:nops
                c = pivcoeffs[k]
                colidx = pivrow[k]
                buffer[colidx] = submul(buffer[colidx], m, c, shift)
            end
        end

        # TODO: not so happy with this
        new_row_length = 0
        @inbounds for j in 1:matrix.ncols
            iszero(buffer[j]) && continue
            new_row_length += 1
        end

        # write out matrix row again
        j = 1
        new_row = Vector{MonIdx}(undef, new_row_length)
        new_coeffs = Vector{Coeff}(undef, new_row_length)
        @inbounds for k in 1:matrix.ncols
            # TODO: we shouldnt have to do this here
            buffer[k] = buffer[k] % Char
            iszero(buffer[k]) && continue
            new_row[j] = col2hash[k]
            new_coeffs[j] = buffer[k]
            if isone(j)
                pivots[k] = i
            end
            buffer[k] = zero(Cbuf)
            j += 1
        end
        matrix.rows[i] = new_row
        matrix.coeffs[i] = new_coeffs
    end
end


# helper functions
# field arithmetic
function maxshift(::Val{Char}) where Char
    bufchar = Cbuf(Char)
    return bufchar << leading_zeros(bufchar)
end

# compute a representation of a - b*c mod char (char ~ Shift)
@inline function submul(a::Cbuf, b::Coeff, c::Coeff, ::Val{Shift}) where Shift
    r0 = a - Cbuf(b)*Cbuf(c)
    r1 = r0 + Shift
    r0 > a ? r1 : r0
end

# TODO: why is there typecasting in SignatureGB.jl
@inline function inv(a::Coeff, ::Val{Char}) where Char
    return invmod(a, Char)
end

@inline function mul(a, b, ::Val{Char}) where Char 
    return Coeff((Cbuf(a) * Cbuf(b)) % Char)
end
