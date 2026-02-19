# fy

![ZigZig Top guys enjoying fy](./fy.png)

Short for _funky yak_, _flying yacht_, or _funny yodeling_ depending on your mood. Also _fuck yeah_.

`fy` is a tiny concatenative programming language JIT compiled to aarch64 machine code.

`fy` is a toy, of the kind where the batteries constantly leak and only that weird guy in suspenders plays with it.

Join [#fy on concatenative Discord](https://discord.com/channels/1150472957093744721/1166896397254131804).

## Highlights

- **~1.8MB static binary** — the entire compiler, JIT, assembler, REPL, and runtime
- **JIT compiler in <4k LoC Zig** — compiles directly to ARM64 machine code at runtime
- **No interpreter** — every word compiles to native instructions before execution
- **Advanced FFI** — call macOS frameworks (AppKit, CoreAudio), raylib, libm, or any C library
- **Compile-time macros** — run real fy code at compile time, emit machine code
- **Structs** — define C-compatible memory layouts with auto-generated accessors
- **Callbacks** — create C-callable function pointers with thread-safe private stacks

## Quick Taste

```forth
: fib  dup 1 <= [ drop 1 ] [ dup 1- fib swap 2 - fib + ] ifte ;
10 fib .   ( 89 )
```

```forth
[1 2 3 4 5] [dup *] map 0 swap [+] reduce .   ( 55 )
```

```forth
:: _lib "/usr/lib/libSystem.B.dylib" dl-open ;
: strlen  _lib "strlen" dl-sym bind: s:i ;
"hello" strlen .   ( 5 )
```

## Building

`fy` requires **macOS on Apple Silicon** (aarch64). The JIT uses `MAP_JIT` and `pthread_jit_write_protect_np` which are macOS-specific. You'll need a Zig compiler (0.13+).

```sh
zig build
./zig-out/bin/fy
```

Check `--help` for available flags and arguments.

## Documentation

Full language documentation is in [`docs/`](docs/README.md):

- [Getting Started](docs/getting-started.md) — building, running, REPL
- [Language Guide](docs/language-guide.md) — syntax, stack model, core concepts
- [Builtins Reference](docs/builtins.md) — every built-in word documented
- [FFI Guide](docs/ffi.md) — calling C libraries, structs, callbacks
- [Macros](docs/macros.md) — compile-time metaprogramming
- [Editor Support](docs/editor.md) — VSCode extension, live hot-patching
- [Examples](docs/examples.md) — annotated walkthroughs

## Examples

Examples can be found in [`examples/`](examples/). Highlights:

| Example                                                 | Description                       |
| ------------------------------------------------------- | --------------------------------- |
| [`fib.fy`](examples/fib.fy)                             | Fibonacci                         |
| [`fact.fy`](examples/fact.fy)                           | Factorial                         |
| [`tak.fy`](examples/tak.fy)                             | TAK benchmark with locals         |
| [`sierp.fy`](examples/sierp.fy)                         | Sierpinski triangle PPM generator |
| [`libm.fy`](examples/libm.fy)                           | Math functions via FFI            |
| [`raylib_hello.fy`](examples/raylib_hello.fy)           | raylib window                     |
| [`raylib_synth_poly.fy`](examples/raylib_synth_poly.fy) | Polyphonic synthesizer            |
| [`glass.fy`](examples/glass.fy)                         | macOS Liquid Glass via ObjC FFI   |
| [`macro.fy`](examples/macro.fy)                         | Compile-time macros               |

## Editor Support

A VSCode extension with syntax highlighting and **live hot-patching** is in [`editors/vscode/fy-lang/`](editors/vscode/fy-lang/). Run your program with `fy --serve`, place your cursor on a word definition, hit **Cmd+Shift+Enter**, and the running program picks up the new code instantly — no restart needed. See the [Editor Support docs](docs/editor.md) for details.

## Features

- If you make a mistake, fy simply crashes. No hand-holding, no "did you mean...?", no stack traces. Just silence and a nonzero exit code. This is a feature - the authentic 1970s mainframe experience, now on your $3000 laptop.
- There is no plan.
