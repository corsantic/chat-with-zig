const std = @import("std");
const Server = @import("server.zig").Server;
const net = std.net;
const posix = std.posix;

const log = std.log.scoped(.main);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var server = try Server.init(allocator, 4096);
    defer server.deinit();

    const address = try net.Address.parseIp("127.0.0.1", 5882);
    try server.run(address);
}
