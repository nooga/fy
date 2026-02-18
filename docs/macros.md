# Macros

[Home](README.md) | [Getting Started](getting-started.md) | [Language Guide](language-guide.md) | [Builtins](builtins.md) | [FFI](ffi.md) | **Macros** | [Examples](examples.md)

fy macros are words that run at **compile time**. When the compiler encounters a macro during compilation, it executes the macro immediately instead of emitting a call. The macro can inspect and modify the compiler's output, enabling custom syntax and compile-time computation.

## Defining Macros

```forth
macro: name body ;
```

The body is compiled into a self-contained function that uses a separate macro data stack (isolated from the runtime stack). When invoked during compilation, the macro can:

- Read the last compiled quote with `peek-quote`
- Remove the last emitted push with `unpush`
- Emit literal values with `emit-lit`
- Emit word calls with `emit-word`

## Compiler Primitives

These words are only available during macro execution:

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `emit-lit` | `value --` | Emit code that pushes `value` as a literal |
| `emit-word` | `name --` | Emit a call to the named word |
| `peek-quote` | `-- quote\|0` | Get the last quote literal pushed by the compiler |
| `unpush` | `--` | Remove the last quote push from compiled output |

## Example: `const` Macro

The `const` macro evaluates a quote at compile time and bakes the result as a literal:

```forth
macro: const  peek-quote unpush do emit-lit ;
```

How it works:
1. `peek-quote` — get the quote the compiler just pushed (e.g., `[2 3 +]`)
2. `unpush` — remove the push instruction from the compiled output
3. `do` — execute the quote at compile time, producing a result
4. `emit-lit` — emit machine code to push that result as a constant

Usage:

```forth
[2 3 +] const .    ( compiles as if you wrote: 5 . )
```

## Example: Compile-Time Fibonacci

```forth
: cfib  dup 1 <= [ drop 1 ] [ dup 1- cfib swap 2 - cfib + ] ifte ;

macro: const  peek-quote unpush do emit-lit ;

[10 cfib] const .   ( computed at compile time! prints 89 )
```

The Fibonacci value is computed during compilation. At runtime, it's just a literal push — zero overhead.

## Example: Objective-C Integration

From `examples/objc.fy`, macros create custom syntax for Objective-C message sending:

```forth
macro: @class  peek-quote unpush do cls emit-lit ;
macro: @sel    peek-quote unpush do sel emit-lit ;
```

This enables:

```forth
[NSWindow] @class
[alloc] @sel
msg0
```

Which at compile time resolves the class and selector, baking the pointers as constants.

## How Macros Interact with the Compiler

When the compiler sees a word marked as `immediate` (which is what `macro:` sets):

1. It does **not** emit a call instruction
2. Instead, it calls the macro function immediately
3. The macro runs with access to `Builtins.compilerPtr` — a pointer to the active compiler
4. The macro can call `emit-lit` and `emit-word` to inject code into the current compilation
5. The macro can call `peek-quote` and `unpush` to inspect and modify recently compiled code

This happens at the ARM64 machine code level — macros don't manipulate an AST or bytecode, they directly control what machine instructions get emitted.

## Quote Introspection

Macros can inspect quote contents using the standard quote operations:

```forth
macro: my-macro
  peek-quote          ( get the quote )
  dup qlen            ( check its length )
  0 swap qnth         ( get first element )
  dup word?           ( is it a word? )
  [ word->str ]       ( convert to string if so )
  [ drop "not-a-word" ]
  ifte
  ( ... do something with the string ... )
  emit-lit
;
```

## Macro Data Stack

Macros execute on a separate data stack (`macro_data_stack_mem`, 8KB) so they don't interfere with runtime stack state. This means macros can push and pop freely without corrupting the program being compiled.

## Limitations

- Macros can only emit literals (`emit-lit`) and word calls (`emit-word`)
- Macros cannot emit arbitrary machine code or control flow
- `peek-quote` only sees the most recently compiled quote literal
- Macros run in sequence with compilation — they see the compiler state at the point where they appear
