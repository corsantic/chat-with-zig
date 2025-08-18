const std = @import("std");
const net = std.net;
const posix = std.posix;
const Allocator = std.mem.Allocator;
const Reader = @import("reader.zig").Reader;

pub const Client = struct {
    reader: Reader,
    socket: posix.socket_t,
    address: net.Address,

    to_write: []u8,
    write_buf: []u8,

    pub fn init(allocator: Allocator, socket: posix.socket_t, address: net.Address) !Client {
        const reader = try Reader.init(allocator, 4096);
        errdefer reader.deinit(allocator);

        const write_buf = try allocator.alloc(u8, 4096);
        errdefer allocator.free(write_buf);

        return .{
            .socket = socket,
            .address = address,
            //
            .reader = reader,
            .to_write = .{},
            .write_buf = write_buf,
        };
    }
    pub fn deinit(self: *const Client, allocator: Allocator) void {
        self.reader.deinit(allocator);
        allocator.free(self.write_buf);
    }

    pub fn readMessage(self: *Client) !?[]const u8 {
        return self.reader.readMessage(self.socket) catch |err| switch (err) {
            error.WouldBlock => return null,
            else => return err,
        };
    }

    pub fn writeMessage(self: *Client, message: []const u8) !void {
        if (self.to_write.len > 0) {
            // Depending on how you structure your code, this might not be possible
            // For example, in an HTTP server, the application might not control
            // the actual "writeMessage" call, and thus it would not be possible
            // to have more than one writeMessage per request
            return error.PendingMessage;
        }

        if (message.len + 4 > self.write_buf.len) {
            // Could allocate a dynamic buffer. Could use a large buffer pool
            return error.MessageTooLarge;
        }
        // copy our length prefix + message to our write buffer
        std.mem.writeInt(u32, self.write_buf[0..4], @intCast(message.len), .little);
        // copy the message to our write buffer
        const end = message.len + 4;
        @memcpy(self.write_buf[4..end], message);

        // setup our to_write slice
        self.to_write = self.write_buf[0..end];

        return self.write();
    }
    // Returns `false` if we didn't manage to write the whole mssage
    // Returns `true` if the message is fully written
    fn write(self: *Client) !bool {
        var buf = self.to_write;
        // when this function exits, we'll store whatever isn't written back into
        // self.to_write. If we wrote everything, than this will be an empty
        // slice (which is what we want)
        defer self.to_write = buf;

        while (buf.len > 0) {
            const n = posix.write(self.socket, buf) catch |err| switch (err) {
                error.WouldBlock => return false,
                else => return err,
            };

            // As long as buf.len > 0, I don't *think* write can ever return 0.
            // But I'm not sure either.
            if (n == 0) {
                return error.Closed;
            }

            // this is what we still have to write
            buf = buf[n..];
        } else {
            return true;
        }
    }
};
