const std = @import("std");
const mem = std.mem;
const debug = std.debug;
const testing = std.testing;
const ArrayList = std.array_list.Managed;

const graph = @import("graph.zig");
const iteratorz = @import("iteratorz");

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
            ) !Iterator.This {
                const nodes = try arena.create(graph.Vector(Data));
                nodes.* = .init(arena);
                try nodes.append(node);

                return switch (self.*) {
                    .level_order => traverseInfer(arena, LevelOrderTraversal.init(skipper, nodes)),
                    .post_order => traverseInfer(
                        arena,
                        PostOrderTraversal.init(skipper, nodes, .init(arena)),
                    ),
                    .pre_order => traverseInfer(arena, PreOrderTraversal.init(skipper, nodes)),
                    _ => unreachable,
                };
            }

            pub fn traverseInfer(arena: mem.Allocator, traversal: anytype) !Iterator.This {
                var t = try arena.create(@TypeOf(traversal));
                t.* = traversal;
                var iterable = try arena.create(Iterable);
                iterable.* = .init(&t.interface);
                var default = try arena.create(Iterator.Default);
                default.* = .init(&iterable.interface);
                return .init(&default.interface);
            }

            // Iterator for level-order traversal.
            const LevelOrderTraversal = struct {
                const It = @This();
                const Interface = Iterable.Getter;

                interface: Interface,
                skipper: Skipper,
                nodes: *NI.List,

                pub fn init(skipper: *Skipper.Interface, nodes: *NI.List) It {
                    return .{
                        .interface = .{ .current = current },
                        .skipper = .init(skipper),
                        .nodes = nodes,
                    };
                }

                pub fn current(getter: *Interface) !?*NI {
                    const self: *It = @fieldParentPtr("interface", getter);
                    var nodes = self.nodes;
                    if (nodes.items.len == 0) return null;
                    const head = nodes.orderedRemove(0);

                    var i: usize = 0;
                    for (head.neighbors.items) |neighbor| {
                        const skip = self.skipper.skip(head, i, head.neighbors);
                        if (!skip) try nodes.append(neighbor);
                        i += 1;
                    }

                    return head;
                }
            };

            // Iterator for post-order traversal.
            const PostOrderTraversal = struct {
                const It = @This();
                const Interface = Iterable.Getter;
                const Processed = std.AutoHashMap(*const NI, *const NI);

                interface: Interface,
                skipper: Skipper,
                nodes: *NI.List,
                processed: Processed,

                pub fn init(skipper: *Skipper.Interface, nodes: *NI.List, processed: Processed) It {
                    return .{
                        .interface = .{ .current = current },
                        .skipper = .init(skipper),
                        .nodes = nodes,
                        .processed = processed,
                    };
                }

                pub fn current(getter: *Interface) !?*NI {
                    const self: *It = @fieldParentPtr("interface", getter);
                    var nodes = self.nodes;
                    if (nodes.items.len == 0) return null;
                    const head = nodes.getLast();
                    if (self.processed.get(head)) |_| return nodes.pop().?;
                    var it = mem.reverseIterator(head.neighbors.items);
                    var i: usize = 0;
                    while (it.next()) |n| : (i += 1) {
                        const skip = self.skipper.skip(n, i, head.neighbors);
                        if (!skip) try nodes.append(n);
                    }
                    try self.processed.put(head, head);
                    return current(getter);
                }
            };

            // Iterator for pre-order traversal.
            const PreOrderTraversal = struct {
                const It = @This();
                const Interface = Iterable.Getter;

                interface: Interface,
                skipper: Skipper,
                nodes: *NI.List,

                pub fn init(skipper: *Skipper.Interface, nodes: *NI.List) It {
                    return .{
                        .interface = .{ .current = current },
                        .skipper = .init(skipper),
                        .nodes = nodes,
                    };
                }

                pub fn current(getter: *Interface) !?*NI {
                    const self: *It = @fieldParentPtr("interface", getter);
                    var nodes = self.nodes;
                    if (nodes.items.len == 0) return null;
                    const head = nodes.pop().?;

                    var it = mem.reverseIterator(head.neighbors.items);
                    var i: usize = 0;
                    while (it.next()) |n| : (i += 1) {
                        const skip = self.skipper.skip(n, i, head.neighbors);
                        if (!skip) try nodes.append(n);
                    }

                    return head;
                }
            };
        };

        pub const Iterator = iteratorz.iterator.Iterator(*NI, void).Readable;

        pub const Iterable = struct {
            const Self = @This();

            pub const Interface = iteratorz.iterable.Iterable(*NI, void).Interface;
            pub const Getter = struct {
                current: *const fn (getter: *Getter) anyerror!?*NI,
            };
            pub const Value = Data;
            pub const StateType = void;

            interface: Interface,
            getter: *Getter,
            current: ?*NI = null,
            set: bool = false,

            pub fn init(getter: *Getter) Self {
                return .{
                    .interface = .{
                        .getValue = getValue,
                        .setValue = setValue,
                        .getState = getState,
                        .setState = setState,
                        .setNextState = setNextState,
                        .setPreviousState = setPreviousState,
                        .setInitialState = setInitialState,
                        .setFinalState = setFinalState,
                        .isStateValid = isStateValid,
                    },
                    .getter = getter,
                };
            }

            pub fn getValue(iterable: *Interface) anyerror!*NI {
                const self: *Self = @fieldParentPtr("interface", iterable);
                return self.current.?;
            }

            pub fn setValue(iterable: *Interface, value: *NI) anyerror!*Interface {
                _ = value;
                return iterable;
            }

            pub fn getState(iterable: *Interface) anyerror!StateType {
                _ = iterable;
                return;
            }

            pub fn setState(iterable: *Interface, state: StateType) anyerror!*Interface {
                _ = state;
                return iterable;
            }

            pub fn setNextState(iterable: *Interface) anyerror!*Interface {
                var self: *Self = @fieldParentPtr("interface", iterable);
                self.current = try self.getter.current(self.getter);
                if (self.current == null) return error.InvalidState;
                return iterable;
            }

            pub fn setPreviousState(iterable: *Interface) anyerror!*Interface {
                return iterable;
            }

            pub fn setInitialState(iterable: *Interface) anyerror!*Interface {
                return iterable;
            }

            pub fn setFinalState(iterable: *Interface) anyerror!*Interface {
                return iterable;
            }

            pub fn isStateValid(iterable: *Interface) anyerror!bool {
                const self: *Self = @fieldParentPtr("interface", iterable);
                if (!self.set) {
                    self.current = try self.getter.current(self.getter);
                    self.set = true;
                }
                return if (self.current) |_| true else false;
            }
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
            };

            pub const Default = struct {
                const Skip = @This();

                interface: Interface,

                pub fn init() Default {
                    return .{ .interface = .{ .skip = dontSkip } };
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
        if (try it.current()) |actual| {
            try testing.expectEqual(expected, actual.data);
        } else return error.IsNull;
    }
}
