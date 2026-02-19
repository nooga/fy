# Editor Support

[Home](README.md) | [Getting Started](getting-started.md) | [Language Guide](language-guide.md) | [Builtins](builtins.md) | [FFI](ffi.md) | [Macros](macros.md) | [Examples](examples.md) | **Editor**

## VSCode Extension

The `editors/vscode/fy-lang/` directory contains a VSCode extension that provides syntax highlighting and live hot-patching for fy.

### Installation

From the repository root:

```sh
cd editors/vscode/fy-lang
npm install
npm run compile
```

Then install it locally in VSCode:

1. Open VSCode
2. Run **Extensions: Install from VSIX...** from the command palette — or, for development, use **Developer: Reload Window** after symlinking the extension folder into `~/.vscode/extensions/`

### Features

- **Syntax highlighting** — keywords, strings, comments, numbers, word definitions
- **Live hot-patching** — send word definitions to a running fy process with a keystroke

## Live Hot-Patching

fy supports Clojure-style interactive development: edit a word definition in your editor, hit a keybinding, and the running program picks up the new definition immediately — no restart, no reload.

This works because fy uses a **trampoline indirection layer** in the JIT. Every user-defined word gets a stable 4-byte trampoline (a single ARM64 `B` instruction). All callers jump to the trampoline, which jumps to the actual code. When a word is redefined, only the trampoline's target is patched — every caller instantly sees the new behavior.

### Setup

Start your fy program with the `--serve` flag:

```sh
# Auto-assign a port (written to .fy-port in the working directory)
fy --serve my_program.fy

# Or specify a port explicitly
fy --serve --port 4422 my_program.fy
```

The serve flag starts a background TCP listener on `127.0.0.1`. The VSCode extension connects to this listener to send definitions.

### Usage

1. Start your program with `--serve`
2. Open a `.fy` source file in VSCode
3. Place your cursor inside a word definition (`: name ... ;`)
4. Press **Cmd+Shift+Enter** (macOS) or **Ctrl+Shift+Enter** (Linux/Windows)

The extension finds the complete definition surrounding your cursor, sends it to the running process, and flashes the sent region to confirm. The status bar shows the result.

### What Gets Sent

The extension detects these definition forms:

- **Word definitions** — `: name ... ;`
- **Constants** — `:: name ... ;`
- **Macros** — `macro: name ... ;`

It scans backward from the cursor to find the nearest definition start, then forward to the matching `;`.

### Namespace Resolution

fy maps source file paths to namespaces. When you send a definition from a file that was imported with a namespace:

```forth
import "synth"    ( words prefixed with synth: )
```

The runtime knows that definitions sent from `synth.fy` belong to the `synth:` namespace and scopes them correctly.

### Example Workflow

Here's a typical interactive development session with a raylib program:

```sh
# Terminal: start the program with hot-patching enabled
fy --serve --port 4422 examples/raylib_synth_poly.fy
```

The synth opens its window and starts running. Now edit a word in `raylib_synth_poly.fy` in VSCode — say, change a frequency calculation or a drawing routine — and hit **Cmd+Shift+Enter**. The running program updates instantly. No restart, no state loss.

### How It Works

1. **Trampolines** — each user word has a stable entry point (a `B target` instruction). Callers `BL` to the trampoline, never to the word body directly
2. **TCP protocol** — the extension sends `filepath\ncode` over TCP; the runtime compiles the code, patches the trampoline, and replies `ok` or `error: ...`
3. **Thread safety** — compilation happens under a mutex; the JIT page is always mapped RWX with per-thread W^X via `pthread_jit_write_protect_np`; instruction cache is flushed after patching

### Limitations

- **Constants** (`:: name value ;`) are inlined at compile time — redefining a constant patches the constant word itself, but callers that already compiled with the old value won't update
- **Macros** run at compile time only — redefining a macro affects future compilations, not already-compiled code
- **Stack-incompatible redefinitions** may crash — if a word previously returned 1 value and you redefine it to return 3, callers compiled with the old stack effect will misbehave

## CLI Flags

| Flag | Description |
|------|-------------|
| `-s`, `--serve` | Start the hot-patching TCP listener |
| `-p`, `--port <n>` | Set the listener port (default: OS-assigned, written to `.fy-port`) |
