# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

`fy` is a concatenative programming language that JIT compiles to aarch64 machine code. It features:
- Stack-based execution with tagged values (integers and heap objects)
- JIT compilation to native ARM64 assembly
- Quote-based higher-order functions with lazy JIT caching
- Interactive REPL with persistent stack state
- Memory-mapped executable pages with proper codesigning on macOS

## Build, Test, and Development Commands

**Core Commands:**
- `zig build` — Build and install to `zig-out/bin/fy`
- `zig build run -- [args]` — Run with arguments (pass flags after `--`)
- `zig build test` — Run all unit tests in `src/main.zig`
- `zig fmt src build.zig` — Format code before committing

**Running fy:**
- `./zig-out/bin/fy` — Start interactive REPL
- `./zig-out/bin/fy examples/fib.fy` — Execute a file
- `./zig-out/bin/fy --eval "2 3 +"` — Evaluate expression
- `./zig-out/bin/fy --help` — Show all CLI options

**Development Helpers:**
- `zig build run-jit69` — Run minimal JIT demo (`src/jit69.zig`)
- `zig build install-signed` — macOS: Install with proper entitlements for JIT
- Set `FY_DEBUG_ADAPTER=1` to debug quote compilation and execution

## Architecture Overview

### Core Components (`src/main.zig`)

**Fy struct**: Main interpreter instance containing:
- `userWords`: HashMap of user-defined word definitions
- `dataStack[512]`: Main computation stack
- `trampStack[256]`: Isolated stack for adapter functions
- `image`: Memory-mapped JIT executable pages
- `heap`: Unified storage for strings and quotes

**Value System**: Tagged 64-bit values
- `TAG_INT = 0`: Direct integer storage
- `TAG_STR = 1`: Heap reference with high bias (`HEAP_BASE = 1<<40`)
- Type checking via `isInt(v)`, `isStr(v)` functions

**Heap Management**: Unified heap for strings and quotes
- `Heap.Entry`: Union of String/Quote objects  
- `QuoteObj`: Contains `items` array and optional `cached_ptr` for JIT
- Lazy JIT compilation: quotes compile to machine code on first execution

### JIT Compilation System

**Image struct**: Memory-mapped executable pages
- Platform-specific mmap with MAP_JIT on macOS
- Write-protect toggling via `pthread_jit_write_protect_np`
- Auto-growing page allocation

**Compiler struct**: Generates ARM64 assembly
- `code`: Dynamic array of u32 machine instructions
- Call slot patching for runtime function resolution
- Self-recursion support via `RECUR` pseudo-instruction
- Stack frame management with callee-saved register preservation

**Assembly Helpers (`src/asm.zig`)**: Pre-encoded ARM64 instructions
- Stack operations: `.push/.pop` using x21 (stack base) and x22 (stack top)
- Arithmetic/comparison ops with proper calling conventions
- Control flow with conditional branches and function calls

### Language Features

**Word System**: Both built-in and user-defined
- `words` StaticStringMap: Built-in operations (arithmetic, stack, control)
- `userWords` HashMap: Runtime-defined functions
- Compilation modes: `.None`, `.Quote`, `.Function`, `.SessionRet`

**Quote System**: First-class code objects
- `[code]` syntax creates heap-allocated quote objects
- `\word` shorthand for single-word quotes  
- Lazy JIT: quotes compile to function pointers on first `do`
- Operations: `cat` (concatenation), `qlen`, `qhead`, `qtail`, `qpush`

**Parser (`src/main.zig` lines 1082+)**: Token-based with:
- Number literals (integers)
- String literals with escape sequence support
- Character literals (`'a` syntax)
- Nested comment support `( ... ( nested ) ... )`
- Quote parsing with arbitrary nesting depth

## Development Guidelines

### Adding Built-in Words
1. Add assembly sequence to `words` StaticStringMap (line ~866)
2. Use helpers: `binOp()`, `cmpOp()`, `inlineWord()`, `fnToWord()`  
3. Follow calling convention: x0=top-of-stack, x1=second, etc.
4. Add comprehensive test cases in test blocks

### Adding Builtin Functions
1. Implement in `Builtins` struct with proper signature
2. Access fy instance via `@as(*Fy, @ptrFromInt(fyPtr))`
3. Use `fnToWord()` to generate calling wrapper
4. Handle both integer and heap value types appropriately

### Testing Strategy
- Unit tests use `TestCase` struct with input/expected pairs
- Tests cover: basic arithmetic, stack ops, user definitions, quotes, recursion
- Run `zig build test` frequently during development
- Add `.fy` example files for complex features

### Memory Management
- All heap allocations use `fy.fyalloc` (passed-in allocator)
- User word definitions store copied code arrays
- Quote items are deep-copied to prevent use-after-free
- JIT code is freed after linking to executable pages

## Platform-Specific Notes

**macOS/Apple Silicon:**
- Requires codesigning with JIT entitlements (`entitlements.plist`)
- Uses MAP_JIT and pthread_jit_write_protect_np for executable memory
- Default ad-hoc signing ("-") avoids prompts; override with `-Dcodesign-id`

**ARM64 Target Only:**
- All assembly is aarch64-specific
- Register usage: x21=stack base, x22=stack top, x29=frame pointer
- Instruction cache clearing via `__clear_cache()` after JIT

## File Organization
- `src/main.zig`: Core interpreter (2282 lines) — all major components
- `src/asm.zig`: ARM64 instruction encodings and pseudo-instructions
- `src/args.zig`: CLI argument parsing with help/version/eval flags
- `src/jit69.zig`: Minimal JIT demo for testing
- `examples/*.fy`: Sample programs showing language features
- `build.zig`: Zig build configuration with codesigning support
