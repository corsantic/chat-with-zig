const std = @import("std");
const net = std.net;
const posix = std.posix;
const Allocator = std.mem.Allocator;
const Client = @import("client.zig").Client;

const log = std.log.scoped(.server);

pub const Server = struct {
    // Our Client need an allocator to create their read buffer
    allocator: Allocator,

    // The number of clients currently connected
    connected: usize,

    // polls[0] is the listening socket
    polls: []posix.pollfd,

    // list of clients, only client[0..connected] are valid
    clients: []Client,

    // This is always polls[1..] and it's used to so that we can manipulate
    // clients and client_polls together. Necessary because polls[0] is the
    // listening socket, and we don't ever touch that.
    client_polls: []posix.pollfd,

    pub fn init(allocator: Allocator, max: usize) !Server {
        const polls = try allocator.alloc(posix.pollfd, max + 1);
        errdefer allocator.free(polls);

        const clients = try allocator.alloc(Client, max);
        errdefer allocator.free(clients);

        return .{
            .polls = polls,
            .clients = clients,
            .connected = 0,
            .client_polls = polls[1..],
            .allocator = allocator,
        };
    }
    pub fn run(self: *Server, address: net.Address) !void {
        const tpe: u32 = posix.SOCK.STREAM | posix.SOCK.NONBLOCK;
        const protocol = posix.IPPROTO.TCP;

        const listener = try posix.socket(address.any.family, tpe, protocol);

        defer posix.close(listener);

        try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        try posix.bind(listener, &address.any, address.getOsSockLen());
        try posix.listen(listener, 128);

        //Reserved for listening socket
        self.polls[0] = .{ .fd = listener, .events = posix.POLL.IN, .revents = 0 };

        while (true) {
            _ = try posix.poll(self.polls[0 .. self.connected + 1], -1);

            if (self.polls[0].revents != 0) {
                self.accept(listener) catch |err| log.err("failed to accept {}", .{err});
            }

            var i: usize = 0;
            while (i < self.connected) {
                const revents = self.client_polls[i].revents;

                if (revents == 0) {
                    // This socket is not ready, go to the next one
                    i += 1;
                    continue;
                }
                var client = self.clients[i];

                if (revents & posix.POLL.IN == posix.POLL.IN) {
                    while (true) {
                        const msg = client.readMessage() catch {
                            // we don't increment `i` when we remove the client
                            // because removeClient does a swap and puts the last
                            // client at position i
                            self.removeClient(i);
                            break;
                        } orelse {
                            // no more messages, but this client is still connected
                            i += 1;
                            break;
                        };
                        std.debug.print("got: {s}\n", .{msg});

                        const written = client.writeMessage(msg) catch {
                            self.removeClient(i);
                            break;
                        };

                        // If writeMessage didn't fully write the message, we change to
                        // write-mode, asking to be notified of the socket's write-readiness
                        // instead of its read-readiness.
                        if (written == false) {
                            self.client_polls[i].events = posix.POLL.OUT;
                            break;
                        }
                        // else, the entire message was written, we stay in read-mode
                        // and see if the client has another message ready
                    }
                } else if (revents & posix.POLL.OUT == posix.POLL.OUT) {
                    // This whole block is new. This means that socket was previously put
                    // into write-mode and that it is now ready. We write what we can.
                    const written = client.write() catch {
                        self.removeClient(i);
                        continue;
                    };
                    if (written) {
                        // and if the entire message was written, we revert to read-mode.
                        self.client_polls[i].events = posix.POLL.IN;
                    }
                }
            }
        }
    }
    fn accept(self: *Server, listener: posix.socket_t) !void {
        const available = self.client_polls.len - self.connected;
        for (0..available) |_| {
            // we'll continue to accept until we get error.WouldBlock
            // or until our program crashes because we overflow self.clients and self.polls
            // (we really should fix that!)
            var address: net.Address = undefined;
            var address_len: posix.socklen_t = @sizeOf(net.Address);

            const socket = posix.accept(listener, &address.any, &address_len, posix.SOCK.NONBLOCK) catch |err| switch (err) {
                error.WouldBlock => break,
                else => return err,
            };
            const client = Client.init(self.allocator, socket, address) catch |err| {
                posix.close(socket);
                log.err("failed to create client: {}", .{err});
                return;
            };
            const connected = self.connected;
            self.clients[connected] = client;
            self.client_polls[connected] = .{ .fd = socket, .events = posix.POLL.IN, .revents = 0 };
            self.connected = connected + 1;
        } else {
            //polls[0] is _always_ the listening socket
            disableListeningSocket();
        }
    }

    fn removeClient(self: *Server, at: usize) void {
        var client = self.clients[at];
        posix.close(client.socket);
        client.deinit(self.allocator);

        // Swap the client we're removing with the last one
        // So that when we set connected -= 1, it'll effectively "remove"
        // the client from our slices.
        const last_index = self.connected - 1;
        self.clients[at] = self.clients[last_index];
        self.client_polls[at] = self.client_polls[last_index];

        self.connected = last_index;
        enableListeningSocket();
    }
    fn disableListeningSocket(self: *Server) void {
        self.polls[0].events = 0;
    }
    fn enableListeningSocket(self: *Server) void {
        self.polls[0].events = posix.POLL.IN;
    }

    pub fn deinit(self: *Server) void {
        //TODO: Close connected sockets?
        self.allocator.free(self.polls);
        self.allocator.free(self.clients);
    }
};
