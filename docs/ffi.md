# FFI Guide

[Home](README.md) | [Getting Started](getting-started.md) | [Language Guide](language-guide.md) | [Builtins](builtins.md) | **FFI** | [Macros](macros.md) | [Examples](examples.md)

fy's FFI lets you call any C function from any dynamic library — including system frameworks, raylib, libm, and Objective-C runtimes. The JIT compiler emits native ARM64 calling convention code inline, so FFI calls have minimal overhead.

## Loading Libraries

```forth
"/usr/lib/libSystem.B.dylib" dl-open
```

`dl-open` takes a string path and returns an opaque handle (integer). On failure, it returns 0 and prints the `dlerror()` message.

Store the handle as a constant for reuse:

```forth
:: _lib "/usr/lib/libSystem.B.dylib" dl-open ;
```

## Looking Up Symbols

```forth
_lib "strlen" dl-sym
```

`dl-sym` takes a library handle and a symbol name string, returning a function pointer (integer). Returns 0 if not found.

## Calling C Functions

### Low-Level: `ccall0` through `ccall3`

For quick calls without type marshaling:

```forth
( getpid() — no arguments )
_lib "getpid" dl-sym ccall0 .

( strlen(ptr) — one argument )
"hello" cstr-new
_lib "strlen" dl-sym
ccall1 .                    ( prints 5 )

( the pointer leaks! use cstr-free or with-cstr instead )
```

Stack layout for `ccallN`: push args left-to-right, then fptr on top.

### `bind:` — Typed Binding

`bind:` is the primary way to create FFI wrappers. It reads a type signature and emits inline ARM64 code to marshal arguments according to the C calling convention.

```forth
: strlen  _strlen bind: s:i ;
```

**Signature format**: `<arg-types>:<return-type>`

#### Argument Types

| Char | Type | Description |
|------|------|-------------|
| `i` | int/pointer | 64-bit integer, passed in x register |
| `p` | pointer | Same as `i`, semantic alias |
| `f` | float32 | f64→f32 conversion, passed in s register |
| `d` | float64 | Passed in d register |
| `4` | 4-byte struct | Passed as 32-bit value in x register (e.g., Color) |
| `s` | temp string | Auto-converts fy string to C string, freed after call |
| `S` | persistent string | Auto-converts fy string to C string, NOT freed |

#### Return Types

| Char | Type | Description |
|------|------|-------------|
| `v` | void | Nothing returned; no value pushed |
| `i` | int | Return value pushed as integer |
| `p` | pointer | Same as `i` |
| `f` | float32 | f32→f64 widened, pushed as float |
| `d` | float64 | Pushed as float |
| `S` | struct | Return via x8 pointer (see below) |

### Examples

```forth
( void function, 3 int args )
: InitWindow  _InitWindow bind: iii:v ;

( int function, no args )
: WindowShouldClose  _WindowShouldClose bind: :i ;

( void function, string arg — auto C string conversion )
: DrawText  _DrawText bind: siiii:v ;

( float function )
: sinf  _sinf bind: f:f ;

( double function )
: pow  _pow bind: dd:d ;
```

### String Auto-Conversion

The `s` type in `bind:` automatically:
1. Converts the fy string to a C string (null-terminated, via `malloc`)
2. Passes the C pointer to the function
3. Frees the C string after the call returns

Use `S` if the C function stores the pointer (it won't be freed).

### `sig:` — Inline Typed Call

`sig:` is an alias for `bind:` that works identically. Use whichever reads better:

```forth
-42 _abs sig: i:i .     ( inline call: prints 42 )
```

## C String Management

For manual control over C strings:

```forth
"hello" cstr-new        ( allocate C string → ptr )
( ... use ptr ... )
cstr-free               ( free it )
```

### `with-cstr` — Scoped C String

```forth
"hello" _strlen with-cstr .    ( auto alloc, call strlen, free, push result )
```

### `with-cstr-f` — Scoped with Function Pointer

```forth
"hello" _strlen [ ccall1 ] with-cstr-f .
```

Pushes both the C string pointer and function pointer onto an isolated trampoline stack, executes the quote, frees the string, returns the result.

## Struct Return (`S` return type)

For C functions that return structs via pointer (ARM64 ABI: x8 register):

```forth
( push buffer pointer first, then args )
MyStruct.alloc          ( allocate buffer )
arg1 arg2               ( push function arguments )
_SomeFunction bind: ii:S    ( call; result written to buffer via x8 )
```

The buffer pointer should be on the stack *below* all arguments. After the call, the buffer pointer is pushed back.

## Callbacks

`callback:` creates a C-callable function pointer that bridges into a fy word:

```forth
: my-handler  ( args on stack ) ... ;
callback: ii:v my-handler
```

This pushes a C function pointer onto the stack. When C code calls this pointer, the trampoline:
1. Saves/restores fy data stack registers
2. Sets up a **private data stack** (thread-safe — important for audio callbacks)
3. Pushes C arguments onto the fy stack
4. Calls the named fy word
5. Marshals the return value back to C

```forth
( Audio callback: receives buffer pointer and frame count )
: audio-fill  ( ptr frames -- )
  ... fill audio buffer ...
;

callback: pi:v audio-fill
( stack now has a C function pointer suitable for SetAudioStreamCallback )
```

The callback signature uses the same type characters as `bind:`.

## Complete FFI Example

Here's a minimal example calling `abs()` from libSystem:

```forth
( Load library and cache symbol )
:: _lib "/usr/lib/libSystem.B.dylib" dl-open ;
:: _abs _lib "abs" dl-sym ;

( Create typed wrapper )
: abs  _abs bind: i:i ;

( Use it )
-42 abs .       ( prints 42 )
```

## Auto-Generated FFI Bindings

The `tools/gen-ffi` tool generates `.fy` binding files from a simple declaration format (`.ffi` files):

```
# raylib.ffi
libraylib.dylib
InitWindow iii:v
CloseWindow :v
WindowShouldClose :i
BeginDrawing :v
EndDrawing :v
ClearBackground 4:v
```

Run:

```sh
zig build gen-ffi -- raylib.ffi
```

This produces a `raylib.fy` file with `dl-open`, `dl-sym`, and `bind:` wrappers for every function.

## Practical Tips

- Use `::` for library handles and function pointers — they're evaluated once at compile time
- The `s` arg type in `bind:` handles string conversion automatically — no need for `cstr-new`/`cstr-free`
- Callbacks get their own data stack, so they're safe to use from any thread (e.g., audio threads)
- For Objective-C frameworks, see `examples/objc.fy` which wraps `objc_msgSend` and selector registration
- `ccall1pac` provides PAC (Pointer Authentication Code) safe calling on Apple Silicon
