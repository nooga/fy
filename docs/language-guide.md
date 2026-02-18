# Language Guide

[Home](README.md) | [Getting Started](getting-started.md) | **Language Guide** | [Builtins](builtins.md) | [FFI](ffi.md) | [Macros](macros.md) | [Examples](examples.md)

fy is a **concatenative**, **stack-based** language. Programs are sequences of *words* separated by whitespace. Each word either pushes a value onto the data stack or pops values, does something, and pushes results back.

## The Data Stack

All computation flows through a single data stack. Values are 64-bit integers (i64). Strings and quotes are heap-allocated and referenced via tagged pointers.

```forth
2 3 +       ( push 2, push 3, pop both and push 5 )
dup *       ( duplicate 5, multiply: 25 )
.           ( pop and print: 25 )
```

Stack effects are written in Forth notation: `( before -- after )`.

## Literals

### Integers

Decimal integers, optionally negative:

```forth
42          ( push 42 )
-7          ( push -7 )
0           ( push 0 )
```

### Floats

Numbers with a decimal point:

```forth
3.14        ( push 3.14 as f64, bitcast into Value )
-0.5        ( negative float )
```

Floats use a separate set of arithmetic words: `f+`, `f-`, `f*`, `f/`, `f.`, etc. See [Builtins](builtins.md#floats).

### Strings

Double-quoted, with backslash escapes:

```forth
"hello"             ( push a heap string )
"line one\nline two"  ( \n = newline )
"tab\there"         ( \t = tab )
"null\0byte"        ( \0 = null byte )
"escaped\"quote"    ( \" = literal quote )
```

Supported escapes: `\n` `\r` `\t` `\\` `\"` `\0`.

### Character Literals

Single quote followed by a character pushes its ASCII value:

```forth
'A          ( push 65 )
'\n         ( push 10 — but note: this is just the character 'n' after '\', not a newline )
```

## Comments

Parenthesized text is a comment. Nesting is supported:

```forth
( this is a comment )
( outer ( inner ) still comment )
2 3 + ( add two numbers ) .
```

## Word Definitions

### `:` — Define a Word

```forth
: square  dup * ;
: abs  dup 0 < [ 0 swap - ] [ ] ifte ;
```

Everything between `:` and `;` is compiled. The word becomes callable by name. Words can call themselves recursively:

```forth
: fib  dup 1 <= [ drop 1 ] [ dup 1- fib swap 2 - fib + ] ifte ;
```

Mutual recursion works — words can call any previously or forward-defined word.

### `::` — Compile-Time Constants

```forth
:: answer 42 ;
:: pi 3.14159 ;
:: lib "/usr/lib/libSystem.B.dylib" dl-open ;
```

The body after the name is compiled, executed once at compile time, and the result is baked into the word as a literal. This is essential for FFI handles and computed constants.

## Quotes

Quotes are first-class code blocks delimited by `[ ... ]`:

```forth
[ 1 + ]         ( a quote that adds 1 )
[ dup * ]       ( a quote that squares )
```

Quotes can be:
- Executed with `do`
- Passed to combinators (`ifte`, `map`, `reduce`, `filter`, `each`, `dotimes`, `repeat`)
- Stored on the stack and manipulated as data
- Contain any code including nested quotes

### Backslash Shorthand

`\word` creates a single-word quote:

```forth
\+              ( equivalent to [ + ] )
[1 2 3] \. each    ( print each element )
```

### Locals

Quotes can bind stack values to named locals:

```forth
1 2 3 [ | a b c | a b + c * ] do    ( (1 + 2) * 3 = 9 )
```

The `| name1 name2 ... |` header pops values from the stack (right-to-left: last name gets TOS) and makes them available by name within the quote body. Locals are immutable and lexically scoped.

```forth
5 [ | x |
  x 1+
  x 1-
  *
] do .          ( 6 * 4 = 24 )
```

## Control Flow

### `ifte` — If-Then-Else

```forth
condition [ then-body ] [ else-body ] ifte
```

Pops the condition and two quotes. Executes the then-quote if condition is non-zero, else-quote if zero:

```forth
: abs  dup 0 < [ 0 swap - ] [ ] ifte ;
5 abs .         ( 5 )
-3 abs .        ( 3 )
```

### `do` — Execute a Quote

```forth
[ 2 3 + ] do .  ( 5 )
```

### `do?` — Conditional Execute

```forth
condition [ body ] do?
```

Executes the quote only if condition is non-zero. Does nothing if zero:

```forth
1 [ "yes" s. .nl ] do?     ( prints "yes" )
0 [ "no" s. .nl ] do?      ( prints nothing )
```

### `dotimes` — Counted Loop

```forth
count [ body ] dotimes
```

Executes the body `count` times:

```forth
5 [ "hello" s. .nl ] dotimes
```

### `repeat` — Loop Until Zero

```forth
initial [ body ] repeat
```

Loops while TOS is non-zero. The body should leave a new condition on TOS:

```forth
5 [ dup . 1- dup ] repeat drop   ( prints 5 4 3 2 1 )
```

### `recur` — Tail Recursion

Inside a word definition, `recur` jumps back to the beginning of the current word, enabling efficient tail-recursive loops.

## Stack Manipulation

| Word | Effect | Description |
|------|--------|-------------|
| `dup` | `a -- a a` | Duplicate top |
| `dup2` | `a b -- a b a b` | Duplicate top pair |
| `drop` | `a --` | Discard top |
| `drop2` | `a b --` | Discard top two |
| `swap` | `a b -- b a` | Swap top two |
| `over` | `a b -- a b a` | Copy second to top |
| `over2` | `c d a b -- c d a b c d` | Copy third+fourth |
| `nip` | `a b -- b` | Drop second |
| `tuck` | `a b -- b a b` | Copy top below second |
| `rot` | `a b c -- b c a` | Rotate three |
| `-rot` | `a b c -- c a b` | Reverse rotate |
| `depth` | `-- n` | Current stack depth |
| `>r` | `x --` | Move to retain stack |
| `r>` | `-- x` | Move from retain stack |
| `r@` | `-- x` | Copy from retain stack |
| `dip` | `x f -- x` | Execute f, preserving x |

The **retain stack** (return stack) is a secondary stack for temporary storage. Use `>r` / `r>` to shuttle values there and back.

**dip** is a powerful combinator: it saves TOS, executes the quote/word beneath it, then restores TOS:

```forth
1 2 3 [ + ] dip    ( 1+2=3, then 3 restored → stack: 3 3 )
```

## Higher-Order Operations

These words take quotes (or word references via `\word`) and operate over collections:

| Word | Effect | Description |
|------|--------|-------------|
| `map` | `list f -- list'` | Apply f to each element |
| `reduce` | `acc list f -- result` | Fold with accumulator |
| `filter` | `list f -- list'` | Keep elements where f returns non-zero |
| `each` | `list f -- 0` | Apply f for side effects |

```forth
[1 2 3 4] [dup *] map                   ( [1 4 9 16] )
0 [1 2 3 4 5] [+] reduce               ( 15 )
[1 2 3 4 5] [ 3 > ] filter             ( [4 5] )
[1 2 3] \. each                         ( prints 1 2 3 )
```

## Modules

### `include` — Textual Inclusion

```forth
include "mathlib.fy"
```

Reads and compiles the file. All definitions enter the current scope.

### `import` — Namespaced Import

```forth
import "raylib"
```

Reads `raylib.fy`, compiling all definitions with a `raylib:` prefix:

```forth
import "raylib"
raylib:InitWindow
```

Paths are resolved relative to the importing file. The `.fy` extension is appended automatically if missing. Each file is imported at most once (dedup guard).

## Structs

Define C-compatible memory layouts:

```forth
struct: Point
  f32 x
  f32 y
;
```

This generates:
- `Point.size` — struct size in bytes
- `Point.alloc` — allocate zeroed memory for one Point
- `Point.new` — pop field values from stack, allocate, and initialize
- `Point.x@` / `Point.x!` — read/write the `x` field
- `Point.y@` / `Point.y!` — read/write the `y` field

Field types: `i8`, `u8`, `i16`, `u16`, `i32`, `u32`, `i64`, `u64`, `f32`, `f64`, `ptr`.

```forth
1.0 2.0 Point.new      ( allocate and init: x=1.0, y=2.0 )
Point.x@ f.            ( prints 1.0 )
3.0 swap Point.y!      ( set y to 3.0 )
```

See [FFI Guide](ffi.md) for using structs with C libraries.

## Type System

fy values are untyped 64-bit words. The runtime distinguishes three kinds via tag bits:

| Type | Description |
|------|-------------|
| Integer | Raw i64, tag bit 0 |
| String | Heap-allocated byte array |
| Quote | Heap-allocated code block |

Type-checking words: `int?`, `string?`, `quote?`, `word?`.

Floats are f64 values bitcast into the i64 representation — they share the integer tag but are manipulated with `f+`, `f-`, etc.

## Garbage Collection

fy has a mark-and-sweep garbage collector for heap objects (strings and quotes). Trigger it manually with `gc`. The GC walks the data stack and roots (compiler-created literals) to find reachable objects.

## Next Steps

- [Builtins Reference](builtins.md) — complete word list
- [FFI Guide](ffi.md) — call C libraries
- [Macros](macros.md) — compile-time metaprogramming
- [Examples](examples.md) — real programs
