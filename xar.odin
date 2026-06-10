package exponential_array

import "core:mem"
import fmt "core:fmt"
import slice "core:slice"
import "core:reflect"
import "base:runtime"
import intrinsics "base:intrinsics"



/*
API of the exponential array.
Data chunks must be stored anywhere further from base pointer.
Base pointer may be the adress of the header.
If base pointer is the adress of the header then header and chunks must be both contained in a memory stable container
for POD-safe copy.
Base pointer must be reseted after memcopy.
*/




// Data structure
Header :: struct($T: typeid, $N_Chunks: int, $Initial_Capacity: int,) {
    allocator: ^mem.Allocator,
    base: uintptr,
    data: [N_Chunks]uintptr,  // base+chunk[i] == raw_data([]$T)

    /*
    raw_chunk_data: [^]T = rawptr(data[chunk_idx])
    chunk: []T = raw_chunk_data[0: chunk_capacity]
    */

    n_allocated_chunks: int,
    length: int,
    capacity: int,
}


// for initializing and setting up when moving header alongside it's backing data.
init_header :: proc(header: ^Header, allocator: ^mem.Allocator) {
    header.base = uintptr(header)
    header.allocator = allocator
}

append_item :: proc(header: ^Header($T, $Initial_Capacity, $N_Chunks), item: T) {
    if header.capacity > header.length {
        // copy item into [len]
        item_ptr, err := get_item_ptr(header, header.length)
        if err == nil {
            header.length += 1
            item_ptr^ = item
        }
        else {
            fmt.println("Pointer to item could not be retrieved.", err)
        }
    }
    else {
        // allocate new chunk
        fmt.println("Could not append")
    }
}

Index_Error :: enum {
    Negative,
    Out_Of_Bounds,
}


get_item :: proc(header: ^Header($T, $N_Chunks, $Initial_Capacity), index: int) -> (item: T, error: Maybe(Index_Error)) {

    item_ptr: ^T
    item_ptr, error = get_item_ptr(header, index)
    return item_ptr^, error

}

get_item_ptr :: proc(header: ^Header($T, $N_Chunks, $Initial_Capacity), index: int) -> (item_ptr: ^T, error: Maybe(Index_Error)) {

    if index < 0 {
        return nil, Index_Error.Negative
    }

    if index >= header.capacity {
        return nil, Index_Error.Out_Of_Bounds
    }

    chunk_idx: int = 0
    accumulated_capacity: int = 0


    accumulated_capacity += _chunk_capacity(chunk_idx, header^) or_else 0
    chunk_idx += 1
    for index >= accumulated_capacity { /*This is guaranted to finish*/
        accumulated_capacity += _chunk_capacity(chunk_idx, header^) or_else 0
        chunk_idx += 1
    }
    chunk_idx -= 1

    // If I reached here it means chunk_idx is the index of the chunk where the wanted item is.
    // Also max_cap is the capacity up to (and including) the desired chunk.

    // Ahora tengo que encontrar en que indice dentro de ese chunk se encuentra mi objeto segun si indice global

    n_items_on_chunk := _chunk_capacity(chunk_idx, header^) or_else 0
    chunk_local_index := index - (header.capacity - n_items_on_chunk)
    chunk_location : rawptr = rawptr(header.base + header.data[chunk_idx])
    first_item : ^T = cast(^T)(chunk_location)  // Pointer to first item in chunk
    typed_chunk := slice.from_ptr(first_item, n_items_on_chunk )
    item_ptr = &typed_chunk[chunk_local_index]
    return item_ptr, nil

}

set_default_value :: proc(item_idx: int, header: ^$H/Header($T, $N_Chunks, $Initial_Capacity)) -> Maybe(Index_Error) {
    item := get_item_ptr(header, item_idx) or_return
    item^ = T{}
    return nil
}


Shrink_Error :: enum {

}
// Deallocates chunks to match minimum required capacity.
shrink :: proc(header: ^$H/Header($T, $N_Chunks, $Initial_Capacity)) -> union #shared_nil {mem.Allocator_Error, Shrink_Error} {
    n_leftover_chunks := _chunks_needed_for(header.length) < header.n_allocated_chunks
    if n_leftover_chunks > 0 {
        for i in 0..<n_leftover_chunks {
            index_to_delete := header.n_allocated_chunks - 1
            defer header.n_allocated_chunks -= 1

            free(rawptr(header.data[index_to_delete]), allocator = header.allocator^)

        }
    }

    // Procesar errores y retornar.
}

ordered_remove :: proc(header: ^$H/Header($T, $N_Chunks, $Initial_Capacity), index: int) {}
unordered_remove :: proc(header: ^$H/Header($T, $N_Chunks, $Initial_Capacity), index: int) {}



// Auxiliary
_allocate_new_chunk :: proc(header: ^$T/Header) -> (ok: bool) {

    next_chunk_idx := header.n_allocated_chunks
    if next_chunk_idx >= T.N_Chunks {
        //Chunk array already full
        return false
    }

    next_chunk_capacity, _ := _chunk_capacity(next_chunk_idx, header^)
    new_chunk_adress, allocation_arror := mem.alloc(next_chunk_capacity, allocator=header.allocator^)
    new_chunk_adress_number := uintptr(new_chunk_adress)

    if new_chunk_adress_number < header.base {
        // Wrong offset
        free(new_chunk_adress)
        return false
    }

    // If succesfull do update header data
    header.data[header.n_allocated_chunks] = new_chunk_adress_number - header.base
    header.n_allocated_chunks += 1
    header.capacity += next_chunk_capacity
    return true
}

_chunk_capacity :: proc(chunk_idx: int, _: $T/Header) -> (chunk_cap: int, ok: bool) {
    //fmt.println(array, T.N_Chunks)
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

_chunks_needed_for :: proc(n_items: int, _: $H/Header($T, $N_Chunks, $Initial_Capacity)) -> (n_chunks: int) {

    if n_items == 0 do return 0

    acc_capacity : int = 0
    for n in 0..<N_Chunks {
        acc_capacity += _chunk_capacity(n, H) or_else 0

        if n_items <= acc_capacity do return n

    }
}




// Iterator

Iterator :: struct($Header_Subtype: typeid) where intrinsics.type_is_specialization_of(Header_Subtype, Header) {
    current_i: int,
    header: ^Header_Subtype,
}

iterator_instantiate :: proc(header: ^$H/Header) -> Iterator(H) {
    return Iterator(H){ current_i = 0, header = header}
}

iterator_iterate :: proc(iterator: ^$I/Iterator($H/Header($T, $N_Chunks, $Initial_Capacity))) -> (item: T, idx: int, ok: bool) {
    header := cast(^H)(iterator.header)
    item = get_item(header, iterator.current_i) or_else {}
    if iterator.current_i <= header.capacity {
        defer iterator.current_i += 1
        return item, iterator.current_i, true
    }
    else {
        return {}, 0, false
    }
}



main :: proc() {
    fmt.println("Hola")


    buffer, _:= new([mem.Megabyte]byte)
    arena: mem.Arena
    mem.arena_init(&arena, buffer[:])
    arena_allocator := mem.arena_allocator(&arena)


    apple :: struct {
        a: int,
        b: [2]int,
        c: [3]bool,
    }
    apple_bin :: Header(apple, 10, 8)

    apples_exponential_array := apple_bin{}
    apples_exponential_array.allocator = &arena_allocator

    capacity, ok := _chunk_capacity(5, apples_exponential_array)
    if ok do fmt.println(capacity)
    else do fmt.println("error")


    fmt.println("n_allocated_chunks", apples_exponential_array.n_allocated_chunks, apples_exponential_array.capacity)
    _allocate_new_chunk(&apples_exponential_array)
    fmt.println("n_allocated_chunks", apples_exponential_array.n_allocated_chunks, apples_exponential_array.capacity)

    new_apple := apple{a=67}
    append_item(&apples_exponential_array, new_apple)
    append_item(&apples_exponential_array, new_apple)
    append_item(&apples_exponential_array, new_apple)

    set_default_value(0, &apples_exponential_array)


    fmt.println(intrinsics.type_is_specialization_of(apple_bin, Header))
    fmt.println("Begin")
    iterator := iterator_instantiate(&apples_exponential_array)
    for item, idx in iterator_iterate(&iterator) {
        fmt.println(item, idx)
    }

    fmt.println("End")

}
