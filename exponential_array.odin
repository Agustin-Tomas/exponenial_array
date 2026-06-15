package exponential_array

import "core:mem"
import fmt "core:fmt"
import slice "core:slice"
import "core:reflect"
import "base:runtime"
import intrinsics "base:intrinsics"



/*  Implementación de un 'exponential array'.

    Se trata de un array dinámico que aloja chunks de tamaño creciente.

    La implementación es POD-safe, es decir, que los elementos guardados
    se referencian mediante offsets, de modo que la estructura puede
    copiarse a otra región de la memoria de modo que la copia pueda operar
    con normalidad en su localidad.

    Se presupone que toda la estructura de datos será contenida dentro
    de un mismo bloque de memoria y que el uintptr base se ubica en una
    posición de la memoria anterior a la ubicacion de cualquiera de sus
    chunks (base+offset=elemento y offset siempre es positivo).

    Se recomienda almacenar la estructura de datos en una memory arena
    ya que cumple estos requisitos naturalmente.

    La razón de esta implementación es tener un array dinámico POD-safe
    ya que el implementado en la librería estándar de Odin utiliza
    punteros, lo que colisiona con la necesitad de mi AT-Engine de duplicar
    estados globales arbitrariamente y manipular los punteros era un
    incordio. Aparte es una buena práctica para el aprendizaje.

*/




// Data structure
/* Estructura que representa y contiene toda la información de un exponential array */
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
/*  Inicializa un exponential array
    El puntero del mismo Header se utiliza como base para calcular los offsets
    Al mover el bloque de memoria donde fueron asignados el Header y sus chunks se debe volver a inicializar el Header
*/
init_header :: proc(header: ^Header($T, $Initial_Capacity, $N_Chunks), allocator: ^mem.Allocator) {
    header.base = uintptr(header)
    header.allocator = allocator
}

/*  Agrega un elemento al final del exponential array
*/
append_item :: proc(header: ^Header($T, $Initial_Capacity, $N_Chunks), item: T) -> (ok: bool) {
    //fmt.println(item)
    if header.length >= header.capacity {
        array_growth_error: mem.Allocator_Error
        for header.length >= header.capacity {
            ok, array_growth_error = _allocate_new_chunk(header)
            if !ok {
                return
            }
        }
    }

    // copy item into [len]
    item_ptr, err := get_item_ptr(header, header.length)
    if err == nil {
        header.length += 1
        item_ptr^ = item
        return true
    }

    return false
}

/* Tipo de error que opera junto a get?¡_item */
Index_Error :: enum {
    Negative,
    Out_Of_Bounds,
}
/* Devuelve el valor literal del elemento indicado */
get_item :: proc(header: ^Header($T, $N_Chunks, $Initial_Capacity), index: int) -> (item: T, error: Maybe(Index_Error)) {

    item_ptr: ^T
    item_ptr, error = get_item_ptr(header, index)
    if error == nil {
        return item_ptr^, error
    }
    else {
        return
    }

}

/* Devuelve un puntero al elemento indicado */
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

    n_items_on_chunk      := _chunk_capacity(chunk_idx, header^) or_else 0
    capacity_here_onwards := (_chunk_range_capacity(chunk_idx, header.n_allocated_chunks, header^))
    // chunk_local_index  := index - (header.capacity - capacity_here_onwards)
    chunk_local_index := capacity_here_onwards + index - _total_capacity(header^)
    chunk_location    := rawptr(header.base + header.data[chunk_idx])
    first_item        := cast(^T)(chunk_location)  // Pointer to first item in chunk
    typed_chunk       := slice.from_ptr(first_item, n_items_on_chunk)
    item_ptr = &typed_chunk[chunk_local_index]
    return item_ptr, nil

}

/* Reestablece un elemento indicado a su valor por defecto */
set_default_value :: proc(item_idx: int, header: ^$H/Header($T, $N_Chunks, $Initial_Capacity)) -> Maybe(Index_Error) {
    item := get_item_ptr(header, item_idx) or_return
    item^ = T{}
    return nil
}


/*  Desaloja los chunks que no son necesarios para albergar la cantidad de items actualmente contenidos.
    Desaloja en órden del último al primero.
    No tiene en cuenta los elementos en los chunks a desalojar.
*/
// NO ESTÁ TESTEADO
_brute_shrink :: proc(header: ^$H/Header($T, $N_Chunks, $Initial_Capacity)) -> mem.Allocator_Error {
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


/*  Aún no implementado...
    En los handle_maps no requiero remover nada ya que los uso a modo de stack o denoto gen=0 como item muerto.
*/
ordered_remove :: proc(header: ^$H/Header($T, $N_Chunks, $Initial_Capacity), index: int) {}
unordered_remove :: proc(header: ^$H/Header($T, $N_Chunks, $Initial_Capacity), index: int) {}



/* Funciones auxiliares */

/* Asigna memoria a un nuevo chunk */
_allocate_new_chunk :: proc(header: ^$H/Header($T, $N_Chunks, $Initial_Capacity)) -> (ok: bool, error: mem.Allocator_Error) {

    next_chunk_idx := header.n_allocated_chunks
    if next_chunk_idx >= N_Chunks {
        //Chunk array already full
        return false, nil
    }

    next_chunk_capacity, ok_next := _chunk_capacity(next_chunk_idx, header^)
    if !ok_next {
        return false, nil
    }

    new_chunk_adress, allocation_arror := mem.alloc(next_chunk_capacity * size_of(T), allocator=header.allocator^)
    if allocation_arror != nil {
        return false, allocation_arror
    }
    new_chunk_adress_number := uintptr(new_chunk_adress)

    if new_chunk_adress_number < header.base {
        // Wrong offset
        free(new_chunk_adress)
        return false, nil
    }

    // If succesfull do update header data
    header.data[header.n_allocated_chunks] = new_chunk_adress_number - header.base
    header.n_allocated_chunks += 1
    header.capacity += next_chunk_capacity
    return true, nil
}

/* Devuelve la capacidad del chunk indicado */
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

/* Devuelve la cantidad mínima de chunks necesarios para contener tantos items */
_chunks_needed_for :: proc(n_items: int, _: $H/Header($T, $N_Chunks, $Initial_Capacity)) -> (n_chunks: int) {

    if n_items == 0 do return 0

    acc_capacity : int = 0
    for n in 0..<N_Chunks {
        acc_capacity += _chunk_capacity(n, H) or_else 0

        if n_items <= acc_capacity do return n

    }
}

/* Devuelve la capacidad total de un exar */
_total_capacity :: proc(header: $H/Header($T, $N_Chunks, $Initial_Capacity)) -> (max_n_items: int) {
    total_capacity := 0
    for i in 0..<header.n_allocated_chunks {
        chunk_cap, ok := _chunk_capacity(i, header)
        total_capacity += chunk_cap
    }
    return total_capacity
}

/* Devuelve la capacidad entre un chunk y otro, sin contar la capacidad del último */
/* FALTAN CHEQUEOS DE SEGURIDAD */
_chunk_range_capacity :: proc(chunk_idx_start: int, chunk_idx_end: int, header: $T/Header) -> int {
    acc_capacity: int = 0
    for i in chunk_idx_start..<chunk_idx_end {
        chunk_cap, ok := _chunk_capacity(i, header)
        acc_capacity += chunk_cap
    }
    return acc_capacity
}



/*  Código para iterar
    - Iterator es una estructura de bookeeping con la que no se interactúa directamente
    - iterator_init se usa para instanciar un Iterator para el array que queremos iterar
    - iterator_iterate_all itera todos los items de un array, estén inicializados o no, devolviendo el item, indice y ok

    Ej.:
        my_iterator := iterator_init(my_header)
        for item, index in iterator_iterate_all(&my_iterator) {
            // do something
        }

 */

Iterator :: struct($Header_Subtype: typeid) where intrinsics.type_is_specialization_of(Header_Subtype, Header) {
    current_i: int,
    header: ^Header_Subtype,
}

iterator_init :: proc(header: ^$H/Header) -> Iterator(H) {
    return Iterator(H){ current_i = 0, header = header}
}

iterator_iterate_all :: proc(iterator: ^$I/Iterator($H/Header($T, $N_Chunks, $Initial_Capacity))) -> (item: T, idx: int, ok: bool) {
    header := cast(^H)(iterator.header)
    item_gotten, ok_get := get_item(header, iterator.current_i)
    defer iterator.current_i += 1
    return item_gotten, iterator.current_i, (ok_get == nil)

}



// Test
main :: proc() {
    fmt.println("Hola")


    buffer, _:= new([mem.Megabyte]byte)
    arena: mem.Arena
    mem.arena_init(&arena, buffer[:])
    arena_allocator := mem.arena_allocator(&arena)
    context.allocator = arena_allocator


    apple :: struct {
        a: int,
        b: [2]int,
        c: [3]bool,
    }
    apple_bin :: Header(apple, 10, 8)

    apples_exponential_array := new(apple_bin)
    init_header(apples_exponential_array, &arena_allocator)

    // fmt.println("n_allocated_chunks", apples_exponential_array.n_allocated_chunks, apples_exponential_array.capacity)
    _allocate_new_chunk(apples_exponential_array)
    // fmt.println("n_allocated_chunks", apples_exponential_array.n_allocated_chunks, apples_exponential_array.capacity)

    new_apple := apple{a=0}

    fmt.println("INIT APPEND")
    for i in 0..<32 {
        new_apple = apple{a=i}
        append_item(apples_exponential_array, new_apple)
    }
    fmt.println("END APPEND")

    set_default_value(1, apples_exponential_array)


    // fmt.println(intrinsics.type_is_specialization_of(apple_bin, Header))
    fmt.println("Begin")
    iterator := iterator_init(apples_exponential_array)
    for item, idx in iterator_iterate_all(&iterator) {
        fmt.println(item, idx)
    }

    fmt.println(apples_exponential_array)

    fmt.println("End")

}
