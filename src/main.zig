const std = @import("std");
const Reader = @import("reader.zig").Reader;
const Client = @import("client.zig").Client;
const net = std.net;
const posix = std.posix;

pub fn main() !void {
    const address = try net.Address.parseIp4("127.0.0.1", 5882);
    const tpe: u32 = posix.SOCK.STREAM;
    const protocol = posix.IPPROTO.TCP;

    const listener = try posix.socket(address.any.family, tpe, protocol);

    defer posix.close(listener);

    try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    try posix.bind(listener, &address.any, address.getOsSockLen());
    try posix.listen(listener, 128);

    while (true) {
        var client_address: net.Address = undefined;
        var client_address_len: posix.socklen_t = @sizeOf(net.Address);

        const socket = posix.accept(listener, &client_address.any, &client_address_len, 0) catch |err|
            {
                std.debug.print("error accept: {}\n", .{err});
                continue;
            };

        const client = Client{ .socket = socket, .address = client_address };
        const thread = try std.Thread.spawn(.{}, Client.handle, .{client});
        thread.detach();
    }
}


fn readMessage(socket: posix.socket_t, buf: []u8) ![]u8 {
    var header: [4]u8 = undefined;
    try readAll(socket, &header);

    const len = std.mem.readInt(u32, &header, .little);

    if (len > buf.len) {
        return error.BufferTooSmall;
    }

    const msg = buf[0..len];
    try readAll(socket, msg);

    return msg;
}

fn readAll(socket: posix.socket_t, buf: []u8) !void {
    var into = buf;
    while (into.len > 0) {
        const n = try posix.read(socket, into);

        if (n == 0) {
            return error.Closed;
        }
        into = into[n..];
    }
}

fn writeMessage(socket: posix.socket_t, msg: []const u8) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, @intCast(msg.len), .little);

    var vec = [2]posix.iovec_const{
        .{ .len = 4, .base = &buf },
        .{ .len = msg.len, .base = msg.ptr },
    };
    try writeAllVectored(socket, &vec);
}

fn writeAllVectored(socket: posix.socket_t, vec: []posix.iovec_const) !void {
    var i: usize = 0;
    while (true) {
        var n = try posix.writev(socket, vec[i..]);
        while (n >= vec[i].len) {
            n -= vec[i].len;
            i += 1;
            if (i >= vec.len) return;
        }
        vec[i].base += n;
        vec[i].len -= n;
    }
}

fn writeAll(socket: posix.socket_t, msg: []const u8) !void {
    var pos: usize = 0;
    while (pos < msg.len) {
        const written = try posix.write(socket, msg[pos..]);

        if (written == 0) {
            return error.Closed;
        }
        pos += written;
    }
}
