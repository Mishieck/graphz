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
            self: *Self,
            arena: mem.Allocator,
            comptime traversal: Traversal.Method,
        ) !Traversal.Iterator(traversal, Self, getNeighbors) {
            return try Traversal.traverse(arena, Self, traversal, self, getNeighbors);
        }

        pub fn getNeighbors(self: *const Self) Neighbors {
            return self.neighbors;
        }
    };
}
pub fn TreeNode(comptime Data: type) type {
    return struct {
        const Self = @This();
        pub const Children = ArrayList(*Self);

        data: Data,
        parent: ?*Self,
        children: Children,

        pub fn traverse(
            self: *Self,
            arena: mem.Allocator,
            comptime traversal: Traversal.Method,
        ) !Traversal.Iterator(traversal, Self, getChildren) {
            return try Traversal.traverse(arena, Self, traversal, self, getChildren);
        }

        pub fn getChildren(self: *const Self) Children {
            return self.children;
        }

        pub fn previousSibling(self: *const Self) ?*Self {
            return self.getSibling(-1);
        }

        pub fn nextSibling(self: *const Self) ?*Self {
            return self.getSibling(1);
        }

        pub fn getSibling(self: *const Self, offset: isize) ?*Self {
            return if (self.parent) |parent| sibling: {
                const node_position: isize = for (parent.children.items, 0..) |child, i| {
                    if (child == self) break @bitCast(i);
                } else break :sibling null;

                const sibling_position = node_position + offset;
                const is_within_range = sibling_position >= 0 and sibling_position < parent.children.items.len;
                break :sibling if (is_within_range) parent.children.items[@bitCast(sibling_position)] else null;
            } else null;
        }
    };
}

test TreeNode {
    const N = TreeNode(u8);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var node = N{ .data = 0, .parent = null, .children = .init(allocator) };
    var left = N{ .data = 1, .parent = &node, .children = .init(allocator) };
    try node.children.append(&left);
    var center = N{ .data = 1, .parent = &node, .children = .init(allocator) };
    try node.children.append(&center);
    var right = N{ .data = 2, .parent = &node, .children = .init(allocator) };
    try node.children.append(&right);

    try testing.expectEqual(&left, center.previousSibling());
    try testing.expectEqual(&right, center.nextSibling());
}

pub const Traversal = struct {
    pub const Method = enum(u8) {
        breadth_first,
        depth_first,
        _,
    };

    pub fn NeighborGetter(comptime N: type) type {
        return fn (node: *const N) ArrayList(*N);
    }

    pub fn traverse(
        arena: mem.Allocator,
        comptime N: type,
        comptime traversal: Traversal.Method,
        node: *N,
        comptime getNeighbors: *const NeighborGetter(N),
    ) !Iterator(traversal, N, getNeighbors) {
        var nodes = ArrayList(*const N).init(arena);
        try nodes.append(node);

        return switch (traversal) {
            .breadth_first => Iterator(traversal, N, getNeighbors){ .nodes = nodes },
            .depth_first => Iterator(traversal, N, getNeighbors){
                .nodes = nodes,
                .processed = .init(arena),
            },
            _ => unreachable,
        };
    }

    pub fn Iterator(
        comptime traversal: Traversal.Method,
        N: type,
        comptime getNeighbors: *const NeighborGetter(N),
    ) type {
        const BreadthFirstTraversal = struct {
            const It = @This();

            nodes: ArrayList(*const N),

            pub fn next(self: *It) !?*const N {
                if (self.nodes.items.len == 0) return null;
                const head = self.nodes.orderedRemove(0);
                try self.nodes.appendSlice(getNeighbors(head).items);
                return head;
            }
        };

        const DepthFirstTraversal = struct {
            const It = @This();

            nodes: ArrayList(*const N),
            processed: std.AutoHashMap(*const N, *const N),

            pub fn next(self: *It) !?*const N {
                if (self.nodes.items.len == 0) return null;
                const head = self.nodes.getLast();
                if (self.processed.get(head)) |_| return self.nodes.pop().?;
                var it = mem.reverseIterator(getNeighbors(head).items);
                while (it.next()) |n| try self.nodes.append(n);
                try self.processed.put(head, head);
                return self.next();
            }
        };

        return switch (traversal) {
            .breadth_first => BreadthFirstTraversal,
            .depth_first => DepthFirstTraversal,
            _ => unreachable,
        };
    }
};

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
