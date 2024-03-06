pub const @"str x0, [sp, #-16]!" = 0xf81f0fe0;
pub const @"str x1, [sp, #-16]!" = 0xf81f0fe1;
pub const @"ldr x0, [sp], #16" = 0xf84107e0;
pub const @"ldr x1, [sp], #16" = 0xf84107e1;
pub const @"stp x29, x30, [sp, #0x10]!" = 0xa9bf7bfd;
pub const @"ldp x29, x30, [sp], #0x10" = 0xa8c17bfd;

pub const @"stp x0, x1, [x21, #-16]!" = 0xa9bf06a0;
pub const @"ldp x0, x1, [x21], #16" = 0xa8c106a0;
pub const @"stp x1, x0, [x21, #-16]!" = 0xa9bf02a1;
pub const @"ldp x1, x0, [x21], #16" = 0xa8c102a1;
pub const @"stp x2, x3, [x21, #-16]!" = 0xa9bf0ea2;
pub const @"ldp x2, x3, [x21], #16" = 0xa8c10ea2;

pub const @"mov x0, x21" = 0xaa1503e0;
pub const @"mov x1, x22" = 0xaa1603e1;

pub const @"str x0, [x21, #-8]!" = 0xf81f8ea0;
pub const @"str x1, [x21, #-8]!" = 0xf81f8ea1;

pub const @"ldr x0, [x21], #8" = 0xf84086a0;
pub const @"ldr x1, [x21], #8" = 0xf84086a1;

pub const @"mov x29, sp" = 0x910003fd;
pub const @"mov sp, x29" = 0x910003bf;

pub const @"mov x0, #0" = 0xd2800000;
pub const @"mov x0, #1" = 0xd2800020;

pub const @"add x0, x0, x1" = 0x8b010000;
pub const @"sub x0, x1, x0" = 0xcb010000;
pub const @"mul x0, x0, x1" = 0x9b017c00;
pub const @"sdiv x0, x1, x0" = 0x9ac10c00;
pub const @"and x0, x0, x1" = 0x8a010000;

pub const @"add x0, x0, #1" = 0x91000400;
pub const @"sub x0, x0, #1" = 0xd1000400;

pub const @"sub x0, x22, x21" = 0xcb1502c0;
pub const @"asr x0, x0, #3" = 0x9343fc00;

pub const @"cbz x0, 0" = 0xb4000000;

pub const @"cmp x0, x1" = 0xeb01001f;

pub const @"cmp x2, #0" = 0xf100005f;
pub const @"csel x0, x0, x1, ne" = 0x9a811000;

pub const @"b 0" = 0x14000000;
pub const @"b 2" = @"b 0" + 2;

pub const @"beq #2" = 0x54000060;
pub const @"bne #2" = 0x54000061;
pub const @"bgt #2" = 0x5400006c;
pub const @"blt #2" = 0x5400006b;
pub const @"bge #2" = 0x5400006a;
pub const @"ble #2" = 0x5400006d;

pub const @"blr x0" = 0xd63f0000;

pub const ret = 0xd65f03c0;

// pseudo instructions

// call slot is used to indicate where to put the function call address and is replaced with the actual address
pub const CALLSLOT = 0xffffffff;

pub const @".push x0" = @"str x0, [x21, #-8]!"; //@"str x0, [sp, #-16]!";
pub const @".push x1" = @"str x1, [x21, #-8]!"; //@"str x1, [sp, #-16]!";
pub const @".pop x0" = @"ldr x0, [x21], #8"; //@"ldr x0, [sp], #16";
pub const @".pop x1" = @"ldr x1, [x21], #8"; //@"ldr x1, [sp], #16";

pub const @".push x0, x1" = @"stp x1, x0, [x21, #-16]!";
pub const @".pop x0, x1" = @"ldp x0, x1, [x21], #16";
pub const @".push x1, x0" = @"stp x0, x1, [x21, #-16]!";
pub const @".pop x1, x0" = @"ldp x1, x0, [x21], #16";
pub const @".push x2, x3" = @"stp x2, x3, [x21, #-16]!";
pub const @".pop x2, x3" = @"ldp x2, x3, [x21], #16";

// register used to store call address: x20
pub const REGCALL = 20;

// helpers
pub fn @"blr Xn"(n: u5) u32 {
    return @"blr x0" | @as(u32, @intCast(n)) << 5;
}

pub fn @"cbz Xn, offset"(n: u5, offset: u19) u32 {
    return @"cbz x0, 0" | @as(u32, @intCast(n)) | @as(u32, @intCast(offset)) << 5;
}

pub fn @"b offset"(offset: i26) u32 {
    //@compileLog("b", offset, @"b 0" | (@as(u32, @bitCast(@as(i32, offset)))) & 0x3ffffff);
    return @"b 0" | (@as(u32, @bitCast(@as(i32, offset))) & 0x3ffffff);
}

pub fn @".pop Xn"(n: usize) u32 {
    return @".pop x0" + @as(u32, @intCast(n));
}

pub fn @"lsr Xn, Xm, #s"(n: u5, m: u5, s: u6) u32 {
    return 0x9ac12800 | @as(u32, @intCast(n)) | @as(u32, @intCast(m)) << 5 | @as(u32, @intCast(s)) << 10;
}
