const std = @import("std");
const mem = std.mem;
const debug = std.debug;
const testing = std.testing;
const ArrayList = std.array_list.Managed;

const graph = @import("graph.zig");
const Traversal = @import("traversal.zig").Traversal;

pub fn Node(comptime Data: type) type {
    return struct {
        const Self = @This();
        const Interface = graph.Node(Data).Interface;
        const T = Traversal(Data);
        const Children = NodeChildren(Data);

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
        pub fn children(self: *const Self) Children {
            return Children.init(@constCast(&self.interface.neighbors));
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

test Node {
    const N = Node(u8);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var root = try N.init(allocator, 0, null);
    var left = try N.init(allocator, 1, &root);
    try root.interface.neighbors.append(&left.interface);
    var center = try N.init(allocator, 2, &root);
    try root.interface.neighbors.append(&center.interface);
    var right = try N.init(allocator, 3, &root);
    try root.interface.neighbors.append(&right.interface);
    var left_of_left = try N.init(allocator, 4, &root);
    try left.interface.neighbors.append(&left_of_left.interface);

    try testing.expectEqual(&left.interface, &N.previousSibling(&center).?.interface);
    try testing.expectEqual(&right.interface, &N.nextSibling(&center).?.interface);

    var it = try N.traverse(&root.interface, allocator, .level_order);
    for ([_]u8{ 0, 1, 2, 3 }) |expected| {
        const actual = try it.next();
        try testing.expect(actual != null);
        try testing.expectEqual(expected, actual.?.data);
    }

    const children = root.children();
    try testing.expectEqual(3, children.len());
    for ([_]N{ left, center, right }, 0..) |n, i| try testing.expectEqual(
        n.data(),
        children.get(i).data(),
    );
}

pub fn NodeChildren(Data: type) type {
    return struct {
        const Self = @This();
        const TreeNode = Node(Data);
        const Nodes = *graph.Vector(Data);

        nodes: Nodes,

        pub fn init(nodes: Nodes) Self {
            return .{ .nodes = nodes };
        }

        pub fn len(self: *const Self) usize {
            return self.nodes.items.len - 1;
        }

        pub fn get(self: *const Self, index: usize) *TreeNode {
            return @fieldParentPtr("interface", self.nodes.items[index + 1]);
        }

        pub fn set(self: *const Self, index: usize, value: *TreeNode) *TreeNode {
            self.nodes.insert(index + 1, &value.interface);
        }
    };
}
