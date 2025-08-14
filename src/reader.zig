const std = @import("std");
const posix = std.posix;
const net = std.net;
const Allocator = std.mem.Allocator;

// @source : https://www.openmymind.net/TCP-Server-In-Zig-Part-3-Minimizing-Writes-and-Reads/
pub const Reader = struct {
    // This is what we will read into and where we will look for a complete message
    buf: []u8,

    // This is where in buf that we are read up to, any subsequent reads need
    // to start from here
    pos: usize = 0,

    // This is where our next message starts at
    start: usize = 0,

    pub fn init(allocator: Allocator, size: usize) !Reader {
        return .{
            .pos = 0,
            .start = 0,
            .buf = try allocator.alloc(u8, size),
        };
    }

    pub fn deinit(self: *const Reader, allocator: Allocator) void {
        allocator.free(self.buf);
    }

    pub fn readMessage(self: *Reader, socket: posix.socket_t) ![]u8 {
        var buf = self.buf;

        // Loop until we have read a message, or the connection was closed
        while (true) {
            // Check if we already have a message in our buffer
            if (try self.bufferedMessage()) |msg| {
                return msg;
            }

            // read data from the socket, we need to read this into buf from
            // the end of where we have data (aka, self.pos)
            const pos = self.pos;
            const n = try posix.read(socket, buf[pos..]);
            if (n == 0) {
                return error.Closed;
            }
            self.pos = pos + n;
        }
    }

    // Checks if there's a full message in self.buf already.
    // If there isn't, checks that we have enough spare space in self.buf for
    // the next message.

    fn bufferedMessage(self: *Reader) !?[]u8 {
        const buf = self.buf;

        // position up to where we have valid data
        const pos = self.pos;

        // position where the next message start
        const start = self.start;

        // pos - start represents bytes that we've read from the socket
        // but that we haven't yet returned as a "message" - possibly because
        // its incomplete.'

        std.debug.assert(pos >= start);

        const unprocessed = buf[start..pos];

        if (unprocessed.len < 4) {
            // We always need at least 4 bytes of data (the length prefix)
            self.ensureSpace(4 - unprocessed.len) catch unreachable;
            return null;
        }
        // The length of the message
        const message_len = std.mem.readInt(u32, unprocessed[0..4], .little);

        // the length of our message + the length of our prefix
        const total_len = message_len + 4;

        if (unprocessed.len < total_len) {
            // We know the length of the message, but we don't have all the
            // bytes yet.
            try self.ensureSpace(total_len);
            return null;
        }
        // Position start at the start of the next message. We might not have
        // any data for this next message, but we know that it'll start where
        // our last message ended
        self.start += total_len;
        return unprocessed[4..total_len];
    }

    // We want to make sure we have enough spare space in our buffer. This can
    // mean two things:
    //   1 - If we know that length of the next message, we need to make sure
    //       that our buffer is large enough for that message. If our buffer
    //       isn't large enough, we return an error (as an alternative, we could
    //       do something else, like dynamically allocate memory or pull a large
    //       buffer from a buffer pool).
    //   2 - At any point that we need to read more data, we need to make sure
    //       that our "spare" space (self.buf.len - self.start) is large enough
    //       for the required data. If it isn't, we need shift our buffer around
    //       and move whatever unprocessed data we have back to the start.

    fn ensureSpace(self: *Reader, space: usize) error{BufferTooSmall}!void {
        const buf = self.buf;

        if (buf.len < space) {
            // Even if we compacted our buffer (moving any unprocessed data back
            // to the start), we wouldn't have enough space for this message in
            // our buffer. Alternatively: dynamically allocate or pull a large
            // buffer from a buffer pool.
            return error.BufferTooSmall;
        }

        const start = self.start;
        const spare = buf.len - start;

        if (spare >= space) {
            // We have enough space nothing to do
            return;
        }

        // At this point, we know that our buffer is larger enough for the data
        // we want to read, but we don't have enough spare space. We need to
        // "compact" our buffer, moving any unprocessed data back to the start
        // of the buffer.
        const unprocessed = buf[start..self.pos];
        std.mem.copyForwards(u8, buf[0..unprocessed.len], unprocessed);
        self.start = 0;
        self.pos = unprocessed.len;
    }
};
