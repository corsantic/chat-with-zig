const std = @import("std");
const net = std.net;
const posix = std.posix;
const Allocator = std.mem.Allocator;
const Reader = @import("reader.zig").Reader;

pub const Client = struct {
    reader: Reader,
    socket: posix.socket_t,
    address: net.Address,

    pub fn init(allocator: Allocator, socket: posix.socket_t, address: net.Address) !Client {
        const reader = try Reader.init(allocator, 4096);
        errdefer reader.deinit(allocator);

        return .{
            .socket = socket,
            .address = address,
            .reader = reader,
        };
    }
    pub fn deinit(self: *const Client, allocator: Allocator) void {
        self.reader.deinit(allocator);
    }

    pub fn readMessage(self: *Client) !?[]const u8 {
        return self.reader.readMessage(self.socket) catch |err| switch (err) {
            error.WouldBlock => return null,
            else => return err,
        };
    }
};
