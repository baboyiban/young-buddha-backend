const std = @import("std");
const handler = @import("handler.zig");

pub fn start(allocator: std.mem.Allocator, address: std.net.Address) !void {
    var listener = try std.net.Address.listen(address, .{});
    defer listener.deinit();

    std.log.info("server Listening on http://127.0.0.1:{d}", .{address.getPort()});

    while (true) {
        const conn = try listener.accept();

        handler.handleConnection(allocator, conn) catch |err| {
            std.log.err("failed to handle connection: {s}", .{@errorName(err)});
        };
    }
}
