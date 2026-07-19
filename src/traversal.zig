const std = @import("std");
const mem = std.mem;
const debug = std.debug;
const testing = std.testing;
const ArrayList = std.array_list.Managed;

const graph = @import("graph.zig");

pub fn Traversal(Data: type) type {
    const N = graph.Node(Data);
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
                var nodes = graph.Vector(Data).init(arena);
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
    const N = graph.Node(u8);
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
