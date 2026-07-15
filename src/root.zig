const std = @import("std");
const mem = std.mem;
const debug = std.debug;
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

        pub fn fromVector(gpa: mem.Allocator, vector: Vector(Data)) !Self {
            const N = Node(Data);
            var nodes = Nodes.init(gpa);
            var edges = Edges.init(gpa);

            for (vector.items, 0..) |node, i| {
                try nodes.append(node.data);
                var neighbors = node.neighbors;
                defer neighbors.deinit();

                for (neighbors.items) |neighbor| {
                    try edges.append(.{ i, mem.indexOf(*N.Interface, vector.items, &.{neighbor}).? });
                }
            }

            return .{ .nodes = nodes, .edges = edges };
        }

        pub fn toVector(self: *const Self, arena: mem.Allocator, N: type) !Vector(Data) {
            var vector = Vector(Data).init(arena);
            for (self.nodes.items) |data| try vector.append(try N.fromData(arena, data));

            for (self.edges.items) |edge| {
                const i, const j = edge;
                const from = vector.items[i];
                const to = vector.items[j];
                try from.neighbors.append(to);
            }

            return vector;
        }
    };
}

test Graph {
    const G = Graph(u8);
    const N = Node(u8);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var nodes = G.Nodes.init(testing.allocator);
    defer nodes.deinit();
    try nodes.appendSlice(&.{ 0, 1, 2, 3, 4, 5, 6 });

    var edges = G.Edges.init(testing.allocator);
    defer edges.deinit();
    try edges.appendSlice(&.{
        .{ 0, 1 },
        .{ 0, 2 },
        .{ 1, 3 },
        .{ 1, 4 },
        .{ 2, 5 },
        .{ 2, 6 },
    });

    var graph = G{ .nodes = nodes, .edges = edges };
    const vector = try graph.toVector(arena.allocator(), N.Default);
    defer vector.deinit();

    graph = try G.fromVector(testing.allocator, vector);
    defer graph.nodes.deinit();
    defer graph.edges.deinit();

    try testing.expectEqual(nodes.items.len, graph.nodes.items.len);
    try testing.expectEqualSlices(u8, nodes.items, graph.nodes.items);

    try testing.expectEqual(edges.items.len, graph.edges.items.len);
    for (edges.items, 0..) |edge, i| try testing.expectEqualSlices(
        usize,
        &edge,
        &graph.edges.items[i],
    );
}

pub fn Vector(Data: type) type {
    return ArrayList(*Node(Data).Interface);
}

pub fn Node(comptime Data: type) type {
    return struct {
        const Self = @This();
        pub const Neighbors = ArrayList(*Self);

        interface: *Interface,

        pub fn init(interface: *Interface) Self {
            return .{ .interface = interface };
        }

        pub inline fn default(arena: mem.Allocator, d: Data) Self {
            return .init(@constCast(&Default.init(d, .init(arena)).interface));
        }

        pub fn data(self: *const Self) Data {
            return self.interface.data;
        }

        /// Gets a list of neighbors. Caller owns the memory. Free using `deinitNeighbors`.
        pub fn neighbors(self: *const Self, gpa: mem.Allocator) !Neighbors {
            var ns = Neighbors.init(gpa);
            for (self.interface.neighbors.items) |neighbor| {
                const n = try gpa.create(Self);
                n.* = .init(neighbor);
                try ns.append(n);
            }
            return ns;
        }

        /// Frees memory allocated to `Neighbors`;
        pub fn deinitNeighbors(gpa: mem.Allocator, ns: *Neighbors) void {
            for (ns.items) |n| gpa.destroy(n);
            ns.deinit();
        }

        pub fn traverse(self: *Self, arena: mem.Allocator, traversal: T.Method) !T.Iterator {
            return self.interface.traverse(self.interface, arena, traversal);
        }

        const T = Traversal(Data);

        pub fn fromGraph(arena: mem.Allocator, graph: Graph(Data)) !Self {
            const vector = try graph.toVector(arena, Default);
            return .init(vector.items[0]);
        }

        pub fn toGraph(self: *Self, arena: mem.Allocator) !Graph(Data) {
            var vector = Vector(Data).init(arena);
            defer vector.deinit();
            var it = try self.traverse(arena, .level_order);
            while (try it.next()) |node| try vector.append(node);
            return Graph(Data).fromVector(arena, vector);
        }

        pub const Default = struct {
            interface: Interface,

            pub inline fn init(d: Data, ns: Interface.List) Default {
                return .{
                    .interface = .{
                        .data = d,
                        .neighbors = ns,
                        .traverse = traverseDefault,
                        .fromData = fromData,
                    },
                };
            }

            pub fn fromData(arena: mem.Allocator, d: Data) !*Interface {
                const node = try arena.create(Default);
                node.* = .init(d, .init(arena));
                return &node.interface;
            }

            pub fn traverseDefault(
                node: *Interface,
                arena: mem.Allocator,
                traversal: T.Method,
            ) !T.Iterator {
                const skipper = try arena.create(T.Skipper.Default);
                var nodes = try arena.create(Interface.List);
                nodes.* = .init(arena);
                try nodes.append(node);
                skipper.* = .init(nodes);
                return traversal.traverse(arena, node, &skipper.interface);
            }
        };

        pub const Interface = struct {
            pub const List = ArrayList(*Interface);

            data: Data,
            neighbors: List,
            traverse: *const fn (
                node: *Interface,
                arena: mem.Allocator,
                traversal: T.Method,
            ) anyerror!T.Iterator,
            fromData: *const fn (arena: mem.Allocator, data: Data) anyerror!*Interface,
        };
    };
}

test Node {
    const G = Graph(u8);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var nodes = G.Nodes.init(testing.allocator);
    defer nodes.deinit();
    try nodes.appendSlice(&.{ 0, 1, 2, 3, 4, 5, 6 });

    var edges = G.Edges.init(testing.allocator);
    defer edges.deinit();
    try edges.appendSlice(&.{
        .{ 0, 1 },
        .{ 0, 2 },
        .{ 1, 3 },
        .{ 1, 4 },
        .{ 2, 5 },
        .{ 2, 6 },
    });

    var graph = G{ .nodes = nodes, .edges = edges };

    const N = Node(u8);
    var node = try N.fromGraph(arena.allocator(), graph);
    graph = try node.toGraph(arena.allocator());

    try testing.expectEqual(nodes.items.len, graph.nodes.items.len);
    try testing.expectEqualSlices(u8, nodes.items, graph.nodes.items);

    try testing.expectEqual(edges.items.len, graph.edges.items.len);
    for (edges.items, 0..) |edge, i| try testing.expectEqualSlices(
        usize,
        &edge,
        &graph.edges.items[i],
    );
}

pub fn TreeNode(comptime Data: type) type {
    return struct {
        const Self = @This();
        const Interface = Node(Data).Interface;
        const T = Traversal(Data);
        const Children = ArrayList(*Self);

        interface: Interface,

        pub fn init(arena: mem.Allocator, node_data: Data, parent_node: ?*Self) !Self {
            const neighbors = Interface.List.init(arena);
            var node = Self{
                .interface = .{
                    .data = node_data,
                    .neighbors = neighbors,
                    .traverse = traverse,
                    .fromData = fromData,
                },
            };

            try node.interface.neighbors.append(if (parent_node) |p| &p.interface else self: {
                const n = try arena.create(Self);
                n.* = node;
                break :self &n.interface;
            });

            return node;
        }

        pub fn data(self: *const Self) Data {
            return self.interface.data;
        }

        pub fn traverse(
            interface: *Interface,
            arena: mem.Allocator,
            traversal: T.Method,
        ) !T.Iterator {
            var nodes = try arena.create(Interface.List);
            nodes.* = .init(arena);
            try nodes.append(interface);
            var skipper = try arena.create(Skipper);
            skipper.* = .init(nodes);
            return try traversal.traverse(arena, interface, &skipper.interface);
        }

        pub const Skipper = struct {
            interface: T.Skipper.Interface,

            pub fn init(nodes: *Interface.List) Skipper {
                return .{ .interface = .{ .skip = skipParent, .nodes = nodes } };
            }

            pub fn skipParent(
                self: *T.Skipper.Interface,
                node: *const Interface,
                index: usize,
                neighbors: Interface.List,
            ) bool {
                _ = self;
                _ = node;
                _ = neighbors;
                return index == 0;
            }
        };

        pub fn fromData(arena: mem.Allocator, node_data: Data) !*Interface {
            const self = try arena.create(Self);
            self.* = try .init(arena, node_data, null);
            return &self.interface;
        }

        pub fn fromInterface(interface: *Interface) *Self {
            const self: *Self = @fieldParentPtr("interface", interface);
            return self;
        }

        pub fn parent(self: *const Self) ?*Self {
            const p = self.interface.neighbors.items[0];
            return if (p == &self.interface) null else .fromInterface(p);
        }

        pub fn previousSibling(self: *const Self) ?*Self {
            return getSibling(self, -1);
        }

        pub fn nextSibling(self: *const Self) ?*Self {
            return getSibling(self, 1);
        }

        /// Caller owns the memory.
        pub fn children(self: *const Self, gpa: mem.Allocator) !Children {
            var c = Children.init(gpa);
            for (self.interface.neighbors.items[1..]) |i| try c.append(.fromInterface(i));
            return c;
        }

        pub fn getSibling(self: *const Self, offset: isize) ?*Self {
            return if (parent(self)) |p| sibling: {
                const node_position: isize = for (p.interface.neighbors.items, 0..) |child, i| {
                    if (child == &self.interface) break @bitCast(i);
                } else break :sibling null;

                const sibling_position = node_position + offset;
                const neighbor_count = p.interface.neighbors.items.len;
                const is_within_range = sibling_position > 0 and sibling_position < neighbor_count;
                break :sibling if (is_within_range) Self.fromInterface(
                    p.interface.neighbors.items[@bitCast(sibling_position)],
                ) else null;
            } else null;
        }
    };
}

test TreeNode {
    const N = TreeNode(u8);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var node = try N.init(allocator, 0, null);
    var left = try N.init(allocator, 1, &node);
    try node.interface.neighbors.append(&left.interface);
    var center = try N.init(allocator, 2, &node);
    try node.interface.neighbors.append(&center.interface);
    var right = try N.init(allocator, 3, &node);
    try node.interface.neighbors.append(&right.interface);
    var left_of_left = try N.init(allocator, 4, &node);
    try left.interface.neighbors.append(&left_of_left.interface);

    try testing.expectEqual(&left.interface, &N.previousSibling(&center).?.interface);
    try testing.expectEqual(&right.interface, &N.nextSibling(&center).?.interface);

    var it = try N.traverse(&node.interface, allocator, .level_order);
    for ([_]u8{ 0, 1, 2, 3 }) |expected| {
        const actual = try it.next();
        try testing.expect(actual != null);
        try testing.expectEqual(expected, actual.?.data);
    }
}

pub fn Traversal(Data: type) type {
    const N = Node(Data);
    const NI = N.Interface;

    return struct {
        pub const Method = enum(u8) {
            level_order,
            post_order,
            pre_order,
            _,

            pub fn traverse(
                self: *const Method,
                arena: mem.Allocator,
                node: *NI,
                skipper: *Skipper.Interface,
            ) !Iterator {
                var nodes = Vector(Data).init(arena);
                try nodes.append(node);

                return switch (self.*) {
                    .level_order => traverseInfer(arena, LevelOrderTraversal.init(skipper)),
                    .post_order => traverseInfer(
                        arena,
                        PostOrderTraversal.init(skipper, .init(arena)),
                    ),
                    .pre_order => traverseInfer(arena, PreOrderTraversal.init(skipper)),
                    _ => unreachable,
                };
            }

            pub fn traverseInfer(arena: mem.Allocator, traversal: anytype) !Iterator {
                const it = try arena.create(@TypeOf(traversal));
                it.* = traversal;
                return .init(&it.interface);
            }

            // Iterator for level-order traversal.
            const LevelOrderTraversal = struct {
                const It = @This();

                interface: Iterator.Interface,

                pub fn init(skipper: *Skipper.Interface) It {
                    return .{
                        .interface = .{ .next = next, .skipper = .init(skipper) },
                    };
                }

                pub fn next(iterator: *Iterator.Interface) !?*NI {
                    const self: *It = @fieldParentPtr("interface", iterator);
                    var nodes = iterator.skipper.interface.nodes;
                    if (nodes.items.len == 0) return null;
                    const head = nodes.orderedRemove(0);

                    var i: usize = 0;
                    for (head.neighbors.items) |neighbor| {
                        const skip = self.interface.skipper.skip(head, i, head.neighbors);
                        if (!skip) try nodes.append(neighbor);
                        i += 1;
                    }

                    return head;
                }
            };

            // Iterator for post-order traversal.
            const PostOrderTraversal = struct {
                const It = @This();
                const Processed = std.AutoHashMap(*const NI, *const NI);

                interface: Iterator.Interface,
                processed: Processed,

                pub fn init(skipper: *Skipper.Interface, processed: Processed) It {
                    return .{
                        .interface = .{ .next = next, .skipper = .init(skipper) },
                        .processed = processed,
                    };
                }

                pub fn next(iterator: *Iterator.Interface) !?*NI {
                    const self: *It = @fieldParentPtr("interface", iterator);
                    var nodes = iterator.skipper.interface.nodes;
                    if (nodes.items.len == 0) return null;
                    const head = nodes.getLast();
                    if (self.processed.get(head)) |_| return nodes.pop().?;
                    var it = mem.reverseIterator(head.neighbors.items);
                    var i: usize = 0;
                    while (it.next()) |n| : (i += 1) {
                        const skip = iterator.skipper.skip(n, i, head.neighbors);
                        if (!skip) try nodes.append(n);
                    }
                    try self.processed.put(head, head);
                    return iterator.next(iterator);
                }
            };

            // Iterator for pre-order traversal.
            const PreOrderTraversal = struct {
                const It = @This();

                interface: Iterator.Interface,

                pub fn init(skipper: *Skipper.Interface) It {
                    return .{ .interface = .{ .next = next, .skipper = .init(skipper) } };
                }

                pub fn next(iterator: *Iterator.Interface) !?*NI {
                    var nodes = iterator.skipper.interface.nodes;
                    if (nodes.items.len == 0) return null;
                    const head = nodes.pop().?;

                    var it = mem.reverseIterator(head.neighbors.items);
                    var i: usize = 0;
                    while (it.next()) |n| : (i += 1) {
                        const skip = iterator.skipper.skip(n, i, head.neighbors);
                        if (!skip) try nodes.append(n);
                    }

                    return head;
                }
            };
        };

        pub const Iterator = struct {
            interface: *Interface,

            pub fn init(interface: *Interface) Iterator {
                return .{ .interface = interface };
            }

            pub fn next(self: *Iterator) anyerror!?*NI {
                return self.interface.next(self.interface);
            }

            pub const Interface = struct {
                next: *const fn (*Interface) anyerror!?*NI,
                skipper: Skipper,
            };
        };

        pub const Skipper = struct {
            interface: *Interface,

            pub fn init(skipper: *Interface) Skipper {
                return .{ .interface = skipper };
            }

            pub fn skip(
                self: *Skipper,
                node: *const NI,
                index: usize,
                neighbors: NI.List,
            ) bool {
                return self.interface.skip(self.interface, node, index, neighbors);
            }

            pub const Interface = struct {
                skip: *const fn (
                    self: *Interface,
                    node: *const NI,
                    index: usize,
                    neighbors: NI.List,
                ) bool,
                nodes: *NI.List,
            };

            pub const Default = struct {
                const Skip = @This();

                interface: Interface,

                pub fn init(nodes: *NI.List) Default {
                    return .{ .interface = .{ .skip = dontSkip, .nodes = nodes } };
                }

                pub fn dontSkip(
                    skipper: *Interface,
                    node: *const NI,
                    index: usize,
                    neighbors: NI.List,
                ) bool {
                    _ = skipper;
                    _ = node;
                    _ = index;
                    _ = neighbors;
                    return false;
                }
            };
        };
    };
}

test "Traversal" {
    const expectations = [_]struct { Traversal(u8).Method, []const u8 }{
        .{ .level_order, &.{ 0, 1, 2, 3 } },
        .{ .post_order, &.{ 3, 1, 2, 0 } },
        .{ .pre_order, &.{ 0, 1, 3, 2 } },
    };

    inline for (expectations) |expectation| try testTraverse(expectation.@"0", expectation.@"1");
}

fn testTraverse(comptime method: Traversal(u8).Method, expectations: []const u8) !void {
    const N = Node(u8);
    const Default = N.Default;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var root = Default.init(0, .init(allocator));
    var left = Default.init(1, .init(allocator));
    try root.interface.neighbors.append(&left.interface);
    var right = Default.init(2, .init(allocator));
    try root.interface.neighbors.append(&right.interface);
    var left_of_left = Default.init(3, .init(allocator));
    try left.interface.neighbors.append(&left_of_left.interface);

    var node = N.init(&root.interface);
    var it = try node.traverse(allocator, method);
    for (expectations) |expected| {
        if (try it.next()) |actual| {
            try testing.expectEqual(expected, actual.data);
        } else return error.IsNull;
    }
}
