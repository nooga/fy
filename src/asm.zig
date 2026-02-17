pub const @"str x0, [sp, #-16]!" = 0xf81f0fe0;
pub const @"str x1, [sp, #-16]!" = 0xf81f0fe1;
pub const @"ldr x0, [sp], #16" = 0xf84107e0;
pub const @"ldr x1, [sp], #16" = 0xf84107e1;
pub const @"stp x29, x30, [sp, #0x10]!" = 0xa9bf7bfd;
pub const @"ldp x29, x30, [sp], #0x10" = 0xa8c17bfd;
pub const @"stp x21, x22, [sp, #0x10]!" = 0xa9bf5bf5;
pub const @"ldp x21, x22, [sp], #0x10" = 0xa8c15bf5;
pub const @"stp x1, x2, [sp, #-16]!" = 0xa9bf02e1;
pub const @"ldp x2, x3, [sp], #16" = 0xa8c106e2;

pub const @"stp x0, x1, [x21, #-16]!" = 0xa9bf06a0;
pub const @"ldp x0, x1, [x21], #16" = 0xa8c106a0;
pub const @"stp x1, x0, [x21, #-16]!" = 0xa9bf02a1;
pub const @"ldp x1, x0, [x21], #16" = 0xa8c102a1;
pub const @"stp x2, x3, [x21, #-16]!" = 0xa9bf0ea2;
pub const @"ldp x2, x3, [x21], #16" = 0xa8c10ea2;

pub const @"mov x0, x21" = 0xaa1503e0;
pub const @"mov x1, x22" = 0xaa1603e1;
pub const @"mov x0, x22" = 0xaa1603e0;
pub const @"mov x21, x0" = 0xaa0003f5;
pub const @"mov x22, x0" = 0xaa0003f6;
pub const @"mov x1, x21" = 0xaa1503e1;
pub const @"mov x21, x1" = 0xaa0103f5;
pub const @"mov x22, x2" = 0xaa0203f6;
pub const @"mov x16, x0" = 0xaa0003f0;
pub const @"mov x2, x21" = 0xaa1503e2;
pub const @"mov x3, x22" = 0xaa1603e3;
pub const @"mov x3, x21" = 0xaa1503e3;
pub const @"mov x4, x22" = 0xaa1603e4;

pub const @"mov x0, x1" = 0xaa0103e0;
pub const @"mov x1, x0" = 0xaa0003e1;
pub const @"mov x0, x2" = 0xaa0203e0;
pub const @"mov x1, x2" = 0xaa0203e1;
pub const @"mov x2, x0" = 0xaa0003e2;
pub const @"mov x2, x1" = 0xaa0103e2;
pub const @"mov x0, x3" = 0xaa0303e0;
pub const @"mov x0, x4" = 0xaa0403e0;
pub const @"mov x0, x5" = 0xaa0503e0;
pub const @"mov x4, x0" = 0xaa0003e4;
pub const @"mov x5, x0" = 0xaa0003e5;
pub const @"mov x3, x0" = 0xaa0003e3;
pub const @"mov x4, x2" = 0xaa0203e4;

pub const @"str x0, [x21, #-8]!" = 0xf81f8ea0;
pub const @"str x1, [x21, #-8]!" = 0xf81f8ea1;

pub const @"ldr x0, [x21], #8" = 0xf84086a0;
pub const @"ldr x1, [x21], #8" = 0xf84086a1;

pub const @"mov x29, sp" = 0x910003fd;
pub const @"mov sp, x29" = 0x910003bf;

pub const @"mov x0, #0" = 0xd2800000;
pub const @"mov x0, #1" = 0xd2800020;
pub const @"mov x1, #0" = 0xd2800001;
pub const @"mov x2, #0" = 0xd2800002;

pub const @"add x0, x0, x1" = 0x8b010000;
pub const @"sub x0, x1, x0" = 0xcb010000;
pub const @"mul x0, x0, x1" = 0x9b017c00;
pub const @"sdiv x0, x1, x0" = 0x9ac10c00;
pub const @"and x0, x0, x1" = 0x8a010000;
pub const @"orr x0, x0, x1" = 0xaa010000;
pub const @"eor x0, x0, x1" = 0xca010000;
pub const @"lsl x0, x1, x0" = 0x9ac02020; // LSLV x0, x1, x0 (Rd=0, Rn=1, Rm=0)
pub const @"lsr x0, x1, x0" = 0x9ac02420; // LSRV x0, x1, x0 (Rd=0, Rn=1, Rm=0)

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
pub const CALLSLOT0 = 0xffffffff; // default call slot
pub const RECUR = 0xfffffffe;
pub const CALLSLOT3 = 0xfffffffb;

// Backward-compat alias
pub const CALLSLOT = CALLSLOT0;

pub const @".push x0" = @"str x0, [x21, #-8]!"; //@"str x0, [sp, #-16]!";
pub const @".push x1" = @"str x1, [x21, #-8]!"; //@"str x1, [sp, #-16]!";
pub const @".push x2" = 0xf81f8ea2; // str x2, [x21, #-8]!
pub const @".pop x0" = @"ldr x0, [x21], #8"; //@"ldr x0, [sp], #16";
pub const @".pop x1" = @"ldr x1, [x21], #8"; //@"ldr x1, [sp], #16";
pub const @".pop x2" = 0xf84086a2; // ldr x2, [x21], #8

pub const @".push x0, x1" = @"stp x1, x0, [x21, #-16]!";
pub const @".pop x0, x1" = @"ldp x0, x1, [x21], #16";
pub const @".push x1, x0" = @"stp x0, x1, [x21, #-16]!";
pub const @".pop x1, x0" = @"ldp x1, x0, [x21], #16";
pub const @".push x2, x3" = @"stp x2, x3, [x21, #-16]!";
pub const @".pop x2, x3" = @"ldp x2, x3, [x21], #16";

// same macros but with sp instead of x21
pub const @".rpush x0" = @"str x0, [sp, #-16]!";
pub const @".rpush x1" = @"str x1, [sp, #-16]!";
pub const @".rpop x0" = @"ldr x0, [sp], #16";
pub const @".rpop x1" = @"ldr x1, [sp], #16";

pub fn @".rpush Xn"(n: usize) u32 {
    return @"str x0, [sp, #-16]!" + @as(u32, @intCast(n));
}
pub fn @".rpop Xn"(n: usize) u32 {
    return @"ldr x0, [sp], #16" + @as(u32, @intCast(n));
}

// register used to store call address: use x16 (caller-saved) for PLT/IP0
pub const REGCALL = 16;

// helpers
pub fn @"blr Xn"(n: u5) u32 {
    return @"blr x0" | @as(u32, @intCast(n)) << 5;
}

pub fn @"cbz Xn, offset"(n: u5, offset: u19) u32 {
    return @"cbz x0, 0" | @as(u32, @intCast(n)) | @as(u32, @intCast(offset)) << 5;
}

pub fn @"cbnz Xn, offset"(n: u5, offset: u19) u32 {
    return 0xb5000000 | @as(u32, @intCast(n)) | @as(u32, @intCast(offset)) << 5;
}

/// BL imm26 -- branch with link, PC-relative, ±128MB range
/// offset is in instruction words (4 bytes each), not bytes
pub fn @"bl offset"(offset: i26) u32 {
    return 0x94000000 | (@as(u32, @bitCast(@as(i32, offset))) & 0x3ffffff);
}

pub fn @"b offset"(offset: i26) u32 {
    //@compileLog("b", offset, @"b 0" | (@as(u32, @bitCast(@as(i32, offset)))) & 0x3ffffff);
    return @"b 0" | (@as(u32, @bitCast(@as(i32, offset))) & 0x3ffffff);
}

pub fn @".pop Xn"(n: usize) u32 {
    return @".pop x0" + @as(u32, @intCast(n));
}

pub fn @".push Xn"(n: usize) u32 {
    return @".push x0" + @as(u32, @intCast(n));
}

pub fn @"lsr Xn, Xm, #s"(n: u5, m: u5, s: u6) u32 {
    return 0x9ac12800 | @as(u32, @intCast(n)) | @as(u32, @intCast(m)) << 5 | @as(u32, @intCast(s)) << 10;
}

// SP-relative helpers for locals frames
// Reserve a stack frame: sub sp, sp, #imm (imm must be a multiple of 16, imm <= 4095)
pub fn sub_sp_imm(imm: u12) u32 {
    return 0xd1000000 | (@as(u32, imm) << 10) | (31 << 5) | 31;
}

// Release a stack frame: add sp, sp, #imm (imm must be a multiple of 16, imm <= 4095)
pub fn add_sp_imm(imm: u12) u32 {
    return 0x91000000 | (@as(u32, imm) << 10) | (31 << 5) | 31;
}

// STR X0, [SP, #offset] where offset is in bytes and must be a multiple of 8 (max 32760)
pub fn str_sp_x0(offset_bytes: u32) u32 {
    const imm12: u32 = @as(u32, offset_bytes >> 3);
    return 0xf9000000 | (imm12 << 10) | (31 << 5) | 0; // Rt=x0, Rn=SP(31)
}

// LDR X0, [SP, #offset] where offset is in bytes and must be a multiple of 8 (max 32760)
pub fn ldr_sp_x0(offset_bytes: u32) u32 {
    const imm12: u32 = @as(u32, offset_bytes >> 3);
    return 0xf9400000 | (imm12 << 10) | (31 << 5) | 0; // Rt=x0, Rn=SP(31)
}

// MOV Xd, Xn (register-to-register move, alias for ORR Xd, XZR, Xn)
pub fn @"mov Xd, Xn"(d: u5, n: u5) u32 {
    return 0xaa0003e0 | @as(u32, d) | (@as(u32, n) << 16);
}

// --- Floating-point register instructions ---

// FMOV Dd, Xn — move 64-bit general register to double-precision float register
// Encoding: 0x9E670000 | Rn<<5 | Rd
pub fn @"fmov Dd, Xn"(d: u5, n: u5) u32 {
    return 0x9E670000 | @as(u32, d) | (@as(u32, n) << 5);
}

// FMOV Xd, Dn — move double-precision float register to 64-bit general register
// Encoding: 0x9E660000 | Rn<<5 | Rd
pub fn @"fmov Xd, Dn"(d: u5, n: u5) u32 {
    return 0x9E660000 | @as(u32, d) | (@as(u32, n) << 5);
}

// FMOV Sd, Wn — move 32-bit general register to single-precision float register
// Encoding: 0x1E270000 | Rn<<5 | Rd
pub fn @"fmov Sd, Wn"(d: u5, n: u5) u32 {
    return 0x1E270000 | @as(u32, d) | (@as(u32, n) << 5);
}

// FMOV Wd, Sn — move single-precision float register to 32-bit general register
// Encoding: 0x1E260000 | Rn<<5 | Rd
pub fn @"fmov Wd, Sn"(d: u5, n: u5) u32 {
    return 0x1E260000 | @as(u32, d) | (@as(u32, n) << 5);
}

// FCVT Sd, Dn — convert double to single-precision
// Encoding: 0x1E624000 | Rn<<5 | Rd
pub fn @"fcvt Sd, Dn"(d: u5, n: u5) u32 {
    return 0x1E624000 | @as(u32, d) | (@as(u32, n) << 5);
}

// FCVT Dd, Sn — convert single to double-precision
// Encoding: 0x1E22C000 | Rn<<5 | Rd
pub fn @"fcvt Dd, Sn"(d: u5, n: u5) u32 {
    return 0x1E22C000 | @as(u32, d) | (@as(u32, n) << 5);
}

// --- Sized memory access instructions for struct fields ---

// STRB Wt, [Xn, #imm] — 8-bit store, unsigned byte offset (0..4095)
pub fn strb_imm(rt: u5, rn: u5, offset: u12) u32 {
    return 0x39000000 | (@as(u32, offset) << 10) | (@as(u32, rn) << 5) | @as(u32, rt);
}

// STRH Wt, [Xn, #imm] — 16-bit store, unsigned byte offset (must be multiple of 2)
pub fn strh_imm(rt: u5, rn: u5, offset_bytes: u12) u32 {
    const scaled: u32 = @as(u32, offset_bytes) >> 1;
    return 0x79000000 | (scaled << 10) | (@as(u32, rn) << 5) | @as(u32, rt);
}

// STR Wt, [Xn, #imm] — 32-bit store, unsigned byte offset (must be multiple of 4)
pub fn str_w_imm(rt: u5, rn: u5, offset_bytes: u12) u32 {
    const scaled: u32 = @as(u32, offset_bytes) >> 2;
    return 0xB9000000 | (scaled << 10) | (@as(u32, rn) << 5) | @as(u32, rt);
}

// STR Xt, [Xn, #imm] — 64-bit store, unsigned byte offset (must be multiple of 8)
pub fn str_x_imm(rt: u5, rn: u5, offset_bytes: u12) u32 {
    const scaled: u32 = @as(u32, offset_bytes) >> 3;
    return 0xF9000000 | (scaled << 10) | (@as(u32, rn) << 5) | @as(u32, rt);
}

// STR St, [Xn, #imm] — float32 store, unsigned byte offset (must be multiple of 4)
pub fn str_s_imm(rt: u5, rn: u5, offset_bytes: u12) u32 {
    const scaled: u32 = @as(u32, offset_bytes) >> 2;
    return 0xBD000000 | (scaled << 10) | (@as(u32, rn) << 5) | @as(u32, rt);
}

// STR Dt, [Xn, #imm] — float64 store, unsigned byte offset (must be multiple of 8)
pub fn str_d_imm(rt: u5, rn: u5, offset_bytes: u12) u32 {
    const scaled: u32 = @as(u32, offset_bytes) >> 3;
    return 0xFD000000 | (scaled << 10) | (@as(u32, rn) << 5) | @as(u32, rt);
}

// LDRB Wt, [Xn, #imm] — 8-bit load, unsigned byte offset (0..4095)
pub fn ldrb_imm(rt: u5, rn: u5, offset: u12) u32 {
    return 0x39400000 | (@as(u32, offset) << 10) | (@as(u32, rn) << 5) | @as(u32, rt);
}

// LDRH Wt, [Xn, #imm] — 16-bit load, unsigned byte offset (must be multiple of 2)
pub fn ldrh_imm(rt: u5, rn: u5, offset_bytes: u12) u32 {
    const scaled: u32 = @as(u32, offset_bytes) >> 1;
    return 0x79400000 | (scaled << 10) | (@as(u32, rn) << 5) | @as(u32, rt);
}

// LDR Wt, [Xn, #imm] — 32-bit load, unsigned byte offset (must be multiple of 4)
pub fn ldr_w_imm(rt: u5, rn: u5, offset_bytes: u12) u32 {
    const scaled: u32 = @as(u32, offset_bytes) >> 2;
    return 0xB9400000 | (scaled << 10) | (@as(u32, rn) << 5) | @as(u32, rt);
}

// LDR Xt, [Xn, #imm] — 64-bit load, unsigned byte offset (must be multiple of 8)
pub fn ldr_x_imm(rt: u5, rn: u5, offset_bytes: u12) u32 {
    const scaled: u32 = @as(u32, offset_bytes) >> 3;
    return 0xF9400000 | (scaled << 10) | (@as(u32, rn) << 5) | @as(u32, rt);
}

// LDR St, [Xn, #imm] — float32 load, unsigned byte offset (must be multiple of 4)
pub fn ldr_s_imm(rt: u5, rn: u5, offset_bytes: u12) u32 {
    const scaled: u32 = @as(u32, offset_bytes) >> 2;
    return 0xBD400000 | (scaled << 10) | (@as(u32, rn) << 5) | @as(u32, rt);
}

// LDR Dt, [Xn, #imm] — float64 load, unsigned byte offset (must be multiple of 8)
pub fn ldr_d_imm(rt: u5, rn: u5, offset_bytes: u12) u32 {
    const scaled: u32 = @as(u32, offset_bytes) >> 3;
    return 0xFD400000 | (scaled << 10) | (@as(u32, rn) << 5) | @as(u32, rt);
}

// --- Helpers for callback trampolines ---

/// MOVZ Xd, #imm16, LSL #shift — load 16-bit immediate, zero others
pub fn movz(rd: u5, imm16: u16, shift: u6) u32 {
    const hw: u32 = @as(u32, shift) >> 4; // 0,16,32,48 → 0,1,2,3
    return 0xd2800000 | (hw << 21) | (@as(u32, imm16) << 5) | @as(u32, rd);
}

/// MOVK Xd, #imm16, LSL #shift — keep other bits, insert 16-bit immediate
pub fn movk(rd: u5, imm16: u16, shift: u6) u32 {
    const hw: u32 = @as(u32, shift) >> 4;
    return 0xf2800000 | (hw << 21) | (@as(u32, imm16) << 5) | @as(u32, rd);
}

/// Emit a 4-instruction sequence to load a 64-bit immediate into Xd
pub fn movImm64(rd: u5, val: u64) [4]u32 {
    return .{
        movz(rd, @truncate(val), 0),
        movk(rd, @truncate(val >> 16), 16),
        movk(rd, @truncate(val >> 32), 32),
        movk(rd, @truncate(val >> 48), 48),
    };
}
