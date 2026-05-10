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
            comptime skipper: anytype,
        ) !Traversal.Iterator(traversal, Data, skipper) {
            return try Traversal.traverse(arena, Data, traversal, self, skipper);
        }

        pub const default_skipper = Traversal.Skipper(Data, void){
            .record = {},
            .skip = dont_skip,
        };

        pub fn dont_skip(
            self: Traversal.Skipper(Data, void),
            node: *const Self,
            index: usize,
            neighbors: Neighbors,
        ) bool {
            _ = self;
            _ = node;
            _ = index;
            _ = neighbors;
            return false;
        }
    };
}

pub fn TreeNode(comptime Data: type) type {
    return struct {
        const Self = Node(Data);

        pub fn init(arena: mem.Allocator, data: Data, parent_node: ?*Self) !Self {
            const neighbors = Self.Neighbors.init(arena);
            var node = Self{
                .data = data,
                .neighbors = neighbors,
            };

            try node.neighbors.append(parent_node orelse self: {
                const n = try arena.create(Self);
                n.* = node;
                break :self n;
            });

            return node;
        }

        pub fn traverse(
            self: *Self,
            arena: mem.Allocator,
            comptime traversal: Traversal.Method,
        ) !Traversal.Iterator(traversal, Data, parent_skipper) {
            return try Traversal.traverse(arena, Data, traversal, self, parent_skipper);
        }

        pub const parent_skipper = Traversal.Skipper(Data, void){
            .record = {},
            .skip = skipParent,
        };

        pub fn skipParent(
            self: Traversal.Skipper(Data, void),
            node: *const Self,
            index: usize,
            neighbors: Self.Neighbors,
        ) bool {
            _ = self;
            _ = node;
            _ = neighbors;
            return index == 0;
        }

        pub fn parent(self: *const Self) ?*const Self {
            const p = self.neighbors.items[0];
            return if (p == self) null else p;
        }

        pub fn previousSibling(self: *const Self) ?*Self {
            return getSibling(self, -1);
        }

        pub fn nextSibling(self: *const Self) ?*Self {
            return getSibling(self, 1);
        }

        pub fn children(self: *const Self) Children {
            return .{ .neighbors = self.neighbors };
        }

        pub fn getSibling(self: *const Self, offset: isize) ?*Self {
            return if (parent(self)) |p| sibling: {
                const node_position: isize = for (p.neighbors.items, 0..) |child, i| {
                    if (child == self) break @bitCast(i);
                } else break :sibling null;

                const sibling_position = node_position + offset;
                const is_within_range = sibling_position > 0 and sibling_position < p.neighbors.items.len;
                break :sibling if (is_within_range) p.neighbors.items[@bitCast(sibling_position)] else null;
            } else null;
        }

        pub const Children = struct {
            neighbors: Self.Neighbors,
            current_index: usize = 1,

            pub fn next(self: *Children) ?*Self {
                if (self.current_index == self.neighbors.items.len) return null;
                const node = self.neighbors.items[self.current_index];
                self.current_index += 1;
                return node;
            }
        };
    };
}

test TreeNode {
    const N = TreeNode(u8);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var node = try N.init(allocator, 0, null);
    var left = try N.init(allocator, 1, &node);
    try node.neighbors.append(&left);
    var center = try N.init(allocator, 2, &node);
    try node.neighbors.append(&center);
    var right = try N.init(allocator, 3, &node);
    try node.neighbors.append(&right);
    var left_of_left = try N.init(allocator, 4, &node);
    try left.neighbors.append(&left_of_left);

    try testing.expectEqual(&left, N.previousSibling(&center));
    try testing.expectEqual(&right, N.nextSibling(&center));

    var it = try N.traverse(&node, allocator, .level_order);
    for ([_]u8{ 0, 1, 2, 3 }) |expected| {
        const actual = try it.next();
        try testing.expect(actual != null);
        try testing.expectEqual(expected, actual.?.data);
    }
}

pub const Traversal = struct {
    pub const Method = enum(u8) {
        level_order,
        post_order,
        pre_order,
        _,
    };

    pub fn traverse(
        arena: mem.Allocator,
        comptime Data: type,
        comptime traversal: Traversal.Method,
        node: *Node(Data),
        comptime skipper: anytype,
    ) !Iterator(traversal, Data, skipper) {
        const N = Node(Data);
        var nodes = ArrayList(*const N).init(arena);
        try nodes.append(node);

        return switch (traversal) {
            .level_order => Iterator(traversal, Data, skipper){ .nodes = nodes },
            .post_order => Iterator(traversal, Data, skipper){
                .nodes = nodes,
                .processed = .init(arena),
            },
            .pre_order => Iterator(traversal, Data, skipper){ .nodes = nodes },
            _ => unreachable,
        };
    }

    pub fn SkipperRecord(skipper: anytype) type {
        return @typeInfo(@TypeOf(skipper)).@"struct".fields[0].type;
    }

    pub fn Iterator(
        comptime traversal: Traversal.Method,
        Data: type,
        comptime skipper: anytype,
    ) type {
        const N = Node(Data);
        const SR = SkipperRecord(skipper);
        const sk: Skipper(Data, SR) = skipper;

        // Iterator for level-order traversal.
        const LevelOrderTraversal = struct {
            const It = @This();

            nodes: ArrayList(*const N),

            pub fn next(self: *It) !?*const N {
                if (self.nodes.items.len == 0) return null;
                const head = self.nodes.orderedRemove(0);

                var i: usize = 0;
                for (head.neighbors.items) |neighbor| {
                    if (!sk.skip(sk, head, i, head.neighbors)) try self.nodes.append(neighbor);
                    i += 1;
                }

                return head;
            }
        };

        // Iterator for post-order traversal.
        const PostOrderTraversal = struct {
            const It = @This();

            nodes: ArrayList(*const N),
            processed: std.AutoHashMap(*const N, *const N),

            pub fn next(self: *It) !?*const N {
                if (self.nodes.items.len == 0) return null;
                const head = self.nodes.getLast();
                if (self.processed.get(head)) |_| return self.nodes.pop().?;
                var it = mem.reverseIterator(head.neighbors.items);
                var i: usize = 0;
                while (it.next()) |n| : (i += 1) {
                    if (!sk.skip(sk, n, i, head.neighbors)) try self.nodes.append(n);
                }
                try self.processed.put(head, head);
                return self.next();
            }
        };

        // Iterator for pre-order traversal.
        const PreOrderTraversal = struct {
            const It = @This();

            nodes: ArrayList(*const N),

            pub fn next(self: *It) !?*const N {
                if (self.nodes.items.len == 0) return null;
                const head = self.nodes.pop().?;

                var it = mem.reverseIterator(head.neighbors.items);
                var i: usize = 0;
                while (it.next()) |n| : (i += 1) {
                    if (!sk.skip(sk, n, i, head.neighbors)) try self.nodes.append(n);
                }

                return head;
            }
        };

        return switch (traversal) {
            .level_order => LevelOrderTraversal,
            .post_order => PostOrderTraversal,
            .pre_order => PreOrderTraversal,
            _ => unreachable,
        };
    }

    pub fn Skipper(Data: type, Record: type) type {
        const N = Node(Data);

        return struct {
            const Skip = @This();

            record: Record,
            skip: *const fn (self: Skip, node: *const N, index: usize, neighbors: N.Neighbors) bool,
        };
    }
};

test "Traversal" {
    const expectations = [_]struct { Traversal.Method, []const u8 }{
        .{ .level_order, &.{ 0, 1, 2, 3 } },
        .{ .post_order, &.{ 3, 1, 2, 0 } },
        .{ .pre_order, &.{ 0, 1, 3, 2 } },
    };

    inline for (expectations) |expectation| try testTraverse(expectation.@"0", expectation.@"1");
}

fn testTraverse(comptime method: Traversal.Method, expectations: []const u8) !void {
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

    const skipper = N.default_skipper;
    var it = try node.traverse(allocator, method, skipper);
    for (expectations) |expected| {
        const actual = try it.next();
        try testing.expect(actual != null);
        try testing.expectEqual(expected, actual.?.data);
    }
}
