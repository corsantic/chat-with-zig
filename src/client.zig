const std = @import("std");
const net = std.net;
const posix = std.posix;
const Reader = @import("reader.zig").Reader;

pub const Client = struct {
    socket: posix.socket_t,
    address: net.Address,

    pub fn handle(self: Client) void {
        self._handle() catch |err| switch (err) {
            error.Closed => {},
            else => std.debug.print("[{any}] client handle error: {}\n", .{ self.address, err }),
        };
    }

    fn _handle(self: Client) !void {
        const socket = self.socket;

        defer posix.close(socket);
        std.debug.print("{} connected\n", .{self.address});

        const timeout = posix.timeval{ .sec = 2, .usec = 500_000 };

        //Read timeout
        try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, &std.mem.toBytes(timeout));
        //Write timeout
        try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.SNDTIMEO, &std.mem.toBytes(timeout));

        var buf: [1028]u8 = undefined;
        var reader = Reader{ .socket = socket, .buf = &buf, .pos = 0 };

        while (true) {
            const msg = try reader.readMessage();
            std.debug.print("Got: {s}\n", .{msg});
        }
    }
};
