const std = @import("std");
const tracy = @import("tracy");

var finalise_threads = std.atomic.Atomic(bool).init(false);

fn handleSigInt(_: c_int) callconv(.C) void {
    finalise_threads.store(true, .Release);
}

pub fn main() !void {
    tracy.setThreadName("Main");
    defer tracy.message("Graceful main thread exit");

    try std.os.sigaction(std.os.SIG.INT, &.{
        .handler = .{ .handler = handleSigInt },
        .mask = std.os.empty_sigset,
        .flags = 0,
    }, null);

    const other_thread = try std.Thread.spawn(.{}, otherThread, .{});
    defer other_thread.join();

    while (!finalise_threads.load(.Acquire)) {
        tracy.frameMark();

        const zone = tracy.initZone(@src(), .{ .name = "Important work" });
        defer zone.deinit();
        std.time.sleep(100);
    }
}

fn otherThread() void {
    tracy.setThreadName("Other");
    defer tracy.message("Graceful other thread exit");

    var os_allocator = tracy.TracingAllocator.init(std.heap.page_allocator);

    var arena = std.heap.ArenaAllocator.init(os_allocator.allocator());
    defer arena.deinit();

    var tracing_allocator = tracy.TracingAllocator.initNamed("arena", arena.allocator());

    var stack = std.ArrayList(u8).init(tracing_allocator.allocator());
    defer stack.deinit();

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    while (!finalise_threads.load(.Acquire)) {
        const zone = tracy.initZone(@src(), .{ .name = "IO loop" });
        defer zone.deinit();

        stdout.print("Enter string: ", .{}) catch unreachable;

        const stream_zone = tracy.initZone(@src(), .{ .name = "Writer.streamUntilDelimiter" });
        stdin.streamUntilDelimiter(stack.writer(), '\n', null) catch unreachable;
        stream_zone.deinit();

        const toowned_zone = tracy.initZone(@src(), .{ .name = "ArrayList.toOwnedSlice" });
        var str = stack.toOwnedSlice() catch unreachable;
        defer tracing_allocator.allocator().free(str);
        toowned_zone.deinit();

        const reverse_zone = tracy.initZone(@src(), .{ .name = "std.mem.reverse" });
        std.mem.reverse(u8, str);
        reverse_zone.deinit();

        stdout.print("Reversed: {s}\n", .{str}) catch unreachable;
    }
}
