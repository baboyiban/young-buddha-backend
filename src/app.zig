const std = @import("std");
const db = @import("db/connection.zig");
const redis = @import("redis/client.zig");

pub const AppCtx = struct {
    allocator: std.mem.Allocator,
    db: *db.sqlite3,
    redis: *redis.RedisClient,
};
