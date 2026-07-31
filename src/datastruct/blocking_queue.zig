//! Blocking queue implementation aimed primarily for message passing
//! between threads.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Returns a blocking queue implementation for type T.
///
/// This is tailor made for ghostty usage so it isn't meant to be maximally
/// generic, but I'm happy to make it more generic over time. Traits of this
/// queue that are specific to our usage:
///
///   - Fixed size. We expect our queue to quickly drain and also not be
///     too large so we prefer a fixed size queue for now.
///   - No blocking pop. We use an external event loop mechanism such as
///     eventfd to notify our waiter that there is no data available so
///     we don't need to implement a blocking pop.
///   - Drain function. Most queues usually pop one at a time. We have
///     a mechanism for draining since on every IO loop our TTY drains
///     the full queue so we can get rid of the overhead of a ton of
///     locks and bounds checking and do a one-time drain.
///
/// One key usage pattern is that our blocking queues are single producer
/// single consumer (SPSC). The mutex is only used for the blocking case
/// (when the queue is full and the producer needs to wait); the fast path
/// (instant timeout) is lock-free for SPSC scenarios.
pub fn BlockingQueue(
    comptime T: type,
    comptime capacity: usize,
) type {
    return struct {
        const Self = @This();

        // The type we use for queue size types. We can optimize this
        // in the future to be the correct bit-size for our preallocated
        // size for this queue.
        pub const Size = u32;

        // The bounds of this queue. We recast this to Size so we can do math.
        const bounds: Size = @intCast(capacity);

        /// Specifies the timeout for an operation.
        pub const Timeout = union(enum) {
            /// Fail instantly (non-blocking).
            instant: void,

            /// Run forever or until interrupted
            forever: void,

            /// Nanoseconds
            ns: u64,
        };

        /// Our data. The values are undefined until they are written.
        data: [bounds]T = undefined,

        /// The next location to write (next empty loc) and next location
        /// to read (next non-empty loc). The number of written elements.
        ///
        /// In the SPSC case, write and read are only modified by one thread
        /// each, so we can use relaxed atomics for the fast non-blocking path.
        /// We use a counter-based approach where positions wrap via modulo.
        write: std.atomic.Value(usize) = .init(0),
        read: std.atomic.Value(usize) = .init(0),

        /// A CV for being notified when the queue is no longer full. This is
        /// used for writing. Note we DON'T have a CV for waiting on the
        /// queue not being EMPTY because we use external notifiers for that.
        /// Only used in the slow blocking path; the fast path is lock-free.
        mutex: std.Thread.Mutex = .{},
        cond_not_full: std.Thread.Condition = .{},
        not_full_waiters: usize = 0,

        /// Allocate the blocking queue on the heap.
        pub fn create(alloc: Allocator) Allocator.Error!*Self {
            const ptr = try alloc.create(Self);
            errdefer alloc.destroy(ptr);

            ptr.* = .{
                .data = undefined,
                .write = .init(0),
                .read = .init(0),
                .mutex = .{},
                .cond_not_full = .{},
                .not_full_waiters = 0,
            };

            return ptr;
        }

        /// Free all the resources for this queue. This should only be
        /// called once all producers and consumers have quit.
        pub fn destroy(self: *Self, alloc: Allocator) void {
            self.* = undefined;
            alloc.destroy(self);
        }

        /// Returns the current number of items in the queue.
        fn len(self: *Self) usize {
            const w = self.write.load(.monotonic);
            const r = self.read.load(.monotonic);
            if (w >= r) return w - r;
            // Handle counter wrap-around: write and read can wrap around
            // after reaching max usize. We use a simple approach where
            // we detect the wrap and add half the max counter value.
            const wrap: usize = @as(u64, 1) << 63;
            if (w + wrap >= r) return w + wrap - r;
            return w - r + wrap;
        }

        /// Returns true if the queue is full.
        fn full(self: *Self) bool {
            return self.len() >= bounds;
        }

        /// Push a value to the queue. This returns the total size of the
        /// queue (unread items) after the push. A return value of zero
        /// means that the push failed.
        pub fn push(self: *Self, value: T, timeout: Timeout) Size {
            // Fast path: check if queue is not full using atomics
            const cur_write = self.write.load(.monotonic);
            const cur_len: usize = self.len();
            if (cur_len >= bounds) {
                // Queue is full, need to handle blocking
                switch (timeout) {
                    .instant => return 0,
                    .forever => {
                        self.mutex.lock();
                        defer self.mutex.unlock();
                        self.not_full_waiters += 1;
                        defer self.not_full_waiters -= 1;
                        self.cond_not_full.wait(&self.mutex);
                    },
                    .ns => |ns| {
                        self.mutex.lock();
                        defer self.mutex.unlock();
                        self.not_full_waiters += 1;
                        defer self.not_full_waiters -= 1;
                        self.cond_not_full.timedWait(&self.mutex, ns) catch return 0;
                    },
                }

                // If we're still full, then we failed to write. This can
                // happen in situations where we are interrupted.
                if (self.full()) return 0;
            }

            // Add our data and update write position
            // In SPSC, only the producer writes to this position
            const write_pos = cur_write % bounds;
            self.data[write_pos] = value;
            self.write.store(cur_write +% 1, .monotonic);

            return @intCast(cur_len +% 1);
        }

        /// Pop a value from the queue without blocking.
        pub fn pop(self: *Self) ?T {
            // Fast path: check if queue is empty using atomics
            const cur_read = self.read.load(.monotonic);
            const cur_len: usize = self.len();
            if (cur_len == 0) return null;

            // Get the index we're going to read data from
            const read_pos = cur_read % bounds;
            const val = self.data[read_pos];

            // Update read position
            self.read.store(cur_read +% 1, .monotonic);

            return val;
        }

        /// Pop all values from the queue. This avoids many locks, bounds
        /// checks, and cv signals by doing a single pass over the queue.
        pub fn drain(self: *Self) DrainIterator {
            return .{ .queue = self };
        }

        pub const DrainIterator = struct {
            queue: *Self,

            pub fn next(self: *DrainIterator) ?T {
                const cur_read = self.queue.read.load(.monotonic);
                const cur_len: usize = self.queue.len();
                if (cur_len == 0) return null;

                const read_pos = cur_read % bounds;
                const val = self.queue.data[read_pos];

                self.queue.read.store(cur_read +% 1, .monotonic);

                return val;
            }
        };
    };
}

test "basic push and pop" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const Q = BlockingQueue(u64, 4);
    const q = try Q.create(alloc);
    defer q.destroy(alloc);

    // Should have no values
    try testing.expect(q.pop() == null);

    // Push until we're full
    try testing.expectEqual(@as(Q.Size, 1), q.push(1, .{ .instant = {} }));
    try testing.expectEqual(@as(Q.Size, 2), q.push(2, .{ .instant = {} }));
    try testing.expectEqual(@as(Q.Size, 3), q.push(3, .{ .instant = {} }));
    try testing.expectEqual(@as(Q.Size, 4), q.push(4, .{ .instant = {} }));
    try testing.expectEqual(@as(Q.Size, 0), q.push(5, .{ .instant = {} }));

    // Pop!
    try testing.expect(q.pop().? == 1);
    try testing.expect(q.pop().? == 2);
    try testing.expect(q.pop().? == 3);
    try testing.expect(q.pop().? == 4);
    try testing.expect(q.pop() == null);

    // Drain does nothing
    var it = q.drain();
    try testing.expect(it.next() == null);

    // Verify we can still push
    try testing.expectEqual(@as(Q.Size, 1), q.push(1, .{ .instant = {} }));
}

test "timed push" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const Q = BlockingQueue(u64, 1);
    const q = try Q.create(alloc);
    defer q.destroy(alloc);

    // Push
    try testing.expectEqual(@as(Q.Size, 1), q.push(1, .{ .instant = {} }));
    try testing.expectEqual(@as(Q.Size, 0), q.push(2, .{ .instant = {} }));

    // Timed push should fail
    try testing.expectEqual(@as(Q.Size, 0), q.push(2, .{ .ns = 1000 }));
}
