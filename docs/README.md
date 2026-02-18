# fy Language Documentation

**fy** is a concatenative, stack-based programming language that JIT-compiles to native aarch64 machine code. The entire compiler fits in under 4,000 lines of Zig and produces a ~1.8MB binary with zero runtime dependencies.

## Table of Contents

- [Getting Started](getting-started.md) — building, running, REPL
- [Language Guide](language-guide.md) — syntax, stack model, core concepts
- [Builtins Reference](builtins.md) — every built-in word documented
- [FFI Guide](ffi.md) — calling C libraries, structs, callbacks
- [Macros](macros.md) — compile-time metaprogramming
- [Examples](examples.md) — annotated walkthroughs

## What Makes fy Interesting

- **~1.8MB static binary** — the entire compiler, JIT, assembler, REPL, and runtime
- **JIT compiler in <4k LoC Zig** — compiles fy source directly to ARM64 machine code at runtime
- **No interpreter** — every word is compiled to native instructions before execution
- **Advanced FFI** — call into macOS frameworks (AppKit, CoreAudio), raylib, libm, or any C library
- **Compile-time macros** — fy macros run real fy code at compile time and emit machine code

## Quick Taste

```forth
( Fibonacci — classic recursive definition )
: fib  dup 1 <= [ drop 1 ] [ dup 1- fib swap 2 - fib + ] ifte ;

10 fib .    ( prints 89 )
```

```forth
( Functional pipeline — map, reduce, filter )
[1 2 3 4 5] [dup *] map        ( square each: [1 4 9 16 25] )
0 swap [+] reduce .             ( sum: 55 )
```

```forth
( Call any C function )
"/usr/lib/libSystem.B.dylib" dl-open
: _lib ;
_lib "strlen" dl-sym
: strlen  _lib "strlen" dl-sym bind: s:i ;
"hello" strlen .                ( prints 5 )
```
