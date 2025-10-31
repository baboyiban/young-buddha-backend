const std = @import("std");
const redis = @import("client.zig");

test "redis client integration: ping / set / get / del" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try redis.RedisClient.init(allocator, "127.0.0.1", 6379);
    defer client.deinit();

    // ping
    const ping_ok = try client.ping();
    try std.testing.expect(ping_ok);

    // set
    try client.set("test_key", "hello-from-zig");

    // get
    const got = try client.get("test_key");
    try std.testing.expect(got != null);

    // 검사하고 할당 해제
    const g = got.?; // []const u8
    try std.testing.expect(std.mem.eql(u8, g, "hello-from-zig"));
    allocator.free(g);

    // del (cleanup)
    const deleted = try client.del("test_key");
    try std.testing.expect(deleted);
}
