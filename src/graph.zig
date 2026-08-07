const std = @import("std");
const mem = std.mem;
const debug = std.debug;
const testing = std.testing;
const ArrayList = std.array_list.Managed;

const iteratorz = @import("iteratorz");
const Traversal = @import("traversal.zig").Traversal;

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
        pub const Iterator = iteratorz.iterator.ReadableIterator(Self, T.State).This;

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

        pub inline fn traverse(self: *Self, arena: mem.Allocator, traversal: T.Method) !Iterator {
            var it = try traverseInterface(self.interface, arena, traversal);
            return it.to(
                iteratorz.map.Readable(iteratorz.iterator.Iterator(*Interface, T.State), toNode),
            ).*;
        }

        pub fn traverseInterface(
            interface: *Interface,
            arena: mem.Allocator,
            traversal: T.Method,
        ) !T.Iterator.This {
            const skipper = try interface.skipper.init(arena);
            const t = try traversal.traverse(arena, interface, skipper);
            return t;
        }

        pub fn toNode(interface: *Interface) !Self {
            return .init(interface);
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
            while (try it.next()) |node| try vector.append(node.interface);
            return Graph(Data).fromVector(arena, vector);
        }

        pub const Default = struct {
            interface: Interface,

            pub inline fn init(d: Data, ns: Interface.List) Default {
                return .{
                    .interface = .{
                        .data = d,
                        .neighbors = ns,
                        .skipper = T.Skipper.Default.value,
                        .fromData = fromData,
                    },
                };
            }

            pub fn fromData(arena: mem.Allocator, d: Data) !*Interface {
                const node = try arena.create(Default);
                node.* = .init(d, .init(arena));
                return &node.interface;
            }
        };

        pub const Interface = struct {
            pub const List = ArrayList(*Interface);

            data: Data,
            neighbors: List,
            skipper: T.Skipper,
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
