// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

const std = @import("std");
const builtin = @import("builtin");

pub fn main() anyerror!void {
    std.log.info(
        "All your codebase are belong to us.",
        .{},
    );
}

extern "kernel32" fn OutputDebugStringW(std.os.windows.LPCWSTR) callconv(.Stdcall) void;

fn debugOutputFn(context: void, bytes: []const u8) error{InvalidUtf8}!usize {
    var buffer: [8192]u16 = undefined;

    var dest_i: usize = 0;
    var src_i: usize = 0;

    while (src_i < bytes.len) {
        const n = std.unicode.utf8ByteSequenceLength(bytes[src_i]) catch return error.InvalidUtf8;
        const next_src_i = src_i + n;
        const codepoint = std.unicode.utf8Decode(bytes[src_i..next_src_i]) catch return error.InvalidUtf8;
        if (codepoint < 0x10000) {
            const short = @intCast(u16, codepoint);
            if (dest_i == buffer.len - 1) {
                buffer[dest_i] = 0;
                OutputDebugStringW(@ptrCast([*:0]u16, &buffer));
                dest_i = 0;
            }
            buffer[dest_i] = std.mem.nativeToLittle(u16, short);
            dest_i += 1;
        } else {
            const high = @intCast(u16, (codepoint - 0x10000) >> 10) + 0xd800;
            const low = @intCast(u16, codepoint & 0x3ff + 0xDC00);
            if (dest_i == buffer.len - 2) {
                buffer[dest_i] = 0;
                OutputDebugStringW(@ptrCast([*:0]u16, &buffer));
                dest_i = 0;
            }
            buffer[dest_i] = std.mem.nativeToLittle(u16, high);
            buffer[dest_i + 1] = std.mem.nativeToLittle(u16, low);
            dest_i += 2;
        }
        src_i = next_src_i;
    }
    buffer[dest_i] = 0;
    OutputDebugStringW(@ptrCast([*:0]u16, &buffer));
    return src_i;
}

const DebugOutputLogWriter = std.io.Writer(void, error{InvalidUtf8}, debugOutputFn);

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const finalDebugFormatString = @tagName(level) ++
        (if (scope == .default) "" else "(" ++ @tagName(scope) ++ ")") ++
        ": " ++ format;
    if (builtin.os.tag == .windows and builtin.subsystem orelse .Console == .Windows) {
        const debugOutputWriter = DebugOutputLogWriter{ .context = .{} };
        const held = std.debug.getStderrMutex().acquire();
        defer held.release();
        debugOutputWriter.print(finalDebugFormatString ++ "\n", args) catch undefined;
    } else {
        const stderr = std.io.getStdErr().writer();
        const held = std.debug.getStderrMutex().acquire();
        defer held.release();
        try stderr.print(finalDebugFormatString ++ "\n", args) catch undefined;
    }
}
