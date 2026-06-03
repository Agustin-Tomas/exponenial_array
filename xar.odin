package exponential_array

import "core:mem"
import fmt "core:fmt"
import slice "core:slice"

Header :: struct($T: typeid, $Initial_Capacity: int, $N_Chunks: int) {
    // Memory safety through exponential_array procedures only.
    base: uintptr,  // Base must be a location prior to all chunks.
    // Chunks must be allocated futher than base.
    chunks: [N_Chunks]uintptr, // base+chunk[i] == raw_data([]$T)
    allocator: mem.Allocator,
    array_len: int,
    array_cap: int,
}


append :: proc(at: ^Header($T, $Initial_Capacity, $N_Chunks), item: T) {
    if at.array_cap < at.array_len {
        // copy item into [len]

    }
}

Index_Error :: enum {
    Negative,
    Out_Of_Bounds,
}

chunk_inner_cap :: proc(chunk_idx: int, array: $T/Header) -> (chunk_cap: int, ok: bool) {
    if chunk_idx < 0 {
        // Negative index
        return 0, false
    }
    else if chunk_idx == 0 {
        // First chunk
        return T.Initial_Capacity, true
    }
    else if chunk_idx >= T.N_Chunks {
        // Out of bounds index
        return 0, false
    }
    else {
        // Correct index and not the first chunk
        return T.Initial_Capacity * (1 << uint(chunk_idx - 1)), true
    }
}

get :: proc(from: ^Header($T, $Initial_Capacity, $N_Chunks), index: int) -> (item: T, error: Maybe(Index_Error)) {

    if index < 0 {
        error = Index_Error.Negative
        return
    }

    chunk_idx: int = 0
    max_cap: int = 8

    conditional:
    if index < max_cap {
        // chunk_idx = 0
        break conditional
    }
    else {

        for _chunk_idx := 1; (chunk_i < N_Chunks); chunk_i += 1 {
            max_cap *= 2

            if index < max_cap {
                chunk_idx = _chunk_idx
                break conditional
            }
        }

        // If program reaches here it means item index is out of range of currently
        error = Index_Error.Out_Of_Bounds
        return

    }

    // If I reached here it means chunk_idx is the index of the chunk where the wanted item is.
    // Also max_cap is the capacity up to (and including) the desired chunk.

    // Ahora tengo que encontrar en que indice dentro de ese chunk se encuentra mi objeto segun si indice global

    chunk_local_index := index - (max_cap / 2)
    chunk_location : rawptr = rawptr(from.base + from.chunks[chunk_idx])
    chunk := slice.from_ptr(chunk_location, (max_cap / 2) )
    item = chunk[chunk_local_index]
    return item, nil

}


main :: proc() {
    fmt.println("Hola")

    apple :: struct {
        a: int,
        b: [2]int,
        c: [3]bool,
    }

    apple_bin :: Header(apple, 8, 10)

    new_bin := apple_bin{}

    chunk_inner_cap(0, new_bin)


}
