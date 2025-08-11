const std = @import("std");

pub fn main() !void {
    const x: u32 = 257;
    
    std.debug.print("system: {any}\n", .{std.mem.asBytes(&x)});
    
    var buf: [4]u8 = undefined;

    std.mem.writeInt(u32, &buf, x, .big);

    std.debug.print("big-endian:    {any}\n", .{&buf});

    std.mem.writeInt(u32, &buf, x, .little);
    std.debug.print("little-endian {any}\n", .{&buf});
}
