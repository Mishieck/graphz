const std = @import("std");
const mem = std.mem;
const debug = std.debug;
const testing = std.testing;
const ArrayList = std.array_list.Managed;

const iteratorz = @import("iteratorz");
const graph = @import("graph.zig");
const Traversal = @import("traversal.zig").Traversal;

pub fn Node(comptime Data: type) type {
    return struct {
        const Self = @This();
        const Interface = graph.Node(Data).Interface;
        const T = Traversal(Data);
        const Parent = NodeParent(Data);
        const Children = NodeChildren(Data);
        const Siblings = NodeSiblings(Data);
        pub const Iterator = iteratorz.iterator.ReadableIterator(*Self, void).This;

        interface: Interface,

        pub fn init(arena: mem.Allocator, node_data: Data, parent_node: ?*Self) !Self {
            const neighbors = Interface.List.init(arena);
            var node = Self{
                .interface = .{
                    .data = node_data,
                    .neighbors = neighbors,
                    .traverse = traverseInterface,
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

        pub fn traverseInterface(
            node: *Interface,
            arena: mem.Allocator,
            traversal: T.Method,
        ) !T.Iterator.This {
            var skipper = try arena.create(Skipper);
            skipper.* = .init();
            return traversal.traverse(arena, node, &skipper.interface);
        }

        pub inline fn traverse(
            self: *Self,
            arena: mem.Allocator,
            traversal: T.Method,
        ) anyerror!Iterator {
            var it = try self.interface.traverse(&self.interface, arena, traversal);
            return it.to(iteratorz.map.Readable(iteratorz.iterator.Iterator(*Interface, void), toTreeNode)).*;
        }

        pub fn toTreeNode(interface: *Interface) !*Self {
            return @fieldParentPtr("interface", interface);
        }

        pub const Skipper = struct {
            interface: T.Skipper.Interface,

            pub fn init() Skipper {
                return .{ .interface = .{ .skip = skipParent } };
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

        pub fn parent(self: *Self) Parent {
            return Parent.init(self);
        }

        pub fn siblings(self: *Self) Siblings {
            return Siblings.init(self);
        }

        pub fn children(self: *Self) Children {
            return Children.init(self);
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

    var it = try root.traverse(arena.allocator(), .level_order);
    for ([_]u8{ 0, 1, 2, 3 }) |expected| {
        const actual = try it.current();
        try testing.expect(actual != null);
        try testing.expectEqual(expected, actual.?.data());
    }
}

pub fn NodeParent(Data: type) type {
    return struct {
        const Self = @This();
        const TreeNode = Node(Data);
        const Neighbors = graph.Vector(Data);

        node: *TreeNode,

        pub fn init(node: *TreeNode) Self {
            return .{ .node = node };
        }

        pub fn get(self: *const Self) ?*TreeNode {
            const first_neighbor = self.node.interface.neighbors.items[0];
            return if (&self.node.interface == first_neighbor) null else @fieldParentPtr(
                "interface",
                first_neighbor,
            );
        }

        pub fn set(self: *Self, new_parent: *TreeNode) !*Self {
            _ = self.node.interface.neighbors.orderedRemove(0);
            try self.node.interface.neighbors.insert(0, &new_parent.interface);
            return self;
        }

        pub fn remove(self: *Self) !*TreeNode {
            const parent = self.node.interface.neighbors.orderedRemove(0);
            try self.node.interface.neighbors.insert(0, &self.node.interface);
            return @fieldParentPtr("interface", parent);
        }
    };
}

test NodeParent {
    const N = Node(u8);

    const gpa = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const aa = arena.allocator();

    var parent = try N.init(aa, 0, null);
    var child = try N.init(aa, 1, &parent);

    var p = child.parent();
    try testing.expectEqual(&parent, p.get());
    _ = try p.remove();
    try testing.expectEqual(null, p.get());
    _ = try p.set(&parent);
    try testing.expectEqual(&parent, p.get());
}

pub fn NodeSiblings(Data: type) type {
    return struct {
        const Self = @This();
        const TreeNode = Node(Data);
        const Neighbors = graph.Vector(Data);

        node: *TreeNode,

        pub fn init(node: *TreeNode) Self {
            return .{ .node = node };
        }

        pub fn previous(self: *const Self) ?*TreeNode {
            return self.sibling(-1);
        }

        pub fn next(self: *const Self) ?*TreeNode {
            return self.sibling(1);
        }

        pub fn sibling(self: *const Self, offset: isize) ?*TreeNode {
            return if (self.node.parent().get()) |parent| has_parent: {
                const children = parent.children();

                const child_count = children.len();
                const index: isize = for (0..child_count) |i| {
                    if (children.get(i) == self.node) break @bitCast(i);
                } else unreachable;

                const sibling_index, const overflow_bit = @addWithOverflow(index, offset);
                break :has_parent switch (overflow_bit) {
                    0 => switch (sibling_index >= 0 and sibling_index < child_count) {
                        true => children.get(@bitCast(sibling_index)),
                        false => null,
                    },
                    1 => null,
                };
            } else null;
        }
    };
}

test NodeSiblings {
    const N = Node(u8);

    const gpa = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const aa = arena.allocator();

    var root = try N.init(aa, 0, null);
    var left = try N.init(aa, 1, &root);
    var center = try N.init(aa, 2, &root);
    var right = try N.init(aa, 3, &root);

    var children = root.children();
    _ = try children.append(@constCast(&left));
    _ = try children.append(@constCast(&center));
    _ = try children.append(@constCast(&right));

    var siblings = center.siblings();
    try testing.expectEqual(&left, siblings.previous());
    try testing.expectEqual(&right, siblings.next());

    var parent = center.parent();
    _ = try parent.remove();
    try testing.expectEqual(null, siblings.previous());
    try testing.expectEqual(null, siblings.next());
}

pub fn NodeChildren(Data: type) type {
    return struct {
        const Self = @This();
        const TreeNode = Node(Data);
        const Neighbors = graph.Vector(Data);
        const List = ArrayList(*TreeNode);

        neighbors: *Neighbors,

        pub fn init(node: *TreeNode) Self {
            return .{ .neighbors = &node.interface.neighbors };
        }

        pub fn get(self: *const Self, index: usize) *TreeNode {
            return @fieldParentPtr("interface", self.neighbors.items[index + 1]);
        }

        pub fn set(self: *Self, index: usize, node: *TreeNode) !*Self {
            _ = self.orderedRemove(index);
            _ = try self.insert(index, node);
            return self;
        }

        pub fn orderedRemove(self: *Self, index: usize) *TreeNode {
            return @fieldParentPtr("interface", self.neighbors.orderedRemove(index + 1));
        }

        pub fn insert(self: *Self, index: usize, node: *TreeNode) !*Self {
            try self.neighbors.insert(index + 1, &node.interface);
            return self;
        }

        pub fn append(self: *Self, node: *TreeNode) !*Self {
            try self.neighbors.append(&node.interface);
            return self;
        }

        pub fn list(self: *const Self, gpa: mem.Allocator) !List {
            var neighbors = List.init(gpa);
            for (0..self.neighbors.items.len - 1) |i| try neighbors.append(self.get(i));
            return neighbors;
        }

        pub fn len(self: *const Self) usize {
            return self.neighbors.items.len - 1;
        }
    };
}

test NodeChildren {
    const N = Node(u8);
    const C = NodeChildren(u8);

    const gpa = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const aa = arena.allocator();

    var root = try N.init(aa, 0, null);
    var left = try N.init(aa, 1, &root);
    var center = try N.init(aa, 2, &root);
    var right = try N.init(aa, 3, &root);

    var children = C.init(&root);
    _ = try children.append(&left);
    _ = try children.append(&right);
    try testing.expectEqual(2, children.len());
    _ = try children.insert(1, &center);
    try testing.expectEqual(3, children.len());

    var list = try children.list(gpa);
    defer list.deinit();
    for (0..3) |i| try testing.expectEqual(i + 1, list.items[i].data());

    _ = try children.set(0, &right);
    _ = try children.set(2, &left);
    var reversed_list = try children.list(gpa);
    defer reversed_list.deinit();
    for ([_]u8{ 3, 2, 1 }, 0..) |data, i| try testing.expectEqual(
        data,
        reversed_list.items[i].data(),
    );
}
