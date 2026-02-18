# Examples

[Home](README.md) | [Getting Started](getting-started.md) | [Language Guide](language-guide.md) | [Builtins](builtins.md) | [FFI](ffi.md) | [Macros](macros.md) | **Examples**

Annotated walkthroughs of fy programs, from simple to complex.

## Factorial (`examples/fact.fy`)

Classic recursive factorial:

```forth
: fact
  dup 1 <=            ( is n <= 1? )
  [ drop 1 ]          ( base case: return 1 )
  [ dup 1- fact * ]   ( recursive: n * fact(n-1) )
  ifte
;

10 fact .              ( prints 3628800 )
```

Key concepts: word definition, recursion, `ifte` conditional.

## Fibonacci (`examples/fib.fy`)

```forth
: fib
  dup 1 <=
  [ drop 1 ]
  [ dup 1- fib swap 2 - fib + ]
  ifte
;

10 fib .               ( prints 89 )
```

Naive doubly-recursive Fibonacci. Demonstrates that fy handles deep recursion through proper ARM64 call frames.

## TAK Benchmark (`examples/tak.fy`)

The Takeuchi function — a classic benchmark for function call overhead:

```forth
: tak
  [ | x y z |
    y x >=
    [ z ]
    [
      x 1- y z tak
      y 1- z x tak
      z 1- x y tak
      tak
    ] ifte
  ] do
;
```

Demonstrates locals (`| x y z |`) for readable multi-argument words.

## Loops (`examples/loops.fy`, `examples/loop.fy`)

### Counted Loop with `dotimes`

```forth
5 [ "hello" s. .nl ] dotimes
```

### Loop with `repeat`

```forth
5 [ dup . 1- dup ] repeat drop
```

Prints `5 4 3 2 1`. The quote must leave a condition on TOS — `repeat` continues while it's non-zero.

## Sierpinski Triangle (`examples/sierp.fy`)

Generates a PPM image of the Sierpinski triangle using bitwise AND:

```forth
: pixel
  & 0 = [ 0 0 0 ] [ 255 255 255 ] ifte
;
```

Each pixel's color is determined by `x & y == 0`. Demonstrates file I/O (`spit`), string building, and bitwise operations.

## Functional Programming

### Map, Reduce, Filter

```forth
( Square every element )
[1 2 3 4] [dup *] map          ( → [1 4 9 16] )

( Sum a list )
0 [1 2 3 4 5] [+] reduce       ( → 15 )

( Keep only values > 3 )
[1 2 3 4 5] [3 >] filter       ( → [4 5] )

( Side effects )
[1 2 3] \. each                 ( prints 1 2 3 )
```

### Quote Manipulation

```forth
qnil                            ( empty quote [] )
42 qpush                        ( [42] )
99 qpush                        ( [42 99] )
qhead .                         ( prints 42 )

( Build a quote from words )
[] [\+ \- \*] \cat reduce       ( concatenate word-quotes )
```

## FFI: libm Math Functions (`examples/libm.fy`)

```forth
:: _lib "/usr/lib/libm.dylib" dl-open ;

:: _sin  _lib "sin" dl-sym ;
:: _cos  _lib "cos" dl-sym ;
:: _pow  _lib "pow" dl-sym ;
:: _sqrt _lib "sqrt" dl-sym ;

: sin   _sin  bind: d:d ;
: cos   _cos  bind: d:d ;
: pow   _pow  bind: dd:d ;
: sqrt  _sqrt bind: d:d ;

3.14159 sin f.          ( ≈ 0.0 )
2.0 10.0 pow f.         ( 1024.0 )
144.0 sqrt f.           ( 12.0 )
```

Key pattern: `::` evaluates `dl-open`/`dl-sym` once at compile time, then `bind:` generates inline calling code.

## FFI: raylib Game Window (`examples/raylib_hello.fy`)

```forth
include "raylib.fy"

800 450 "Hello from fy!" InitWindow

[ WindowShouldClose not ] [
  BeginDrawing
    245 245 245 255 ClearBackground
    190 200 20 "fy says hello!" DrawText
  EndDrawing
] repeat

CloseWindow
```

A complete raylib window with a game loop. The `raylib.fy` file (auto-generated from `raylib.ffi` by `gen-ffi`) provides all the bindings.

## FFI: Polyphonic Synthesizer (`examples/raylib_synth_poly.fy`)

A real-time polyphonic synthesizer using raylib audio:

```forth
struct: Voice
  f32 phase    f32 freq
  f32 attack   f32 decay
  f32 sustain  f32 release
  f32 env      i32 state
  i32 key      i32 active
;
```

Demonstrates:
- Struct definitions with field accessors
- Audio callbacks (`callback: pi:v audio-fill`)
- Thread-safe callbacks with private data stacks
- Real-time DSP with float math
- Complex control flow for ADSR envelopes

## Modules: Import (`examples/golden/import_basic.fy`)

```forth
import "testlib"
5 testlib:double .      ( prints 10 )
```

Where `testlib.fy` defines:

```forth
: double  2 * ;
```

After `import "testlib"`, all words gain a `testlib:` prefix.

## Macros: Compile-Time Constants (`examples/macro.fy`)

```forth
: cfib  dup 1 <= [ drop 1 ] [ dup 1- cfib swap 2 - cfib + ] ifte ;

macro: const  peek-quote unpush do emit-lit ;

[10 cfib] const .       ( Fibonacci computed at compile time! )
```

The result (89) is baked into the binary — zero runtime cost.

## macOS Liquid Glass (`examples/glass.fy`)

```forth
import "objc"

( ... create NSWindow, NSView, set up appearance ... )
```

Demonstrates calling Objective-C frameworks through `objc_msgSend`, selector registration, and class lookup — all via fy's FFI. See the [objc.fy module](../examples/objc.fy) for the ObjC bridge implementation.

## Golden Tests

The `examples/golden/` directory contains small focused tests for individual features. Each `.fy` file has a matching `.expected` file with the expected output. These serve as both tests and minimal examples:

| Test | Feature |
|------|---------|
| `locals_basic` | Local variable binding |
| `locals_nested_shadow` | Shadowing locals in nested quotes |
| `ifte_basic_true/false` | Basic conditional branching |
| `ifte_do_question` | `do?` conditional execution |
| `quotes_do` | Quote execution with `do` |
| `map_basic` | `map` over quotes |
| `reduce_basic_sum` | `reduce` for summation |
| `ffi_strlen` | FFI string length call |
| `ffi_abs` | FFI absolute value |
| `float_basic` | Float arithmetic |
| `strings_basic` | String operations |
| `constant_basic` | Compile-time constants |
| `mutual_even_odd` | Mutual recursion |
| `recursion_sum` | Basic recursion |
| `import_basic` | Module import |
| `nested_loops` | Nested `dotimes` |
