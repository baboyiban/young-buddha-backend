const std = @import("std");
const handler = @import("handler/root.zig");
const app = @import("app.zig");

pub fn start(allocator: std.mem.Allocator, address: std.net.Address, ctx: *app.AppCtx) !void {
    _ = allocator; // 현재 사용하지 않음
    var listener = try std.net.Address.listen(address, .{});
    defer listener.deinit();

    std.log.info("server listening on http://127.0.0.1:{d}", .{address.getPort()});

    while (true) {
        const conn = try listener.accept();

        handler.handleConnection(ctx, conn) catch |err| {
            std.log.err("failed to handle connecdtion: {s}", .{@errorName(err)});
        };
    }
}
