const std = @import("std");
const app = @import("../app.zig");

pub fn handleConnection(ctx: *app.AppCtx, conn: std.net.Server.Connection) !void {
    _ = ctx;
    defer conn.stream.close();

    var read_buf: [4096]u8 = undefined;
    var write_buf: [4096]u8 = undefined;

    var net_reader = std.net.Stream.reader(conn.stream, &read_buf);
    var net_writer = std.net.Stream.writer(conn.stream, &write_buf);

    const in_iface: *std.Io.Reader = std.net.Stream.Reader.interface(&net_reader);
    const out_iface: *std.Io.Writer = &net_writer.interface;

    var server = std.http.Server.init(in_iface, out_iface);

    while (true) {
        var req = server.receiveHead() catch |err| {
            std.log.err("Failed to receive request head: {s}", .{@errorName(err)});
            break;
        };

        // TODO: 여기에서 req 정보를 보고 간단한 라우팅을 붙일 수 있습니다.
        try req.respond("Hello from Young Buddha!", .{});
    }
}
