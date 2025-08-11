const std = @import("std");
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

    var buf: [128]u8 = undefined;
    while (true) {
        var client_address: net.Address = undefined;
        var client_address_len: posix.socklen_t = @sizeOf(net.Address);

        const socket = posix.accept(listener, &client_address.any, &client_address_len, 0) catch |err|
            {
                std.debug.print("error accept: {}\n", .{err});
                continue;
            };

        defer posix.close(socket);

        std.debug.print("{} connected\n", .{client_address});

        const timeout = posix.timeval{ .sec = 2, .usec = 500_000 };

        //Read timeout
        try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, &std.mem.toBytes(timeout));
        //Write timeout
        try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.SNDTIMEO, &std.mem.toBytes(timeout));

        // code will wait here for client
        const read = try readMessage(socket, &buf);

        try writeMessage(socket, read);
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
    try writeAll(socket, &buf);
    try writeAll(socket, msg);

    // //Delimiter
    // if (try posix.write(socket, &[1]u8{0}) != 1) {
    //     return error.Closed;
    // }
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
