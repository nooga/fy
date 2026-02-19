# Getting Started

[Home](README.md) | **Getting Started** | [Language Guide](language-guide.md) | [Builtins](builtins.md) | [FFI](ffi.md) | [Macros](macros.md) | [Examples](examples.md)

## Requirements

- **macOS on Apple Silicon** (M1/M2/M3/M4)
- **Zig compiler** (0.13+)

fy generates ARM64 machine code and uses macOS-specific JIT APIs (`MAP_JIT`, `pthread_jit_write_protect_np`). It does not run on Linux or x86.

## Building

```sh
git clone <repo-url>
cd fy
zig build
```

The binary lands at `./zig-out/bin/fy` (~1.8MB). The build system handles code signing for JIT execution automatically.

## Running

### Interactive REPL

```sh
./zig-out/bin/fy
```

If no files or `-e` flags are given, fy drops into the REPL:

```
fy! v0.0.1
fy> 2 3 + .
5
    0
fy> : square dup * ;
    0
fy> 7 square .
49
    0
```

The REPL preserves the data stack between lines. The `0` printed after each result is the return value of the session expression.

### Running Files

```sh
./zig-out/bin/fy examples/fib.fy
```

### Evaluating Expressions

```sh
./zig-out/bin/fy -e "2 3 + ."
```

### Shebang Scripts

fy files can start with a shebang:

```
#!/path/to/fy
10 fib .
```

The `#!` line is automatically stripped before compilation.

## Command-Line Flags

| Flag | Description |
|------|-------------|
| `-e`, `--eval <expr>` | Evaluate an expression |
| `-r`, `--repl` | Launch interactive REPL |
| `-i`, `--image` | Dump JIT image to `fy.out` |
| `-v`, `--version` | Print version |
| `-s`, `--serve` | Start the hot-patching TCP listener |
| `-p`, `--port <n>` | Set the listener port (default: OS-assigned) |
| `-h`, `--help` | Show help |

## Editor Support

A VSCode extension with syntax highlighting and live hot-patching is available in `editors/vscode/fy-lang/`. See the [Editor Support](editor.md) page for installation and usage.

## Running Tests

The `examples/golden/` directory contains golden tests (`.fy` files paired with `.expected` output files). Run them with:

```sh
zig build test
```

## Next Steps

- [Language Guide](language-guide.md) — learn the syntax and core concepts
- [Examples](examples.md) — see annotated real-world programs
