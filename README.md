# fy
![ZigZig Top guys enjoying some fy](./fy.png)

As in: *functional, yeah*.

`fy` is a tiny concatenative programming language JIT compiled to aarch64 machine code. 

This is a toy, and an early work in progress. 

Join [#fy on concatenative Discord](https://discord.com/channels/1150472957093744721/1166896397254131804) to discuss.

## Building

`fy` is written in Zig and targets aarch64. You'll need a Zig compiler and a 64-bit ARM machine such as AppleSilicon or a Raspberry Pi. 

Build with:
```sh
zig build
```

Run with:
```sh
./zig-out/bin/fy
```

Peruse its puny source at `src/main.zig`.

## Features

[There is no plan.](https://github.com/SerenityOS/serenity/blob/master/Documentation/FAQ.md#will-serenityos-support-thing)