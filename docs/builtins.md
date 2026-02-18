# Builtins Reference

[Home](README.md) | [Getting Started](getting-started.md) | [Language Guide](language-guide.md) | **Builtins** | [FFI](ffi.md) | [Macros](macros.md) | [Examples](examples.md)

Every built-in word in fy, organized by category. Stack effects are written as `( before -- after )`.

## Arithmetic

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `+` | `a b -- a+b` | Integer addition |
| `-` | `a b -- a-b` | Integer subtraction |
| `*` | `a b -- a*b` | Integer multiplication |
| `/` | `a b -- a/b` | Signed integer division |
| `!-` | `a b -- b-a` | Reverse subtraction |
| `1+` | `a -- a+1` | Increment |
| `1-` | `a -- a-1` | Decrement |

## Comparison

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `=` | `a b -- flag` | Equal |
| `!=` | `a b -- flag` | Not equal |
| `<` | `a b -- flag` | Less than |
| `>` | `a b -- flag` | Greater than |
| `<=` | `a b -- flag` | Less or equal |
| `>=` | `a b -- flag` | Greater or equal |

Flags are `1` (true) or `0` (false).

## Bitwise & Logic

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `&` | `a b -- a&b` | Bitwise AND |
| `or` | `a b -- a\|b` | Bitwise OR |
| `xor` | `a b -- a^b` | Bitwise XOR |
| `<<` | `a b -- a<<b` | Left shift |
| `>>` | `a b -- a>>b` | Logical right shift |
| `not` | `f -- !f` | Boolean NOT (0→1, nonzero→0) |

## Stack Manipulation

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `dup` | `a -- a a` | Duplicate top |
| `dup2` | `a b -- a b a b` | Duplicate top pair |
| `drop` | `a --` | Discard top |
| `drop2` | `a b --` | Discard top two |
| `swap` | `a b -- b a` | Swap top two |
| `over` | `a b -- a b a` | Copy second to top |
| `over2` | `c d a b -- c d a b c d` | Copy 3rd and 4th to top |
| `nip` | `a b -- b` | Drop second element |
| `tuck` | `a b -- b a b` | Copy top under second |
| `rot` | `a b c -- b c a` | Rotate three upward |
| `-rot` | `a b c -- c a b` | Rotate three downward |
| `depth` | `-- n` | Current stack depth |

## Retain Stack

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `>r` | `x --` | Move TOS to retain stack |
| `r>` | `-- x` | Pop from retain stack |
| `r@` | `-- x` | Copy top of retain stack |

## Control Flow

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `do` | `... f --` | Execute quote/callable f |
| `do?` | `pred f --` | Execute f only if pred is non-zero |
| `ifte` | `cond ft ff --` | Execute ft if cond non-zero, else ff |
| `dotimes` | `n f --` | Execute f n times |
| `repeat` | `cond f --` | Loop: execute f while TOS non-zero |
| `recur` | `--` | Tail-recursive jump to word start |
| `dip` | `x f -- x` | Execute f, preserving x underneath |
| `not` | `f -- !f` | Boolean negation |

## Output

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `.` | `a --` | Print value (int, string, or quote) |
| `s.` | `a --` | Print value (alias for `.`) |
| `.c` | `a --` | Print as ASCII character |
| `.nl` | `--` | Print newline |
| `.hex` | `a --` | Print as hexadecimal |
| `f.` | `a --` | Print as floating-point number |
| `spy` | `a -- a` | Print value without consuming it |
| `.dbg` | `--` | Print entire data stack |

## Strings

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `s+` | `a b -- a+b` | Concatenate two strings |
| `slen` | `s -- n` | String length in bytes |

## Floats

Floats are f64 values stored as bitcast i64. Use `i>f` / `f>i` to convert.

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `f+` | `a b -- a+b` | Float addition |
| `f-` | `a b -- a-b` | Float subtraction |
| `f*` | `a b -- a*b` | Float multiplication |
| `f/` | `a b -- a/b` | Float division |
| `f<` | `a b -- flag` | Float less-than |
| `f>` | `a b -- flag` | Float greater-than |
| `f=` | `a b -- flag` | Float equality |
| `fneg` | `a -- -a` | Float negation |
| `i>f` | `n -- f` | Integer to float |
| `f>i` | `f -- n` | Float to integer (truncate) |
| `f.` | `f --` | Print float |

## Quote Operations

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `qnil` | `-- q` | Create empty quote |
| `qlen` | `q -- n` | Quote length |
| `qempty?` | `q -- flag` | Is quote empty? |
| `qhead` | `q -- val` | First element |
| `qtail` | `q -- q'` | All but first element |
| `qpush` | `q x -- q'` | Append element to quote |
| `qnth` | `q n -- val` | Nth element (0-based) |
| `qnth-type` | `q n -- type` | Type of nth element (0=int, 1=float, 2=word, 3=string, 4=quote) |
| `cat` | `a b -- q` | Concatenate two quotes |
| `qcat` | `a b -- q` | Alias for `cat` |
| `compose` | `a b -- q` | Alias for `cat` |
| `curry` | `val quot -- quot'` | Prepend value to quote |
| `range` | `n -- q` | Create quote `[0 1 2 ... n-1]` |

## Higher-Order

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `map` | `list f -- list'` | Apply f to each element, collect results |
| `reduce` | `acc list f -- result` | Fold: f receives `(element accumulator)` |
| `filter` | `list f -- list'` | Keep elements where f returns non-zero |
| `each` | `list f -- 0` | Apply f to each element, discard results |

## Type Checking

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `int?` | `a -- flag` | Is value an integer? |
| `string?` | `a -- flag` | Is value a string? |
| `quote?` | `a -- flag` | Is value a quote? |
| `word?` | `a -- flag` | Is value a single-word quote? |
| `word->str` | `a -- s` | Extract word name as string |

## I/O

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `slurp` | `path -- string` | Read entire file as string |
| `spit` | `string path -- 0` | Write string to file |
| `readln` | `-- string` | Read line from stdin |

## Memory

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `alloc` | `size -- ptr` | Allocate zeroed memory (via libc malloc) |
| `free` | `ptr -- 0` | Free allocated memory |
| `!64` | `val addr --` | Store 64-bit value |
| `@64` | `addr -- val` | Load 64-bit value |
| `!32` | `val addr --` | Store 32-bit value |
| `@32` | `addr -- val` | Load 32-bit value |
| `f!32` | `fval addr --` | Store float32 |
| `f@32` | `addr -- fval` | Load float32 |
| `!16` | `val addr --` | Store 16-bit value |
| `@16` | `addr -- val` | Load 16-bit value |

## FFI

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `dl-open` | `path -- handle` | Open dynamic library |
| `dl-sym` | `handle name -- fptr` | Look up symbol |
| `dl-close` | `handle -- 0` | Close library |
| `cstr-new` | `string -- ptr` | Allocate C string from fy string |
| `cstr-free` | `ptr -- 0` | Free C string |
| `with-cstr` | `string callable -- result` | Auto-managed C string call |
| `with-cstr-q` | `string quote -- result` | Auto-managed C string with quote |
| `with-cstr-f` | `string fptr quote -- result` | Auto-managed with fptr+quote |
| `ccall0` | `fptr -- ret` | Call C function with 0 args |
| `ccall1` | `fptr a -- ret` | Call C function with 1 arg |
| `ccall1pac` | `fptr a -- ret` | PAC-safe 1-arg call (Apple Silicon) |
| `ccall2` | `fptr a b -- ret` | Call C function with 2 args |
| `ccall3` | `fptr a b c -- ret` | Call C function with 3 args |

See [FFI Guide](ffi.md) for `bind:`, `sig:`, `callback:`, and struct details.

## Garbage Collection

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `gc` | `--` | Trigger mark-and-sweep garbage collection |

## Compiler Primitives (Macros Only)

These words are only available inside `macro:` definitions:

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `emit-lit` | `value --` | Emit push-literal machine code |
| `emit-word` | `name --` | Emit word call machine code |
| `peek-quote` | `-- quote\|0` | Get last compiled quote literal |
| `unpush` | `--` | Remove last quote push from output |

See [Macros](macros.md) for details.
