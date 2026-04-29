const std = @import("std");
const ArrayList = std.array_list.Managed;

pub const Edge = [2]usize;

pub fn Graph(comptime Data: type) type {
    return struct {
        const Self = @This();

        nodes: ArrayList(Data),
        edges: ArrayList(Edge),
    };
}

pub fn Node(comptime Data: type) type {
    return struct {
        const Self = @This();

        data: Data,
        neighbors: ArrayList(*Self),
    };
}
