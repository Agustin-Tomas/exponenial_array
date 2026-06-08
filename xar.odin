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


Header :: struct($T: typeid, $N_Chunks: int, $Initial_Capacity: int,) {
    memory_bounds: []byte,
    allocator: ^mem.Allocator,  // Try always using the same allocator if possible

    base: uintptr,  // Base must be a location prior to all chunks.
    // Chunks must be allocated futher than base.
    chunks: [N_Chunks]uintptr, // base+chunk[i] == raw_data([]$T)
    n_allocated_chunks: int,

    array_len: int,
    array_cap: int,
}

// for initializing and setting up when moving header alongside it's backing data.
deploy_header :: proc(header: ^Header, allocator: ^mem.Allocator) {
    header.base = uintptr(header)
    header.allocator = allocator
}

// Necesita reservar memoria
// Se sirve de un allocator... proc(size) -> []byte
append_item :: proc(header: ^Header($T, $Initial_Capacity, $N_Chunks), item: T) {
    if header.array_cap > header.array_len {
        // copy item into [len]
        item_ptr, err := get_item_ptr(header, header.array_len)
        if err == nil {
            header.array_len += 1
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


allocate_new_chunk :: proc(header: ^$T/Header) -> (ok: bool) {

    next_chunk_idx := header.n_allocated_chunks
    if next_chunk_idx >= T.N_Chunks {
        //Chunk array already full
        return false
    }

    next_chunk_capacity, _ := chunk_capacity(next_chunk_idx, header^)
    new_chunk_adress, allocation_arror := mem.alloc(next_chunk_capacity, allocator=header.allocator^)
    new_chunk_adress_number := uintptr(new_chunk_adress)

    if new_chunk_adress_number < header.base {
        // Wrong offset
        free(new_chunk_adress)
        return false
    }

    // If succesfull do update header data
    header.chunks[header.n_allocated_chunks] = new_chunk_adress_number - header.base
    header.n_allocated_chunks += 1
    header.array_cap += next_chunk_capacity
    return true
}




//chunk_inner_cap :: proc(chunk_idx: int, array: Header($T, $Initial_Capacity, $N_Chunks)) -> (chunk_cap: int, ok: bool) {
chunk_capacity :: proc(chunk_idx: int, /*header type specialization*/_: $T/Header) -> (chunk_cap: int, ok: bool) {
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


get_item :: proc(header: ^Header($T, $N_Chunks, $Initial_Capacity), index: int) -> (item: T, error: Maybe(Index_Error)) {

    if index < 0 {
        return {}, Index_Error.Negative
    }

    if index >= header.array_cap {
        return {}, Index_Error.Out_Of_Bounds
    }

    chunk_idx: int = 0
    accumulated_capacity: int = 0


    accumulated_capacity += chunk_capacity(chunk_idx, header^) or_else 0
    chunk_idx += 1
    for index >= accumulated_capacity { /*This is guaranted to finish*/
        accumulated_capacity += chunk_capacity(chunk_idx, header^) or_else 0
        chunk_idx += 1
    }
    chunk_idx -= 1

    // If I reached here it means chunk_idx is the index of the chunk where the wanted item is.
    // Also max_cap is the capacity up to (and including) the desired chunk.

    // Ahora tengo que encontrar en que indice dentro de ese chunk se encuentra mi objeto segun si indice global

    n_items_on_chunk := chunk_capacity(chunk_idx, header^) or_else 0
    chunk_local_index := index - (header.array_cap - n_items_on_chunk)
    chunk_location : rawptr = rawptr(header.base + header.chunks[chunk_idx])
    first_item : ^T = cast(^T)(chunk_location)  // Pointer to first item in chunk
    typed_chunk := slice.from_ptr(first_item, n_items_on_chunk )
    item = typed_chunk[chunk_local_index]
    return item, nil

}

get_item_ptr :: proc(header: ^Header($T, $N_Chunks, $Initial_Capacity), index: int) -> (item_ptr: ^T, error: Maybe(Index_Error)) {

    if index < 0 {
        return nil, Index_Error.Negative
    }

    if index >= header.array_cap {
        return nil, Index_Error.Out_Of_Bounds
    }

    chunk_idx: int = 0
    accumulated_capacity: int = 0


    accumulated_capacity += chunk_capacity(chunk_idx, header^) or_else 0
    chunk_idx += 1
    for index >= accumulated_capacity { /*This is guaranted to finish*/
        accumulated_capacity += chunk_capacity(chunk_idx, header^) or_else 0
        chunk_idx += 1
    }
    chunk_idx -= 1

    // If I reached here it means chunk_idx is the index of the chunk where the wanted item is.
    // Also max_cap is the capacity up to (and including) the desired chunk.

    // Ahora tengo que encontrar en que indice dentro de ese chunk se encuentra mi objeto segun si indice global

    n_items_on_chunk := chunk_capacity(chunk_idx, header^) or_else 0
    chunk_local_index := index - (header.array_cap - n_items_on_chunk)
    chunk_location : rawptr = rawptr(header.base + header.chunks[chunk_idx])
    first_item : ^T = cast(^T)(chunk_location)  // Pointer to first item in chunk
    typed_chunk := slice.from_ptr(first_item, n_items_on_chunk )
    item_ptr = &typed_chunk[chunk_local_index]
    return item_ptr, nil

}


Iterator :: struct($Header_Subtype: typeid)
        where intrinsics.type_is_specialization_of(Header_Subtype, Header) {
    current_i: int,
    header: ^Header_Subtype,
}

init_iterator :: proc(header: ^$T/Header) -> Iterator(T) {
    return Iterator(T){ current_i = 0, header = header}
}

iterator_iterate :: proc(iterator: ^$I/Iterator($H/Header($T, $N_Chunks, $Initial_Capacity))) -> (item: T, idx: int, ok: bool) {
    header := cast(^H)(iterator.header)
    item = get_item(header, iterator.current_i) or_else {}
    if iterator.current_i <= header.array_cap {
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

    capacity, ok := chunk_capacity(5, apples_exponential_array)
    if ok do fmt.println(capacity)
    else do fmt.println("error")


    fmt.println("n_allocated_chunks", apples_exponential_array.n_allocated_chunks, apples_exponential_array.array_cap)
    allocate_new_chunk(&apples_exponential_array)
    fmt.println("n_allocated_chunks", apples_exponential_array.n_allocated_chunks, apples_exponential_array.array_cap)

    new_apple := apple{a=67}
    append_item(&apples_exponential_array, new_apple)
    append_item(&apples_exponential_array, new_apple)
    append_item(&apples_exponential_array, new_apple)


    fmt.println(intrinsics.type_is_specialization_of(apple_bin, Header))
    fmt.println("Begin")
    iterator := init_iterator(&apples_exponential_array)
    for item, idx in iterator_iterate(&iterator) {
        fmt.println(item, idx)
    }

    fmt.println("End")

}
