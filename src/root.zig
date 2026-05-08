const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const ArrayList = std.array_list.Managed;

pub const Edge = [2]usize;

pub fn Graph(comptime Data: type) type {
    return struct {
        const Self = @This();
        pub const Nodes = ArrayList(Data);
        pub const Edges = ArrayList(Edge);

        nodes: Nodes,
        edges: Edges,
    };
}

pub fn Node(comptime Data: type) type {
    return struct {
        const Self = @This();
        pub const Neighbors = ArrayList(*Self);

        data: Data,
        neighbors: Neighbors,

        pub fn traverse(
            self: *const Self,
            arena: mem.Allocator,
            comptime traversal: Traversal,
        ) !Iterator(traversal) {
            var nodes = ArrayList(*const Self).init(arena);
            try nodes.append(self);

            return switch (traversal) {
                .breadth_first => BreadthFirstTraversal{ .nodes = nodes },
                .depth_first => DepthFirstTraversal{ .nodes = nodes, .processed = .init(arena) },
                _ => unreachable,
            };
        }

        pub const Traversal = enum(u8) {
            breadth_first,
            depth_first,
            _,
        };

        pub fn Iterator(comptime traversal: Traversal) type {
            return switch (traversal) {
                .breadth_first => BreadthFirstTraversal,
                .depth_first => DepthFirstTraversal,
                _ => unreachable,
            };
        }

        pub const BreadthFirstTraversal = struct {
            const It = @This();

            nodes: ArrayList(*const Self),

            pub fn next(self: *It) !?*const Self {
                if (self.nodes.items.len == 0) return null;
                const head = self.nodes.orderedRemove(0);
                try self.nodes.appendSlice(head.neighbors.items);
                return head;
            }
        };

        pub const DepthFirstTraversal = struct {
            const It = @This();

            nodes: ArrayList(*const Self),
            processed: std.AutoHashMap(*const Self, *const Self),

            pub fn next(self: *It) !?*const Self {
                if (self.nodes.items.len == 0) return null;
                const head = self.nodes.getLast();
                if (self.processed.get(head)) |_| return self.nodes.pop().?;
                var it = mem.reverseIterator(head.neighbors.items);
                while (it.next()) |n| try self.nodes.append(n);
                try self.processed.put(head, head);
                return self.next();
            }
        };
    };
}

test "Traversal" {
    const N = Node(u8);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var node = N{ .data = 0, .neighbors = .init(allocator) };
    var left = N{ .data = 1, .neighbors = .init(allocator) };
    try node.neighbors.append(&left);
    var right = N{ .data = 2, .neighbors = .init(allocator) };
    try node.neighbors.append(&right);
    var left_of_left = N{ .data = 3, .neighbors = .init(allocator) };
    try left.neighbors.append(&left_of_left);

    var bf = try node.traverse(allocator, .breadth_first);
    for ([_]u8{ 0, 1, 2, 3 }) |i| {
        const item = try bf.next();
        try testing.expect(item != null);
        try testing.expectEqual(i, item.?.data);
    }

    var df = try node.traverse(allocator, .depth_first);
    for ([_]u8{ 3, 1, 2, 0 }) |i| {
        const item = try df.next();
        try testing.expect(item != null);
        try testing.expectEqual(i, item.?.data);
    }
}
