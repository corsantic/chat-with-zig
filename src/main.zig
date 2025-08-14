const std = @import("std");
const Reader = @import("reader.zig").Reader;
const Client = @import("client.zig").Client;
const net = std.net;
const posix = std.posix;

pub fn main() !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // const allocator = gpa.allocator();

    // var polls: std.Thread.Pool = undefined;
    // try std.Thread.Pool.init(&polls, .{ .allocator = allocator, .n_jobs = 64 });

    const address = try net.Address.parseIp4("127.0.0.1", 5882);
    const tpe: u32 = posix.SOCK.STREAM | posix.SOCK.NONBLOCK;
    const protocol = posix.IPPROTO.TCP;

    const listener = try posix.socket(address.any.family, tpe, protocol);

    defer posix.close(listener);

    try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    try posix.bind(listener, &address.any, address.getOsSockLen());
    try posix.listen(listener, 128);

    // Our server can support 4095 clients. Wait, shouldn't that be 4096? No
    // One of the polling slots (the first one) is reserved for our listening
    // socket.

    var polls: [4096]posix.pollfd = undefined;

    polls[0] = .{ .fd = listener, .events = posix.POLL.IN, .revents = 0 };
    var poll_count: usize = 1;

    while (true) {
        // polls is the total number of connections we can monitor, but
        // polls[0..poll_count] is the actual number of clients + the listening
        // socket that are currently connected
        var active = polls[0..poll_count];

        // 2nd argument is the timeout, -1 is infinity
        _ = try posix.poll(active, -1);

        // Active[0] is _always_ the listening socket. When this socket is ready
        // we can accept. Putting it outside the following while loop means that
        // we don't have to check if if this is the listening socket on each
        // iteration
        //
        if (active[0].revents != 0) {
            // The listening socket is ready, accept!
            // Notice that we pass SOCK.NONBLOCK to accept, placing the new client
            // socket in non-blocking mode. Also, for now, for simplicity,
            // we're not capturing the client address (the two null arguments).
            const socket = try posix.accept(listener, null, null, posix.SOCK.NONBLOCK);

            polls[poll_count] = .{
                .fd = socket,
                // This will be SET by posix.poll to tell us what event is ready
                // (or it will stay 0 if this socket isn't ready)
                .revents = 0,
                // We want to be notified about the POLL.IN event
                // (i.e. can read without blocking)
                .events = posix.POLL.IN,
            };
            // increment the number of active connections we're monitoring
            // this can overflow our 4096 polls array. TODO: fix that!
            poll_count += 1;
        }

        var i: usize = 1;
        while (i < active.len) {
            const polled = active[i];

            const revents = polled.revents;

            if (revents == 0) {
                // This socket is not ready, go to the next one
                i += 1;
                continue;
            }

            var closed = false;

            if (revents & posix.POLL.IN == posix.POLL.IN) {
                var buf: [4096]u8 = undefined;
                const read = posix.read(polled.fd, &buf) catch 0;
                if (read == 0) {
                    // probably closed on the other side
                    closed = true;
                } else {
                    std.debug.print("[{d}] got: {s}\n", .{ polled.fd, buf[0..read] });
                }
            }

            // either the read failed, or we're being notified through poll
            // that the socket is closed
            if (closed or (revents & posix.POLL.HUP == posix.POLL.HUP)) {
                posix.close(polled.fd);
                // We use a simple trick to remove it: we swap it with the last
                // item in our array, then "shrink" our array by 1
                const last_index = active.len - 1;
                active[i] = active[last_index];
                active = active[0..last_index];
                poll_count -= 1;
                // don't increment `i` because we swapped out the removed item
                // and shrank the array
            } else {
                // not closed, go to the next socket
                i += 1;
            }
        }

        // var client_address: net.Address = undefined;
        // var client_address_len: posix.socklen_t = @sizeOf(net.Address);
        //
        // const socket = posix.accept(listener, &client_address.any, &client_address_len, posix.SOCK.NONBLOCK) catch |err|
        //     {
        //         std.debug.print("error accept: {}\n", .{err});
        //         continue;
        //     };
        //
        // const client = Client{ .socket = socket, .address = client_address };
        // try pool.spawn(Client.handle, .{client});
    }
}
