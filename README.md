# fy

![ZigZig Top guys enjoying fy](./fy.png)

Short for _funky yak_, _flying yacht_, or _funny yodeling_ depending on your mood. Also _fuck yeah_.

`fy` is a tiny concatenative programming language JIT compiled to aarch64 machine code.

`fy` is a toy, of the kind where the batteries constantly leak and only that weird guy in suspenders plays with it.

Join [#fy on concatenative Discord](https://discord.com/channels/1150472957093744721/1166896397254131804).

## Building

`fy` is written in Zig and targets aarch64 exclusively. You'll need a Zig compiler and a 64-bit ARM machine such as AppleSilicon or a Raspberry Pi.

Build with:

```sh
zig build
```

Run with:

```sh
./zig-out/bin/fy
```

Check `--help` for the latest news on available flags and arguments.

## Examples

Examples can be found in `examples/`.

## Features

[There is no plan.](https://github.com/SerenityOS/serenity/blob/master/Documentation/FAQ.md#will-serenityos-support-thing)
