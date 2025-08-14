const std = @import("std");
const posix = std.posix;
const net = std.net;
const builtin = @import("builtin");

pub fn main() !void {
    const address = try net.Address.parseIp4("127.0.0.1", 5882);

    const tpe: u32 = posix.SOCK.STREAM;
    const protocol = posix.IPPROTO.TCP;

    const socket = try posix.socket(address.any.family, tpe, protocol);

    defer posix.close(socket);

    try posix.connect(socket, &address.any, address.getOsSockLen());
    const stdin = std.io.getStdIn().reader();

    while (true) {
        var buf: [1024]u8 = undefined;
        if (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            var text = line;
            if (builtin.os.tag == .windows) {
                text = @constCast(std.mem.trimRight(u8, text, "\r"));
            }
            if (text.len == 0) {
                break;
            }
            try writeMessage(socket, buf[0..text.len]);
        }
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
