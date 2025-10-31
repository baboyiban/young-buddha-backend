const std = @import("std");
const server = @import("server.zig");
const db = @import("db.zig");
const redis = @import("redis.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // DB 파일 경로 (개발용)
    const db_path = "data/dev.db";

    // 디렉토리 만들기 (없는 경우)
    std.fs.cwd().makeDir("data") catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
        // 디렉토리가 이미 존재하면 무시
    };

    // DB 열기 (sqlite 파일이 없으면 생성)
    const db_handle = try db.open(db_path);
    defer db.close(db_handle);

    try db.execFile(db_handle, allocator, "migrations/0001_init.sql");

    // Redis 연결
    var redis_client = try redis.RedisClient.init(allocator, "127.0.0.1", 6379);
    defer redis_client.deinit();

    // Redis 연결 테스트
    const is_connected = try redis_client.ping();
    if (is_connected) {
        std.debug.print("redis connected successfully!\n", .{});

        // 테스트 데이터 저장/조회
        try redis_client.set("test_key", "hello redis from zig!");
        if (try redis_client.get("test_key")) |value| {
            std.debug.print("Retreved value: {s}\n", .{value});
        }
    } else {
        std.debug.print("Redis connection failed\n", .{});
    }

    const address = try std.net.Address.parseIp("127.0.0.1", 8080);
    try server.start(allocator, address);
}
